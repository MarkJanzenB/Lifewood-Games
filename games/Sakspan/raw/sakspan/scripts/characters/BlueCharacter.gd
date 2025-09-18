# res://scripts/characters/BlueCharacter.gd
extends PlayerCharacter
class_name BlueCharacter

const CHARACTER_INDEX = 2
const CHARACTER_NAME = "Blue"
const CHARACTER_COLOR = Color.BLUE

func _ready():
	super._ready()
	_setup_character_appearance()

func _setup_character_appearance():
	# Set character-specific properties
	if animated_sprite:
		# You can set a modulate color or load specific animations
		animated_sprite.modulate = CHARACTER_COLOR
	
	# Set any character-specific stats if needed
	# walk_speed = 200.0  # Default speed
	# run_speed = 350.0   # Default speed
	
	print("Blue character initialized for player: ", player_name)

# Override any character-specific behavior if needed
func get_character_index() -> int:
	return CHARACTER_INDEX

func get_character_name() -> String:
	return CHARACTER_NAME

func get_character_color() -> Color:
	return CHARACTER_COLOR
