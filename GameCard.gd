# GameCard.gd
# This script controls the behavior of a single game card in the library.
# It is now fully data-driven, loading artwork from specific game folders.
extends PanelContainer

# --- Resource Preloads ---
# Preloading our placeholder image makes it fast to assign as a fallback.
const PLACEHOLDER_ART = preload("res://placeholder_art.png")

# --- Node References ---
# These paths MUST match your GameCard.tscn scene tree exactly.
@onready var title_label: Label = $VBoxContainer/Label
@onready var box_art_rect: TextureRect = $VBoxContainer/BoxArt

# --- Game Data ---
var game_folder_name: String = ""
var game_title: String = ""

# The _ready() function is a powerful self-check.
func _ready():
	# Assertions will crash the game with a clear error if our node paths are wrong.
	assert(title_label != null, "ERROR on GameCard.tscn: The 'Label' node was not found.")
	assert(box_art_rect != null, "ERROR on GameCard.tscn: The 'BoxArt' (TextureRect) node was not found.")

# This function is called from GameLibrary.gd to give this card its specific info.
func setup_card(p_title: String, p_folder: String):
	game_title = p_title
	game_folder_name = p_folder
	
	# Update the text displayed on the card.
	title_label.text = game_title
	
	# --- Load and Display Artwork ---
	# Start by assuming we will use the placeholder.
	var art_to_display = PLACEHOLDER_ART
	
	# Define the exact paths where the real artwork should be, checking for png first.
	var png_path = "res://games/" + game_folder_name + "/art.png"
	var jpg_path = "res://games/" + game_folder_name + "/art.jpg"
	
	# Check if 'art.png' exists in the game's folder.
	if FileAccess.file_exists(png_path):
		# If it exists, load it.
		art_to_display = load(png_path)
	# If no .png was found, check for 'art.jpg' instead.
	elif FileAccess.file_exists(jpg_path):
		# If it exists, load it.
		art_to_display = load(jpg_path)
		
	# Finally, assign the texture (either the real art or the placeholder).
	box_art_rect.texture = art_to_display

# This function is connected to the 'pressed' signal of the PlayButton.
func _on_play_button_pressed():
	if game_folder_name.is_empty():
		print("ERROR: Play button clicked, but no game folder name is set for this card!")
		return

	var launcher_path = OS.get_executable_path().get_base_dir()
	var game_exe_path = launcher_path.path_join("games").path_join(game_folder_name).path_join(game_folder_name + ".exe")
	
	print("Attempting to launch game at: ", game_exe_path)
	
	if FileAccess.file_exists(game_exe_path):
		OS.create_process(game_exe_path, [])
	else:
		print("LAUNCH FAILED: Executable file not found at the path above.")
