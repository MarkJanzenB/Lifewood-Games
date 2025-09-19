# res://scripts/dev/dev_world.gd
# Dev test world for multiplayer player interaction testing
extends Node2D

# Node references
@onready var players_container: Node2D = $PlayersContainer
@onready var multiplayer_spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var players_label: Label = $UI/InfoPanel/VBox/PlayersLabel
@onready var grid_lines: Node2D = $GridLines

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
	print("[DevWorld] Starting dev test world")
	
	# Ensure input actions exist
	_ensure_input_actions()
	
	# Configure multiplayer spawner
	_setup_multiplayer_spawner()
	
	# Draw grid for reference
	_draw_grid()
	
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
		var test_data = {"name": "TestPlayer_" + str(local_id)}
		_spawn_player_with_spawner(local_id, test_data)
	
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
	
	# Enable movement and set as main player if local
	player_instance.can_move = true
	player_instance.can_attack = true
	if is_local:
		player_instance.is_main_player = true
		print("[DevWorld] Set local player as main: ", player_name)
	
	# Call setup function if it exists
	if player_instance.has_method("setup_multiplayer_player"):
		player_instance.setup_multiplayer_player(player_info, is_local)
	
	# Set player color based on ID
	var colors = [Color.CYAN, Color.YELLOW, Color.MAGENTA, Color.GREEN, Color.ORANGE]
	var color_index = (player_id - 1) % colors.size()
	player_instance.modulate = colors[color_index]
	
	# Track spawned player
	spawned_players[player_id] = player_instance
	
	# Update UI
	_update_players_count()
	
	print("[DevWorld] Player spawned successfully with MultiplayerSpawner: ", player_id)

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
		
		# Set player name
		node.player_name = player_name
		
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
		players_label.text = "Players: " + str(count)
	
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

# Ensure input actions exist for player movement
func _ensure_input_actions():
	var actions = [
		{"name": "move_up", "key": KEY_W},
		{"name": "move_down", "key": KEY_S},
		{"name": "move_left", "key": KEY_A},
		{"name": "move_right", "key": KEY_D},
		{"name": "run", "key": KEY_SHIFT}
	]
	
	for action in actions:
		if not InputMap.has_action(action.name):
			InputMap.add_action(action.name)
			var event = InputEventKey.new()
			event.keycode = action.key
			InputMap.action_add_event(action.name, event)
			print("[DevWorld] Created input action: ", action.name)
