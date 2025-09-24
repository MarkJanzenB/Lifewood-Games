# res://scripts/game_ui.gd

class_name GameUI
extends CanvasLayer

# --- NODE REFERENCES ---
# Match GameUI.tscn layout precisely
@onready var countdown_label: Label = get_node_or_null("MarginContainer/CountdownLabel")
@onready var ammo_label: Label = get_node_or_null("MarginContainer/VBoxContainer/HBoxContainer2/AmmoLabel")
@onready var hiders_label: Label = get_node_or_null("MarginContainer/VBoxContainer/HidersLabel")
@onready var kill_feed_label: Label = get_node_or_null("MarginContainer/VBoxContainer/HBoxContainer/KillFeedLabel")
@onready var status_label: Label = get_node_or_null("MarginContainer/VBoxContainer/HBoxContainer/StatusLabel")
@onready var spotted_label: Label = get_node_or_null("MarginContainer/SpottedLabel")
@onready var spotted_timer: Timer = Timer.new()

var local_player_role: PlayerCharacter.PlayerRole

func _ready():
	# Register this UI instance with the global GameManager
	var game_manager = get_node_or_null("/root/GameMaster")
	if game_manager and game_manager.has_method("register_game_ui"):
		game_manager.register_game_ui(self)
		
	add_child(spotted_timer)
	spotted_timer.wait_time = 2.0
	spotted_timer.one_shot = true
	spotted_timer.timeout.connect(func(): if spotted_label: spotted_label.visible = false)
	
	if kill_feed_label: 
		kill_feed_label.text = ""
	else: 
		push_warning("[GameUI] KillFeedLabel not found")
	if status_label: 
		status_label.text = ""
	else: 
		push_warning("[GameUI] StatusLabel not found")

func initialize(player: PlayerCharacter):
	local_player_role = player.role
	configure_for_role(local_player_role)

func configure_for_role(role: PlayerCharacter.PlayerRole):
	"""Configure UI elements based on player role - called once"""
	local_player_role = role
	print("[GameUI] Configuring UI for role: ", PlayerCharacter.PlayerRole.keys()[role])
	
	if role == PlayerCharacter.PlayerRole.SEEKER:
		if spotted_label:
			spotted_label.visible = false
		if ammo_label:
			ammo_label.visible = true
	elif role == PlayerCharacter.PlayerRole.HIDER:
		if ammo_label:
			ammo_label.visible = false
		if spotted_label:
			spotted_label.visible = false  # Will be shown when spotted

# --- PUBLIC UI FUNCTIONS ---

func update_ammo(count: int):
	if local_player_role == PlayerCharacter.PlayerRole.SEEKER:
		if ammo_label:
			ammo_label.text = "Ammo: " + str(count)

func update_hiders_left(count: int):
	if hiders_label:
		hiders_label.text = "Hiders Left: " + str(count)

func show_kill_feed(message: String):
	if kill_feed_label:
		fade_out_label(kill_feed_label, message)

func show_spotted(is_visible: bool):
	if local_player_role == PlayerCharacter.PlayerRole.HIDER:
		if spotted_label:
			spotted_label.visible = is_visible
			if is_visible:
				spotted_timer.start()

func update_countdown(text: String, is_visible: bool):
	"""Passive display - simply shows the countdown value from server"""
	if countdown_label:
		countdown_label.text = text
		countdown_label.visible = is_visible
		print("[GameUI] Countdown updated: ", text)

func update_status(text: String, is_visible: bool):
	if status_label:
		if is_visible:
			fade_out_label(status_label, text)
		else:
			status_label.visible = false

# Called by GameManager when the match ends
func show_game_over(did_i_win: bool, message: String) -> void:
	if status_label:
		status_label.visible = true
		status_label.modulate.a = 1.0
		status_label.text = message
	if countdown_label:
		countdown_label.visible = false

# --- REUSABLE FADE FUNCTION ---
func fade_out_label(label_node: Label, text: String):
	if label_node:
		label_node.text = text
		label_node.modulate.a = 1.0
		var tween = create_tween()
		tween.tween_interval(3.0)
		tween.tween_property(label_node, "modulate:a", 0, 1.0)

func _exit_tree():
	# Deregister when this HUD is removed to prevent stale references
	var game_manager = get_node_or_null("/root/GameMaster")
	if game_manager and game_manager.has_method("unregister_game_ui"):
		game_manager.unregister_game_ui(self)
