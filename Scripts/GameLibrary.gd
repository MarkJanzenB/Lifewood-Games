# GameLibrary.gd
# UPDATED for new directory structure.
extends Control

# --- Updated Scene Preloads ---
const GameCard = preload("res://Scenes/GameCard.tscn")
const NoGamesMessage = preload("res://Scenes/NoGamesMessage.tscn")
const GAMES_LIST_PATH = "res://GamesList.json"

@onready var grid: GridContainer = $PanelContainer/HBoxContainer/ContentArea/ScrollContainer/MarginContainer/GridContainer
@onready var hbox_container: HBoxContainer = $PanelContainer/HBoxContainer
@onready var content_area: PanelContainer = $PanelContainer/HBoxContainer/ContentArea

var game_database = []

func _ready():
	load_game_database_from_file()
	initialize_folders()
	update_library_view()

func load_game_database_from_file():
	print("Loading game list from: ", GAMES_LIST_PATH)
	if not FileAccess.file_exists(GAMES_LIST_PATH):
		print("ERROR: GamesList.json not found!")
		return
	var file = FileAccess.open(GAMES_LIST_PATH, FileAccess.READ)
	var content = file.get_as_text()
	var json = JSON.parse_string(content)
	if json == null:
		print("ERROR: Failed to parse GamesList.json.")
		return
	if json.has("games"):
		game_database = json.games
		print("Successfully loaded ", game_database.size(), " games.")
	else:
		print("ERROR: GamesList.json is missing 'games' array.")

func initialize_folders():
	print("Checking for required folders...")
	var exe_dir = OS.get_executable_path().get_base_dir()
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
	print("Philippines tab selected. Reloading games...")
	update_library_view()

func _on_button_back_pressed():
	# --- Updated Scene Path ---
	get_tree().change_scene_to_file("res://Scenes/CountrySelection.tscn")

func _on_button_quit_pressed():
	get_tree().quit()
