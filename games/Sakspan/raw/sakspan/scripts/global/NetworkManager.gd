# res://scripts/global/NetworkManager.gd
extends Node

signal player_list_changed(players)
signal connection_succeeded
signal connection_failed
signal game_started(player_data)
signal lobby_found(lobby_info)
signal lobby_data_changed(lobby_data)

const DEFAULT_PORT = 7777
const FALLBACK_PORT = 8080
const BROADCAST_PORT = 7778
const BROADCAST_INTERVAL = 1.0
const GAME_IDENTIFIER = "sakspan_bangSak_v1"
const MAX_LOBBY_NAME_LENGTH = 20
const MIN_LOBBY_NAME_LENGTH = 3

var players: Dictionary = {}
var my_name: String = "Player" + str(randi_range(1000, 9999))
var my_lobby_data: Dictionary = {}
var room_code: String = ""
var _udp_peer: PacketPeerUDP
var _udp_recv: PacketPeerUDP
var _is_listening: bool = false
var _is_broadcasting: bool = false
var _last_join_ip: String = ""
var _broadcast_timer: Timer = Timer.new()
var _udp_send: PacketPeerUDP

func _ready():
	print("[NetworkManager] 🚀 NetworkManager initializing...")
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	_broadcast_timer.wait_time = BROADCAST_INTERVAL
	_broadcast_timer.timeout.connect(_send_broadcast)
	add_child(_broadcast_timer)
	# Ensure _process() runs so we can poll UDP packets.
	set_process(true)
	print("[NetworkManager] ✅ NetworkManager ready!")

func _process(_delta):
	if not _is_listening:
		return
	# GODOT 4 UDP LISTENING METHOD
	if _udp_recv != null and _udp_recv.is_bound() and _udp_recv.get_available_packet_count() > 0:
		while _udp_recv.get_available_packet_count() > 0:
			# For receiving, get_packet() returns a PackedByteArray
			var packet_data: PackedByteArray = _udp_recv.get_packet()
			var sender_ip: String = _udp_recv.get_packet_ip()
			# var sender_port = _udp_peer.get_packet_port() # If needed

			var json_string: String = packet_data.get_string_from_utf8()
			var parsed_raw: Variant = JSON.parse_string(json_string)

			if typeof(parsed_raw) == TYPE_DICTIONARY:
				var parsed: Dictionary = parsed_raw
				if parsed.get("identifier") != GAME_IDENTIFIER:
					continue
				# --- HOST: Handle a client's request to find a lobby by code ---
				if multiplayer.has_multiplayer_peer() and multiplayer.is_server() and parsed.get("request_type") == "find_lobby":
					if parsed.get("room_code") == room_code:
						print("[NetworkManager] Received find request for my room code. Responding to ", sender_ip)
						_send_direct_lobby_info(sender_ip)
					continue

				# --- CLIENT: Handle a direct response from a host ---
				if multiplayer.has_multiplayer_peer() and not multiplayer.is_server() and parsed.get("request_type") == "lobby_response":
					parsed["ip"] = sender_ip
					print("[NetworkManager] Received direct lobby response from ", sender_ip)
					emit_signal("lobby_found", parsed)
					continue

				# --- CLIENT: Handle a general broadcast from a host ---
				if (not multiplayer.has_multiplayer_peer() or not multiplayer.is_server()) and parsed.has("room_code"):
					parsed["ip"] = sender_ip
					print("[NetworkManager] Received lobby broadcast from ", sender_ip, ": ", parsed)
					emit_signal("lobby_found", parsed)

