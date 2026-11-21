extends SceneTree
## Headless regression for thrown bombs: a throw uses one of your three
## bombs and lands where aimed; a direct hit takes you out, closer than 1.5
## floor squares is two hits, closer than 2.5 squares one, further nothing;
## the thrower isn't safe; a direct hit takes Nacho out; bomb traps share
## the supply; and it refills when you're taken out.
##   godot --headless --fixed-fps 60 -s res://tests/bombs.gd

const World = preload("res://scripts/core/world.gd")

var g: Node
var _f := 0
var _failures := 0
var _room := Vector2i.ZERO


func _process(_d: float) -> bool:
	if g == null:
		g = load("res://scripts/game/game.gd").new()
		root.add_child(g)
		g.setup(7, 1, [1, 5], "", 6, {1: "ME", 5: "RIVAL"})
		return false
	_f += 1
	var me: Node = g.local_agent
	var rival: Node = g.agent_of(5)
	var c := World.ROOM.get_center()
	var land := int(g.THROW_TIME * 60.0) + 6
	if _f == 10:
		for a in g.agents:
			a.frozen = false
			a.protect_time = 0.0
		_room = g.world.start_rooms()[0]
		for a in [me, rival]:
			a.room = _room
		_put(me, c + Vector2(-200, 0))
		_put(rival, c + Vector2(200, 0))
		me.facing = 0.0
		g.inventories[5]["bombs"] = 0
		g.do_throw(1, 0.0)
		_check(g.inventories[1]["bombs"] == g.MAX_BOMBS - 1, "a throw uses a bomb")
		_check(g.flying.size() == 1, "and it's in the air")
	if _f == 10 + land:
		_check(rival.ko_time > 0.0 and rival.ko_kind == "DOWN", "a direct hit takes you out")
		_check(g.inventories[1]["hp"] == g.MAX_HP, "the thrower, 400 away, is untouched")
		_check(g.flying.is_empty(), "and the bomb's gone off")
		_check(g.inventories[5]["bombs"] == g.MAX_BOMBS, "taken out: your bombs are refilled")
		# Falloff: 150 away is two hits, 250 one, 350 none.
		for case in [[150.0, 2], [250.0, 1], [350.0, 0]]:
			_ready_for_blast(rival)
			_put(rival, c + Vector2(case[0], 0))
			g.referee._blast(1, _room, c)
			_check(g.inventories[5]["hp"] == g.MAX_HP - case[1],
					"%d away: %d hit(s)" % [int(case[0]), case[1]])
		# Too close to your own bomb: you're caught too.
		_ready_for_blast(me)
		_ready_for_blast(rival)
		_put(me, c + Vector2(-100, 0))
		_put(rival, c + Vector2(400, 0))
		g.referee._blast(1, _room, c)
		_check(g.inventories[1]["hp"] == g.MAX_HP - 2, "the thrower isn't safe")
		# Nacho, someone else's dog, in the room.
		g.referee.handle_search(5, g.world.kennel[0], g.world.kennel[1])
		_ready_for_blast(rival)
		_put(rival, c + Vector2(300, 0))
	if _f == 10 + land + 20:
		_check(g.dog.owner_id == 5 and g.dog.room == _room, "Nacho follows the rival in")
		g.referee._blast(1, _room, g.dog.position)
		_check(g.dog.owner_id == 0 and g.dog.room == g.world.kennel[0], "a direct hit takes Nacho out")
		# Bomb traps come out of the same supply.
		var key: String = World.furniture_key(_room, 0)
		g.inventories[1]["bombs"] = 0
		g.referee.handle_trap(1, {"kind": "BOMB", "key": key})
		_check(not g.traps.has(key), "no bombs, no bomb trap")
		g.inventories[1]["bombs"] = 1
		g.referee.handle_trap(1, {"kind": "BOMB", "key": key})
		_check(g.traps.has(key) and g.inventories[1]["bombs"] == 0, "a bomb trap uses a bomb")
		# And with none left, you can't throw.
		var before: int = g.flying.size()
		g.referee.handle_throw(1, c)
		_check(g.flying.size() == before, "and with none left you can't throw")
		print("bombs: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
		g.queue_free()
		quit(0 if _failures == 0 else 1)
		return true
	return false


## Puts an agent somewhere (a remote agent also needs its network target,
## or it glides back to where it was last heard of).
func _put(a: Node, p: Vector2) -> void:
	a.position = p
	a._target = p


func _ready_for_blast(a: Node) -> void:
	var id: int = g.id_of(a)
	g.inventories[id]["hp"] = g.MAX_HP
	a.ko_time = 0.0
	a.protect_time = 0.0
	a.room = _room


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", what)
