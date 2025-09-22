# res://scripts/dev/dev_world.gd
# Dev test world for multiplayer player interaction testing with full gameplay mechanics
extends Node2D

# Node references
@onready var players_container: Node2D = $PlayersContainer
@onready var multiplayer_spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var players_label: Label = $UI/InfoPanel/VBox/PlayersLabel
@onready var title_label: Label = $UI/InfoPanel/VBox/TitleLabel
@onready var grid_lines: Node2D = $GridLines
@onready var canvas_modulate: CanvasModulate = $CanvasModulate
@onready var obstacles_container: Node2D = $ObstaclesContainer
@onready var game_ui: Control = $GameUI

# Player scene to spawn
const PLAYER_SCENE = preload("res://scenes/player/Player.tscn")

# Spawn configuration
var spawn_points: Array[Vector2] = [
	Vector2(0, 0),
	Vector2(200, 0),
	Vector2(-200, 0),
	Vector2(0, 200),
	Vector2(0, -200)
]

var spawned_players: Dictionary = {}

func _ready():
	print("[DevWorld] Starting dev test world with full gameplay mechanics")
	
	# Initialize hybrid LOS system
	_setup_hybrid_los_system()
	
	# Create sample obstacles for testing
	_create_sample_obstacles()
	
	# Initialize GameUI
	_initialize_game_ui()
	
	# Initialize gameplay
	_initialize_gameplay()
	
	# Configure multiplayer spawner
	_setup_multiplayer_spawner()
	
	# Draw grid for reference
	_draw_grid()
	
	# Hide dev UI panel for normal gameplay
	var info_panel = get_node_or_null("UI/InfoPanel")
	if info_panel:
		info_panel.visible = false
		print("[DevWorld] Dev info panel hidden for gameplay")
	
	# Setup GameManager integration
	_setup_game_manager()
	
	# Connect NetworkManager signals
	if NetworkManager:
		NetworkManager.player_list_changed.connect(_on_player_list_changed)
	
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	# Spawn existing players
	await get_tree().process_frame
	_spawn_all_players()
	
	# Force spawn local player for testing if no players are spawned
	await get_tree().create_timer(1.0).timeout
	if spawned_players.is_empty() and multiplayer.is_server():
		print("[DevWorld] No players spawned, force spawning local player for testing")
		var local_id = multiplayer.get_unique_id()
		var test_data = {"name": "TestPlayer_" + str(local_id), "char_index": 0}
		_spawn_player_with_spawner(local_id, test_data)
	
	# Initialize game mechanics after players are spawned
	await get_tree().create_timer(3.0).timeout
	if multiplayer.is_server() and spawned_players.size() >= 1:
		_initialize_gameplay()
	
	print("[DevWorld] Ready - Server: ", multiplayer.is_server())
	
	# Debug: Check all children in PlayersContainer after a delay
	await get_tree().create_timer(2.0).timeout
	print("[DevWorld] Debug - PlayersContainer children:")
	if players_container:
		for child in players_container.get_children():
			print("  Child: ", child.name, " at ", child.global_position if "global_position" in child else "no position")
			if child.has_method("get_multiplayer_authority"):
				print("    Authority: ", child.get_multiplayer_authority())
				print("    Is main: ", child.is_main_player if "is_main_player" in child else "no is_main_player")
				print("    Can move: ", child.can_move if "can_move" in child else "no can_move")

# --- HYBRID LOS SYSTEM SETUP ---

func _setup_hybrid_los_system():
	"""Setup the hybrid Line of Sight system with global darkness and personal FOV"""
	print("[DevWorld] Setting up hybrid LOS system...")
	
	# Create CanvasModulate for global darkness if it doesn't exist
	if not canvas_modulate:
		canvas_modulate = CanvasModulate.new()
		add_child(canvas_modulate)
	
	# Set global darkness (Among Us style) - lighter for better visibility
	var darkness_color = Color(0.3, 0.3, 0.4, 1.0)
	canvas_modulate.color = darkness_color
	print("[DevWorld] Global darkness applied: ", canvas_modulate.color)
	
	# Sync darkness to all clients
	if multiplayer.is_server():
		_sync_darkness_to_clients.rpc(darkness_color)

func _initialize_game_ui():
	"""Initialize and configure the GameUI"""
	if not game_ui:
		print("[DevWorld] WARNING: GameUI node not found!")
		return
	
	print("[DevWorld] Initializing GameUI...")
	
	# Make sure GameUI is visible and properly configured
	game_ui.visible = true
	
	# Connect to update loop
	if not has_method("_update_game_ui"):
		print("[DevWorld] Adding GameUI update to process")
	
	print("[DevWorld] GameUI initialized successfully")

