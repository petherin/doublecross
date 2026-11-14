extends RefCounted
## Short-lived visual effects in the rooms: trap explosions, spring launches,
## tripwire twangs, cosh hits, vent dust, plus the comic-book words that go
## with them. The room view asks for the ones in the room it's drawing.

const World = preload("res://scripts/core/world.gd")
const Style = preload("res://scripts/ui/style.gd")

## { kind, room, pos, t }
var _effects: Array = []


func add(kind: String, room: Vector2i, pos: Vector2) -> void:
	_effects.append({"kind": kind, "room": room, "pos": pos, "t": 0.0})


## Ages every effect and drops the finished ones.
func tick(delta: float) -> void:
	for e in _effects:
		e["t"] += delta
	_effects = _effects.filter(func(e): return e["t"] < life(e["kind"]))


func in_room(room: Vector2i) -> Array:
	return _effects.filter(func(e): return e["room"] == room)


static func life(kind: String) -> float:
	match kind:
		"BOMB": return 3.2
		"HIT": return 0.5
		"PUFF": return 0.7
		_: return 1.6


func draw(ci: CanvasItem, e: Dictionary) -> void:
	var t: float = e["t"]
	var p := World.iso(e["pos"], 40.0)
	var font := Style.stencil()
	var word := "TWANG!"
	var col := Color("eef1f5")
	match e["kind"]:
		"PUFF":
			# Dust kicked out of a vent.
			var k := t / 0.7
			for i in 10:
				var ang := i * 2.4
				var q := World.iso(e["pos"], 20.0 + 30.0 * k) + Vector2(cos(ang), sin(ang) * 0.5) * (12.0 + 40.0 * k)
				ci.draw_circle(q, 8.0 + 10.0 * k, Color(0.6, 0.58, 0.55, 0.45 * (1.0 - k)))
			return
		"HIT":
			# Quick impact burst.
			var k := t / 0.5
			for i in 8:
				var a := i * TAU / 8.0
				var ray := Vector2.from_angle(a)
				ci.draw_line(p + ray * (12.0 + 30.0 * k), p + ray * (20.0 + 44.0 * k), Color(1, 0.9, 0.4, 1.0 - k), 3.0, true)
			return
		"DOWN":
			word = "WHAM!"
			col = Color("ff5a5f")
			var k := minf(1.0, t * 5.0)
			var pts := PackedVector2Array()
			for i in 16:
				var r := (60.0 if i % 2 == 0 else 30.0) * k
				pts.append(p + Vector2.from_angle(i * TAU / 16.0) * r)
			ci.draw_colored_polygon(pts, Color(1, 0.85, 0.2, clampf(1.6 - t, 0.0, 1.0) * 0.8))
		"BOMB":
			word = "KABOOM!"
			col = Color("ffb13b")
			_draw_explosion(ci, e)
		"SPRING":
			word = "BOING!"
			col = Color("ffd23f")
			var base := World.iso(e["pos"])
			var coil := PackedVector2Array()
			var hgt := minf(1.0, t * 5.0) * 70.0
			for i in 11:
				coil.append(base + Vector2(10 if i % 2 == 0 else -10, -i * hgt / 10.0))
			ci.draw_polyline(coil, Color("c7ccd6"), 3.0, true)
	# Comic-book word that pops and floats up
	var size := int(40 + 20 * minf(1.0, t * 8.0))
	var a := clampf(life(e["kind"]) - 0.4 - t, 0.0, 1.0)
	if e["kind"] == "BOMB":
		size = int(52 + 26 * minf(1.0, t * 8.0))
		p.y -= 50.0
	var w := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at := p + Vector2(-w / 2, -60 - t * 40)
	ci.draw_string_outline(font, at, word, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 10, Color(0, 0, 0, a))
	ci.draw_string(font, at, word, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(col, a))


