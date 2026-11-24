extends RefCounted
## The rulebook. Runs on the host (and on each device for its own bots):
## applies searches, traps, doors, escapes, shots and hits to the match
## state held by the game, counts the clocks down and knocks agents out of
## the match. Every outcome goes out as an event through `game.broadcast`.

const World = preload("res://scripts/core/world.gd")
const Agent = preload("res://scripts/game/agent.gd")
## Chance of Nacho needing (at least) one poo in a match, and after each
## poo, the chance he'll need another later on.
const POO_CHANCE := 0.75
const POO_AGAIN_CHANCE := 0.5
## Thrown bombs: how near the blast you have to be for a direct hit (taken
## out), two hits or one, in floor units (a floor square is 128).
const BLAST_DIRECT := 64.0
const BLAST_NEAR := 192.0
const BLAST_FAR := 320.0

var game: Node
var _rng := RandomNumberGenerator.new()
var _clock_sync := 0.0
## Nacho, in match time (seconds): when he gives up on his attacker, and
## when he last bit.
var _now := 0.0
var _foe_until := 0.0
var _last_bite := -100.0
## Nacho's poo: in three matches out of four, at a random moment (match
## time), and maybe again later. Its own dice, so the rest of the match plays
## out as before.
var _poo_rng := RandomNumberGenerator.new()
var _poo_at := INF
var _poo_end := -1.0
var _poo_spot := {}
## Bombs in the air: {pid, room, pos, at (match time it lands)}.
var _thrown: Array = []


func _init(p_game: Node) -> void:
	game = p_game


## Seeded from the match so a match (and the headless tests) replay the same.
func seed_rng(seed_value: int) -> void:
	_rng.seed = hash(["referee", seed_value])
	_poo_rng.seed = hash(["poo", seed_value])
	if _poo_rng.randf() < POO_CHANCE:
		_poo_at = _poo_rng.randf_range(45.0, 150.0)


func handle_search(pid: int, room: Vector2i, idx: int) -> void:
	if game.over or not game.inventories.has(pid):
		return
	var key := World.furniture_key(room, idx)
	if game.world.is_kennel(room, idx):
		# Nacho's kennel: he's either at home (and now yours) or out.
		game.broadcast({"type": "search", "pid": pid, "key": key, "found": "", "left": "", "disarmed": "",
				"spare": false, "kennel": true, "nacho": game.dog.owner_id == 0})
		return
	var inv: Dictionary = game.inventories[pid]
	var disarmed := ""
	if game.traps.has(key):
		var kind: String = game.traps[key]["kind"]
		var remedy: String = World.TRAPS[kind]
		if inv["gadgets"].has(remedy):
			disarmed = kind
			game.traps.erase(key)
			_use_gadget(pid, remedy)
		else:
			_spring_trap(pid, key, room)
			return
	var found: String = game.contents.get(key, "")
	var left := ""
	var spare := false
	game.contents.erase(key)
	if found in World.GADGETS:
		inv["gadgets"].append(found)
	elif found == World.BRIEFCASE:
		if inv["case"]:
			spare = true   # one's enough: leave it for someone else
			game.contents[key] = found
		else:
			inv["case"] = true
	elif found != "":
		if not inv["case"] and inv["items"].size() >= 1:
			# Hands full, no briefcase: swap what you're holding for what you found.
			left = inv["items"][0]
			inv["items"].erase(left)
			game.contents[key] = left
		inv["items"].append(found)
	game.broadcast({"type": "search", "pid": pid, "key": key, "found": found, "left": left, "disarmed": disarmed,
			"spare": spare})


func handle_trap(pid: int, info: Dictionary) -> void:
	if game.over or not game.inventories.has(pid):
		return
	var key: String = info.get("key", "")
	var kind: String = info.get("kind", "")
	var reason := ""
	if not World.TRAPS.has(kind) or key == "":
		reason = "That trap didn't work."
	elif game.traps.has(key):
		reason = "Something's already rigged here. Best leave it alone…"
	elif key == World.furniture_key(game.world.kennel[0], game.world.kennel[1]):
		reason = "Not in Nacho's kennel!"
	elif game.traps_owned_by(pid) >= game.MAX_TRAPS:
		reason = "You've already got %d traps set." % game.MAX_TRAPS
	elif kind == "BOMB" and game.inventories[pid]["bombs"] <= 0:
		reason = "Out of bombs! You get %d more when you're taken out." % game.MAX_BOMBS
	if reason != "":
		game.broadcast({"type": "trap_fail", "pid": pid, "reason": reason})
		return
	game.traps[key] = {"kind": kind, "owner": pid}
	if kind == "BOMB":
		game.inventories[pid]["bombs"] -= 1   # bomb traps and thrown bombs share the supply
	game.broadcast({"type": "trap_set", "pid": pid, "kind": kind, "key": key})


