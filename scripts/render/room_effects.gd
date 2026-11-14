extends RefCounted
## Short-lived visual effects in the rooms: trap explosions, spring launches,
## tripwire twangs, cosh hits, vent dust, plus the comic-book words that go
## with them. The room view asks for the ones in the room it's drawing.

const World = preload("res://scripts/core/world.gd")
const Style = preload("res://scripts/ui/style.gd")
const Icons = preload("res://scripts/ui/icons.gd")

## { kind, room, pos, t }
var _effects: Array = []


## `extra` adds fields some effects need ("z" height, "seed", "item").
func add(kind: String, room: Vector2i, pos: Vector2, extra := {}) -> void:
	var e := {"kind": kind, "room": room, "pos": pos, "t": 0.0}
	e.merge(extra)
	_effects.append(e)


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
		"PAPER": return 0.9
		"FOUND": return 1.6
		_: return 1.6


func draw(ci: CanvasItem, e: Dictionary) -> void:
	var t: float = e["t"]
	var p := World.iso(e["pos"], 40.0)
	var font := Style.stencil()
	var word := "TWANG!"
	var col := Color("eef1f5")
	match e["kind"]:
		"PAPER":
			_draw_paper(ci, e)
			return
		"FOUND":
			_draw_found(ci, e)
			return
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
		"SHOCK":
			word = "BZZZT!"
			col = Color("9df4ff")
			_draw_arcs(ci, e)
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


## A sheet of paper flung out of furniture being searched, tumbling down.
func _draw_paper(ci: CanvasItem, e: Dictionary) -> void:
	var t: float = e["t"]
	var sd: int = e.get("seed", 0)
	var ang := float(sd % 628) / 100.0
	var speed := 50.0 + float((sd / 7) % 60)
	var drift := Vector2(cos(ang), sin(ang) * 0.5) * speed * t
	var rise := 90.0 * t - 160.0 * t * t
	var at := World.iso(e["pos"], float(e.get("z", 50.0)) + 8.0) + drift - Vector2(0, rise)
	var a := clampf((0.9 - t) / 0.3, 0.0, 1.0)
	var spin := t * (6.0 if sd % 2 == 0 else -6.0) + ang
	ci.draw_set_transform(at, spin, Vector2(1.0, 0.55 + 0.45 * absf(sin(t * 9.0))))
	ci.draw_rect(Rect2(-9, -6.5, 18, 13), Color(0.94, 0.92, 0.84, a))
	for k in 3:
		ci.draw_line(Vector2(-6, -3.5 + k * 3.5), Vector2(5, -3.5 + k * 3.5), Color(0.2, 0.2, 0.25, 0.6 * a), 1.2)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## What you just found pops up out of the furniture, glowing, and floats away.
func _draw_found(ci: CanvasItem, e: Dictionary) -> void:
	var t: float = e["t"]
	var pop := minf(1.0, t / 0.18)
	var s := 34.0 * (pop * 1.25 if t < 0.18 else lerpf(1.25, 1.0, minf(1.0, (t - 0.18) / 0.15)))
	var a := clampf((1.6 - t) / 0.5, 0.0, 1.0)
	var at := World.iso(e["pos"], float(e.get("z", 50.0)) + 34.0 + 46.0 * minf(1.0, t / 0.5) + 14.0 * t)
	ci.draw_circle(at, s * 0.9, Color(1.0, 0.92, 0.55, 0.28 * a))
	ci.draw_circle(at, s * 0.62, Color(0.08, 0.08, 0.1, 0.7 * a))
	for i in 8:
		var ray := Vector2.from_angle(i * TAU / 8.0 + t * 1.5)
		var tip := at + ray * s * (0.95 + 0.15 * sin(t * 12.0 + i))
		ci.draw_line(at + ray * s * 0.75, tip, Color(1.0, 0.9, 0.5, 0.7 * a), 2.0, true)
	if a > 0.0:
		Icons.draw(ci, e.get("item", ""), at, s * 0.85, true)


## Jagged electric arcs crackling out from a shocked agent, re-drawn 30
## times a second so they flicker.
func _draw_arcs(ci: CanvasItem, e: Dictionary) -> void:
	var t: float = e["t"]
	if t > 1.1:
		return
	var c := World.iso(e["pos"], 55.0)
	var frame := floorf(t * 30.0)
	var fade := 1.0 - t / 1.1
	for i in 7:
		var ang := i * TAU / 7.0 + sin(frame * 1.7 + i) * 0.4
		var len := 40.0 + 50.0 * fposmod(sin(frame * 2.3 + i * 3.1) * 0.5 + 0.5, 1.0)
		var pts := PackedVector2Array([c])
		for k in range(1, 6):
			var along := c + Vector2.from_angle(ang) * (len * k / 5.0)
			var jag := Vector2.from_angle(ang + PI / 2) * sin(frame * 3.7 + i * 2.9 + k * 5.3) * 9.0
			pts.append(along + jag)
		ci.draw_polyline(pts, Color(0.75, 0.95, 1.0, 0.9 * fade), 3.0, true)
		ci.draw_polyline(pts, Color(1, 1, 1, 0.9 * fade), 1.2, true)
	ci.draw_circle(c, 18.0 + 6.0 * sin(frame), Color(0.7, 0.95, 1.0, 0.35 * fade))


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
