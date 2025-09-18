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
const DISCOVERY_DEBUG := true
const USE_DEV_TEST_TEMP := true
const DEV_TEST_SCENE_PATH := "res://scenes/dev/dev_test.tscn"

# UDP sockets and timers for LAN discovery
var _udp_listener: PacketPeerUDP = PacketPeerUDP.new()
var _udp_broadcaster: PacketPeerUDP = PacketPeerUDP.new()
var _discovery_poll_timer: Timer
var _broadcast_timer: Timer
var _listening: bool = false
var _discovered_lobbies: Dictionary = {}

# Modular helpers
var discovery: LanDiscovery
var lobby_sync: LobbySync


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

	# Instantiate modular helpers
	discovery = LanDiscovery.new()
	discovery.name = "LanDiscovery"
	add_child(discovery)
	discovery.configure(DISCOVERY_PORT, DISCOVERY_MAGIC)
	discovery.debug = DISCOVERY_DEBUG
	discovery.lobby_found.connect(_on_discovery_lobby_found)
	discovery.set_payload_provider(Callable(self, "_get_lobby_info_payload"))

	lobby_sync = LobbySync.new()
	lobby_sync.name = "LobbySync"
	add_child(lobby_sync)


func create_lobby(player_name: String, _lobby_name: String, max_players: int, _timer_setting: String) -> void:
	var peer = ENetMultiplayerPeer.new()
	var error: int = peer.create_server(DEFAULT_PORT, max_players - 1) # Max peers is exclusive of host
	if error != OK:
		print("SERVER CREATION FAILED")
		connection_failed.emit()
		return

	multiplayer.multiplayer_peer = peer
	# Host is always ID 1
	_add_player_data(1, player_name)
	# Save lobby metadata and broadcast to UI
	var code: String = _generate_room_code()
	my_lobby_data = {
		"name": _lobby_name,
		"max_players": max_players,
		"timer_setting": _timer_setting,
		"room_code": code,
		"is_host": true
	}
	lobby_data_changed.emit(my_lobby_data)
	# Start broadcasting this lobby so LAN clients can discover it
	_start_host_broadcast()
	connection_succeeded.emit()

func join_lobby(player_name: String, ip: String) -> void:
	var peer = ENetMultiplayerPeer.new()
	var error: int = peer.create_client(ip, DEFAULT_PORT)
	if error != OK:
		print("CLIENT CREATION FAILED")
		connection_failed.emit()
		return
	
	multiplayer.multiplayer_peer = peer
	# The 'connected_to_server' signal will handle next steps

func _on_discovery_lobby_found(data: Dictionary) -> void:
	# Mirror discovery results to our own store and re-emit to UI
	if data.has("ip"):
		_discovered_lobbies[String(data["ip"]) ] = data
	lobby_found.emit(data)

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
	var nm: String = get_local_player_name()
	var my_name: String = nm if not nm.is_empty() else ("Player" + str(multiplayer.get_unique_id()))
	lobby_sync.register_with_server.rpc_id(1, my_name)
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

## Removed: stop_lan_discovery_and_reset merged into simpler flows

func start_listening_for_lobbies() -> void:
	if _listening:
		return
	print("[DISCOVERY] Starting listener on UDP:", DISCOVERY_PORT)
	_listening = true
	_discovered_lobbies.clear()
	discovery.start_listening()

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
	var num: String = str(randi_range(1000, 9999))
	return "%s%s_%s" % [adj, ani, num]

func _load_local_name_from_config() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	var err: int = cfg.load("user://settings.cfg")
	if err == OK:
		local_player_name = String(cfg.get_value("player", "name", ""))

func _save_local_name_to_config() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	var err: int = cfg.load("user://settings.cfg")
	# Ignore err; we'll overwrite
	cfg.set_value("player", "name", local_player_name)
	cfg.save("user://settings.cfg")

func request_char_selection(index: int) -> void:
	# Client-side helper: send selection request to server
	lobby_sync.rpc_request_char_selection.rpc(index)

func request_unlock() -> void:
	# Client-side helper: send unlock (-1) to server
	lobby_sync.rpc_request_char_selection.rpc(-1)

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
	# Switch everyone to the dev test scene temporarily (toggleable)
	var target_scene: String = DEV_TEST_SCENE_PATH if USE_DEV_TEST_TEMP else "res://scenes/world.tscn"
	SceneChanger.change_scene_to_file(target_scene)

func leave_lobby() -> void:
	multiplayer.multiplayer_peer = null
	players.clear()
	emit_signal("player_list_changed", players)
	_stop_host_broadcast()
	stop_lan_discovery()

# --- LAN Discovery internals ---
func _poll_discovery() -> void:
	# No-op: handled by LanDiscovery
	pass

func _start_host_broadcast() -> void:
	# Delegate to LanDiscovery
	discovery.start_broadcasting()

func _stop_host_broadcast() -> void:
	# Delegate to LanDiscovery
	discovery.stop_broadcasting()

func _broadcast_lobby() -> void:
	# No-op: broadcasting handled by LanDiscovery, which pulls payload via provider
	pass

func _get_lobby_info_payload() -> Dictionary:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return {}
	return {
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

func stop_lan_discovery() -> void:
	if _discovery_poll_timer:
		_discovery_poll_timer.stop()
	_listening = false
	discovery.stop_listening()
	_discovered_lobbies.clear()

func find_lobby_by_code(code: String) -> void:
	var upper: String = code.strip_edges().to_upper()
	for ip in _discovered_lobbies:
		var data: Dictionary = _discovered_lobbies[ip]
		if String(data.get("room_code", "")).to_upper() == upper:
			lobby_found.emit(data)
			return
	print("[Discovery] No lobby found for code via LAN:", upper)

# --- Room Code Generation ---
func _generate_room_code(len: int = 6) -> String:
	var chars := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" # Avoid ambiguous O/0, I/1
	var code := ""
	for i in len:
		code += chars[int(randi() % chars.length())]
	return code

# --- RPCs (Remote Procedure Calls) ---


## Lobby RPCs are handled by LobbySync child node



# --- Helpers ---
func _get_lan_ipv4() -> String:
	var addrs: PackedStringArray = IP.get_local_addresses()
	for a in addrs:
		# Skip loopback/APIPA/virtual adapters commonly seen on Windows
		if a.begins_with("127.") or a.begins_with("0.") or a.begins_with("169.254."):
			continue
		# Prefer to avoid VirtualBox Host-Only adapter
		if a.begins_with("192.168.56."):
			continue
		if a.begins_with("192.168.") or a.begins_with("10."):
			return a
		if a.begins_with("172."):
			var parts := a.split(".")
			if parts.size() >= 2:
				var s := int(parts[1])
				if s >= 16 and s <= 31:
					return a
	return ""

func get_local_ipv4() -> String:
	return _get_lan_ipv4()
