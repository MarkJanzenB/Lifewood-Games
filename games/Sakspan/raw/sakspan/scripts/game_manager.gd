# game_manager.gd

extends Node

# An enum to define the possible states of our game.
enum GameState { WAITING_TO_START, COUNTDOWN, IN_PROGRESS, FINISHED }

# This variable will hold the current state of the game.
var current_state: GameState = GameState.WAITING_TO_START

func _ready():
	print("GameManager is ready. Current state: ", GameState.keys()[current_state])
	# We will add code here later to start the countdown.
