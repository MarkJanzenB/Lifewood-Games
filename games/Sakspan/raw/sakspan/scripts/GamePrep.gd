# GamePrep.gd - Handles the role reveal and countdown sequence
extends Control

# UI References
@onready var seeker_name_label: Label = $CenterContainer/VBoxContainer/SeekerInfoContainer/SeekerNameLabel
@onready var countdown_value_label: Label = $CenterContainer/VBoxContainer/CountdownContainer/CountdownValueLabel
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel

# Flag to prevent duplicate readiness reports
var _readiness_reported: bool = false

func _ready():
	print("[GamePrep] GamePrep scene loaded for peer ", multiplayer.get_unique_id())
	
	# Connect to GameManager signals for role and countdown updates
	# Use direct singleton access instead of node path
	var game_manager = GameManager
	if game_manager:
		# Connect to role reveal signal
		if game_manager.has_signal("seeker_revealed"):
			game_manager.seeker_revealed.connect(_on_seeker_revealed)
		
		# Connect to countdown signal  
		if game_manager.has_signal("prep_countdown_updated"):
			game_manager.prep_countdown_updated.connect(_on_countdown_updated)
		
		print("[GamePrep] Connected to GameManager signals")
	else:
		print("[GamePrep] ❌ GameManager singleton not found!")
	
	# CRITICAL FIX: Report readiness to NetworkManager after scene is fully loaded
	# Wait one frame to ensure scene is fully initialized
	await get_tree().process_frame
	
	# Report readiness to NetworkManager
	var network_manager = NetworkManager
	if network_manager:
		if multiplayer.is_server():
			# Server: Check if we need to wait for clients or can proceed immediately
			if network_manager.players.size() == 1:
				# Single player - server can proceed immediately
				print("[GamePrep] Single player - server proceeding with role assignment")
				if game_manager and game_manager.has_method("start_role_assignment"):
					game_manager.start_role_assignment()
			else:
				# Multiplayer - server waits for all clients to report readiness
				print("[GamePrep] Server ready, waiting for ", network_manager.players.size() - 1, " clients")
		else:
			# Client: Report readiness to server (only once)
			if not _readiness_reported:
				print("[GamePrep] Client ", multiplayer.get_unique_id(), " reporting readiness to server")
				if network_manager.has_method("rpc_report_gameprep_ready"):
					network_manager.rpc_report_gameprep_ready.rpc_id(1)  # Send to server (ID 1)
					_readiness_reported = true
				else:
					print("[GamePrep] ❌ NetworkManager missing rpc_report_gameprep_ready method!")
			else:
				print("[GamePrep] ⚠️ Readiness already reported - skipping duplicate")
	else:
		print("[GamePrep] ❌ NetworkManager singleton not found!")

# Called when GameManager broadcasts the seeker information
func _on_seeker_revealed(seeker_name: String, seeker_character: String):
	print("[GamePrep] 🎯 CLIENT RECEIVED: Seeker revealed - ", seeker_name, " (Peer: ", multiplayer.get_unique_id(), ")")
	if seeker_name_label:
		seeker_name_label.text = seeker_name
		seeker_name_label.add_theme_color_override("font_color", Color.RED)
	
	if status_label:
		status_label.text = "Roles assigned! Preparing to enter game world..."

# Called when GameManager broadcasts countdown updates
func _on_countdown_updated(time_remaining: int):
	print("[GamePrep] ⏰ CLIENT RECEIVED: Countdown update - ", time_remaining, " (Peer: ", multiplayer.get_unique_id(), ")")
	if countdown_value_label:
		countdown_value_label.text = str(time_remaining)
		
		# Color coding for urgency
		if time_remaining <= 2:
			countdown_value_label.add_theme_color_override("font_color", Color.RED)
		elif time_remaining <= 3:
			countdown_value_label.add_theme_color_override("font_color", Color.YELLOW)
		else:
			countdown_value_label.add_theme_color_override("font_color", Color.WHITE)
	
	# Update status based on countdown
	if status_label:
		if time_remaining > 0:
			status_label.text = "Get ready to enter the game world..."
		else:
			status_label.text = "Loading game world..."
