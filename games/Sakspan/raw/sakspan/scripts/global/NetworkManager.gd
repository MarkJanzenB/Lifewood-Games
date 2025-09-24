# res://scripts/global/NetworkManager.gd
extends Node

signal connection_succeeded
signal connection_failed
signal player_list_changed(players_dict)
signal lobby_found(lobby_info)
signal game_started(player_data)
signal lobby_data_changed(lobby_data)
signal player_joined(player_id: int, player_data: Dictionary)
signal player_left(player_id: int)
signal game_world_ready
signal all_peers_verified_and_ready  # CRITICAL: Signal for GameManager initialization

# Master list of all players in the lobby/game.
# Structure: {1: {"name": "HostName", "ready": false, "char_index": -1}, 54321: {"name": "ClientName", "ready": false, "char_index": -1}}
var players: Dictionary = {}
var my_lobby_data: Dictionary = {}  # Lobby metadata storage
var is_game_started: bool = false  # Add game state tracking
var local_player_name: String = ""  # Stored name picked on the Multiplayer menu
var game_scene_loaded: bool = false

# SYNCHRONIZATION BARRIER: Track which peers have loaded the scene
var ready_peers: Array = []

const DEFAULT_PORT: int = 8080
const ALTERNATIVE_PORTS: Array[int] = [8080, 7777, 9999, 12345, 25565]
const DISCOVERY_PORT := 9001
const DISCOVERY_MAGIC := "SAKSPAN_V1"
const DISCOVERY_DEBUG := true
const USE_DEV_TEST_TEMP := true  # Enable dev_test environment
const GAMEPREP_SCENE_PATH := "res://scenes/GamePrep.tscn"
const DEV_TEST_SCENE_PATH := "res://scenes/dev/dev_world.tscn"
const WORLD_SCENE_PATH := "res://scenes/world.tscn"

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
	print("[CreateLobby] Creating server on port ", DEFAULT_PORT)
	print("[CreateLobby] Max players: ", max_players, " (", max_players - 1, " peers)")
	print("[CreateLobby] Host name: ", player_name)
	
	var peer = ENetMultiplayerPeer.new()
	var error: int = peer.create_server(DEFAULT_PORT, max_players - 1) # Max peers is exclusive of host
	if error != OK:
		print("[CreateLobby] SERVER CREATION FAILED - Error code: ", error)
		print("[CreateLobby] Possible causes:")
		print("  - Port ", DEFAULT_PORT, " already in use")
		print("  - Insufficient permissions")
		print("  - Network adapter issues")
		connection_failed.emit()
		return

	print("[CreateLobby] Server created successfully!")
	multiplayer.multiplayer_peer = peer
	# Host is always ID 1
	var my_id = multiplayer.get_unique_id()
	print("[CreateLobby] Host ID: ", my_id)
	_add_player_data(my_id, player_name)
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
	print("[JoinLobby] Attempting to join lobby at ", ip, ":", DEFAULT_PORT)
	print("[JoinLobby] Player name: ", player_name)
	
	# Test basic connectivity first
	var diag = preload("res://scripts/global/NetworkDiagnostics.gd").new()
	if not diag.test_udp_connection(ip, DEFAULT_PORT):
		print("[JoinLobby] UDP connectivity test failed")
	
	var peer = ENetMultiplayerPeer.new()
	
	var error: int = peer.create_client(ip, DEFAULT_PORT)
	if error != OK:
		print("[JoinLobby] CLIENT CREATION FAILED - Error code: ", error)
		print("[JoinLobby] Error meanings:")
		print("  ERR_ALREADY_IN_USE (48): Port already in use")
		print("  ERR_CANT_CREATE (50): Cannot create client")
		print("  ERR_INVALID_PARAMETER (51): Invalid IP or port")
		connection_failed.emit()
		return
	
	print("[JoinLobby] ENet client created successfully, attempting connection...")
	multiplayer.multiplayer_peer = peer
	
	# Set a timer to detect connection timeout
	var timeout_timer = Timer.new()
	add_child(timeout_timer)
	timeout_timer.wait_time = 10.0  # 10 second timeout
	timeout_timer.one_shot = true
	timeout_timer.timeout.connect(_on_connection_timeout)
	timeout_timer.start()
	
	# Store timer reference to clean it up later
	set_meta("connection_timeout_timer", timeout_timer)

