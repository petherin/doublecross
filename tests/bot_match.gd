extends SceneTree
## Headless regression: an idle player against the hard bot. The bot must
## find the intel and briefcase and escape before the clock runs out.
##   godot --headless --fixed-fps 60 -s res://tests/bot_match.gd [-- --bots=3 --seed=7 --spectate]
## With --spectate the player is put out after two seconds, and the camera
## must follow the bots (room by room) while they play on.

const LIMIT := 60 * 60 * 12   # twelve minutes of game time at 60 fps

var _game: Node
var _frames := 0
var _spectate := false
var _bad_follow := 0


func _process(_delta: float) -> bool:
	if _game == null:
		# Loaded at runtime: the game script refers to autoloads, which only
		# exist once the tree is running.
		_game = load("res://scripts/game/game.gd").new()
		root.add_child(_game)
		var bots := 1
		var seed_value := 12345
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--bots="):
				bots = a.get_slice("=", 1).to_int()
			elif a.begins_with("--seed="):
				seed_value = a.get_slice("=", 1).to_int()
			elif a == "--spectate":
				_spectate = true
		_game.setup(seed_value, 1, [1], "hard", 6, {1: "TEST"}, bots)
		return false
	_frames += 1
	if _spectate and _frames == 120:
		_game.referee.eliminate(1, "time")
	if _spectate and _frames > 125 and not _game.over:
		if not _game.spectating or _game.watched == _game.local_agent or _game.watched.out:
			print("FAIL: not watching a rival once out")
			return _finish(1)
		if _game.view.room != _game.watched.room:
			_bad_follow += 1
			if _bad_follow > 2:
				print("FAIL: the view isn't following the agent being watched")
				return _finish(1)
		else:
			_bad_follow = 0
	if _game.over:
		var won := false
		for b in _game.bots.values():
			won = won or b.agent.celebrating
		print("match over after %.0f s: %s; a bot escaped: %s" % [_frames / 60.0, _game.result, won])
		var tl: Array = _game.presenter.timeline
		print("timeline: %d entries" % tl.size())
		var escaped: bool = not tl.is_empty() and str(tl.back()["text"]).ends_with("escaped with the intel")
		if tl.is_empty() or (_game.result["reason"] == "escape" and not escaped):
			print("FAIL: the debrief timeline is missing or doesn't end with the escape")
			return _finish(1)
		return _finish(0 if won else 1)
	if _frames > LIMIT:
		print("FAIL: match did not finish in time")
		return _finish(1)
	return false


func _finish(code: int) -> bool:
	_game.queue_free()
	quit(code)
	return true
