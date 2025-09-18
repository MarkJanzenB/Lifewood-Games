# res://scripts/characters/GreenCharacter.gd
extends PlayerCharacter
class_name GreenCharacter

const CHARACTER_INDEX = 3
const CHARACTER_NAME = "Green"
const CHARACTER_COLOR = Color.GREEN

func _ready():
	super._ready()
	_setup_character_appearance()

func _setup_character_appearance():
	# Set character-specific properties
	if animated_sprite:
		animated_sprite.modulate = CHARACTER_COLOR
	
	print("Green character initialized for player: ", player_name)

func get_character_index() -> int:
	return CHARACTER_INDEX

func get_character_name() -> String:
	return CHARACTER_NAME

func get_character_color() -> Color:
	return CHARACTER_COLOR