func _on_discovery_lobby_found(data: Dictionary) -> void:
	# Mirror discovery results to our own store and re-emit to UI
	if data.has("ip"):
		_discovered_lobbies[String(data["ip"]) ] = data
	lobby_found.emit(data)

func _add_player_data(id: int, name: String) -> void:
	players[id] = {
		"name": name,
		"char_index": -1,
		"is_host": id == 1,
		"ready": false
	}
	player_list_changed.emit(players)
	player_joined.emit(id, players[id])
	print("Updated Players List: ", players)

func _remove_player_data(id: int) -> void:
	if players.has(id):
		player_left.emit(id)
		players.erase(id)
		player_list_changed.emit(players)
		print("Updated Players List: ", players)

# --- Signal Handlers ---

func _on_peer_connected(id: int) -> void:
	print("[NetworkManager] Peer connected: %s" % id)
	print("[NetworkManager] Total peers now: ", multiplayer.get_peers().size() + 1)  # +1 for self

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: %s" % id)
	_remove_player_data(id)

func _on_connected_to_server() -> void:
	print("[NetworkManager] Successfully connected to the server!")
	print("[NetworkManager] My client ID: ", multiplayer.get_unique_id())
	print("[NetworkManager] Connected peers: ", multiplayer.get_peers())
	
	# Clean up connection timeout timer
	_cleanup_connection_timer()
	
	# Now that we're connected, tell the server who we are.
	var nm: String = get_local_player_name()
	var my_name: String = nm if not nm.is_empty() else ("Player" + str(multiplayer.get_unique_id()))
	print("[NetworkManager] Registering with server as: ", my_name)
	
	# Ensure LobbySync is ready before calling RPC
	if lobby_sync:
		lobby_sync.register_with_server.rpc_id(1, my_name)
		print("[NetworkManager] Registration RPC sent to server")
	else:
		print("[NetworkManager] ERROR: LobbySync not available!")
	
	connection_succeeded.emit()

func _on_connection_failed() -> void:
	print("[NetworkManager] CONNECTION FAILED.")
	print("[NetworkManager] Possible causes:")
	print("  - Host is not running or not accessible")
	print("  - Firewall blocking connection")
	print("  - Network connectivity issues")
	print("  - Port ", DEFAULT_PORT, " is blocked")
	
	# Clean up connection timeout timer
	_cleanup_connection_timer()
	
	multiplayer.multiplayer_peer = null
	connection_failed.emit()

func _on_server_disconnected() -> void:
	print("DISCONNECTED FROM SERVER.")
	multiplayer.multiplayer_peer = null
	players.clear()
	# Here you would typically change scene back to the main menu.
	# SceneChanger.change_scene_to_file("res://scenes/UI/Main_Menu/main_menu.tscn")

func _on_connection_timeout() -> void:
	print("[NetworkManager] CONNECTION TIMEOUT - No response from server")
	print("[NetworkManager] This usually means:")
	print("  - The host IP is wrong or unreachable")
	print("  - The host is not running a server")
	print("  - Network/firewall is blocking the connection")
	
	# Clean up and fail the connection
	multiplayer.multiplayer_peer = null
	_cleanup_connection_timer()
	connection_failed.emit()

func _cleanup_connection_timer() -> void:
	if has_meta("connection_timeout_timer"):
		var timer = get_meta("connection_timeout_timer")
		if timer and is_instance_valid(timer):
			timer.queue_free()
		remove_meta("connection_timeout_timer")

