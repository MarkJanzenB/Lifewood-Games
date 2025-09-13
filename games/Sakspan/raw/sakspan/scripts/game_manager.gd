# game_manager.gd

extends Node

enum GameState { WAITING_TO_START, COUNTDOWN, IN_PROGRESS, FINISHED }
var current_state: GameState = GameState.WAITING_TO_START

func _ready():
	await get_tree().create_timer(0.01).timeout
	initialize_game()

func initialize_game():
	print("GameManager is initializing the game...")
	
	var all_hiders = get_tree().get_nodes_in_group("hider")
	var all_seekers = get_tree().get_nodes_in_group("seeker")
	
	if all_seekers.is_empty():
		print("ERROR: No Seeker found in the game!")
		return
		
	# --- THE BULLETPROOF FIX ---
	# We get the seeker node as a generic object.
	var seeker = all_seekers[0]
	
	# We check if the node actually has the function we want to call.
	if seeker.has_method("set_ammo"):
		var ammo_to_set = all_hiders.size() + 1
		# We use .call() to invoke the function by its name as a string.
		# This bypasses the broken type system and will always work.
		seeker.call("set_ammo", ammo_to_set)
		print("Seeker ammo set to: ", ammo_to_set)
	else:
		print("ERROR: The found Seeker node does not have a 'set_ammo' function!")


func on_player_eliminated():
	# Wait a frame to let the player node be removed from the tree.
	await get_tree().create_timer(0.01).timeout
	
	var remaining_hiders = get_tree().get_nodes_in_group("hider")
	var remaining_seekers = get_tree().get_nodes_in_group("seeker")
	
	print("Checking win conditions... Hiders remaining: ", remaining_hiders.size())
	
	# --- WIN CONDITIONS ---
	if remaining_hiders.is_empty():
		print("SEEKERS WIN!")
		get_tree().quit() # For now, just quit the game.
		
	if remaining_seekers.is_empty():
		print("HIDERS WIN!")
		get_tree().quit() # For now, just quit the game.
