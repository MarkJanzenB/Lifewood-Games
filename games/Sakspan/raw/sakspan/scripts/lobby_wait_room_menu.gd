# lobby_wait_room_menu.gd
extends Control

# --- SCENE REFERENCES (PATHS) ---
# These paths are based on your screenshot. Double-check them if you have issues.
@onready var lobby_name_label: Label = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/LobbyNameLabel
@onready var players_count_label: Label = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/PlayersCountLabel
@onready var player_list_container: VBoxContainer = $PanelContainer/MarginContainer/VBoxContainer/ScrollContainer/PlayerListContainer
@onready var character_grid: GridContainer = $PanelContainer/MarginContainer/VBoxContainer/CharacterGrid
@onready var root_vbox: VBoxContainer = $PanelContainer/MarginContainer/VBoxContainer
@onready var lock_in_button: Button = $PanelContainer/MarginContainer/VBoxContainer/LockInButton
@onready var start_game_button: Button = $PanelContainer/MarginContainer/VBoxContainer/StartGameButton
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
	if Engine.has_singleton("GameManager"):
		GameManager.reset_to_lobby()
	_check_ui_nodes()
	_resolve_nodes_if_missing()
	if Engine.has_singleton("NetworkManager"):
		# Access autoloaded NetworkManager directly
		_lobby_data = NetworkManager.my_lobby_data if NetworkManager.my_lobby_data != null else {}
		_players_in_lobby = NetworkManager.players if NetworkManager.players != null else {}
		NetworkManager.player_list_changed.connect(_on_player_list_changed)
		NetworkManager.game_started.connect(_on_game_started)
		# Update header when lobby data is synced from host
		NetworkManager.lobby_data_changed.connect(func(data: Dictionary):
			lobby_data = data
			if lobby_name_label:
				var nm := String(lobby_data.get("name", ""))
				if nm.is_empty():
					lobby_name_label.text = _compose_lobby_title("Loading...")
				else:
					lobby_name_label.text = _compose_lobby_title(nm)
		)
		# Proactively request resyncs on entering the Wait Room
		NetworkManager.request_lobby_resync()
		NetworkManager.request_players_resync()
	if start_game_button:
		start_game_button.pressed.connect(_on_start_game_button_pressed)
	if lock_in_button:
		lock_in_button.pressed.connect(_on_lock_in_button_pressed)
	if leave_lobby_button:
		leave_lobby_button.pressed.connect(_on_leave_lobby_button_pressed)

	# Initialize from NetworkManager by default; may be overridden via _initialize_lobby
	lobby_data = NetworkManager.my_lobby_data
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
	_heartbeat_timer.wait_time = 1.0
	_heartbeat_timer.timeout.connect(func():
		_update_player_list(NetworkManager.players)
		_update_start_game_button())
	add_child(_heartbeat_timer)
	_heartbeat_timer.start()


# --- SETUP AND CHECKS ---
func _check_ui_nodes():
	if not lobby_name_label: push_warning("[LobbyWaitRoom] LobbyNameLabel not found.")
	if not players_count_label: push_warning("[LobbyWaitRoom] PlayersCountLabel not found.")
	if not player_list_container: push_warning("[LobbyWaitRoom] PlayerListContainer not found.")
	if not character_grid: push_warning("[LobbyWaitRoom] CharacterGrid not found.")
	if not lock_in_button: push_warning("[LobbyWaitRoom] LockInButton not found.")
	if not start_game_button: push_warning("[LobbyWaitRoom] StartGameButton not found.")
	if not leave_lobby_button: push_warning("[LobbyWaitRoom] LeaveLobbyButton not found.")

func _resolve_nodes_if_missing():
	# Fallback: try to find nodes by name anywhere under this scene if direct paths changed
	if not players_count_label:
		players_count_label = _find_node_by_name(self, "PlayersCountLabel") as Label
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
	if locked_in: return
	selected_char_index = idx
	_update_character_grid_highlight()
	# Update selection label for local feedback before locking in
	if selection_label:
		var cname: String = CHARACTER_NAMES[idx] if (idx >= 0 and idx < CHARACTER_NAMES.size()) else "#%d" % idx
		selection_label.text = "You selected: %s (not locked in)" % cname
	print("[LobbyWaitRoom] Selected character index=", idx)

# This function now correctly uses the custom "set_selected" method on your buttons.
func _update_character_grid_highlight():
	if not character_grid: return
	for i in range(character_grid.get_child_count()):
		# The "as CharacterButton" cast now works because of "class_name".
		var btn = character_grid.get_child(i) as CharacterButton
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
		var char_text := " (Picking...)"
		if p_char >= 0:
			char_text = " (Ready)"
		var host_text := " (Host)" if p_is_host else ""
		label.text = "%s%s%s" % [p_name, host_text, char_text]
		player_list_container.add_child(label)
		count += 1

	if players_count_label:
		players_count_label.text = "Players: %d/%d" % [count, lobby_data.get("max_players", 5)]

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
		if selected_char_index == -1: return
		NetworkManager.request_char_selection(selected_char_index)
		locked_in = true
		lock_in_button.text = "UNLOCK"
		for i in range(character_grid.get_child_count()):
			var btn = character_grid.get_child(i)
			if i != selected_char_index:
				btn.disabled = true
		print("[LobbyWaitRoom] Lock in sent for index=", selected_char_index)
		NetworkManager.request_players_resync()
	else:
		# Unlock request
		NetworkManager.request_unlock()
		locked_in = false
		lock_in_button.text = "LOCK IN"
		for i in range(character_grid.get_child_count()):
			var btn = character_grid.get_child(i)
			btn.disabled = false
		_update_character_grid_highlight()
		print("[LobbyWaitRoom] Unlock requested")
		NetworkManager.request_players_resync()

	_update_start_game_button()

func _on_player_list_changed(players: Dictionary):
	_update_player_list(players)
	_update_start_game_button()
	if not locked_in:
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
		# Fallback: if for any reason the RPC/signal is delayed, transition locally too
		# (clients will still switch on game_started)
		SceneChanger.change_scene_to_file("res://scenes/world.tscn")

func _on_game_started(_player_data):
	print("[LobbyWaitRoom] game_started received. Loading world.tscn...")
	SceneChanger.change_scene_to_file("res://scenes/world.tscn")

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
