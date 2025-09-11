# GameLibrary.gd
# This is the final, complete script for the main launcher screen.
# It manages all core logic, including loading, adding, and editing games.
extends Control

# --- Scene Preloads ---
const GameCard = preload("res://Scenes/GameCard.tscn")
const NoGamesMessage = preload("res://Scenes/NoGamesMessage.tscn")
const GameSettingsPanel = preload("res://Scenes/GameSettingsPanel.tscn")

# --- Node References ---
@onready var grid: GridContainer = $PanelContainer/HBoxContainer/ContentArea/ScrollContainer/MarginContainer/GridContainer
@onready var hbox_container: HBoxContainer = $PanelContainer/HBoxContainer
@onready var content_area: PanelContainer = $PanelContainer/HBoxContainer/ContentArea
@onready var add_game_dialog: FileDialog = $AddGameDialog

# --- State Variables ---
var settings_panel_instance
var game_database = []

# The _ready() function is the entry point when the scene loads.
func _ready():
	# Instance the settings panel once and keep it ready, but hidden.
	settings_panel_instance = GameSettingsPanel.instantiate()
	add_child(settings_panel_instance)
	settings_panel_instance.hide()
	
	# Connect to the panel's signals to handle user actions.
	settings_panel_instance.settings_saved.connect(_on_settings_saved)
	settings_panel_instance.settings_cancelled.connect(_on_settings_cancelled)
	
	# Run the startup sequence.
	load_game_database_from_file()
	initialize_folders()
	update_library_view()

# --- Core Logic Functions ---

# Loads the game list from the external GamesList.json file.
func load_game_database_from_file():
	var games_list_path = _get_games_list_path()
	print("Attempting to load external game list from: ", games_list_path)
	
	# If the file doesn't exist, create a new, empty one.
	if not FileAccess.file_exists(games_list_path):
		print("WARNING: GamesList.json not found! Creating a new one.")
		_save_database_to_file() # Saving an empty database creates the file.
		return

	# If the file exists, read and parse it.
	var file = FileAccess.open(games_list_path, FileAccess.READ)
	var content = file.get_as_text()
	var json = JSON.parse_string(content)
	
	if json == null:
		print("ERROR: Failed to parse GamesList.json. The file might be corrupted.")
		return

	if json.has("games"):
		game_database = json.games
		print("Successfully loaded ", game_database.size(), " games from external list.")
	else:
		print("ERROR: GamesList.json is missing the top-level 'games' array.")

# Creates necessary folders on disk if they are missing.
func initialize_folders():
	print("Checking for required folders...")
	# This function no longer creates specific game folders, as paths are absolute.
	# We can keep a default "games" folder for convenience if desired.
	var base_dir = _get_base_directory()
	var games_dir_path = base_dir.path_join("games")
	if not DirAccess.dir_exists_absolute(games_dir_path):
		print("Default 'games' folder not found. Creating it.")
		DirAccess.make_dir_absolute(games_dir_path)
	print("Folder check complete.")

# Clears and rebuilds the UI display of game cards.
func update_library_view():
	# Cleanup old UI elements.
	var old_message = hbox_container.find_child("no_games_message", false)
	if old_message: old_message.queue_free()
	for child in grid.get_children(): child.queue_free()
	
	# Decide whether to show the "No Games" message or the game cards.
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
			card.settings_requested.connect(_on_game_settings_requested)
			card.setup_card(game_data)

# Saves the current state of the game_database array back to the JSON file.
func _save_database_to_file():
	var games_list_path = _get_games_list_path()
	var file = FileAccess.open(games_list_path, FileAccess.WRITE)
	var data_to_save = {"games": game_database}
	var json_string = JSON.stringify(data_to_save, "\t", true)
	file.store_string(json_string)
	file.close()
	print("GamesList.json has been updated.")

# --- Helper Functions ---

func _get_games_list_path() -> String:
	return _get_base_directory().path_join("GamesList.json")

func _get_base_directory() -> String:
	if OS.has_feature("export"):
		return OS.get_executable_path().get_base_dir()
	else:
		return ProjectSettings.globalize_path("res://")

# --- Signal Handlers ---

func _on_game_settings_requested(game_data: Dictionary):
	print("Opening settings for: ", game_data.title)
	# Add a temporary key to the dictionary. This is the original, unchanged folder path
	# that we will use to find the game again when saving, even if the user changes the path.
	var data_with_lookup = game_data.duplicate()
	data_with_lookup["original_folder_for_lookup"] = game_data.folder
	settings_panel_instance.open_with_data(data_with_lookup)

func _on_settings_saved(updated_data: Dictionary):
	print("Saving new settings for: ", updated_data.title)
	# Use the temporary lookup key to find the game to update.
	var original_folder = updated_data.get("original_folder_for_lookup", "")
	
	for i in range(game_database.size()):
		if game_database[i].folder == original_folder:
			updated_data.erase("original_folder_for_lookup") # Clean up the temporary key.
			game_database[i] = updated_data # Replace the old data.
			break
	
	_save_database_to_file()
	update_library_view()

func _on_settings_cancelled():
	print("Settings change cancelled.")

func _on_add_game_button_pressed():
	add_game_dialog.popup_centered()

func _on_add_game_dialog_dir_selected(dir_path: String):
	print("User selected folder to add: ", dir_path)
	var found_exe = ""
	var dir = DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".exe"):
				found_exe = file_name
				break
			file_name = dir.get_next()
	else:
		OS.alert("Could not access the selected directory.", "Error")
		return

	if found_exe.is_empty():
		OS.alert("No executable (.exe) file was found in the selected folder.", "Executable Not Found")
		return
		
	var new_game_data = {
		"title": dir_path.get_file(),
		"folder": dir_path,
		"executable": found_exe
	}
	
	print("New game found! Title: '", new_game_data.title, "', Executable: '", new_game_data.executable, "'")
	
	game_database.append(new_game_data)
	_save_database_to_file()
	update_library_view() # This line refreshes the UI.

# --- Sidebar Button Functions ---

func _on_button_ph_pressed():
	load_game_database_from_file()
	update_library_view()

func _on_button_back_pressed():
	get_tree().change_scene_to_file("res://Scenes/CountrySelection.tscn")

func _on_button_quit_pressed():
	get_tree().quit()
