# res://scripts/game_ui.gd

class_name GameUI
extends CanvasLayer

# --- NODE REFERENCES ---
# Match GameUI.tscn layout precisely
@onready var countdown_label: Label = get_node_or_null("MarginContainer/CountdownLabel")
@onready var ammo_label: Label = get_node_or_null("MarginContainer/VBoxContainer/HBoxContainer2/AmmoLabel")
@onready var hiders_label: Label = get_node_or_null("MarginContainer/VBoxContainer/HidersLabel")
@onready var kill_feed_label: Label = get_node_or_null("MarginContainer/VBoxContainer/HBoxContainer/KillFeedLabel")
@onready var status_label: Label = get_node_or_null("MarginContainer/VBoxContainer/HBoxContainer/StatusLabel")
@onready var spotted_label: Label = get_node_or_null("MarginContainer/SpottedLabel")
@onready var spotted_timer: Timer = Timer.new()

var local_player_role: PlayerCharacter.PlayerRole = PlayerCharacter.PlayerRole.HIDER  # Default to HIDER

# Method to set the local player's role
func set_local_player_role(role: PlayerCharacter.PlayerRole) -> void:
	local_player_role = role
	print("[GameUI] Local player role set to: ", role)

func _ready():
	# Register this UI instance with the global GameManager
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("register_game_ui"):
		game_manager.register_game_ui(self)
		print("[GameUI] Successfully registered with GameManager")
	else:
		print("[GameUI] ❌ Failed to register with GameManager")
		
	add_child(spotted_timer)
	spotted_timer.wait_time = 2.0
	spotted_timer.one_shot = true
	spotted_timer.timeout.connect(func(): if spotted_label: spotted_label.visible = false)
	
	if kill_feed_label: 
		kill_feed_label.text = ""
	else: 
		push_warning("[GameUI] KillFeedLabel not found")
	if status_label: 
		status_label.text = ""
	else: 
		push_warning("[GameUI] StatusLabel not found")

func initialize(player: PlayerCharacter):
	local_player_role = player.role
	configure_for_role(local_player_role)

func configure_for_role(role: PlayerCharacter.PlayerRole):
	"""Configure UI elements based on player role - called once"""
	local_player_role = role
	print("[GameUI] Configuring UI for role: ", PlayerCharacter.PlayerRole.keys()[role])
	
	if role == PlayerCharacter.PlayerRole.SEEKER:
		if spotted_label:
			spotted_label.visible = false
		if ammo_label:
			ammo_label.visible = true
	elif role == PlayerCharacter.PlayerRole.HIDER:
		if ammo_label:
			ammo_label.visible = false
		if spotted_label:
			spotted_label.visible = false  # Will be shown when spotted

# --- PUBLIC UI FUNCTIONS ---

func update_ammo(count: int):
	if local_player_role == PlayerCharacter.PlayerRole.SEEKER:
		if ammo_label:
			ammo_label.text = "Ammo: " + str(count)

func update_hiders_left(count: int):
	if hiders_label:
		hiders_label.text = "Hiders Left: " + str(count)

func show_kill_feed(message: String):
	if kill_feed_label:
		fade_out_label(kill_feed_label, message)

func show_spotted(is_visible: bool):
	if local_player_role == PlayerCharacter.PlayerRole.HIDER:
		if spotted_label:
			if is_visible:
				_show_spotted_alert_with_animation()
			else:
				_hide_spotted_alert_with_animation()

func _show_spotted_alert_with_animation():
	"""Show spotted alert with dramatic animation"""
	if not spotted_label:
		return
		
	print("[GameUI] 🚨 Showing SPOTTED alert with animation")
	
	# Configure the spotted label
	spotted_label.text = "⚠️ SPOTTED! ⚠️"
	spotted_label.visible = true
	spotted_label.modulate = Color.RED
	spotted_label.add_theme_font_size_override("font_size", 36)
	spotted_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	spotted_label.add_theme_constant_override("shadow_offset_x", 3)
	spotted_label.add_theme_constant_override("shadow_offset_y", 3)
	
	# Start with invisible and small
	spotted_label.modulate.a = 0.0
	spotted_label.scale = Vector2(0.5, 0.5)
	
	# Create dramatic entrance animation
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Fade in and scale up
	tween.tween_property(spotted_label, "modulate:a", 1.0, 0.3)
	tween.tween_property(spotted_label, "scale", Vector2(1.3, 1.3), 0.3)
	tween.tween_property(spotted_label, "scale", Vector2(1.0, 1.0), 0.2).set_delay(0.3)
	
	# Add pulsing effect
	tween.tween_callback(_start_spotted_pulse).set_delay(0.5)
	
	# Auto-hide after some time
	spotted_timer.start()

