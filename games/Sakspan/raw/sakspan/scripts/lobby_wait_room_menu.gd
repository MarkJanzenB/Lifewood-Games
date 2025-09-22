# lobby_wait_room_menu.gd
extends Control

# --- SCENE REFERENCES (PATHS) ---
# These paths are based on your screenshot. Double-check them if you have issues.
@onready var lobby_name_label: Label = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/LobbyNameLabel
@onready var players_count_label: Label = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/PlayersCountLabel
@onready var timer_label: Label = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/GameTimerLabel
@onready var player_list_container: VBoxContainer = $PanelContainer/MarginContainer/VBoxContainer/ScrollContainer/PlayerListContainer
@onready var character_grid: GridContainer = $PanelContainer/MarginContainer/VBoxContainer/CharacterGrid
@onready var root_vbox: VBoxContainer = $PanelContainer/MarginContainer/VBoxContainer
@onready var lock_in_button: Button = $PanelContainer/MarginContainer/VBoxContainer/LockInButton
@onready var start_game_button: Button = $PanelContainer/MarginContainer/VBoxContainer/StartGameButton
#@onready var dev_test_button: Button = $PanelContainer/MarginContainer/VBoxContainer/DevTestButton
@onready var leave_lobby_button: Button = $PanelContainer/MarginContainer/VBoxContainer/LeaveLobbyButton
var _heartbeat_timer := Timer.new()

# --- RESOURCES ---
# [!!! IMPORTANT: YOU MUST FIX THIS LINE !!!]
# In the Godot editor, find your "CharacterButton.tscn" file in the FileSystem panel.
# Drag that file and drop it between the parentheses of preload() below.
const CharacterButtonScene = preload("res://scenes/UI/character_button.tscn")

# Make sure these paths to your character images are correct.
const CHARACTER_ICONS := [
	preload("res://scenes/UI/Lobby_Wait_Room/pink_char.png"),
	preload("res://scenes/UI/Lobby_Wait_Room/red_char.png"),
	preload("res://scenes/UI/Lobby_Wait_Room/blue_char.png"),
	preload("res://scenes/UI/Lobby_Wait_Room/green_char.png"),
	preload("res://scenes/UI/Lobby_Wait_Room/yellow_char.png"),
]

# --- LOBBY STATE VARIABLES ---
var selected_char_index: int = -1
var locked_in: bool = false
var is_host: bool = false
var lobby_data: Dictionary = {}
var selection_label: Label = null

const CHARACTER_NAMES := ["Pink", "Red", "Blue", "Green", "Yellow"]

# --- STATE VARIABLES ---
var _is_host: bool = false
var _lobby_data: Dictionary = {}
var _players_in_lobby: Dictionary = {} # { peer_id: { name, is_host, ready, char_index } }
var _my_peer_id: int
var _my_temp_selection_index: int = -1

