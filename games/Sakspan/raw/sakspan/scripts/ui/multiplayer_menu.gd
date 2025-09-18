# res://scripts/ui/multiplayer_menu.gd
extends Control

# UI Node References
@onready var host_button: Button = $VBoxContainer/HostButton
@onready var join_button: Button = $VBoxContainer/JoinButton
@onready var player_name_input: LineEdit = $VBoxContainer/PlayerNameInput
@onready var lobby_name_input: LineEdit = $VBoxContainer/LobbySettings/LobbyNameInput
@onready var max_players_spinbox: SpinBox = $VBoxContainer/LobbySettings/MaxPlayersSpinBox
@onready var timer_option: OptionButton = $VBoxContainer/LobbySettings/TimerOption
@onready var ip_input: LineEdit = $VBoxContainer/JoinSettings/IPInput
@onready var lobby_settings: VBoxContainer = $VBoxContainer/LobbySettings
@onready var join_settings: VBoxContainer = $VBoxContainer/JoinSettings
@onready var discovered_lobbies_list: ItemList = $VBoxContainer/DiscoveredLobbies/LobbyList
@onready var refresh_button: Button = $VBoxContainer/DiscoveredLobbies/RefreshButton
@onready var status_label: Label = $VBoxContainer/StatusLabel

var is_hosting_mode: bool = false
var discovered_lobbies: Dictionary = {}

func _ready():
	# Connect UI signals
	if host_button:
		host_button.pressed.connect(_on_host_button_pressed)
	if join_button:
		join_button.pressed.connect(_on_join_button_pressed)
	if refresh_button:
		refresh_button.pressed.connect(_on_refresh_button_pressed)
	if discovered_lobbies_list:
		discovered_lobbies_list.item_selected.connect(_on_lobby_selected)
		discovered_lobbies_list.item_activated.connect(_on_lobby_activated)
	
	# Connect NetworkManager signals
	if NetworkManager:
		NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
		NetworkManager.connection_failed.connect(_on_connection_failed)
		NetworkManager.lobby_found.connect(_on_lobby_found)
	
	# Initialize UI
	_setup_ui()
	_load_saved_settings()
	
	# Start listening for lobbies
	NetworkManager.start_listening_for_lobbies()

func _setup_ui():
	# Setup timer options
	if timer_option:
		timer_option.clear()
		timer_option.add_item("3 minutes")
		timer_option.add_item("5 minutes")
		timer_option.add_item("10 minutes")
		timer_option.add_item("15 minutes")
		timer_option.selected = 1  # Default to 5 minutes
	
	# Setup max players
	if max_players_spinbox:
		max_players_spinbox.min_value = 2
		max_players_spinbox.max_value = 5
		max_players_spinbox.value = 4
	
	# Initially hide both settings panels
	if lobby_settings:
		lobby_settings.visible = false
	if join_settings:
		join_settings.visible = false
	
	# Set default values
	if lobby_name_input:
		lobby_name_input.text = "My Lobby"
	if ip_input:
		ip_input.text = "127.0.0.1"
	
	_update_status("Ready to play!")

func _load_saved_settings():
	# Load player name from NetworkManager
	if player_name_input and NetworkManager:
		var saved_name = NetworkManager.get_local_player_name()
		if not saved_name.is_empty():
			player_name_input.text = saved_name
		else:
			player_name_input.text = NetworkManager.randomize_local_player_name()

func _on_host_button_pressed():
	if is_hosting_mode:
		_start_hosting()
	else:
		_show_host_settings()

func _on_join_button_pressed():
	if not is_hosting_mode:
		_join_lobby_by_ip()
	else:
		_show_join_settings()

func _show_host_settings():
	is_hosting_mode = true
	if lobby_settings:
		lobby_settings.visible = true
	if join_settings:
		join_settings.visible = false
	if host_button:
		host_button.text = "CREATE LOBBY"
	if join_button:
		join_button.text = "JOIN INSTEAD"
	_update_status("Configure your lobby settings")

