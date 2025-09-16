# res://scripts/global/NetworkManager.gd
extends Node

signal player_list_changed(players)
signal connection_succeeded
signal connection_failed
signal game_started(player_data)
signal lobby_found(lobby_info)

const DEFAULT_PORT = 7777
const BROADCAST_PORT = 7778
const BROADCAST_INTERVAL = 1.0
const GAME_IDENTIFIER = "my_hide_and_seek_game_v1"

var players: Dictionary = {}
var my_name: String = "Player" + str(randi_range(1000, 9999))
var my_lobby_data: Dictionary = {}

var _udp_send := PacketPeerUDP.new()
var _udp_recv := PacketPeerUDP.new()
var _broadcast_timer = Timer.new()
var _is_broadcasting = false
var _is_listening = false

func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_broadcast_timer.wait_time = BROADCAST_INTERVAL
	_broadcast_timer.timeout.connect(_send_broadcast)
	add_child(_broadcast_timer)
	# Ensure _process() runs so we can poll UDP packets.
	set_process(true)

func _process(_delta):
	if not _is_listening: return
	# GODOT 4 UDP LISTENING METHOD
	if _udp_recv.is_bound() and _udp_recv.get_available_packet_count() > 0:
		while _udp_recv.get_available_packet_count() > 0:
			# For receiving, get_packet() returns a PackedByteArray
			var packet_data: PackedByteArray = _udp_recv.get_packet()
			var sender_ip: String = _udp_recv.get_packet_ip()
			# var sender_port = _udp_peer.get_packet_port() # If needed
			
			var json_string = packet_data.get_string_from_utf8()
			var parsed = JSON.parse_string(json_string)
			
			if typeof(parsed) == TYPE_DICTIONARY and parsed.get("identifier") == GAME_IDENTIFIER:
				parsed["ip"] = sender_ip
				print("[NetworkManager] Received lobby broadcast from ", sender_ip, ": ", parsed)
				emit_signal("lobby_found", parsed)

func create_lobby(player_name: String, lobby_name: String, max_players: int, timer_setting: String):
	# Set local player name and cap max players to 5 (min 2)
	my_name = player_name
	# SAFETY: Tear down any existing peer (e.g., from a previous client session)
	if multiplayer.multiplayer_peer != null:
		print("[NetworkManager] Clearing existing peer before creating server")
		multiplayer.multiplayer_peer = null
	var capped_max: int = int(clamp(max_players, 2, 5))
	var peer = ENetMultiplayerPeer.new()
	if peer.create_server(DEFAULT_PORT, capped_max) != OK:
		print("Failed to create server.")
		return
	multiplayer.multiplayer_peer = peer
	players[1] = {"name": my_name, "is_host": true, "ready": false, "char_index": -1}
	my_lobby_data = {"name": lobby_name, "max_players": capped_max, "timer": timer_setting}
	start_broadcasting()
	# Also push lobby metadata to any already connected peers (none typically at creation)
	rpc("_rpc_sync_lobby_data", my_lobby_data)
	emit_signal("player_list_changed", players)
	emit_signal("connection_succeeded")

func join_lobby(player_name: String, ip: String):
	# Set local player name before connecting so registration sends the right name
	my_name = player_name
	# SAFETY: If we were acting as server, stop and clear before joining
	if multiplayer.is_server() or multiplayer.multiplayer_peer != null:
		print("[NetworkManager] Clearing existing peer before joining server at ", ip)
		stop_lan_discovery()
		multiplayer.multiplayer_peer = null
	var peer = ENetMultiplayerPeer.new()
	if peer.create_client(ip, DEFAULT_PORT) != OK:
		print("Failed to connect.")
		emit_signal("connection_failed")
		return
	multiplayer.multiplayer_peer = peer
	# Defer success until the low-level connection succeeds
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)

func leave_lobby():
	players.clear()
	my_lobby_data.clear()
	multiplayer.multiplayer_peer = null
	stop_lan_discovery()

func start_broadcasting():
	if _is_broadcasting: return
	_is_broadcasting = true
	_udp_send.set_broadcast_enabled(true)
	_broadcast_timer.start()
	_send_broadcast()

func _on_connected_to_server():
	print("[NetworkManager] Low-level connected to server. My client id=", multiplayer.get_unique_id())
	# Ensure we act purely as client from now on
	stop_lan_discovery()
	# Notify UI flow now that transport is ready
	emit_signal("connection_succeeded")
	# Register and request a fresh players list from the host
	rpc_id(1, "_rpc_register_player", my_name)
	request_players_resync()