func create_lobby(player_name: String, lobby_name: String, max_players: int, timer_setting: String):
	# Validate lobby name
	if lobby_name.length() < MIN_LOBBY_NAME_LENGTH or lobby_name.length() > MAX_LOBBY_NAME_LENGTH:
		print("[NetworkManager] Invalid lobby name length. Must be between %d and %d characters." % [MIN_LOBBY_NAME_LENGTH, MAX_LOBBY_NAME_LENGTH])
		return
	
	# Set local player name and cap max players to 5 (min 2)
	my_name = player_name
	# SAFETY: Tear down any existing peer (e.g., from a previous client session)
	if multiplayer.multiplayer_peer != null:
		print("[NetworkManager] Clearing existing peer before creating server")
		multiplayer.multiplayer_peer = null
	
	var capped_max: int = int(clamp(max_players, 2, 5))
	# Generate a unique room code for this lobby
	room_code = _generate_room_code()
	
	print("[NetworkManager] 🏠 HOST: Creating ENet server on port %d..." % DEFAULT_PORT)
	var peer = ENetMultiplayerPeer.new()
	var server_result = peer.create_server(DEFAULT_PORT, capped_max)
	print("[NetworkManager] 🔍 HOST: Server creation result: %d (OK=0)" % server_result)
	if server_result != OK:
		print("[NetworkManager] ⚠️ HOST: Primary server failed on port %d, trying fallback port %d..." % [DEFAULT_PORT, FALLBACK_PORT])
		var fallback_peer = ENetMultiplayerPeer.new()
		var fallback_result = fallback_peer.create_server(FALLBACK_PORT, capped_max)
		print("[NetworkManager] 🔍 HOST: Fallback server result: %d (OK=0)" % fallback_result)
		if fallback_result != OK:
			print("[NetworkManager] ❌ HOST: FAILED to create server on both ports %d and %d!" % [DEFAULT_PORT, FALLBACK_PORT])
			return
		print("[NetworkManager] ✅ HOST: ENet server created successfully on fallback port %d" % FALLBACK_PORT)
		multiplayer.multiplayer_peer = fallback_peer
	else:
		print("[NetworkManager] ✅ HOST: ENet server created successfully on port %d" % DEFAULT_PORT)
		multiplayer.multiplayer_peer = peer
	players[1] = {"name": my_name, "is_host": true, "ready": false, "char_index": -1}
	my_lobby_data = {
		"name": lobby_name,
		"room_code": room_code,
		"max_players": capped_max,
		"timer": timer_setting,
		"status": "waiting",
		"game_mode": "Bang-Sak"
	}
	# Add the host LAN IP so clients can display the correct IP rather than their own
	my_lobby_data["host_ip"] = _get_lan_ipv4()
	
	print("[NetworkManager] 🏠 HOST: Created lobby '%s' with room code: %s" % [lobby_name, room_code])
	print("[NetworkManager] 🏠 HOST: Server listening on port %d for %d max players" % [DEFAULT_PORT, capped_max])
	print("[NetworkManager] 📡 HOST: Starting UDP broadcast on port %d..." % BROADCAST_PORT)
	start_broadcasting()
	# Also push lobby metadata to any already connected peers (none typically at creation)
	rpc("_rpc_sync_lobby_data", my_lobby_data)
	emit_signal("player_list_changed", players)
	emit_signal("connection_succeeded")

func join_lobby(player_name: String, ip: String):
	print("[NetworkManager] 🔄 CLIENT: Starting join attempt - Player: '%s' | Target IP: %s:%d" % [player_name, ip, DEFAULT_PORT])
	
	my_name = player_name
	_last_join_ip = ip  # Store IP for fallback attempts
	
	print("[NetworkManager] 🔌 CLIENT: Creating ENet client peer...")
	var peer = ENetMultiplayerPeer.new()
	if peer.create_client(ip, DEFAULT_PORT) != OK:
		print("[NetworkManager] ❌ CLIENT: FAILED to create ENet client!")
		emit_signal("connection_failed")
		return
	
	print("[NetworkManager] 🚀 CLIENT: ENet peer created successfully, attempting connection...")
	multiplayer.multiplayer_peer = peer
	
	# Connect multiplayer signals if not already connected
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	
	print("[NetworkManager] 📡 CLIENT: Waiting for low-level connection to establish...")
	
	# Connection callbacks are already set up in _ready()

