extends RefCounted
## Shared textures, built or loaded once and cached: the Blender-rendered
## floor and wall surfaces (with normal maps), and procedural soft light,
## vignette, grain and wood textures.

## The room textures are rendered at 2 pixels per game unit.
const ROOM_TEX_SCALE := 0.5

static var _cache := {}


## Steel tread plate, tiling every 128 floor units.
static func floor_tex() -> Texture2D:
	return _room_tex("floor")


## Riveted wall panels, tiling every 128 units along a wall, WALL_H high.
static func wall_tex() -> Texture2D:
	return _room_tex("wall")


## A colour texture with its normal map, so the room's lights shade it.
static func _room_tex(name: String) -> Texture2D:
	if not _cache.has(name):
		var ct := CanvasTexture.new()
		ct.diffuse_texture = load("res://assets/sprites/room/%s.png" % name)
		ct.normal_texture = load("res://assets/sprites/room/%s_n.png" % name)
		ct.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		_cache[name] = ct
	return _cache[name]


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
## 256x256 noise: white and black specks with random alpha, for film grain.
static func grain() -> Texture2D:
	if not _cache.has("grain"):
		var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for y in 256:
			for x in 256:
				var v := 1.0 if rng.randf() < 0.5 else 0.0
				img.set_pixel(x, y, Color(v, v, v, rng.randf()))
		_cache["grain"] = ImageTexture.create_from_image(img)
	return _cache["grain"]


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