func start_listening_for_lobbies():
	if _is_listening: return
	# Corrected: Use bind() instead of listen() for PacketPeerUDP to start listening.
	var bind_status := _udp_recv.bind(BROADCAST_PORT, "0.0.0.0")
	if bind_status != OK:
		push_warning("[NetworkManager] Error starting UDP listener on port %d. Status: %d" % [BROADCAST_PORT, bind_status])
		return
	_is_listening = true
	# Ensure processing is enabled to poll UDP packets.
	set_process(true)

func stop_lan_discovery():
	_broadcast_timer.stop()
	_udp_send.close()
	_udp_recv.close()
	_is_broadcasting = false
	_is_listening = false
	# Disable processing if neither broadcasting nor listening to save cycles.
	if not _is_broadcasting and not _is_listening:
		set_process(false)

func request_char_selection(char_index: int):
	rpc_id(1, "_rpc_request_char_selection", multiplayer.get_unique_id(), char_index)

func start_game():
	if multiplayer.is_server():
		# Assign roles randomly: exactly 1 seeker, others hiders
		var ids: Array = players.keys()
		if ids.size() > 0:
			var seeker_index := int(randi() % ids.size())
			var seeker_id := int(ids[seeker_index])
			for id in ids:
				var role := "seeker" if int(id) == seeker_id else "hider"
				players[int(id)]["role"] = role
			# Sync updated players with roles to all peers
			rpc("_rpc_sync_player_data", players)
		# Stop LAN broadcast and start the game for everyone
		stop_lan_discovery()
		rpc("_rpc_start_game")
		# Also execute locally on the host so it transitions too
		_rpc_start_game()

func _send_broadcast():
	if not _is_broadcasting or not multiplayer.is_server(): stop_lan_discovery(); return
	var data = my_lobby_data.duplicate()
	data["identifier"] = GAME_IDENTIFIER
	data["current_players"] = players.size()
	var packet = JSON.stringify(data).to_utf8_buffer()
	
	# GODOT 4.1.1 UDP SENDING METHOD
	# Corrected: Set the destination address and port before calling put_packet().
	_udp_send.set_dest_address("255.255.255.255", BROADCAST_PORT)
	var err := _udp_send.put_packet(packet)
	if err != OK:
		push_warning("[NetworkManager] Failed to send broadcast packet: %d" % err)
	else:
		print("[NetworkManager] Broadcast sent: ", data)

func _on_peer_connected(id: int):
	if multiplayer.is_server():
		rpc_id(id, "_rpc_request_info")

func _on_peer_disconnected(id: int):
	if multiplayer.is_server():
		players.erase(id)
		rpc("_rpc_sync_player_data", players)
		# Also update locally for host UI
		emit_signal("player_list_changed", players)

@rpc("any_peer")
func _rpc_request_info():
	if not multiplayer.is_server(): rpc_id(1, "_rpc_register_player", my_name)

@rpc("any_peer", "call_local")
func _rpc_register_player(player_name: String):
	if multiplayer.is_server():
		var peer_id = multiplayer.get_remote_sender_id()
		players[peer_id] = {"name": player_name, "is_host": false, "ready": false, "char_index": -1}
		# Send full lobby metadata and then current players
		rpc_id(peer_id, "_rpc_sync_lobby_data", my_lobby_data)
		rpc("_rpc_sync_player_data", players)
		# Also update locally for host UI
		emit_signal("player_list_changed", players)

@rpc("reliable")
func _rpc_sync_player_data(new_player_data: Dictionary):
	players = new_player_data
	emit_signal("player_list_changed", players)

@rpc("any_peer", "call_local")
func _rpc_request_players_resync():
	# Called by a client; server responds with full player data
	if multiplayer.is_server():
		rpc("_rpc_sync_player_data", players)

func request_players_resync():
	rpc_id(1, "_rpc_request_players_resync")

@rpc("reliable")
func _rpc_sync_lobby_data(lobby_data: Dictionary):
	my_lobby_data = lobby_data

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
func _rpc_request_unlock(peer_id: int):
	if multiplayer.is_server():
		if players.has(peer_id):
			players[peer_id].char_index = -1
			players[peer_id].ready = false
			rpc("_rpc_sync_player_data", players)
			emit_signal("player_list_changed", players)

func request_unlock():
	rpc_id(1, "_rpc_request_unlock", multiplayer.get_unique_id())

@rpc("reliable", "call_local")
func _rpc_start_game():
	emit_signal("game_started", players)