func leave_lobby():
	players.clear()
	my_lobby_data.clear()
	multiplayer.multiplayer_peer = null
	stop_lan_discovery()
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("reset_to_lobby"):
		game_manager.reset_to_lobby()

func start_broadcasting():
	if _is_broadcasting: return
	_udp_send = PacketPeerUDP.new()
	# Bind the sending socket to an ephemeral port (port 0)
	if _udp_send.bind(0) != OK:
		push_warning("[NetworkManager] UDP broadcast sender failed to bind.")
		_udp_send = null # Clear the invalid peer
		return
	_is_broadcasting = true
	_udp_send.set_broadcast_enabled(true)
	_broadcast_timer.start()
	_send_broadcast() # Send one immediately

func _on_peer_connected(id):
	print("[NetworkManager] ✅ PEER CONNECTED - ID: ", id, " | Total peers: ", multiplayer.get_peers().size() + 1)
	print("[NetworkManager] 📊 Connection details - Is server: ", multiplayer.is_server(), " | My ID: ", multiplayer.get_unique_id())
	
	if multiplayer.is_server():
		print("[NetworkManager] 🏠 HOST: New client connected, requesting player info...")
		rpc_id(id, "_rpc_request_info")

func _on_peer_disconnected(id):
	print("[NetworkManager] ❌ PEER DISCONNECTED - ID: ", id, " | Remaining peers: ", multiplayer.get_peers().size())
	print("[NetworkManager] 📊 Disconnection details - Is server: ", multiplayer.is_server(), " | My ID: ", multiplayer.get_unique_id())
	
	if multiplayer.is_server():
		print("[NetworkManager] 🏠 HOST: Client disconnected, updating player list...")
		players.erase(id)
		rpc("_rpc_sync_player_data", players)
		emit_signal("player_list_changed", players)

func _on_connected_to_server():
	print("[NetworkManager] ✅ CLIENT: Successfully connected to server!")
	print("[NetworkManager] 📋 CLIENT: My assigned ID: ", multiplayer.get_unique_id())
	print("[NetworkManager] 🛑 CLIENT: Stopping LAN discovery...")
	
	# Ensure we act purely as client from now on
	stop_lan_discovery()
	
	print("[NetworkManager] 📢 CLIENT: Emitting connection_succeeded signal...")
	emit_signal("connection_succeeded")
	
	print("[NetworkManager] 📝 CLIENT: Registering with server - Name: '%s'" % my_name)
	rpc_id(1, "_rpc_register_player", my_name)
	
	print("[NetworkManager] 🔄 CLIENT: Requesting player list sync...")
	request_players_resync()

func _on_connection_failed():
	print("[NetworkManager] ❌ CLIENT: Connection to server FAILED on port %d!" % DEFAULT_PORT)
	print("[NetworkManager] 🔄 CLIENT: Trying fallback port %d..." % FALLBACK_PORT)
	
	# Try fallback port
	var fallback_peer = ENetMultiplayerPeer.new()
	var target_ip = multiplayer.multiplayer_peer.get_peer_address(1) if multiplayer.has_multiplayer_peer() else "unknown"
	
	# Get the IP from the last join attempt
	if _last_join_ip != "":
		print("[NetworkManager] 🔌 CLIENT: Attempting fallback connection to %s:%d" % [_last_join_ip, FALLBACK_PORT])
		if fallback_peer.create_client(_last_join_ip, FALLBACK_PORT) == OK:
			multiplayer.multiplayer_peer = fallback_peer
			print("[NetworkManager] 📡 CLIENT: Fallback connection attempt started...")
			return
	
	print("[NetworkManager] ❌ CLIENT: All connection attempts failed!")
	print("[NetworkManager] 🔍 CLIENT: Possible causes - Server offline, wrong IP, firewall blocking ports %d and %d" % [DEFAULT_PORT, FALLBACK_PORT])
	print("[NetworkManager] 💡 CLIENT: Try these troubleshooting steps:")
	print("[NetworkManager] 💡 CLIENT: 1. Check if host can ping client IP")
	print("[NetworkManager] 💡 CLIENT: 2. Temporarily disable Windows Firewall on both machines")
	print("[NetworkManager] 💡 CLIENT: 3. Try connecting from host to client instead")
	emit_signal("connection_failed")

