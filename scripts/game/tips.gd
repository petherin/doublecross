extends Node
## One-off field tips for new agents, typed on the ticker tape the first time
## each situation comes up (and never again on this device).

const World = preload("res://scripts/core/world.gd")

const TEXT := {
	"search": "TIP: stand by furniture until it glows, then press SEARCH.",
	"vent": "TIP: a vent! Press CRAWL to shuffle through the ducts to a room further away.",
	"rival": "TIP: a rival! ATTACK swings your cosh up close; FIRE shoots a dart from range.",
	"full": "TIP: no briefcase, so you can carry one item at a time. Find one!",
	"trap": "TIP: press TRAP to hide a nasty surprise in furniture, or a tripwire in a doorway.",
	"exit": "TIP: that glowing doorway is the EXIT. It opens once you hold all four pieces of intel.",
	"low": "TIP: under 30 seconds! When your clock runs out, you're out of the mission.",
}
## Seconds between tips, so they don't pile up on the ticker tape.
const GAP := 7.0

var game: Node
var _quiet := 4.0


func _init(p_game: Node) -> void:
	game = p_game


func _process(delta: float) -> void:
	_quiet -= delta
	if _quiet > 0.0 or game.over or game.local_agent == null or game.local_agent.frozen:
		return
	var a = game.local_agent
	if game.nearest_furniture(a) != -1:
		_show("search")
	elif game.world.vent_near(a.room, a.position) != -1:
		_show("vent")
	elif game.rival_near(a, 1.0e9) != null:
		_show("rival")
	elif game.world.exit_room == a.room:
		_show("exit")
	elif not game.inventories[game.my_id]["items"].is_empty() and not game.inventories[game.my_id]["case"]:
		_show("full")
	elif game.clocks.get(game.my_id, 999.0) < 30.0:
		_show("low")
	elif _quiet < -40.0:
		_show("trap")


func _show(id: String) -> void:
	if Settings.tips_seen.has(id):
		return
	Settings.tips_seen[id] = true
	Settings.save()
	game.hud.toast(TEXT[id], Color(0.85, 0.95, 1.0), 4.5)
	_quiet = GAP