func _ready():
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("reset_to_lobby"):
		game_manager.reset_to_lobby()
	
	# Safety: ensure fullscreen background never intercepts mouse
	var bg := get_node_or_null("../lobby_wait_room_background") as Control
	if bg:
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	_check_ui_nodes()
	_resolve_nodes_if_missing()
	
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		# Access via the node instance to avoid symbol conflicts
		_lobby_data = network_manager.my_lobby_data if network_manager.my_lobby_data != null else {}
		_players_in_lobby = network_manager.players if network_manager.players != null else {}
		if not network_manager.player_list_changed.is_connected(_on_player_list_changed):
			network_manager.player_list_changed.connect(_on_player_list_changed)
		if not network_manager.game_started.is_connected(_on_game_started):
			network_manager.game_started.connect(_on_game_started)
		# Update header when lobby data is synced from host
		if not network_manager.lobby_data_changed.is_connected(func(_d: Dictionary): pass):
			network_manager.lobby_data_changed.connect(func(data: Dictionary):
				lobby_data = data
				if lobby_name_label:
					var nm := String(lobby_data.get("name", ""))
					if nm.is_empty():
						lobby_name_label.text = _compose_lobby_title("Loading...")
					else:
						lobby_name_label.text = _compose_lobby_title(nm)
			)
		# Proactively request resyncs on entering the Wait Room
		if network_manager.has_method("request_lobby_resync"):
			network_manager.request_lobby_resync()
		if network_manager.has_method("request_players_resync"):
			network_manager.request_players_resync()
	if start_game_button:
		start_game_button.pressed.connect(_on_start_game_button_pressed)
	#if dev_test_button:
		#dev_test_button.pressed.connect(_on_dev_test_button_pressed)
	if lock_in_button:
		lock_in_button.pressed.connect(_on_lock_in_button_pressed)
	if leave_lobby_button:
		leave_lobby_button.pressed.connect(_on_leave_lobby_button_pressed)
	# Default focus to Lock In for immediate keyboard navigation
	if lock_in_button:
		lock_in_button.grab_focus()

	# Initialize from NetworkManager by default; may be overridden via _initialize_lobby
	lobby_data = (get_node_or_null("/root/NetworkManager") as Node).my_lobby_data if get_node_or_null("/root/NetworkManager") else {}
	is_host = multiplayer.is_server()
	if lobby_name_label:
		var nm := String(lobby_data.get("name", ""))
		if nm.is_empty():
			lobby_name_label.text = _compose_lobby_title("Loading...")
		else:
			lobby_name_label.text = _compose_lobby_title(nm)

	# Ensure a label exists above the character grid to show selections
	selection_label = root_vbox.get_node_or_null("SelectionNameLabel") as Label
	if not selection_label:
		selection_label = Label.new()
		selection_label.name = "SelectionNameLabel"
		selection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		selection_label.text = "No selection yet"
		root_vbox.add_child(selection_label)
		# Move it above the CharacterGrid
		var idx = root_vbox.get_children().find(character_grid)
		if idx != -1:
			root_vbox.move_child(selection_label, idx)
	
	_update_player_list(NetworkManager.players)
	_setup_character_grid()
	_update_start_game_button()

	# Heartbeat refresh in case signals are missed; keeps UI in sync
	_heartbeat_timer.wait_time = 0.5  # More frequent updates
	_heartbeat_timer.timeout.connect(func():
		_update_player_list(NetworkManager.players)
		_update_start_game_button()
		_update_character_grid_lock(NetworkManager.players))
	add_child(_heartbeat_timer)
	_heartbeat_timer.start()


# --- SETUP AND CHECKS ---
func _check_ui_nodes():
	if not lobby_name_label: push_warning("[LobbyWaitRoom] LobbyNameLabel not found.")
	if not players_count_label: push_warning("[LobbyWaitRoom] PlayersCountLabel not found.")
	if not timer_label: push_warning("[LobbyWaitRoom] TimerLabel not found.")
	if not player_list_container: push_warning("[LobbyWaitRoom] PlayerListContainer not found.")
	if not character_grid: push_warning("[LobbyWaitRoom] CharacterGrid not found.")
	if not lock_in_button: push_warning("[LobbyWaitRoom] LockInButton not found.")
	if not start_game_button: push_warning("[LobbyWaitRoom] StartGameButton not found.")
	if not leave_lobby_button: push_warning("[LobbyWaitRoom] LeaveLobbyButton not found.")

func _resolve_nodes_if_missing():
	# Fallback: try to find nodes by name anywhere under this scene if direct paths changed
	if not players_count_label:
		players_count_label = _find_node_by_name(self, "PlayersCountLabel") as Label
	if not timer_label:
		timer_label = _find_node_by_name(self, "TimerLabel") as Label
	if not lobby_name_label:
		lobby_name_label = _find_node_by_name(self, "LobbyNameLabel") as Label
	if not player_list_container:
		player_list_container = _find_node_by_name(self, "PlayerListContainer") as VBoxContainer
	if not character_grid:
		character_grid = _find_node_by_name(self, "CharacterGrid") as GridContainer
	if not lock_in_button:
		lock_in_button = _find_node_by_name(self, "LockInButton") as Button
	if not start_game_button:
		start_game_button = _find_node_by_name(self, "StartGameButton") as Button
	if not leave_lobby_button:
		leave_lobby_button = _find_node_by_name(self, "LeaveLobbyButton") as Button

func _find_node_by_name(root: Node, target: String) -> Node:
	if root.name == target:
		return root
	for child in root.get_children():
		var n = _find_node_by_name(child, target)
		if n: return n
	return null

# This function now correctly uses your custom CharacterButton scene.
func _setup_character_grid():
	if not character_grid: return
	for child in character_grid.get_children():
		child.queue_free()
	# Make the grid visually larger and nicely spaced
	character_grid.columns = CHARACTER_ICONS.size()
	character_grid.add_theme_constant_override("h_separation", 24)
	character_grid.add_theme_constant_override("v_separation", 24)
	
	for i in range(CHARACTER_ICONS.size()):
		var btn = CharacterButtonScene.instantiate()
		btn.set_character(CHARACTER_ICONS[i], i)
		btn.character_selected.connect(_on_character_selected)
		character_grid.add_child(btn)
		# Try to enlarge buttons
		if btn.has_method("set_custom_minimum_size"):
			btn.custom_minimum_size = Vector2(96, 96)
		elif "custom_minimum_size" in btn:
			btn.custom_minimum_size = Vector2(96, 96)
		else:
			btn.scale = Vector2(1.5, 1.5)


