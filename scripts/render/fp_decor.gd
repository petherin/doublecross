extends Node2D
## Paints one wall's decorations (screens, maps, clocks, signs, posters, fuse
## boxes) into an off-screen texture for the first-person view, using the same
## drawing code and seed as the overhead view so each room looks the same.

const WallDecor = preload("res://scripts/render/wall_decor.gd")

## Texture pixels per game unit.
const PX := 2.0
## Decorations hang within this height of the floor (the overhead walls' height).
const BAND_H := 110.0

## Animation time for the screens (refresh() repaints at a new time).
var t := 0.0
var _spans: Array = []
var _tint := Color.WHITE
var _wall := 0
var _seed := 0
var _room := Vector2i.ZERO


## Paints the decor along a wall `length` units long, with decorations kept
## clear of `spans` gaps (doorways), and returns the painter: its texture()
## is the picture. The viewport is parented to `host`, so it goes when the
## room is rebuilt.
static func paint(host: Node, length: float, spans: Array, tint: Color, wall: int,
		seed_value: int, room: Vector2i) -> Node2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(int(length * PX), int(BAND_H * PX))
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var painter := new()
	painter._spans = spans
	painter._tint = tint
	painter._wall = wall
	painter._seed = seed_value
	painter._room = room
	vp.add_child(painter)
	host.add_child(vp)
	return painter


## The painted wall, as a texture.
func texture() -> Texture2D:
	return (get_parent() as SubViewport).get_texture()


## Repaints the wall at animation time `time` (screens scroll and sweep).
func refresh(time: float) -> void:
	t = time
	queue_redraw()
	(get_parent() as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE


func _draw() -> void:
	# Wall space is (distance along the wall, -height above the floor).
	var xf := Transform2D(0.0, Vector2(PX, PX), 0.0, Vector2(0.0, BAND_H * PX))
	WallDecor.draw(self, xf, _spans, _tint, _wall, _seed, _room, t)
