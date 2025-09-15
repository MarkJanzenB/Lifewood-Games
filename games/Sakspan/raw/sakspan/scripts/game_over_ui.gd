# res://scripts/game_over_ui.gd

class_name GameOverUI
extends CanvasLayer

@onready var result_label: Label = $CenterContainer/VBoxContainer/ResultLabel
@onready var player_sprite: TextureRect = $CenterContainer/VBoxContainer/PlayerSprite
@onready var player_info_label: Label = $CenterContainer/VBoxContainer/PlayerInfoLabel
@onready var winning_team_label: Label = $CenterContainer/VBoxContainer/WinningTeamLabel

func show_screen(local_player: PlayerCharacter, did_i_win: bool, winning_text: String):
	# Set the result text and color
	if did_i_win:
		result_label.text = "VICTORY"
		result_label.modulate = Color.GREEN
	else:
		result_label.text = "DEFEAT"
		result_label.modulate = Color.RED
		
	# Set the player's info
	player_sprite.texture = local_player.animated_sprite.sprite_frames.get_frame_texture("idle", 0)
	player_info_label.text = local_player.player_name + " (" + PlayerCharacter.PlayerRole.keys()[local_player.role] + ")"
	winning_team_label.text = winning_text
	
	# Show the screen
	self.visible = true
