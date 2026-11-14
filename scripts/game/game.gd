extends Node2D
## One match: builds the base, spawns the agents, wires up the HUD and runs
## the rules.
##
## The host is the referee (referee.gd). Players (and bots) ask the host to search,
## set a trap, walk through a door or escape; the host decides what happens,
## updates the match state and broadcasts the whole state plus an "event"
## describing what just happened. Every tablet then shows that event.
## Each tablet only draws the room its own agent is in.

signal leave_requested
signal rematch_requested
## Every match event, after it's been applied (handy for tests and effects).
signal event_happened(event: Dictionary)

const World = preload("res://scripts/core/world.gd")
const Agent = preload("res://scripts/game/agent.gd")
const RoomView = preload("res://scripts/render/room_view.gd")
const Hud = preload("res://scripts/ui/hud/hud.gd")
const Ui = preload("res://scripts/ui/ui.gd")
const Bot = preload("res://scripts/game/bot.gd")
const Referee = preload("res://scripts/game/referee.gd")
const EventPresenter = preload("res://scripts/game/event_presenter.gd")

## Peer ids of computer-controlled rivals in one-player games: 2, 3, 4.
const FIRST_BOT_ID := 2

const SEARCH_TIME := 0.8
const TRAP_TIME := 1.2
const SEARCH_REACH := 46.0
const DOOR_REACH := 120.0
const KO_TIME := 4.0
const MAX_TRAPS := 3

# Combat and clocks
const TIME_LIMIT := 360.0       # each agent's clock, in seconds
const TRAP_PENALTY := 20.0      # seconds lost when caught by a trap
const DOWN_PENALTY := 30.0      # seconds lost when taken out in a fight
const DOWN_TIME := 3.0
const PROTECT_TIME := 3.0       # can't be hit for this long after getting up
const MAX_HP := 3
const MAX_DARTS := 3
const MELEE_RANGE := 85.0
const MELEE_COOLDOWN := 0.55
const DART_COOLDOWN := 0.7
const DART_SPEED := 950.0
const AIM_CONE := 0.6           # auto-aim at a rival within this angle (radians)
const CRAWL_TIME := 2.4         # seconds spent crawling through an air duct

const STYLES := [
	{"name": "AGENT CRIMSON", "accent": Color("ff5a5f"), "sheet": "crimson"},
	{"name": "AGENT COBALT", "accent": Color("5ab0ff"), "sheet": "cobalt"},
	{"name": "AGENT AMBER", "accent": Color("ffbf3a"), "sheet": "amber"},
	{"name": "AGENT JADE", "accent": Color("4fe39a"), "sheet": "jade"},
]

var world: World
var local_agent: Agent
var agents: Array[Agent] = []
var my_id := 1

# ---- Match state (owned by the host, mirrored on every tablet) ----
## What's in each piece of furniture: furniture_key -> item.
var contents := {}
## peer id -> { "items": [intel...], "case": bool, "gadgets": [gadget...] }
var inventories := {}
## furniture_key or door_key -> { "kind": "BOMB"|"SPRING"|"WIRE", "owner": peer id }
var traps := {}
var over := false
## peer id -> seconds left on that agent's clock (host counts down, syncs).
var clocks := {}

## Bot id -> its brain (one-player games only).
var bots := {}
## Agents knocked out of the match (clock ran out, or left): peer id -> true.
var eliminated := {}
## Darts in flight: { owner, room, pos, vel, live } (live = this device checks hits)
var darts: Array = []
var time_limit := TIME_LIMIT
## Vent shortcuts the local player has been through: [vent index, partner].
var known_vents: Array = []
## The rulebook (used by the host, and by every device for its own bots).
var referee := Referee.new(self)
## Turns events into animations, messages and sounds on this device.
var presenter := EventPresenter.new(self)
var view: RoomView
var hud: Hud
var _agent_by_id := {}
var _exit_cooldown := 0.0
var _rng := RandomNumberGenerator.new()
var _start_room := {}
var _melee_cd := 0.0
var _dart_cd := 0.0
var _step_t := {}
var _was_searching := {}
var _last_tick := -1


