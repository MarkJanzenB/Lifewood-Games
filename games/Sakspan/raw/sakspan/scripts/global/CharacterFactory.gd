# res://scripts/global/CharacterFactory.gd
extends Node
class_name CharacterFactory

# Character scene paths - fallback to base player scene if character scenes don't exist
const BASE_PLAYER_SCENE = preload("res://scenes/player.tscn")

# Try to load character scenes, fallback to base player scene
static func _get_character_scenes() -> Dictionary:
	var scenes = {}
	var scene_paths = [
		"res://scenes/characters/PinkCharacter.tscn",
		"res://scenes/characters/RedCharacter.tscn", 
		"res://scenes/characters/BlueCharacter.tscn",
		"res://scenes/characters/GreenCharacter.tscn",
		"res://scenes/characters/YellowCharacter.tscn"
	]
	
	for i in range(scene_paths.size()):
		var scene_path = scene_paths[i]
		if ResourceLoader.exists(scene_path):
			scenes[i] = load(scene_path)
		else:
			print("[CharacterFactory] Character scene not found: ", scene_path, " - using base player scene")
			scenes[i] = BASE_PLAYER_SCENE
	
	return scenes

const CHARACTER_NAMES = ["Pink", "Red", "Blue", "Green", "Yellow"]
const CHARACTER_COLORS = [Color.MAGENTA, Color.RED, Color.BLUE, Color.GREEN, Color.YELLOW]

# Create a character instance based on the selected character index
static func create_character(character_index: int) -> PlayerCharacter:
	var character_scenes = _get_character_scenes()
	
	if character_index < 0 or character_index >= character_scenes.size():
		print("[CharacterFactory] Invalid character index: ", character_index, ", using default")
		character_index = 0
	
	var character_scene = character_scenes[character_index]
	if not character_scene:
		print("[CharacterFactory] Character scene not found for index: ", character_index)
		return null
	
	var character_instance = character_scene.instantiate() as PlayerCharacter
	if not character_instance:
		print("[CharacterFactory] Failed to instantiate character for index: ", character_index)
		return null
	
	# Apply character color if using base player scene
	if character_scene == BASE_PLAYER_SCENE:
		_apply_character_appearance(character_instance, character_index)
	
	print("[CharacterFactory] Created character: ", CHARACTER_NAMES[character_index])
	return character_instance

# Apply character appearance to base player scene
static func _apply_character_appearance(player: PlayerCharacter, character_index: int):
	if character_index >= 0 and character_index < CHARACTER_COLORS.size():
		var color = CHARACTER_COLORS[character_index]
		if player.has_node("AnimatedSprite2D"):
			var sprite = player.get_node("AnimatedSprite2D")
			sprite.modulate = color
		print("[CharacterFactory] Applied ", CHARACTER_NAMES[character_index], " appearance to base player")

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
