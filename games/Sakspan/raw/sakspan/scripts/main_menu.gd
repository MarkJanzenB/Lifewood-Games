extends Control

@onready var single_click_effect: AudioStreamPlayer = get_node_or_null("single_click_effect")
@onready var start_button: Button = get_node_or_null("CenterContainer/MenuVBox/ButtonsVBox/start_game_button")
@onready var options_button: Button = get_node_or_null("CenterContainer/MenuVBox/ButtonsVBox/options_button")
@onready var quit_button: Button = get_node_or_null("CenterContainer/MenuVBox/ButtonsVBox/quit_button")

func _ready() -> void:
	# Check Audio
	if single_click_effect and not single_click_effect.stream:
		# Corrected path for fallback sound effect. Ensure this path is correct.
		var fallback := load("res://assets/sound_effects/single_click.mp3")
		if fallback:
			single_click_effect.stream = fallback
		else:
			push_warning("[MainMenu] Fallback 'single_click.mp3' not found at 'res://assets/sound_effects/single_click.mp3'.")
	elif not single_click_effect:
		push_warning("[MainMenu] Missing 'single_click_effect' AudioStreamPlayer node.")

	# Hook up buttons only if they exist
	if start_button:
		start_button.pressed.connect(_on_start_game_button_pressed)
	else:
		push_warning("[MainMenu] 'start_game_button' not found.")
		
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
	get_tree().change_scene_to_file("res://scenes/UI/Multiplayer/multiplayer_menu.tscn")

func _on_options_button_pressed() -> void:
	_play_click()
	print("Option Button Pressed!")
	# FIX: Add scene change for the Options button
	# You need to replace "res://scenes/UI/Options/options_menu.tscn" with the actual path
	# to your options menu scene file.
	# If this scene doesn't exist, Godot will print an error to the Output panel.
	get_tree().change_scene_to_file("res://scenes/UI/Options/options_menu.tscn")


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
