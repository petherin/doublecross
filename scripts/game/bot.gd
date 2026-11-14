extends Node
## A computer-controlled rival for one-player games.
##
## The bot plays by the same rules as a person: it doesn't know where the
## items are until it searches, it can only carry one item until it finds the
## briefcase, and it has to walk to the exit. It remembers what it has
## searched and where it left things.

const World = preload("res://scripts/core/world.gd")
const Agent = preload("res://scripts/game/agent.gd")

const CELL := 40.0
## How each difficulty plays.
##  speed:   fraction of full running speed
##  think:   pause between decisions (seconds), so it feels human
##  memory:  chance it remembers having searched something
##  avoid_own: chance it remembers (and steers clear of) its own traps
##  trap:    chance of setting a trap after a search
##  sneaky:  re-searches a room when it hears a trap go off there (dropped intel)
##  vents:   "none" ignores air-vent shortcuts, "learn" finds them by trying
##           vents it comes across, "all" knows every duct from the start
## Fighting, per difficulty:
##  aggro:  chance it picks a fight when it meets you
##  react:  delay before each attack (seconds)
##  aim:    dart aim error (radians)
##  chase:  how far it will chase you across a room
const FIGHT := {
	"easy": {"aggro": 0.3, "react": [0.7, 1.2], "aim": 0.45, "chase": 250.0},
	"medium": {"aggro": 0.6, "react": [0.35, 0.7], "aim": 0.22, "chase": 450.0},
	"hard": {"aggro": 0.85, "react": [0.15, 0.4], "aim": 0.08, "chase": 700.0},
}

const LEVELS := {
	"easy": {
		"speed": 0.72, "think": [0.7, 1.5], "memory": 0.75, "avoid_own": 0.7,
		"trap": 0.12, "sneaky": false, "vents": "none",
	},
	"medium": {
		"speed": 0.82, "think": [0.4, 1.0], "memory": 1.0, "avoid_own": 1.0,
		"trap": 0.2, "sneaky": false, "vents": "learn",
	},
	"hard": {
		"speed": 0.92, "think": [0.2, 0.6], "memory": 1.0, "avoid_own": 1.0,
		"trap": 0.3, "sneaky": true, "vents": "all",
	},
}

var game: Node
var agent: Agent
var id := 2
var level := "hard"
var _p: Dictionary = LEVELS["hard"]
var _f: Dictionary = FIGHT["hard"]
var _engaged := false
var _met_in := Vector2i(-1, -1)
var _attack_cd := 0.0
var _fight_time := 0.0
var _chase: PackedVector2Array = PackedVector2Array()
var _chase_replan := 0.0

var _grids := {}             # room -> AStarGrid2D
var _searched := {}          # furniture key -> true (looked, nothing useful left)
var _known := {}
var _own_memory := {}        # own trap key -> does it remember this one?
var _vents_known := {}       # vent index -> true once the bot knows where it goes
var _vents_tried := {}             # furniture key -> item the bot knows is there
var _path: PackedVector2Array = PackedVector2Array()
var _action := {}            # what to do once the path is done
var _wait := 0.6
var _rng := RandomNumberGenerator.new()
var _stuck_time := 0.0
var _last_pos := Vector2.ZERO


func setup(p_game: Node, p_agent: Agent, p_id: int, p_level := "hard") -> void:
	game = p_game
	agent = p_agent
	id = p_id
	level = p_level if LEVELS.has(p_level) else "hard"
	_p = LEVELS[level]
	_f = FIGHT[level]
	if _p["vents"] == "all":
		for i in game.world.vents.size():
			_vents_known[i] = true
	_rng.randomize()
	agent.room_changed.connect(func(_r):
		_path = PackedVector2Array()
		_action = {}
		_think_pause())


func _think_pause() -> void:
	_wait = _rng.randf_range(_p["think"][0], _p["think"][1])


