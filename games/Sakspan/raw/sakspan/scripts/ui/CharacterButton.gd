# res://scripts/ui/CharacterButton.gd
extends Button
class_name LobbyCharacterButton

signal character_selected(index: int)

var character_index: int = -1
var character_texture: Texture2D
var is_selected: bool = false

@onready var character_icon: TextureRect = $CharacterIcon

func _ready():
	# Connect button press
	pressed.connect(_on_button_pressed)
	
	# Setup button appearance
	custom_minimum_size = Vector2(80, 80)

func set_character(texture: Texture2D, index: int):
	character_texture = texture
	character_index = index
	
	if character_icon:
		character_icon.texture = texture
	else:
		# If no TextureRect child, set as button icon
		icon = texture

func set_selected(selected: bool):
	is_selected = selected
	_update_appearance()

func _update_appearance():
	if is_selected:
		modulate = Color.YELLOW
	elif disabled:
		modulate = Color.GRAY
	else:
		modulate = Color.WHITE

func _on_button_pressed():
	if not disabled:
		character_selected.emit(character_index)

func _notification(what):
	if what == NOTIFICATION_THEME_CHANGED:
		_update_appearance()