func start_listening_for_lobbies():
	if _is_listening: return
	_udp_recv = PacketPeerUDP.new()
	var bind_status := _udp_recv.bind(BROADCAST_PORT, "0.0.0.0")
	if bind_status != OK:
		push_warning("[NetworkManager] Error starting UDP listener on port %d. Status: %d" % [BROADCAST_PORT, bind_status])
		_udp_recv = null # Clear the invalid peer
		return
	_is_listening = true
	# Ensure processing is enabled to poll UDP packets.
	set_process(true)

func stop_lan_discovery():
	_broadcast_timer.stop()
	if is_instance_valid(_udp_send):
		_udp_send.close()
		_udp_send = null
	if is_instance_valid(_udp_recv):
		_udp_recv.close()
		_udp_recv = null
	_is_broadcasting = false
	_is_listening = false
	# Disable processing if neither broadcasting nor listening to save cycles.
	if not _is_broadcasting and not _is_listening:
		set_process(false)

# Return a likely LAN IPv4 for this device (avoids 127.*)
func _get_lan_ipv4() -> String:
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10."):
			return a
		if a.begins_with("172."):
			var parts = a.split(".")
			if parts.size() >= 2:
				var second = int(parts[1])
				if second >= 16 and second <= 31:
					return a
	return ""

# Generate a unique 6-character room code
func _generate_room_code() -> String:
	const CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var code = ""
	for i in range(6):
		code += CHARS[randi() % CHARS.length()]
	return code

# Find lobby by room code (for future room code joining feature)
func find_lobby_by_code(code: String):
	if not is_instance_valid(_udp_send):
		# Ensure the sender socket is ready
		_udp_send = PacketPeerUDP.new()
		if _udp_send.bind(0) != OK:
			push_warning("[NetworkManager] UDP find request sender failed to bind.")
			_udp_send = null
			return
	
	var request_data = {
		"identifier": GAME_IDENTIFIER,
		"request_type": "find_lobby",
		"room_code": code
	}
	var packet = JSON.stringify(request_data).to_utf8_buffer()
	_udp_send.set_broadcast_enabled(true)
	_udp_send.set_dest_address("255.255.255.255", BROADCAST_PORT)
	if _udp_send.put_packet(packet) != OK:
		push_warning("[NetworkManager] Failed to send find_lobby request packet.")

# Host sends its lobby info directly to a specific IP
func _send_direct_lobby_info(recipient_ip: String):
	if not multiplayer.is_server(): return

	var data = my_lobby_data.duplicate()
	data["identifier"] = GAME_IDENTIFIER
	data["request_type"] = "lobby_response" # Mark this as a direct response
	data["current_players"] = players.size()
	data["timestamp"] = Time.get_ticks_msec()
	data["host_ip"] = my_lobby_data.get("host_ip", _get_lan_ipv4())

	var packet = JSON.stringify(data).to_utf8_buffer()
	_udp_send.set_dest_address(recipient_ip, BROADCAST_PORT)
	if _udp_send.put_packet(packet) != OK:
		push_warning("[NetworkManager] Failed to send direct lobby info to %s" % recipient_ip)

func request_char_selection(char_index: int):
	rpc_id(1, "_rpc_request_char_selection", multiplayer.get_unique_id(), char_index)