func _hide_spotted_alert_with_animation():
	"""Hide spotted alert with fade out animation"""
	if not spotted_label or not spotted_label.visible:
		return
		
	print("[GameUI] ❌ Hiding SPOTTED alert")
	
	# Stop timer
	spotted_timer.stop()
	
	# Create fade out animation
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(spotted_label, "modulate:a", 0.0, 0.5)
	tween.tween_property(spotted_label, "scale", Vector2(0.8, 0.8), 0.5)
	tween.tween_callback(func(): spotted_label.visible = false)

func _start_spotted_pulse():
	"""Start pulsing animation for spotted alert"""
	if not spotted_label or not spotted_label.visible:
		return
		
	# Create infinite pulsing
	var pulse_tween = create_tween()
	pulse_tween.set_loops()
	pulse_tween.tween_property(spotted_label, "modulate", Color.YELLOW, 0.5)
	pulse_tween.tween_property(spotted_label, "modulate", Color.RED, 0.5)

func update_countdown(text: String, is_visible: bool):
	"""Enhanced dramatic countdown display"""
	if countdown_label:
		countdown_label.text = text
		countdown_label.visible = is_visible
		
		# Make countdown more dramatic
		if text.is_valid_int():
			var count = text.to_int()
			if count <= 3 and count > 0:
				# Critical countdown - make it red and larger
				countdown_label.modulate = Color.RED
				countdown_label.scale = Vector2(1.5, 1.5)
				# Add pulsing effect
				var tween = create_tween()
				tween.tween_property(countdown_label, "scale", Vector2(1.8, 1.8), 0.3)
				tween.tween_property(countdown_label, "scale", Vector2(1.5, 1.5), 0.3)
			elif count <= 10:
				# Warning countdown - make it orange
				countdown_label.modulate = Color.ORANGE
				countdown_label.scale = Vector2(1.2, 1.2)
			else:
				# Normal countdown
				countdown_label.modulate = Color.WHITE
				countdown_label.scale = Vector2(1.0, 1.0)
		elif text == "GO!":
			# Dramatic GO! message
			countdown_label.modulate = Color.GREEN
			countdown_label.scale = Vector2(2.0, 2.0)
			var tween = create_tween()
			tween.tween_property(countdown_label, "scale", Vector2(2.5, 2.5), 0.2)
			tween.tween_property(countdown_label, "scale", Vector2(2.0, 2.0), 0.2)
			tween.tween_callback(func(): countdown_label.visible = false).set_delay(1.0)
		else:
			# Reset to normal
			countdown_label.modulate = Color.WHITE
			countdown_label.scale = Vector2(1.0, 1.0)
		
		print("[GameUI] 📡 CLIENT RECEIVED: Countdown updated to '", text, "' (Peer: ", multiplayer.get_unique_id(), ")")

func update_status(text: String, is_visible: bool):
	if status_label:
		if is_visible:
			fade_out_label(status_label, text)
		else:
			status_label.visible = false

func show_dramatic_announcement(message: String):
	"""Show a dramatic announcement with enhanced visual effects"""
	if status_label:
		status_label.text = message
		status_label.visible = true
		status_label.modulate = Color.YELLOW
		status_label.scale = Vector2(1.5, 1.5)
		
		# Create dramatic entrance effect
		var tween = create_tween()
		tween.tween_property(status_label, "scale", Vector2(1.8, 1.8), 0.3)
		tween.tween_property(status_label, "scale", Vector2(1.5, 1.5), 0.3)
		tween.tween_property(status_label, "modulate", Color.WHITE, 1.0)
		tween.tween_callback(func(): fade_out_label(status_label, message)).set_delay(2.0)

# Called by GameManager when the match ends - handles both signatures
func show_game_over(param1, param2: String) -> void:
	print("[GameUI] 🎬 show_game_over called - param1: ", param1, " param2: ", param2)
	
	var did_i_win = false
	var message = param2
	
	# Handle different parameter types
	if typeof(param1) == TYPE_BOOL:
		# Called with (bool, String) - direct win/lose
		did_i_win = param1
	elif typeof(param1) == TYPE_STRING:
		# Called with (String, String) - team name and message
		var winning_team = param1
		# Determine if local player won based on their role
		if local_player_role == PlayerCharacter.PlayerRole.SEEKER and winning_team == "Seekers":
			did_i_win = true
		elif local_player_role == PlayerCharacter.PlayerRole.HIDER and winning_team == "Hiders":
			did_i_win = true
	
	_create_game_over_overlay(did_i_win, message)