## `ids` holds every human peer id in the match; the host (lowest id, 1)
## is Crimson. With a `bot_level`, `bot_count` computer rivals join in.
func setup(seed_value: int, p_my_id: int, ids: Array, bot_level := "", minutes := 6, names := {},
		bot_count := 1) -> void:
	my_id = p_my_id
	time_limit = minutes * 60.0
	_rng.randomize()
	var bot_ids := []
	if bot_level != "":
		for b in clampi(bot_count, 1, World.MAX_PLAYERS - ids.size()):
			bot_ids.append(FIRST_BOT_ID + b)
	ids = ids + bot_ids
	ids.sort()
	world = World.new(seed_value, ids.size())
	contents = world.hidden.duplicate()
	# Darken the world a touch so the room's lights have something to do.
	var ambient := CanvasModulate.new()
	ambient.color = Color(0.66, 0.68, 0.76)
	add_child(ambient)
	view = RoomView.new()
	view.world = world
	add_child(view)
	view.position = Ui.center_offset(self)
	get_viewport().size_changed.connect(func(): view.position = Ui.center_offset(self))

	var starts := world.start_rooms()
	for i in ids.size():
		var id: int = ids[i]
		var a := Agent.new()
		a.name = "Agent_%d" % id
		a.set_multiplayer_authority(id)
		var start: Vector2i = starts[i]
		var style: Dictionary = STYLES[i % STYLES.size()].duplicate()
		var chosen: String = str(names.get(id, "")).strip_edges().to_upper()
		if chosen != "":
			style["name"] = chosen
		var is_bot := id in bot_ids
		if is_bot:
			style["name"] += " (BOT)"
		# The bot's agent is simulated on this device, like the player's own.
		a.configure(world, start, id == my_id or is_bot, style)
		add_child(a)
		agents.append(a)
		_agent_by_id[id] = a
		inventories[id] = {"items": [], "case": false, "gadgets": [], "hp": MAX_HP, "darts": MAX_DARTS}
		clocks[id] = time_limit
		_start_room[id] = start
		a.max_hp = MAX_HP
		a.hp = MAX_HP
		a.recovered.connect(func(kind): _on_recovered(id, kind))
		a.vent_moved.connect(func(entering): _on_vent_moved(a, entering))
		if id == my_id:
			local_agent = a
	view.agents = agents
	view.highlight_color = local_agent.accent
	view.my_id = my_id
	view.darts = darts

	for bid in bot_ids:
		_add_bot(bid, bot_level)

	var vig_layer := CanvasLayer.new()
	vig_layer.layer = 1
	add_child(vig_layer)
	var vig := TextureRect.new()
	vig.texture = preload("res://scripts/render/art.gd").vignette()
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig_layer.add_child(vig)
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.size = Ui.view_size(self)

	hud = Hud.new()
	hud.layer = 2
	add_child(hud)
	hud.setup(world, local_agent.display_name, local_agent.accent)
	hud.leave_requested.connect(func(): leave_requested.emit())
	hud.rematch_requested.connect(func(): rematch_requested.emit())
	hud.search_pressed.connect(_try_search)
	hud.trap_chosen.connect(_try_trap)
	hud.attack_pressed.connect(_try_melee)
	hud.crawl_pressed.connect(_try_vent)
	hud.fire_pressed.connect(_try_fire)
	local_agent.room_changed.connect(_on_room_changed)
	local_agent.search_finished.connect(_on_local_search_finished)
	local_agent.trap_finished.connect(_on_local_trap_finished)
	local_agent.door_passed.connect(_on_local_door_passed)
	local_agent.exit_touched.connect(_on_exit_touched)
	_on_room_changed(local_agent.room, false)
	# The briefing: everyone waits until it self-destructs (or is skipped).
	var rivals := "AGENT UNKNOWN is"
	if agents.size() > 2:
		rivals = "%d rival agents are" % (agents.size() - 1)
	else:
		for a in agents:
			if a != local_agent:
				rivals = a.display_name + " is"
	for a in _simulated_agents():
		a.frozen = true
	hud.briefing_done.connect(func():
		if not over:
			for a in _simulated_agents():
				a.frozen = false)
	hud.show_briefing(local_agent.display_name, rivals, int(time_limit / 60.0))
	_update_hud_status()
	if multiplayer.has_multiplayer_peer() and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.peer_disconnected.connect(_on_peer_left)


