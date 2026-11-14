extends Node2D
## One match: builds the base, spawns the agents, wires up the HUD and runs
## the rules.
##
## The host is the referee. Players (and the bot) ask the host to search,
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
const Hud = preload("res://scripts/ui/hud.gd")
const Ui = preload("res://scripts/ui/ui.gd")
const Bot = preload("res://scripts/game/bot.gd")

## Peer id used for the computer-controlled rival in one-player games.
const BOT_ID := 2

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

var bot: Bot
## Darts in flight: { owner, room, pos, vel, live } (live = this device checks hits)
var darts: Array = []
var time_limit := TIME_LIMIT
## Vent shortcuts the local player has been through: [vent index, partner].
var known_vents: Array = []
var _agent_by_id := {}
var _view: RoomView
var _hud: Hud
var _exit_cooldown := 0.0
var _rng := RandomNumberGenerator.new()
var _start_room := {}
var _melee_cd := 0.0
var _dart_cd := 0.0
var _clock_sync := 0.0
var _step_t := {}
var _was_searching := {}
var _last_tick := -1


## `ids` holds every peer id in the match; the host (lowest id, 1) is Crimson.
func setup(seed_value: int, p_my_id: int, ids: Array, bot_level := "", minutes := 6, names := {}) -> void:
	my_id = p_my_id
	time_limit = minutes * 60.0
	_rng.randomize()
	world = World.new(seed_value)
	contents = world.hidden.duplicate()
	# Darken the world a touch so the room's lights have something to do.
	var ambient := CanvasModulate.new()
	ambient.color = Color(0.66, 0.68, 0.76)
	add_child(ambient)
	_view = RoomView.new()
	_view.world = world
	add_child(_view)
	_view.position = Ui.center_offset(self)
	get_viewport().size_changed.connect(func(): _view.position = Ui.center_offset(self))

	var vs_bot := bot_level != ""
	if vs_bot:
		ids.append(BOT_ID)
	ids.sort()
	for i in ids.size():
		var id: int = ids[i]
		var a := Agent.new()
		a.name = "Agent_%d" % id
		a.set_multiplayer_authority(id)
		var start := Vector2i(0, 0) if i == 0 else Vector2i(World.COLS - 1, World.ROWS - 1)
		var style: Dictionary = STYLES[i % STYLES.size()].duplicate()
		var chosen: String = str(names.get(id, "")).strip_edges().to_upper()
		if chosen != "":
			style["name"] = chosen
		var is_bot := vs_bot and id == BOT_ID
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
	_view.agents = agents
	_view.highlight_color = local_agent.accent
	_view.my_id = my_id
	_view.darts = darts

	if vs_bot:
		var ba: Agent = _agent_by_id[BOT_ID]
		bot = Bot.new()
		add_child(bot)
		bot.setup(self, ba, BOT_ID, bot_level)
		ba.search_finished.connect(func(r, i): _handle_search(BOT_ID, r, i))
		ba.trap_finished.connect(func(info): _handle_trap(BOT_ID, info))
		ba.door_passed.connect(func(r, d): _handle_door(BOT_ID, r, d))
		ba.exit_touched.connect(func(): _handle_escape(BOT_ID))

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

	_hud = Hud.new()
	_hud.layer = 2
	add_child(_hud)
	_hud.setup(world, local_agent.display_name, local_agent.accent)
	_hud.leave_requested.connect(func(): leave_requested.emit())
	_hud.rematch_requested.connect(func(): rematch_requested.emit())
	_hud.search_pressed.connect(_try_search)
	_hud.trap_chosen.connect(_try_trap)
	_hud.attack_pressed.connect(_try_melee)
	_hud.crawl_pressed.connect(_try_vent)
	_hud.fire_pressed.connect(_try_fire)
	local_agent.room_changed.connect(_on_room_changed)
	local_agent.search_finished.connect(_on_local_search_finished)
	local_agent.trap_finished.connect(_on_local_trap_finished)
	local_agent.door_passed.connect(_on_local_door_passed)
	local_agent.exit_touched.connect(_on_exit_touched)
	_on_room_changed(local_agent.room, false)
	# The briefing: everyone waits until it self-destructs (or is skipped).
	var rival_name := "AGENT UNKNOWN"
	for a in agents:
		if a != local_agent:
			rival_name = a.display_name
	local_agent.frozen = true
	if bot:
		_agent_by_id[BOT_ID].frozen = true
	_hud.briefing_done.connect(func():
		if not over:
			local_agent.frozen = false
			if bot:
				_agent_by_id[BOT_ID].frozen = false)
	_hud.show_briefing(local_agent.display_name, rival_name, int(time_limit / 60.0))
	_update_hud_status()


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
	var kb := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var wasd := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var move := kb + wasd
	if _hud.joystick.output != Vector2.ZERO:
		move = _hud.joystick.output
	# Controls are screen-relative: up on the stick = up the screen.
	local_agent.move_input = World.screen_to_floor_dir(move.limit_length(1.0))

	_melee_cd -= delta
	_dart_cd -= delta
	if multiplayer.is_server() and not over:
		_tick_clocks(delta)
	_update_hud_status()
	_sounds(delta)

	var busy := over or local_agent.searching or local_agent.ko_time > 0.0 or local_agent.vent >= 0
	_hud.attack_button.enabled = not busy and _melee_cd <= 0.0
	_hud.fire_button.enabled = not busy and _dart_cd <= 0.0 and inventories[my_id]["darts"] > 0
	var near := -1 if busy else nearest_furniture(local_agent)
	var door := -1 if busy else near_door(local_agent)
	_view.highlight = near
	_hud.search_button.enabled = near != -1
	var vent_here := -1 if busy else world.vent_near(local_agent.room, local_agent.position)
	_view.vent_highlight = vent_here
	_hud.set_crawl(vent_here != -1)
	_hud.set_trap_options(near != -1, door != -1)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_E, KEY_SPACE: _try_search()
			KEY_1: _try_trap("BOMB")
			KEY_2: _try_trap("SPRING")
			KEY_3: _try_trap("WIRE")
			KEY_F: _try_melee()
			KEY_V: _try_vent()
			KEY_G: _try_fire()


