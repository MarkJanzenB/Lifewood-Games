extends EditorScript

func _run():
    # Get current autoloads
    var autoloads = ProjectSettings.get_setting("autoload")
    
    print("Current autoloads:")
    for i in range(autoloads.size()):
        var autoload = autoloads[i]
        print("- ", autoload.name, " -> ", autoload.path)
    
    # Remove any existing GameManager entries
    var new_autoloads = []
    for autoload in autoloads:
        if autoload.name != "GameManager":
            new_autoloads.append(autoload)
    
    # Add the correct GameManager entry
    var game_manager_autoload = {
        "name": "GameManager",
        "path": "res://scenes/GameManager.tscn"
    }
    new_autoloads.append(game_manager_autoload)
    
    # Update project settings
    ProjectSettings.set_setting("autoload", new_autoloads)
    ProjectSettings.save()
    
    print("\nUpdated autoloads:")
    for i in range(new_autoloads.size()):
        var autoload = new_autoloads[i]
        print("- ", autoload.name, " -> ", autoload.path)
    
    print("\nAutoloads have been reset. Please restart the Godot editor for changes to take effect.")