func _add_bot(bid: int, level: String) -> void:
	var ba: Agent = _agent_by_id[bid]
	var b := Bot.new()
	add_child(b)
	b.setup(self, ba, bid, level)
	bots[bid] = b
	ba.search_finished.connect(func(r, i): referee.handle_search(bid, r, i))
	ba.trap_finished.connect(func(info): referee.handle_trap(bid, info))
	ba.door_passed.connect(func(r, d): referee.handle_door(bid, r, d))
	ba.exit_touched.connect(func(): referee.handle_escape(bid))


## The agents this device moves itself: the player's own, plus any bots.
func _simulated_agents() -> Array:
	var out := [local_agent]
	for bid in bots:
		out.append(_agent_by_id[bid])
	return out


# The local player's agent finished an action: ask the referee to apply it.
func _on_local_search_finished(room: Vector2i, idx: int) -> void:
	if not over:
		request_search.rpc_id(1, room, idx)


func _on_local_trap_finished(info: Dictionary) -> void:
	if not over:
		request_trap.rpc_id(1, info)


func _on_local_door_passed(from_room: Vector2i, dir: int) -> void:
	if not over:
		request_door.rpc_id(1, from_room, dir)


func _process(delta: float) -> void:
	if local_agent == null:
		return
	_exit_cooldown -= delta
	# Keyboard / gamepad (see Project Settings > Input Map), or the touch stick.
	var move := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if hud.joystick.output != Vector2.ZERO:
		move = hud.joystick.output
	# Controls are screen-relative: up on the stick = up the screen.
	local_agent.move_input = World.screen_to_floor_dir(move.limit_length(1.0))

	_melee_cd -= delta
	_dart_cd -= delta
	if multiplayer.is_server() and not over:
		referee.tick_clocks(delta)
	_update_hud_status()
	_sounds(delta)

	var busy := over or local_agent.searching or local_agent.ko_time > 0.0 or local_agent.vent >= 0
	hud.attack_button.enabled = not busy and _melee_cd <= 0.0
	hud.fire_button.enabled = not busy and _dart_cd <= 0.0 and inventories[my_id]["darts"] > 0
	var near := -1 if busy else nearest_furniture(local_agent)
	var door := -1 if busy else near_door(local_agent)
	view.highlight = near
	hud.search_button.enabled = near != -1
	var vent_here := -1 if busy else world.vent_near(local_agent.room, local_agent.position)
	view.vent_highlight = vent_here
	hud.set_crawl(vent_here != -1)
	hud.set_trap_options(near != -1, door != -1)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("search"):
		_try_search()
	elif event.is_action_pressed("trap_bomb"):
		_try_trap("BOMB")
	elif event.is_action_pressed("trap_spring"):
		_try_trap("SPRING")
	elif event.is_action_pressed("trap_wire"):
		_try_trap("WIRE")
	elif event.is_action_pressed("attack"):
		_try_melee()
	elif event.is_action_pressed("crawl"):
		_try_vent()
	elif event.is_action_pressed("fire"):
		_try_fire()


func _on_room_changed(room: Vector2i, animate := true) -> void:
	view.room = room
	view.lights.rebuild(world, room)
	hud.show_room(room, animate)
	if animate:
		Sound.play("door", -6.0)


## Footsteps, rummaging, the low-time tick and music tempo.
func _sounds(delta: float) -> void:
	for a in agents:
		if a.room != local_agent.room:
			continue
		var vol := -12.0 if a == local_agent else -16.0
		if a.moving and a.ko_time <= 0.0:
			_step_t[a] = _step_t.get(a, 0.0) - delta
			if _step_t[a] <= 0.0:
				_step_t[a] = 0.3
				Sound.play("step", vol)
		if a.searching and not _was_searching.get(a, false):
			Sound.play("rummage", vol + 9.0)
		_was_searching[a] = a.searching
	if over:
		return
	var left: float = clocks.get(my_id, 999.0)
	Sound.music_tempo(1.08 if left < 60.0 else 1.0)
	if left < 30.0 and int(left) != _last_tick:
		_last_tick = int(left)
		Sound.play("tick", -4.0, false, 0.0)


# ------------------------------------------------------------------ helpers

## The closest furniture within arm's reach of `a`, or -1.
func nearest_furniture(a: Agent) -> int:
	var best := -1
	var best_d := INF
	var items: Array = world.furniture(a.room)
	var p := a.position
	for i in items.size():
		var r: Rect2 = items[i]["rect"]
		var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
		var d := p.distance_to(q)
		if d <= Agent.RADIUS + SEARCH_REACH and d < best_d:
			best = i
			best_d = d
	return best


