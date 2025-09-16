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

var _udp_peer = PacketPeerUDP.new()
var _broadcast_timer = Timer.new()
var _is_broadcasting = false
var _is_listening = false

func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_broadcast_timer.wait_time = BROADCAST_INTERVAL
	_broadcast_timer.timeout.connect(_send_broadcast)
	add_child(_broadcast_timer)

func _process(_delta):
	if not _is_listening: return
	
	# GODOT 4.1.1 UDP LISTENING METHOD
	if _udp_peer.is_listening() and _udp_peer.get_packet_count() > 0:
		while _udp_peer.get_packet_count() > 0:
			# For receiving, get_packet() returns a PackedByteArray
			var packet_data = _udp_peer.get_packet()
			var sender_ip = _udp_peer.get_packet_ip()
			# var sender_port = _udp_peer.get_packet_port() # If needed
			
			var json_string = packet_data.get_string_from_utf8()
			var parsed = JSON.parse_string(json_string)
			
			if typeof(parsed) == TYPE_DICTIONARY and parsed.get("identifier") == GAME_IDENTIFIER:
				parsed["ip"] = sender_ip
				emit_signal("lobby_found", parsed)

func create_lobby(player_name: String, lobby_name: String, max_players: int, timer_setting: String):
	# Set local player name and cap max players to 5 (min 2)
	my_name = player_name
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
	var peer = ENetMultiplayerPeer.new()
	if peer.create_client(ip, DEFAULT_PORT) != OK:
		print("Failed to connect.")
		emit_signal("connection_failed")
		return
	multiplayer.multiplayer_peer = peer
	emit_signal("connection_succeeded")

func leave_lobby():
	players.clear()
	my_lobby_data.clear()
	multiplayer.multiplayer_peer = null
	stop_lan_discovery()

func start_broadcasting():
	if _is_broadcasting: return
	_is_broadcasting = true
	_udp_peer.set_broadcast_enabled(true)
	_broadcast_timer.start()
	_send_broadcast()

func start_listening_for_lobbies():
	if _is_listening: return
	# Corrected: Use bind() instead of listen() for PacketPeerUDP to start listening.
	if _udp_peer.bind(BROADCAST_PORT) != OK:
		print("Error starting UDP listener.")
		return
	_is_listening = true

func stop_lan_discovery():
	_broadcast_timer.stop()
	_udp_peer.close()
	_is_broadcasting = false
	_is_listening = false

func request_char_selection(char_index: int):
	rpc_id(1, "_rpc_request_char_selection", multiplayer.get_unique_id(), char_index)

func start_game():
	if multiplayer.is_server():
		stop_lan_discovery()
		rpc("_rpc_start_game")

func _send_broadcast():
	if not _is_broadcasting or not multiplayer.is_server(): stop_lan_discovery(); return
	var data = my_lobby_data.duplicate()
	data["identifier"] = GAME_IDENTIFIER
	data["current_players"] = players.size()
	var packet = JSON.stringify(data).to_utf8_buffer()
	
	# GODOT 4.1.1 UDP SENDING METHOD
	# Corrected: Set the destination address and port before calling put_packet().
	_udp_peer.set_dest_address("255.255.255.255", BROADCAST_PORT)
	_udp_peer.put_packet(packet)

func _on_peer_connected(id: int):
	if multiplayer.is_server():
		rpc_id(id, "_rpc_request_info")

func _on_peer_disconnected(id: int):
	if multiplayer.is_server():
		players.erase(id)
		rpc("_rpc_sync_player_data", players)

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

@rpc("reliable")
func _rpc_sync_player_data(new_player_data: Dictionary):
	players = new_player_data
	emit_signal("player_list_changed", players)

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

@rpc("reliable")
func _rpc_start_game():
	emit_signal("game_started", players)
