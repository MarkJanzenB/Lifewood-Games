# GameCard.gd
# UPDATED for new directory structure.
extends PanelContainer

# --- Updated Asset Preload ---
const PLACEHOLDER_ART = preload("res://Assets/placeholder_art.png")

@onready var title_label: Label = $VBoxContainer/Label
@onready var box_art_rect: TextureRect = $VBoxContainer/BoxArt

var game_folder_name: String = ""
var game_title: String = ""

func _ready():
	assert(title_label != null, "ERROR on GameCard.tscn: The 'Label' node was not found.")
	assert(box_art_rect != null, "ERROR on GameCard.tscn: The 'BoxArt' node was not found.")

func setup_card(p_title: String, p_folder: String):
	game_title = p_title
	game_folder_name = p_folder
	title_label.text = game_title
	
	var art_to_display = PLACEHOLDER_ART
	
	# This path is still correct for finding art inside your Godot project.
	var png_path = "res://games/" + game_folder_name + "/art.png"
	var jpg_path = "res://games/" + game_folder_name + "/art.jpg"
	
	if FileAccess.file_exists(png_path):
		art_to_display = load(png_path)
	elif FileAccess.file_exists(jpg_path):
		art_to_display = load(jpg_path)
		
	box_art_rect.texture = art_to_display

func _on_play_button_pressed():
	if game_folder_name.is_empty():
		return

	var exe_dir = OS.get_executable_path().get_base_dir()
	var game_exe_path = exe_dir.path_join("games").path_join(game_folder_name).path_join(game_folder_name + ".exe")
	
	print("Attempting to launch game at: ", game_exe_path)
	
	var err = OS.create_process(game_exe_path, [])
	if err != OK:
		print("LAUNCH FAILED! Error code: ", err)