## The doorway (to another room) that `a` is standing in front of, or -1.
func near_door(a: Agent) -> int:
	var R := World.ROOM
	var c := R.get_center()
	var best := -1
	var best_d := DOOR_REACH
	for dir in World.DIR_VEC:
		if world.opening(a.room, dir) != 1:
			continue
		var v := Vector2(World.DIR_VEC[dir])
		var door := c + v * R.size / 2.0
		var d := a.position.distance_to(door)
		if d < best_d:
			best_d = d
			best = dir
	return best


## The intel `pid` still needs before the exit will open.
func missing_intel(pid: int) -> Array:
	var out := []
	for item in World.INTEL:
		if not inventories[pid]["items"].has(item):
			out.append(item)
	return out


## The agent with peer id `id`, or null.
func agent_of(id: int) -> Agent:
	return _agent_by_id.get(id)


func agent_ids() -> Array:
	return _agent_by_id.keys()


func _sender() -> int:
	var pid := multiplayer.get_remote_sender_id()
	return pid if pid != 0 else multiplayer.get_unique_id()


func traps_owned_by(pid: int) -> int:
	var n := 0
	for k in traps:
		if traps[k]["owner"] == pid:
			n += 1
	return n


# ------------------------------------------------------------------ local input

func _try_search() -> void:
	if over or local_agent.searching or local_agent.ko_time > 0.0:
		return
	var idx := nearest_furniture(local_agent)
	if idx != -1:
		local_agent.start_search(idx, SEARCH_TIME)


func _try_trap(kind: String) -> void:
	if over or local_agent.searching or local_agent.ko_time > 0.0:
		return
	var key := ""
	if kind == "WIRE":
		var dir := near_door(local_agent)
		if dir == -1:
			hud.toast("Stand by a doorway to rig a tripwire.", Color("ffd23f"), 2.0)
			return
		key = World.door_key(local_agent.room, dir)
	else:
		var idx := nearest_furniture(local_agent)
		if idx == -1:
			hud.toast("Stand next to some furniture to hide a trap in it.", Color("ffd23f"), 2.0)
			return
		key = World.furniture_key(local_agent.room, idx)
	if traps_owned_by(my_id) >= MAX_TRAPS:
		hud.toast("You've already got %d traps set. Use them before setting more!" % MAX_TRAPS, Color("ffd23f"), 2.5)
		return
	local_agent.start_trap({"kind": kind, "key": key}, TRAP_TIME)
	Sound.play("trap_set", -3.0)


func _on_exit_touched() -> void:
	if over or _exit_cooldown > 0.0:
		return
	_exit_cooldown = 2.0
	var missing := missing_intel(my_id)
	if missing.is_empty():
		request_escape.rpc_id(1)
	else:
		Sound.play("locked", -4.0)
		hud.toast("The exit won't open yet. Still missing: %s" % ", ".join(PackedStringArray(missing)), Color("ffd23f"), 3.0)


# ------------------------------------------------------------------ air-vent shortcuts

func _try_vent() -> void:
	if over or local_agent.searching or local_agent.ko_time > 0.0 or local_agent.vent >= 0:
		return
	var idx := world.vent_near(local_agent.room, local_agent.position)
	if idx != -1:
		do_vent(my_id, idx)


## Crawl agent `id` into vent `idx`; it comes out of the partner vent
## CRAWL_TIME later. Used for the local player and the bot.
func do_vent(id: int, idx: int) -> void:
	var a: Agent = _agent_by_id[id]
	var dest: int = world.vents[idx]["link"]
	a.enter_vent(idx)
	if id == my_id:
		var sheet := "res://assets/sprites/crawl_%s.png" % a.sheet_name
		hud.show_duct(load(sheet) if ResourceLoader.exists(sheet) else null, CRAWL_TIME)
		Sound.play("crawl", 0.0, false, 0.0)
		var pair := [mini(idx, dest), maxi(idx, dest)]
		if not known_vents.has(pair):
			known_vents.append(pair)
			hud.set_known_vents(known_vents)
	get_tree().create_timer(CRAWL_TIME).timeout.connect(func():
		if is_instance_valid(a) and a.vent == idx:
			a.exit_vent(dest)
			if id == my_id and not over:
				hud.toast("Out of the vent in the %s." % world.rooms[a.room]["name"].to_upper(), Color.WHITE, 2.0))


