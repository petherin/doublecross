extends Node
## Sound effects and music. All audio is synthesised by tools/make_audio.py.
##
## Buses: Music, SFX, and Distant (SFX heard through walls: quieter and muffled).

const NAMES := [
	"step1", "step2", "rummage", "found", "gadget", "nothing", "trap_set", "boom",
	"boing", "twang", "swing", "hit", "down", "dart", "door", "click", "locked",
	"tick", "win", "lose",
]
const VOICES := 12

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer


func _ready() -> void:
	_make_bus("Music")
	_make_bus("SFX")
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

	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	var m: AudioStream = load("res://assets/audio/music.ogg")
	if m is AudioStreamOggVorbis:
		m.loop = true
	_music.stream = m
	add_child(_music)

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


## Plays an effect. `distant` = it happened in another room (muffled).
func play(sound_name: String, volume_db := 0.0, distant := false, pitch_jitter := 0.06) -> void:
	if not _streams.has(sound_name):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stop()
	p.stream = _streams[sound_name]
	p.bus = "Distant" if distant else "SFX"
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


func music(on: bool) -> void:
	if on and not _music.playing:
		_music.play()
	elif not on:
		_music.stop()


## Speeds the music up a touch when time is running out.
func music_tempo(scale: float) -> void:
	_music.pitch_scale = scale
