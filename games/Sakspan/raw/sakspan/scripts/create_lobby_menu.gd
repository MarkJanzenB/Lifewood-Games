#res://scenes/UI/Create_Lobby/create_lobby_menu.tscn
extends Control

# --- NODE REFERENCES ---
@onready var lobby_name_line_edit: LineEdit = $FormPanel/FormMargin/FormVBox/LobbyNameHBox/LobbyNameLineEdit
@onready var max_players_option: OptionButton = $FormPanel/FormMargin/FormVBox/MaxPlayersHBox/MaxPlayersOptionButton
# FIX: Added the missing reference for the game timer dropdown
@onready var game_timer_option: OptionButton = $FormPanel/FormMargin/FormVBox/GameTimerHBox/GameTimerOptionButton
@onready var create_button: Button = $FormPanel/FormMargin/FormVBox/create_lobby_button
@onready var back_button: Button = $FormPanel/FormMargin/FormVBox/back_button

# --- CONSTANTS FOR CHOICES ---
const MAX_PLAYER_CHOICES = [2, 3, 4, 5]
const TIMER_CHOICES = ["2 minutes", "5 minutes", "10 minutes"]

func _ready():
	# Connect signals to their functions
	create_button.pressed.connect(_on_create_button_pressed)
	back_button.pressed.connect(_on_back_button_pressed)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	
	# FIX: Call the function to populate the dropdowns
	_populate_options()

# This new function adds the items to your OptionButtons
func _populate_options():
	# Populate Max Players
	for num_players in MAX_PLAYER_CHOICES:
		max_players_option.add_item(str(num_players))
	# Set a default selection (e.g., 4 players)
	max_players_option.select(2) # Index 2 corresponds to "4" in our array

	# Populate Game Timer
	for timer_choice in TIMER_CHOICES:
		game_timer_option.add_item(timer_choice)
	# Set a default selection (e.g., 5 minutes)
	game_timer_option.select(1) # Index 1 corresponds to "5 minutes"

func _on_create_button_pressed():
	# Get player name from a global setting or another input field
	var player_name = "Host" + str(randi_range(1000, 9999))
	var lobby_name = lobby_name_line_edit.text
	if lobby_name.is_empty():
		lobby_name = player_name + "'s Room" # Default name
		
	# Get the selected values from the dropdowns
	var max_players = int(max_players_option.get_item_text(max_players_option.selected))
	var timer_setting = game_timer_option.get_item_text(game_timer_option.selected)
	
	print("[CreateLobby] Creating room '%s' with %d max players" % [lobby_name, max_players])
	NetworkManager.create_lobby(player_name, lobby_name, max_players, timer_setting)

func _on_back_button_pressed():
	SceneChanger.change_scene_to_file("res://scenes/UI/Multiplayer/multiplayer_menu.tscn")

func _on_connection_succeeded():
	var init := {"lobby_info": NetworkManager.my_lobby_data, "is_host": true}
	SceneChanger.change_scene_to_file("res://scenes/UI/Lobby_Wait_Room/lobby_wait_room_menu.tscn", init)
