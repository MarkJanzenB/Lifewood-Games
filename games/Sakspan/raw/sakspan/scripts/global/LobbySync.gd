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
@rpc("any_peer", "call_local", "reliable")
func rpc_request_char_selection(index: int) -> void:
	if not multiplayer.is_server():
		return
	var mgr := _get_manager()
	if mgr == null:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	if index < -1 or index > 10:
		return
	if mgr.players.has(sender_id):
		mgr.players[sender_id]["char_index"] = index
		print("[LobbySync] Player ", sender_id, " selected character ", index)
		sync_char_selection.rpc(sender_id, index)
		mgr.player_list_changed.emit(mgr.players)

@rpc("authority", "call_local", "reliable")
func sync_char_selection(id: int, index: int) -> void:
	var mgr := _get_manager()
	if mgr == null:
		return
	if not mgr.players.has(id):
		return
	mgr.players[id]["char_index"] = index
	print("[LobbySync] Synced character selection: Player ", id, " -> character ", index)
	mgr.player_list_changed.emit(mgr.players)

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