func _on_room_changed(room: Vector2i, animate := true) -> void:
	_view.room = room
	_view.lights.rebuild(world, room)
	_hud.show_room(room, animate)
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


func _missing(pid: int) -> Array:
	var out := []
	for item in World.INTEL:
		if not inventories[pid]["items"].has(item):
			out.append(item)
	return out


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
			_hud.toast("Stand by a doorway to rig a tripwire.", Color("ffd23f"), 2.0)
			return
		key = World.door_key(local_agent.room, dir)
	else:
		var idx := nearest_furniture(local_agent)
		if idx == -1:
			_hud.toast("Stand next to some furniture to hide a trap in it.", Color("ffd23f"), 2.0)
			return
		key = World.furniture_key(local_agent.room, idx)
	if traps_owned_by(my_id) >= MAX_TRAPS:
		_hud.toast("You've already got %d traps set. Use them before setting more!" % MAX_TRAPS, Color("ffd23f"), 2.5)
		return
	local_agent.start_trap({"kind": kind, "key": key}, TRAP_TIME)
	Sound.play("trap_set", -3.0)


func _on_exit_touched() -> void:
	if over or _exit_cooldown > 0.0:
		return
	_exit_cooldown = 2.0
	var missing := _missing(my_id)
	if missing.is_empty():
		request_escape.rpc_id(1)
	else:
		Sound.play("locked", -4.0)
		_hud.toast("The exit won't open yet. Still missing: %s" % ", ".join(PackedStringArray(missing)), Color("ffd23f"), 3.0)


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
		_hud.show_duct(load(sheet) if ResourceLoader.exists(sheet) else null, CRAWL_TIME)
		Sound.play("crawl", 0.0, false, 0.0)
		var pair := [mini(idx, dest), maxi(idx, dest)]
		if not known_vents.has(pair):
			known_vents.append(pair)
			_hud.set_known_vents(known_vents)
	get_tree().create_timer(CRAWL_TIME).timeout.connect(func():
		if is_instance_valid(a) and a.vent == idx:
			a.exit_vent(dest)
			if id == my_id and not over:
				_hud.toast("Out of the vent in the %s." % world.rooms[a.room]["name"].to_upper(), Color.WHITE, 2.0))


