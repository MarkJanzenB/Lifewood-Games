# res://scripts/game_over_ui.gd

class_name GameOverUI
extends CanvasLayer

@onready var result_label: Label = $CenterContainer/VBoxContainer/ResultLabel
@onready var player_sprite: TextureRect = $CenterContainer/VBoxContainer/PlayerSprite
@onready var player_info_label: Label = $CenterContainer/VBoxContainer/PlayerInfoLabel
@onready var winning_team_label: Label = $CenterContainer/VBoxContainer/WinningTeamLabel
@onready var return_to_lobby_button: Button = $CenterContainer/VBoxContainer/ButtonContainer/ReturnToLobbyButton

var button_pressed: bool = false  # Prevent multiple rapid presses

func _ready():
	# Connect button signals
	if return_to_lobby_button:
		return_to_lobby_button.pressed.connect(_on_return_to_lobby_pressed)

func show_game_over(did_i_win: bool, winning_text: String, local_player: PlayerCharacter = null):
	"""Show the game over screen with proper styling"""
	
	# Set the main title
	result_label.text = "GAME OVER"
	result_label.add_theme_font_size_override("font_size", 48)
	result_label.add_theme_color_override("font_color", Color.WHITE)
	
	# Set win/lose status with emojis and colors
	if did_i_win:
		player_info_label.text = "🎉 YOU WIN! 🎉"
		player_info_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		player_info_label.text = "💀 YOU LOSE 💀"  
		player_info_label.add_theme_color_override("font_color", Color.RED)
	
	player_info_label.add_theme_font_size_override("font_size", 24)
	
	# Set the winning team message
	winning_team_label.text = winning_text
	winning_team_label.add_theme_font_size_override("font_size", 16)
	winning_team_label.add_theme_color_override("font_color", Color.WHITE)
	
	# Set player sprite if available
	if local_player and local_player.animated_sprite and local_player.animated_sprite.sprite_frames:
		player_sprite.texture = local_player.animated_sprite.sprite_frames.get_frame_texture("idle", 0)
		player_sprite.custom_minimum_size = Vector2(64, 64)
	else:
		player_sprite.visible = false
	
	# Show the screen with animation
	self.visible = true
	_animate_entrance()

func _animate_entrance():
	"""Animate the game over screen entrance"""
	var center_container = $CenterContainer
	center_container.modulate.a = 0.0
	center_container.scale = Vector2(0.5, 0.5)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(center_container, "modulate:a", 1.0, 0.5)
	tween.tween_property(center_container, "scale", Vector2(1.0, 1.0), 0.5)

func _on_return_to_lobby_pressed():
	"""Handle return to lobby button press with debounce"""
	if button_pressed:
		print("[GameOverUI] Button already pressed, ignoring duplicate")
		return
	
	button_pressed = true
	return_to_lobby_button.disabled = true
	return_to_lobby_button.text = "Returning..."
	
	print("[GameOverUI] Return to Multiplayer Menu pressed")
	if GameManager:
		GameManager.reset_to_multiplayer_menu()
	
	# Re-enable after delay to prevent spam
	if get_tree():
		await get_tree().create_timer(2.0).timeout
		if is_instance_valid(return_to_lobby_button):
			return_to_lobby_button.disabled = false
			return_to_lobby_button.text = "Return to Multiplayer Menu"
			button_pressed = false


# Legacy method for compatibility
func show_screen(local_player: PlayerCharacter, did_i_win: bool, winning_text: String):
	show_game_over(did_i_win, winning_text, local_player)
