# lobby_wait_room_menu.gd
extends Control

# --- EXPORT VARIABLES ---
@export var lobby_player_item_scene: PackedScene
@export var character_sprites: Array[Texture2D]

# --- NODE REFERENCES ---
@onready var lobby_name_label: Label = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/LobbyNameLabel
@onready var game_timer_label: Label = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/GameTimerLabel
@onready var players_count_label: Label = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/PlayersCountLabel
@onready var player_list_container: VBoxContainer = $PanelContainer/MarginContainer/VBoxContainer/ScrollContainer/PlayerListContainer
@onready var character_grid: GridContainer = $PanelContainer/MarginContainer/VBoxContainer/CharacterGrid
@onready var lock_in_button: Button = $PanelContainer/MarginContainer/VBoxContainer/LockInButton
@onready var start_game_button: Button = $PanelContainer/MarginContainer/VBoxContainer/StartGameButton
@onready var leave_lobby_button: Button = $PanelContainer/MarginContainer/VBoxContainer/LeaveLobbyButton

# --- STATE VARIABLES ---
var _is_host: bool = false
var _lobby_data: Dictionary = {}
var _players_in_lobby: Dictionary = {} # { peer_id: { name, is_host, ready, char_index } }
var _my_peer_id: int
var _my_temp_selection_index: int = -1

func _ready() -> void:
	_my_peer_id = multiplayer.get_unique_id()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	lock_in_button.pressed.connect(_on_lock_in_button_pressed)
	start_game_button.pressed.connect(_on_start_game_button_pressed)
	leave_lobby_button.pressed.connect(_on_leave_lobby_button_pressed)
	_populate_character_grid()

# Called by SceneChanger after scene load
func _initialize_lobby(lobby_info: Dictionary, is_host: bool) -> void:
	_lobby_data = lobby_info
	_is_host = is_host
	start_game_button.visible = _is_host
	if _is_host:
		_players_in_lobby[_my_peer_id] = {
			"name": "Player_" + str(_my_peer_id),
			"is_host": true,
			"ready": false,
			"char_index": -1
		}
	_update_ui()

func _populate_character_grid() -> void:
	if character_sprites.is_empty():
		return
	for i in range(character_sprites.size()):
		var button: TextureButton = TextureButton.new()
		button.texture_normal = character_sprites[i]
		button.custom_minimum_size = Vector2(80, 80)
		button.pressed.connect(_on_char_button_pressed.bind(i))
		character_grid.add_child(button)

func _on_char_button_pressed(char_index: int) -> void:
	_my_temp_selection_index = char_index
	_update_ui()

func _on_lock_in_button_pressed() -> void:
	if _my_temp_selection_index == -1:
		return
	rpc_id(1, "request_lock_in", _my_peer_id, _my_temp_selection_index)

func _on_start_game_button_pressed() -> void:
	if not _is_host:
		return
	print("Host is starting the game...")
	# Broadcast to everyone to load the game scene, sending final player data
	rpc("start_game", _players_in_lobby)

func _on_leave_lobby_button_pressed() -> void:
	multiplayer.multiplayer_peer = null
	var sc: Node = get_node_or_null("/root/SceneChanger")
	if sc:
		sc.call("change_scene_to_file", "res://scenes/UI/multiplayer_menu.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/UI/multiplayer_menu.tscn")

func _on_peer_connected(id: int) -> void:
	if not _is_host:
		return
	_players_in_lobby[id] = {
		"name": "Player_" + str(id),
		"is_host": false,
		"ready": false,
		"char_index": -1
	}
	rpc("sync_lobby_state", _players_in_lobby)

func _on_peer_disconnected(id: int) -> void:
	if not _is_host:
		return
	_players_in_lobby.erase(id)
	rpc("sync_lobby_state", _players_in_lobby)

@rpc(any_peer=true, call_local=true)
func request_lock_in(peer_id: int, char_index: int) -> void:
	if not _is_host:
		return
	# Validate that char is not taken
	for p_id in _players_in_lobby.keys():
		var pdata: Dictionary = _players_in_lobby[p_id]
		if int(pdata.get("char_index", -1)) == char_index:
			print("Host: Character %d is taken. Request denied for %d." % [char_index, peer_id])
			return
	if _players_in_lobby.has(peer_id):
		_players_in_lobby[peer_id]["char_index"] = char_index
		_players_in_lobby[peer_id]["ready"] = true
	rpc("sync_lobby_state", _players_in_lobby)

@rpc(reliable=true)
func sync_lobby_state(new_state: Dictionary) -> void:
	_players_in_lobby = new_state.duplicate(true)
	_update_ui()

@rpc(reliable=true)
func start_game(final_player_data: Dictionary) -> void:
	print("Received start game command! Loading game scene...")
	var sc: Node = get_node_or_null("/root/SceneChanger")
	if sc:
		sc.call("change_scene_to_file", "res://scenes/game/game_scene.tscn", {"players": final_player_data})
	else:
		get_tree().change_scene_to_file("res://scenes/game/game_scene.tscn")

func _update_ui() -> void:
	lobby_name_label.text = "Lobby: " + str(_lobby_data.get("name", "[Name]"))
	game_timer_label.text = "Timer: " + str(_lobby_data.get("timer", "[Timer]"))
	players_count_label.text = "Players: %d/%d" % [_players_in_lobby.size(), int(_lobby_data.get("max_players", 0))]

	var taken_char_indices: Array[int] = []
	for p_id in _players_in_lobby.keys():
		var char_idx: int = int(_players_in_lobby[p_id].get("char_index", -1))
		if char_idx != -1:
			taken_char_indices.append(char_idx)

	for i in range(character_grid.get_child_count()):
		var button: TextureButton = character_grid.get_child(i) as TextureButton
		if button:
			button.disabled = i in taken_char_indices
			button.modulate = Color(1, 1, 1, 1)
			if i == _my_temp_selection_index:
				button.modulate = Color(1.0, 0.84, 0.0)

	for child in player_list_container.get_children():
		child.queue_free()

	for p_id in _players_in_lobby.keys():
		var player_data: Dictionary = _players_in_lobby[p_id]
		if lobby_player_item_scene == null:
			continue
		var player_item: Node = lobby_player_item_scene.instantiate()
		player_list_container.add_child(player_item)
		var char_texture: Texture2D = null
		var idx: int = int(player_data.get("char_index", -1))
		if idx >= 0 and idx < character_sprites.size():
			char_texture = character_sprites[idx]
		if player_item.has_method("update_display"):
			player_item.call("update_display", player_data, char_texture)

	var self_is_ready: bool = false
	if _players_in_lobby.has(_my_peer_id):
		self_is_ready = bool(_players_in_lobby[_my_peer_id].get("ready", false))
	lock_in_button.disabled = self_is_ready or _my_temp_selection_index == -1
	lock_in_button.text = self_is_ready ? "LOCKED IN" : "LOCK IN"

	if _is_host:
		var all_ready: bool = true
		if _players_in_lobby.is_empty():
			all_ready = false
		for p_id in _players_in_lobby.keys():
			if not bool(_players_in_lobby[p_id].get("ready", false)):
				all_ready = false
				break
		start_game_button.disabled = not all_ready or _players_in_lobby.size() < 2