# --- UI UPDATE AND SIGNAL HANDLER FUNCTIONS ---
func _on_character_selected(idx: int):
	if locked_in: 
		print("[LobbyWaitRoom] Character selection ignored - already locked in")
		return
		
	selected_char_index = idx
	_update_character_grid_highlight()
	
	# Update selection label for local feedback before locking in
	if selection_label:
		var cname: String = CHARACTER_NAMES[idx] if (idx >= 0 and idx < CHARACTER_NAMES.size()) else "#%d" % idx
		selection_label.text = "You selected: %s (press LOCK IN to confirm)" % cname
	
	print("[LobbyWaitRoom] Selected character index=", idx, " (", CHARACTER_NAMES[idx], ")")
	print("[LobbyWaitRoom] My player ID: ", multiplayer.get_unique_id())
	print("[LobbyWaitRoom] Is server: ", multiplayer.is_server())

# This function now correctly uses the custom "set_selected" method on your buttons.
func _update_character_grid_highlight():
	if not character_grid: return
	for i in range(character_grid.get_child_count()):
		# The "as CharacterButton" cast now works because of "class_name".
		var btn = character_grid.get_child(i) as LobbyCharacterButton
		if btn:
			btn.set_selected(i == selected_char_index)

func _update_character_grid_lock(players: Dictionary):
	if not character_grid: return
	var picked: Array[int] = []
	var picked_by := {}
	for id in players:
		var idx = int(players[id].get("char_index", -1))
		if idx >= 0:
			picked.append(idx)
			picked_by[idx] = String(players[id].get("name", str(id)))
			
	var my_id: int = multiplayer.get_unique_id()
	var my_char: int = -1
	if players.has(my_id):
		my_char = int(players[my_id].get("char_index", -1))
		
	for i in range(character_grid.get_child_count()):
		var btn = character_grid.get_child(i)
		btn.disabled = (i in picked and i != my_char)
		# Show who selected this character (tooltip)
		if i in picked_by:
			btn.tooltip_text = "Selected by %s" % String(picked_by[i])
		else:
			btn.tooltip_text = ""

func _update_player_list(players: Dictionary):
	if not player_list_container:
		return
	for c in player_list_container.get_children():
		c.queue_free()

	var count := 0
	for id in players:
		var p: Dictionary = players[id]
		var label := Label.new()
		var p_name: String = p.get("name", "Player %s" % str(id))
		var p_char: int = int(p.get("char_index", -1))
		var p_is_host: bool = bool(p.get("is_host", false))
		
		# Show character selection status
		var char_text := " - Selecting..."
		if p_char >= 0 and p_char < CHARACTER_NAMES.size():
			char_text = " - " + CHARACTER_NAMES[p_char] + " ✓"
		
		var host_text := " [HOST]" if p_is_host else ""
		
		# Color code the text based on ready status
		label.text = "%s%s%s" % [p_name, host_text, char_text]
		if p_char >= 0:
			label.modulate = Color.GREEN  # Ready players in green
		else:
			label.modulate = Color.YELLOW  # Selecting players in yellow
			
		player_list_container.add_child(label)
		count += 1

	if players_count_label:
		players_count_label.text = "Players: %d/%d" % [count, lobby_data.get("max_players", 5)]
	
	# Update timer display
	if timer_label:
		var timer_setting = lobby_data.get("timer", "Default")
		timer_label.text = "Timer: " + str(timer_setting)

# NOTE: Removed duplicate alternate implementations of _setup_character_grid and
# _update_character_grid_lock that conflicted with the CharacterButton-based grid above.

func _update_start_game_button():
	if not start_game_button: return
	start_game_button.disabled = true
	if is_host:
		var players = NetworkManager.players
		var ready_count = 0
		for id in players:
			if int(players[id].get("char_index", -1)) >= 0:
				ready_count += 1
		if players.size() >= 2 and ready_count == players.size():
			start_game_button.disabled = false
			start_game_button.tooltip_text = ""
	else:
		start_game_button.disabled = true

	# Helpful tooltip why disabled
	if start_game_button.disabled:
		if is_host:
			start_game_button.tooltip_text = "Waiting for all players to lock in (min 2 players)."
		else:
			start_game_button.tooltip_text = "Only the host can start the game."

