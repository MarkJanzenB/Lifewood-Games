# GameLibrary.gd
# FINAL VERSION - Refactored with a unified refresh_library() function.
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

# The _ready() function is now much simpler.
func _ready():
	settings_panel_instance = GameSettingsPanel.instantiate()
	add_child(settings_panel_instance)
	settings_panel_instance.hide()
	settings_panel_instance.settings_saved.connect(_on_settings_saved)
	settings_panel_instance.settings_cancelled.connect(_on_settings_cancelled)
	
	# REFACTORED: All startup logic is now handled by our new refresh function.
	refresh_library()

# --- NEW: A unified refresh function that is the single source of truth ---
func refresh_library():
	print("Refreshing game library...")
	# 1. Always load the latest data from the file first.
	load_game_database_from_file()
	# 2. Ensure all necessary folders exist based on the loaded data.
	initialize_folders()
	# 3. Redraw the UI based on the in-memory database.
	update_library_view()

# --- Core Logic Functions ---

# This function now only focuses on reading the file into the database.
func load_game_database_from_file():
	var games_list_path = _get_games_list_path()
	if not FileAccess.file_exists(games_list_path):
		_save_database_to_file()
		game_database.clear() # Ensure database is empty if file was just created.
		return

	var file = FileAccess.open(games_list_path, FileAccess.READ)
	var content = file.get_as_text()
	var json = JSON.parse_string(content)
	
	if json != null and json.has("games"):
		game_database = json.games
	else:
		# If file is invalid or missing the "games" key, clear the database for safety.
		game_database.clear()
		print("ERROR: GamesList.json is invalid or missing 'games' array. Library will be empty.")

# This function's logic is still sound.
func initialize_folders():
	var base_dir = _get_base_directory()
	var games_dir_path = base_dir.path_join("games")
	if not DirAccess.dir_exists_absolute(games_dir_path): DirAccess.make_dir_absolute(games_dir_path)
	for game_data in game_database:
		if not DirAccess.dir_exists_absolute(game_data.folder):
			DirAccess.make_dir_absolute(game_data.folder)

# This is the function you asked about. Its logic remains the same, but it is now
# guaranteed to be called with the most up-to-date data.
# Replace this function in GameLibrary.gd

func update_library_view():
	# Cleanup old UI elements.
	var old_message = hbox_container.find_child("no_games_message", false)
	if old_message: old_message.queue_free()
	for child in grid.get_children(): child.queue_free()
	
	# This check is now completely reliable.
	if game_database.is_empty():
		content_area.visible = false
		var message_scene = NoGamesMessage.instantiate()
		message_scene.name = "no_games_message"
		
		# --- THIS IS THE FIX ---
		# Find the Label node within the instanced scene.
		var message_label = message_scene.find_child("Label") 
		if message_label:
			# Now we can safely change its text.
			message_label.text = "Please install or add Lifewood Games"
		# -------------------------
		
		message_scene.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
		hbox_container.add_child(message_scene)
	else:
		content_area.visible = true
		for game_data in game_database:
			var card = GameCard.instantiate()
			grid.add_child(card)
			card.settings_requested.connect(_on_game_settings_requested)
			card.setup_card(game_data)

func _save_database_to_file():
	var games_list_path = _get_games_list_path()
	var file = FileAccess.open(games_list_path, FileAccess.WRITE)
	var data_to_save = {"games": game_database}
	var json_string = JSON.stringify(data_to_save, "\t", true)
	file.store_string(json_string)
	file.close()

# --- Helper Functions (Unchanged) ---
func _get_games_list_path() -> String: return _get_base_directory().path_join("GamesList.json")
func _get_base_directory() -> String:
	if OS.has_feature("export"): return OS.get_executable_path().get_base_dir()
	else: return ProjectSettings.globalize_path("res://")

# --- Signal Handlers (Now simplified to call refresh_library) ---



# Called when the user selects a folder in the AddGameDialog.
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
	
	# 1. Add the new game data to our in-memory list.
	game_database.append(new_game_data)
	# 2. Save the updated list to the file.
	_save_database_to_file()
	
	# --- THIS IS THE FIX ---
	# 3. Instead of trying to refresh, simply switch to our loading screen.
	# The loading screen will then switch back, forcing a clean reload.
	get_tree().change_scene_to_file("res://Scenes/AddingGameScreen.tscn")

func _on_settings_saved(updated_data: Dictionary):
	# ... (logic to find and update the game is the same)
	var original_folder = updated_data.get("original_folder_for_lookup", "")
	for i in range(game_database.size()):
		if game_database[i].folder == original_folder:
			updated_data.erase("original_folder_for_lookup"); game_database[i] = updated_data; break
	
	_save_database_to_file()
	refresh_library() # REFACTORED

# ... (The rest of the signal handlers are unchanged)
func _on_game_settings_requested(game_data: Dictionary):
	var data_with_lookup = game_data.duplicate(); data_with_lookup["original_folder_for_lookup"] = game_data.folder
	settings_panel_instance.open_with_data(data_with_lookup)
func _on_settings_cancelled(): print("Settings change cancelled.")
func _on_add_game_button_pressed(): add_game_dialog.popup_centered()

# --- Sidebar Button Functions (Now simplified) ---
func _on_button_ph_pressed():
	refresh_library() # REFACTORED
func _on_button_back_pressed(): get_tree().change_scene_to_file("res://Scenes/CountrySelection.tscn")
func _on_button_quit_pressed(): get_tree().quit()