func _process(_delta):
	"""Update GameUI with current game state"""
	if game_ui and game_ui.has_method("update_game_status"):
		_update_game_ui()

func _update_game_ui():
	"""Update GameUI with current player and game information"""
	if not game_ui:
		return
	
	# Find local player
	var local_player = null
	for player_id in spawned_players:
		var player = spawned_players[player_id]
		if is_instance_valid(player) and player.is_main_player:
			local_player = player
			break
	
	if not local_player:
		return
	
	# Update role-specific information
	if local_player.role == PlayerCharacter.PlayerRole.SEEKER:
		if game_ui.has_method("update_ammo"):
			game_ui.update_ammo(local_player.ammo)
		
		# Count alive hiders
		var alive_hiders = 0
		for player_id in spawned_players:
			var player = spawned_players[player_id]
			if is_instance_valid(player) and player.current_state == PlayerCharacter.PlayerState.ALIVE and player.role == PlayerCharacter.PlayerRole.HIDER:
				alive_hiders += 1
		
		if game_ui.has_method("update_hiders_left"):
			game_ui.update_hiders_left(alive_hiders)
	else:
		# For hiders, show survival status
		if game_ui.has_method("update_game_status"):
			game_ui.update_game_status("Role: HIDER - Stay hidden!")

@rpc("authority", "call_local", "reliable")
func _sync_darkness_to_clients(darkness_color: Color):
	"""Sync CanvasModulate darkness to all clients"""
	print("[DevWorld] Syncing darkness color: ", darkness_color)
	
	# Ensure CanvasModulate exists
	if not canvas_modulate:
		canvas_modulate = get_node_or_null("CanvasModulate")
		if not canvas_modulate:
			canvas_modulate = CanvasModulate.new()
			add_child(canvas_modulate)
	
	# Apply darkness
	canvas_modulate.color = darkness_color
	print("[DevWorld] Darkness synchronized for client: ", multiplayer.get_unique_id())

func _create_sample_obstacles():
	"""Create sample obstacles with LightOccluder2D for shadow casting"""
	print("[DevWorld] Creating sample obstacles for LOS testing...")
	
	# Create obstacles container if it doesn't exist
	if not obstacles_container:
		obstacles_container = Node2D.new()
		obstacles_container.name = "ObstaclesContainer"
		add_child(obstacles_container)
	
	# Create several wall obstacles
	var wall_positions = [
		Vector2(100, 100),
		Vector2(-150, 50),
		Vector2(50, -100),
		Vector2(-100, -150),
		Vector2(250, -50)
	]
	
	for i in range(wall_positions.size()):
		var wall = _create_wall_obstacle(wall_positions[i], Vector2(80, 20))
		wall.name = "Wall_" + str(i)
		obstacles_container.add_child(wall)
	
	print("[DevWorld] Created ", wall_positions.size(), " wall obstacles")

func _create_wall_obstacle(pos: Vector2, size: Vector2) -> StaticBody2D:
	"""Create a wall obstacle with collision and light occlusion"""
	var wall = StaticBody2D.new()
	wall.global_position = pos
	
	# Visual representation
	var sprite = Sprite2D.new()
	var texture = ImageTexture.new()
	var image = Image.create(int(size.x), int(size.y), false, Image.FORMAT_RGB8)
	image.fill(Color(0.3, 0.3, 0.3))  # Dark gray
	texture.set_image(image)
	sprite.texture = texture
	wall.add_child(sprite)
	
	# Collision shape
	var collision = CollisionShape2D.new()
	var rect_shape = RectangleShape2D.new()
	rect_shape.size = size
	collision.shape = rect_shape
	wall.add_child(collision)
	
	# Light occluder for shadow casting
	var occluder = LightOccluder2D.new()
	var occluder_shape = OccluderPolygon2D.new()
	var half_size = size / 2
	occluder_shape.polygon = PackedVector2Array([
		Vector2(-half_size.x, -half_size.y),
		Vector2(half_size.x, -half_size.y),
		Vector2(half_size.x, half_size.y),
		Vector2(-half_size.x, half_size.y)
	])
	occluder.occluder = occluder_shape
	wall.add_child(occluder)
	
	# Set collision layers
	wall.collision_layer = 4  # Obstacles layer
	wall.collision_mask = 0   # Don't collide with anything
	
	return wall