func _on_vent_moved(a: Agent, entering: bool) -> void:
	# Grille rattles and a puff of dust, for whoever's in that room.
	if a.room != local_agent.room:
		return
	Sound.play("vent", -2.0)
	if not entering:
		_view.add_effect("PUFF", a.room, a.position)


# ------------------------------------------------------------------ combat (local side)

func _update_hud_status() -> void:
	var rival := -1
	for id in clocks:
		if id != my_id:
			rival = id
	_hud.set_status(clocks.get(my_id, 0.0), clocks.get(rival, -1.0),
		inventories[my_id]["hp"], MAX_HP, inventories[my_id]["darts"])


## The nearest other agent in `a`'s room that can be hit, and within `reach`.
func rival_near(a: Agent, reach: float) -> Agent:
	var best: Agent = null
	var best_d := reach
	for o in agents:
		if o == a or o.room != a.room or o.ko_time > 0.0 or o.vent >= 0:
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
		_hud.toast("Out of darts! They refill when you're taken out… or use your cosh.", Color("ffd23f"), 2.0)
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
	if id == BOT_ID or multiplayer.is_server():
		_handle_fire(id)
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
	if by == BOT_ID or multiplayer.is_server():
		_handle_hit(by, target, kind)
	else:
		request_hit.rpc_id(1, target, kind)


func _on_recovered(id: int, kind: String) -> void:
	# After being taken out you wake up back where you started.
	if kind == "DOWN" and (id == my_id or (bot and id == BOT_ID)):
		_agent_by_id[id].respawn(_start_room[id])


# ------------------------------------------------------------------ host: requests

@rpc("any_peer", "call_local", "reliable")
func request_hit(target: int, kind: String) -> void:
	if multiplayer.is_server():
		_handle_hit(_sender(), target, kind)


@rpc("any_peer", "call_local", "reliable")
func request_fire() -> void:
	if multiplayer.is_server():
		_handle_fire(_sender())


@rpc("any_peer", "call_local", "reliable")
func request_search(room: Vector2i, idx: int) -> void:
	if multiplayer.is_server():
		_handle_search(_sender(), room, idx)


@rpc("any_peer", "call_local", "reliable")
func request_trap(info: Dictionary) -> void:
	if multiplayer.is_server():
		_handle_trap(_sender(), info)


@rpc("any_peer", "call_local", "reliable")
func request_door(from_room: Vector2i, dir: int) -> void:
	if multiplayer.is_server():
		_handle_door(_sender(), from_room, dir)


@rpc("any_peer", "call_local", "reliable")
func request_escape() -> void:
	if multiplayer.is_server():
		_handle_escape(_sender())


# ------------------------------------------------------------------ host: rules

func _handle_search(pid: int, room: Vector2i, idx: int) -> void:
	if over or not inventories.has(pid):
		return
	var key := World.furniture_key(room, idx)
	var inv: Dictionary = inventories[pid]
	var disarmed := ""
	if traps.has(key):
		var kind: String = traps[key]["kind"]
		var remedy: String = World.TRAPS[kind]
		if inv["gadgets"].has(remedy):
			disarmed = kind
			traps.erase(key)
			_use_gadget(pid, remedy)
		else:
			_spring_trap(pid, key, room)
			return
	var found: String = contents.get(key, "")
	var left := ""
	contents.erase(key)
	if found in World.GADGETS:
		inv["gadgets"].append(found)
	elif found == World.BRIEFCASE:
		inv["case"] = true
	elif found != "":
		if not inv["case"] and inv["items"].size() >= 1:
			# Hands full, no briefcase: swap what you're holding for what you found.
			left = inv["items"][0]
			inv["items"].erase(left)
			contents[key] = left
		inv["items"].append(found)
	_broadcast({"type": "search", "pid": pid, "key": key, "found": found, "left": left, "disarmed": disarmed})