func handle_door(pid: int, from_room: Vector2i, dir: int) -> void:
	if game.over or not game.inventories.has(pid):
		return
	var key := World.door_key(from_room, dir)
	if not game.traps.has(key):
		return
	var to_room: Vector2i = from_room + World.DIR_VEC[dir]
	var remedy: String = World.TRAPS["WIRE"]
	if game.inventories[pid]["gadgets"].has(remedy):
		game.traps.erase(key)
		_use_gadget(pid, remedy)
		game.broadcast({"type": "disarm", "pid": pid, "kind": "WIRE"})
	else:
		_spring_trap(pid, key, to_room)


func handle_escape(pid: int) -> void:
	if game.over:
		return
	if game.inventories.has(pid) and game.missing_intel(pid).is_empty():
		game.game_over.rpc(pid, "escape")


func handle_fire(pid: int) -> void:
	if game.over or not game.inventories.has(pid):
		return
	game.inventories[pid]["darts"] = maxi(0, game.inventories[pid]["darts"] - 1)
	game.broadcast({"type": "fire", "pid": pid})


func handle_hit(by: int, target: int, kind: String) -> void:
	if target == game.dog.DOG_ID:
		_hit_nacho(by)
		return
	if game.over or by == target or not game.inventories.has(target) or not game.inventories.has(by):
		return
	var ta: Agent = game.agent_of(target)
	var ba: Agent = game.agent_of(by)
	if ta.ko_time > 0.0 or ta.protect_time > 0.0 or ta.vent >= 0:
		return
	if kind == "melee" and (ta.room != ba.room or ta.position.distance_to(ba.position) > game.MELEE_RANGE * 2.0):
		return
	_damage(by, target, 1, kind, ba.position)


## `amount` hits on `target` (from `by`, who was at `from`): a hit, or taken
## out if it's their last. Attacking Nacho's agent sets him on you.
func _damage(by: int, target: int, amount: int, kind: String, from: Vector2) -> void:
	var ta: Agent = game.agent_of(target)
	var ba: Agent = game.agent_of(by)
	if target == game.dog.owner_id and by != target and kind != "bite" and ba and game.dog.room == ba.room:
		_set_nacho_on(by)
	var inv: Dictionary = game.inventories[target]
	inv["hp"] -= amount
	if inv["hp"] > 0:
		game.broadcast({"type": "hit", "pid": target, "by": by, "kind": kind, "from": from})
		return
	# Taken out: drop the intel, lose time, wake up back at the start.
	var lost: Array = inv["items"].duplicate()
	inv["items"].clear()
	for item in lost:
		_hide_somewhere(item, ta.room)
	_refill(inv)
	_penalise(target, game.DOWN_PENALTY)
	game.broadcast({"type": "down", "pid": target, "by": by, "kind": kind, "room": ta.room, "lost": lost,
			"from": from})
	_send_nacho_home(target)


## Back on your feet after being taken out: full health, darts and bombs.
func _refill(inv: Dictionary) -> void:
	inv["hp"] = game.MAX_HP
	inv["darts"] = game.MAX_DARTS
	inv["bombs"] = game.MAX_BOMBS


## Throws a bomb at floor point `to`: it lands THROW_TIME later and blows up.
func handle_throw(pid: int, to: Vector2) -> void:
	var a: Agent = game.agent_of(pid)
	if game.over or a == null or not game.inventories.has(pid) or game.inventories[pid]["bombs"] <= 0:
		return
	if a.ko_time > 0.0 or a.vent >= 0 or a.out:
		return
	game.inventories[pid]["bombs"] -= 1
	var d := to - a.position
	to = a.position + d.limit_length(game.THROW_RANGE)
	to = to.clamp(World.ROOM.position + Vector2(20, 20), World.ROOM.end - Vector2(20, 20))
	_thrown.append({"pid": pid, "room": a.room, "pos": to, "at": _now + game.THROW_TIME})
	game.broadcast({"type": "throw", "pid": pid, "room": a.room, "from": a.position, "to": to})


## Thrown bombs that have landed go off.
func _tick_thrown() -> void:
	var keep := []
	for b in _thrown:
		if _now >= b["at"]:
			_blast(b["pid"], b["room"], b["pos"])
		else:
			keep.append(b)
	_thrown = keep


