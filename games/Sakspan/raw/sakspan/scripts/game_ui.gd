# res://scripts/game_ui.gd

class_name GameUI
extends CanvasLayer

# --- NODE REFERENCES ---
# Modern GameUI layout references
@onready var countdown_label: Label = get_node_or_null("TopBar/TopBarContent/CenterSection/CountdownLabel")
@onready var ammo_label: Label = get_node_or_null("TopBar/TopBarContent/RightSection/AmmoContainer/AmmoLabel")
@onready var ammo_icon: Label = get_node_or_null("TopBar/TopBarContent/RightSection/AmmoContainer/AmmoIcon")
@onready var hiders_label: Label = get_node_or_null("TopBar/TopBarContent/LeftSection/HidersLabel")
@onready var kill_feed_label: RichTextLabel = get_node_or_null("KillFeedContainer/KillFeedLabel")
@onready var status_label: Label = get_node_or_null("TopBar/TopBarContent/LeftSection/StatusLabel")
@onready var spotted_indicator: Control = get_node_or_null("SpottedIndicator")
@onready var spotted_label: Label = get_node_or_null("SpottedIndicator/SpottedLabel")
@onready var ghost_overlay: Control = get_node_or_null("GhostOverlay")
@onready var ghost_label: Label = get_node_or_null("GhostOverlay/GhostLabel")
@onready var spotted_timer: Timer = Timer.new()

# Animation tweens
var spotted_tween: Tween
var kill_feed_tween: Tween
var ghost_transition_tween: Tween

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
		
	# Initialize timers and UI elements
	add_child(spotted_timer)
	spotted_timer.wait_time = 3.0
	spotted_timer.one_shot = true
	spotted_timer.timeout.connect(_hide_spotted_alert_with_animation)
	
	# Initialize UI elements
	_initialize_modern_ui()
	
	# Hide dynamic elements initially
	if spotted_indicator:
		spotted_indicator.visible = false
		spotted_indicator.modulate.a = 0.0
	if ghost_overlay:
		ghost_overlay.visible = false
		ghost_overlay.modulate.a = 0.0

func _initialize_modern_ui():
	"""Initialize the modern UI with proper styling and animations"""
	if kill_feed_label: 
		kill_feed_label.text = "[center][color=yellow]Kill Feed[/color][/center]"
	else: 
		push_warning("[GameUI] KillFeedLabel not found")
		
	if status_label: 
		status_label.text = "Preparing..."
	else: 
		push_warning("[GameUI] StatusLabel not found")
		
	if ammo_label:
		ammo_label.text = "Cursed Stones: 0"
	if hiders_label:
		hiders_label.text = "Hiders Left: 0"
		
	# Add subtle pulsing animation to ammo icon
	if ammo_icon:
		_start_ammo_icon_animation()

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
			ammo_label.text = "Cursed Stones: " + str(count)
			_animate_ammo_update(count)

func update_hiders_left(count: int):
	if hiders_label:
		hiders_label.text = "Hiders Left: " + str(count)

func show_kill_feed(message: String):
	if kill_feed_label:
		_show_modern_kill_feed(message)

func _show_modern_kill_feed(message: String):
	"""Show kill feed with modern styling and animation"""
	if not kill_feed_label:
		return
		
	print("[GameUI] 💀 Showing modern kill feed: ", message)
	
	# Format the message with BBCode
	var formatted_message = "[center][color=yellow]Kill Feed[/color][/center]\n[center][color=red]💀 " + message + " 💀[/color][/center]"
	
	# Stop any existing animation
	if kill_feed_tween:
		kill_feed_tween.kill()
	
	# Set the message and prepare animation
	kill_feed_label.text = formatted_message
	kill_feed_label.modulate.a = 0.0
	kill_feed_label.scale = Vector2(0.8, 0.8)
	
	# Create entrance animation
	kill_feed_tween = create_tween()
	kill_feed_tween.set_parallel(true)
	
	# Fade in and scale up
	kill_feed_tween.tween_property(kill_feed_label, "modulate:a", 1.0, 0.3)
	kill_feed_tween.tween_property(kill_feed_label, "scale", Vector2(1.1, 1.1), 0.3).set_trans(Tween.TRANS_BACK)
	kill_feed_tween.tween_property(kill_feed_label, "scale", Vector2(1.0, 1.0), 0.2).set_delay(0.3)
	
	# Hold for a moment, then fade out
	kill_feed_tween.tween_property(kill_feed_label, "modulate:a", 0.0, 0.5).set_delay(3.0)
	kill_feed_tween.tween_property(kill_feed_label, "scale", Vector2(0.8, 0.8), 0.5).set_delay(3.0)
	
	# Reset to default after animation
	kill_feed_tween.tween_callback(func(): 
		kill_feed_label.text = "[center][color=yellow]Kill Feed[/color][/center]"
		kill_feed_label.modulate.a = 1.0
		kill_feed_label.scale = Vector2(1.0, 1.0)
	).set_delay(3.5)

