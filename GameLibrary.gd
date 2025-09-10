# GameLibrary.gd
# This script manages the main game library view. It is responsible for
# displaying the game cards or a message if no games are available.
extends Control

# --- Scene Preloads ---
# Preloading scenes makes them ready to be instanced (created) quickly.
const GameCard = preload("res://GameCard.tscn")
const NoGamesMessage = preload("res://NoGamesMessage.tscn")

# --- Node References ---
# We get direct references to the nodes we need to control. The '@onready'
# keyword ensures the script waits until these nodes are ready before assigning them.
# IMPORTANT: These paths must exactly match your GameLibrary.tscn scene tree.
@onready var grid: GridContainer = $PanelContainer/HBoxContainer/ContentArea/ScrollContainer/MarginContainer/GridContainer
@onready var hbox_container: HBoxContainer = $PanelContainer/HBoxContainer
@onready var content_area: PanelContainer = $PanelContainer/HBoxContainer/ContentArea

# --- Game Database ---
# This is a list of all the games your launcher knows about.
# The "folder" name MUST match the folder name in your "games" directory.
var game_database = [
	 #{"title": "My First Game", "folder": "MyFirstGame"},
	 #{"title": "Epic Adventure", "folder": "EpicAdventure"},
	 #{"title": "Pixel Racer", "folder": "PixelRacer"},
]

# The _ready() function is called once when the scene loads.
func _ready():
	# When the library first opens, call our main function to decide what to show.
	update_library_view()

# This is the main function that controls the entire library display.
func update_library_view():
	# --- Cleanup Phase ---
	# First, find and remove any "No Games" message from a previous view.
	# We search for it by the name we assigned it.
	var old_message = hbox_container.find_child("no_games_message", false)
	if old_message:
		old_message.queue_free()

	# Next, clear out all old game cards from the grid to ensure a fresh start.
	for child in grid.get_children():
		child.queue_free()

	# --- Logic Phase ---
	# The core logic: check if our list of games is empty.
	if game_database.is_empty():
		# --- THERE ARE NO GAMES ---
		# 1. Hide the entire panel that normally holds the game cards.
		content_area.visible = false
		
		# 2. Create an instance of our "No Games" message scene.
		var message = NoGamesMessage.instantiate()
		
		# 3. Give it a unique name so we can find it and remove it later.
		message.name = "no_games_message"
		
		# 4. Crucially, tell the message to expand to fill all available space.
		message.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
		
		# 5. Add the message to the screen.
		hbox_container.add_child(message)
		
	else:
		# --- THERE ARE GAMES TO DISPLAY ---
		# 1. Make sure the panel for the game cards is visible.
		content_area.visible = true
		
		# 2. Loop through every game in our database.
		for game_data in game_database:
			# Create a new game card instance.
			var card = GameCard.instantiate()
			
			# --- THIS IS THE MOST IMPORTANT STEP ---
			# Add the card to the scene tree FIRST. This makes its nodes ready.
			grid.add_child(card)
			
			# NOW that the card is in the scene, we can safely call its setup function.
			card.setup_card(game_data.title, game_data.folder)
			# -------------------------------------

# --- Sidebar Button Functions ---
# These functions must be connected to the 'pressed' signal of their respective buttons.

func _on_button_ph_pressed():
	print("Philippines tab selected. Reloading games...")
	# This simply re-runs our main display logic.
	# In the future, you could change the game_database here to show different games.
	update_library_view()

func _on_button_back_pressed():
	# Takes the user back to the region selection screen.
	get_tree().change_scene_to_file("res://CountrySelection.tscn")

func _on_button_quit_pressed():
	# Safely closes the entire application.
	get_tree().quit()