## A thrown bomb goes off at `pos`: a direct hit takes you out (or Nacho);
## nearer than 1.5 floor squares is two hits, nearer than 2.5 squares one.
## The thrower isn't safe either.
func _blast(by: int, room: Vector2i, pos: Vector2) -> void:
	game.broadcast({"type": "blast", "pid": by, "room": room, "pos": pos})
	for a: Agent in game.agents:
		var id: int = game.id_of(a)
		if a.room != room or a.out or a.vent >= 0 or a.ko_time > 0.0 or a.protect_time > 0.0 \
				or not game.inventories.has(id):
			continue
		var amount := blast_damage(a.position.distance_to(pos))
		if amount > 0:
			_damage(by, id, amount, "blast", pos)
	var dog: Node = game.dog
	if dog.room == room and dog.visible_now() and dog.owner_id not in [0, by]:
		var amount := blast_damage(dog.position.distance_to(pos))
		if amount > 0:
			_hit_nacho(by, amount)


## Hits a blast does at `dist` from where it went off (3: taken out).
static func blast_damage(dist: float) -> int:
	if dist <= BLAST_DIRECT:
		return 3
	if dist <= BLAST_NEAR:
		return 2
	if dist <= BLAST_FAR:
		return 1
	return 0


## Someone hits Nacho: it hurts, he goes for them, and three hits send him
## home to his kennel, nobody's dog any more, for whoever finds him next.
func _hit_nacho(by: int, amount := 1) -> void:
	var att: Agent = game.agent_of(by)
	var dog: Node = game.dog
	if game.over or att == null or dog.owner_id in [0, by] or att.room != dog.room or dog.protect_time > 0.0:
		return
	var hp: int = dog.hp - amount
	if hp > 0:
		_set_nacho_on(by)
		game.broadcast({"type": "nacho_hit", "pid": by, "hp": hp, "room": dog.room})
	else:
		game.broadcast({"type": "nacho_down", "pid": by, "owner": dog.owner_id, "room": dog.room,
				"at": dog.position})


## Points Nacho at someone attacking his agent or him. He keeps at them
## for as long as they keep attacking.
func _set_nacho_on(pid: int) -> void:
	_foe_until = _now + game.dog.FOE_MEMORY
	if game.dog.foe_id != pid:
		game.broadcast({"type": "nacho_foe", "pid": pid, "owner": game.dog.owner_id})


## Host, every frame: Nacho bites his attacker while they're in reach, and
## calls it off once they've stopped attacking (or gone).
func tick_nacho(delta: float) -> void:
	_now += delta
	if game.over:
		return
	_tick_poo()
	_tick_turds()
	var dog: Node = game.dog
	if dog.foe_id == 0:
		return
	var foe: Agent = game.agent_of(dog.foe_id)
	if foe == null or foe.out or foe.room != dog.room or dog.owner_id == 0 or _now > _foe_until:
		game.broadcast({"type": "nacho_foe", "pid": 0, "owner": dog.owner_id})
		return
	if dog.position.distance_to(foe.position) < dog.BITE_REACH and _now - _last_bite > dog.BITE_EVERY \
			and foe.ko_time <= 0.0 and foe.protect_time <= 0.0:
		_last_bite = _now
		handle_hit(dog.owner_id, dog.foe_id, "bite")


## Nacho's poo: starts when it's time and he isn't fighting (or crawling
## through a duct); stops if anyone starts on him or his agent (he'll try
## again later); and leaves a turd when he's done.
func _tick_poo() -> void:
	var dog: Node = game.dog
	if _poo_end >= 0.0:
		if dog.foe_id != 0 or not dog.is_pooing() or dog.room != _poo_spot["room"]:
			# Interrupted (he's gone for someone, or been sent home).
			_poo_end = -1.0
			_poo_at = _now + _poo_rng.randf_range(40.0, 90.0)
			game.broadcast({"type": "nacho_poo", "stage": "stop", "owner": dog.owner_id})
		elif _now >= _poo_end:
			_poo_end = -1.0
			# Maybe another later on.
			if _poo_rng.randf() < POO_AGAIN_CHANCE:
				_poo_at = _now + _poo_rng.randf_range(90.0, 180.0)
			game.broadcast({"type": "nacho_poo", "stage": "done", "owner": dog.owner_id,
					"room": _poo_spot["room"], "pos": _poo_spot["pos"]})
		return
	# Only out with an agent (never at home in his kennel), and not mid-fight.
	if _now < _poo_at or dog.owner_id == 0 or dog.foe_id != 0 or not dog.visible_now() or dog.hurt_time > 0.0:
		return
	_poo_at = INF
	var plan: Array = dog.poo_plan()
	_poo_spot = {"room": dog.room, "pos": plan[2]}
	_poo_end = _now + dog.POO_TIME
	game.broadcast({"type": "nacho_poo", "stage": "start", "owner": dog.owner_id, "room": dog.room,
			"stand": plan[0], "face": plan[1]})


## Starts Nacho's poo now (for tests).
func poo_now() -> void:
	_poo_at = _now


