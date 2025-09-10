# GameLibrary.gd
# FINAL VERSION with folder initialization on launch.
extends Control

const GameCard = preload("res://Scenes/GameCard.tscn")
const NoGamesMessage = preload("res://Scenes/NoGamesMessage.tscn")

@onready var grid: GridContainer = $PanelContainer/HBoxContainer/ContentArea/ScrollContainer/MarginContainer/GridContainer
@onready var hbox_container: HBoxContainer = $PanelContainer/HBoxContainer
@onready var content_area: PanelContainer = $PanelContainer/HBoxContainer/ContentArea

var game_database = [
	 {"title": "My First Game", "folder": "MyFirstGame"},
	 {"title": "Epic Adventure", "folder": "EpicAdventure"},
	 {"title": "Pixel Racer", "folder": "PixelRacer"},
]

# The _ready() function runs once when the scene loads.
func _ready():
	# --- NEW INITIALIZATION LOGIC ---
	initialize_folders()
	# ------------------------------
	
	# After ensuring folders exist, update the library view as normal.
	update_library_view()

# This new function checks for and creates all necessary game folders.
func initialize_folders():
	print("Checking for required folders...")
	# Get the directory where "Lifewood Games.exe" is running.
	var exe_dir = OS.get_executable_path().get_base_dir()
	
	# Define the path for the main "games" folder.
	var games_dir_path = exe_dir.path_join("games")
	
	# 1. Check for the main "games" folder.
	if not DirAccess.dir_exists_absolute(games_dir_path):
		print("Games folder not found. Creating it at: ", games_dir_path)
		# If it doesn't exist, create it.
		DirAccess.make_dir_absolute(games_dir_path)
	
	# 2. Loop through every game in the database to check for its specific folder.
	for game_data in game_database:
		var specific_game_path = games_dir_path.path_join(game_data.folder)
		if not DirAccess.dir_exists_absolute(specific_game_path):
			print("Folder for '", game_data.title, "' not found. Creating it at: ", specific_game_path)
			# If it doesn't exist, create it.
			DirAccess.make_dir_absolute(specific_game_path)
	
	print("Folder check complete.")

# This function updates the UI (no changes needed here).
func update_library_view():
	# ... (The rest of this function is exactly the same as before)
	var old_message = hbox_container.find_child("no_games_message", false)
	if old_message:
		old_message.queue_free()

	for child in grid.get_children():
		child.queue_free()

	if game_database.is_empty():
		content_area.visible = false
		var message = NoGamesMessage.instantiate()
		message.name = "no_games_message"
		message.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
		hbox_container.add_child(message)
	else:
		content_area.visible = true
		for game_data in game_database:
			var card = GameCard.instantiate()
			grid.add_child(card)
			card.setup_card(game_data.title, game_data.folder)

# --- Sidebar Button Functions (no changes needed here) ---
func _on_button_ph_pressed():
	print("Philippines tab selected. Reloading games...")
	update_library_view()

func _on_button_back_pressed():
	get_tree().change_scene_to_file("res://CountrySelection.tscn")

func _on_button_quit_pressed():
	get_tree().quit()
