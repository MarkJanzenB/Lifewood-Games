# res://scripts/global/CharacterFactory.gd
extends Node
class_name CharacterFactory

const BASE_PLAYER_SCENE = preload("res://scenes/player.tscn")

const CHARACTER_NAMES = ["Pink", "Red", "Blue", "Green", "Yellow"]
const CHARACTER_COLORS = [Color.MAGENTA, Color.RED, Color.BLUE, Color.GREEN, Color.YELLOW]

# Create a character instance based on the selected character index
static func create_character(character_index: int) -> PlayerCharacter:
	if character_index < 0 or character_index >= CHARACTER_NAMES.size():
		character_index = 0
	
	print("[CharacterFactory] Creating character with index: ", character_index, " (", CHARACTER_NAMES[character_index], ")")
	
	# Instantiate base player scene
	var character_instance = BASE_PLAYER_SCENE.instantiate() as PlayerCharacter
	if not character_instance:
		print("[CharacterFactory] ERROR: Failed to instantiate base player scene")
		return null
	
	# Set the character index - appearance will be applied in setup_multiplayer_player
	character_instance.character_index = character_index
	
	print("[CharacterFactory] Created ", CHARACTER_NAMES[character_index], " character successfully")
	return character_instance

# Apply character appearance to base player scene
static func _apply_character_appearance(player: PlayerCharacter, character_index: int):
	if character_index < 0 or character_index >= CHARACTER_COLORS.size():
		print("[CharacterFactory] Invalid character index: ", character_index)
		return
	
	var color = CHARACTER_COLORS[character_index]
	var character_name = CHARACTER_NAMES[character_index]
	
	print("[CharacterFactory] Applying ", character_name, " appearance with color: ", color)
	
	# Try to find the animated sprite node
	var sprite_node = null
	if player.has_node("AnimatedSprite2D"):
		sprite_node = player.get_node("AnimatedSprite2D")
		print("[CharacterFactory] Found AnimatedSprite2D node")
	elif player.get("animated_sprite"):
		sprite_node = player.animated_sprite
		print("[CharacterFactory] Found animated_sprite property")
	else:
		print("[CharacterFactory] ERROR: No animated sprite found on player!")
		print("[CharacterFactory] Player children: ", player.get_children())
		return
	
	if sprite_node:
		sprite_node.modulate = color
		print("[CharacterFactory] Successfully applied ", character_name, " color: ", color)
		print("[CharacterFactory] Sprite modulate is now: ", sprite_node.modulate)
	
	# Ensure character index is set
	player.character_index = character_index
	print("[CharacterFactory] Character setup complete for ", character_name)

# Get character info without instantiating
static func get_character_name(character_index: int) -> String:
	if character_index >= 0 and character_index < CHARACTER_NAMES.size():
		return CHARACTER_NAMES[character_index]
	return "Unknown"

static func get_character_color(character_index: int) -> Color:
	if character_index >= 0 and character_index < CHARACTER_COLORS.size():
		return CHARACTER_COLORS[character_index]
	return Color.WHITE

static func get_character_count() -> int:
	return CHARACTER_NAMES.size()

# Validate if a character index is valid
static func is_valid_character_index(index: int) -> bool:
	return index >= 0 and index < CHARACTER_NAMES.size()

# Get all available character indices
static func get_available_character_indices() -> Array[int]:
	var indices: Array[int] = []
	for i in range(CHARACTER_NAMES.size()):
		indices.append(i)
	return indices
