# AudioManager.gd - Global Audio Management Singleton
# This singleton manages all audio settings and provides a centralized interface
# for controlling volume levels across different audio buses.

extends Node

# Audio bus indices
const MASTER_BUS = 0
const MUSIC_BUS = 1
const SFX_BUS = 2
const UI_BUS = 3
const VOICE_BUS = 4

# Default volume levels (0.0 to 1.0)
const DEFAULT_MASTER_VOLUME = 0.8
const DEFAULT_MUSIC_VOLUME = 0.7
const DEFAULT_SFX_VOLUME = 0.8
const DEFAULT_UI_VOLUME = 0.9
const DEFAULT_VOICE_VOLUME = 0.9

# Current volume levels
var master_volume: float = DEFAULT_MASTER_VOLUME
var music_volume: float = DEFAULT_MUSIC_VOLUME
var sfx_volume: float = DEFAULT_SFX_VOLUME
var ui_volume: float = DEFAULT_UI_VOLUME
var voice_volume: float = DEFAULT_VOICE_VOLUME

# Mute states
var master_muted: bool = false
var music_muted: bool = false
var sfx_muted: bool = false
var ui_muted: bool = false
var voice_muted: bool = false

# Settings file path
const SETTINGS_FILE = "user://audio_settings.cfg"

# Signals for UI updates
signal volume_changed(bus_name: String, volume: float)
signal mute_changed(bus_name: String, muted: bool)

func _ready():
	# Load saved settings
	load_audio_settings()
	# Apply loaded settings to audio buses
	apply_all_settings()

# Convert linear volume (0.0-1.0) to decibels
func linear_to_db(linear_volume: float) -> float:
	if linear_volume <= 0.0:
		return -80.0  # Effectively muted
	return 20.0 * log(linear_volume) / log(10.0)

# Convert decibels to linear volume (0.0-1.0)
func db_to_linear(db_volume: float) -> float:
	if db_volume <= -80.0:
		return 0.0
	return pow(10.0, db_volume / 20.0)

# Set master volume
func set_master_volume(volume: float):
	master_volume = clamp(volume, 0.0, 1.0)
	if not master_muted:
		AudioServer.set_bus_volume_db(MASTER_BUS, linear_to_db(master_volume))
	volume_changed.emit("Master", master_volume)
	save_audio_settings()

# Set music volume
func set_music_volume(volume: float):
	music_volume = clamp(volume, 0.0, 1.0)
	if not music_muted:
		AudioServer.set_bus_volume_db(MUSIC_BUS, linear_to_db(music_volume))
	# Update MusicManager if it exists
	if has_node("/root/MusicManager"):
		get_node("/root/MusicManager").set_music_volume(music_volume)
	volume_changed.emit("Music", music_volume)
	save_audio_settings()

# Set SFX volume
func set_sfx_volume(volume: float):
	sfx_volume = clamp(volume, 0.0, 1.0)
	if not sfx_muted:
		AudioServer.set_bus_volume_db(SFX_BUS, linear_to_db(sfx_volume))
	volume_changed.emit("SFX", sfx_volume)
	save_audio_settings()

# Set UI volume
func set_ui_volume(volume: float):
	ui_volume = clamp(volume, 0.0, 1.0)
	if not ui_muted:
		AudioServer.set_bus_volume_db(UI_BUS, linear_to_db(ui_volume))
	volume_changed.emit("UI", ui_volume)
	save_audio_settings()

# Set voice volume
func set_voice_volume(volume: float):
	voice_volume = clamp(volume, 0.0, 1.0)
	if not voice_muted:
		AudioServer.set_bus_volume_db(VOICE_BUS, linear_to_db(voice_volume))
	volume_changed.emit("Voice", voice_volume)
	save_audio_settings()

# Toggle master mute
func toggle_master_mute():
	master_muted = !master_muted
	if master_muted:
		AudioServer.set_bus_volume_db(MASTER_BUS, -80.0)
	else:
		AudioServer.set_bus_volume_db(MASTER_BUS, linear_to_db(master_volume))
	mute_changed.emit("Master", master_muted)
	save_audio_settings()

# Toggle music mute
func toggle_music_mute():
	music_muted = !music_muted
	if music_muted:
		AudioServer.set_bus_volume_db(MUSIC_BUS, -80.0)
	else:
		AudioServer.set_bus_volume_db(MUSIC_BUS, linear_to_db(music_volume))
	mute_changed.emit("Music", music_muted)
	save_audio_settings()

# Toggle SFX mute
func toggle_sfx_mute():
	sfx_muted = !sfx_muted
	if sfx_muted:
		AudioServer.set_bus_volume_db(SFX_BUS, -80.0)
	else:
		AudioServer.set_bus_volume_db(SFX_BUS, linear_to_db(sfx_volume))
	mute_changed.emit("SFX", sfx_muted)
	save_audio_settings()

# Toggle UI mute
func toggle_ui_mute():
	ui_muted = !ui_muted
	if ui_muted:
		AudioServer.set_bus_volume_db(UI_BUS, -80.0)
	else:
		AudioServer.set_bus_volume_db(UI_BUS, linear_to_db(ui_volume))
	mute_changed.emit("UI", ui_muted)
	save_audio_settings()

