# res://scripts/game_manager.gd

extends Node

signal player_eliminated(eliminated_player: PlayerCharacter, attacker: PlayerCharacter)
signal game_state_changed(new_state: GameState)

enum GameState { WAITING_TO_START, HIDER_HEADSTART, GAME_START_COUNTDOWN, IN_PROGRESS, FINISHED }
var current_state: GameState = GameState.WAITING_TO_START

# --- NEW UI REFERENCE ---
# This variable will be set by the GameUI scene itself when it loads.
var game_ui_instance: GameUI = null

# Timers are created in code to be self-contained.
@onready var main_timer: Timer = Timer.new()
@onready var ammo_cooldown_timer: Timer = Timer.new()
@onready var sak_delay_timer: Timer = Timer.new()

func _ready():
	add_child(main_timer)
	add_child(ammo_cooldown_timer)
	add_child(sak_delay_timer)
	
	main_timer.one_shot = true
	sak_delay_timer.one_shot = true
	ammo_cooldown_timer.one_shot = true
	
	player_eliminated.connect(on_player_eliminated)
	main_timer.timeout.connect(_on_main_timer_timeout)
	ammo_cooldown_timer.timeout.connect(_on_ammo_cooldown_timeout)
	sak_delay_timer.timeout.connect(_on_sak_delay_timer_timeout)
	
	await get_tree().process_frame
	initialize_game()

func initialize_game():
	var all_hiders = get_tree().get_nodes_in_group("hider")
	var all_seekers = get_tree().get_nodes_in_group("seeker")
	# Reset all as non-main and disable their cameras
	for p in all_seekers + all_hiders:
		var pc = p as PlayerCharacter
		if pc:
			pc.is_main_player = false
			var cam: Camera2D = pc.get_node_or_null("Camera2D")
			if cam:
				cam.enabled = false

	# Choose the local main player: host controls Seeker, client controls Hider
	var main_pc: PlayerCharacter = null
	if multiplayer.is_server():
		if not all_seekers.is_empty():
			main_pc = all_seekers[0] as PlayerCharacter
	else:
		if not all_hiders.is_empty():
			main_pc = all_hiders[0] as PlayerCharacter

	if main_pc:
		main_pc.is_main_player = true
		var cam2: Camera2D = main_pc.get_node_or_null("Camera2D")
		if cam2:
			cam2.enabled = true
		if is_instance_valid(game_ui_instance):
			game_ui_instance.initialize(main_pc)

	# Give ammo to the seeker based on hiders present (server authoritative)
	if not all_seekers.is_empty():
		var seeker = all_seekers[0] as PlayerCharacter
		if seeker:
			seeker.set_ammo(all_hiders.size() + 1)

	update_ui()
	change_state(GameState.HIDER_HEADSTART)

func start_ammo_cooldown():
	print("Seeker is out of ammo! Starting 5-second cooldown...")
	ammo_cooldown_timer.start(5.0)

func change_state(new_state: GameState):
	if current_state == new_state: return
	current_state = new_state
	emit_signal("game_state_changed", new_state)
	print("Game state changed to: ", GameState.keys()[new_state])

	if not is_instance_valid(game_ui_instance): return # Safety check

	match new_state:
		GameState.HIDER_HEADSTART:
			game_ui_instance.update_status("Hiders, GO! Seeker is frozen.", true)
			main_timer.start(5.0)
		GameState.GAME_START_COUNTDOWN:
			game_ui_instance.update_status("", false)
			game_ui_instance.update_countdown("10", true)
			main_timer.start(10.0)
		GameState.IN_PROGRESS:
			game_ui_instance.update_status("The Hunt is On!", true)
			game_ui_instance.update_countdown("GO!", false)
			sak_delay_timer.start(3.0)
		GameState.FINISHED:
			ammo_cooldown_timer.stop()

func _process(delta: float):
	if not is_instance_valid(game_ui_instance): return # Safety check
	
	if current_state == GameState.GAME_START_COUNTDOWN:
		game_ui_instance.update_countdown(str(ceil(main_timer.time_left)), true)
	update_ui()

func update_ui():
	if not is_instance_valid(game_ui_instance): return # Safety check
	
	var living_hiders_count = get_tree().get_nodes_in_group("hider").filter(func(hider): return (hider as PlayerCharacter).current_state == PlayerCharacter.PlayerState.ALIVE).size()
	game_ui_instance.update_hiders_left(living_hiders_count)
	
	var seekers = get_tree().get_nodes_in_group("seeker")
	if not seekers.is_empty():
		var seeker = seekers[0] as PlayerCharacter
		if seeker:
			game_ui_instance.update_ammo(seeker.ammo)

func on_player_eliminated(eliminated_player: PlayerCharacter, attacker: PlayerCharacter):
	if not is_instance_valid(game_ui_instance): return # Safety check
	
	var message = ""
	if attacker.role == PlayerCharacter.PlayerRole.SEEKER:
		message = attacker.player_name + " bonked " + eliminated_player.player_name
	elif attacker.role == PlayerCharacter.PlayerRole.HIDER:
		if eliminated_player.role == PlayerCharacter.PlayerRole.SEEKER:
			message = attacker.player_name + " just bonked " + eliminated_player.player_name
		else:
			message = attacker.player_name + " accidentally bonked " + eliminated_player.player_name
	
	game_ui_instance.show_kill_feed(message)

func check_win_conditions():
	await get_tree().process_frame
	
	var all_hiders = get_tree().get_nodes_in_group("hider")
	var all_seekers = get_tree().get_nodes_in_group("seeker")
	
	var living_hiders_count = all_hiders.filter(func(hider): return (hider as PlayerCharacter).current_state == PlayerCharacter.PlayerState.ALIVE).size()
	var living_seekers_count = all_seekers.filter(func(seeker): return (seeker as PlayerCharacter).current_state == PlayerCharacter.PlayerState.ALIVE).size()

	var game_over = false
	var winning_text = ""
	var seekers_win = false

	if living_hiders_count == 0:
		winning_text = "SEEKERS WIN!"
		seekers_win = true
		game_over = true
		
	if living_seekers_count == 0:
		winning_text = "HIDERS WIN!"
		seekers_win = false
		game_over = true
		
	if game_over:
		print(winning_text)
		change_state(GameState.FINISHED)
		
		# We will add the game over screen logic here in a future step.
		get_tree().paused = true

# --- SIGNAL HANDLERS ---

func _on_main_timer_timeout():
	if current_state == GameState.HIDER_HEADSTART:
		change_state(GameState.GAME_START_COUNTDOWN)
	elif current_state == GameState.GAME_START_COUNTDOWN:
		change_state(GameState.IN_PROGRESS)

func _on_ammo_cooldown_timeout():
	var seekers = get_tree().get_nodes_in_group("seeker")
	if seekers.is_empty(): return
	var seeker = seekers[0] as PlayerCharacter
	if seeker and seeker.current_state == PlayerCharacter.PlayerState.ALIVE:
		seeker.ammo += 1

func _on_sak_delay_timer_timeout():
	for hider in get_tree().get_nodes_in_group("hider"):
		(hider as PlayerCharacter).can_attack = true
	print("Hiders can now SAK!")