func _on_vent_moved(a: Agent, entering: bool) -> void:
	# Grille rattles and a puff of dust, for whoever's in that room.
	if a.room != local_agent.room:
		return
	Sound.play("vent", -2.0)
	if not entering:
		view.add_effect("PUFF", a.room, a.position)


# ------------------------------------------------------------------ combat (local side)

func _update_hud_status() -> void:
	var rivals := []
	for id in _agent_by_id:
		if id != my_id:
			var out: bool = eliminated.has(id)
			var left := ceilf(clocks.get(id, 0.0))
			rivals.append({"clock": left, "accent": _agent_by_id[id].accent, "out": out})
	hud.set_status(clocks.get(my_id, 0.0), rivals,
		inventories[my_id]["hp"], MAX_HP, inventories[my_id]["darts"])


## The nearest other agent in `a`'s room that can be hit, and within `reach`.
func rival_near(a: Agent, reach: float) -> Agent:
	var best: Agent = null
	var best_d := reach
	for o in agents:
		if o == a or o.out or o.room != a.room or o.ko_time > 0.0 or o.vent >= 0:
			continue
		var d := a.position.distance_to(o.position)
		if d < best_d:
			best_d = d
			best = o
	return best


func _id_of(a: Agent) -> int:
	for id in _agent_by_id:
		if _agent_by_id[id] == a:
			return id
	return -1


func _try_melee() -> void:
	if over or local_agent.searching or local_agent.ko_time > 0.0 or _melee_cd > 0.0:
		return
	_melee_cd = MELEE_COOLDOWN
	do_melee(my_id)


func _try_fire() -> void:
	if over or local_agent.searching or local_agent.ko_time > 0.0 or _dart_cd > 0.0:
		return
	if inventories[my_id]["darts"] <= 0:
		hud.toast("Out of darts! They refill when you're taken out… or use your cosh.", Color("ffd23f"), 2.0)
		return
	_dart_cd = DART_COOLDOWN
	do_fire(my_id, 0.0)


## Swing the cosh. Used for the local player and the bot.
func do_melee(id: int) -> void:
	var a: Agent = _agent_by_id[id]
	var target := rival_near(a, MELEE_RANGE)
	if target:
		a.facing = (target.position - a.position).angle()
	a.swing()
	_attack_sound("swing", a.room)
	show_attack.rpc("melee", id, a.position, Vector2.from_angle(a.facing))
	if target:
		_send_hit(id, _id_of(target), "melee")


## Fire a dart. Auto-aims at a rival roughly in front; `aim_error` (radians)
## makes the bot miss sometimes.
func do_fire(id: int, aim_error: float) -> void:
	var a: Agent = _agent_by_id[id]
	var dir := Vector2.from_angle(a.facing)
	var target := rival_near(a, 2000.0)
	if target:
		var to := (target.position - a.position).normalized()
		if absf(dir.angle_to(to)) < AIM_CONE or id != my_id:
			dir = to
	dir = dir.rotated(_rng.randf_range(-aim_error, aim_error))
	a.facing = dir.angle()
	a.swing()
	var start := a.position + dir * 34.0
	darts.append({"owner": id, "room": a.room, "pos": start, "vel": dir * DART_SPEED, "live": true})
	_attack_sound("dart", a.room)
	show_attack.rpc("dart", id, start, dir)
	if bots.has(id) or multiplayer.is_server():
		referee.handle_fire(id)
	else:
		request_fire.rpc_id(1)


## Cosmetic copy of the other side's attack (the attacker's device decides hits).
@rpc("any_peer", "call_remote", "unreliable_ordered")
func show_attack(kind: String, id: int, pos: Vector2, dir: Vector2) -> void:
	if not _agent_by_id.has(id):
		return
	var a: Agent = _agent_by_id[id]
	a.facing = dir.angle()
	a.swing()
	_attack_sound("dart" if kind == "dart" else "swing", a.room)
	if kind == "dart":
		darts.append({"owner": id, "room": a.room, "pos": pos, "vel": dir * DART_SPEED, "live": false})


func _attack_sound(sound_name: String, room: Vector2i) -> void:
	if room == local_agent.room:
		Sound.play(sound_name, -3.0)


