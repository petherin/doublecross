extends Node
## Top-level flow: menu <-> match. The host gathers 1-3 rivals in a lobby,
## then starts the match by sending everyone the same world seed.

const Menu = preload("res://scripts/ui/menu.gd")
const Game = preload("res://scripts/game/game.gd")

var _menu: Menu
var _game: Game
## One-player modes are run entirely on this device.
var _offline_mode := ""   # "", "practice" or "bot"
var _bot_level := "medium"
var _bot_count := 1
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
	Net.opponent_left.connect(_on_opponent_left)
	Net.joined_host.connect(func(): hello.rpc_id(1, Settings.player_name, Net.version))
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
		_menu.bot_requested.connect(func(level, count):
			_bot_level = level
			_bot_count = count
			_start_offline("bot"))
		_menu.host_requested.connect(_on_host_requested)
		_menu.start_requested.connect(_start_match)
		add_child(_menu)
	_menu.set_status(msg)


func _leave() -> void:
	Net.end_session("")
	_show_menu("")


# ------------------------------------------------------------------ lobby

func _on_host_requested() -> void:
	_names = {1: Settings.player_name}
	_update_lobby()


func _on_opponent_joined(id: int) -> void:
	# Wait for the joiner's hello (codename and version) before counting them.
	var waited := 0.0
	while Net.in_session and not _names.has(id) and waited < 5.0 and multiplayer.get_peers().has(id):
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	if Net.in_session and not _names.has(id) and multiplayer.get_peers().has(id):
		Net.kick(id)


func _on_opponent_left(id: int) -> void:
	_names.erase(id)
	_update_lobby()


## Host: tells everyone who's in the lobby, and whether it can start.
func _update_lobby() -> void:
	if not Net.is_hosting or Net.in_game:
		return
	lobby.rpc(_names)
	if _names.size() >= Net.MAX_PLAYERS:
		_start_match()


## Host presses START (or the lobby fills up).
func _start_match() -> void:
	if not Net.is_hosting or Net.in_game or _names.size() < 2:
		return
	Net.in_game = true
	start_game.rpc(randi(), Settings.clock_minutes, _names)


## A joining player introduces themselves: codename and app version. Every
## device must run the same version, or the host turns the joiner away.
@rpc("any_peer", "call_remote", "reliable")
func hello(player_name: String, their_version: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if their_version != Net.version:
		wrong_version.rpc_id(id, Net.version)
		if _menu:
			_menu.set_status("A rival with v%s was turned away (you have v%s). Still waiting…" % [their_version, Net.version])
		await get_tree().create_timer(0.5).timeout
		Net.kick(id)
		return
	_names[id] = player_name.strip_edges().left(14)
	_update_lobby()


## Sent to a joiner whose version doesn't match the host's.
@rpc("authority", "call_remote", "reliable")
func wrong_version(host_version: String) -> void:
	Net.end_session("")
	_show_menu("Can't join: host has v%s, you have v%s. Update both devices." % [host_version, Net.version])


## Who's in the lobby so far (host and joiners alike show it).
@rpc("authority", "call_local", "reliable")
func lobby(names: Dictionary) -> void:
	_names = names
	if _menu:
		_menu.set_lobby(names.values(), multiplayer.is_server())


@rpc("authority", "call_local", "reliable")
func start_game(seed_value: int, minutes := 6, names := {}) -> void:
	Net.in_game = true
	_minutes = minutes
	_names = names
	_offline_mode = ""
	_begin(seed_value, names.keys())


# ------------------------------------------------------------------ matches

func _start_offline(mode: String) -> void:
	_offline_mode = mode
	_names = {multiplayer.get_unique_id(): Settings.player_name}
	_minutes = Settings.clock_minutes
	_begin(randi(), [multiplayer.get_unique_id()])


func _rematch() -> void:
	if _offline_mode != "":
		_begin(randi(), [multiplayer.get_unique_id()])
	elif multiplayer.is_server():
		# Only agents still connected play again.
		for id in _names.keys():
			if id != 1 and not multiplayer.get_peers().has(id):
				_names.erase(id)
		if _names.size() >= 2:
			start_game.rpc(randi(), Settings.clock_minutes, _names)
		else:
			_leave()


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
	var bot_level := _bot_level if _offline_mode == "bot" else ""
	_game.setup(seed_value, multiplayer.get_unique_id(), ids, bot_level, _minutes, _names, _bot_count)
	Sound.music(true)
	Sound.music_tempo(1.0)
	_game.leave_requested.connect(_leave)
	_game.rematch_requested.connect(_rematch)
