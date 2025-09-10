# UserSettings.gd
extends Node

# This is the file path where our settings will be saved.
# "user://" is a special Godot path that saves data in a safe place
# on the user's computer.
const SAVE_PATH = "user://user_settings.cfg"

# This function saves the country name the user picks.
func save_country(country_name: String):
	var config = ConfigFile.new()
	config.set_value("user", "country", country_name)
	config.save(SAVE_PATH)
	print("Saved country:", country_name) # A message for us to see in the output log.

# This function reads the saved file to see what country was picked.
# If it can't find a file, it returns an empty string "".
func load_country() -> String:
	var config = ConfigFile.new()
	# We check if the file exists first to avoid errors.
	if config.load(SAVE_PATH) == OK:
		return config.get_value("user", "country", "")
	return ""

# A helper function that simply checks if a country has been saved at all.
func has_country_setting() -> bool:
	# If the loaded country is NOT an empty string, it means a setting exists.
	return load_country() != ""
