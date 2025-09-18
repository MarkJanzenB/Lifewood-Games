# res://scripts/global/LobbySync.gd
extends Node
class_name LobbySync

# Expects owner to provide `players: Dictionary` and `_add_player_data(id:int, name:String)`

@rpc("any_peer", "reliable")
func register_with_server(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var mgr := _get_manager()
	if mgr == null:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_owner_add_player(sender_id, player_name)
	# Tell the new player about everyone already in the lobby
	for existing_id in mgr.players:
		if existing_id != sender_id:
			sync_new_player.rpc_id(sender_id, existing_id, mgr.players[existing_id]["name"])
	# And announce the new player to everyone
	sync_new_player.rpc(sender_id, player_name)

@rpc("authority", "reliable")
func sync_new_player(id: int, name: String) -> void:
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