## Called by the game for everything that happens in the match.
func on_event(e: Dictionary) -> void:
	var pid: int = e.get("pid", 0)
	match e.get("type", ""):
		"search":
			if pid != id:
				return
			var key: String = e["key"]
			_known.erase(key)
			if _rng.randf() < _p["memory"]:
				_searched[key] = true
			if e["left"] != "":
				_known[key] = e["left"]
				_searched.erase(key)
				_think_pause()
				return
			_think_pause()
			# Only rig furniture it has just emptied. Nothing can be hidden in
			# trapped furniture, so a careful bot never needs to come back to it.
			_maybe_trap(key, _p["trap"])
		"ko", "down":
			if e.get("type") == "down" and e.get("by", 0) == id:
				_engaged = false
			var room: Vector2i = e["room"]
			if pid == id or _p["sneaky"]:
				# Intel just went flying in that room: worth searching it again.
				for i in world().furniture(room).size():
					_searched.erase(World.furniture_key(room, i))
			if pid == id:
				_path = PackedVector2Array()
				_action = {}
				_wait = 0.4
		"trap_set", "trap_fail":
			if pid == id:
				_think_pause()


## Maybe hide a trap: in the furniture at `key`, or across another doorway.
func _maybe_trap(key: String, chance: float) -> void:
	if _rng.randf() >= chance or game.traps_owned_by(id) >= game.MAX_TRAPS:
		return
	var info := {}
	var door: int = game.near_door(agent)
	# Careless bots also string tripwires across doors they'll use themselves.
	if door != -1 and _p["avoid_own"] < 1.0 and _rng.randf() < 0.35:
		info = {"kind": "WIRE", "key": World.door_key(agent.room, door)}
	elif not game.traps.has(key) and not game.contents.has(key):
		info = {"kind": "BOMB" if _rng.randf() < 0.5 else "SPRING", "key": key}
	if info.is_empty() or game.traps.has(info["key"]):
		return
	_path = PackedVector2Array()
	_action = {}
	agent.start_trap(info, game.TRAP_TIME)


func _physics_process(delta: float) -> void:
	agent.move_input = Vector2.ZERO
	_attack_cd -= delta
	if game.over or agent.frozen or agent.searching or agent.ko_time > 0.0 or agent.vent >= 0:
		return
	if _fight(delta):
		return
	if _wait > 0.0:
		_wait -= delta
		return
	if not _path.is_empty():
		_follow(delta)
		return
	if not _action.is_empty():
		_do_action()
		return
	_think()


# ------------------------------------------------------------------ fighting

## Returns true while the bot is busy fighting (and not exploring).
func _fight(delta: float) -> bool:
	# The nearest other agent in the room, human or bot.
	var rival: Agent = game.rival_near(agent, 1.0e9)
	if rival == null:
		_met_in = Vector2i(-1, -1)
		_engaged = false
		return false
	# Decide once per meeting whether to pick a fight.
	if _met_in != agent.room:
		_met_in = agent.room
		_engaged = _rng.randf() < _f["aggro"]
		_fight_time = 0.0
		_attack_cd = _rng.randf_range(_f["react"][0], _f["react"][1])
	# Carrying everything? Ignore the rival and run for it. Also leave a rival
	# who's down or just back on their feet alone.
	if not _engaged or game.missing_intel(id).is_empty() or rival.ko_time > 0.0 or rival.protect_time > 0.0:
		return false
	var to := rival.position - agent.position
	var dist := to.length()
	if dist > _f["chase"]:
		return false
	# Don't keep at a fight that's going nowhere.
	_fight_time += delta
	if _fight_time > 6.0:
		_engaged = false
		return false
	_path = PackedVector2Array()
	_action = {}
	agent.facing = to.angle()
	if dist < game.MELEE_RANGE - 10.0:
		if _attack_cd <= 0.0:
			game.do_melee(id)
			_attack_cd = game.MELEE_COOLDOWN + _rng.randf_range(_f["react"][0], _f["react"][1])
		return true
	if _attack_cd <= 0.0 and game.inventories[id]["darts"] > 0 and dist > 200.0 and _rng.randf() < 0.5:
		game.do_fire(id, _f["aim"])
		_attack_cd = game.DART_COOLDOWN + _rng.randf_range(_f["react"][0], _f["react"][1])
		return true
	# Close in, going round any furniture in the way.
	_chase_replan -= delta
	if _chase_replan <= 0.0 or _chase.is_empty():
		_chase_replan = 0.4
		var grid := _grid(agent.room)
		_chase = grid.get_point_path(_cell_of(agent.position, grid), _cell_of(rival.position, grid), true)
	while not _chase.is_empty() and agent.position.distance_to(_chase[0]) < 12.0:
		_chase.remove_at(0)
	var goal: Vector2 = _chase[0] if not _chase.is_empty() else rival.position
	agent.move_input = (goal - agent.position).normalized() * _p["speed"]
	return true