func _handle_trap(pid: int, info: Dictionary) -> void:
	if over or not inventories.has(pid):
		return
	var key: String = info.get("key", "")
	var kind: String = info.get("kind", "")
	var reason := ""
	if not World.TRAPS.has(kind) or key == "":
		reason = "That trap didn't work."
	elif traps.has(key):
		reason = "Something's already rigged here. Best leave it alone…"
	elif traps_owned_by(pid) >= MAX_TRAPS:
		reason = "You've already got %d traps set." % MAX_TRAPS
	if reason != "":
		_broadcast({"type": "trap_fail", "pid": pid, "reason": reason})
		return
	traps[key] = {"kind": kind, "owner": pid}
	_broadcast({"type": "trap_set", "pid": pid, "kind": kind, "key": key})


func _handle_door(pid: int, from_room: Vector2i, dir: int) -> void:
	if over or not inventories.has(pid):
		return
	var key := World.door_key(from_room, dir)
	if not traps.has(key):
		return
	var to_room: Vector2i = from_room + World.DIR_VEC[dir]
	var remedy: String = World.TRAPS["WIRE"]
	if inventories[pid]["gadgets"].has(remedy):
		traps.erase(key)
		_use_gadget(pid, remedy)
		_broadcast({"type": "disarm", "pid": pid, "kind": "WIRE"})
	else:
		_spring_trap(pid, key, to_room)


func _handle_escape(pid: int) -> void:
	if over:
		return
	if inventories.has(pid) and _missing(pid).is_empty():
		game_over.rpc(pid, "escape")


func _handle_fire(pid: int) -> void:
	if over or not inventories.has(pid):
		return
	inventories[pid]["darts"] = maxi(0, inventories[pid]["darts"] - 1)
	_broadcast({"type": "fire", "pid": pid})


func _handle_hit(by: int, target: int, kind: String) -> void:
	if over or by == target or not inventories.has(target) or not inventories.has(by):
		return
	var ta: Agent = _agent_by_id[target]
	var ba: Agent = _agent_by_id[by]
	if ta.ko_time > 0.0 or ta.protect_time > 0.0 or ta.vent >= 0:
		return
	if kind == "melee" and (ta.room != ba.room or ta.position.distance_to(ba.position) > MELEE_RANGE * 2.0):
		return
	var inv: Dictionary = inventories[target]
	inv["hp"] -= 1
	if inv["hp"] > 0:
		_broadcast({"type": "hit", "pid": target, "by": by, "kind": kind, "from": ba.position})
		return
	# Taken out: drop the intel, lose time, wake up back at the start.
	var lost: Array = inv["items"].duplicate()
	inv["items"].clear()
	for item in lost:
		_hide_somewhere(item, ta.room)
	inv["hp"] = MAX_HP
	inv["darts"] = MAX_DARTS
	_penalise(target, DOWN_PENALTY)
	_broadcast({"type": "down", "pid": target, "by": by, "kind": kind, "room": ta.room, "lost": lost, "from": ba.position})


func _penalise(pid: int, seconds: float) -> void:
	clocks[pid] = maxf(1.0, clocks[pid] - seconds)
	sync_clocks.rpc(clocks)


