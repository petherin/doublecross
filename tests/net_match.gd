extends SceneTree
## Network regression: a real host and joiner, as two processes on this
## machine, start a match with bots in the two empty seats. The host must run
## the bots; the joiner must see them as remote agents that move.
##   godot --headless -s res://tests/net_match.gd -- --role=host &
##   godot --headless -s res://tests/net_match.gd -- --role=join

const TIMEOUT := 90.0

var _role := ""
var _main: Node
var _t := 0.0
var _dialled := false
var _started := false
var _game_t := 0.0
var _first := {}      # bot agent -> its position when first seen


func _process(delta: float) -> bool:
	if _main == null:
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--role="):
				_role = a.get_slice("=", 1)
		var settings := root.get_node("Settings")
		settings.host_bots = true
		settings.bot_level = "hard"
		settings.player_name = _role.to_upper()
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	_t += delta
	if _t > TIMEOUT:
		return _finish("FAIL: %s timed out (game started: %s)" % [_role, _main._game != null])
	if not _dialled and _t > (1.0 if _role == "host" else 3.0):
		_dialled = true
		if _role == "host":
			_main._menu._on_host()
		else:
			root.get_node("Net").join("127.0.0.1")
	if _role == "host" and not _started and _main._names.size() >= 2:
		_started = true
		_main._start_match()
	var g: Node = _main._game
	if g == null or g.agents.is_empty():
		return false
	var verdict := _judge(g, delta)
	return _finish(verdict) if verdict != "" else false


## "" while the match is still being watched, otherwise the result line.
func _judge(g: Node, delta: float) -> String:
	var bots: Array = g.agents.filter(func(a): return a.display_name.ends_with("(BOT)"))
	if bots.size() != 2:
		return "FAIL: %s sees %d bots, wanted 2" % [_role, bots.size()]
	if _role == "host" and g.bots.size() != 2:
		return "FAIL: the host isn't running the bots"
	if _role == "join" and (not g.bots.is_empty() or bots.any(func(a): return a.is_local)):
		return "FAIL: the joiner is running bots itself"
	_game_t += delta
	for a in bots:
		if not _first.has(a):
			_first[a] = a.position
	if _role == "host":
		return "net_match host: ok" if _game_t > 30.0 else ""
	for a in bots:
		var moved: float = a.position.distance_to(_first[a])
		if moved > 40.0:
			return "net_match join: ok (a bot moved %.0f units on this device)" % moved
	return ""

func _finish(msg: String) -> bool:
	print(msg)
	root.get_node("Net").end_session("")
	quit(0 if msg.contains(": ok") else 1)
	return true