# Toggle voice mute
func toggle_voice_mute():
	voice_muted = !voice_muted
	if voice_muted:
		AudioServer.set_bus_volume_db(VOICE_BUS, -80.0)
	else:
		AudioServer.set_bus_volume_db(VOICE_BUS, linear_to_db(voice_volume))
	mute_changed.emit("Voice", voice_muted)
	save_audio_settings()

# Get current volume for a specific bus
func get_volume(bus_name: String) -> float:
	match bus_name.to_lower():
		"master":
			return master_volume
		"music":
			return music_volume
		"sfx":
			return sfx_volume
		"ui":
			return ui_volume
		"voice":
			return voice_volume
		_:
			push_warning("AudioManager: Unknown bus name: " + bus_name)
			return 0.0

# Get mute state for a specific bus
func is_muted(bus_name: String) -> bool:
	match bus_name.to_lower():
		"master":
			return master_muted
		"music":
			return music_muted
		"sfx":
			return sfx_muted
		"ui":
			return ui_muted
		"voice":
			return voice_muted
		_:
			push_warning("AudioManager: Unknown bus name: " + bus_name)
			return false

# Apply all current settings to audio buses
func apply_all_settings():
	# Apply volumes (considering mute states)
	AudioServer.set_bus_volume_db(MASTER_BUS, linear_to_db(master_volume) if not master_muted else -80.0)
	AudioServer.set_bus_volume_db(MUSIC_BUS, linear_to_db(music_volume) if not music_muted else -80.0)
	AudioServer.set_bus_volume_db(SFX_BUS, linear_to_db(sfx_volume) if not sfx_muted else -80.0)
	AudioServer.set_bus_volume_db(UI_BUS, linear_to_db(ui_volume) if not ui_muted else -80.0)
	AudioServer.set_bus_volume_db(VOICE_BUS, linear_to_db(voice_volume) if not voice_muted else -80.0)

# Save audio settings to file
func save_audio_settings():
	var config = ConfigFile.new()
	
	# Volume settings
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "ui_volume", ui_volume)
	config.set_value("audio", "voice_volume", voice_volume)
	
	# Mute settings
	config.set_value("audio", "master_muted", master_muted)
	config.set_value("audio", "music_muted", music_muted)
	config.set_value("audio", "sfx_muted", sfx_muted)
	config.set_value("audio", "ui_muted", ui_muted)
	config.set_value("audio", "voice_muted", voice_muted)
	
	var error = config.save(SETTINGS_FILE)
	if error != OK:
		push_error("AudioManager: Failed to save audio settings: " + str(error))

# Load audio settings from file
func load_audio_settings():
	var config = ConfigFile.new()
	var error = config.load(SETTINGS_FILE)
	
	if error != OK:
		print("AudioManager: No saved settings found, using defaults")
		return
	
	# Load volume settings with defaults
	master_volume = config.get_value("audio", "master_volume", DEFAULT_MASTER_VOLUME)
	music_volume = config.get_value("audio", "music_volume", DEFAULT_MUSIC_VOLUME)
	sfx_volume = config.get_value("audio", "sfx_volume", DEFAULT_SFX_VOLUME)
	ui_volume = config.get_value("audio", "ui_volume", DEFAULT_UI_VOLUME)
	voice_volume = config.get_value("audio", "voice_volume", DEFAULT_VOICE_VOLUME)
	
	# Load mute settings with defaults
	master_muted = config.get_value("audio", "master_muted", false)
	music_muted = config.get_value("audio", "music_muted", false)
	sfx_muted = config.get_value("audio", "sfx_muted", false)
	ui_muted = config.get_value("audio", "ui_muted", false)
	voice_muted = config.get_value("audio", "voice_muted", false)
	
	print("AudioManager: Audio settings loaded successfully")

# Reset all settings to defaults
func reset_to_defaults():
	master_volume = DEFAULT_MASTER_VOLUME
	music_volume = DEFAULT_MUSIC_VOLUME
	sfx_volume = DEFAULT_SFX_VOLUME
	ui_volume = DEFAULT_UI_VOLUME
	voice_volume = DEFAULT_VOICE_VOLUME
	
	master_muted = false
	music_muted = false
	sfx_muted = false
	ui_muted = false
	voice_muted = false
	
	apply_all_settings()
	save_audio_settings()
	
	# Emit signals for UI updates
	volume_changed.emit("Master", master_volume)
	volume_changed.emit("Music", music_volume)
	volume_changed.emit("SFX", sfx_volume)
	volume_changed.emit("UI", ui_volume)
	volume_changed.emit("Voice", voice_volume)
	
	mute_changed.emit("Master", master_muted)
	mute_changed.emit("Music", music_muted)
	mute_changed.emit("SFX", sfx_muted)
	mute_changed.emit("UI", ui_muted)
	mute_changed.emit("Voice", voice_muted)

# Convenience function to play UI sounds
func play_ui_sound(sound_path: String):
	var audio_player = AudioStreamPlayer.new()
	add_child(audio_player)
	audio_player.bus = "UI"
	
	var audio_stream = load(sound_path)
	if audio_stream:
		audio_player.stream = audio_stream
		audio_player.play()
		# Remove the player after the sound finishes
		audio_player.finished.connect(func(): audio_player.queue_free())
	else:
		push_warning("AudioManager: Could not load sound: " + sound_path)
		audio_player.queue_free()