# Debug function to test connection status
func debug_connection_status():
	print("=== CONNECTION STATUS DEBUG ===")
	print("Multiplayer peer: ", multiplayer.multiplayer_peer)
	if multiplayer.multiplayer_peer:
		print("Peer type: ", "Server" if multiplayer.is_server() else "Client")
		print("My ID: ", multiplayer.get_unique_id())
		print("Connected peers: ", multiplayer.get_peers())
		print("Connection status: ", multiplayer.multiplayer_peer.get_connection_status())
	print("Players in lobby: ", players)
	print("Local player name: ", get_local_player_name())
	print("=== END DEBUG ===")

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
	print("[NetworkManager] === CHARACTER SELECTION REQUEST ===")
	print("[NetworkManager] Requesting character selection: ", index)
	print("[NetworkManager] My player ID: ", multiplayer.get_unique_id())
	print("[NetworkManager] Is server: ", multiplayer.is_server())
	print("[NetworkManager] Current players: ", players)
	print("[NetworkManager] Multiplayer peer: ", multiplayer.multiplayer_peer)
	print("[NetworkManager] Multiplayer peer status: ", multiplayer.multiplayer_peer.get_connection_status() if multiplayer.multiplayer_peer else "NULL")
	print("[NetworkManager] Connected peers: ", multiplayer.get_peers())
	
	if not CharacterFactory.is_valid_character_index(index):
		print("[NetworkManager] ERROR: Invalid character index: ", index)
		return
	
	if not multiplayer.multiplayer_peer:
		print("[NetworkManager] ERROR: No multiplayer peer connection!")
		return
	
	# For servers, the connection status might be different, so let's be more flexible
	var connection_status = multiplayer.multiplayer_peer.get_connection_status()
	if not multiplayer.is_server() and connection_status != MultiplayerPeer.CONNECTION_CONNECTED:
		print("[NetworkManager] ERROR: Client not connected to server! Status: ", connection_status)
		return
	elif multiplayer.is_server() and connection_status not in [MultiplayerPeer.CONNECTION_CONNECTED, MultiplayerPeer.CONNECTION_CONNECTING]:
		print("[NetworkManager] ERROR: Server peer not in valid state! Status: ", connection_status)
		return
	
	if lobby_sync:
		print("[NetworkManager] LobbySync found, attempting to send RPC to server...")
		print("[NetworkManager] LobbySync node: ", lobby_sync)
		print("[NetworkManager] LobbySync has rpc_request_char_selection method: ", lobby_sync.has_method("rpc_request_char_selection"))
		
		if multiplayer.is_server():
			# If we're the server, call the function directly instead of using RPC
			print("[NetworkManager] We are server - calling rpc_request_char_selection directly")
			lobby_sync.rpc_request_char_selection(index)
		else:
			# If we're a client, send RPC to server
			print("[NetworkManager] We are client - sending RPC to server")
			lobby_sync.rpc_request_char_selection.rpc(index)
		
		print("[NetworkManager] Character selection request completed successfully")
		
		# Don't update local state immediately - let the server handle it and sync back
		# This ensures consistent state across all clients and the host
		print("[NetworkManager] Waiting for server response to update character selection")
	else:
		print("[NetworkManager] ERROR: LobbySync not available!")
		print("[NetworkManager] Available children: ", get_children()) 

func request_unlock() -> void:
	# Helper: send unlock (-1) to server
	if lobby_sync:
		print("[NetworkManager] Sending unlock request to server")
		if multiplayer.is_server():
			# If we're the server, call the function directly
			print("[NetworkManager] We are server - calling rpc_request_char_selection directly for unlock")
			lobby_sync.rpc_request_char_selection(-1)
		else:
			# If we're a client, send RPC to server
			print("[NetworkManager] We are client - sending unlock RPC to server")
			lobby_sync.rpc_request_char_selection.rpc(-1)
	else:
		print("[NetworkManager] ERROR: LobbySync not available for unlock!")

## ... (rest of the code remains the same)
func get_player_character_index(player_id: int) -> int:
	if players.has(player_id):
		return int(players[player_id].get("char_index", -1))
	return -1

