extends EditorScript

func _run():
	# Define required autoloads with their paths
	var required_autoloads = [
		{"name": "NetworkManager", "path": "res://scripts/global/NetworkManager.gd"},
		{"name": "SceneChanger", "path": "res://scripts/global/SceneChanger.gd"},
		{"name": "GameManager", "path": "res://scenes/GameManager.tscn"}
	]
	
	# Get current autoloads
	var autoloads = ProjectSettings.get_setting("autoload")
	var autoloads_updated = false
	
	# Check each required autoload
	for required in required_autoloads:
		var exists = false
		
		# Check if it already exists
		for autoload in autoloads:
			if autoload.name == required.name:
				exists = true
				# Update path if it's different
				if autoload.path != required.path:
					autoload.path = required.path
					autoloads_updated = true
				break
		
		# Add if it doesn't exist
		if not exists:
			autoloads.append({
				"name": required.name,
				"path": required.path
			})
			autoloads_updated = true
	
	# Save changes if any were made
	if autoloads_updated:
		ProjectSettings.set_setting("autoload", autoloads)
		ProjectSettings.save()
		print("Autoloads have been updated. Please restart the Godot editor for changes to take effect.")
	else:
		print("All required autoloads are already set up correctly.")
	
	# Print current autoloads for verification
	print("\nCurrent autoloads:")
	for autoload in autoloads:
		print("- ", autoload.name, " -> ", autoload.path)
