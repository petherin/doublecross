extends RefCounted
## Shows match events on this device once the referee has applied them:
## knock-outs and hurt animations, explosions, ticker-tape messages, screen
## flashes, sounds and a buzz on phones.

const World = preload("res://scripts/core/world.gd")
const Agent = preload("res://scripts/game/agent.gd")

var game: Node


func _init(p_game: Node) -> void:
	game = p_game


## Applies one match event on this device: animations, toasts, flashes and sounds.
func present(e: Dictionary) -> void:
	var pid: int = e.get("pid", 0)
	var me: bool = pid == game.my_id
	_sound(e, me)
	var col: Color = game.local_agent.accent.lightened(0.3)
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
			game.view.add_effect("HIT", victim.room, victim.position)
			if me:
				game.hud.flash(Color("ff2a2a"))
			elif e["by"] == game.my_id:
				pass
		"down":
			var victim: Agent = game.agent_of(pid)
			victim.hurt(victim.position - e["from"])
			victim.knock_out("DOWN", game.DOWN_TIME)
			victim.protect_time = game.PROTECT_TIME
			game.view.add_effect("DOWN", e["room"], victim.position)
			var dropped := " Your intel went flying!" if not (e["lost"] as Array).is_empty() else ""
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
			else:
				var why := "ran out of time" if e["reason"] == "time" else "left the base"
				game.hud.toast("%s %s and is out!" % [who.display_name, why], col, 3.5)
		"ko":
			var victim: Agent = game.agent_of(pid)
			victim.knock_out(e["kind"], game.KO_TIME)
			game.view.add_effect(e["kind"], e["room"], victim.position)
			var lost: Array = e["lost"]
			var dropped := " Your intel went flying!" if not lost.is_empty() else ""
			var trap_name: String = World.TRAP_NAMES[e["kind"]]
			if me and e["owner"] == game.my_id:
				game.hud.toast("Caught in your own %s! Nice one. -%ds.%s" % [trap_name, int(game.TRAP_PENALTY), dropped], warn, 3.5)
				game.hud.flash(Color("ff7a1a") if e["kind"] == "BOMB" else Color("ffd23f"))
			elif me:
				var args := [_exclamation(e["kind"]), trap_name, int(game.TRAP_PENALTY), dropped]
				game.hud.toast("%s! You walked into a %s. -%ds.%s" % args, warn, 3.5)
				game.hud.flash(Color("ff7a1a") if e["kind"] == "BOMB" else Color("ffd23f"))
			elif e["owner"] == game.my_id:
				game.hud.toast("Your %s got %s!" % [trap_name, victim.display_name], col, 3.0)


func _sound(e: Dictionary, me: bool) -> void:
	var here: bool = not e.has("room") or e["room"] == game.local_agent.room
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
			var v: Agent = game.agent_of(e["pid"])
			if v.room == game.local_agent.room:
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