func _setup_game_manager():
	"""Setup GameManager integration for server-authoritative gameplay"""
	print("[DevWorld] Setting up GameManager integration...")
	
	# Connect to GameManager signals if it exists
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		print("[DevWorld] GameManager found, connecting signals...")
		if not game_manager.game_state_changed.is_connected(_on_game_state_changed):
			game_manager.game_state_changed.connect(_on_game_state_changed)
		if not game_manager.player_eliminated.is_connected(_on_player_eliminated):
			game_manager.player_eliminated.connect(_on_player_eliminated)
	else:
		print("[DevWorld] WARNING: GameManager not found as singleton!")

func _initialize_gameplay():
	"""Initialize gameplay by assigning roles and starting game flow"""
	if not multiplayer.is_server():
		return
	
	print("[DevWorld] Initializing gameplay...")
	
	# Assign roles to players
	_assign_player_roles()
	
	# Start game timer for testing (60 seconds)
	_start_game_timer()
	
	# Start game immediately for dev testing
	print("[DevWorld] Starting game immediately for dev testing")

func _start_game_timer():
	"""Start the main game timer using lobby setting"""
	if not has_node("GameTimer"):
		var timer = Timer.new()
		timer.name = "GameTimer"
		
		# Get timer setting from NetworkManager lobby data
		var timer_duration = _parse_timer_setting()
		timer.wait_time = timer_duration
		timer.one_shot = true
		timer.timeout.connect(_on_game_timer_timeout)
		add_child(timer)
		
		print("[DevWorld] Game timer created with duration: ", timer_duration, " seconds")
	
	var timer = get_node("GameTimer")
	timer.start()
	print("[DevWorld] Game timer started - ", timer.wait_time, " seconds")

func _parse_timer_setting() -> float:
	"""Parse timer setting from lobby data"""
	var network_manager = get_node_or_null("/root/NetworkManager")
	if not network_manager:
		print("[DevWorld] NetworkManager not found, using default 60 seconds")
		return 60.0
	
	var timer_setting = network_manager.my_lobby_data.get("timer", "Default")
	print("[DevWorld] Parsing timer setting: ", timer_setting)
	
	# Parse common timer formats
	match timer_setting:
		"1 minute":
			return 60.0
		"2 minutes":
			return 120.0
		"3 minutes":
			return 180.0
		"5 minutes":
			return 300.0
		"10 minutes":
			return 600.0
		_:
			# Try to extract number from string
			var regex = RegEx.new()
			regex.compile("(\\d+)")
			var result = regex.search(str(timer_setting))
			if result:
				var minutes = result.get_string().to_int()
				print("[DevWorld] Extracted ", minutes, " minutes from timer setting")
				return minutes * 60.0
			else:
				print("[DevWorld] Could not parse timer setting, using default 60 seconds")
				return 60.0

func _on_game_timer_timeout():
	"""Handle game timer timeout - Hiders win"""
	print("[DevWorld] Game timer expired - Hiders win!")
	_end_game("HIDERS", "Time expired! Hiders survived and won!")

func _assign_player_roles():
	"""Assign asymmetrical roles: 1 Seeker, rest Hiders"""
	if not multiplayer.is_server():
		return
	
	var player_ids = spawned_players.keys()
	if player_ids.is_empty():
		return
	
	print("[DevWorld] Assigning roles to ", player_ids.size(), " players...")
	
	# Randomly select one seeker
	var seeker_id = player_ids[randi() % player_ids.size()]
	
	for player_id in player_ids:
		var player = spawned_players[player_id]
		if not is_instance_valid(player):
			continue
		
		if player_id == seeker_id:
			# Assign Seeker role
			player.assign_role(PlayerCharacter.PlayerRole.SEEKER)
			player.set_ammo(player_ids.size())  # Ammo based on hider count
			print("[DevWorld] Assigned SEEKER role to ", player.player_name, " with ", player.ammo, " ammo")
		else:
			# Assign Hider role
			player.assign_role(PlayerCharacter.PlayerRole.HIDER)
			print("[DevWorld] Assigned HIDER role to ", player.player_name)

func _setup_multiplayer_spawner():
	if not multiplayer_spawner:
		return
	
	# The spawnable scenes are already configured in the .tscn file
	# Just connect the signals
	multiplayer_spawner.spawned.connect(_on_player_spawned)
	multiplayer_spawner.despawned.connect(_on_player_despawned)
	
	print("[DevWorld] MultiplayerSpawner configured")

func _draw_grid():
	# Create visual grid lines for reference
	var line_color = Color(0.5, 0.5, 0.5, 0.3)
	
	# Vertical lines
	for x in range(-10, 11):
		var line = Line2D.new()
		line.add_point(Vector2(x * 100, -1000))
		line.add_point(Vector2(x * 100, 1000))
		line.default_color = line_color
		line.width = 1.0
		grid_lines.add_child(line)
	
	# Horizontal lines
	for y in range(-10, 11):
		var line = Line2D.new()
		line.add_point(Vector2(-1000, y * 100))
		line.add_point(Vector2(1000, y * 100))
		line.default_color = line_color
		line.width = 1.0
		grid_lines.add_child(line)

