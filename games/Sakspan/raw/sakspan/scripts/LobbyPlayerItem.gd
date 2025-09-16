# LobbyPlayerItem.gd
extends PanelContainer

@onready var character_icon: TextureRect = $HBoxContainer/CharacterIcon
@onready var player_name_label: Label = $HBoxContainer/PlayerNameLabel
@onready var ready_status_label: Label = $HBoxContainer/ReadyStatusLabel

# This function is called from the main lobby script to update what this item shows
func update_display(player_data: Dictionary, char_texture: Texture2D = null) -> void:
	var player_name: String = str(player_data.get("name", "Unknown Player"))
	var is_host: bool = bool(player_data.get("is_host", false))
	var is_ready: bool = bool(player_data.get("ready", false))

	player_name_label.text = player_name + (is_host ? " (Host)" : "")
	character_icon.texture = char_texture

	if is_ready:
		ready_status_label.text = "Ready!"
		ready_status_label.modulate = Color(0.6, 1.0, 0.6, 1.0)
	else:
		ready_status_label.text = "Choosing..."
		ready_status_label.modulate = Color(1, 1, 1, 1)
