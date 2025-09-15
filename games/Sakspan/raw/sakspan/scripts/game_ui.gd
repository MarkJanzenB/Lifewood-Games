# res://scripts/game_ui.gd (Definitive Version with Fading Logic)

class_name GameUI
extends CanvasLayer

# --- NODE REFERENCES ---
@onready var countdown_label: Label = $MarginContainer/CountdownLabel
@onready var ammo_label: Label = $MarginContainer/VBoxContainer/HBoxContainer2/AmmoLabel
@onready var hiders_label: Label = $MarginContainer/VBoxContainer/HidersLabel
@onready var kill_feed_label: Label = $MarginContainer/VBoxContainer/HBoxContainer/KillFeedLabel
@onready var status_label: Label = $MarginContainer/VBoxContainer/HBoxContainer/StatusLabel
@onready var spotted_label: Label = $MarginContainer/SpottedLabel
@onready var spotted_timer: Timer = Timer.new()

var local_player_role: PlayerCharacter.PlayerRole

func _ready():
	add_child(spotted_timer)
	spotted_timer.wait_time = 2.0
	spotted_timer.one_shot = true
	spotted_timer.timeout.connect(func(): spotted_label.visible = false)
	
	# Clear the labels at the start of the game.
	kill_feed_label.text = ""
	status_label.text = ""

func initialize(player: PlayerCharacter):
	local_player_role = player.role
	if local_player_role == PlayerCharacter.PlayerRole.SEEKER:
		spotted_label.visible = false
	elif local_player_role == PlayerCharacter.PlayerRole.HIDER:
		ammo_label.visible = false

# --- PUBLIC UI FUNCTIONS ---

func update_ammo(count: int):
	if local_player_role == PlayerCharacter.PlayerRole.SEEKER:
		ammo_label.text = "Ammo: " + str(count)

func update_hiders_left(count: int):
	hiders_label.text = "Hiders Left: " + str(count)

func show_kill_feed(message: String):
	# This function now calls our new reusable fade-out function.
	fade_out_label(kill_feed_label, message)

func show_spotted(is_visible: bool):
	if local_player_role == PlayerCharacter.PlayerRole.HIDER:
		spotted_label.visible = is_visible
		if is_visible:
			spotted_timer.start()

func update_countdown(text: String, is_visible: bool):
	countdown_label.text = text
	countdown_label.visible = is_visible

func update_status(text: String, is_visible: bool):
	status_label.visible = is_visible
	# The status label will now also fade out automatically.
	if is_visible:
		fade_out_label(status_label, text)

# --- NEW REUSABLE FADE FUNCTION ---
func fade_out_label(label_node: Label, text: String):
	label_node.text = text
	label_node.modulate.a = 1.0 # Make sure it's fully visible
	var tween = create_tween()
	tween.tween_interval(3.0) # Wait for 3 seconds
	tween.tween_property(label_node, "modulate:a", 0, 1.0) # Fade to transparent over 1 second
