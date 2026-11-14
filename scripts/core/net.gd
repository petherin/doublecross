extends Node
## Networking: hosting/joining a 2-player game over the local network,
## plus LAN discovery so nobody has to type IP addresses.
##
## Discovery works two ways, because many Android phones silently drop
## broadcast packets:
## - the host broadcasts "DBLX1|codename|version" every few seconds, and
## - joiners scan: they send a probe to every address on their subnet and a
##   host answers each probe directly (unicast), which phones always receive.

signal opponent_joined(peer_id: int)
signal joined_host
signal join_failed
signal session_ended(reason: String)
signal hosts_changed

const GAME_PORT := 47810
const DISCOVERY_PORT := 47811
const PROBE_PORT := 47812
const PROBE := "DBLX1?"
## Seconds between automatic subnet scans while idle on the multiplayer menu.
const SCAN_INTERVAL := 10.0
## Minimum gap between scans, including manual refreshes.
const MIN_SCAN_GAP := 2.0
## Seconds between host announcements.
const BROADCAST_INTERVAL := 3.0
const MAGIC := "DBLX1"
const HOST_TIMEOUT := 25.0

## This build's version ("0.27" on released builds, "dev" from the editor).
## Both devices must run the same version to play together.
var version: String = str(ProjectSettings.get_setting("application/config/version", "dev"))
## True once a two-player match has started (before that, a host keeps its
## lobby open if a joiner is turned away).
var in_game := false

var is_hosting := false
var in_session := false
## ip -> { "name": String, "version": String, "seen": float }
var discovered := {}

var _broadcaster: PacketPeerUDP
var _responder: PacketPeerUDP
var _listener: PacketPeerUDP
var _broadcast_timer := 0.0
var _scan_timer := 0.0
var _last_scan_clock := -MIN_SCAN_GAP
var _clock := 0.0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func(): joined_host.emit())
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(func(): end_session("The host left the game."))


func host() -> Error:
	end_session("")
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(GAME_PORT, 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_hosting = true
	in_session = true
	_start_broadcasting()
	return OK


func join(ip: String) -> Error:
	end_session("")
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, GAME_PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	in_session = true
	return OK


func stop_broadcasting() -> void:
	_broadcast_timer = 0.0
	if _broadcaster:
		_broadcaster.close()
		_broadcaster = null
	if _responder:
		_responder.close()
		_responder = null


## Tears down the current connection. A non-empty reason is reported to the UI.
func end_session(reason: String) -> void:
	stop_broadcasting()
	var was_in_session := in_session
	in_game = false
	is_hosting = false
	in_session = false
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if was_in_session and reason != "":
		session_ended.emit(reason)


func start_listening() -> void:
	if _listener:
		return
	_listener = PacketPeerUDP.new()
	if _listener.bind(DISCOVERY_PORT) != OK:
		# Port busy (e.g. a second copy on this computer): any port will do
		# for scanning, since hosts answer probes directly.
		_listener = PacketPeerUDP.new()
		if _listener.bind(0) != OK:
			_listener = null
	scan()


func stop_listening() -> void:
	if _listener:
		_listener.close()
		_listener = null
	_scan_timer = 0.0
	_last_scan_clock = -MIN_SCAN_GAP
	var had_hosts := not discovered.is_empty()
	discovered.clear()
	if had_hosts:
		hosts_changed.emit()


## Probes every address on this device's local subnet(s) for a host.
func scan() -> void:
	if _listener == null:
		return
	# FIND HOST can request an immediate scan, but repeated clicks must not
	# turn into a burst of hundreds of UDP probes.
	if _clock - _last_scan_clock < MIN_SCAN_GAP:
		return
	_last_scan_clock = _clock
	_scan_timer = SCAN_INTERVAL
	var probe := PROBE.to_utf8_buffer()
	var mine := IP.get_local_addresses()
	for addr: String in _lan_addresses():
		var prefix := addr.substr(0, addr.rfind(".") + 1)
		for i in range(1, 255):
			var target: String = prefix + str(i)
			if target in mine:
				continue
			_listener.set_dest_address(target, PROBE_PORT)
			_listener.put_packet(probe)


## This device's private IPv4 addresses (home/office Wi-Fi ranges).
func _lan_addresses() -> Array:
	var out := []
	for addr in IP.get_local_addresses():
		if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172."):
			out.append(addr)
	return out


## Best guess at this device's LAN address, shown on the host screen
## so the other player can type it in if auto-discovery is blocked.
func local_ip() -> String:
	var best := ""
	for addr in IP.get_local_addresses():
		if addr.contains(":") or addr.begins_with("127.") or addr.begins_with("169.254."):
			continue
		if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172."):
			return addr
		best = addr
	return best if best != "" else "unknown"


func _process(delta: float) -> void:
	_clock += delta
	if _broadcaster:
		_broadcast_timer -= delta
		if _broadcast_timer <= 0.0:
			_broadcast_timer = BROADCAST_INTERVAL
			_broadcaster.put_packet(_announcement())
	if _responder:
		# Answer joiners' probes directly.
		while _responder.get_available_packet_count() > 0:
			var data := _responder.get_packet().get_string_from_utf8()
			if data == PROBE:
				_responder.set_dest_address(_responder.get_packet_ip(), _responder.get_packet_port())
				_responder.put_packet(_announcement())
	if _listener:
		_scan_timer -= delta
		if _scan_timer <= 0.0:
			scan()
		var changed := false
		while _listener.get_available_packet_count() > 0:
			var data := _listener.get_packet().get_string_from_utf8()
			var ip := _listener.get_packet_ip()
			var parts := data.split("|")
			if parts.size() >= 2 and parts[0] == MAGIC and ip != "":
				if not discovered.has(ip):
					changed = true
				discovered[ip] = {"name": parts[1], "version": parts[2] if parts.size() > 2 else "?", "seen": _clock}
		for ip in discovered.keys():
			if _clock - discovered[ip]["seen"] > HOST_TIMEOUT:
				discovered.erase(ip)
				changed = true
		if changed:
			hosts_changed.emit()


func _on_peer_connected(id: int) -> void:
	if is_hosting:
		stop_broadcasting()
		opponent_joined.emit(id)


func _on_peer_disconnected(_id: int) -> void:
	if is_hosting and not in_game:
		# A joiner left (or was turned away) before the match: keep waiting.
		_start_broadcasting()
		return
	end_session("Your opponent disconnected.")


## Disconnects a joining device (e.g. one running a different version).
func kick(id: int) -> void:
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(id)


func _start_broadcasting() -> void:
	if _broadcaster == null:
		_broadcaster = PacketPeerUDP.new()
		_broadcaster.set_broadcast_enabled(true)
		_broadcaster.set_dest_address("255.255.255.255", DISCOVERY_PORT)
		_broadcast_timer = 0.0
	if _responder == null:
		_responder = PacketPeerUDP.new()
		if _responder.bind(PROBE_PORT) != OK:
			_responder = null


## What a host says about itself: magic|codename|version.
func _announcement() -> PackedByteArray:
	var host_name := Settings.player_name.strip_edges().left(14)
	if host_name == "":
		host_name = "UNKNOWN"
	return ("%s|%s|%s" % [MAGIC, host_name, version]).to_utf8_buffer()


func _on_connection_failed() -> void:
	end_session("")
	join_failed.emit()
