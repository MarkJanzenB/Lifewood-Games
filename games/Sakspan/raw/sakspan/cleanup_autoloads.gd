extends EditorScript

func _run():
    # Get current autoloads
    var autoloads = ProjectSettings.get_setting("autoload")
    
    print("Current autoloads:")
    for i in range(autoloads.size()):
        var autoload = autoloads[i]
        print("- ", autoload.name, " -> ", autoload.path)
    
    # Remove any GameManager entries
    var new_autoloads = []
    for autoload in autoloads:
        if autoload.name != "GameManager":
            new_autoloads.append(autoload)
    
    # Update project settings
    ProjectSettings.set_setting("autoload", new_autoloads)
    ProjectSettings.save()
    
    print("\nCleaned up autoloads:")
    for i in range(new_autoloads.size()):
        var autoload = new_autoloads[i]
        print("- ", autoload.name, " -> ", autoload.path)
    
    print("\nPlease restart the Godot editor for changes to take effect.")
    
    # Now add GameManager back as an autoload
    var game_manager_autoload = {
        "name": "GameManager",
        "path": "res://scripts/global/GameManager.gd"
    }
    
    new_autoloads.append(game_manager_autoload)
    ProjectSettings.set_setting("autoload", new_autoloads)
    ProjectSettings.save()
    
    print("\nAdded GameManager back as an autoload.")
    print("Please restart the Godot editor for changes to take effect.")
