# CountrySelection.gd
extends Control

# The _ready() function runs as soon as the scene is loaded.
func _ready():
	# We find the "Others" button and set its disabled property to true.
	# The '$' is a shortcut for get_node().
	# Make sure the path matches your scene tree!
	$VBoxContainer/Button_Others

# This function runs when the "Philippines" button is pressed.
func _on_button_ph_pressed():
	# This is the most important new line:
	# We tell our global UserSettings script to save the choice.
	UserSettings.save_country("Philippines")
	
	# Then we proceed to the game library as before.
	get_tree().change_scene_to_file("res://Scenes/GameLibrary.tscn")

# Since the "Others" button is disabled, we no longer need its function.
# You can safely delete the _on_button_others_pressed() function if it's still here.
