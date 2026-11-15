extends Node
## Sound effects and music. All audio is synthesised by tools/make_audio.py.
##
## Buses: Music, SFX, and Distant (SFX heard through walls: quieter and muffled).

const NAMES := [
	"step1", "step2", "step3", "step4", "rummage1", "rummage2", "rummage3",
	"found", "gadget", "nothing", "trap_set", "boom", "boing", "twang", "swing",
	"hit", "down", "dart", "door", "click", "locked", "tick", "win", "lose",
	"type1", "type2", "type3", "stamp", "paper", "poof", "crawl", "vent", "zap",
	"oof1", "oof2", "argh1", "argh2", "yell", "haha", "bark1", "bark2", "yip", "growl",
]
const VOICES := 12

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer
## Extra layers mixed over the bed: a rival nearby, and the clock running out.
var _layers := {}          # name -> AudioStreamPlayer
var _layer_target := {}    # name -> 0..1
var _layer_level := {}     # name -> current 0..1
## Room tone: two players so one room's sound can crossfade into the next.
var _amb: Array[AudioStreamPlayer] = []
var _amb_streams := {}
var _amb_current := ""


func _ready() -> void:
	_make_bus("Music")
	_make_bus("SFX")
	_make_bus("Ambience")
	for amb_name in ["amb_hvac", "amb_machines", "amb_pipes"]:
		var st: AudioStream = load("res://assets/audio/%s.ogg" % amb_name)
		if st is AudioStreamOggVorbis:
			st.loop = true
			_amb_streams[amb_name] = st
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Ambience"
		p.volume_db = -60.0
		add_child(p)
		_amb.append(p)
	# A compressor for punch and a touch of room on the effects.
	var sfx_bus := AudioServer.get_bus_index("SFX")
	var comp := AudioEffectCompressor.new()
	comp.threshold = -14.0
	comp.ratio = 4.0
	comp.attack_us = 2000.0
	comp.release_ms = 180.0
	comp.gain = 3.0
	AudioServer.add_bus_effect(sfx_bus, comp)
	var room := AudioEffectReverb.new()
	room.room_size = 0.35
	room.damping = 0.6
	room.wet = 0.1
	room.dry = 1.0
	AudioServer.add_bus_effect(sfx_bus, room)
	var limiter := AudioEffectHardLimiter.new()
	AudioServer.add_bus_effect(0, limiter)
	var distant := _make_bus("Distant")
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 700.0
	AudioServer.add_bus_effect(distant, lp)
	AudioServer.set_bus_volume_db(distant, -9.0)
	AudioServer.set_bus_send(distant, "SFX")

	for n in NAMES:
		var path := "res://assets/audio/%s.wav" % n
		if ResourceLoader.exists(path):
			_streams[n] = load(path)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)

	_music = _loop_player("music")
	for layer in ["tension", "hurry"]:
		_layers[layer] = _loop_player("music_" + layer)
		_layers[layer].volume_db = -60.0
		_layer_target[layer] = 0.0
		_layer_level[layer] = 0.0

	Settings.changed.connect(_apply_volumes)
	_apply_volumes()


func _make_bus(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	return idx


func _apply_volumes() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(Settings.music_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(Settings.sfx_volume, 0.0001)))
	# Room tone sits well under the effects and follows their volume.
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambience"),
			linear_to_db(maxf(Settings.sfx_volume, 0.0001)) - 15.0)


## Plays an effect. `distant` = it happened in another room (muffled).
## `pitch` sets the base pitch (a voice); jitter varies it a little each time.
func play(sound_name: String, volume_db := 0.0, distant := false, pitch_jitter := 0.06, pitch := 1.0) -> void:
	if not _streams.has(sound_name):
		# "step" -> one of step1, step2, ... at random.
		var takes := []
		for n in _streams:
			if n.begins_with(sound_name) and n.trim_prefix(sound_name).is_valid_int():
				takes.append(n)
		if takes.is_empty():
			return
		sound_name = takes[randi() % takes.size()]
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stop()
	p.stream = _streams[sound_name]
	p.bus = "Distant" if distant else "SFX"
	p.volume_db = volume_db
	p.pitch_scale = pitch * (1.0 + randf_range(-pitch_jitter, pitch_jitter))
	p.play()


func _loop_player(stream_name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	var m: AudioStream = load("res://assets/audio/%s.ogg" % stream_name)
	if m is AudioStreamOggVorbis:
		m.loop = true
	p.stream = m
	add_child(p)
	return p


## Starts (or stops) the music. The layers start in step with the bed and
## stay there, since all three loops are exactly the same length.
func music(on: bool) -> void:
	if on and not _music.playing:
		music_layers(0.0, 0.0)
		for layer in _layers:
			_layer_level[layer] = 0.0
			_layers[layer].volume_db = -60.0
		_music.play()
		for layer in _layers.values():
			layer.play()
	elif not on:
		_music.stop()
		for layer in _layers.values():
			layer.stop()


## Crossfades the room tone to `amb_name` ("" for silence) over `seconds`.
func ambience(amb_name: String, seconds := 0.8) -> void:
	if amb_name == _amb_current:
		return
	_amb_current = amb_name
	var old: AudioStreamPlayer = _amb[0]
	var nxt: AudioStreamPlayer = _amb[1]
	_amb.reverse()
	var tw := create_tween().set_parallel()
	tw.tween_property(old, "volume_db", -60.0, seconds)
	if _amb_streams.has(amb_name):
		nxt.stream = _amb_streams[amb_name]
		nxt.volume_db = -60.0
		nxt.play(randf() * 12.0)
		tw.tween_property(nxt, "volume_db", 0.0, seconds)
	tw.chain().tween_callback(func():
		if old.volume_db <= -59.0:
			old.stop())


## How much of each extra layer to bring in (0..1); they fade over a second.
func music_layers(tension: float, hurry: float) -> void:
	_layer_target["tension"] = clampf(tension, 0.0, 1.0)
	_layer_target["hurry"] = clampf(hurry, 0.0, 1.0)


## Speeds the music up a touch when time is running out.
func music_tempo(scale: float) -> void:
	_music.pitch_scale = scale
	for layer in _layers.values():
		layer.pitch_scale = scale


func _process(delta: float) -> void:
	for layer in _layers:
		var level: float = _layer_level[layer]
		var target: float = _layer_target[layer]
		level = move_toward(level, target, delta * (1.6 if target > level else 0.8))
		_layer_level[layer] = level
		_layers[layer].volume_db = linear_to_db(maxf(level, 0.001)) if level > 0.001 else -60.0
