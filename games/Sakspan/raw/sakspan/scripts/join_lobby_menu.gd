#res://scenes/UI/join_Lobby/join_lobby_menu.tscn
# join_lobby_menu.gd
extends Control

@onready var lobby_list: Tree = $PanelContainer/MarginContainer/VBoxContainer/LobbyList
@onready var refresh_button: Button = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/RefreshButton
@onready var join_selected_button: Button = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/JoinSelectedButton
@onready var back_button: Button = $PanelContainer/MarginContainer/VBoxContainer/BackButton
@onready var room_code_line_edit: LineEdit = $PanelContainer/MarginContainer/VBoxContainer/CodeJoinHBox/RoomCodeLineEdit
@onready var join_with_code_button: Button = $PanelContainer/MarginContainer/VBoxContainer/CodeJoinHBox/JoinWithCodeButton

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
	# Double-click/Enter on a lobby row to join
	lobby_list.item_activated.connect(func(): _on_join_selected_button_pressed())
	join_with_code_button.pressed.connect(_on_join_with_code_button_pressed)

	# SAFETY: Ensure we are not accidentally still hosting from a prior scene
	multiplayer.multiplayer_peer = null
	NetworkManager.stop_lan_discovery()

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
	print("[JoinLobby] Refresh clicked: restarting LAN discovery...")
	NetworkManager.stop_lan_discovery()
	NetworkManager.start_listening_for_lobbies()

func _on_join_selected_button_pressed():
	var selected_item = lobby_list.get_selected()
	if not selected_item: return

	var ip_to_join = selected_item.get_metadata(0)
	var room_name = selected_item.get_text(0)
	var room_code = selected_item.get_text(1)
	var player_name = "Player" + str(randi_range(1000, 9999)) # Generate random name

	# Prefer the host_ip from the selected lobby info if present
	if _selected_lobby_info.has("host_ip"):
		ip_to_join = String(_selected_lobby_info["host_ip"])
	# Sanitize and validate IP
	if typeof(ip_to_join) != TYPE_STRING:
		ip_to_join = String(ip_to_join)
	ip_to_join = ip_to_join.strip_edges()
	if not _is_valid_lan_ipv4(ip_to_join):
		print("[JoinLobby] Refusing to join non-LAN or invalid IP:", ip_to_join)
		return

	# Stop discovery and clear any existing peers for a clean connect
	NetworkManager.stop_lan_discovery()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null

	print("[JoinLobby] Joining room '%s' (Code: %s) at %s" % [room_name, room_code, ip_to_join])
	NetworkManager.join_lobby(player_name, ip_to_join)
	join_selected_button.disabled = true
	join_selected_button.text = "CONNECTING..."
	refresh_button.disabled = true

func _on_join_with_code_button_pressed():
	var code = room_code_line_edit.text.strip_edges().to_upper()
	if code.length() != 6:
		print("[JoinLobby] Invalid room code format.")
		# Optionally, provide visual feedback to the user here
		return
	
	print("[JoinLobby] Searching for lobby with code: ", code)
	NetworkManager.find_lobby_by_code(code)

func _on_back_button_pressed():
	SceneChanger.change_scene_to_file("res://scenes/UI/Multiplayer/multiplayer_menu.tscn")

func _on_lobby_list_item_selected():
	join_selected_button.disabled = lobby_list.get_selected() == null
	if lobby_list.get_selected() != null:
		var ip = lobby_list.get_selected().get_metadata(0)
		if _found_lobbies.has(ip):
			_selected_lobby_info = _found_lobbies[ip]

# --- NetworkManager Signal Handlers ---

func _on_lobby_found(info: Dictionary):
	# When NetworkManager finds a lobby, add or update it in our dictionary
	# Prefer the host's provided IP if available
	var ip := String(info.get("host_ip", info.get("ip", "")))
	if not _is_valid_lan_ipv4(ip):
		print("[JoinLobby] Ignoring non-LAN or invalid IP:", ip)
		return
	info["ip"] = ip
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
		var info: Dictionary = _found_lobbies[ip]
		var ts: int = int(info.get("timestamp", 0))
		if ts > 0 and now - ts > 3000: # 3 seconds
			ips_to_remove.append(ip)
			
	if not ips_to_remove.is_empty():
		for ip in ips_to_remove:
			_found_lobbies.erase(ip)
		_update_lobby_list_ui()

func _update_lobby_list_ui():
	lobby_list.clear()
	var root = lobby_list.create_item()

	for ip in _found_lobbies:
		var info: Dictionary = _found_lobbies[ip]
		var item = lobby_list.create_item(root)
		item.set_text(0, String(info.get("name", "Unknown Room")))
		item.set_text(1, String(info.get("room_code", "N/A")))
		item.set_text(2, "%d/%d" % [int(info.get("current_players", 0)), int(info.get("max_players", 0))])
		item.set_text(3, String(info.get("timer", "5 minutes")))
		
		# Set status with color coding
		var status = String(info.get("status", "waiting"))
		item.set_text(4, status.capitalize())
		if status == "full":
			item.set_custom_color(4, Color.RED)
		else:
			item.set_custom_color(4, Color.GREEN)
		
		item.set_metadata(0, ip) # Store the IP address

func _configure_lobby_list_columns():
	lobby_list.set_columns(5)
	lobby_list.set_column_title(0, "Room Name")
	lobby_list.set_column_title(1, "Room Code")
	lobby_list.set_column_title(2, "Players")
	lobby_list.set_column_title(3, "Timer")
	lobby_list.set_column_title(4, "Status")
	lobby_list.hide_root = true

# --- IP Utilities ---
func _is_valid_lan_ipv4(addr: String) -> bool:
	if addr.is_empty():
		return false
	if not addr.is_valid_ip_address():
		return false
	# Exclude loopback, APIPA, invalid and common virtual adapter ranges
	if addr.begins_with("127.") or addr == "0.0.0.0" or addr.begins_with("169.254."):
		return false
	if addr.begins_with("192.168.56."):
		return false
	# Accept typical LAN ranges
	if addr.begins_with("192.168.") or addr.begins_with("10."):
		return true
	if addr.begins_with("172."):
		var parts := addr.split(".")
		if parts.size() >= 2:
			var second := int(parts[1])
			if second >= 16 and second <= 31:
				return true
	return false