func show_spotted(is_visible: bool):
	print("[GameUI] 🎯 show_spotted called - is_visible: ", is_visible, " local_role: ", local_player_role, " spotted_indicator exists: ", spotted_indicator != null)
	
	if local_player_role == PlayerCharacter.PlayerRole.HIDER:
		if spotted_indicator:
			if is_visible:
				_show_spotted_alert_with_animation()
			else:
				_hide_spotted_alert_with_animation()
		else:
			print("[GameUI] ❌ spotted_indicator is null - cannot show spotted alert")
	else:
		print("[GameUI] ⚠️ Not showing spotted alert - player is not a HIDER (role: ", local_player_role, ")")

func _show_spotted_alert_with_animation():
	"""Show modern spotted alert with dramatic animation"""
	if not spotted_indicator or not spotted_label:
		return
		
	print("[GameUI] 🚨 Showing MODERN SPOTTED alert with animation")
	
	# Stop any existing animation
	if spotted_tween:
		spotted_tween.kill()
	
	# Make indicator visible and reset properties
	spotted_indicator.visible = true
	spotted_indicator.modulate.a = 0.0
	spotted_indicator.scale = Vector2(0.3, 0.3)
	spotted_indicator.rotation = 0.0
	
	# Create dramatic entrance animation
	spotted_tween = create_tween()
	spotted_tween.set_parallel(true)
	
	# Fade in and scale up
	spotted_tween.tween_property(spotted_indicator, "modulate:a", 1.0, 0.3)
	spotted_tween.tween_property(spotted_indicator, "scale", Vector2(1.2, 1.2), 0.3).set_trans(Tween.TRANS_BACK)
	
	# Slight rotation shake
	spotted_tween.tween_property(spotted_indicator, "rotation", deg_to_rad(-5), 0.1)
	spotted_tween.tween_property(spotted_indicator, "rotation", deg_to_rad(5), 0.1).set_delay(0.1)
	spotted_tween.tween_property(spotted_indicator, "rotation", 0.0, 0.1).set_delay(0.2)
	
	# Scale back to normal
	spotted_tween.tween_property(spotted_indicator, "scale", Vector2(1.0, 1.0), 0.2).set_delay(0.3)
	
	# Pulsing effect
	var pulse_tween = create_tween()
	pulse_tween.set_loops()
	pulse_tween.tween_property(spotted_indicator, "scale", Vector2(1.05, 1.05), 0.5)
	pulse_tween.tween_property(spotted_indicator, "scale", Vector2(1.0, 1.0), 0.5)
	
	# Auto-hide after timer
	spotted_timer.start()

func _hide_spotted_alert_with_animation():
	"""Hide spotted alert with smooth animation"""
	if not spotted_indicator:
		return
		
	print("[GameUI] 🔇 Hiding SPOTTED alert with animation")
	
	# Stop any existing animation
	if spotted_tween:
		spotted_tween.kill()
	
	# Create exit animation
	spotted_tween = create_tween()
	spotted_tween.set_parallel(true)
	
	# Fade out and scale down
	spotted_tween.tween_property(spotted_indicator, "modulate:a", 0.0, 0.5)
	spotted_tween.tween_property(spotted_indicator, "scale", Vector2(0.3, 0.3), 0.5).set_trans(Tween.TRANS_BACK)
	
	# Hide when animation completes
	spotted_tween.tween_callback(func(): spotted_indicator.visible = false).set_delay(0.5)

func _start_ammo_icon_animation():
	"""Start subtle pulsing animation for ammo icon"""
	if not ammo_icon:
		return
	
	var ammo_tween = create_tween()
	ammo_tween.set_loops()
	ammo_tween.tween_property(ammo_icon, "modulate:a", 0.7, 1.0)
	ammo_tween.tween_property(ammo_icon, "modulate:a", 1.0, 1.0)

