extends SceneTree
## Headless regression: an idle player against the hard bot. The bot must
## find the intel and briefcase and escape before the clock runs out.
##   godot --headless --fixed-fps 60 -s res://tests/bot_match.gd

const LIMIT := 60 * 60 * 7   # seven minutes of game time at 60 fps

var _game: Node
var _frames := 0


func _process(_delta: float) -> bool:
	if _game == null:
		# Loaded at runtime: the game script refers to autoloads, which only
		# exist once the tree is running.
		_game = load("res://scripts/game/game.gd").new()
		root.add_child(_game)
		_game.setup(12345, 1, [1], "hard", 6, {1: "TEST"})
		return false
	_frames += 1
	if _game.over:
		var won: bool = _game.bot.agent.celebrating
		print("match over after %.0f s, bot escaped: %s" % [_frames / 60.0, won])
		return _finish(0 if won else 1)
	if _frames > LIMIT:
		print("FAIL: match did not finish in time")
		return _finish(1)
	return false


func _finish(code: int) -> bool:
	_game.queue_free()
	quit(code)
	return true
