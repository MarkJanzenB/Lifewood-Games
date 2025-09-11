# GameLibrary.gd
# FINAL, DEFINITIVE VERSION - Correctly finds external files in both editor and export.
extends Control

# ... (consts and @onready vars are the same) ...
const GameCard = preload("res://Scenes/GameCard.tscn")
const NoGamesMessage = preload("res://Scenes/NoGamesMessage.tscn")
const GameSettingsPanel = preload("res://Scenes/GameSettingsPanel.tscn")
@onready var grid: GridContainer = $PanelContainer/HBoxContainer/ContentArea/ScrollContainer/MarginContainer/GridContainer
@onready var hbox_container: HBoxContainer = $PanelContainer/HBoxContainer
@onready var content_area: PanelContainer = $PanelContainer/HBoxContainer/ContentArea
@onready var add_game_dialog: FileDialog = $AddGameDialog
var settings_panel_instance
var game_database = []

func _ready():
	settings_panel_instance = GameSettingsPanel.instantiate()
	add_child(settings_panel_instance)
	settings_panel_instance.hide()
	settings_panel_instance.settings_saved.connect(_on_settings_saved)
	settings_panel_instance.settings_cancelled.connect(_on_settings_cancelled)
	
	load_game_database_from_file()
	initialize_folders()
	update_library_view()

# --- THIS IS THE ONLY FUNCTION THAT NEEDS REPLACING ---
# It now correctly finds the project root when in the editor.
func _get_base_directory() -> String:
	if OS.has_feature("export"):
		# When exported, this is correct. It gets the folder where the .exe is.
		return OS.get_executable_path().get_base_dir()
	else:
		# When running in the editor, this gets the true project root folder.
		return DirAccess.open("res://").get_current_dir().get_base_dir()

# ... (all other functions in this script are now correct and do not need to be changed)
# ... (load_game_database_from_file, initialize_folders, update_library_view, _save_database_to_file, etc...)
# ... PASTE THE REST OF YOUR EXISTING GAMELIBRARY.GD SCRIPT HERE ...
func load_game_database_from_file():
	var games_list_path = _get_games_list_path()
	if not FileAccess.file_exists(games_list_path):
		_save_database_to_file()
		return
	var file = FileAccess.open(games_list_path, FileAccess.READ)
	var content = file.get_as_text()
	var json = JSON.parse_string(content)
	if json != null and json.has("games"): game_database = json.games

func initialize_folders():
	var base_dir = _get_base_directory()
	var games_dir_path = base_dir.path_join("games")
	if not DirAccess.dir_exists_absolute(games_dir_path): DirAccess.make_dir_absolute(games_dir_path)

func update_library_view():
	var old_message = hbox_container.find_child("no_games_message", false)
	if old_message: old_message.queue_free()
	for child in grid.get_children(): child.queue_free()
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

func _save_database_to_file():
	var games_list_path = _get_games_list_path()
	var file = FileAccess.open(games_list_path, FileAccess.WRITE)
	var data_to_save = {"games": game_database}
	var json_string = JSON.stringify(data_to_save, "\t", true)
	file.store_string(json_string)
	file.close()

func _get_games_list_path() -> String:
	return _get_base_directory().path_join("GamesList.json")

func _on_game_settings_requested(game_data: Dictionary):
	var data_with_lookup = game_data.duplicate()
	data_with_lookup["original_folder_for_lookup"] = game_data.folder
	settings_panel_instance.open_with_data(data_with_lookup)

func _on_settings_saved(updated_data: Dictionary):
	var original_folder = updated_data.get("original_folder_for_lookup", "")
	for i in range(game_database.size()):
		if game_database[i].folder == original_folder:
			updated_data.erase("original_folder_for_lookup")
			game_database[i] = updated_data
			break
	_save_database_to_file()
	update_library_view()

func _on_settings_cancelled():
	print("Settings change cancelled.")

func _on_add_game_button_pressed():
	add_game_dialog.popup_centered()

func _on_add_game_dialog_dir_selected(dir_path: String):
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
	var new_game_data = { "title": dir_path.get_file(), "folder": dir_path, "executable": found_exe }
	game_database.append(new_game_data)
	_save_database_to_file()
	update_library_view()

func _on_button_ph_pressed():
	load_game_database_from_file()
	update_library_view()

func _on_button_back_pressed():
	get_tree().change_scene_to_file("res://Scenes/CountrySelection.tscn")

func _on_button_quit_pressed():
	get_tree().quit()
