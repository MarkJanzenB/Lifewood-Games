# game_manager.gd (New Win Condition Logic)
extends Node

func _ready():
	await get_tree().create_timer(0.01).timeout
	initialize_game()

func initialize_game():
	var all_hiders = get_tree().get_nodes_in_group("hider")
	var all_seekers = get_tree().get_nodes_in_group("seeker")
	if all_seekers.is_empty(): return
	var seeker = all_seekers[0] as Player
	if seeker:
		seeker.set_ammo(all_hiders.size() + 1)
		print("Seeker ammo set to: ", seeker.ammo)

func on_player_eliminated():
	await get_tree().create_timer(0.01).timeout
	check_win_conditions()

func check_win_conditions():
	var all_hiders = get_tree().get_nodes_in_group("hider")
	var all_seekers = get_tree().get_nodes_in_group("seeker")
	
	# --- SEEKER WIN CONDITION ---
	var living_hiders_count = 0
	for hider in all_hiders:
		if (hider as Player).current_state == Player.PlayerState.ALIVE:
			living_hiders_count += 1
			
	if living_hiders_count == 0:
		print("ALL HIDERS ARE GHOSTS! SEEKERS WIN!")
		get_tree().quit()
		return
		
	# --- HIDER WIN CONDITION ---
	# If there are no seekers left in the "seeker" group, it means they have become a ghost.
	var living_seekers_count = 0
	for seeker in all_seekers:
		if (seeker as Player).current_state == Player.PlayerState.ALIVE:
			living_seekers_count += 1
			
	if living_seekers_count == 0:
		print("THE SEEKER IS A GHOST! HIDERS WIN!")
		get_tree().quit()
