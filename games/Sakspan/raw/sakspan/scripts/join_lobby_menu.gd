# join_lobby_menu.gd
extends Control

@onready var lobby_list: Tree = $PanelContainer/MarginContainer/VBoxContainer/LobbyList
@onready var refresh_button: Button = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/RefreshButton
@onready var join_selected_button: Button = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/JoinSelectedButton
@onready var back_button: Button = $PanelContainer/MarginContainer/VBoxContainer/BackButton

# A dictionary to store found lobbies, keyed by their IP address
var _found_lobbies: Dictionary = {}
var _cleanup_timer := Timer.new()
var _selected_lobby_info: Dictionary = {}

func _ready():
	# --- Connect Signals ---
	refresh_button.pressed.connect(_on_refresh_button_pressed)
	join_selected_button.pressed.connect(_on_join_selected_button_pressed)
	back_button.pressed.connect(_on_back_button_pressed)
	lobby_list.item_selected.connect(_on_lobby_list_item_selected)

	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	# The new signal for LAN discovery
	NetworkManager.lobby_found.connect(_on_lobby_found)
	
	# --- UI and Logic Setup ---
	join_selected_button.disabled = true
	_configure_lobby_list_columns()
	
	# Timer to remove lobbies that are no longer broadcasting
	_cleanup_timer.wait_time = 3.0 # Lobbies older than 3s will be removed
	_cleanup_timer.timeout.connect(_on_cleanup_timer_timeout)
	add_child(_cleanup_timer)
	_cleanup_timer.start()

	# Tell the NetworkManager to start listening
	NetworkManager.start_listening_for_lobbies()

func _exit_tree():
	# CRITICAL: Stop listening when we leave this scene
	NetworkManager.stop_lan_discovery()

# --- UI Signal Handlers ---

func _on_refresh_button_pressed():
	# Clearing the list and waiting for new broadcasts acts as a refresh
	_found_lobbies.clear()
	_update_lobby_list_ui()
	print("Cleared lobby list, waiting for new broadcasts...")

func _on_join_selected_button_pressed():
	var selected_item = lobby_list.get_selected()
	if not selected_item: return

	var ip_to_join = selected_item.get_metadata(0)
	var player_name = "Joiner" # TODO: Get from global settings
	
	NetworkManager.join_lobby(player_name, ip_to_join)
	join_selected_button.disabled = true
	join_selected_button.text = "CONNECTING..."

func _on_back_button_pressed():
	SceneChanger.change_scene_to_file("res://scenes/UI/multiplayer_menu.tscn")

func _on_lobby_list_item_selected():
	join_selected_button.disabled = lobby_list.get_selected() == null
	if lobby_list.get_selected() != null:
		var ip = lobby_list.get_selected().get_metadata(0)
		if _found_lobbies.has(ip):
			_selected_lobby_info = _found_lobbies[ip]

# --- NetworkManager Signal Handlers ---

func _on_lobby_found(info: Dictionary):
	# When NetworkManager finds a lobby, add or update it in our dictionary
	var ip = info.ip
	info["timestamp"] = Time.get_ticks_msec() # Mark when we last heard from it
	_found_lobbies[ip] = info
	_update_lobby_list_ui()

func _on_connection_succeeded():
	var init := {"lobby_info": _selected_lobby_info, "is_host": false}
	SceneChanger.change_scene_to_file("res://scenes/UI/Lobby_Wait_Room/lobby_wait_room_menu.tscn", init)

func _on_connection_failed():
	print("Connection Failed!")
	join_selected_button.disabled = false
	join_selected_button.text = "JOIN"
	# TODO: Show an error message popup

# --- Helper Functions ---

func _on_cleanup_timer_timeout():
	var now = Time.get_ticks_msec()
	var ips_to_remove = []
	for ip in _found_lobbies:
		if now - _found_lobbies[ip].timestamp > 3000: # 3 seconds
			ips_to_remove.append(ip)
			
	if not ips_to_remove.is_empty():
		for ip in ips_to_remove:
			_found_lobbies.erase(ip)
		_update_lobby_list_ui()

func _update_lobby_list_ui():
	lobby_list.clear()
	var root = lobby_list.create_item()

	for ip in _found_lobbies:
		var info = _found_lobbies[ip]
		var item = lobby_list.create_item(root)
		item.set_text(0, info.name)
		item.set_text(1, "%d/%d" % [info.current_players, info.max_players])
		# item.set_text(2, info.timer) # Add this back if you send timer info
		item.set_text(3, "Waiting") # Or get real status from broadcast
		item.set_metadata(0, ip) # Store the IP address

func _configure_lobby_list_columns():
	lobby_list.set_columns(4)
	lobby_list.set_column_title(0, "Lobby Name")
	lobby_list.set_column_title(1, "Players")
	lobby_list.set_column_title(2, "Timer")
	lobby_list.set_column_title(3, "Status")
	lobby_list.hide_root = true