func _all_players_ready() -> bool:
	if players.size() < 2:
		return false
	for id in players.keys():
		if int(players[id].get("char_index", -1)) < 0:
			return false
	return true

func start_game():
	if not multiplayer.is_server():
		return

	# Validate readiness; if not ready, refuse to start quietly (UI decides enabling)
	if not _all_players_ready():
		print("[NetworkManager] start_game refused: not all players are locked in or not enough players.")
		print("[NetworkManager] Players snapshot:", players)
		return

	# Assign roles randomly: exactly 1 seeker, others hiders
	var ids: Array = players.keys()
	if ids.is_empty():
		print("[NetworkManager] start_game aborted: no players in dictionary.")
		return
	randomize()
	var seeker_index := int(randi() % ids.size())
	var seeker_id := int(ids[seeker_index])
	for id in players.keys():
		players[int(id)]["role"] = "seeker" if int(id) == seeker_id else "hider"
	print("[NetworkManager] Roles assigned. Seeker=", seeker_id, " players=", players)

	# Mark lobby in-game and stop discovery
	my_lobby_data["status"] = "in_game"
	stop_lan_discovery()
	print("[NetworkManager] Broadcasting start to peers... Peers=", multiplayer.get_peers())

	# Sync final player data and lobby metadata, then instruct everyone to load the world
	rpc("_rpc_sync_player_data", players)
	rpc("_rpc_sync_lobby_data", my_lobby_data)
	rpc("_rpc_start_game", players, my_lobby_data)
	_rpc_start_game(players, my_lobby_data) # call_local for the host as well

# Host-only helpers to assign seeker explicitly before start
func host_assign_seeker(seeker_id: int):
	if not multiplayer.is_server():
		return
	var ids: Array = players.keys()
	for id in ids:
		players[int(id)]["role"] = "seeker" if int(id) == int(seeker_id) else "hider"
	rpc("_rpc_sync_player_data", players)
	emit_signal("player_list_changed", players)

func host_assign_random_seeker():
	if not multiplayer.is_server():
		return
	var ids: Array = players.keys()
	if ids.is_empty():
		return
	randomize()
	var seeker_index := int(randi() % ids.size())
	var seeker_id := int(ids[seeker_index])
	for id in ids:
		players[int(id)]["role"] = "seeker" if int(id) == seeker_id else "hider"
	rpc("_rpc_sync_player_data", players)
	emit_signal("player_list_changed", players)

func request_unlock():
	rpc_id(1, "_rpc_request_unlock", multiplayer.get_unique_id())

@rpc("reliable", "call_local")
func _rpc_start_game(start_players: Dictionary, start_lobby_data: Dictionary):

	players = start_players
	my_lobby_data = start_lobby_data
	emit_signal("player_list_changed", players)
	emit_signal("lobby_data_changed", my_lobby_data)
	# Backwards compatibility for any UI still listening for the signal
	emit_signal("game_started", players)
	# Perform the actual scene transition here to avoid UI desyncs
	SceneChanger.change_scene_to_file("res://scenes/world.tscn")

func _send_broadcast():
	if not _is_broadcasting or not multiplayer.is_server(): 
		stop_lan_discovery()
		return
	
	var data = my_lobby_data.duplicate()
	data["identifier"] = GAME_IDENTIFIER
	data["current_players"] = players.size()
	data["timestamp"] = Time.get_ticks_msec()
	# Ensure broadcast includes host_ip for clients to display
	data["host_ip"] = my_lobby_data.get("host_ip", _get_lan_ipv4())
	
	# Update status based on game state
	if players.size() >= my_lobby_data.get("max_players", 5):
		data["status"] = "full"
	else:
		data["status"] = "waiting"
	
	var packet = JSON.stringify(data).to_utf8_buffer()
	
	# GODOT 4.1.1 UDP SENDING METHOD
	_udp_send.set_dest_address("255.255.255.255", BROADCAST_PORT)
	var err := _udp_send.put_packet(packet)
	if err != OK:
		push_warning("[NetworkManager] Failed to send broadcast packet: %d" % err)
	else:
		print("[NetworkManager] Broadcasting room '%s' (Code: %s)" % [data.get("name", "Unknown"), data.get("room_code", "N/A")])


