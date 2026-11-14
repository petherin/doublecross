extends Node
## Networking: hosting/joining a 2-player game over the local network,
## plus LAN auto-discovery so nobody has to type IP addresses.

signal opponent_joined(peer_id: int)
signal joined_host
signal join_failed
signal session_ended(reason: String)
signal hosts_changed

const GAME_PORT := 47810
const DISCOVERY_PORT := 47811
const MAGIC := "DBLX1"
const HOST_TIMEOUT := 3.5

## This build's version ("0.27" on released builds, "dev" from the editor).
## Both devices must run the same version to play together.
var version: String = str(ProjectSettings.get_setting("application/config/version", "dev"))
## True once a two-player match has started (before that, a host keeps its
## lobby open if a joiner is turned away).
var in_game := false

var is_hosting := false
var in_session := false
## ip -> { "name": String, "seen": float }
var discovered := {}

var _broadcaster: PacketPeerUDP
var _listener: PacketPeerUDP
var _broadcast_timer := 0.0
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
	_broadcaster = PacketPeerUDP.new()
	_broadcaster.set_broadcast_enabled(true)
	_broadcaster.set_dest_address("255.255.255.255", DISCOVERY_PORT)
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
	if _broadcaster:
		_broadcaster.close()
		_broadcaster = null


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
		_listener = null


func stop_listening() -> void:
	if _listener:
		_listener.close()
		_listener = null
	discovered.clear()


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
			_broadcast_timer = 1.0
			var msg := "%s|%s|%s" % [MAGIC, OS.get_model_name(), version]
			_broadcaster.put_packet(msg.to_utf8_buffer())
	if _listener:
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
	if _broadcaster:
		return
	_broadcaster = PacketPeerUDP.new()
	_broadcaster.set_broadcast_enabled(true)
	_broadcaster.set_dest_address("255.255.255.255", DISCOVERY_PORT)


func _on_connection_failed() -> void:
	end_session("")
	join_failed.emit()
