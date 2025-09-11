# GameCard.gd
# FINAL, DEFINITIVE VERSION - Correctly finds external files in both editor and export.
extends PanelContainer

# ... (signal and const are the same) ...
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
	_load_artwork()

# --- THIS IS THE ONLY FUNCTION THAT NEEDS REPLACING ---
# It now correctly finds the project root when in the editor.
func _get_base_directory() -> String:
	if OS.has_feature("export"):
		# When exported, this is correct. It gets the folder where the .exe is.
		return OS.get_executable_path().get_base_dir()
	else:
		# When running in the editor, this gets the true project root folder.
		return DirAccess.open("res://").get_current_dir().get_base_dir()

# ... (The rest of the script now uses the fixed helper function)
# ... PASTE THE REST OF YOUR EXISTING GAMECARD.GD SCRIPT HERE ...
func _load_artwork():
	var game_folder_path = game_data.get("folder", "")
	if game_folder_path.is_empty():
		box_art_rect.texture = PLACEHOLDER_ART
		return
	var png_path = game_folder_path.path_join("art.png")
	var jpg_path = game_folder_path.path_join("art.jpg")
	var image = Image.new()
	if image.load(png_path) == OK:
		box_art_rect.texture = ImageTexture.create_from_image(image)
		return
	if image.load(jpg_path) == OK:
		box_art_rect.texture = ImageTexture.create_from_image(image)
		return
	box_art_rect.texture = PLACEHOLDER_ART

func _on_play_button_pressed():
	if game_data.is_empty(): return
	var game_folder_path = game_data.get("folder", "")
	var game_executable = game_data.get("executable", "")
	var game_exe_path = game_folder_path.path_join(game_executable)
	var pid = OS.create_process(game_exe_path, [])
	if pid > 0:
		Global.monitor_game_process(pid)
	else:
		OS.alert("Failed to launch the game. Please verify the path in the game's settings and ensure the file exists.", "Launch Error")

func _on_settings_button_pressed():
	settings_requested.emit(game_data)
