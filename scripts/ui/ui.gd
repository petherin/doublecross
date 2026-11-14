extends RefCounted
## Screen-size helpers so the game is comfortable on phones as well as tablets.
##
## The game is laid out for a 1280x800 tablet. The window stretches in
## "expand" mode, so a wide phone gets a wider view instead of black bars.
## On small physical screens the HUD and text are scaled up by `scale()`.
## For testing on a computer, run with `-- --ui-scale=1.5` to fake a phone.

const BASE := Vector2(1280, 800)

static var _cached := 0.0


## How much to enlarge HUD controls and text: 1.0 on tablets and computers,
## up to 1.6 on small phones.
static func scale() -> float:
	if _cached > 0.0:
		return _cached
	var s := 1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ui-scale="):
			_cached = maxf(0.5, a.get_slice("=", 1).to_float())
			return _cached
	if OS.has_feature("mobile"):
		var px := DisplayServer.screen_get_size()
		var dpi := float(DisplayServer.screen_get_dpi())
		if dpi > 0.0:
			# Short side of the screen in inches: ~5.3 on a 10" tablet, ~2.8 on a phone.
			var short_in := minf(px.x, px.y) / dpi
			s = clampf(4.2 / short_in, 1.0, 1.6)
	_cached = s
	return s


## The visible area in game units (wider than 1280 on a wide phone).
static func view_size(node: Node) -> Vector2:
	return node.get_viewport().get_visible_rect().size


## Offset that centres a 1280x800 layout in the visible area.
static func center_offset(node: Node) -> Vector2:
	return ((view_size(node) - BASE) / 2.0).floor()