func _create_game_over_overlay(did_i_win: bool, message: String) -> void:
	"""Create a full-screen game over overlay"""
	print("[GameUI] 🎨 Creating game over overlay")
	
	# Hide existing UI elements
	if countdown_label: countdown_label.visible = false
	if status_label: status_label.visible = false
	if ammo_label: ammo_label.visible = false
	if hiders_label: hiders_label.visible = false
	if kill_feed_label: kill_feed_label.visible = false
	if spotted_label: spotted_label.visible = false
	
	# Create full-screen overlay
	var overlay = ColorRect.new()
	overlay.name = "GameOverOverlay"
	overlay.color = Color(0, 0, 0, 0.8)  # Semi-transparent black
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 1000  # Ensure it's on top
	add_child(overlay)
	
	# Create main container with proper centering
	var main_container = VBoxContainer.new()
	main_container.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	main_container.add_theme_constant_override("separation", 30)
	main_container.custom_minimum_size = Vector2(400, 300)  # Set minimum size
	overlay.add_child(main_container)
	
	# Create title label
	var title_label = Label.new()
	title_label.text = "GAME OVER"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 48)
	title_label.add_theme_color_override("font_color", Color.WHITE)
	main_container.add_child(title_label)
	
	# Create result label
	var result_label = Label.new()
	if did_i_win:
		result_label.text = "🎉 YOU WIN! 🎉"
		result_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		result_label.text = "💀 YOU LOSE 💀"
		result_label.add_theme_color_override("font_color", Color.RED)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 36)
	main_container.add_child(result_label)
	
	# Create message label
	var message_label = Label.new()
	message_label.text = message
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 24)
	message_label.add_theme_color_override("font_color", Color.WHITE)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.custom_minimum_size = Vector2(400, 0)
	main_container.add_child(message_label)
	
	# Create button container
	var button_container = HBoxContainer.new()
	button_container.add_theme_constant_override("separation", 20)
	main_container.add_child(button_container)
	
	# Create "Return to Lobby" button
	var lobby_button = Button.new()
	lobby_button.text = "Return to Lobby"
	lobby_button.custom_minimum_size = Vector2(150, 50)
	lobby_button.pressed.connect(_on_return_to_lobby_pressed)
	button_container.add_child(lobby_button)
	
	# Create "Quit Game" button
	var quit_button = Button.new()
	quit_button.text = "Quit Game"
	quit_button.custom_minimum_size = Vector2(150, 50)
	quit_button.pressed.connect(_on_quit_game_pressed)
	button_container.add_child(quit_button)
	
	# Add entrance animation
	var tween = create_tween()
	overlay.modulate.a = 0.0
	main_container.scale = Vector2(0.5, 0.5)
	tween.parallel().tween_property(overlay, "modulate:a", 1.0, 0.5)
	tween.parallel().tween_property(main_container, "scale", Vector2(1.0, 1.0), 0.5)
	tween.tween_callback(func(): print("[GameUI] ✅ Game Over overlay animation complete"))
	
	print("[GameUI] ✅ Game Over overlay created successfully")

func _on_return_to_lobby_pressed() -> void:
	"""Handle return to lobby button press"""
	print("[GameUI] 🏠 Return to Lobby pressed")
	# Let GameManager handle the transition
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("return_to_lobby"):
		game_manager.return_to_lobby()
	else:
		# Fallback: transition directly
		get_tree().change_scene_to_file("res://scenes/multiplayer_menu.tscn")

func _on_quit_game_pressed() -> void:
	"""Handle quit game button press"""
	print("[GameUI] 🚪 Quit Game pressed")
	get_tree().quit()

# --- REUSABLE FADE FUNCTION ---
func fade_out_label(label_node: Label, text: String):
	if label_node:
		label_node.text = text
		label_node.modulate.a = 1.0
		var tween = create_tween()
		tween.tween_interval(3.0)
		tween.tween_property(label_node, "modulate:a", 0, 1.0)

func _exit_tree():
	# Deregister when this HUD is removed to prevent stale references
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("unregister_game_ui"):
		game_manager.unregister_game_ui(self)
