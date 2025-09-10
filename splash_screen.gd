# SplashScreen.gd
extends Control

func _on_timer_timeout():
	# Here's the new logic:
	# We ask our global UserSettings script if a country setting has been saved.
	if UserSettings.has_country_setting():
		# If a setting EXISTS, we skip country selection and go to the library.
		get_tree().change_scene_to_file("res://GameLibrary.tscn")
	else:
		# If a setting does NOT exist, we show the one-time country selection screen.
		get_tree().change_scene_to_file("res://CountrySelection.tscn")
