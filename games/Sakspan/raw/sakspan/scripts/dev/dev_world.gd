# dev_world.gd - Passive scene managed by GameManager singleton
# CRITICAL: This scene must NEVER be run directly from the editor (F5/Play Scene)
# It has hard dependencies on NetworkManager's multiplayer session and player data
# All testing must begin from main menu -> lobby -> "Start Game" button

extends Node2D

func _ready():
	# This scene is now passively managed by the GameManager singleton
	print("[DevWorld] dev_world.tscn has loaded for peer ", multiplayer.get_unique_id())
	print("[DevWorld] Scene is now managed by GameManager's scene detection system")