func _animate_ammo_update(count: int):
	"""Animate ammo count changes"""
	if not ammo_label or not ammo_icon:
		return
	
	# Create a brief highlight animation
	var highlight_tween = create_tween()
	highlight_tween.set_parallel(true)
	
	# Scale pulse
	highlight_tween.tween_property(ammo_label, "scale", Vector2(1.2, 1.2), 0.1)
	highlight_tween.tween_property(ammo_label, "scale", Vector2(1.0, 1.0), 0.2).set_delay(0.1)
	
	# Color flash based on ammo count
	var flash_color = Color.GREEN if count > 0 else Color.RED
	highlight_tween.tween_property(ammo_label, "modulate", flash_color, 0.1)
	highlight_tween.tween_property(ammo_label, "modulate", Color(1, 0.8, 0.2, 1), 0.2).set_delay(0.1)
	
	# Icon animation
	highlight_tween.tween_property(ammo_icon, "scale", Vector2(1.3, 1.3), 0.1)
	highlight_tween.tween_property(ammo_icon, "scale", Vector2(1.0, 1.0), 0.2).set_delay(0.1)

func show_ghost_overlay():
	"""Show ghost overlay with smooth transition"""
	if not ghost_overlay:
		return
		
	print("[GameUI] 👻 Showing ghost overlay")
	
	ghost_overlay.visible = true
	ghost_overlay.modulate.a = 0.0
	
	if ghost_transition_tween:
		ghost_transition_tween.kill()
	
	ghost_transition_tween = create_tween()
	ghost_transition_tween.tween_property(ghost_overlay, "modulate:a", 1.0, 1.0).set_trans(Tween.TRANS_SINE)

func hide_ghost_overlay():
	"""Hide ghost overlay with smooth transition"""
	if not ghost_overlay:
		return
		
	print("[GameUI] 👻 Hiding ghost overlay")
	
	if ghost_transition_tween:
		ghost_transition_tween.kill()
	
	ghost_transition_tween = create_tween()
	ghost_transition_tween.tween_property(ghost_overlay, "modulate:a", 0.0, 1.0).set_trans(Tween.TRANS_SINE)
	ghost_transition_tween.tween_callback(func(): ghost_overlay.visible = false).set_delay(1.0)

func update_countdown(time_left, is_visible: bool = true):
	"""Update countdown with dramatic animation - supports both int and string"""
	if not countdown_label:
		return
	
	# Handle both int and string inputs
	var text: String
	if time_left is int:
		text = str(time_left)
	else:
		text = str(time_left)
	
	countdown_label.text = text
	countdown_label.visible = is_visible
	
	# Create dramatic countdown animation
	var countdown_tween = create_tween()
	countdown_tween.set_parallel(true)
	
	# Scale animation
	countdown_tween.tween_property(countdown_label, "scale", Vector2(1.5, 1.5), 0.1)
	countdown_tween.tween_property(countdown_label, "scale", Vector2(1.0, 1.0), 0.4).set_delay(0.1)
	
	# Color animation based on urgency
	var urgency_color: Color
	if text.is_valid_int():
		var count = text.to_int()
		if count <= 3:
			urgency_color = Color.RED
		elif count <= 10:
			urgency_color = Color.YELLOW
		else:
			urgency_color = Color.WHITE
	elif text == "GO!":
		urgency_color = Color.GREEN
		countdown_tween.tween_property(countdown_label, "scale", Vector2(2.0, 2.0), 0.2)
		countdown_tween.tween_callback(func(): countdown_label.visible = false).set_delay(1.0)
	else:
		urgency_color = Color.WHITE
	
	countdown_tween.tween_property(countdown_label, "modulate", urgency_color, 0.1)
	countdown_tween.tween_property(countdown_label, "modulate", Color.WHITE, 0.4).set_delay(0.1)

func show_status_message(message: String):
	"""Show status message with animation"""
	if not status_label:
		return
	
	status_label.text = message
	
	# Brief highlight animation
	var status_tween = create_tween()
	status_tween.tween_property(status_label, "modulate", Color.CYAN, 0.2)
	status_tween.tween_property(status_label, "modulate", Color(0.9, 0.9, 1, 1), 0.3).set_delay(0.2)
	
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

# Duplicate update_countdown function removed

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
# REMOVED: Game over overlay functionality - now handled by dedicated GameOverUI scene
# GameUI no longer creates game over overlays to maintain clean separation of concerns

func _on_return_to_lobby_pressed() -> void:
	"""Handle return to lobby button press"""
	print("[GameUI] 🏠 Return to Lobby pressed")
	# Let GameManager handle the transition
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("reset_to_lobby"):
		game_manager.reset_to_lobby()
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
