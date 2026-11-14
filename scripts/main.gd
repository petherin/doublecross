extends Node
## Top-level flow: menu <-> match. The host starts the match as soon as a
## rival joins by sending everyone the same world seed.

const Menu = preload("res://scripts/menu.gd")
const Game = preload("res://scripts/game.gd")

var _menu: Menu
var _game: Game
## One-player modes are run entirely on this device.
var _offline_mode := ""   # "", "practice" or "bot"
var _bot_level := "medium"
var _minutes := 6
## peer id -> chosen codename, gathered by the host before the match starts.
var _names := {}


func _ready() -> void:
	randomize()
	# Typewriter type everywhere text is drawn with the default font.
	var tw := load("res://assets/fonts/CourierPrime-Bold.ttf")
	if tw:
		ThemeDB.fallback_font = tw
	get_tree().set_auto_accept_quit(false)
	get_tree().set_quit_on_go_back(false)
	Net.opponent_joined.connect(_on_opponent_joined)
	Net.joined_host.connect(func(): register_name.rpc_id(1, Settings.player_name))
	Net.session_ended.connect(_show_menu)
	_show_menu("")
	Sound.music(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _game:
			_leave()
		else:
			Net.end_session("")
			get_tree().quit()


func _show_menu(msg: String) -> void:
	if _game:
		remove_child(_game)
		_game.queue_free()
		_game = null
	if _menu == null:
		_menu = Menu.new()
		_menu.practice_requested.connect(func(): _start_offline("practice"))
		_menu.bot_requested.connect(func(level):
			_bot_level = level
			_start_offline("bot"))
		add_child(_menu)
	_menu.set_status(msg)


func _leave() -> void:
	Net.end_session("")
	_show_menu("")


func _on_opponent_joined(id: int) -> void:
	# Wait for the joiner to tell us their codename (or give up after 3s).
	_names = {1: Settings.player_name}
	var waited := 0.0
	while Net.in_session and not _names.has(id) and waited < 3.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	if Net.in_session:
		start_game.rpc(randi(), Settings.clock_minutes, _names)


## A joining player tells the host their codename.
@rpc("any_peer", "call_remote", "reliable")
func register_name(player_name: String) -> void:
	if multiplayer.is_server():
		_names[multiplayer.get_remote_sender_id()] = player_name.strip_edges().left(14)


@rpc("authority", "call_local", "reliable")
func start_game(seed_value: int, minutes := 6, names := {}) -> void:
	_minutes = minutes
	_names = names
	_offline_mode = ""
	var ids: Array = [multiplayer.get_unique_id()]
	ids.append_array(multiplayer.get_peers())
	_begin(seed_value, ids)


func _start_offline(mode: String) -> void:
	_offline_mode = mode
	_names = {multiplayer.get_unique_id(): Settings.player_name}
	_minutes = Settings.clock_minutes
	_begin(randi(), [multiplayer.get_unique_id()])


func _rematch() -> void:
	if _offline_mode != "":
		_begin(randi(), [multiplayer.get_unique_id()])
	elif multiplayer.is_server():
		start_game.rpc(randi(), Settings.clock_minutes, _names)


func _begin(seed_value: int, ids: Array) -> void:
	if _game:
		remove_child(_game)
		_game.queue_free()
		_game = null
	if _menu:
		Net.stop_listening()
		remove_child(_menu)
		_menu.queue_free()
		_menu = null
	_game = Game.new()
	_game.name = "Game"
	add_child(_game)
	_game.setup(seed_value, multiplayer.get_unique_id(), ids, _bot_level if _offline_mode == "bot" else "", _minutes, _names)
	Sound.music(true)
	Sound.music_tempo(1.0)
	_game.leave_requested.connect(_leave)
	_game.rematch_requested.connect(_rematch)
