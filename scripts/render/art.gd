extends RefCounted
## Procedurally generated textures, built once and cached. No image files
## needed: the floor plates, wall panels and soft light/shadow sprites are
## all made here from noise and simple shapes.

static var _cache := {}


static func floor_tex() -> Texture2D:
	if not _cache.has("floor"):
		_cache["floor"] = ImageTexture.create_from_image(_floor_image())
	return _cache["floor"]


static func wall_tex() -> Texture2D:
	if not _cache.has("wall"):
		_cache["wall"] = ImageTexture.create_from_image(_wall_image())
	return _cache["wall"]


## Dark wood grain for the desk under the case file.
static func wood_tex() -> Texture2D:
	if not _cache.has("wood"):
		var w := 256
		var h := 256
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		var n := FastNoiseLite.new()
		n.seed = 21
		n.frequency = 0.02
		var fine := FastNoiseLite.new()
		fine.seed = 5
		fine.frequency = 0.35
		for y in h:
			for x in w:
				var grain := sin((x * 0.05 + n.get_noise_2d(x * 0.3, y * 2.0) * 6.0) * 6.0) * 0.5 + 0.5
				var v := 0.16 + grain * 0.06 + fine.get_noise_2d(x * 0.2, y * 3.0) * 0.025
				img.set_pixel(x, y, Color(v * 1.25, v * 0.82, v * 0.55))
		_cache["wood"] = ImageTexture.create_from_image(img)
	return _cache["wood"]


## White radial blob fading to transparent: used for lights and soft shadows.
static func soft() -> Texture2D:
	if not _cache.has("soft"):
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.45))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		_cache["soft"] = t
	return _cache["soft"]


## Dark edges for the whole screen.
static func vignette() -> Texture2D:
	if not _cache.has("vignette"):
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0))
		g.set_color(1, Color(0, 0, 0, 0.75))
		g.add_point(0.55, Color(0, 0, 0, 0.0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.05, 0.5)
		t.width = 256
		t.height = 256
		_cache["vignette"] = t
	return _cache["vignette"]


# Steel tread plate: raised diagonal bars, plate seams, rivets and grime.
static func _floor_image() -> Image:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var grime := FastNoiseLite.new()
	grime.seed = 7
	grime.frequency = 0.035
	var fine := FastNoiseLite.new()
	fine.seed = 11
	fine.frequency = 0.5
	var corners := [Vector2(6, 6), Vector2(n - 7, 6), Vector2(6, n - 7), Vector2(n - 7, n - 7)]
	for y in n:
		for x in n:
			var v := 0.15 + grime.get_noise_2d(x, y) * 0.035 + fine.get_noise_2d(x, y) * 0.018
			var cx := x % 16
			var cy := y % 16
			var flip := ((x / 16) + (y / 16)) % 2 == 0
			var d: int = absi(cx - cy) if flip else absi(cx + cy - 15)
			if cx > 2 and cx < 13 and cy > 2 and cy < 13:
				if d <= 1:
					v += 0.045
				elif d == 2:
					v -= 0.02
			# Plate seams with a bevel highlight.
			if x == 0 or y == 0:
				v = 0.05
			elif x == 1 or y == 1:
				v += 0.05
			elif x == n - 1 or y == n - 1:
				v -= 0.03
			for c in corners:
				var dist := Vector2(x, y).distance_to(c)
				if dist < 2.2:
					v = 0.3 - dist * 0.05
				elif dist < 3.2:
					v = 0.07
			# A few scratches.
			if (x * 7 + y * 3) % 97 == 0 and fine.get_noise_2d(x * 3, y) > 0.2:
				v += 0.06
			img.set_pixel(x, y, Color(v, v * 1.02, v * 1.08))
	return img


# Riveted steel wall panels with a seam, vents of light and grime at the bottom.
static func _wall_image() -> Image:
	var w := 128
	var h := 112
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var grime := FastNoiseLite.new()
	grime.seed = 3
	grime.frequency = 0.05
	for y in h:
		for x in w:
			var v := 0.2 + grime.get_noise_2d(x, y * 2) * 0.025
			# Bottom grime and top light.
			v -= clampf((y - 80) / 32.0, 0.0, 1.0) * 0.06
			v += clampf((20 - y) / 20.0, 0.0, 1.0) * 0.03
			# Panel bevels.
			if x <= 1 or y <= 1:
				v = 0.3
			elif x >= w - 2 or y >= h - 2:
				v = 0.09
			elif y == 56 or y == 57:
				v = 0.11 if y == 56 else 0.27
			# Bolts.
			for b in [
					Vector2(8, 8), Vector2(w - 9, 8), Vector2(8, h - 9),
					Vector2(w - 9, h - 9), Vector2(8, 50), Vector2(w - 9, 50)]:
				var dist := Vector2(x, y).distance_to(b)
				if dist < 2.0:
					v = 0.36
				elif dist < 2.8:
					v = 0.1
			img.set_pixel(x, y, Color(v * 0.95, v, v * 1.1))
	return img
