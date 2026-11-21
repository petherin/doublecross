extends RefCounted
## Shows match events on this device once the referee has applied them:
## knock-outs and hurt animations, explosions, ticker-tape messages, screen
## flashes, sounds and a buzz on phones.

const World = preload("res://scripts/core/world.gd")
const Agent = preload("res://scripts/game/agent.gd")

var game: Node
## The match so far, for the debrief: {"t": seconds in, "text", "col"}.
var timeline: Array = []


func _init(p_game: Node) -> void:
	game = p_game


## Adds a line to the timeline, about agent `a`.
func note(a: Agent, text: String) -> void:
	var line := short_name(a) + " " + text
	# The same thing twice in a few seconds is one moment.
	if not timeline.is_empty() and timeline.back()["text"] == line and game.elapsed - timeline.back()["t"] < 5.0:
		return
	timeline.append({"t": game.elapsed, "text": line, "col": a.accent})


## "AGENT COBALT (TRAPPER BOT)" -> "COBALT", to keep the timeline lines short.
static func short_name(a: Agent) -> String:
	return a.display_name.trim_prefix("AGENT ").get_slice(" (", 0)


## The moments worth a line in the debrief: intel and briefcases found,
## traps sprung, takedowns and agents going out.
func _record(e: Dictionary) -> void:
	if e.get("type", "") == "nacho_poo" and e["stage"] == "done":
		timeline.append({"t": game.elapsed, "col": Color("b0703a"),
				"text": "Nacho left a mess in the " + str(game.world.rooms[e["room"]]["name"]).to_upper()})
		return
	var who: Agent = game.agent_of(e.get("pid", 0))
	if who == null:
		return
	match e.get("type", ""):
		"search":
			var found: String = e["found"]
			if e.get("nacho", false):
				note(who, "found Nacho the dog")
			elif found in World.INTEL or (found == World.BRIEFCASE and not e.get("spare", false)):
				note(who, "found the " + found)
		"nacho_foe":
			var keeper: Agent = game.agent_of(e["owner"])
			if keeper:
				note(keeper, "set Nacho on " + short_name(who))
		"nacho_home":
			note(who, "lost Nacho, who ran home")
		"nacho_down":
			note(who, "took out Nacho, who ran home")
		"ko":
			var owner: Agent = game.agent_of(e["owner"])
			var trap: String = World.TRAP_NAMES[e["kind"]].to_lower()
			if owner == who:
				note(who, "walked into their own " + trap)
			elif owner:
				note(who, "was caught by %s's %s" % [short_name(owner), trap])
		"down":
			var by: Agent = game.agent_of(e["by"])
			if e["kind"] == "slip":
				note(who, "slipped in Nacho's mess and was taken out")
			elif by and e["kind"] == "bite":
				note(who, "was taken out by Nacho")
			elif by:
				note(by, "took out " + short_name(who))
		"out":
			note(who, "ran out of time" if e["reason"] == "time" else "left the mission")


## Nacho's poo: he squats, he's interrupted, or he's done (and there's a turd).
func _poo(e: Dictionary) -> void:
	var mine: bool = e["owner"] == game.my_id and game.my_id != 0
	match e["stage"]:
		"start":
			game.dog.start_poo(e["stand"], e["face"])
			if mine:
				game.hud.toast("Nacho's stopped for a poo…", Color(1, 1, 1, 0.85), 2.5)
		"stop":
			game.dog.finish_poo()
		"done":
			game.dog.finish_poo()
			game.turds.append({"room": e["room"], "pos": e["pos"]})
			for b in game.bots.values():
				b.forget_room(e["room"])
			if e["room"] == game.watched.room:
				Sound.play("plop", 0.0)
				game.view.add_effect("PUFF", e["room"], e["pos"])
				game.hud.toast("Mind your step: Nacho's left a little present.", Color("e0b080"), 3.0)


## The turd someone slipped in is gone (squashed flat, all over them).
func _tread_in(room: Vector2i, pos: Vector2) -> void:
	for t in game.turds:
		if t["room"] == room and (t["pos"] as Vector2).is_equal_approx(pos):
			game.turds.erase(t)
			break
	for b in game.bots.values():
		b.forget_room(room)


## Nacho's teeth find their mark: a snap, a yelp and a stumble.
func _bitten(victim: Agent, me: bool) -> void:
	game.dog.bite(victim)
	victim.knock_out("BITE", game.dog.BITE_STUN)
	if victim.room == game.watched.room:
		Sound.play("bark", 0.0)
	if me:
		game.hud.toast("Nacho bit you! Stop attacking and he'll back off.", Color("ffd23f"), 2.0)


## Nacho's kennel was searched: he's found, or he's already out.
func _kennel(e: Dictionary, pid: int, me: bool, col: Color) -> void:
	var who: Agent = game.agent_of(pid)
	if e.get("nacho", false):
		game.dog.found_by(pid)
		if game.dog.room == game.watched.room:
			Sound.play("yip", -2.0)
		if me:
			game.hud.toast("You found NACHO! He'll sniff out traps and hidden intel, and see off attackers.",
					col, 4.0)
		else:
			game.hud.toast("%s found Nacho the dog!" % who.display_name, col, 3.0)
	elif me:
		var keeper: Agent = game.agent_of(game.dog.owner_id)
		game.hud.toast("Nacho's kennel is empty. He's out with %s." % (keeper.display_name if keeper else "someone"),
				Color(1, 1, 1, 0.8), 2.5)