# Get the selected character name for a player
func get_player_character_name(player_id: int) -> String:
	var char_index = get_player_character_index(player_id)
	if char_index >= 0:
		return CharacterFactory.get_character_name(char_index)
	return "No Selection"

# Check if all players have selected characters
func all_players_ready() -> bool:
	if players.is_empty():
		return false
	
	for player_id in players:
		var char_index = int(players[player_id].get("char_index", -1))
		if char_index < 0:
			return false
	return true

func start_game() -> void:
	# DEFINITIVE SYNCHRONIZATION BARRIER: Host triggers scene loading and resets checklist
	if multiplayer.is_server():
		# Validate game can start
		if not _validate_game_start():
			print("[NetworkManager] Game cannot start - validation failed")
			return
		
		print("[NetworkManager] Starting game. Resetting readiness checklist.")
		
		# IMPORTANT: Reset the checklist before starting
		ready_peers.clear()
		print("[NetworkManager] 📋 Expecting ", players.size(), " peers to report readiness")
		
		# Tell all peers to load the world
		rpc_load_world.rpc()
	else:
		print("[StartGame] Only host can start the game.")

func _validate_game_start() -> bool:
	"""Validate that the game can start with current player setup"""
	print("[NetworkManager] Validating game start conditions...")
	
	# Check minimum player count
	if players.size() < 2:
		print("[NetworkManager] Not enough players (need at least 2, have ", players.size(), ")")
		return false
	
	# Check all players are ready (have character selected)
	var ready_count = 0
	for player_id in players:
		var char_index = int(players[player_id].get("char_index", -1))
		if char_index >= 0:
			ready_count += 1
	
	if ready_count != players.size():
		print("[NetworkManager] Not all players ready (", ready_count, "/", players.size(), ")")
		return false
	
	# Validate role assignment will work
	# For hide and seek, we need at least 1 seeker and 1 hider
	if players.size() < 2:
		print("[NetworkManager] Need at least 2 players for hide and seek")
		return false
	
	print("[NetworkManager] Game start validation passed - ", players.size(), " players ready")
	return true

# Pre-game countdown system
@rpc("authority", "call_local", "reliable")
func rpc_show_start_countdown(countdown_seconds: int) -> void:
	print("[NetworkManager] Starting countdown: ", countdown_seconds, " seconds")
	emit_signal("lobby_data_changed", {"countdown": countdown_seconds, "status": "starting"})
	
	# Start local countdown timer
	var countdown_timer = Timer.new()
	add_child(countdown_timer)
	countdown_timer.wait_time = 1.0
	countdown_timer.timeout.connect(_on_countdown_tick.bind(countdown_seconds, countdown_timer))
	countdown_timer.start()

func _on_countdown_tick(remaining_seconds: int, timer: Timer) -> void:
	remaining_seconds -= 1
	
	if remaining_seconds > 0:
		print("[NetworkManager] Countdown: ", remaining_seconds)
		emit_signal("lobby_data_changed", {"countdown": remaining_seconds, "status": "starting"})
		# Continue countdown
		timer.timeout.disconnect(_on_countdown_tick)
		timer.timeout.connect(_on_countdown_tick.bind(remaining_seconds, timer))
	else:
		print("[NetworkManager] Countdown finished - starting game!")
		timer.queue_free()
		
		# Only server actually starts the game
		if multiplayer.is_server():
			rpc_start_game.rpc(my_lobby_data)

# SCENE-DRIVEN INITIALIZATION: Simple scene loader
@rpc("any_peer", "call_local", "reliable")
func rpc_load_world() -> void:
	print("[NetworkManager] 🌍 SCENE-DRIVEN: Loading world scene...")
	is_game_started = true
	game_scene_loaded = false
	emit_signal("game_started", players)
	
	# PHASE 2: Load GamePrep scene first for role assignment
	var target_scene: String = GAMEPREP_SCENE_PATH
	print("[NetworkManager] 📡 Switching to GamePrep scene: ", target_scene)
	get_tree().change_scene_to_file(target_scene)

