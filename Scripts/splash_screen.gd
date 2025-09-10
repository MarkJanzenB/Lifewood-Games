# splash_screen.gd
extends Control

func _on_timer_timeout():
	if UserSettings.has_country_setting():
		get_tree().change_scene_to_file("res://Scenes/GameLibrary.tscn")
	else:
		get_tree().change_scene_to_file("res://Scenes/CountrySelection.tscn")
