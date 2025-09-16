# lobby_wait_room_menu.gd
extends Control

# --- EXPORT VARIABLES ---
@export var lobby_player_item_scene: PackedScene
@export var character_sprites: Array[Texture2D] = [
    preload("res://scenes/UI/Lobby_Wait_Room/blue_char.png"),
    preload("res://scenes/UI/Lobby_Wait_Room/green_char.png"),
    preload("res://scenes/UI/Lobby_Wait_Room/pink_char.png"),
    preload("res://scenes/UI/Lobby_Wait_Room/red_char.png"),
    preload("res://scenes/UI/Lobby_Wait_Room/yellow_char.png"),
]

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

func _ready():
    _check_ui_nodes()
    if Engine.has_singleton("NetworkManager") or ("NetworkManager" in ProjectSettings.get_setting("autoloads")):
        # Access autoloaded NetworkManager directly
        _lobby_data = NetworkManager.my_lobby_data if NetworkManager.my_lobby_data != null else {}
        _players_in_lobby = NetworkManager.players if NetworkManager.players != null else {}
        NetworkManager.player_list_changed.connect(_on_player_list_changed)
        if NetworkManager.has_signal("game_started"):
            NetworkManager.game_started.connect(_on_game_started)
    if start_game_button:
        start_game_button.pressed.connect(_on_start_game_button_pressed)
    if lock_in_button:
        lock_in_button.pressed.connect(_on_lock_in_button_pressed)
    if leave_lobby_button:
        leave_lobby_button.pressed.connect(_on_leave_lobby_button_pressed)

    # Load lobby data from NetworkManager
    _lobby_data = NetworkManager.my_lobby_data
    _is_host = multiplayer.is_server()
    _update_lobby_header()
    _update_player_list(NetworkManager.players)
    _setup_character_grid()
    _update_start_game_button()

func _update_lobby_header():
    if lobby_name_label:
        lobby_name_label.text = "Lobby: " + _lobby_data.get("name", "Unnamed Lobby")
    if $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/GameTimerLabel:
        $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/GameTimerLabel.text = "Timer: " + str(_lobby_data.get("timer", "-"))
    if players_count_label:
        players_count_label.text = "Players: %d/%d" % [_players_in_lobby.size(), int(_lobby_data.get("max_players", 5))]

func _update_player_list(players: Dictionary):
    for child in player_list_container.get_children():
        child.queue_free()

    for p_id in players.keys():
        var player_data: Dictionary = players[p_id]
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

func _setup_character_grid():
    for i in range(character_sprites.size()):
        var button: TextureButton = TextureButton.new()
        button.texture_normal = character_sprites[i]
        button.custom_minimum_size = Vector2(80, 80)
        button.pressed.connect(_on_char_button_pressed.bind(i))
        character_grid.add_child(button)

func _update_character_grid_lock(players: Dictionary):
    var taken_char_indices: Array[int] = []
    for p_id in players.keys():
        var char_idx: int = int(players[p_id].get("char_index", -1))
        if char_idx != -1:
            taken_char_indices.append(char_idx)

    for i in range(character_grid.get_child_count()):
        var button: TextureButton = character_grid.get_child(i) as TextureButton
        if button:
            button.disabled = i in taken_char_indices
            button.modulate = Color(1, 1, 1, 1)
            if i == _my_temp_selection_index:
                button.modulate = Color(1.0, 0.84, 0.0)

func _update_start_game_button():
    if _is_host:
        var all_ready: bool = true
        if _players_in_lobby.is_empty():
            all_ready = false
        for p_id in _players_in_lobby.keys():
            if not bool(_players_in_lobby[p_id].get("ready", false)):
                all_ready = false
                break
        start_game_button.disabled = not all_ready or _players_in_lobby.size() < 2

func _on_char_button_pressed(char_index: int) -> void:
    _my_temp_selection_index = char_index
    _update_character_grid_lock(_players_in_lobby)

func _on_lock_in_button_pressed() -> void:
    if _my_temp_selection_index == -1:
        return
    # Delegate to NetworkManager which enforces unique selection and syncs
    if NetworkManager and NetworkManager.has_method("request_char_selection"):
        NetworkManager.request_char_selection(_my_temp_selection_index)

func _on_start_game_button_pressed() -> void:
    if not _is_host:
        return
    if NetworkManager and NetworkManager.has_method("start_game"):
        NetworkManager.start_game()

func _on_leave_lobby_button_pressed() -> void:
    multiplayer.multiplayer_peer = null
    var sc: Node = get_node_or_null("/root/SceneChanger")
    if sc:
        sc.call("change_scene_to_file", "res://scenes/UI/multiplayer_menu.tscn")
    else:
        get_tree().change_scene_to_file("res://scenes/UI/multiplayer_menu.tscn")

func _on_player_list_changed(new_players: Dictionary) -> void:
    _players_in_lobby = new_players.duplicate(true)
    _update_lobby_header()
    _update_player_list(new_players)
    _update_start_game_button()
    _update_character_grid_lock(new_players)

func _on_game_started(player_data: Dictionary) -> void:
    # Transition to the actual game scene if available
    var sc: Node = get_node_or_null("/root/SceneChanger")
    if sc:
        sc.call("change_scene_to_file", "res://scenes/game/game_scene.tscn", {"players": player_data})
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