# ------------------------------------------------------------------ decisions

func _inv() -> Dictionary:
	return game.inventories[id]


func _can_take_more() -> bool:
	return _inv()["case"] or _inv()["items"].is_empty()


func _think() -> void:
	var inv := _inv()
	if game.missing_intel(id).is_empty():
		_head_for_room(world().exit_room, {"type": "exit"})
		return

	# 1) Something useful in this room?
	var here := _targets_in(agent.room)
	if not here.is_empty():
		var idx: int = _closest_furniture(here)
		_plan_search(idx)
		return

	# 2) Otherwise go to the nearest room that has something worth checking.
	var best_room := Vector2i(-1, -1)
	var best_d := 999
	for r in world().rooms:
		if r == agent.room or _targets_in(r).is_empty():
			continue
		var d := _room_distance(agent.room, r)
		if d < best_d:
			best_d = d
			best_room = r
	if best_room.x >= 0:
		_head_for_room(best_room, {})
		return

	# 3) Searched everything and still missing intel: the rival must be
	#    moving things about. Forget what we've searched and start again.
	_searched.clear()
	_wait = 0.5


## Furniture in `room` worth visiting: unsearched, or known to hold an item
## the bot can actually pick up right now.
func _targets_in(room: Vector2i) -> Array:
	var out := []
	var items: Array = world().furniture(room)
	for i in items.size():
		var key := World.furniture_key(room, i)
		if game.traps.has(key) and game.traps[key]["owner"] == id and _remembers_own(key):
			continue
		if _known.has(key):
			if _can_take_more():
				out.append(i)
		elif not _searched.has(key):
			out.append(i)
	return out


func _closest_furniture(candidates: Array) -> int:
	var best: int = candidates[0]
	var best_d := INF
	for i in candidates:
		var r: Rect2 = world().furniture(agent.room)[i]["rect"]
		var d := agent.position.distance_to(r.get_center())
		if d < best_d:
			best_d = d
			best = i
	return best


func _plan_search(idx: int) -> void:
	var spot := _search_spot(agent.room, idx)
	if spot == Vector2.INF:
		# Can't reach it; don't keep trying.
		_searched[World.furniture_key(agent.room, idx)] = true
		return
	_go_to(spot, {"type": "search", "idx": idx})


## Moves one room closer to `target`, or does `final_action` if already there.
func _head_for_room(target: Vector2i, final_action: Dictionary) -> void:
	if agent.room == target:
		if final_action.get("type", "") == "exit":
			_go_to(_door_approach(world().exit_dir), {"type": "push", "dir": world().exit_dir})
		return
	# A curious bot sometimes tries a vent it hasn't been through yet.
	if _p["vents"] == "learn":
		for i in world().vents.size():
			if world().vents[i]["room"] == agent.room and not _vents_tried.has(i):
				_vents_tried[i] = true
				if _rng.randf() < 0.4:
					_go_to(world().vents[i]["front"], {"type": "vent", "idx": i})
					return
	var step := _route_step(agent.room, target)
	if step.get("type", "") == "vent":
		_go_to(world().vents[step["idx"]]["front"], {"type": "vent", "idx": step["idx"]})
	elif step.get("type", "") == "door":
		_go_to(_door_approach(step["dir"]), {"type": "push", "dir": step["dir"]})