## Applies one match event on this device: animations, toasts, flashes and sounds.
func present(e: Dictionary) -> void:
	_record(e)
	var pid: int = e.get("pid", 0)
	var me: bool = pid == game.my_id
	_sound(e, me)
	var col: Color = game.local_agent.accent.lightened(0.3)
	var warn := Color("ffd23f")
	match e.get("type", ""):
		"search":
			if e.get("kennel", false):
				_kennel(e, pid, me, col)
				return
			if not me:
				return
			var found: String = e["found"]
			var idx := int(str(e["key"]).get_slice(",", 2))
			if found != "" and not e.get("spare", false):
				game.view.show_found(idx, found)
			var msg := ""
			if e["disarmed"] != "":
				msg = "Defused a %s with your %s!  " % [World.TRAP_NAMES[e["disarmed"]], World.TRAPS[e["disarmed"]]]
			if found == "":
				game.hud.toast(msg + "Nothing here.", col if msg != "" else Color(1, 1, 1, 0.8), 2.0 if msg != "" else 1.2)
			elif found in World.GADGETS:
				game.hud.toast(msg + "Found the %s! It beats a %s." % [found, World.TRAP_NAMES[_trap_for(found)]], col, 3.0)
			elif found == World.BRIEFCASE and e.get("spare", false):
				game.hud.toast(msg + "Another briefcase. One's enough; you left it here.", Color(1, 1, 1, 0.8), 2.5)
			elif found == World.BRIEFCASE:
				game.hud.toast(msg + "Found a BRIEFCASE! Now you can carry everything.", col)
			elif e["left"] != "":
				var full := "Found the %s, but your hands are full,\nso you left the %s here. Find a briefcase!"
				game.hud.toast(msg + full % [found, e["left"]], warn, 4.0)
			else:
				var n: int = game.inventories[game.my_id]["items"].size()
				var line := "Found the %s!  (%d/%d)" % [found, n, World.INTEL.size()]
				if n == World.INTEL.size():
					line = "Got the lot! Now get to the EXIT!"
				game.hud.toast(msg + line, col)
		"trap_set":
			if me:
				game.hud.toast("%s set. Only you can see the marker." % World.TRAP_NAMES[e["kind"]], col, 2.0)
		"trap_fail":
			if me:
				game.hud.toast(e["reason"], warn, 2.5)
		"disarm":
			if me:
				game.hud.toast("Snipped a TRIPWIRE with your WIRE CUTTERS!", col, 2.5)
		"hit":
			var victim: Agent = game.agent_of(pid)
			victim.hurt(victim.position - e["from"])
			if e["kind"] == "bite":
				_bitten(victim, me)
			game.view.add_effect("HIT", victim.room, victim.position)
			if victim.room == game.watched.room:
				game.view.shake(3.0, 0.2)
			if me:
				game.hud.flash(Color("ff2a2a"))
			elif e["by"] == game.my_id:
				pass
		"down":
			var victim: Agent = game.agent_of(pid)
			if e["kind"] != "slip":
				victim.hurt(victim.position - e["from"])
			if e["kind"] == "bite":
				game.dog.bite(victim)
			var slipped: bool = e["kind"] == "slip"
			# A slip isn't a blow: no burst, just feet up, over and thump.
			victim.knock_out("SLIP" if slipped else "DOWN", game.DOWN_TIME)
			victim.protect_time = game.PROTECT_TIME
			if slipped:
				_tread_in(e["room"], e["turd"])
			else:
				game.view.add_effect("DOWN", e["room"], victim.position)
			if e["room"] == game.watched.room:
				game.view.shake(8.0, 0.4)
				if not slipped:
					game.hit_stop()
			var dropped := " Your intel went flying!" if not (e["lost"] as Array).is_empty() else ""
			if e["kind"] == "slip":
				if e["room"] == game.watched.room:
					Sound.play("slip", 0.0)
				if me:
					game.hud.flash(Color("8a5a2b"))
					game.hud.toast("You slipped in Nacho's mess! Taken out, and everything you had went flying.",
							warn, 3.5)
				elif e["room"] == game.watched.room:
					game.hud.toast("%s slipped in Nacho's mess!" % victim.display_name, col, 3.0)
				return
			if me:
				game.hud.flash(Color("ff2a2a"))
				game.hud.toast("You've been taken out! -%ds.%s" % [int(game.DOWN_PENALTY), dropped], warn, 3.5)
			elif e["by"] == game.my_id:
				game.hud.toast("You took out %s! They lose %ds." % [victim.display_name, int(game.DOWN_PENALTY)], col, 3.0)
		"out":
			var who: Agent = game.agent_of(pid)
			who.frozen = true
			who.out = true
			if me:
				game.hud.toast("Your clock ran out. You're out of the mission." if e["reason"] == "time"
						else "You've left the mission.", warn, 4.0)
				game.spectate()
			else:
				if game.spectating and who == game.watched:
					game.spectate()
				var why := "ran out of time" if e["reason"] == "time" else "left the base"
				game.hud.toast("%s %s and is out!" % [who.display_name, why], col, 3.5)
		"nacho_foe":
			game.dog.set_foe(pid)
			if pid == 0:
				return
			if game.dog.room == game.watched.room:
				Sound.play("growl", -2.0)
			if me:
				game.hud.toast("Nacho's coming for you! Stop attacking and he'll back off.", warn, 3.0)
			elif e["owner"] == game.my_id:
				game.hud.toast("Nacho goes for %s!" % game.agent_of(pid).display_name, col, 2.5)
		"nacho_poo":
			_poo(e)
		"nacho_hit":
			game.dog.hit(e["hp"])
			if e["room"] == game.watched.room:
				Sound.play("yelp", -3.0)
				Sound.play("hit", -6.0)
		"nacho_down":
			game.view.add_effect("PUFF", e["room"], e["at"])
			if e["room"] == game.watched.room:
				Sound.play("yelp", 0.0)
			game.dog.go_home()
			if e["owner"] == game.my_id:
				game.hud.toast("Nacho's been taken out! He's limped home to his kennel.", warn, 3.0)
			elif me:
				game.hud.toast("You saw off Nacho. He's run home to his kennel.", col, 3.0)
		"nacho_home":
			game.dog.go_home()
			if me:
				game.hud.toast("Nacho has run back to his kennel.", Color(1, 1, 1, 0.8), 2.5)
		"ko":
			var victim: Agent = game.agent_of(pid)
			victim.knock_out(e["kind"], game.KO_TIME)
			game.view.add_effect(e["kind"], e["room"], victim.position)
			if e["room"] == game.watched.room:
				game.view.shake({"BOMB": 16.0, "SHOCK": 4.0}.get(e["kind"], 6.0), 1.2 if e["kind"] == "SHOCK" else 0.5)
				game.hit_stop()
			elif e["kind"] == "BOMB":
				game.view.shake(5.0, 0.4)   # felt through the walls
			var lost: Array = e["lost"]
			var dropped := " Your intel went flying!" if not lost.is_empty() else ""
			var trap_name: String = World.TRAP_NAMES[e["kind"]]
			if me and e["owner"] == game.my_id:
				game.hud.toast("Caught in your own %s! Nice one. -%ds.%s" % [trap_name, int(game.TRAP_PENALTY), dropped], warn, 3.5)
				game.hud.flash(_flash_colour(e["kind"]))
			elif me:
				var args := [_exclamation(e["kind"]), trap_name, int(game.TRAP_PENALTY), dropped]
				game.hud.toast("%s! You walked into a %s. -%ds.%s" % args, warn, 3.5)
				game.hud.flash(_flash_colour(e["kind"]))
			elif e["owner"] == game.my_id:
				game.hud.toast("Your %s got %s!" % [trap_name, victim.display_name], col, 3.0)