func _spawn_all_players():
	print("[DevWorld] Spawning all connected players - Server: ", multiplayer.is_server())
	
	# Get player data from NetworkManager
	var player_data = NetworkManager.players
	print("[DevWorld] Player data available: ", player_data)
	
	if multiplayer.is_server():
		# Use MultiplayerSpawner to spawn all players
		for player_id in player_data:
			if not spawned_players.has(player_id):
				_spawn_player_with_spawner(player_id, player_data[player_id])
	else:
		# Client waits for server to spawn players via MultiplayerSpawner
		print("[DevWorld] Client waiting for server to spawn players...")

func _spawn_player_with_spawner(player_id: int, player_info: Dictionary):
	if not multiplayer.is_server():
		return
	
	if spawned_players.has(player_id):
		print("[DevWorld] Player ", player_id, " already spawned")
		return
	
	print("[DevWorld] Spawning player with MultiplayerSpawner: ", player_id, " - ", player_info.get("name", "Unknown"))
	
	# Use MultiplayerSpawner to spawn the player
	# Use consistent spawn index calculation
	var all_player_ids = NetworkManager.players.keys()
	all_player_ids.sort()  # Ensure consistent order
	var spawn_index = all_player_ids.find(player_id) % spawn_points.size()
	var spawn_position = spawn_points[spawn_index]
	print("[DevWorld] Server spawning player ", player_id, " at index ", spawn_index, " position: ", spawn_position)
	
	# Create the player instance
	var player_instance = PLAYER_SCENE.instantiate()
	
	# Set name and authority before adding to scene
	player_instance.name = "Player_" + str(player_id)
	player_instance.set_multiplayer_authority(player_id)
	player_instance.global_position = spawn_position
	
	# Add to the PlayersContainer (MultiplayerSpawner will handle replication)
	players_container.add_child(player_instance, true)
	
	# Setup player data - use the original player script methods
	var is_local = (player_id == multiplayer.get_unique_id())
	var player_name = player_info.get("name", "Player")
	
	# Set player name BEFORE replication config setup
	player_instance.player_name = player_name
	
	# Enable movement and attacks for all players (dev testing)
	player_instance.can_move = true
	player_instance.can_attack = true
	if is_local:
		player_instance.is_main_player = true
		print("[DevWorld] Set local player as main: ", player_name)
	
	# Force enable attacks for dev testing
	await get_tree().process_frame
	player_instance.can_attack = true
	print("[DevWorld] Force enabled attacks for player: ", player_name)
	
	# Call setup function if it exists
	if player_instance.has_method("setup_multiplayer_player"):
		player_instance.setup_multiplayer_player(player_info, is_local)
	
	# Apply character appearance based on character selection
	var character_index = player_info.get("char_index", 0)
	_apply_character_appearance(player_instance, character_index)
	
	# Setup personal FOV lighting (hybrid LOS system)
	_setup_player_personal_fov(player_instance)
	
	# Track spawned player
	spawned_players[player_id] = player_instance
	
	# Update UI
	_update_players_count()
	
	print("[DevWorld] Player spawned successfully with MultiplayerSpawner: ", player_id)

func _apply_character_appearance(player: Node, character_index: int):
	# Use CharacterFactory to get the correct color
	if character_index < 0 or character_index >= CharacterFactory.get_character_count():
		character_index = 0  # Default to first character
	
	var color = CharacterFactory.get_character_color(character_index)
	var character_name = CharacterFactory.get_character_name(character_index)
	
	print("[DevWorld] Applying ", character_name, " appearance with color: ", color)
	
	# Apply color to animated sprite
	if player.has_node("AnimatedSprite2D"):
		var sprite = player.get_node("AnimatedSprite2D")
		sprite.modulate = color
		print("[DevWorld] Successfully applied ", character_name, " color: ", color)
	else:
		print("[DevWorld] ERROR: No AnimatedSprite2D found on player!")
	
	# Ensure character index is set
	if "character_index" in player:
		player.character_index = character_index

