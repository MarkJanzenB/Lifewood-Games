# AddingGameScreen.gd
extends PanelContainer

@onready var timer = $Timer

# When the scene loads, start the timer immediately.
func _ready():
	timer.start()

# When the timer finishes, go back to the GameLibrary.
# By the time this runs, the GameLibrary will be forced to fully reload
# itself, reading the updated GamesList.json file.
func _on_timer_timeout():
	get_tree().change_scene_to_file("res://Scenes/GameLibrary.tscn")
