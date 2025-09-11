# GameCard.gd
# FINAL VERSION - Uses absolute paths for both launching and artwork.
extends PanelContainer

signal settings_requested(game_data)

const PLACEHOLDER_ART = preload("res://Assets/placeholder_art.png")

@onready var title_label: Label = $VBoxContainer/Label
@onready var box_art_rect: TextureRect = $VBoxContainer/BoxArt

var game_data: Dictionary

func _ready():
	assert(title_label != null, "ERROR on GameCard.tscn: The 'Label' node was not found.")
	assert(box_art_rect != null, "ERROR on GameCard.tscn: The 'BoxArt' (TextureRect) node was not found.")

func setup_card(p_game_data: Dictionary):
	self.game_data = p_game_data
	title_label.text = game_data.title
	# This function now correctly handles absolute paths.
	_load_artwork()

# --- THIS IS THE UPDATED FUNCTION ---
# This private function now uses the absolute path stored in game_data.
func _load_artwork():
	# 1. Get the full, absolute path to the game's folder from our data.
	# We use .get() for safety in case the key is missing.
	var game_folder_path = game_data.get("folder", "")
	
	# If the path is empty for some reason, just use the placeholder and stop.
	if game_folder_path.is_empty():
		box_art_rect.texture = PLACEHOLDER_ART
		return

	# 2. Define the exact, absolute paths to the potential art files.
	var png_path = game_folder_path.path_join("art.png")
	var jpg_path = game_folder_path.path_join("art.jpg")
	
	# 3. Try to load the image from the absolute paths.
	var image = Image.new()
	if image.load(png_path) == OK:
		# If the PNG was loaded successfully, create a texture and display it.
		box_art_rect.texture = ImageTexture.create_from_image(image)
		return # Stop here, we found the art.
	
	if image.load(jpg_path) == OK:
		# If the JPG was loaded successfully, do the same.
		box_art_rect.texture = ImageTexture.create_from_image(image)
		return # Stop here.
	
	# 4. If neither file was found at the absolute path, use the placeholder.
	box_art_rect.texture = PLACEHOLDER_ART

# This is the updated play button function that also uses absolute paths.
func _on_play_button_pressed():
	if game_data.is_empty():
		return

	# The 'folder' key already contains the FULL path to the game's directory.
	var game_folder_path = game_data.get("folder", "")
	var game_executable = game_data.get("executable", "")
	
	# We simply join the absolute folder path with the executable's name.
	var game_exe_path = game_folder_path.path_join(game_executable)
	
	print("FINAL ATTEMPT to launch game at (absolute path): ", game_exe_path)
		
	var pid = OS.create_process(game_exe_path, [])
	
	if pid > 0:
		Global.monitor_game_process(pid)
	else:
		OS.alert("Failed to launch the game. Please verify the path in the game's settings and ensure the file exists.", "Launch Error")

# This function is connected to the SettingsButton and remains the same.
func _on_settings_button_pressed():
	settings_requested.emit(game_data)
