# res://scripts/global/LobbySync.gd
extends Node
class_name LobbySync

# Expects owner to provide `players: Dictionary` and `_add_player_data(id:int, name:String)`

@rpc("any_peer", "reliable")
func register_with_server(player_name: String) -> void:
	print("[LobbySync] Registration request received from: ", player_name)
	print("[LobbySync] Is server: ", multiplayer.is_server())
	
	if not multiplayer.is_server():
		print("[LobbySync] Not server, ignoring registration")
		return
		
	var mgr := _get_manager()
	if mgr == null:
		print("[LobbySync] ERROR: Cannot get NetworkManager!")
		return
		
	var sender_id: int = multiplayer.get_remote_sender_id()
	print("[LobbySync] Registering player ", player_name, " with ID ", sender_id)
	
	_owner_add_player(sender_id, player_name)
	
	# Tell the new player about everyone already in the lobby
	print("[LobbySync] Syncing existing players to new client...")
	for existing_id in mgr.players:
		if existing_id != sender_id:
			print("[LobbySync] Telling new player about existing player: ", existing_id, " - ", mgr.players[existing_id]["name"])
			sync_new_player.rpc_id(sender_id, existing_id, mgr.players[existing_id]["name"])
	
	# And announce the new player to everyone
	print("[LobbySync] Announcing new player to all clients...")
	sync_new_player.rpc(sender_id, player_name)

@rpc("authority", "reliable")
func sync_new_player(id: int, name: String) -> void:
	print("[LobbySync] Syncing new player: ", id, " - ", name)
	_owner_add_player(id, name)

# Character selection
@rpc("any_peer", "reliable")
func rpc_request_char_selection(index: int) -> void:
	print("[LobbySync] === RPC CHARACTER SELECTION RECEIVED ===")
	print("[LobbySync] Character selection request received: index=", index)
	print("[LobbySync] Is server: ", multiplayer.is_server())
	print("[LobbySync] Remote sender ID: ", multiplayer.get_remote_sender_id())
	print("[LobbySync] My unique ID: ", multiplayer.get_unique_id())
	print("[LobbySync] Multiplayer peer: ", multiplayer.multiplayer_peer)
	print("[LobbySync] Connected peers: ", multiplayer.get_peers())
	
	if not multiplayer.is_server():
		print("[LobbySync] Not server, ignoring character selection")
		return
		
	var mgr := _get_manager()
	if mgr == null:
		print("[LobbySync] ERROR: Cannot get NetworkManager!")
		return
		
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	
	print("[LobbySync] Processing character selection for player ", sender_id, " -> character ", index)
	print("[LobbySync] Current players before update: ", mgr.players)
	
	if index < -1 or index > 10:
		print("[LobbySync] Invalid character index: ", index)
		return
	
	# Validate character availability (only if not deselecting)
	if index >= 0:
		for player_id in mgr.players:
			if player_id != sender_id and mgr.players[player_id].get("char_index", -1) == index:
				print("[LobbySync] Character ", index, " already taken by player ", player_id)
				# Send error message back to requesting client
				_notify_character_unavailable.rpc_id(sender_id, index)
				return
		
	if mgr.players.has(sender_id):
		mgr.players[sender_id]["char_index"] = index
		print("[LobbySync] Updated player ", sender_id, " character to ", index)
		print("[LobbySync] Players after update: ", mgr.players)
		
		# Emit signal to update UI on server FIRST (before RPC)
		print("[LobbySync] Emitting player_list_changed signal on server")
		mgr.player_list_changed.emit(mgr.players)
		
		# Then sync to all clients (including the sender via call_local)
		print("[LobbySync] Sending sync_char_selection RPC to all clients...")
		sync_char_selection.rpc(sender_id, index)
		
		print("[LobbySync] Character selection synced and UI updated")
	else:
		print("[LobbySync] ERROR: Player ", sender_id, " not found in players list")
		print("[LobbySync] Available players: ", mgr.players.keys())

# Notify client that character is unavailable
@rpc("authority", "call_remote", "reliable")
func _notify_character_unavailable(char_index: int) -> void:
	"""Server notifies client that character is already taken"""
	print("[LobbySync] Character ", char_index, " is unavailable - already taken")
	
	# Find the lobby wait room to show error message
	var lobby_wait_room = get_tree().get_first_node_in_group("lobby_wait_room")
	if not lobby_wait_room:
		# Try alternative method
		lobby_wait_room = get_node_or_null("/root/LobbyWaitRoomMenu")
	
	if lobby_wait_room and lobby_wait_room.has_method("show_character_unavailable_message"):
		lobby_wait_room.show_character_unavailable_message(char_index)
	else:
		print("[LobbySync] Could not find lobby wait room to show error message")

@rpc("authority", "call_local", "reliable")
func sync_char_selection(id: int, index: int) -> void:
	print("[LobbySync] === SYNC CHARACTER SELECTION ===")
	print("[LobbySync] sync_char_selection called for player ", id, " -> character ", index)
	print("[LobbySync] Called on: ", "Server" if multiplayer.is_server() else "Client")
	print("[LobbySync] My unique ID: ", multiplayer.get_unique_id())
	print("[LobbySync] Is this for me? ", id == multiplayer.get_unique_id())
	
	var mgr := _get_manager()
	if mgr == null:
		print("[LobbySync] ERROR: Cannot get NetworkManager in sync_char_selection!")
		return
	if not mgr.players.has(id):
		print("[LobbySync] ERROR: Player ", id, " not found in players list during sync")
		print("[LobbySync] Available players: ", mgr.players.keys())
		return
	
	# Update the player's character selection
	var old_index = mgr.players[id].get("char_index", -1)
	mgr.players[id]["char_index"] = index
	print("[LobbySync] Updated player ", id, " character from ", old_index, " to ", index)
	print("[LobbySync] Current players state: ", mgr.players)
	
	# Emit signal to update UI on both server and clients
	print("[LobbySync] Emitting player_list_changed signal to update UI")
	mgr.player_list_changed.emit(mgr.players)
	print("[LobbySync] UI update signal emitted successfully")

func _owner_add_player(id: int, name: String) -> void:
	var mgr := _get_manager()
	if mgr and mgr.has_method("_add_player_data"):
		mgr._add_player_data(id, name)

func has_method_on_owner(m: String) -> bool:
	var mgr := _get_manager()
	return mgr != null and mgr.has_method(m)

func _get_manager() -> Node:
	var nm := get_node_or_null("/root/NetworkManager")
	if nm != null:
		return nm
	return get_parent()