func _setup_player_personal_fov(player: Node):
	"""Setup personal Field of View lighting for the hybrid LOS system"""
	if not player.has_node("VisionCone/PointLight2D"):
		print("[DevWorld] WARNING: Player missing PointLight2D for personal FOV")
		return
	
	var point_light = player.get_node("VisionCone/PointLight2D")
	
	# Configure personal FOV light (Among Us style circular light) - brighter for visibility
	point_light.enabled = true
	point_light.energy = 2.0  # Increased from 1.2
	point_light.color = Color.WHITE
	point_light.shadow_enabled = true
	point_light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	
	# Set light radius for personal visibility - larger radius
	if point_light.texture:
		point_light.texture_scale = 4.0  # Increased from 2.5 for better visibility
	
	# Ensure player sprite is visible by setting proper light mask
	if player.has_node("AnimatedSprite2D"):
		var sprite = player.get_node("AnimatedSprite2D")
		sprite.light_mask = 1  # Make sure sprite receives light
		
		# For the local player, ensure they're always visible to themselves
		if player.is_main_player:
			sprite.self_modulate = Color(1.2, 1.2, 1.2, 1.0)  # Slightly brighter for self
			print("[DevWorld] Enhanced self-visibility for local player")
	
	print("[DevWorld] Personal FOV configured for player: ", player.name)

# --- GAMEMANAGER SIGNAL HANDLERS ---

func _on_game_state_changed(new_state: int):
	"""Handle GameManager state changes"""
	print("[DevWorld] Game state changed to: ", new_state)
	
	# Update GameUI with new state
	if game_ui and game_ui.has_method("update_game_state"):
		game_ui.update_game_state(new_state)
	
	# Update all players based on game state
	for player_id in spawned_players:
		var player = spawned_players[player_id]
		if is_instance_valid(player) and player.has_method("_on_game_state_changed"):
			player._on_game_state_changed(new_state)

func _on_player_eliminated(eliminated_player: Object, attacker: Object):
	"""Handle player elimination events"""
	if eliminated_player and attacker:
		print("[DevWorld] Player eliminated: ", eliminated_player.player_name, " by ", attacker.player_name)
		
		# Could add visual effects, sounds, etc. here
		_create_elimination_effect(eliminated_player.global_position)
		
		# Check win conditions after elimination (with small delay for death animation)
		if multiplayer.is_server():
			await get_tree().create_timer(0.1).timeout
			_check_win_conditions()

func _create_elimination_effect(position: Vector2):
	"""Create visual effect at elimination position"""
	# Simple particle effect or flash
	var effect = ColorRect.new()
	effect.color = Color.RED
	effect.size = Vector2(50, 50)
	effect.position = position - effect.size / 2
	add_child(effect)
	
	# Fade out effect
	var tween = create_tween()
	tween.tween_property(effect, "modulate:a", 0.0, 1.0)
	tween.tween_callback(effect.queue_free)

func _check_win_conditions():
	"""Check if any team has won the game"""
	if not multiplayer.is_server():
		return
	
	var alive_seekers = 0
	var alive_hiders = 0
	var total_seekers = 0
	var total_hiders = 0
	
	# Count alive players by role
	for player_id in spawned_players:
		var player = spawned_players[player_id]
		if is_instance_valid(player):
			if player.role == PlayerCharacter.PlayerRole.SEEKER:
				total_seekers += 1
				if player.current_state == PlayerCharacter.PlayerState.ALIVE and not player.is_dying:
					alive_seekers += 1
			else:
				total_hiders += 1
				if player.current_state == PlayerCharacter.PlayerState.ALIVE and not player.is_dying:
					alive_hiders += 1
	
	print("[DevWorld] Win check - Alive Seekers: ", alive_seekers, "/", total_seekers, " Alive Hiders: ", alive_hiders, "/", total_hiders)
	
	# Check win conditions - must have decisive victory
	if alive_seekers == 0 and total_seekers > 0:
		# Seeker eliminated - Hiders win
		print("[DevWorld] GAME OVER: Seeker eliminated!")
		_end_game("HIDERS", "The Seeker was eliminated! Hiders win!")
	elif alive_hiders == 0 and total_hiders > 0:
		# All Hiders eliminated - Seeker wins
		print("[DevWorld] GAME OVER: All Hiders eliminated!")
		_end_game("SEEKERS", "All Hiders eliminated! Seeker wins!")
	else:
		print("[DevWorld] Game continues...")

func _on_peer_connected(id: int):
	print("[DevWorld] Peer connected: ", id)
	
	# Wait for NetworkManager to register the player
	await get_tree().create_timer(0.5).timeout
	
	if multiplayer.is_server() and NetworkManager.players.has(id):
		_spawn_player_with_spawner(id, NetworkManager.players[id])

func _on_peer_disconnected(id: int):
	print("[DevWorld] Peer disconnected: ", id)
	
	if spawned_players.has(id):
		var player_instance = spawned_players[id]
		if is_instance_valid(player_instance):
			player_instance.queue_free()
		spawned_players.erase(id)
		_update_players_count()

