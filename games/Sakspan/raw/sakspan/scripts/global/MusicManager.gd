# MusicManager.gd - Global Music Management Singleton
# Handles background music across all scenes with seamless transitions

extends Node

# Audio players for crossfading
var player_a: AudioStreamPlayer
var player_b: AudioStreamPlayer
var current_player: AudioStreamPlayer
var next_player: AudioStreamPlayer

# Music tracks
var main_theme: AudioStream
var current_track: AudioStream

# State tracking
var is_playing: bool = false
var current_scene_name: String = ""

# Scenes that should NOT have background music
var silent_scenes: Array[String] = ["world", "world_new"]

func _ready():
	print("MusicManager: Initializing...")
	
	# Create two audio players for crossfading
	player_a = AudioStreamPlayer.new()
	player_b = AudioStreamPlayer.new()
	add_child(player_a)
	add_child(player_b)
	
	# Configure both players
	for player in [player_a, player_b]:
		player.bus = "Music"
		player.volume_db = 0.0
	
	current_player = player_a
	next_player = player_b
	
	# Load main theme
	main_theme = load("res://assets/sound_effects/main_theme_music.mp3")
	if main_theme:
		print("MusicManager: Main theme loaded successfully")
		# Enable looping if possible
		if "loop" in main_theme:
			main_theme.loop = true
	else:
		push_error("MusicManager: Failed to load main theme music!")
	
	# Connect to scene changes
	if get_tree():
		get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node):
	# Check if a new scene root was added
	if node.get_parent() == get_tree().root and node != self:
		var scene_name = node.scene_file_path.get_file().get_basename()
		_handle_scene_change(scene_name)

func _handle_scene_change(scene_name: String):
	if current_scene_name == scene_name:
		return
		
	current_scene_name = scene_name
	print("MusicManager: Scene changed to ", scene_name)
	
	# Check if this scene should have music
	var should_be_silent = false
	for silent_scene in silent_scenes:
		if scene_name.contains(silent_scene):
			should_be_silent = true
			break
	
	if should_be_silent:
		stop_music()
	else:
		play_main_theme()

func play_main_theme():
	if not main_theme:
		push_warning("MusicManager: Main theme not loaded")
		return
	
	if is_playing and current_track == main_theme:
		return  # Already playing the main theme
	
	play_music(main_theme)

func play_music(stream: AudioStream, fade_time: float = 1.0):
	if not stream:
		push_warning("MusicManager: Attempted to play null stream")
		return
	
	current_track = stream
	
	# If nothing is playing, start immediately
	if not is_playing:
		current_player.stream = stream
		current_player.volume_db = 0.0
		current_player.play()
		is_playing = true
		print("MusicManager: Started playing music")
		return
	
	# If same track is already playing, do nothing
	if current_player.stream == stream and current_player.playing:
		return
	
	# Crossfade to new track
	_crossfade_to(stream, fade_time)

func _crossfade_to(stream: AudioStream, fade_time: float):
	print("MusicManager: Crossfading to new track")
	
	# Setup next player
	next_player.stream = stream
	next_player.volume_db = -80.0  # Start silent
	next_player.play()
	
	# Create crossfade tween
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Fade out current, fade in next
	tween.tween_property(current_player, "volume_db", -80.0, fade_time)
	tween.tween_property(next_player, "volume_db", 0.0, fade_time)
	
	# When done, swap players and stop the old one
	tween.finished.connect(func():
		current_player.stop()
		var temp = current_player
		current_player = next_player
		next_player = temp
		print("MusicManager: Crossfade completed")
	)

func stop_music(fade_time: float = 1.0):
	if not is_playing:
		return
	
	print("MusicManager: Stopping music")
	
	if fade_time > 0:
		var tween = create_tween()
		tween.tween_property(current_player, "volume_db", -80.0, fade_time)
		tween.finished.connect(func():
			current_player.stop()
			is_playing = false
			current_track = null
		)
	else:
		current_player.stop()
		is_playing = false
		current_track = null

func pause_music():
	if is_playing and current_player.playing:
		current_player.stream_paused = true
		print("MusicManager: Music paused")

func resume_music():
	if is_playing and current_player.stream_paused:
		current_player.stream_paused = false
		print("MusicManager: Music resumed")

func set_music_volume(volume: float):
	# This will be called by AudioManager
	var db_volume = AudioManager.linear_to_db(volume) if volume > 0 else -80.0
	
	for player in [player_a, player_b]:
		if player.playing:
			player.volume_db = db_volume

func get_current_track() -> AudioStream:
	return current_track

func is_music_playing() -> bool:
	return is_playing and current_player.playing

# Force start music for specific scenes (called manually)
func force_start_main_theme():
	play_main_theme()

# Force stop music for specific scenes (called manually)
func force_stop_music():
	stop_music(0.5)