@rpc("any_peer")
func _rpc_request_info():
	print("[NetworkManager] 📞 CLIENT: Received info request from server")
	if not multiplayer.is_server(): 
		print("[NetworkManager] 📝 CLIENT: Sending registration to server with name: '%s'" % my_name)
		rpc_id(1, "_rpc_register_player", my_name)

@rpc("any_peer", "call_local")
func _rpc_register_player(player_name: String):
	if multiplayer.is_server():
		var peer_id = multiplayer.get_remote_sender_id()
		print("[NetworkManager] 🏠 HOST: Registering new player - ID: %d, Name: '%s'" % [peer_id, player_name])
		players[peer_id] = {"name": player_name, "is_host": false, "ready": false, "char_index": -1}
		print("[NetworkManager] 🏠 HOST: Sending lobby data to new player...")
		rpc_id(peer_id, "_rpc_sync_lobby_data", my_lobby_data)
		print("[NetworkManager] 🏠 HOST: Broadcasting updated player list to all clients...")
		rpc("_rpc_sync_player_data", players)
		# Also update locally for host UI
		emit_signal("player_list_changed", players)
		print("[NetworkManager] 🏠 HOST: Player registration complete. Total players: %d" % players.size())

@rpc("authority", "call_local", "reliable")
func _rpc_sync_player_data(new_player_data: Dictionary):
	print("[NetworkManager] 📋 Received player data sync - Players: %d" % new_player_data.size())
	players = new_player_data
	emit_signal("player_list_changed", players)

@rpc("any_peer", "call_local")
func _rpc_request_players_resync():
	# Called by a client; server responds with full player data
	if multiplayer.is_server():
		rpc("_rpc_sync_player_data", players)

func request_players_resync():
	rpc_id(1, "_rpc_request_players_resync")

@rpc("any_peer", "call_local")
func _rpc_request_lobby_resync():
	# Called by a client; server responds with current lobby metadata
	if multiplayer.is_server():
		var sender := multiplayer.get_remote_sender_id()
		rpc_id(sender, "_rpc_sync_lobby_data", my_lobby_data)

func request_lobby_resync():
	rpc_id(1, "_rpc_request_lobby_resync")

@rpc("authority", "call_local", "reliable")
func _rpc_sync_lobby_data(lobby_data: Dictionary):
	my_lobby_data = lobby_data
	emit_signal("lobby_data_changed", my_lobby_data)

@rpc("any_peer", "call_local")
func _rpc_request_char_selection(peer_id: int, char_index: int):
	if multiplayer.is_server():
		for p_id in players:
			if players[p_id].char_index == char_index: return
		players[peer_id].char_index = char_index
		players[peer_id].ready = true
		rpc("_rpc_sync_player_data", players)
		# Update host UI too
		emit_signal("player_list_changed", players)

@rpc("any_peer", "call_local")
func _spawn_players():
	if not multiplayer.is_server():
		return

	var player_spawner = get_tree().get_root().find_child("PlayerSpawner", true, false)
	if not player_spawner:
		print("[NetworkManager] PlayerSpawner not found in the scene tree!")
		return

	for id in players.keys():
		var player_node = player_spawner.spawn(id)
		print(f"[NetworkManager] Spawned player for peer {id}")


@rpc("any_peer", "call_local")
func _rpc_request_unlock(peer_id: int):
	if multiplayer.is_server():
		if players.has(peer_id):
			players[peer_id].char_index = -1
			players[peer_id].ready = false
			rpc("_rpc_sync_player_data", players)
			emit_signal("player_list_changed", players)
