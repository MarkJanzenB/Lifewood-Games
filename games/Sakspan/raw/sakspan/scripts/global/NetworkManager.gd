# res://scripts/global/NetworkManager.gd
extends Node

signal connection_succeeded
signal connection_failed
signal player_list_changed(players_dict)
signal lobby_found(lobby_info)
signal game_started(player_data)
signal lobby_data_changed(lobby_data)

# Master list of all players in the lobby/game.
# Structure: {1: {"name": "HostName"}, 54321: {"name": "ClientName"}}
var players: Dictionary = {}
var my_lobby_data: Dictionary = {}  # Lobby metadata storage
var is_game_started: bool = false  # Add game state tracking
var local_player_name: String = ""  # Stored name picked on the Multiplayer menu

const DEFAULT_PORT = 8080 # Updated to more open port
const DISCOVERY_PORT := 9001
const DISCOVERY_MAGIC := "SAKSPAN_V1"

# UDP sockets and timers for LAN discovery
var _udp_listener: PacketPeerUDP = PacketPeerUDP.new()
var _udp_broadcaster: PacketPeerUDP = PacketPeerUDP.new()
var _discovery_poll_timer: Timer
var _broadcast_timer: Timer
var _listening: bool = false
var _discovered_lobbies: Dictionary = {}


func _ready() -> void:
	# Connect multiplayer signals
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)

	# Load persisted local player name (or generate a friendly default)
	_load_local_name_from_config()
	if local_player_name.is_empty():
		randomize_local_player_name()

	
	# Timers for LAN discovery
	_discovery_poll_timer = Timer.new()
	_discovery_poll_timer.one_shot = false
	_discovery_poll_timer.wait_time = 0.2
	add_child(_discovery_poll_timer)
	_discovery_poll_timer.timeout.connect(_poll_discovery)

	_broadcast_timer = Timer.new()
	_broadcast_timer.one_shot = false
	_broadcast_timer.wait_time = 1.0
	add_child(_broadcast_timer)
	_broadcast_timer.timeout.connect(_broadcast_lobby)

func create_lobby(player_name: String, _lobby_name: String, max_players: int, _timer_setting: String) -> void:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(DEFAULT_PORT, max_players - 1) # Max peers is exclusive of host
	if error != OK:
		print("SERVER CREATION FAILED")
		connection_failed.emit()
		return

	multiplayer.multiplayer_peer = peer
	# Host is always ID 1
	_add_player_data(1, player_name)
	# Save lobby metadata and broadcast to UI
	my_lobby_data = {
		"name": _lobby_name,
		"max_players": max_players,
		"timer_setting": _timer_setting,
		"room_code": "",
		"is_host": true
	}
	lobby_data_changed.emit(my_lobby_data)
	# Start broadcasting this lobby so LAN clients can discover it
	_start_host_broadcast()
	connection_succeeded.emit()

func join_lobby(player_name: String, ip: String) -> void:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, DEFAULT_PORT)
	if error != OK:
		print("CLIENT CREATION FAILED")
		connection_failed.emit()
		return
	
	multiplayer.multiplayer_peer = peer
	# The 'connected_to_server' signal will handle next steps

func _add_player_data(id: int, name: String) -> void:
	players[id] = {
		"name": name,
		"char_index": -1,
		"is_host": id == 1
	}
	player_list_changed.emit(players)
	print("Updated Players List: ", players)

func _remove_player_data(id: int) -> void:
	if players.has(id):
		players.erase(id)
		player_list_changed.emit(players)
		print("Updated Players List: ", players)

# --- Signal Handlers ---

func _on_peer_connected(id: int) -> void:
	print("Peer connected: %s" % id)

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: %s" % id)
	_remove_player_data(id)

func _on_connected_to_server() -> void:
	print("Successfully connected to the server!")
	# Now that we're connected, tell the server who we are.
	# It's important to get the player's name from your UI here.
	# For now, we use a placeholder.
	var nm := get_local_player_name()
	var my_name = nm if not nm.is_empty() else ("Player" + str(multiplayer.get_unique_id()))
	register_with_server.rpc_id(1, my_name)
	connection_succeeded.emit()

func _on_connection_failed() -> void:
	print("CONNECTION FAILED.")
	multiplayer.multiplayer_peer = null
	connection_failed.emit()

