# res://scripts/dev/dev_test.gd
extends Control

@onready var name_line: LineEdit = $Panel/Margin/VBox/TopHBox/NameLine
@onready var ip_line: LineEdit = $Panel/Margin/VBox/TopHBox/IpLine
@onready var host_button: Button = $Panel/Margin/VBox/TopHBox/HostButton
@onready var join_button: Button = $Panel/Margin/VBox/TopHBox/JoinButton
@onready var leave_button: Button = $Panel/Margin/VBox/TopHBox/LeaveButton
@onready var test_world_button: Button = $Panel/Margin/VBox/TestWorldButton
@onready var players_label: Label = $Panel/Margin/VBox/PlayersHBox/PlayersLabel
@onready var players_list: ItemList = $Panel/Margin/VBox/PlayersHBox/PlayersList
@onready var log_output: RichTextLabel = $Panel/Margin/VBox/Log

var _prev_player_ids: PackedInt32Array = []
var _in_session: bool = false

func _ready() -> void:
	set_process_input(true)
	# Default name
	var nm := NetworkManager.get_local_player_name()
	if nm.is_empty():
		nm = NetworkManager.randomize_local_player_name()
	name_line.text = nm
	
	# Hook buttons
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	test_world_button.pressed.connect(_on_test_world_pressed)
	
	# Connect NetworkManager signals
	NetworkManager.connection_succeeded.connect(func(): _log("✅ Connection succeeded"))
	NetworkManager.connection_failed.connect(func(): _log("❌ Connection failed"))
	NetworkManager.player_list_changed.connect(_on_player_list_changed)
	# Ensure we see the current roster when entering from Lobby
	if NetworkManager != null:
		NetworkManager.request_players_resync()
	# If we arrived here already connected (from Lobby), mark session and prevent LineEdit focus
	_in_session = (multiplayer.multiplayer_peer != null)
	if _in_session:
		_disable_text_inputs()
		get_viewport().gui_release_focus()
	
	# Ensure input actions exist (WASD)
	_ensure_input_action("mv_up", KEY_W)
	_ensure_input_action("mv_down", KEY_S)
	_ensure_input_action("mv_left", KEY_A)
	_ensure_input_action("mv_right", KEY_D)
	
	_log("[DevTest] Ready. Enter a name/IP and Host or Join.")

func _ensure_input_action(action_name: String, keycode: int) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
		var ev := InputEventKey.new()
		ev.keycode = keycode
		InputMap.action_add_event(action_name, ev)

func _on_host_pressed() -> void:
	var name := name_line.text.strip_edges()
	if name.is_empty():
		name = NetworkManager.randomize_local_player_name()
		name_line.text = name
	NetworkManager.set_local_player_name(name)
	_log("🏠 Hosting as '" + name + "' on UDP 8080")
	NetworkManager.create_lobby(name, "Dev Room", 5, "5 minutes")
	_in_session = true
	_disable_text_inputs()
	get_viewport().gui_release_focus()

func _on_join_pressed() -> void:
	var name := name_line.text.strip_edges()
	if name.is_empty():
		name = NetworkManager.randomize_local_player_name()
		name_line.text = name
	NetworkManager.set_local_player_name(name)
	var ip := ip_line.text.strip_edges()
	if ip.is_empty():
		_log("[Join] Please enter host IP")
		return
	_log("🔗 Joining '" + ip + "' as '" + name + "'")
	NetworkManager.join_lobby(name, ip)
	_in_session = true	
	_disable_text_inputs()
	get_viewport().gui_release_focus()

func _on_leave_pressed() -> void:
	_log("👋 Leaving session")
	NetworkManager.leave_lobby()
	_in_session = false
	_enable_text_inputs()
	get_viewport().gui_release_focus()

func _on_test_world_pressed() -> void:
	if not _in_session:
		_log("❌ Not connected to a session. Host or join first.")
		return
	
	_log("🌍 Loading dev test world...")
	SceneChanger.change_scene_to_file("res://scenes/dev/dev_world.tscn")