func _show_join_settings():
	is_hosting_mode = false
	if lobby_settings:
		lobby_settings.visible = false
	if join_settings:
		join_settings.visible = true
	if host_button:
		host_button.text = "HOST INSTEAD"
	if join_button:
		join_button.text = "JOIN LOBBY"
	_update_status("Enter IP address or select from discovered lobbies")
	_refresh_lobbies()

func _start_hosting():
	var player_name = player_name_input.text.strip_edges() if player_name_input else ""
	var lobby_name = lobby_name_input.text.strip_edges() if lobby_name_input else "My Lobby"
	var max_players = int(max_players_spinbox.value) if max_players_spinbox else 4
	var timer_setting = timer_option.get_item_text(timer_option.selected) if timer_option else "5 minutes"
	
	if player_name.is_empty():
		_update_status("Please enter a player name!")
		return
	
	# Save player name
	NetworkManager.set_local_player_name(player_name)
	
	_update_status("Creating lobby...")
	_disable_ui()
	
	# Create the lobby
	NetworkManager.create_lobby(player_name, lobby_name, max_players, timer_setting)

func _join_lobby_by_ip():
	var player_name = player_name_input.text.strip_edges() if player_name_input else ""
	var ip = ip_input.text.strip_edges() if ip_input else ""
	
	if player_name.is_empty():
		_update_status("Please enter a player name!")
		return
	
	if ip.is_empty():
		_update_status("Please enter an IP address!")
		return
	
	# Save player name
	NetworkManager.set_local_player_name(player_name)
	
	_update_status("Joining lobby at " + ip + "...")
	_disable_ui()
	
	# Join the lobby
	NetworkManager.join_lobby(player_name, ip)

func _on_refresh_button_pressed():
	_refresh_lobbies()

func _refresh_lobbies():
	_update_status("Searching for lobbies...")
	discovered_lobbies.clear()
	if discovered_lobbies_list:
		discovered_lobbies_list.clear()
	
	# Restart discovery
	NetworkManager.stop_lan_discovery()
	NetworkManager.start_listening_for_lobbies()

func _on_lobby_found(lobby_data: Dictionary):
	var ip = lobby_data.get("host_ip", "")
	if ip.is_empty():
		return
	
	discovered_lobbies[ip] = lobby_data
	_update_lobbies_list()

func _update_lobbies_list():
	if not discovered_lobbies_list:
		return
		
	discovered_lobbies_list.clear()
	
	for ip in discovered_lobbies:
		var lobby = discovered_lobbies[ip]
		var name = lobby.get("name", "Unknown Lobby")
		var current_players = lobby.get("current_players", 0)
		var max_players = lobby.get("max_players", 5)
		var status = lobby.get("status", "waiting")
		
		var display_text = "%s (%d/%d) - %s" % [name, current_players, max_players, status]
		discovered_lobbies_list.add_item(display_text)

func _on_lobby_selected(index: int):
	# Update IP input with selected lobby's IP
	var lobby_ips = discovered_lobbies.keys()
	if index < lobby_ips.size() and ip_input:
		ip_input.text = lobby_ips[index]

func _on_lobby_activated(index: int):
	# Double-click to join
	_on_lobby_selected(index)
	_join_lobby_by_ip()

func _on_connection_succeeded():
	_update_status("Connected! Loading lobby...")
	# Switch to lobby wait room
	SceneChanger.change_scene_to_file("res://scenes/UI/Lobby_Wait_Room/lobby_wait_room_menu.tscn")

func _on_connection_failed():
	_update_status("Connection failed! Please try again.")
	_enable_ui()

func _update_status(message: String):
	if status_label:
		status_label.text = message
	print("[MultiplayerMenu] " + message)

func _disable_ui():
	if host_button:
		host_button.disabled = true
	if join_button:
		join_button.disabled = true
	if refresh_button:
		refresh_button.disabled = true

func _enable_ui():
	if host_button:
		host_button.disabled = false
	if join_button:
		join_button.disabled = false
	if refresh_button:
		refresh_button.disabled = false

func _exit_tree():
	# Clean up discovery when leaving
	if NetworkManager:
		NetworkManager.stop_lan_discovery()