func _physics_process(delta: float) -> void:
	# Move darts; the device that fired a dart decides whether it hits.
	var keep := []
	for d in darts:
		var old: Vector2 = d["pos"]
		d["pos"] = old + d["vel"] * delta
		var p: Vector2 = d["pos"]
		var stop := not World.ROOM.has_point(p)
		for f in world.furniture(d["room"]):
			if (f["rect"] as Rect2).has_point(p):
				stop = true
				break
		if d["live"] and not stop:
			for o in agents:
				var oid := _id_of(o)
				if oid == d["owner"] or o.room != d["room"] or o.ko_time > 0.0 or o.vent >= 0:
					continue
				if Geometry2D.get_closest_point_to_segment(o.position, old, p).distance_to(o.position) < 30.0:
					_send_hit(d["owner"], oid, "dart")
					stop = true
					break
		if not stop:
			keep.append(d)
	darts.clear()
	darts.append_array(keep)


func _send_hit(by: int, target: int, kind: String) -> void:
	if bots.has(by) or multiplayer.is_server():
		referee.handle_hit(by, target, kind)
	else:
		request_hit.rpc_id(1, target, kind)


func _on_recovered(id: int, kind: String) -> void:
	# After being taken out you wake up back where you started.
	if kind == "DOWN" and (id == my_id or bots.has(id)):
		_agent_by_id[id].respawn(_start_room[id])


# ------------------------------------------------------------------ host: requests

@rpc("any_peer", "call_local", "reliable")
func request_hit(target: int, kind: String) -> void:
	if multiplayer.is_server():
		referee.handle_hit(_sender(), target, kind)


@rpc("any_peer", "call_local", "reliable")
func request_fire() -> void:
	if multiplayer.is_server():
		referee.handle_fire(_sender())


@rpc("any_peer", "call_local", "reliable")
func request_search(room: Vector2i, idx: int) -> void:
	if multiplayer.is_server():
		referee.handle_search(_sender(), room, idx)


@rpc("any_peer", "call_local", "reliable")
func request_trap(info: Dictionary) -> void:
	if multiplayer.is_server():
		referee.handle_trap(_sender(), info)


@rpc("any_peer", "call_local", "reliable")
func request_door(from_room: Vector2i, dir: int) -> void:
	if multiplayer.is_server():
		referee.handle_door(_sender(), from_room, dir)


@rpc("any_peer", "call_local", "reliable")
func request_escape() -> void:
	if multiplayer.is_server():
		referee.handle_escape(_sender())


# ------------------------------------------------------------------ host: rules


func _on_peer_left(id: int) -> void:
	if multiplayer.is_server() and not over:
		referee.eliminate(id, "left")


@rpc("authority", "call_local", "unreliable_ordered")
func sync_clocks(c: Dictionary) -> void:
	clocks = c


## Host: sends the whole match state plus what just happened to everyone.
func broadcast(event: Dictionary) -> void:
	sync_state.rpc(contents, inventories, traps, event)


# ------------------------------------------------------------------ everyone: results

@rpc("authority", "call_local", "reliable")
func sync_state(p_contents: Dictionary, p_inventories: Dictionary, p_traps: Dictionary, event: Dictionary) -> void:
	contents = p_contents
	inventories = p_inventories
	traps = p_traps
	for id in inventories:
		if _agent_by_id.has(id):
			_agent_by_id[id].has_case = inventories[id]["case"]
			_agent_by_id[id].hp = inventories[id]["hp"]
	var mine := {}
	for k in traps:
		if traps[k]["owner"] == my_id:
			mine[k] = traps[k]["kind"]
	view.my_traps = mine
	var inv: Dictionary = inventories[my_id]
	hud.set_inventory(inv["items"], inv["case"], inv["gadgets"])
	presenter.present(event)
	for b in bots.values():
		b.on_event(event)
	event_happened.emit(event)


@rpc("authority", "call_local", "reliable")
func game_over(winner: int, reason := "escape") -> void:
	if over:
		return
	over = true
	for a in agents:
		a.frozen = true
	if _agent_by_id.has(winner):
		_agent_by_id[winner].celebrating = true
	var name := ""
	if _agent_by_id.has(winner):
		name = _agent_by_id[winner].display_name
	Sound.music(false)
	Sound.music_tempo(1.0)
	Sound.play("win" if winner == my_id else "lose")
	hud.show_end(winner, my_id, name, reason, multiplayer.is_server())
