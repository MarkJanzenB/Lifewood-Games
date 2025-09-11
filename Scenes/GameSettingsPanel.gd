# GameSettingsPanel.gd
# FINAL VERSION - Now includes the ability to edit the game title.
extends PanelContainer

signal settings_saved(updated_data)
signal settings_cancelled

# --- Node References (with the new TitleLineEdit) ---
@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var title_line_edit: LineEdit = $MarginContainer/VBoxContainer/TitleLineEdit
@onready var folder_line_edit: LineEdit = $MarginContainer/VBoxContainer/HBoxContainer2/FolderLineEdit
@onready var executable_line_edit: LineEdit = $MarginContainer/VBoxContainer/HBoxContainer3/ExecutableLineEdit
@onready var folder_dialog: FileDialog = $FolderDialog
@onready var file_dialog: FileDialog = $FileDialog

# --- State Variables ---
var _original_data: Dictionary
var _current_folder_path: String
var _current_executable_path: String
# NEW: We don't need a temporary variable for the title, as the LineEdit holds the state.

# This function now populates the new title field.
func open_with_data(game_data: Dictionary):
	_original_data = game_data
	
	_current_folder_path = game_data.folder
	_current_executable_path = game_data.executable
	
	# Populate all fields, including the new one.
	title_label.text = "Editing: " + game_data.title # Make the top title more descriptive.
	title_line_edit.text = game_data.title
	folder_line_edit.text = game_data.folder
	executable_line_edit.text = game_data.executable
	
	self.show()

# --- Button Press Handlers ---
# (The browse button handlers are unchanged)
func _on_folder_browse_button_pressed():
	folder_dialog.popup_centered()

func _on_executable_browse_button_pressed():
	file_dialog.current_dir = _current_folder_path
	file_dialog.popup_centered()

# The save function now reads from the new title field.
func _on_save_button_pressed():
	var updated_data = _original_data.duplicate()
	
	# --- THIS IS THE KEY CHANGE ---
	# Read the new values from all three input fields.
	updated_data.title = title_line_edit.text
	updated_data.folder = _current_folder_path
	updated_data.executable = _current_executable_path
	
	settings_saved.emit(updated_data)
	self.hide()

# The cancel function is unchanged.
func _on_cancel_button_pressed():
	settings_cancelled.emit()
	self.hide()

# --- File Dialog Signal Handlers (unchanged) ---
func _on_folder_dialog_dir_selected(dir: String):
	_current_folder_path = dir
	folder_line_edit.text = _current_folder_path

func _on_file_dialog_file_selected(path: String):
	_current_executable_path = path.get_file()
	executable_line_edit.text = _current_executable_path