func _on_server_disconnected() -> void:
	print("DISCONNECTED FROM SERVER.")
	multiplayer.multiplayer_peer = null
	players.clear()
	# Here you would typically change scene back to the main menu.
	# SceneChanger.change_scene_to_file("res://scenes/UI/Main_Menu/main_menu.tscn")

func stop_lan_discovery_and_reset() -> void:
	# Clear any existing multiplayer peer
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null

	# Clear player list
	players.clear()
	player_list_changed.emit(players)
	print("Stopped LAN discovery and reset network state")

func start_listening_for_lobbies() -> void:
	if _listening:
		return
	print("[DISCOVERY] Starting listener on UDP:", DISCOVERY_PORT)
	# Recreate the listener to ensure clean state
	_udp_listener = PacketPeerUDP.new()
	var bind_err := _udp_listener.bind(DISCOVERY_PORT, "0.0.0.0")
	if bind_err != OK:
		push_error("[DISCOVERY] Failed to bind UDP listener: " + str(bind_err))
		return
	_listening = true
	_discovery_poll_timer.start()
	_discovered_lobbies.clear()

# --- UI helper methods to avoid missing symbol errors ---
func request_lobby_resync() -> void:
	emit_signal("lobby_data_changed", my_lobby_data)

func request_players_resync() -> void:
	emit_signal("player_list_changed", players)

# --- Local Player Name Management ---
func get_local_player_name() -> String:
	return local_player_name

func set_local_player_name(name: String) -> void:
	var cleaned := _sanitize_name(name)
	if cleaned.is_empty():
		cleaned = _generate_random_name()
	local_player_name = cleaned
	_save_local_name_to_config()

func randomize_local_player_name() -> String:
	local_player_name = _generate_random_name()
	_save_local_name_to_config()
	return local_player_name

func _sanitize_name(n: String) -> String:
	var s := n.strip_edges()
	# Allow ASCII letters, digits, space and hyphen only (simplified, safe)
	var out := ""
	for ch in s:
		var c := String(ch)
		var code := int(c.unicode_at(0)) if c.length() > 0 else 0
		var is_digit := code >= 48 and code <= 57
		var is_upper := code >= 65 and code <= 90
		var is_lower := code >= 97 and code <= 122
		if is_digit or is_upper or is_lower or c == " " or c == "-":
			out += c
	# Clamp length
	if out.length() > 18:
		out = out.substr(0, 18)
	return out

func _generate_random_name() -> String:
	var adjectives: Array[String] = ["Swift", "Brave", "Clever", "Mighty", "Sneaky", "Lucky", "Bold", "Chill"]
	var critters: Array[String] = ["Fox", "Wolf", "Panda", "Hawk", "Tiger", "Otter", "Lynx", "Koala"]
	var adj: String = adjectives[int(randi() % adjectives.size())]
	var ani: String = critters[int(randi() % critters.size())]
	var num := str(randi_range(1000, 9999))
	return "%s%s_%s" % [adj, ani, num]

func _load_local_name_from_config() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load("user://settings.cfg")
	if err == OK:
		local_player_name = String(cfg.get_value("player", "name", ""))

func _save_local_name_to_config() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load("user://settings.cfg")
	# Ignore err; we'll overwrite
	cfg.set_value("player", "name", local_player_name)
	cfg.save("user://settings.cfg")

func request_char_selection(index: int) -> void:
	# Client-side helper: send selection request to server
	rpc_request_char_selection.rpc(index)

func request_unlock() -> void:
	# Client-side helper: send unlock (-1) to server
	rpc_request_char_selection.rpc(-1)

func start_game() -> void:
	# Host triggers the actual game start; server instructs all peers
	if multiplayer.is_server():
		rpc("rpc_start_game", my_lobby_data)
	else:
		print("[StartGame] Only host can start the game.")

@rpc("authority", "call_local", "reliable")
func rpc_start_game(lobby_info: Dictionary) -> void:
	is_game_started = true
	emit_signal("game_started", players)
	# Switch everyone to the world scene
	SceneChanger.change_scene_to_file("res://scenes/world.tscn")

func leave_lobby() -> void:
	multiplayer.multiplayer_peer = null
	players.clear()
	emit_signal("player_list_changed", players)
	_stop_host_broadcast()
	stop_lan_discovery()

