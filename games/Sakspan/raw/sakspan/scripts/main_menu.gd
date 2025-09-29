# res://scenes/UI/Main_Menu/main_menu.tscn

extends Control

@onready var single_click_effect: AudioStreamPlayer = get_node_or_null("single_click_effect")
@onready var start_button: Button = get_node_or_null("CenterContainer/MenuVBox/ButtonsVBox/start_game_button")
@onready var how_to_play_button: Button = get_node_or_null("CenterContainer/MenuVBox/ButtonsVBox/how_to_play_button")
@onready var options_button: Button = get_node_or_null("CenterContainer/MenuVBox/ButtonsVBox/options_button")
@onready var quit_button: Button = get_node_or_null("CenterContainer/MenuVBox/ButtonsVBox/quit_button")

func _ready() -> void:
	# Start background music
	MusicManager.force_start_main_theme()
	
	# Set audio bus for UI sounds
	if single_click_effect:
		single_click_effect.bus = "UI"
	
	# Check Audio - use the correct sound file
	if single_click_effect and not single_click_effect.stream:
		# Load the actual click effect file
		var click_sound := load("res://assets/sound_effects/single_click_effect.mp3")
		if click_sound:
			single_click_effect.stream = click_sound
		else:
			push_warning("[MainMenu] 'single_click_effect.mp3' not found.")
	elif not single_click_effect:
		push_warning("[MainMenu] Missing 'single_click_effect' AudioStreamPlayer node.")

	# Hook up buttons only if they exist
	if start_button:
		start_button.pressed.connect(_on_start_game_button_pressed)
	else:
		push_warning("[MainMenu] 'start_game_button' not found.")
	
	if how_to_play_button:
		how_to_play_button.pressed.connect(_on_how_to_play_button_pressed)
	else:
		push_warning("[MainMenu] 'how_to_play_button' not found.")
		
	if options_button:
		options_button.pressed.connect(_on_options_button_pressed)
	else:
		push_warning("[MainMenu] 'options_button' not found.")
		
	if quit_button:
		quit_button.pressed.connect(_on_quit_button_pressed)
	else:
		push_warning("[MainMenu] 'quit_button' not found.")

func _on_start_game_button_pressed() -> void:
	_play_click()
	print("Start Game Button Pressed!")
	# This line will change to the multiplayer menu.
	# Make sure this is the intended next scene when "Start Game" is pressed.
	# If you have a different "main game" scene or a lobby scene that isn't the multiplayer setup,
	# you might want to change this path.
	SceneChanger.change_scene_to_file("res://scenes/UI/Multiplayer/multiplayer_menu.tscn")

func _on_how_to_play_button_pressed() -> void:
	_play_click()
	print("How to Play Button Pressed!")
	# Navigate to the How to Play screen
	SceneChanger.change_scene_to_file("res://scenes/UI/HowToPlay/how_to_play.tscn")

func _on_options_button_pressed() -> void:
	_play_click()
	print("Option Button Pressed!")
	# FIX: Add scene change for the Options button
	# You need to replace "res://scenes/UI/Options/options_menu.tscn" with the actual path
	# to your options menu scene file.
	# If this scene doesn't exist, Godot will print an error to the Output panel.
	SceneChanger.change_scene_to_file("res://scenes/UI/Options/options.tscn")


func _on_quit_button_pressed() -> void:
	_play_click()
	print("Quit Button Pressed!")
	get_tree().quit() # exit game

func _play_click() -> void:
	if single_click_effect and single_click_effect.stream:
		single_click_effect.stop()
		single_click_effect.play()
	elif single_click_effect:
		push_warning("[MainMenu] 'single_click_effect' has no AudioStream assigned.")