func _on_player_list_changed(players: Dictionary):
	print("[DevWorld] Player list changed: ", players.keys())
	print("[DevWorld] Current spawned players: ", spawned_players.keys())
	
	# Spawn any new players (server only)
	if multiplayer.is_server():
		for player_id in players:
			if not spawned_players.has(player_id):
				print("[DevWorld] Need to spawn new player: ", player_id)
				_spawn_player_with_spawner(player_id, players[player_id])
	
	_update_players_count()

func _on_player_spawned(node: Node):
	print("[DevWorld] MultiplayerSpawner spawned: ", node.name, " - Server: ", multiplayer.is_server())
	
	# If this is a client receiving a spawned player, track it
	if not multiplayer.is_server():
		# Extract player ID from node name (Player_1234567)
		var player_id_str = node.name.get_slice("_", 1)
		var player_id = int(player_id_str)
		
		print("[DevWorld] Client parsing player ID from name: ", node.name, " -> ", player_id)
		
		# CRITICAL: Set the correct multiplayer authority for this node
		node.set_multiplayer_authority(player_id)
		
		spawned_players[player_id] = node
		
		# Set up the client player properly
		var is_local = (player_id == multiplayer.get_unique_id())
		
		# Get player data from NetworkManager
		var player_data = NetworkManager.players
		var player_info = player_data.get(player_id, {"name": "Unknown"})
		var player_name = player_info.get("name", "Unknown")
		
		# Set player name and update display
		node.player_name = player_name
		if node.has_method("update_username_display"):
			node.update_username_display()
		
		# Apply character appearance based on character selection
		var character_index = player_info.get("char_index", 0)
		_apply_character_appearance(node, character_index)
		
		# Setup personal FOV lighting (hybrid LOS system)
		_setup_player_personal_fov(node)
		
		# CRITICAL: Set correct spawn position on client
		# Use player_id to determine consistent spawn position
		var all_player_ids = NetworkManager.players.keys()
		all_player_ids.sort()  # Ensure consistent order
		var spawn_index = all_player_ids.find(player_id) % spawn_points.size()
		var spawn_position = spawn_points[spawn_index]
		node.global_position = spawn_position
		print("[DevWorld] Client set spawn position for player ", player_id, " (index ", spawn_index, ") to: ", spawn_position)
		
		# Reconfigure the player's authority settings after setting authority
		if node.has_method("_configure_multiplayer_authority"):
			node._configure_multiplayer_authority()
		
		if is_local:
			node.is_main_player = true
			node.can_move = true
			node.can_attack = true
			
			# Ensure camera is enabled for local player
			if node.has_method("get_node") and node.get_node_or_null("Camera2D"):
				var camera = node.get_node("Camera2D")
				camera.enabled = true
				camera.make_current()
				print("[DevWorld] Client enabled camera for local player")
			
			print("[DevWorld] Client set up local player: ", player_id, " - ", player_name)
		else:
			print("[DevWorld] Client received remote player: ", player_id, " - ", player_name)
		
		_update_players_count()

func _on_player_despawned(node: Node):
	print("[DevWorld] MultiplayerSpawner despawned: ", node.name, " - Server: ", multiplayer.is_server())
	
	# If this is a client, remove from tracking
	if not multiplayer.is_server():
		# Extract player ID from node name (Player_1234567)
		var player_id_str = node.name.get_slice("_", 1)
		var player_id = int(player_id_str)
		
		if spawned_players.has(player_id):
			spawned_players.erase(player_id)
			_update_players_count()
			print("[DevWorld] Client removed despawned player: ", player_id)

func _update_players_count():
	var count = spawned_players.size()
	if players_label:
		# Hide the players count label since we show usernames above characters
		players_label.visible = false
	
	# Debug: Print all spawned players and their positions
	print("[DevWorld] Current spawned players: ", count)
	for player_id in spawned_players:
		var player = spawned_players[player_id]
		if is_instance_valid(player):
			print("  Player ", player_id, ": ", player.player_name, " at ", player.global_position, " visible: ", player.visible)
		else:
			print("  Player ", player_id, ": INVALID NODE")

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			print("[DevWorld] Returning to lobby")
			# Return to multiplayer menu
			SceneChanger.change_scene_to_file("res://scenes/UI/Multiplayer/multiplayer_menu.tscn")
		elif event.keycode == KEY_F5:
			print("[DevWorld] === F5 DEBUG: Game State Info ===")
			_debug_game_state()
		elif event.keycode == KEY_F6:
			print("[DevWorld] === F6 DEBUG: Force Start Game ===")
			if multiplayer.is_server():
				_initialize_gameplay()
		elif event.keycode == KEY_F7:
			print("[DevWorld] === F7 DEBUG: Testing character colors ===")
			_test_character_colors()
		elif event.keycode == KEY_F8:
			print("[DevWorld] === F8 DEBUG: LOS System Test ===")
			_debug_los_system()
		elif event.keycode == KEY_F9:
			print("[DevWorld] === F9 DEBUG: Toggle Global Darkness ===")
			_toggle_global_darkness()

