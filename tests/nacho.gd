extends SceneTree
## Headless regression for Nacho the dog: finding him in his kennel, his
## nose (barks at hidden things, growls at traps, never sets them off),
## following his agent to the next room, going for (and only for as long as)
## anyone who attacks his agent or him, and running home when his agent is
## taken out.
##   godot --headless --fixed-fps 60 -s res://tests/nacho.gd

const World = preload("res://scripts/core/world.gd")

var g: Node
var _f := 0
var _failures := 0
var _item_key := ""
var _trap_key := ""
var _rival_hp := 0


func _process(_d: float) -> bool:
	if g == null:
		g = load("res://scripts/game/game.gd").new()
		root.add_child(g)
		# Two players, no bots: agent 5 stands in for a rival on another device.
		g.setup(7, 1, [1, 5], "", 6, {1: "ME", 5: "RIVAL"})
		return false
	_f += 1
	var me: Node = g.local_agent
	var kr: Vector2i = g.world.kennel[0]
	if _f == 10:
		for a in g.agents:
			a.frozen = false
		me.room = kr
		me.position = g.dog.kennel_front() + Vector2(160, 140)
		_check(g.dog.owner_id == 0 and g.dog.room == kr, "Nacho starts at home")
		g.referee.handle_search(1, kr, g.world.kennel[1])
		_check(g.dog.owner_id == 1, "searching the kennel finds him")
		g.referee.handle_search(5, kr, g.world.kennel[1])
		_check(g.dog.owner_id == 1, "nobody else can take him")
		# Something to find and something to avoid, near where we stand.
		var keys := []
		for i in g.world.furniture(kr).size():
			if not g.world.is_kennel(kr, i):
				keys.append(World.furniture_key(kr, i))
		keys.sort_custom(func(a, b): return _dist(a) < _dist(b))
		_item_key = keys[0]
		_trap_key = keys[1]
		g.contents.erase(_trap_key)
		g.contents[_item_key] = "CASH"
		g.traps[_trap_key] = {"kind": "BOMB", "owner": 5}
	if _f == 60 * 40:
		_check(g.dog.flags.get(_item_key, "") == "item", "he barks at the hidden CASH")
		_check(g.dog.flags.get(_trap_key, "") == "trap", "he growls at the bomb")
		_check(g.traps.has(_trap_key), "and doesn't set it off")
		# Through a door: he follows into the next room.
		var next := kr
		for dir in World.DIR_VEC:
			if g.world.has_door(kr, dir):
				next = kr + World.DIR_VEC[dir]
				break
		me.room = next
		me.position = World.ROOM.get_center()
	if _f == 60 * 41:
		_check(g.dog.room == me.room, "he follows to the next room")
		# A rival attacks: the blow lands, and Nacho goes for them.
		var rival: Node = g.agent_of(5)
		rival.room = me.room
		rival.position = me.position + Vector2(60, 0)
		var hp: int = g.inventories[1]["hp"]
		g.referee.handle_hit(5, 1, "melee")
		_check(g.inventories[1]["hp"] == hp - 1, "blows on his agent still land")
		_check(g.dog.foe_id == 5, "and Nacho goes for the attacker")
		_rival_hp = g.inventories[5]["hp"]
	if _f == 60 * 43:
		_check(g.inventories[5]["hp"] < _rival_hp, "he bites them")
	if _f == 60 * 48:
		# They've stopped attacking for a few seconds: so has he.
		_check(g.dog.foe_id == 0, "he backs off once they stop")
		var hp5: int = g.inventories[5]["hp"]
		# Attacking Nacho himself does nothing to him, but sets him on you.
		g.referee.handle_hit(5, g.dog.DOG_ID, "melee")
		_check(g.dog.foe_id == 5, "attacking Nacho sets him on you")
		_check(g.inventories[1]["hp"] >= 1 and g.inventories[5]["hp"] == hp5, "and nobody's hurt by it")
	if _f == 60 * 49:
		# Taken out: he runs home to his kennel.
		for i in 3:
			g.agent_of(1).protect_time = 0.0
			g.agent_of(1).ko_time = 0.0
			g.referee.handle_hit(5, 1, "melee")
		_check(g.dog.owner_id == 0 and g.dog.room == kr, "taken out: he runs home to his kennel")
		print("nacho: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
		g.queue_free()
		quit(0 if _failures == 0 else 1)
		return true
	return false


func _dist(key: String) -> float:
	var idx := int(key.get_slice(",", 2))
	var r: Rect2 = g.world.furniture(g.world.kennel[0])[idx]["rect"]
	return r.get_center().distance_to(g.local_agent.position)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", what)
