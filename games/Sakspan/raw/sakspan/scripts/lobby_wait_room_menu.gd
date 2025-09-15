extends Control

@onready var lobby_name_label: Label = get_node_or_null("YOUR_PATH_TO_LobbyNameLabel")
@onready var players_count_label: Label = get_node_or_null("YOUR_PATH_TO_PlayersCountLabel")
@onready var player_list_container: VBoxContainer = get_node_or_null("YOUR_PATH_TO_PlayerListContainer")
@onready var character_grid: GridContainer = get_node_or_null("YOUR_PATH_TO_CharacterGrid")
@onready var lock_in_button: Button = get_node_or_null("YOUR_PATH_TO_LockInButton")
@onready var start_game_button: Button = get_node_or_null("YOUR_PATH_TO_StartGameButton")
@onready var leave_lobby_button: Button = get_node_or_null("YOUR_PATH_TO_LeaveLobbyButton")

const CHARACTER_COUNT := 5
const CHARACTER_ICONS := [
	preload("res://assets/characters/char_0.png"),
	preload("res://assets/characters/char_1.png"),
	preload("res://assets/characters/char_2.png"),
	preload("res://assets/characters/char_3.png"),
	preload("res://assets/characters/char_4.png")
]

var selected_char_index: int = -1
var locked_in: bool = false
var is_host: bool = false
var lobby_data: Dictionary = {}

func _ready():
	_check_ui_nodes()
	NetworkManager.player_list_changed.connect(_on_player_list_changed)
	NetworkManager.game_started.connect(_on_game_started)
	if start_game_button:
		start_game_button.pressed.connect(_on_start_game_button_pressed)
	if lock_in_button:
		lock_in_button.pressed.connect(_on_lock_in_button_pressed)
	if leave_lobby_button:
		leave_lobby_button.pressed.connect(_on_leave_lobby_button_pressed)

	# Load lobby data from NetworkManager
	lobby_data = NetworkManager.my_lobby_data
	is_host = (NetworkManager.players.has(1) and NetworkManager.players[1].name == NetworkManager.my_name)
	if lobby_name_label:
		lobby_name_label.text = "Lobby: " + lobby_data.get("name", "Unnamed Lobby")
	_update_player_list(NetworkManager.players)
	_setup_character_grid()
	_update_start_game_button()

func _check_ui_nodes():
	if not lobby_name_label: push_warning("[LobbyWaitRoom] LobbyNameLabel not found.")
	if not players_count_label: push_warning("[LobbyWaitRoom] PlayersCountLabel not found.")
	if not player_list_container: push_warning("[LobbyWaitRoom] PlayerListContainer not found.")
	if not character_grid: push_warning("[LobbyWaitRoom] CharacterGrid not found.")
	if not lock_in_button: push_warning("[LobbyWaitRoom] LockInButton not found.")
	if not start_game_button: push_warning("[LobbyWaitRoom] StartGameButton not found.")
	if not leave_lobby_button: push_warning("[LobbyWaitRoom] LeaveLobbyButton not found.")

func _setup_character_grid():
	if not character_grid: return
	character_grid.clear()
	for i in range(CHARACTER_COUNT):
		var btn = TextureButton.new()
		btn.texture_normal = CHARACTER_ICONS[i]
		btn.toggle_mode = true
		btn.pressed.connect(_on_character_selected.bind(i))
		character_grid.add_child(btn)

func _on_character_selected(idx: int):
	if locked_in: return
	selected_char_index = idx
	_update_character_grid_highlight()

func _update_character_grid_highlight():
	if not character_grid: return
	for i in range(character_grid.get_child_count()):
		var btn = character_grid.get_child(i)
		btn.button_pressed = (i == selected_char_index)

func _on_lock_in_button_pressed():
	if selected_char_index == -1 or locked_in: return
	NetworkManager.request_char_selection(selected_char_index)
	locked_in = true
	lock_in_button.disabled = true

func _on_player_list_changed(players: Dictionary):
	_update_player_list(players)
	_update_start_game_button()
	_update_character_grid_lock(players)

func _update_player_list(players: Dictionary):
	if not player_list_container: return
	player_list_container.clear()
	var count = 0
	for id in players:
		var p = players[id]
		var label = Label.new()
		var char_text = p.char_index >= 0 ? " (Char %d)" % p.char_index : ""
		label.text = "%s%s%s" % [p.name, p.is_host ? " (Host)" : "", char_text]
		player_list_container.add_child(label)
		count += 1
	if players_count_label:
		players_count_label.text = "Players: %d/%d" % [count, lobby_data.get("max_players", 5)]

func _update_character_grid_lock(players: Dictionary):
	if not character_grid: return
	# Disable buttons for characters already picked
	var picked = []
	for id in players:
		var idx = players[id].char_index
		if idx >= 0:
			picked.append(idx)
	for i in range(character_grid.get_child_count()):
		var btn = character_grid.get_child(i)
		btn.disabled = (i in picked and players.values().find({"char_index": i, "name": NetworkManager.my_name}) == -1)

func _update_start_game_button():
	if not start_game_button: return
	start_game_button.disabled = true
	if is_host:
		# Host can only start if at least 2 players and all are locked in
		var players = NetworkManager.players
		var ready_count = 0
		for id in players:
			if players[id].ready:
				ready_count += 1
		if players.size() >= 2 and ready_count == players.size():
			start_game_button.disabled = false
	else:
		start_game_button.disabled = true

func _on_start_game_button_pressed():
	if is_host:
		NetworkManager.start_game()

func _on_game_started(_player_data):
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_leave_lobby_button_pressed():
	NetworkManager.leave_lobby()
	get_tree().change_scene_to_file("res://scenes/UI/multiplayer_menu.tscn")
