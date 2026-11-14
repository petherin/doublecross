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


func _init(p_game: Node) -> void:
	game = p_game
	_rng.randomize()


func handle_search(pid: int, room: Vector2i, idx: int) -> void:
	if game.over or not game.inventories.has(pid):
		return
	var key := World.furniture_key(room, idx)
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
	if game.over or by == target or not game.inventories.has(target) or not game.inventories.has(by):
		return
	var ta: Agent = game.agent_of(target)
	var ba: Agent = game.agent_of(by)
	if ta.ko_time > 0.0 or ta.protect_time > 0.0 or ta.vent >= 0:
		return
	if kind == "melee" and (ta.room != ba.room or ta.position.distance_to(ba.position) > game.MELEE_RANGE * 2.0):
		return
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


func _penalise(pid: int, seconds: float) -> void:
	game.clocks[pid] = maxf(1.0, game.clocks[pid] - seconds)
	game.sync_clocks.rpc(game.clocks)


func tick_clocks(delta: float) -> void:
	for id in game.clocks:
		if not game.eliminated.has(id):
			game.clocks[id] -= delta
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
			if game.contents.has(k) or game.traps.has(k):
				continue
			anywhere.append(k)
			if r == room:
				here.append(k)
	var pool := here if not here.is_empty() else anywhere
	if pool.is_empty():
		return
	game.contents[pool[_rng.randi_range(0, pool.size() - 1)]] = item
