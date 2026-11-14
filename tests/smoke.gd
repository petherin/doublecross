extends SceneTree
## Fast headless checks, run in CI:
## - every script compiles and every input action is mapped,
## - generated bases for 2, 3 and 4 agents obey the rules (all items hidden,
##   vents link distant rooms, every piece of furniture has a sprite),
## - the menu and a match can be built and run for a few frames.
##   godot --headless -s res://tests/smoke.gd

var _failures := 0
var _frames := 0
var _game: Node
var _menu: Node


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: ", what)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_check_scripts("res://scripts")
		_check_worlds()
		for action in ["move_left", "move_right", "move_up", "move_down", "search", "crawl",
				"attack", "fire", "trap_bomb", "trap_spring", "trap_wire"]:
			_check(InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty(),
					"input action " + action)
		_menu = load("res://scripts/ui/menu.gd").new()
		root.add_child(_menu)
		_game = load("res://scripts/game/game.gd").new()
		root.add_child(_game)
		_game.setup(7, 1, [1], "medium", 6, {1: "SMOKE"})
	elif _frames == 120:
		_check(not _game.over, "match ended within two seconds")
		print("smoke: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
		_menu.queue_free()
		_game.queue_free()
		quit(0 if _failures == 0 else 1)
		return true
	return false


func _check_scripts(dir: String) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_check_scripts(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			var s: GDScript = load(dir.path_join(f))
			_check(s != null and s.can_instantiate(), "script compiles: " + f)


func _check_worlds() -> void:
	var World = load("res://scripts/core/world.gd")
	var sprites: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://assets/sprites/furniture.json"))["sprites"]
	for seed_value in 300:
		var players: int = 2 + seed_value % 3
		var w = World.new(seed_value, players)
		var tag := " (seed %d, %d players)" % [seed_value, players]
		var starts: Array = w.start_rooms()
		_check(starts.size() == players, "one start room per agent" + tag)
		_check(w.rooms.size() == World.SIZES[players].x * World.SIZES[players].y, "base size" + tag)
		_check(not w.exit_room in starts, "exit not in a start room" + tag)
		var items: Array = w.hidden.values()
		for item in World.INTEL + [World.BRIEFCASE] + World.GADGETS:
			_check(item in items, item + " hidden" + tag)
		_check(w.opening(w.exit_room, w.exit_dir) == 2, "exit on an outer wall" + tag)
		_check(w.vents.size() >= 2 and w.vents.size() % 2 == 0, "vents come in pairs" + tag)
		for i in w.vents.size():
			var v: Dictionary = w.vents[i]
			var partner: Dictionary = w.vents[v["link"]]
			_check(partner["link"] == i, "vent links are mutual" + tag)
			var d: Vector2i = (v["room"] as Vector2i) - (partner["room"] as Vector2i)
			_check(absi(d.x) + absi(d.y) >= 2, "vent skips at least one room" + tag)
		for r in w.rooms:
			for f in w.rooms[r]["furniture"]:
				_check(sprites.has(f["type"] + "_" + f["wall"]), "sprite for " + f["type"] + tag)