# --- LAN Discovery internals ---
func _poll_discovery() -> void:
	if not _listening:
		return
	while _udp_listener.get_available_packet_count() > 0:
		var pkt := _udp_listener.get_packet()
		var text := pkt.get_string_from_utf8()
		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = parsed
		if data.get("magic", "") != DISCOVERY_MAGIC:
			continue
		# Normalize and emit
		var ip := String(data.get("host_ip", data.get("ip", "")))
		data["ip"] = ip
		_discovered_lobbies[ip] = data
		lobby_found.emit(data)

func _start_host_broadcast() -> void:
	# Host broadcasts lobby info periodically
	_udp_broadcaster = PacketPeerUDP.new()
	_udp_broadcaster.set_broadcast_enabled(true)
	_broadcast_timer.start()

func _stop_host_broadcast() -> void:
	if _broadcast_timer:
		_broadcast_timer.stop()
	_udp_broadcaster = PacketPeerUDP.new()

func _broadcast_lobby() -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	var info := {
		"magic": DISCOVERY_MAGIC,
		"name": String(my_lobby_data.get("name", "")),
		"room_code": String(my_lobby_data.get("room_code", "")),
		"max_players": int(my_lobby_data.get("max_players", 5)),
		"current_players": players.size(),
		"timer": String(my_lobby_data.get("timer_setting", "5 minutes")),
		"host_ip": _get_lan_ipv4(),
		"port": DEFAULT_PORT,
		"status": ("full" if players.size() >= int(my_lobby_data.get("max_players", 5)) else "waiting")
	}
	var bytes := JSON.stringify(info).to_utf8_buffer()
	_udp_broadcaster.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_udp_broadcaster.put_packet(bytes)

func stop_lan_discovery() -> void:
	if _discovery_poll_timer:
		_discovery_poll_timer.stop()
	_listening = false
	_udp_listener = PacketPeerUDP.new()
	_discovered_lobbies.clear()

func find_lobby_by_code(code: String) -> void:
	var upper := code.strip_edges().to_upper()
	for ip in _discovered_lobbies:
		var data: Dictionary = _discovered_lobbies[ip]
		if String(data.get("room_code", "")).to_upper() == upper:
			lobby_found.emit(data)
			return
	print("[Discovery] No lobby found for code:", upper)

# --- RPCs (Remote Procedure Calls) ---

@rpc("any_peer", "reliable")
func register_with_server(player_name: String) -> void:
	# This function ONLY runs on the server.
	var sender_id = multiplayer.get_remote_sender_id()
	
	# Add the new player to the server's list.
	_add_player_data(sender_id, player_name)

	# Now, tell the new player about everyone who was already in the lobby.
	for existing_id in players:
		if existing_id != sender_id:
			sync_new_player.rpc_id(sender_id, existing_id, players[existing_id]["name"])

	# Finally, tell everyone (including the new player) about the new player.
	sync_new_player.rpc(sender_id, player_name)

@rpc("authority", "reliable")
func sync_new_player(id: int, name: String) -> void:
	# This function runs on ALL clients to inform them of a new player.
	_add_player_data(id, name)

# Clients request a character selection; server validates and broadcasts
@rpc("any_peer", "call_local", "reliable")
func rpc_request_char_selection(index: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	# When the host triggers this locally, remote sender is 0. Map to self (server's unique ID).
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	# Enforce basic bounds and uniqueness (optional)
	if index < -1 or index > 10: # arbitrary upper bound; adjust to your roster
		return
	# Assign
	if players.has(sender_id):
		players[sender_id]["char_index"] = index
		sync_char_selection.rpc(sender_id, index)
		player_list_changed.emit(players)

## No separate RPC for unlock; use rpc_request_char_selection(-1)

@rpc("authority", "call_local", "reliable")
func sync_char_selection(id: int, index: int) -> void:
	if not players.has(id):
		return
	players[id]["char_index"] = index
	player_list_changed.emit(players)



# --- Helpers ---
func _get_lan_ipv4() -> String:
	var addrs: PackedStringArray = IP.get_local_addresses()
	for a in addrs:
		if a.begins_with("192.168.") or a.begins_with("10."):
			return a
		if a.begins_with("172."):
			var parts := a.split(".")
			if parts.size() >= 2:
				var s := int(parts[1])
				if s >= 16 and s <= 31:
					return a
	return ""
