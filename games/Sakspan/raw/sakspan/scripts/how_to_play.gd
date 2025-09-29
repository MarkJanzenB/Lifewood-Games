# res://scripts/how_to_play.gd

extends Control

@onready var back_button: Button = $BackButton
@onready var tab_container: TabContainer = $MainContainer/TabContainer

func _ready() -> void:
	# Connect back button
	if back_button:
		back_button.pressed.connect(_on_back_button_pressed)
	
	# Start background music
	if MusicManager:
		MusicManager.force_start_main_theme()
	
	# Set default tab to Overview
	if tab_container:
		tab_container.current_tab = 0
		print("[HowToPlay] Initialized with ", tab_container.get_tab_count(), " tabs")

func _on_back_button_pressed() -> void:
	print("[HowToPlay] Back to main menu pressed")
	# Return to main menu
	SceneChanger.change_scene_to_file("res://scenes/UI/Main_Menu/main_menu.tscn")

# Handle escape key to go back
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_button_pressed()

# Handle tab navigation with number keys
func _unhandled_input(event: InputEvent) -> void:
	if not tab_container:
		return
		
	if event is InputEventKey and event.pressed:
		var tab_count = tab_container.get_tab_count()
		
		# Number keys 1-8 for quick tab switching
		if event.keycode >= KEY_1 and event.keycode <= KEY_8:
			var tab_index = event.keycode - KEY_1
			if tab_index < tab_count:
				tab_container.current_tab = tab_index
				print("[HowToPlay] Switched to tab: ", tab_index)