func _tick_clocks(delta: float) -> void:
	for id in clocks:
		clocks[id] -= delta
	_clock_sync -= delta
	if _clock_sync <= 0.0:
		_clock_sync = 0.5
		sync_clocks.rpc(clocks)
	var out := []
	for id in clocks:
		if clocks[id] <= 0.0:
			out.append(id)
	if out.is_empty():
		return
	# Someone's clock ran out: the other agent (if they still have time) wins.
	var winner := 0
	for id in clocks:
		if clocks[id] > 0.0:
			winner = id
	if clocks.size() == 1:
		winner = 0
	game_over.rpc(winner, "time")


@rpc("authority", "call_local", "unreliable_ordered")
func sync_clocks(c: Dictionary) -> void:
	clocks = c


## The victim is knocked out and the intel they carry flies into the
## furniture around the room.
func _spring_trap(pid: int, key: String, room: Vector2i) -> void:
	var trap: Dictionary = traps[key]
	traps.erase(key)
	var lost: Array = inventories[pid]["items"].duplicate()
	inventories[pid]["items"].clear()
	for item in lost:
		_hide_somewhere(item, room)
	_penalise(pid, TRAP_PENALTY)
	_broadcast({"type": "ko", "pid": pid, "kind": trap["kind"], "owner": trap["owner"], "room": room, "lost": lost})


## A gadget is used up, then turns up again somewhere else in the base.
func _use_gadget(pid: int, gadget: String) -> void:
	inventories[pid]["gadgets"].erase(gadget)
	_hide_somewhere(gadget, Vector2i(-1, -1))


## Puts `item` in an empty, untrapped piece of furniture, preferring `room`.
func _hide_somewhere(item: String, room: Vector2i) -> void:
	var here := []
	var anywhere := []
	for r in world.rooms:
		for i in world.furniture(r).size():
			var k := World.furniture_key(r, i)
			if contents.has(k) or traps.has(k):
				continue
			anywhere.append(k)
			if r == room:
				here.append(k)
	var pool := here if not here.is_empty() else anywhere
	if pool.is_empty():
		return
	contents[pool[_rng.randi_range(0, pool.size() - 1)]] = item


func _broadcast(event: Dictionary) -> void:
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
	_view.my_traps = mine
	var inv: Dictionary = inventories[my_id]
	_hud.set_inventory(inv["items"], inv["case"], inv["gadgets"])
	_on_event(event)
	if bot:
		bot.on_event(event)
	event_happened.emit(event)


