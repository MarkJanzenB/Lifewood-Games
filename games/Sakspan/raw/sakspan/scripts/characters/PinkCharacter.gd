# res://scripts/characters/PinkCharacter.gd
extends PlayerCharacter
class_name PinkCharacter

const CHARACTER_INDEX = 0
const CHARACTER_NAME = "Pink"
const CHARACTER_COLOR = Color.MAGENTA

func _ready():
	super._ready()
	_setup_character_appearance()

func _setup_character_appearance():
	# Set character-specific properties
	if animated_sprite:
		animated_sprite.modulate = CHARACTER_COLOR
	
	print("Pink character initialized for player: ", player_name)

func get_character_index() -> int:
	return CHARACTER_INDEX

func get_character_name() -> String:
	return CHARACTER_NAME

func get_character_color() -> Color:
	return CHARACTER_COLOR
