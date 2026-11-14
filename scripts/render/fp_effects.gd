extends Node3D
## The room's effects in first person: explosions, shocks, springs, hits,
## dust and paperwork as 3D particles and light flashes, with the same
## comic-book words floating in the room. It reads the overhead view's
## effect list and spawns each new effect once.

const Style = preload("res://scripts/ui/style.gd")

var _seen := {}


## Spawns anything in `effects` (the overhead view's list) not seen before.
func sync(effects: Array) -> void:
	var live := {}
	for e in effects:
		var id: int = e.get("id", 0)
		live[id] = true
		if not _seen.has(id):
			_seen[id] = true
			_spawn(e)
	for id in _seen.keys():
		if not live.has(id):
			_seen.erase(id)


## Forgets everything (on changing room), so old effects don't replay.
func clear() -> void:
	for c in get_children():
		c.queue_free()
	_seen.clear()


func _spawn(e: Dictionary) -> void:
	var p: Vector2 = e["pos"]
	var at := Vector3(p.x, 0.0, p.y)
	match e["kind"]:
		"BOMB":
			_flash(at + Vector3(0, 60, 0), Color(1.0, 0.55, 0.2), 16.0, 1.0)
			_burst(at + Vector3(0, 40, 0), 40, Color(1.0, 0.6, 0.15), Color(0.9, 0.15, 0.0, 0.0), 26.0, 260.0, 0.7, -120.0)
			_burst(at + Vector3(0, 50, 0), 26, Color(0.25, 0.24, 0.23, 0.8), Color(0.1, 0.1, 0.1, 0.0), 42.0, 60.0, 2.6, 40.0)
			_word("KABOOM!", at + Vector3(0, 170, 0), Color("ffb13b"), 1.8, 1.4)
		"SHOCK":
			_flash(at + Vector3(0, 80, 0), Color(0.6, 0.9, 1.0), 5.0, 1.1, true)
			_burst(at + Vector3(0, 70, 0), 34, Color(0.85, 0.97, 1.0), Color(0.4, 0.8, 1.0, 0.0), 4.0, 220.0, 0.35, -200.0)
			_word("BZZZT!", at + Vector3(0, 175, 0), Color("9df4ff"), 1.6)
		"SPRING":
			_burst(at + Vector3(0, 10, 0), 14, Color(0.6, 0.58, 0.55, 0.6), Color(0.6, 0.58, 0.55, 0.0), 16.0, 70.0, 0.7, 0.0)
			_word("BOING!", at + Vector3(0, 175, 0), Color("ffd23f"), 1.4)
		"WIRE":
			_word("TWANG!", at + Vector3(0, 160, 0), Color("eef1f5"), 1.4)
		"DOWN":
			_flash(at + Vector3(0, 60, 0), Color(1.0, 0.9, 0.6), 3.0, 0.5)
			_burst(at + Vector3(0, 60, 0), 18, Color(1.0, 0.85, 0.2), Color(1.0, 0.85, 0.2, 0.0), 8.0, 180.0, 0.4, 0.0)
			_word("WHAM!", at + Vector3(0, 165, 0), Color("ff5a5f"), 1.4)
		"HIT":
			_burst(at + Vector3(0, 75, 0), 12, Color(1.0, 0.9, 0.4), Color(1.0, 0.9, 0.4, 0.0), 6.0, 160.0, 0.3, 0.0)
		"PUFF":
			_burst(at + Vector3(0, 20, 0), 14, Color(0.6, 0.58, 0.55, 0.5), Color(0.6, 0.58, 0.55, 0.0), 18.0, 50.0, 0.8, 20.0)
		"PAPER":
			_paper(at + Vector3(0, float(e.get("z", 50.0)) + 6.0, 0), int(e.get("seed", 0)))
		"FOUND":
			var item: String = e.get("item", "")
			_word(item + "!", at + Vector3(0, float(e.get("z", 50.0)) + 40.0, 0), Color(1.0, 0.92, 0.55), 1.6, 0.5)


## A light that blazes and dies away (flickering, for electricity).
func _flash(at: Vector3, col: Color, energy: float, seconds: float, flicker := false) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = 900.0
	l.omni_attenuation = 0.6
	l.position = at
	add_child(l)
	var tw := create_tween()
	if flicker:
		for i in 8:
			tw.tween_property(l, "light_energy", energy * (0.2 if i % 2 == 0 else 1.0), seconds / 8.0)
	tw.tween_property(l, "light_energy", 0.0, seconds * 0.5)
	tw.tween_callback(l.queue_free)


## A one-shot burst of soft round particles: sparks, fire, smoke or dust.
## `gravity` pulls them down (negative) or lifts them (positive).
func _burst(at: Vector3, amount: int, start: Color, end: Color, size: float, speed: float, life: float,
		gravity: float) -> void:
	var cp := CPUParticles3D.new()
	cp.position = at
	cp.amount = amount
	cp.one_shot = true
	cp.explosiveness = 0.95
	cp.lifetime = life
	cp.direction = Vector3.UP
	cp.spread = 180.0
	cp.initial_velocity_min = speed * 0.4
	cp.initial_velocity_max = speed
	cp.gravity = Vector3(0, gravity, 0)
	cp.scale_amount_min = 0.6
	cp.scale_amount_max = 1.4
	var g := Gradient.new()
	g.set_color(0, start)
	g.set_color(1, end)
	cp.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = preload("res://scripts/render/art.gd").soft()
	q.material = m
	cp.mesh = q
	cp.emitting = true
	add_child(cp)
	get_tree().create_timer(life + 0.5).timeout.connect(cp.queue_free)


## A comic-book word that pops up and floats away.
func _word(text: String, at: Vector3, col: Color, seconds: float, size := 1.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = Style.stencil()
	l.font_size = 96
	l.pixel_size = 0.32 * size
	l.outline_size = 18
	l.outline_modulate = Color.BLACK
	l.modulate = col
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = at
	l.scale = Vector3.ONE * 0.3
	add_child(l)
	var tw := create_tween().set_parallel()
	tw.tween_property(l, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position", at + Vector3(0, 40, 0), seconds)
	tw.tween_property(l, "modulate:a", 0.0, 0.4).set_delay(seconds - 0.4)
	tw.chain().tween_callback(l.queue_free)


## A sheet of paper flung out of furniture being searched.
func _paper(at: Vector3, seed_v: int) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(14, 10)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.94, 0.92, 0.84)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.position = at
	add_child(mi)
	var ang := float(seed_v % 628) / 100.0
	var out := Vector3(cos(ang), 0, sin(ang)) * (40.0 + float(seed_v % 50))
	var tw := create_tween().set_parallel()
	tw.tween_property(mi, "position", at + out + Vector3(0, 30, 0), 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "rotation", Vector3(ang * 3.0, ang, ang * 2.0), 0.9)
	tw.chain().tween_property(mi, "position:y", 1.0, 0.6).set_ease(Tween.EASE_IN)
	tw.chain().tween_interval(0.6)
	tw.chain().tween_callback(mi.queue_free)
