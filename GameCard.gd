# GameCard.gd
# FINAL VERSION for EXE Distribution
extends PanelContainer

const PLACEHOLDER_ART = preload("res://placeholder_art.png")

@onready var title_label: Label = $VBoxContainer/Label
@onready var box_art_rect: TextureRect = $VBoxContainer/BoxArt

var game_folder_name: String = ""
var game_title: String = ""

func _ready():
	assert(title_label != null, "ERROR on GameCard.tscn: The 'Label' node was not found.")
	assert(box_art_rect != null, "ERROR on GameCard.tscn: The 'BoxArt' (TextureRect) node was not found.")

func setup_card(p_title: String, p_folder: String):
	game_title = p_title
	game_folder_name = p_folder
	title_label.text = game_title
	
	# --- Art Loading Logic (No changes needed here) ---
	var art_to_display = PLACEHOLDER_ART
	var png_path = "res://games/" + game_folder_name + "/art.png"
	var jpg_path = "res://games/" + game_folder_name + "/art.jpg"
	
	if FileAccess.file_exists(png_path):
		art_to_display = load(png_path)
	elif FileAccess.file_exists(jpg_path):
		art_to_display = load(jpg_path)
		
	box_art_rect.texture = art_to_display

func _on_play_button_pressed():
	if game_folder_name.is_empty():
		print("ERROR: Play button clicked, but no folder name is set.")
		return

	# --- THIS IS THE KEY LOGIC FOR AN EXE LAUNCHER ---
	# 1. Get the directory where "Lifewood Games.exe" is currently running.
	var exe_dir = OS.get_executable_path().get_base_dir()
	
	# 2. Build the path to the game's folder relative to the exe.
	#    This will correctly point to: ".../Lifewood Games/games/MyFirstGame/"
	var game_folder_path = exe_dir.path_join("games").path_join(game_folder_name)
	
	# 3. Build the full path to the game's executable inside that folder.
	#    This will point to: ".../MyFirstGame/MyFirstGame.exe"
	var game_exe_path = game_folder_path.path_join(game_folder_name + ".exe")
	
	print("Attempting to launch game at: ", game_exe_path)
	
	# We can't use FileAccess.file_exists() on external files easily.
	# Instead, we just try to launch it. A dialog for errors would be a good future feature.
	var err = OS.create_process(game_exe_path, [])
	
	if err != OK:
		print("LAUNCH FAILED! Error code: ", err)
		# Here you could implement a pop-up dialog to inform the user.
