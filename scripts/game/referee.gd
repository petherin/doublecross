extends RefCounted
## The rulebook. Runs on the host (and on each device for its own bots):
## applies searches, traps, doors, escapes, shots and hits to the match
## state held by the game, counts the clocks down and knocks agents out of
## the match. Every outcome goes out as an event through `game.broadcast`.

const World = preload("res://scripts/core/world.gd")
const Agent = preload("res://scripts/game/agent.gd")

var game: Node
var _rng := RandomNumberGenerator.new()
var _clock_sync := 0.0
## Nacho, in match time (seconds): when he gives up on his attacker, and
## when he last bit.
var _now := 0.0
var _foe_until := 0.0
var _last_bite := -100.0


func _init(p_game: Node) -> void:
	game = p_game


## Seeded from the match so a match (and the headless tests) replay the same.
func seed_rng(seed_value: int) -> void:
	_rng.seed = hash(["referee", seed_value])


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
		reason = "You've already got %d game.traps set." % game.MAX_TRAPS
	if reason != "":
		game.broadcast({"type": "trap_fail", "pid": pid, "reason": reason})
		return
	game.traps[key] = {"kind": kind, "owner": pid}
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
		# Nacho can't be hurt, but he won't let it go.
		var att: Agent = game.agent_of(by)
		if not game.over and att and game.dog.owner_id not in [0, by] and att.room == game.dog.room:
			_set_nacho_on(by)
		return
	if game.over or by == target or not game.inventories.has(target) or not game.inventories.has(by):
		return
	var ta: Agent = game.agent_of(target)
	var ba: Agent = game.agent_of(by)
	if ta.ko_time > 0.0 or ta.protect_time > 0.0 or ta.vent >= 0:
		return
	if kind == "melee" and (ta.room != ba.room or ta.position.distance_to(ba.position) > game.MELEE_RANGE * 2.0):
		return
	# Attacking Nacho's agent sets him on you.
	if target == game.dog.owner_id and kind != "bite" and game.dog.room == ba.room:
		_set_nacho_on(by)
	var inv: Dictionary = game.inventories[target]
	inv["hp"] -= 1
	if inv["hp"] > 0:
		game.broadcast({"type": "hit", "pid": target, "by": by, "kind": kind, "from": ba.position})
		return
	# Taken out: drop the intel, lose time, wake up back at the start.
	var lost: Array = inv["items"].duplicate()
	inv["items"].clear()
	for item in lost:
		_hide_somewhere(item, ta.room)
	inv["hp"] = game.MAX_HP
	inv["darts"] = game.MAX_DARTS
	_penalise(target, game.DOWN_PENALTY)
	game.broadcast({"type": "down", "pid": target, "by": by, "kind": kind, "room": ta.room, "lost": lost,
			"from": ba.position})
	_send_nacho_home(target)


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
	var dog: Node = game.dog
	if dog.foe_id == 0 or game.over:
		return
	var foe: Agent = game.agent_of(dog.foe_id)
	if foe == null or foe.out or foe.room != dog.room or dog.owner_id == 0 or _now > _foe_until:
		game.broadcast({"type": "nacho_foe", "pid": 0, "owner": dog.owner_id})
		return
	if dog.position.distance_to(foe.position) < dog.BITE_REACH and _now - _last_bite > dog.BITE_EVERY \
			and foe.ko_time <= 0.0 and foe.protect_time <= 0.0:
		_last_bite = _now
		handle_hit(dog.owner_id, dog.foe_id, "bite")


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
