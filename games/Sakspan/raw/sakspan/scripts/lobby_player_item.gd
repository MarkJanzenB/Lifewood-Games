# res://scenes/UI/Lobby_Wait_Room/LobbyPlayerItem.gd
extends PanelContainer

@onready var player_name_label: Label = $HBoxContainer/PlayerNameLabel
@onready var ready_status_label: Label = $HBoxContainer/ReadyStatusLabel

func set_player_info(player_name: String, is_ready: bool, player_id: int) -> void:
	if player_name_label:
		player_name_label.text = "%s  (ID: %d)" % [player_name, player_id]
	if ready_status_label:
		ready_status_label.text = "READY" if is_ready else "WAITING"
		ready_status_label.modulate = Color(0.6, 1.0, 0.6, 1.0) if is_ready else Color(1, 1, 1, 1)
