# File: LobbyUI.gd (or your lobby script name)
# This script is attached to your root "PanelContainer" node.
extends Control

# --- SCENE REFERENCES (PATHS) ---
# These paths are based on your screenshot. Double-check them if you have issues.
@onready var lobby_name_label: Label = $HBoxContainer/LobbyNameLab
@onready var players_count_label: Label = $HBoxContainer/PlayersCountLabe
@onready var player_list_container: VBoxContainer = $ScrollContainer/PlayerListContai
@onready var character_grid: GridContainer = $CharacterGrid
@onready var lock_in_button: Button = $LockInButton
@onready var start_game_button: Button = $StartGameButton
@onready var leave_lobby_button: Button = $LeaveLobbyButto

# --- RESOURCES ---
# [!!! IMPORTANT: YOU MUST FIX THIS LINE !!!]
# In the Godot editor, find your "CharacterButton.tscn" file in the FileSystem panel.
# Drag that file and drop it between the parentheses of preload() below.
const CharacterButtonScene = preload("res://scenes/UI/character_button.tscn")

# Make sure these paths to your character images are correct.
const CHARACTER_ICONS := [
	preload("res://scenes/UI/Lobby_Wait_Room/pink_char.png"),
	preload("res://scenes/UI/Lobby_Wait_Room/red_char.png"),
	preload("res://scenes/UI/Lobby_Wait_Room/blue_char.png"),
	preload("res://scenes/UI/Lobby_Wait_Room/green_char.png"),
	preload("res://scenes/UI/Lobby_Wait_Room/yellow_char.png"),
]

# --- LOBBY STATE VARIABLES ---
var selected_char_index: int = -1
var locked_in: bool = false
var is_host: bool = false
var lobby_data: Dictionary = {}


# --- GODOT FUNCTIONS ---
func _ready():
	_check_ui_nodes()
	NetworkManager.player_list_changed.connect(_on_player_list_changed)
	NetworkManager.game_started.connect(_on_game_started)
	
	start_game_button.pressed.connect(_on_start_game_button_pressed)
	lock_in_button.pressed.connect(_on_lock_in_button_pressed)
	leave_lobby_button.pressed.connect(_on_leave_lobby_button_pressed)

	lobby_data = NetworkManager.my_lobby_data
	is_host = multiplayer.is_server()
	lobby_name_label.text = "Lobby: " + lobby_data.get("name", "Unnamed Lobby")
	
	_update_player_list(NetworkManager.players)
	_setup_character_grid()
	_update_start_game_button()


# --- SETUP AND CHECKS ---
func _check_ui_nodes():
	if not lobby_name_label: push_warning("[LobbyWaitRoom] LobbyNameLabel not found.")
	if not players_count_label: push_warning("[LobbyWaitRoom] PlayersCountLabel not found.")
	if not player_list_container: push_warning("[LobbyWaitRoom] PlayerListContainer not found.")
	if not character_grid: push_warning("[LobbyWaitRoom] CharacterGrid not found.")
	if not lock_in_button: push_warning("[LobbyWaitRoom] LockInButton not found.")
	if not start_game_button: push_warning("[LobbyWaitRoom] StartGameButton not found.")
	if not leave_lobby_button: push_warning("[LobbyWaitRoom] LeaveLobbyButton not found.")

# This function now correctly uses your custom CharacterButton scene.
func _setup_character_grid():
	if not character_grid: return
	for child in character_grid.get_children():
		child.queue_free()
		
	for i in range(CHARACTER_ICONS.size()):
		var btn = CharacterButtonScene.instance()
		btn.set_character(CHARACTER_ICONS[i], i)
		btn.character_selected.connect(_on_character_selected)
		character_grid.add_child(btn)


# --- UI UPDATE AND SIGNAL HANDLER FUNCTIONS ---
func _on_character_selected(idx: int):
	if locked_in: return
	selected_char_index = idx
	_update_character_grid_highlight()

# This function now correctly uses the custom "set_selected" method on your buttons.
func _update_character_grid_highlight():
	if not character_grid: return
	for i in range(character_grid.get_child_count()):
		# The "as CharacterButton" cast now works because of "class_name".
		var btn = character_grid.get_child(i) as CharacterButton
		if btn:
			btn.set_selected(i == selected_char_index)

func _update_character_grid_lock(players: Dictionary):
	if not character_grid: return
	var picked = []
	for id in players:
		var idx = players[id].char_index
		if idx >= 0:
			picked.append(idx)
			
	var my_id: int = multiplayer.get_unique_id()
	var my_char: int = -1
	if players.has(my_id):
		my_char = int(players[my_id].get("char_index", -1))
		
	for i in range(character_grid.get_child_count()):
		var btn = character_grid.get_child(i)
		btn.disabled = (i in picked and i != my_char)

func _update_player_list(players: Dictionary):
	if not player_list_container: return
	for c in player_list_container.get_children(): c.queue_free()
	
	var count = 0
	for id in players:
		var p = players[id]
		var label = Label.new()
		var p_name: String = p.get("name", "Player %s" % str(id))
		var p_char: int = int(p.get("char_index", -1))
		var p_is_host: bool = bool(p.get("is_host", false))
		var char_text = " (Picking...)"
		if p_char >= 0:
			char_text = " (Ready)"
			
		var host_text = " (Host)" if p_is_host else ""
		label.text = "%s%s%s" % [p_name, host_text, char_text]
		player_list_container.add_child(label)
		count += 1
		
	if players_count_label:
		players_count_label.text = "Players: %d/%d" % [count, lobby_data.get("max_players", 5)]

func _update_start_game_button():
	if not start_game_button: return
	start_game_button.disabled = true
	if is_host:
		var players = NetworkManager.players
		var ready_count = 0
		for id in players:
			if players[id].char_index >= 0:
				ready_count += 1
		if players.size() >= 2 and ready_count == players.size():
			start_game_button.disabled = false
	else:
		start_game_button.disabled = true


# --- BUTTON PRESS AND NETWORKING ---
func _on_lock_in_button_pressed():
	if selected_char_index == -1 or locked_in: return
	NetworkManager.request_char_selection(selected_char_index)
	locked_in = true
	lock_in_button.disabled = true
	for i in range(character_grid.get_child_count()):
		var btn = character_grid.get_child(i)
		if i != selected_char_index:
			btn.disabled = true

func _on_player_list_changed(players: Dictionary):
	_update_player_list(players)
	_update_start_game_button()
	if not locked_in:
		_update_character_grid_lock(players)

func _on_start_game_button_pressed():
	if is_host:
		NetworkManager.start_game()

func _on_game_started(_player_data):
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_leave_lobby_button_pressed():
	NetworkManager.leave_lobby()
	get_tree().change_scene_to_file("res://scenes/UI/multiplayer_menu.tscn")