# NOTE: Removed unused _on_char_button_pressed; grid uses CharacterButton signals.

# --- BUTTON PRESS AND NETWORKING ---
func _on_lock_in_button_pressed():
	# Toggle behavior: Lock in -> Unlock, Unlock -> Lock in
	if not locked_in:
		if selected_char_index == -1: 
			_update_status("Please select a character first!")
			return
		
		var character_name = CHARACTER_NAMES[selected_char_index] if selected_char_index < CHARACTER_NAMES.size() else "Unknown"
		print("[LobbyWaitRoom] === LOCK IN BUTTON PRESSED ===")
		print("[LobbyWaitRoom] Locking in character: ", character_name, " (index ", selected_char_index, ")")
		print("[LobbyWaitRoom] My player ID: ", multiplayer.get_unique_id())
		print("[LobbyWaitRoom] Is server: ", multiplayer.is_server())
		print("[LobbyWaitRoom] Multiplayer peer: ", multiplayer.multiplayer_peer)
		print("[LobbyWaitRoom] Connected peers: ", multiplayer.get_peers())
		print("[LobbyWaitRoom] Current NetworkManager players before lock-in: ", NetworkManager.players)
		
		print("[LobbyWaitRoom] Calling NetworkManager.request_char_selection(", selected_char_index, ")")
		NetworkManager.request_char_selection(selected_char_index)
		print("[LobbyWaitRoom] NetworkManager.request_char_selection() call completed")
		
		locked_in = true
		lock_in_button.text = "UNLOCK"
		
		# Disable other character buttons
		for i in range(character_grid.get_child_count()):
			var btn = character_grid.get_child(i)
			if i != selected_char_index:
				btn.disabled = true
		
		# Update selection label
		if selection_label:
			selection_label.text = "Locked in as: " + character_name + " ✓"
		
		# Force immediate UI refresh
		await get_tree().process_frame
		_update_player_list(NetworkManager.players)
		_update_start_game_button()
		NetworkManager.request_players_resync()
	else:
		# Unlock request
		print("[LobbyWaitRoom] Unlocking character selection")
		NetworkManager.request_unlock()
		locked_in = false
		lock_in_button.text = "LOCK IN"
		
		# Re-enable all character buttons
		for i in range(character_grid.get_child_count()):
			var btn = character_grid.get_child(i)
			btn.disabled = false
		
		# Update selection label
		if selection_label:
			var character_name = CHARACTER_NAMES[selected_char_index] if selected_char_index < CHARACTER_NAMES.size() else "Unknown"
			selection_label.text = "You selected: " + character_name + " (press LOCK IN to confirm)"
		
		_update_character_grid_highlight()
		NetworkManager.request_players_resync()

	_update_start_game_button()

func _update_status(message: String):
	print("[LobbyWaitRoom] ", message)
	# You can add a status label to show messages to the player if needed

# Debug function to manually refresh UI
func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F5:
			print("[LobbyWaitRoom] F5 pressed - Manual UI refresh")
			print("[LobbyWaitRoom] Current players: ", NetworkManager.players)
			_update_player_list(NetworkManager.players)
			_update_character_grid_lock(NetworkManager.players)
			_update_start_game_button()