func _disable_text_inputs() -> void:
	name_line.editable = false
	ip_line.editable = false
	name_line.focus_mode = Control.FOCUS_NONE
	ip_line.focus_mode = Control.FOCUS_NONE

func _enable_text_inputs() -> void:
	name_line.editable = true
	ip_line.editable = true
	name_line.focus_mode = Control.FOCUS_ALL
	ip_line.focus_mode = Control.FOCUS_ALL

func _on_player_list_changed(players: Dictionary) -> void:
	# Update list UI
	players_list.clear()
	var ids: PackedInt32Array = []
	for k in players.keys():
		var id := int(k)
		ids.append(id)
	ids.sort()
	for id in ids:
		var pdata: Dictionary = players[id]
		players_list.add_item("%s (%d)" % [String(pdata.get("name", str(id))), id])
	players_label.text = "Players: %d" % ids.size()
	
	# Log join/leave diffs
	var joined: PackedInt32Array = []
	var left: PackedInt32Array = []
	for id in ids:
		if not _contains_int(_prev_player_ids, id):
			joined.append(id)
	for id in _prev_player_ids:
		if not _contains_int(ids, id):
			left.append(id)
	_prev_player_ids = ids.duplicate()
	if joined.size() > 0:
		var jstr: Array = []
		for v in joined:
			jstr.append(str(v))
		_log("👥 Joined: " + ", ".join(jstr))
	if left.size() > 0:
		var lstr: Array = []
		for v in left:
			lstr.append(str(v))
		_log("🚪 Left: " + ", ".join(lstr))

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var handled := false
		# Prefer direct keycode to avoid action map issues
		match event.keycode:
			KEY_W:
				_rpc_submit_input("up")
				handled = true
			KEY_S:
				_rpc_submit_input("down")
				handled = true
			KEY_A:
				_rpc_submit_input("left")
				handled = true
			KEY_D:
				_rpc_submit_input("right")
				handled = true
			_:
				# Fallback to actions if user remapped
				if Input.is_action_pressed("mv_up"):
					_rpc_submit_input("up")
					handled = true
				elif Input.is_action_pressed("mv_down"):
					_rpc_submit_input("down")
					handled = true
				elif Input.is_action_pressed("mv_left"):
					_rpc_submit_input("left")
					handled = true
				elif Input.is_action_pressed("mv_right"):
					_rpc_submit_input("right")
					handled = true
		# While in a session, prevent letters from being typed into LineEdits
		if handled and _in_session:
			accept_event()

func _rpc_submit_input(dir: String) -> void:
	# Client reports intent to server; server broadcasts to all
	if multiplayer.is_server():
		# Directly handle as server (avoid RPC context issues)
		_server_handle_input_from(multiplayer.get_unique_id(), dir)
	else:
		rpc_submit_input.rpc(dir)

@rpc("any_peer", "reliable")
func rpc_submit_input(dir: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	# When the host triggers this locally, remote sender is 0. Map to self (server's unique ID).
	if sender == 0:
		sender = multiplayer.get_unique_id()
	_server_handle_input_from(sender, dir)

func _server_handle_input_from(peer_id: int, dir: String) -> void:
	var name: String = "Peer " + str(peer_id)
	if NetworkManager.players.has(peer_id):
		name = String(NetworkManager.players[peer_id].get("name", name))
	sync_log_input.rpc(peer_id, name, dir)

@rpc("any_peer", "call_local", "reliable")
func sync_log_input(peer_id: int, name: String, dir: String) -> void:
	var key := "?"
	match dir:
		"up":
			key = "w"
		"down":
			key = "s"
		"left":
			key = "a"
		"right":
			key = "d"
	_log("[%s]: moves %s(%s key)" % [name, dir, key])

func _contains_int(arr: PackedInt32Array, value: int) -> bool:
	for v in arr:
		if v == value:
			return true
	return false

func _log(msg: String) -> void:
	var line := "" + msg
	print(line)
	if log_output:
		log_output.append_text(line + "\n")
		log_output.scroll_to_line(log_output.get_line_count() - 1)
