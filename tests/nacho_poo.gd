extends SceneTree
## Headless regression for Nacho's poo: he squats, leaves a turd that stays
## put, stops (and goes for them) if anyone starts on him or his agent mid-
## poo, won't start while he's fighting, and anyone who treads in a turd
## slips and is taken out, losing everything they carry.
##   godot --headless --fixed-fps 60 -s res://tests/nacho_poo.gd

const World = preload("res://scripts/core/world.gd")

var g: Node
var _f := 0
var _failures := 0
var _poo_frame := 0


func _process(_d: float) -> bool:
	if g == null:
		g = load("res://scripts/game/game.gd").new()
		root.add_child(g)
		g.setup(7, 1, [1, 5], "", 6, {1: "ME", 5: "RIVAL"})
		return false
	_f += 1
	var me: Node = g.local_agent
	var rival: Node = g.agent_of(5)
	var kr: Vector2i = g.world.kennel[0]
	var poo_frames := int(g.dog.POO_TIME * 60.0)
	if _f == 10:
		for a in g.agents:
			a.frozen = false
		me.room = kr
		me.position = g.dog.kennel_front() + Vector2(160, 160)
		rival.room = _other_room(kr)
		g.referee.handle_search(1, kr, g.world.kennel[1])
	if _f == 120:
		g.referee.poo_now()
	if _f == 125:
		_check(g.dog.is_pooing(), "he stops for a poo")
		_poo_frame = _f
	if _poo_frame > 0 and _f == _poo_frame + poo_frames + 30:
		_check(not g.dog.is_pooing() and g.turds.size() == 1, "and leaves a turd")
		_check(g.turds[0]["room"] == kr, "where he was")
		# Again, but this time the rival starts on his agent mid-poo.
		g.referee.poo_now()
	if _poo_frame > 0 and _f == _poo_frame + poo_frames + 60:
		_check(g.dog.is_pooing(), "a second poo starts")
		rival.room = kr
		rival.position = me.position + Vector2(60, 0)
		g.referee.handle_hit(5, 1, "melee")
	if _poo_frame > 0 and _f == _poo_frame + poo_frames + 66:
		_check(not g.dog.is_pooing() and g.dog.foe_id == 5, "attacked mid-poo: he stops and goes for them")
		# He won't start one while he's fighting.
		g.referee.poo_now()
	if _poo_frame > 0 and _f == _poo_frame + poo_frames + 72:
		_check(not g.dog.is_pooing(), "and won't start one while he's fighting")
	if _poo_frame > 0 and _f == _poo_frame + 2 * poo_frames + 90:
		_check(g.turds.size() == 1, "the interrupted poo left nothing")
		# Somebody treads in it, carrying everything.
		g.inventories[5]["items"] = ["CASH"]
		g.inventories[5]["case"] = true
		g.inventories[5]["gadgets"] = ["TOOLKIT"]
		g.contents.erase(_key_holding("CASH"))
		rival.protect_time = 0.0
		rival.ko_time = 0.0
		rival.room = kr
		rival.position = g.turds[0]["pos"]
	if _poo_frame > 0 and _f == _poo_frame + 2 * poo_frames + 92:
		var inv: Dictionary = g.inventories[5]
		_check(rival.ko_time > 0.0, "treading in it: slip, fall, taken out")
		_check(inv["items"].is_empty() and not inv["case"] and inv["gadgets"].is_empty(), "losing everything")
		var hidden: Array = g.contents.values()
		_check("CASH" in hidden and "BRIEFCASE" in hidden and "TOOLKIT" in hidden, "which is hidden again")
		_check(g.turds.size() == 1, "the turd stays where it is")
		# His own agent isn't safe either.
		me.protect_time = 0.0
		me.ko_time = 0.0
		me.position = g.turds[0]["pos"]
	if _poo_frame > 0 and _f == _poo_frame + 2 * poo_frames + 94:
		_check(me.ko_time > 0.0, "his own agent slips too")
		_check(g.dog.owner_id == 0, "and Nacho goes home")
		print("nacho_poo: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
		g.queue_free()
		quit(0 if _failures == 0 else 1)
		return true
	if _f > 60 * 60:
		print("FAIL: timed out")
		quit(1)
		return true
	return false


func _other_room(not_this: Vector2i) -> Vector2i:
	for r in g.world.rooms:
		if r != not_this:
			return r
	return not_this


func _key_holding(item: String) -> String:
	for k in g.contents:
		if g.contents[k] == item:
			return k
	return ""


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", what)
