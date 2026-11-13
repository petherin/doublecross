extends Node
## Player settings, saved on the device (user://settings.cfg).

signal changed

const PATH := "user://settings.cfg"

var music_volume := 0.7
var sfx_volume := 0.9
var vibration := true
var clock_minutes := 6
var bot_level := "medium"
var last_ip := ""


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		music_volume = cfg.get_value("audio", "music", music_volume)
		sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
		vibration = cfg.get_value("game", "vibration", vibration)
		clock_minutes = cfg.get_value("game", "clock_minutes", clock_minutes)
		bot_level = cfg.get_value("game", "bot_level", bot_level)
		last_ip = cfg.get_value("net", "last_ip", last_ip)
	changed.emit()


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("game", "vibration", vibration)
	cfg.set_value("game", "clock_minutes", clock_minutes)
	cfg.set_value("game", "bot_level", bot_level)
	cfg.set_value("net", "last_ip", last_ip)
	cfg.save(PATH)
	changed.emit()


## A short buzz on phones/tablets (if enabled).
func buzz(ms: int) -> void:
	if vibration and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)