func _on_event(e: Dictionary) -> void:
	var pid: int = e.get("pid", 0)
	var me := pid == my_id
	_event_sound(e, me)
	var col := local_agent.accent.lightened(0.3)
	var warn := Color("ffd23f")
	match e.get("type", ""):
		"search":
			if not me:
				return
			var found: String = e["found"]
			var msg := ""
			if e["disarmed"] != "":
				msg = "Defused a %s with your %s!  " % [World.TRAP_NAMES[e["disarmed"]], World.TRAPS[e["disarmed"]]]
			if found == "":
				_hud.toast(msg + "Nothing here.", col if msg != "" else Color(1, 1, 1, 0.8), 2.0 if msg != "" else 1.2)
			elif found in World.GADGETS:
				_hud.toast(msg + "Found the %s! It beats a %s." % [found, World.TRAP_NAMES[_trap_for(found)]], col, 3.0)
			elif found == World.BRIEFCASE:
				_hud.toast(msg + "Found a BRIEFCASE! Now you can carry everything.", col)
			elif e["left"] != "":
				_hud.toast(msg + "Found the %s, but your hands are full,\nso you left the %s here. Find a briefcase!" % [found, e["left"]], warn, 4.0)
			else:
				var n: int = inventories[my_id]["items"].size()
				var line := "Found the %s!  (%d/%d)" % [found, n, World.INTEL.size()]
				if n == World.INTEL.size():
					line = "Got the lot! Now get to the EXIT!"
				_hud.toast(msg + line, col)
		"trap_set":
			if me:
				_hud.toast("%s set. Only you can see the marker." % World.TRAP_NAMES[e["kind"]], col, 2.0)
		"trap_fail":
			if me:
				_hud.toast(e["reason"], warn, 2.5)
		"disarm":
			if me:
				_hud.toast("Snipped a TRIPWIRE with your WIRE CUTTERS!", col, 2.5)
		"hit":
			var victim: Agent = _agent_by_id[pid]
			victim.hurt(victim.position - e["from"])
			_view.add_effect("HIT", victim.room, victim.position)
			if me:
				_hud.flash(Color("ff2a2a"))
			elif e["by"] == my_id:
				pass
		"down":
			var victim: Agent = _agent_by_id[pid]
			victim.hurt(victim.position - e["from"])
			victim.knock_out("DOWN", DOWN_TIME)
			victim.protect_time = PROTECT_TIME
			_view.add_effect("DOWN", e["room"], victim.position)
			var dropped := " Your intel went flying!" if not (e["lost"] as Array).is_empty() else ""
			if me:
				_hud.flash(Color("ff2a2a"))
				_hud.toast("You've been taken out! -%ds.%s" % [int(DOWN_PENALTY), dropped], warn, 3.5)
			elif e["by"] == my_id:
				_hud.toast("You took out %s! They lose %ds." % [victim.display_name, int(DOWN_PENALTY)], col, 3.0)
		"ko":
			var victim: Agent = _agent_by_id[pid]
			victim.knock_out(e["kind"], KO_TIME)
			_view.add_effect(e["kind"], e["room"], victim.position)
			var lost: Array = e["lost"]
			var dropped := " Your intel went flying!" if not lost.is_empty() else ""
			var trap_name: String = World.TRAP_NAMES[e["kind"]]
			if me and e["owner"] == my_id:
				_hud.toast("Caught in your own %s! Nice one. -%ds.%s" % [trap_name, int(TRAP_PENALTY), dropped], warn, 3.5)
				_hud.flash(Color("ff7a1a") if e["kind"] == "BOMB" else Color("ffd23f"))
			elif me:
				_hud.toast("%s! You walked into a %s. -%ds.%s" % [_exclamation(e["kind"]), trap_name, int(TRAP_PENALTY), dropped], warn, 3.5)
				_hud.flash(Color("ff7a1a") if e["kind"] == "BOMB" else Color("ffd23f"))
			elif e["owner"] == my_id:
				_hud.toast("Your %s got %s!" % [trap_name, victim.display_name], col, 3.0)


func _event_sound(e: Dictionary, me: bool) -> void:
	var here: bool = not e.has("room") or e["room"] == local_agent.room
	match e.get("type", ""):
		"search":
			if not me:
				return
			if e["disarmed"] != "":
				Sound.play("gadget")
			var found: String = e["found"]
			if found == "":
				Sound.play("nothing", -2.0)
			elif found in World.GADGETS:
				Sound.play("gadget")
			else:
				Sound.play("found")
		"disarm":
			if me:
				Sound.play("gadget")
		"ko":
			var sound_name: String = {"BOMB": "boom", "SPRING": "boing", "WIRE": "twang"}[e["kind"]]
			# A bomb is loud enough to hear through the walls.
			if here or me or e["kind"] == "BOMB":
				Sound.play(sound_name, 0.0, not (here or me), 0.03)
			if me:
				Settings.buzz(350 if e["kind"] == "BOMB" else 200)
		"hit":
			var v: Agent = _agent_by_id[e["pid"]]
			if v.room == local_agent.room:
				Sound.play("hit", -1.0)
			if me:
				Settings.buzz(80)
		"down":
			if here or me:
				Sound.play("down")
			if me:
				Settings.buzz(300)


static func _trap_for(gadget: String) -> String:
	for t in World.TRAPS:
		if World.TRAPS[t] == gadget:
			return t
	return ""


static func _exclamation(kind: String) -> String:
	match kind:
		"BOMB": return "KABOOM"
		"SPRING": return "BOING"
		_: return "TWANG"


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
	_hud.show_end(winner, my_id, name, reason, multiplayer.is_server())