## A fiery, smoky blast: flash, fireball, flying sparks, then rolling smoke.
func _draw_explosion(ci: CanvasItem, e: Dictionary) -> void:
	var t: float = e["t"]
	var ground := World.iso(e["pos"])
	var c := World.iso(e["pos"], 45.0)
	var seed_v := int(e["pos"].x * 7.0 + e["pos"].y * 13.0)
	# 1) White-hot flash
	if t < 0.18:
		var f := t / 0.18
		ci.draw_circle(c, 40.0 + f * 120.0, Color(1.0, 0.97, 0.8, 0.85 * (1.0 - f)))
	# 2) Sparks and debris flying out
	if t < 0.9:
		for i in 16:
			var ang := i * TAU / 16.0 + float((seed_v + i * 31) % 10) * 0.05
			var spd := 160.0 + float((seed_v + i * 17) % 90)
			var d := spd * t
			var start := c + Vector2(cos(ang), sin(ang) * 0.7) * d
			var tail := c + Vector2(cos(ang), sin(ang) * 0.7) * maxf(0.0, d - 22.0)
			var fall := Vector2(0, 160.0 * t * t)
			ci.draw_line(tail + fall, start + fall, Color(1.0, 0.75, 0.25, 1.0 - t / 0.9), 3.0, true)
	# 3) Smoke: dark puffs that billow up and spread out
	if t > 0.12:
		var st := t - 0.12
		for i in 22:
			var k := float((seed_v + i * 53) % 100) / 100.0
			var born := k * 0.35
			if st < born:
				continue
			var age := st - born
			var drift := Vector2((k - 0.5) * 120.0 + sin(age * 2.0 + i) * 14.0, -40.0 - age * (55.0 + k * 40.0))
			var r := 18.0 + age * 26.0 + k * 10.0
			var a := clampf(1.0 - age / 2.7, 0.0, 1.0) * 0.75
			var grey := 0.1 + k * 0.16
			ci.draw_circle(c + drift, r, Color(grey, grey * 0.96, grey * 0.93, a))
	# 4) Fireball: layered, flickering, swelling then collapsing into the smoke
	if t < 0.75:
		var grow := minf(1.0, t / 0.12)
		var fade := 1.0 - clampf((t - 0.25) / 0.5, 0.0, 1.0)
		var layers := [[Color("ff3b1f"), 1.0], [Color("ff7a1a"), 0.78], [Color("ffb13b"), 0.55], [Color("fff1a8"), 0.3]]
		for li in layers.size():
			var lc: Color = layers[li][0]
			var lr: float = layers[li][1]
			for j in 7:
				var ang := j * TAU / 7.0 + t * 3.0 + li
				var wob := 0.75 + 0.25 * sin(t * 40.0 + j * 2.1 + li)
				var off := Vector2(cos(ang), sin(ang) * 0.75) * 34.0 * lr * grow
				ci.draw_circle(c + off - Vector2(0, t * 30.0), 46.0 * lr * grow * wob, Color(lc, fade))
	# 5) Ground glow
	if t < 0.6:
		ci.draw_set_transform(ground, 0.0, Vector2(1.0, 0.5))
		ci.draw_circle(Vector2.ZERO, 110.0, Color(1.0, 0.5, 0.15, 0.35 * (1.0 - t / 0.6)))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Black scorch mark left on the floor by a bomb (fades with the smoke).
func draw_scorch(ci: CanvasItem, e: Dictionary) -> void:
	var t: float = e["t"]
	var a := clampf(minf(t * 6.0, (3.2 - t) / 1.2), 0.0, 1.0)
	var g := World.iso(e["pos"])
	ci.draw_set_transform(g, 0.0, Vector2(1.0, 0.5))
	ci.draw_circle(Vector2.ZERO, 70.0, Color(0.05, 0.04, 0.03, 0.55 * a))
	for i in 9:
		var ang := i * TAU / 9.0
		ci.draw_line(Vector2.from_angle(ang) * 50.0, Vector2.from_angle(ang) * 95.0, Color(0.05, 0.04, 0.03, 0.4 * a), 7.0)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