func _test_character_colors():
	print("[DevWorld] === CHARACTER COLOR TEST ===")
	
	for player_id in spawned_players:
		var player = spawned_players[player_id]
		if is_instance_valid(player):
			print("[DevWorld] Player ", player_id, ": ", player.player_name)
			print("  - Character Index: ", player.character_index if "character_index" in player else "NOT SET")
			print("  - Character Name: ", player.get_character_name() if player.has_method("get_character_name") else "NO METHOD")
			
			if player.has_node("AnimatedSprite2D"):
				var sprite = player.get_node("AnimatedSprite2D")
				print("  - Sprite Color: ", sprite.modulate)
				
				# Get expected color
				var char_index = player.character_index if "character_index" in player else 0
				var expected_color = CharacterFactory.get_character_color(char_index)
				var expected_name = CharacterFactory.get_character_name(char_index)
				print("  - Expected Color: ", expected_color, " (", expected_name, ")")
				
				if sprite.modulate.is_equal_approx(expected_color):
					print("  - ✅ Color matches!")
				else:
					print("  - ❌ Color mismatch! Applying correct color...")
					_apply_character_appearance(player, char_index)
			else:
				print("  - ❌ No AnimatedSprite2D found!")

func _debug_game_state():
	"""Debug function to show current game state"""
	print("[DevWorld] === GAME STATE DEBUG ===")
	print("  - Server: ", multiplayer.is_server())
	print("  - Spawned Players: ", spawned_players.size())
	
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		print("  - GameManager State: ", game_manager.current_state)
		print("  - GameManager Players: ", game_manager.players.size())
	else:
		print("  - GameManager: NOT FOUND")
	
	# Show player roles
	for player_id in spawned_players:
		var player = spawned_players[player_id]
		if is_instance_valid(player):
			var role_name = "UNKNOWN"
			if "role" in player:
				role_name = "SEEKER" if player.role == PlayerCharacter.PlayerRole.SEEKER else "HIDER"
			print("  - Player ", player_id, " (", player.player_name, "): ", role_name)
			if "ammo" in player:
				print("    Ammo: ", player.ammo)

func _debug_los_system():
	"""Debug function to test Line of Sight system"""
	print("[DevWorld] === LOS SYSTEM DEBUG ===")
	print("  - Global Darkness: ", canvas_modulate.color if canvas_modulate else "NOT SET")
	print("  - Obstacles: ", obstacles_container.get_child_count() if obstacles_container else 0)
	
	# Test each player's lighting
	for player_id in spawned_players:
		var player = spawned_players[player_id]
		if is_instance_valid(player):
			print("  - Player ", player.player_name, ":")
			if player.has_node("VisionCone/PointLight2D"):
				var light = player.get_node("VisionCone/PointLight2D")
				print("    Personal Light: Enabled=", light.enabled, " Energy=", light.energy)
				print("    Shadow Enabled: ", light.shadow_enabled)
			else:
				print("    Personal Light: MISSING")
			
			if player.has_node("VisionCone"):
				var cone = player.get_node("VisionCone")
				print("    Vision Cone: Monitoring=", cone.monitoring if "monitoring" in cone else "N/A")
			else:
				print("    Vision Cone: MISSING")

func _toggle_global_darkness():
	"""Toggle global darkness for testing"""
	if not canvas_modulate:
		print("[DevWorld] No CanvasModulate found!")
		return
	
	if canvas_modulate.color.r > 0.5:
		# Currently bright, make dark
		canvas_modulate.color = Color(0.1, 0.1, 0.15, 1.0)
		print("[DevWorld] Global darkness ENABLED")
	else:
		# Currently dark, make bright
		canvas_modulate.color = Color.WHITE
		print("[DevWorld] Global darkness DISABLED")