## First move on the shortest route to `target`, through doors and any
## vent shortcuts the bot knows: {type: "door", dir} or {type: "vent", idx}.
func _route_step(from: Vector2i, target: Vector2i) -> Dictionary:
	var prev := {from: from}
	var how := {}
	var queue := [from]
	while not queue.is_empty():
		var r: Vector2i = queue.pop_front()
		if r == target:
			break
		var steps := []
		var near := _next_room(r, target)
		# Prefer the door the old router would pick (it avoids own tripwires).
		for d in World.DIR_VEC:
			if world().has_door(r, d):
				var n: Vector2i = r + World.DIR_VEC[d]
				if n == near:
					steps.push_front([n, {"type": "door", "dir": d}])
				else:
					steps.append([n, {"type": "door", "dir": d}])
		for i in world().vents.size():
			if world().vents[i]["room"] == r and _vents_known.has(i):
				steps.append([world().vents[world().vents[i]["link"]]["room"], {"type": "vent", "idx": i}])
		for st in steps:
			if not prev.has(st[0]):
				prev[st[0]] = r
				how[st[0]] = st[1]
				queue.append(st[0])
	if not prev.has(target) or target == from:
		return {}
	var r := target
	while prev[r] != from:
		r = prev[r]
	return how[r]


func _do_action() -> void:
	var a := _action
	match a.get("type", ""):
		"vent":
			_action = {}
			var i: int = a["idx"]
			if world().vent_near(agent.room, agent.position, 90.0) == i:
				_vents_known[i] = true
				_vents_known[world().vents[i]["link"]] = true
				game.do_vent(id, i)
			_think_pause()
		"search":
			_action = {}
			agent.start_search(a["idx"], game.SEARCH_TIME)
		"push":
			# Walk straight out through the doorway (or into the exit).
			var v := Vector2(World.DIR_VEC[a["dir"]])
			agent.move_input = v * _p["speed"]
			a["t"] = a.get("t", 0.0) + get_physics_process_delta_time()
			if a["t"] > 1.5:
				_action = {}
				_think_pause()
		_:
			_action = {}


# ------------------------------------------------------------------ movement

func _go_to(target: Vector2, action: Dictionary) -> void:
	var grid := _grid(agent.room)
	var from := _cell_of(agent.position, grid)
	var to := _cell_of(target, grid)
	var path := grid.get_point_path(from, to, true)
	if path.is_empty():
		_path = PackedVector2Array([target])
	else:
		path.append(target)
		_path = path
	_action = action
	_stuck_time = 0.0
	_last_pos = agent.position


func _follow(delta: float) -> void:
	var p := agent.position
	while not _path.is_empty() and p.distance_to(_path[0]) < 10.0:
		_path.remove_at(0)
	if _path.is_empty():
		return
	agent.move_input = (_path[0] - p).normalized() * _p["speed"]
	# If we're not making progress, nudge sideways and re-plan.
	if p.distance_to(_last_pos) < 1.0:
		_stuck_time += delta
		if _stuck_time > 0.6:
			_path = PackedVector2Array()
			agent.move_input = Vector2.from_angle(_rng.randf() * TAU)
			_wait = 0.25
			_stuck_time = 0.0
	else:
		_stuck_time = 0.0
	_last_pos = p


func _door_approach(dir: int) -> Vector2:
	var R := World.ROOM
	var c := R.get_center()
	var inset := Agent.RADIUS + 14.0
	match dir:
		World.Dir.UP: return Vector2(c.x, R.position.y + inset)
		World.Dir.DOWN: return Vector2(c.x, R.end.y - inset)
		World.Dir.LEFT: return Vector2(R.position.x + inset, c.y)
		_: return Vector2(R.end.x - inset, c.y)