## Anyone who treads in a turd slips, falls and is taken out, and
## everything they were carrying goes flying. The turd's gone with them.
func _tick_turds() -> void:
	if game.turds.is_empty():
		return
	for a: Agent in game.agents:
		if a.out or a.vent >= 0 or a.ko_time > 0.0 or a.protect_time > 0.0:
			continue
		for t in game.turds:
			if t["room"] == a.room and a.position.distance_to(t["pos"]) < game.dog.TURD_RADIUS:
				_slip(game.id_of(a), t)
				break


func _slip(pid: int, turd: Dictionary) -> void:
	if not game.inventories.has(pid):
		return
	var inv: Dictionary = game.inventories[pid]
	var lost: Array = inv["items"].duplicate()
	if inv["case"]:
		lost.append(World.BRIEFCASE)
	lost.append_array(inv["gadgets"])
	inv["items"].clear()
	inv["gadgets"].clear()
	inv["case"] = false
	for item in lost:
		_hide_somewhere(item, turd["room"])
	_refill(inv)
	_penalise(pid, game.DOWN_PENALTY)
	game.broadcast({"type": "down", "pid": pid, "by": 0, "kind": "slip", "room": turd["room"], "lost": lost,
			"from": turd["pos"], "turd": turd["pos"]})
	_send_nacho_home(pid)


## Nacho's agent is out of action: he runs home to his kennel.
func _send_nacho_home(pid: int) -> void:
	if game.dog.owner_id == pid:
		game.broadcast({"type": "nacho_home", "pid": pid})


func _penalise(pid: int, seconds: float) -> void:
	game.clocks[pid] = maxf(1.0, game.clocks[pid] - seconds)
	game.sync_clocks.rpc(game.clocks)


func tick_clocks(delta: float) -> void:
	for id in game.clocks:
		if not game.eliminated.has(id):
			game.clocks[id] -= delta
	tick_nacho(delta)
	_tick_thrown()
	_clock_sync -= delta
	if _clock_sync <= 0.0:
		_clock_sync = 0.5
		game.sync_clocks.rpc(game.clocks)
	for id in game.clocks.keys():
		if game.clocks[id] <= 0.0 and not game.eliminated.has(id) and not game.over:
			eliminate(id, "time")


## Host: takes an agent out of the match (clock ran out, or they left).
## Their intel scatters so the others can still finish. When only one agent
## is left they win; if nobody is, nobody does.
func eliminate(pid: int, reason: String) -> void:
	if game.eliminated.has(pid) or game.agent_of(pid) == null:
		return
	game.eliminated[pid] = true
	var room: Vector2i = game.agent_of(pid).room
	var lost: Array = game.inventories[pid]["items"].duplicate()
	game.inventories[pid]["items"].clear()
	for item in lost:
		_hide_somewhere(item, room)
	game.broadcast({"type": "out", "pid": pid, "reason": reason, "room": room, "lost": lost})
	_send_nacho_home(pid)
	var active := []
	for id in game.agent_ids():
		if not game.eliminated.has(id):
			active.append(id)
	if active.size() <= 1 and not game.over:
		game.game_over.rpc(active[0] if active.size() == 1 else 0, reason)


## The victim is knocked out and the intel they carry flies into the
## furniture around the room.
func _spring_trap(pid: int, key: String, room: Vector2i) -> void:
	var trap: Dictionary = game.traps[key]
	game.traps.erase(key)
	var lost: Array = game.inventories[pid]["items"].duplicate()
	game.inventories[pid]["items"].clear()
	for item in lost:
		_hide_somewhere(item, room)
	_penalise(pid, game.TRAP_PENALTY)
	game.broadcast({"type": "ko", "pid": pid, "kind": trap["kind"], "owner": trap["owner"], "room": room, "lost": lost})


## A gadget is used up, then turns up again somewhere else in the base.
func _use_gadget(pid: int, gadget: String) -> void:
	game.inventories[pid]["gadgets"].erase(gadget)
	_hide_somewhere(gadget, Vector2i(-1, -1))


## Puts `item` in an empty, untrapped piece of furniture, preferring `room`.
func _hide_somewhere(item: String, room: Vector2i) -> void:
	var here := []
	var anywhere := []
	for r in game.world.rooms:
		for i in game.world.furniture(r).size():
			var k := World.furniture_key(r, i)
			if game.contents.has(k) or game.traps.has(k) or game.world.is_kennel(r, i):
				continue
			anywhere.append(k)
			if r == room:
				here.append(k)
	var pool := here if not here.is_empty() else anywhere
	if pool.is_empty():
		return
	game.contents[pool[_rng.randi_range(0, pool.size() - 1)]] = item