# Ensure input actions exist for player movement
func _ensure_input_actions():
	var actions = [
		{"name": "move_up", "key": KEY_W},
		{"name": "move_down", "key": KEY_S},
		{"name": "move_left", "key": KEY_A},
		{"name": "move_right", "key": KEY_D},
		{"name": "run", "key": KEY_SHIFT},
		{"name": "fire", "key": KEY_SPACE}
	]
	
	# Also add mouse button for fire action
	var fire_mouse_actions = [
		{"name": "fire", "mouse_button": MOUSE_BUTTON_LEFT}
	]
	
	for action in actions:
		if not InputMap.has_action(action.name):
			InputMap.add_action(action.name)
			var event = InputEventKey.new()
			event.keycode = action.key
			InputMap.action_add_event(action.name, event)
			print("[DevWorld] Created input action: ", action.name)
	
	# Add mouse button events for fire action
	for action in fire_mouse_actions:
		if InputMap.has_action(action.name):
			var mouse_event = InputEventMouseButton.new()
			mouse_event.button_index = action.mouse_button
			InputMap.action_add_event(action.name, mouse_event)
			print("[DevWorld] Added mouse button to fire action: ", action.mouse_button)

# --- GAME OVER SYSTEM ---

func _end_game(winning_team: String, message: String):
	"""End the game and show results"""
	if not multiplayer.is_server():
		return
	
	print("[DevWorld] Ending game - Winner: ", winning_team, " Message: ", message)
	
	# Send game over to all clients
	_show_game_over.rpc(winning_team, message)

@rpc("authority", "call_local", "reliable")
func _show_game_over(winning_team: String, message: String):
	"""Show game over screen to all players"""
	print("[DevWorld] Showing game over - Winner: ", winning_team)
	
	# Find local player
	var local_player = null
	for player_id in spawned_players:
		var player = spawned_players[player_id]
		if is_instance_valid(player) and player.is_main_player:
			local_player = player
			break
	
	if not local_player:
		print("[DevWorld] No local player found for game over screen")
		return
	
	# Determine if local player won
	var did_win = false
	if winning_team == "SEEKERS" and local_player.role == PlayerCharacter.PlayerRole.SEEKER:
		did_win = true
	elif winning_team == "HIDERS" and local_player.role == PlayerCharacter.PlayerRole.HIDER:
		did_win = true
	
	# Create simple game over overlay
	_create_game_over_overlay(did_win, message)

func _create_game_over_overlay(did_win: bool, message: String):
	"""Create a simple game over overlay"""
	var overlay = Control.new()
	overlay.name = "GameOverOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Background
	var background = ColorRect.new()
	background.color = Color(0, 0, 0, 0.8)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(background)
	
	# Main container
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.size = Vector2(400, 200)
	vbox.position = -vbox.size / 2
	overlay.add_child(vbox)
	
	# Result label
	var result_label = Label.new()
	result_label.text = "VICTORY!" if did_win else "DEFEAT!"
	result_label.add_theme_font_size_override("font_size", 48)
	result_label.add_theme_color_override("font_color", Color.GREEN if did_win else Color.RED)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(result_label)
	
	# Message label
	var message_label = Label.new()
	message_label.text = message
	message_label.add_theme_font_size_override("font_size", 18)
	message_label.add_theme_color_override("font_color", Color.WHITE)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(message_label)
	
	# Return button
	var return_button = Button.new()
	return_button.text = "Return to Lobby"
	return_button.pressed.connect(_request_return_to_lobby)
	vbox.add_child(return_button)
	
	# Add to UI layer
	var ui_layer = get_node("UI")
	ui_layer.add_child(overlay)
	
	print("[DevWorld] Game over overlay created")

func _request_return_to_lobby():
	"""Request return to lobby from client"""
	print("[DevWorld] Requesting return to lobby...")
	if multiplayer.is_server():
		_reset_lobby_and_return()
	else:
		_request_lobby_return.rpc_id(1)

@rpc("any_peer", "call_local", "reliable")
func _request_lobby_return():
	"""RPC to request lobby return from server"""
	if multiplayer.is_server():
		print("[DevWorld] Client requested lobby return")
		_reset_lobby_and_return()

func _reset_lobby_and_return():
	"""Reset lobby state and return all players to lobby"""
	if not multiplayer.is_server():
		return
	
	print("[DevWorld] Resetting lobby state and returning all players...")
	
	# Reset all player states in NetworkManager
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		for player_id in network_manager.players:
			var player_data = network_manager.players[player_id]
			# Reset character selection and ready state
			player_data["char_index"] = -1
			player_data["ready"] = false
			# Remove role assignment
			if player_data.has("role"):
				player_data.erase("role")
		
		# Sync updated player data
		if network_manager.has_method("_sync_players_to_all"):
			network_manager._sync_players_to_all()
	
	# Return all clients to lobby
	_return_all_to_lobby.rpc()

@rpc("authority", "call_local", "reliable")
func _return_all_to_lobby():
	"""RPC to return all players to lobby wait room"""
	print("[DevWorld] Returning to lobby wait room...")
	SceneChanger.change_scene_to_file("res://scenes/UI/Lobby_Wait_Room/lobby_wait_room_menu.tscn")