# PHASE 2: Function for GameManager to transition from GamePrep to dev_world
func change_to_dev_world() -> void:
	"""Called by GameManager after GamePrep countdown finishes"""
	if not multiplayer.is_server():
		return
	
	var target_scene: String = DEV_TEST_SCENE_PATH if USE_DEV_TEST_TEMP else WORLD_SCENE_PATH
	print("[NetworkManager] 🎮 Transitioning from GamePrep to game world: ", target_scene)
	
	# Connect scene change detection for game_world_ready signal
	get_tree().tree_changed.connect(_on_scene_changed, CONNECT_ONE_SHOT)
	get_tree().change_scene_to_file(target_scene)

func _on_scene_changed() -> void:
	"""Called when scene transition completes - emits game_world_ready for GameManager"""
	if not multiplayer.is_server():
		return
	
	var current_scene = get_tree().current_scene
	if current_scene and current_scene.scene_file_path == DEV_TEST_SCENE_PATH:
		print("[NetworkManager] 🎯 Game world scene loaded: ", current_scene.scene_file_path)
		
		# Wait one frame to ensure scene is fully initialized
		await get_tree().process_frame
		
		print("[NetworkManager] 🚀 Emitting game_world_ready signal to GameManager")
		game_world_ready.emit()

# DEFINITIVE SYNCHRONIZATION BARRIER: RPC called by dev_world.gd when scene is ready
# The decorator MUST allow the server to call it on itself
@rpc("any_peer", "call_local", "reliable")
func report_readiness(peer_id: int) -> void:
	# This function only executes on the server
	if not multiplayer.is_server():
		return
	
	if not peer_id in ready_peers:
		ready_peers.append(peer_id)
		print("[NetworkManager] Peer ", peer_id, " checked in. (", ready_peers.size(), "/", players.size(), ")")
	
	# Check if the list is full
	if ready_peers.size() == players.size():
		print("[NetworkManager] ✅ All peers are ready. Beginning spawn sequence.")
		
		# Define staggered spawn points to prevent overlapping
		var spawn_points = [
			Vector2(200, 0),
			Vector2(-200, 0), 
			Vector2(0, 200),
			Vector2(0, -200),
			Vector2(150, 150),
			Vector2(-150, 150),
			Vector2(150, -150),
			Vector2(-150, -150)
		]
		
		# Spawn players on all clients with staggered positions
		var spawn_index = 0
		for player_id in players.keys():
			var player_data = players[player_id]
			var spawn_position = spawn_points[spawn_index % spawn_points.size()]
			print("[NetworkManager] 📡 Spawning player ", player_id, " (", player_data.name, ") at ", spawn_position)
			rpc_spawn_player_instance.rpc(player_id, player_data, spawn_position)
			spawn_index += 1
		
		# Wait one frame for the spawn RPCs to be processed
		await get_tree().process_frame
		
		# Now, with 100% certainty, the world is ready
		print("[NetworkManager] 🚀 Emitting all_peers_verified_and_ready signal")
		all_peers_verified_and_ready.emit()

# DEPRECATED: Old functions replaced by scene-driven pattern
@rpc("authority", "call_local", "reliable")
func rpc_start_game(lobby_info: Dictionary) -> void:
	print("[NetworkManager] ⚠️ DEPRECATED: rpc_start_game called - using scene-driven pattern instead")
	rpc_load_world()