func _on_player_list_changed(players: Dictionary):
	print("[LobbyWaitRoom] === PLAYER LIST CHANGED ===")
	print("[LobbyWaitRoom] Player list changed: ", players)
	print("[LobbyWaitRoom] Called on: ", "Host" if multiplayer.is_server() else "Client")
	print("[LobbyWaitRoom] My player ID: ", multiplayer.get_unique_id())
	print("[LobbyWaitRoom] Signal source: ", get_stack()[1] if get_stack().size() > 1 else "Unknown")
	
	# Debug: Print each player's character selection status
	for id in players:
		var char_index = int(players[id].get("char_index", -1))
		var name = players[id].get("name", "Unknown")
		var is_host = players[id].get("is_host", false)
		var status = "Selecting..." if char_index == -1 else CHARACTER_NAMES[char_index] + " ✓"
		var is_me = (id == multiplayer.get_unique_id())
		print("[LobbyWaitRoom] Player ", id, " (", name, ") ", "[HOST] " if is_host else "", "[ME] " if is_me else "", "char_index: ", char_index, " -> ", status)
	
	# Update local state if this is our character selection
	var my_id = multiplayer.get_unique_id()
	if players.has(my_id):
		var my_char_index = int(players[my_id].get("char_index", -1))
		if my_char_index >= 0 and my_char_index != selected_char_index:
			print("[LobbyWaitRoom] Updating local character selection from server: ", my_char_index)
			selected_char_index = my_char_index
			locked_in = true
			lock_in_button.text = "UNLOCK"
			_update_character_grid_highlight()
			
			# Update selection label
			if selection_label:
				var character_name = CHARACTER_NAMES[selected_char_index] if selected_char_index < CHARACTER_NAMES.size() else "Unknown"
				selection_label.text = "Locked in as: " + character_name + " ✓"
		elif my_char_index == -1 and locked_in:
			print("[LobbyWaitRoom] Character unlocked by server")
			locked_in = false
			lock_in_button.text = "LOCK IN"
			if selection_label and selected_char_index >= 0:
				var character_name = CHARACTER_NAMES[selected_char_index] if selected_char_index < CHARACTER_NAMES.size() else "Unknown"
				selection_label.text = "You selected: " + character_name + " (press LOCK IN to confirm)"
	
	_update_player_list(players)
	_update_start_game_button()
	_update_character_grid_lock(players)
	_update_selection_label_from_players(players)

func _update_selection_label_from_players(players: Dictionary):
	if not selection_label: return
	var entries: Array[String] = []
	for id in players:
		var name := String(players[id].get("name", str(id)))
		var idx := int(players[id].get("char_index", -1))
		if idx >= 0:
			var cname: String = CHARACTER_NAMES[idx] if (idx >= 0 and idx < CHARACTER_NAMES.size()) else "#%d" % idx
			entries.append("%s → %s" % [name, cname])
	if entries.is_empty():
		selection_label.text = "No one locked in yet"
	else:
		selection_label.text = ", ".join(entries)

func _on_start_game_button_pressed():
	if is_host:
		print("[LobbyWaitRoom] Start Game pressed by host. Sending RPC...")
		NetworkManager.start_game()

func _on_dev_test_button_pressed():
	if is_host:
		print("[LobbyWaitRoom] Host starting dev test. Syncing to all clients...")
		_start_dev_test.rpc()
	else:
		print("[LobbyWaitRoom] Only host can start dev test.")

@rpc("authority", "call_local", "reliable")
func _start_dev_test():
	print("[LobbyWaitRoom] Loading dev world...")
	SceneChanger.change_scene_to_file("res://scenes/dev/dev_world.tscn")

func _on_game_started(_player_data):
	print("[LobbyWaitRoom] game_started received. Loading world.tscn...")
	# FIXED: Use NetworkManager's scene selection logic instead of hardcoded path
	# This respects the USE_DEV_TEST_TEMP flag and loads dev_world.tscn when enabled
	var target_scene: String = NetworkManager.DEV_TEST_SCENE_PATH if NetworkManager.USE_DEV_TEST_TEMP else NetworkManager.WORLD_SCENE_PATH
	print("[LobbyWaitRoom] Target scene: ", target_scene)
	get_tree().change_scene_to_file(target_scene)

func _on_leave_lobby_button_pressed():
	NetworkManager.leave_lobby()
	SceneChanger.change_scene_to_file("res://scenes/UI/Multiplayer/multiplayer_menu.tscn")


# --- OPTIONAL INITIALIZER CALLED BY SceneChanger ---
# Allows passing lobby info and host flag when switching to this scene
func _initialize_lobby(info: Dictionary, host: bool):
	# Some callers pass { "lobby_info": {...}, "is_host": <bool> }
	if info.has("lobby_info") and typeof(info["lobby_info"]) == TYPE_DICTIONARY:
		lobby_data = info["lobby_info"]
	else:
		lobby_data = info
	is_host = host
	if lobby_name_label:
		var nm := String(lobby_data.get("name", ""))
		if nm.is_empty():
			lobby_name_label.text = _compose_lobby_title("Loading...")
		else:
			lobby_name_label.text = _compose_lobby_title(nm)
	_update_player_list(NetworkManager.players)
	_update_start_game_button()

# Compose lobby title with host IP so others can join
func _compose_lobby_title(name: String) -> String:
	var room_code := String(lobby_data.get("room_code", ""))
	if room_code.is_empty():
		return "Lobby: %s" % name
	return "Lobby: %s    Code: %s" % [name, room_code]

# Removed _get_lan_ipv4 helper; composed inline above to avoid missing symbol issues.
