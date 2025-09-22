# res://scripts/dev/dev_game_ui.gd
# GameUI for dev_world.tscn - handles Kill Feed, Spotted alerts, and game status
extends Control

# Node references
@onready var kill_feed: VBoxContainer = $KillFeed
@onready var spotted_alert: Label = $SpottedAlert
@onready var game_status: Label = $GameStatus

# Kill feed management
var kill_feed_messages: Array[Label] = []
const MAX_KILL_FEED_MESSAGES = 5
const KILL_FEED_DURATION = 8.0

# Spotted alert management
var spotted_timer: Timer
var spotted_fade_tween: Tween

func _ready():
	print("[DevGameUI] GameUI initialized")
	
	# Setup spotted alert timer
	spotted_timer = Timer.new()
	spotted_timer.wait_time = 3.0
	spotted_timer.one_shot = true
	spotted_timer.timeout.connect(_hide_spotted_alert)
	add_child(spotted_timer)
	
	# Style the spotted alert
	_setup_spotted_alert_style()
	
	# Register with GameManager if it exists
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("register_game_ui"):
		game_manager.register_game_ui(self)
		print("[DevGameUI] Registered with GameManager")
	
	# Update initial game status
	update_game_status("Waiting for players...")

func _setup_spotted_alert_style():
	"""Setup the visual style for the spotted alert"""
	if not spotted_alert:
		return
	
	# Make it big and red
	spotted_alert.add_theme_font_size_override("font_size", 48)
	spotted_alert.add_theme_color_override("font_color", Color.RED)
	spotted_alert.add_theme_color_override("font_shadow_color", Color.BLACK)
	spotted_alert.add_theme_constant_override("shadow_offset_x", 3)
	spotted_alert.add_theme_constant_override("shadow_offset_y", 3)

# --- KILL FEED SYSTEM ---

func show_kill_feed(message: String):
	"""Add a message to the kill feed"""
	print("[DevGameUI] Kill Feed: ", message)
	
	if not kill_feed:
		return
	
	# Create new kill feed message
	var kill_message = Label.new()
	kill_message.text = message
	kill_message.add_theme_font_size_override("font_size", 14)
	kill_message.add_theme_color_override("font_color", Color.WHITE)
	kill_message.add_theme_color_override("font_shadow_color", Color.BLACK)
	kill_message.add_theme_constant_override("shadow_offset_x", 1)
	kill_message.add_theme_constant_override("shadow_offset_y", 1)
	kill_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	# Add to kill feed
	kill_feed.add_child(kill_message)
	kill_feed_messages.append(kill_message)
	
	# Remove old messages if we have too many
	while kill_feed_messages.size() > MAX_KILL_FEED_MESSAGES:
		var old_message = kill_feed_messages.pop_front()
		if is_instance_valid(old_message):
			old_message.queue_free()
	
	# Auto-remove this message after duration
	get_tree().create_timer(KILL_FEED_DURATION).timeout.connect(
		func(): _remove_kill_feed_message(kill_message)
	)

func _remove_kill_feed_message(message: Label):
	"""Remove a specific kill feed message"""
	if is_instance_valid(message) and message in kill_feed_messages:
		kill_feed_messages.erase(message)
		message.queue_free()

# --- SPOTTED ALERT SYSTEM ---

func show_spotted_alert():
	"""Show the 'SPOTTED!' alert for Hiders"""
	print("[DevGameUI] Showing SPOTTED alert")
	
	if not spotted_alert:
		return
	
	# Stop any existing fade tween
	if spotted_fade_tween:
		spotted_fade_tween.kill()
	
	# Show and animate the alert
	spotted_alert.visible = true
	spotted_alert.modulate = Color.WHITE
	
	# Create pulsing effect
	spotted_fade_tween = create_tween()
	spotted_fade_tween.set_loops()
	spotted_fade_tween.tween_property(spotted_alert, "modulate:a", 0.5, 0.3)
	spotted_fade_tween.tween_property(spotted_alert, "modulate:a", 1.0, 0.3)
	
	# Start timer to hide alert
	spotted_timer.start()

func _hide_spotted_alert():
	"""Hide the spotted alert"""
	print("[DevGameUI] Hiding SPOTTED alert")
	
	if not spotted_alert:
		return
	
	# Stop pulsing
	if spotted_fade_tween:
		spotted_fade_tween.kill()
	
	# Fade out
	spotted_fade_tween = create_tween()
	spotted_fade_tween.tween_property(spotted_alert, "modulate:a", 0.0, 0.5)
	spotted_fade_tween.tween_callback(func(): spotted_alert.visible = false)

# --- GAME STATUS SYSTEM ---

