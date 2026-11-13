extends Node
## A computer-controlled rival for one-player games.
##
## The bot plays by the same rules as a person: it doesn't know where the
## items are until it searches, it can only carry one item until it finds the
## briefcase, and it has to walk to the exit. It remembers what it has
## searched and where it left things.

const World = preload("res://scripts/world.gd")
const Agent = preload("res://scripts/agent.gd")

const CELL := 40.0
const REACH := 60.0          # how close to furniture it needs to stand to search
const THINK_MIN := 0.25      # pause between decisions, so it feels human
const THINK_MAX := 0.7
const SPEED_FACTOR := 0.9    # a touch slower than a person at full tilt

var game: Node
var agent: Agent
var id := 2

var _grids := {}             # room -> AStarGrid2D
var _searched := {}          # furniture key -> true (looked, nothing useful left)
var _known := {}             # furniture key -> item the bot knows is there
var _path: PackedVector2Array = PackedVector2Array()
var _action := {}            # what to do once the path is done
var _wait := 0.6
var _rng := RandomNumberGenerator.new()
var _stuck_time := 0.0
var _last_pos := Vector2.ZERO


func setup(p_game: Node, p_agent: Agent, p_id: int) -> void:
	game = p_game
	agent = p_agent
	id = p_id
	_rng.randomize()
	agent.room_changed.connect(func(_r):
		_path = PackedVector2Array()
		_action = {}
		_wait = _rng.randf_range(THINK_MIN, THINK_MAX))


## Called by the game after the host settles one of the bot's searches.
func on_search_result(key: String, found: String, left: String) -> void:
	_known.erase(key)
	_searched[key] = true
	if left != "":
		_known[key] = left
		_searched.erase(key)
	_wait = _rng.randf_range(THINK_MIN, THINK_MAX)


func _physics_process(delta: float) -> void:
	agent.move_input = Vector2.ZERO
	if game.over or agent.frozen or agent.searching:
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


# ------------------------------------------------------------------ decisions

func _inv() -> Dictionary:
	return game.inventories[id]


func _can_take_more() -> bool:
	return _inv()["case"] or _inv()["items"].is_empty()


func _think() -> void:
	var inv := _inv()
	if game._missing(id).is_empty():
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
	if inv["items"].is_empty() and not inv["case"]:
		return


## Furniture in `room` worth visiting: unsearched, or known to hold an item
## the bot can actually pick up right now.
func _targets_in(room: Vector2i) -> Array:
	var out := []
	var items: Array = world().furniture(room)
	for i in items.size():
		var key := World.furniture_key(room, i)
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
	var step := _next_room(agent.room, target)
	for dir in World.DIR_VEC:
		if agent.room + World.DIR_VEC[dir] == step:
			_go_to(_door_approach(dir), {"type": "push", "dir": dir})
			return


func _do_action() -> void:
	var a := _action
	match a.get("type", ""):
		"search":
			_action = {}
			agent.start_search(a["idx"], game.SEARCH_TIME)
		"push":
			# Walk straight out through the doorway (or into the exit).
			var v := Vector2(World.DIR_VEC[a["dir"]])
			agent.move_input = v * SPEED_FACTOR
			a["t"] = a.get("t", 0.0) + get_physics_process_delta_time()
			if a["t"] > 1.5:
				_action = {}
				_wait = _rng.randf_range(0.3, 1.0)
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
	agent.move_input = (_path[0] - p).normalized() * SPEED_FACTOR
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
			if d > REACH:
				continue
			var score := agent.position.distance_to(p)
			if score < best_d:
				best_d = score
				best = p
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
	if a.x != b.x:
		return a + Vector2i(signi(b.x - a.x), 0)
	return a + Vector2i(0, signi(b.y - a.y))
