# File: CharacterButton.gd
# This script goes on your "CharacterButton.tscn" root node.
class_name CharacterButton
extends TextureButton

# Signal to notify the lobby when this character is selected.
# It will send its own index (e.g., 0 for pink, 1 for red) as a parameter.
signal character_selected(character_index)

# This variable will hold the index of this character.
var character_index: int = -1

# A color to dim the button when it's not the selected one.
const DIM_COLOR = Color(0.6, 0.6, 0.6, 1.0)
# The normal, bright color.
const NORMAL_COLOR = Color(1.0, 1.0, 1.0, 1.0)


# This function is called by the lobby script to give this button its image and index.
func set_character(texture: Texture, index: int):
	self.texture_normal = texture
	self.character_index = index

# This function is called by the lobby script to visually show if this button is the active choice.
func set_selected(is_selected: bool):
	if is_selected:
		self.modulate = NORMAL_COLOR # Make it bright
	else:
		self.modulate = DIM_COLOR # Make it dim

# The _ready function runs when the button is created.
func _ready():
	# When this button is pressed, call the local "_on_pressed" function.
	self.pressed.connect(_on_pressed)
	# Start off dimmed.
	set_selected(false)

# This function runs only when this specific button is clicked.
func _on_pressed():
	# When clicked, emit the signal and include our unique index.
	emit_signal("character_selected", character_index)
