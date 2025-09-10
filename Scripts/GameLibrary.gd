# GameLibrary.gd
# FINAL VERSION - Reads EXTERNAL-ONLY GamesList.json
extends Control

const GameCard = preload("res://Scenes/GameCard.tscn")
const NoGamesMessage = preload("res://Scenes/NoGamesMessage.tscn")

@onready var grid: GridContainer = $PanelContainer/HBoxContainer/ContentArea/ScrollContainer/MarginContainer/GridContainer
@onready var hbox_container: HBoxContainer = $PanelContainer/HBoxContainer
@onready var content_area: PanelContainer = $PanelContainer/HBoxContainer/ContentArea

var game_database = []

func _ready():
	load_game_database_from_file()
	initialize_folders()
	update_library_view()

func load_game_database_from_file():
	# --- THIS IS THE NEW UNIFIED LOGIC ---
	# 1. Determine the base directory.
	var base_dir = ""
	if OS.has_feature("export"):
		# When exported, the base directory is where the .exe is.
		base_dir = OS.get_executable_path().get_base_dir()
	else:
		# When running in the editor, the base directory is the project's root folder.
		base_dir = ProjectSettings.globalize_path("res://")

	# 2. Define the path to the external JSON file.
	var games_list_path = base_dir.path_join("GamesList.json")
	
	print("Attempting to load external game list from: ", games_list_path)
	
	if not FileAccess.file_exists(games_list_path):
		print("ERROR: External GamesList.json not found at the expected path!")
		return

	var file = FileAccess.open(games_list_path, FileAccess.READ)
	var content = file.get_as_text()
	var json = JSON.parse_string(content)
	
	if json == null:
		print("ERROR: Failed to parse GamesList.json. Check for syntax errors.")
		return

	if json.has("games"):
		game_database = json.games
		print("Successfully loaded ", game_database.size(), " games from external list.")
	else:
		print("ERROR: GamesList.json is missing the top-level 'games' array.")

# The rest of the script remains exactly the same.
func initialize_folders():
	var exe_dir = ""
	if OS.has_feature("export"):
		exe_dir = OS.get_executable_path().get_base_dir()
	else:
		exe_dir = ProjectSettings.globalize_path("res://")
		
	var games_dir_path = exe_dir.path_join("games")
	if not DirAccess.dir_exists_absolute(games_dir_path):
		DirAccess.make_dir_absolute(games_dir_path)
	for game_data in game_database:
		var specific_game_path = games_dir_path.path_join(game_data.folder)
		if not DirAccess.dir_exists_absolute(specific_game_path):
			DirAccess.make_dir_absolute(specific_game_path)
	print("Folder check complete.")

func update_library_view():
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

func _on_button_ph_pressed():
	update_library_view()

func _on_button_back_pressed():
	get_tree().change_scene_to_file("res://Scenes/CountrySelection.tscn")

func _on_button_quit_pressed():
	get_tree().quit()