func update_game_status(status: String):
	"""Update the game status display"""
	if game_status:
		game_status.text = status
		print("[DevGameUI] Status: ", status)

func update_game_state(state: int):
	"""Update UI based on game state"""
	match state:
		0: # LOBBY
			update_game_status("Waiting for players...")
		1: # STARTING
			update_game_status("Game starting...")
		2: # WAITING_TO_START
			update_game_status("Preparing game...")
		3: # PRE_GAME_FREEZE
			update_game_status("Role assignments complete!")
		4: # HIDER_HEADSTART
			update_game_status("Hiders, GO! Find hiding spots!")
		5: # GAME_START_COUNTDOWN
			update_game_status("The Seeker is on the move!")
		6: # SEEKER_RELEASED
			update_game_status("The Seeker is on the move!")
		7: # IN_PROGRESS
			update_game_status("The Hunt is On!")
		8: # FINISHED
			update_game_status("Game Over")
		9: # GAME_OVER
			update_game_status("Match ended")
		_:
			update_game_status("Waiting for players...")

func update_ammo(ammo_count: int):
	"""Update ammo display for Seekers"""
	update_game_status("Ammo: " + str(ammo_count))

func update_hiders_left(count: int):
	"""Update hiders remaining count"""
	update_game_status("Hiders Left: " + str(count))

func update_countdown(time_text: String, show: bool):
	"""Update countdown display"""
	if show:
		update_game_status("Starting in: " + time_text)
	else:
		update_game_status("")

# --- GAMEMANAGER INTEGRATION ---

func initialize(player: Object):
	"""Initialize UI for a specific player"""
	if not player:
		return
	
	print("[DevGameUI] Initializing for player: ", player.player_name)
	
	# Setup role-specific UI visibility
	if "role" in player:
		if player.role == PlayerCharacter.PlayerRole.SEEKER:
			update_game_status("Role: SEEKER - Find and eliminate Hiders!")
			# Seeker sees ammo, all players see hiders left
			_setup_seeker_ui()
		else:
			update_game_status("Role: HIDER - Hide from the Seeker!")
			# Hider can see spotted alerts, all players see hiders left
			_setup_hider_ui()

func _setup_seeker_ui():
	"""Setup UI elements specific to Seekers"""
	print("[DevGameUI] Setting up Seeker UI")
	# Seeker-specific UI setup would go here
	# For now, the ammo display is handled in the update loop

func _setup_hider_ui():
	"""Setup UI elements specific to Hiders"""
	print("[DevGameUI] Setting up Hider UI")
	# Hider-specific UI setup would go here
	# Spotted alert is already available for all players

func update_role_specific_info(player: Object):
	"""Update role-specific information"""
	if not player or not "role" in player:
		return
	
	if player.role == PlayerCharacter.PlayerRole.SEEKER:
		# Show ammo count for Seekers
		if "ammo" in player:
			var status = "Ammo: " + str(player.ammo)
			# Count hiders for all players
			var hiders_count = _count_alive_hiders()
			if hiders_count > 0:
				status += " | Hiders Left: " + str(hiders_count)
			update_game_status(status)
	else:
		# Show hiders left for Hiders
		var hiders_count = _count_alive_hiders()
		update_game_status("Hiders Left: " + str(hiders_count))

func _count_alive_hiders() -> int:
	"""Count alive hiders in the game"""
	# This would need to be connected to the game world
	# For now, return a placeholder
	return 0

func show_game_over(did_win: bool, message: String):
	"""Show game over screen"""
	print("[DevGameUI] Game Over: ", message, " - Won: ", did_win)
	
	# Create simple game over display
	var game_over_label = Label.new()
	game_over_label.text = message + "\n" + ("YOU WIN!" if did_win else "YOU LOSE!")
	game_over_label.add_theme_font_size_override("font_size", 36)
	game_over_label.add_theme_color_override("font_color", Color.GREEN if did_win else Color.RED)
	game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	# Position in center
	game_over_label.anchors_preset = Control.PRESET_CENTER
	game_over_label.size = Vector2(400, 200)
	game_over_label.position = -game_over_label.size / 2
	
	add_child(game_over_label)

# --- RPC HANDLERS FOR SPOTTED SYSTEM ---

@rpc("authority", "call_local", "reliable")
func trigger_spotted_alert():
	"""RPC to trigger spotted alert on specific client"""
	show_spotted_alert()

@rpc("authority", "call_local", "reliable") 
func hide_spotted_alert_rpc():
	"""RPC to hide spotted alert on specific client"""
	_hide_spotted_alert()

func _exit_tree():
	# Unregister from GameManager
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("unregister_game_ui"):
		game_manager.unregister_game_ui(self)