## A free spot next to the furniture, close enough to search it.
func _search_spot(room: Vector2i, idx: int) -> Vector2:
	var r: Rect2 = world().furniture(room)[idx]["rect"]
	var grid := _grid(room)
	var best := Vector2.INF
	var best_d := INF
	for y in grid.region.size.y:
		for x in grid.region.size.x:
			var cell := Vector2i(x, y)
			if grid.is_point_solid(cell):
				continue
			var p := grid.get_point_position(cell)
			var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
			var d := p.distance_to(q)
			if d > 120.0 or d < 0.01:
				continue
			# Prefer squares close to the furniture, then close to the bot.
			var score := d * 2.0 + agent.position.distance_to(p) * 0.3
			if score < best_d:
				best_d = score
				# Stand right up against the furniture, whatever the grid says.
				best = q + (p - q) / d * (Agent.RADIUS + 8.0)
	return best


func _grid(room: Vector2i) -> AStarGrid2D:
	if _grids.has(room):
		return _grids[room]
	var R := World.ROOM
	var g := AStarGrid2D.new()
	g.region = Rect2i(0, 0, int(R.size.x / CELL), int(R.size.y / CELL))
	g.cell_size = Vector2(CELL, CELL)
	g.offset = R.position + Vector2(CELL, CELL) / 2.0
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.update()
	var margin := Agent.RADIUS + 4.0
	for y in g.region.size.y:
		for x in g.region.size.x:
			var cell := Vector2i(x, y)
			var p := g.get_point_position(cell)
			var solid := not R.grow(-Agent.RADIUS).has_point(p)
			for f in world().furniture(room):
				if (f["rect"] as Rect2).grow(margin).has_point(p):
					solid = true
					break
			g.set_point_solid(cell, solid)
	_grids[room] = g
	return g


func _cell_of(p: Vector2, grid: AStarGrid2D) -> Vector2i:
	var c := Vector2i(((p - grid.offset) / CELL).round())
	c = c.clamp(Vector2i.ZERO, grid.region.size - Vector2i.ONE)
	if not grid.is_point_solid(c):
		return c
	# Nearest free cell.
	var best := c
	var best_d := INF
	for y in grid.region.size.y:
		for x in grid.region.size.x:
			var cell := Vector2i(x, y)
			if not grid.is_point_solid(cell):
				var d := Vector2(cell - c).length_squared()
				if d < best_d:
					best_d = d
					best = cell
	return best


# ------------------------------------------------------------------ room graph

func world() -> World:
	return game.world


func _room_distance(a: Vector2i, b: Vector2i) -> int:
	# Every neighbouring room is connected, so this is just grid distance.
	return absi(a.x - b.x) + absi(a.y - b.y)


func _next_room(a: Vector2i, b: Vector2i) -> Vector2i:
	var options := []
	if a.x != b.x:
		options.append(Vector2i(signi(b.x - a.x), 0))
	if a.y != b.y:
		options.append(Vector2i(0, signi(b.y - a.y)))
	# Prefer a doorway it hasn't rigged with its own tripwire (if it remembers).
	for step in options:
		var dir := _dir_of(step)
		var k := World.door_key(a, dir)
		if not (game.traps.has(k) and game.traps[k]["owner"] == id and _remembers_own(k)):
			return a + step
	return a + options[0]


## Whether the bot remembers its own trap at `key`. Decided once per trap,
## so a forgetful bot doesn't flip-flop about the same piece of furniture.
func _remembers_own(key: String) -> bool:
	if not _own_memory.has(key):
		_own_memory[key] = _rng.randf() < _p["avoid_own"]
	return _own_memory[key]


func _dir_of(step: Vector2i) -> int:
	for d in World.DIR_VEC:
		if World.DIR_VEC[d] == step:
			return d
	return World.Dir.UP