func _sound(e: Dictionary, me: bool) -> void:
	var here: bool = not e.has("room") or e["room"] == game.watched.room
	match e.get("type", ""):
		"search":
			if not me or e.get("kennel", false):
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
			var sound_name: String = {"BOMB": "boom", "SPRING": "boing", "WIRE": "twang", "SHOCK": "zap"}[e["kind"]]
			# A bomb is loud enough to hear through the walls.
			if here or me or e["kind"] == "BOMB":
				Sound.play(sound_name, 0.0, not (here or me), 0.03)
			if here or me:
				var who: Agent = game.agent_of(e["pid"])
				Sound.play("yell" if e["kind"] == "SHOCK" else "argh", -3.0, false, 0.04, who.voice)
			if me:
				Settings.buzz(600 if e["kind"] == "SHOCK" else 350 if e["kind"] == "BOMB" else 200)
		"hit":
			var v: Agent = game.agent_of(e["pid"])
			if v.room == game.watched.room:
				Sound.play("hit", -1.0)
				Sound.play("oof", -4.0, false, 0.06, v.voice)
			if me:
				Settings.buzz(80)
		"down":
			if here or me:
				Sound.play("down")
				Sound.play("argh", -2.0, false, 0.04, game.agent_of(e["pid"]).voice)
			if me:
				Settings.buzz(300)


static func _flash_colour(kind: String) -> Color:
	match kind:
		"BOMB": return Color("ff7a1a")
		"SHOCK": return Color("9df4ff")
		_: return Color("ffd23f")


static func _trap_for(gadget: String) -> String:
	for t in World.TRAPS:
		if World.TRAPS[t] == gadget:
			return t
	return ""


static func _exclamation(kind: String) -> String:
	match kind:
		"BOMB": return "KABOOM"
		"SPRING": return "BOING"
		"SHOCK": return "BZZZT"
		_: return "TWANG"