func leave_lobby() -> void:
	# Change the scene FIRST, while the peer is still valid
	get_tree().change_scene_to_file("res://scenes/UI/Multiplayer/multiplayer_menu.tscn")
	
	# Now, clean up the network state after the transition is queued
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
	var host_ip = _get_lan_ipv4()
	print("[NetworkManager] Broadcasting lobby from IP: ", host_ip)
	return {
		"magic": DISCOVERY_MAGIC,
		"name": String(my_lobby_data.get("name", "")),
		"room_code": String(my_lobby_data.get("room_code", "")),
		"max_players": int(my_lobby_data.get("max_players", 5)),
		"current_players": players.size(),
		"timer": String(my_lobby_data.get("timer_setting", "5 minutes")),
		"host_ip": host_ip,
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

# --- Player Authority and Game State Management ---

func set_player_ready(player_id: int, ready: bool) -> void:
	if players.has(player_id):
		players[player_id]["ready"] = ready
		player_list_changed.emit(players)

func are_all_players_ready() -> bool:
	if players.is_empty():
		return false
	for id in players:
		if not players[id].get("ready", false):
			return false
	return true

func get_player_count() -> int:
	return players.size()

func update_player_role(id: int, role: String) -> void:
	# Helper used by GameManager to mirror role assignment in our players dict
	if players.has(id):
		players[id]["role"] = role
		player_list_changed.emit(players)

func reset_game_state() -> void:
	is_game_started = false
	game_scene_loaded = false
	for id in players:
		players[id]["ready"] = false
	player_list_changed.emit(players)

# Called when world scene is loaded and ready
func notify_game_scene_loaded() -> void:
	game_scene_loaded = true
	print("[NetworkManager] Game scene loaded and ready")

# Get spawn data for all players (used by World script)
func get_spawn_data() -> Dictionary:
	var spawn_data = {}
	var index = 0
	for id in players.keys():
		var char_index = int(players[id].get("char_index", 0))
		spawn_data[id] = {
			"name": players[id]["name"],
			"spawn_index": index,
			"char_index": char_index,
			"character_name": CharacterFactory.get_character_name(char_index),
			"is_host": players[id].get("is_host", false)
		}
		index += 1
	return spawn_data

# DEFINITIVE SYNCHRONIZATION BARRIER: Spawn player instances (guaranteed scene readiness)
@rpc("any_peer", "call_local", "reliable")
func rpc_spawn_player_instance(player_id: int, player_data: Dictionary, spawn_position: Vector2) -> void:
	print("[NetworkManager] 🎭 Spawning player ", player_id, " (", player_data.name, ") at ", spawn_position, " on peer ", multiplayer.get_unique_id())
	var current_scene = get_tree().current_scene
	
	# The scene is now guaranteed to exist because of the synchronization barrier
	if not current_scene: 
		push_error("[NetworkManager] FATAL: No current scene after synchronization barrier!")
		return
	
	var player_container = current_scene.find_child("PlayerContainer", true, false)
	if not player_container:
		push_error("[NetworkManager] Spawn failed on peer ", multiplayer.get_unique_id(), ": PlayerContainer not found!")
		return
	
	# Prevent duplicates
	if player_container.has_node(str(player_id)):
		print("[NetworkManager] Player ", player_id, " already exists, skipping")
		return
	
	var player_scene_resource = load("res://scenes/player/Player.tscn")
	if not player_scene_resource: 
		push_error("[NetworkManager] Failed to load player scene!")
		return
	
	var player_instance = player_scene_resource.instantiate()
	player_instance.name = str(player_id)
	player_instance.add_to_group("player")  # CRITICAL: Add to group for GameManager
	player_container.add_child(player_instance, true)
	
	# CRITICAL: Set multiplayer authority AFTER adding to scene tree
	player_instance.set_multiplayer_authority(player_id)
	
	# SET THE STAGGERED SPAWN POSITION (no more overlapping!)
	player_instance.global_position = spawn_position
	
	if player_instance.has_method("setup_multiplayer_player"):
		var is_local = (player_id == multiplayer.get_unique_id())
		player_instance.setup_multiplayer_player(player_data, is_local)
	
	print("[NetworkManager] ✅ Player ", player_id, " spawned successfully at ", spawn_position, " on peer ", multiplayer.get_unique_id())

# REMOVED: Old confirm_all_players_are_in_scene() function
# Replaced by synchronization barrier pattern in report_readiness()
