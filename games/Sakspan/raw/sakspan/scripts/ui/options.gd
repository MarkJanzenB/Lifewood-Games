# Options.gd - Options Menu Controller
# Manages the options menu interface and connects UI elements to AudioManager

extends Control

# UI References
@onready var back_button: Button = $CenterContainer/Panel/VBoxContainer/BackButton
@onready var reset_button: Button = $CenterContainer/Panel/VBoxContainer/AudioContainer/ResetButton

# Volume sliders
@onready var master_slider: HSlider = $CenterContainer/Panel/VBoxContainer/AudioContainer/MasterContainer/MasterSlider
@onready var music_slider: HSlider = $CenterContainer/Panel/VBoxContainer/AudioContainer/MusicContainer/MusicSlider
@onready var sfx_slider: HSlider = $CenterContainer/Panel/VBoxContainer/AudioContainer/SFXContainer/SFXSlider
@onready var ui_slider: HSlider = $CenterContainer/Panel/VBoxContainer/AudioContainer/UIContainer/UISlider
@onready var voice_slider: HSlider = $CenterContainer/Panel/VBoxContainer/AudioContainer/VoiceContainer/VoiceSlider

# Volume labels
@onready var master_label: Label = $CenterContainer/Panel/VBoxContainer/AudioContainer/MasterContainer/MasterLabel
@onready var music_label: Label = $CenterContainer/Panel/VBoxContainer/AudioContainer/MusicContainer/MusicLabel
@onready var sfx_label: Label = $CenterContainer/Panel/VBoxContainer/AudioContainer/SFXContainer/SFXLabel
@onready var ui_label: Label = $CenterContainer/Panel/VBoxContainer/AudioContainer/UIContainer/UILabel
@onready var voice_label: Label = $CenterContainer/Panel/VBoxContainer/AudioContainer/VoiceContainer/VoiceLabel

# Mute buttons
@onready var master_mute_button: Button = $CenterContainer/Panel/VBoxContainer/AudioContainer/MasterContainer/MasterMuteButton
@onready var music_mute_button: Button = $CenterContainer/Panel/VBoxContainer/AudioContainer/MusicContainer/MusicMuteButton
@onready var sfx_mute_button: Button = $CenterContainer/Panel/VBoxContainer/AudioContainer/SFXContainer/SFXMuteButton
@onready var ui_mute_button: Button = $CenterContainer/Panel/VBoxContainer/AudioContainer/UIContainer/UIMuteButton
@onready var voice_mute_button: Button = $CenterContainer/Panel/VBoxContainer/AudioContainer/VoiceContainer/VoiceMuteButton

# Audio test buttons
@onready var test_sfx_button: Button = $CenterContainer/Panel/VBoxContainer/AudioContainer/SFXContainer/TestSFXButton
@onready var test_ui_button: Button = $CenterContainer/Panel/VBoxContainer/AudioContainer/UIContainer/TestUIButton

# Click sound effect
@onready var click_sound: AudioStreamPlayer = $ClickSound

func _ready():
	# Start background music
	MusicManager.force_start_main_theme()
	
	# Connect UI signals
	_connect_ui_signals()
	
	# Connect to AudioManager signals
	_connect_audio_manager_signals()
	
	# Initialize UI with current audio settings
	_update_all_ui_elements()
	
	print("Options menu initialized")

func _connect_ui_signals():
	# Back and reset buttons
	if back_button:
		back_button.pressed.connect(_on_back_button_pressed)
		print("Options: Back button connected")
	else:
		print("Options: ERROR - Back button not found!")
	if reset_button:
		reset_button.pressed.connect(_on_reset_button_pressed)
		print("Options: Reset button connected")
	else:
		print("Options: ERROR - Reset button not found!")
	
	# Volume sliders
	if master_slider:
		master_slider.value_changed.connect(_on_master_slider_changed)
	if music_slider:
		music_slider.value_changed.connect(_on_music_slider_changed)
	if sfx_slider:
		sfx_slider.value_changed.connect(_on_sfx_slider_changed)
	if ui_slider:
		ui_slider.value_changed.connect(_on_ui_slider_changed)
	if voice_slider:
		voice_slider.value_changed.connect(_on_voice_slider_changed)
	
	# Mute buttons
	if master_mute_button:
		master_mute_button.pressed.connect(_on_master_mute_pressed)
	if music_mute_button:
		music_mute_button.pressed.connect(_on_music_mute_pressed)
	if sfx_mute_button:
		sfx_mute_button.pressed.connect(_on_sfx_mute_pressed)
	if ui_mute_button:
		ui_mute_button.pressed.connect(_on_ui_mute_pressed)
	if voice_mute_button:
		voice_mute_button.pressed.connect(_on_voice_mute_pressed)
	
	# Test buttons
	if test_sfx_button:
		test_sfx_button.pressed.connect(_on_test_sfx_pressed)
	if test_ui_button:
		test_ui_button.pressed.connect(_on_test_ui_pressed)

func _connect_audio_manager_signals():
	# Connect to AudioManager signals for real-time updates
	if AudioManager:
		AudioManager.volume_changed.connect(_on_audio_manager_volume_changed)
		AudioManager.mute_changed.connect(_on_audio_manager_mute_changed)
		print("Options: AudioManager signals connected")
	else:
		print("Options: ERROR - AudioManager not found!")

func _update_all_ui_elements():
	print("Options: Updating UI elements...")
	# Update sliders with current volumes
	if master_slider and AudioManager:
		master_slider.value = AudioManager.master_volume
		print("Options: Master slider set to: ", AudioManager.master_volume)
	if music_slider and AudioManager:
		music_slider.value = AudioManager.music_volume
		print("Options: Music slider set to: ", AudioManager.music_volume)
	if sfx_slider and AudioManager:
		sfx_slider.value = AudioManager.sfx_volume
	if ui_slider and AudioManager:
		ui_slider.value = AudioManager.ui_volume
	if voice_slider and AudioManager:
		voice_slider.value = AudioManager.voice_volume
	
	# Update labels
	_update_volume_labels()
	
	# Update mute button states
	_update_mute_buttons()

func _update_volume_labels():
	if master_label and AudioManager:
		master_label.text = "Master: " + str(int(AudioManager.master_volume * 100)) + "%"
	if music_label and AudioManager:
		music_label.text = "Music: " + str(int(AudioManager.music_volume * 100)) + "%"
	if sfx_label and AudioManager:
		sfx_label.text = "SFX: " + str(int(AudioManager.sfx_volume * 100)) + "%"
	if ui_label and AudioManager:
		ui_label.text = "UI: " + str(int(AudioManager.ui_volume * 100)) + "%"
	if voice_label and AudioManager:
		voice_label.text = "Voice: " + str(int(AudioManager.voice_volume * 100)) + "%"

func _update_mute_buttons():
	if master_mute_button:
		master_mute_button.text = "🔇" if AudioManager.master_muted else "🔊"
		master_mute_button.modulate = Color.RED if AudioManager.master_muted else Color.WHITE
	
	if music_mute_button:
		music_mute_button.text = "🔇" if AudioManager.music_muted else "🔊"
		music_mute_button.modulate = Color.RED if AudioManager.music_muted else Color.WHITE
	
	if sfx_mute_button:
		sfx_mute_button.text = "🔇" if AudioManager.sfx_muted else "🔊"
		sfx_mute_button.modulate = Color.RED if AudioManager.sfx_muted else Color.WHITE
	
	if ui_mute_button:
		ui_mute_button.text = "🔇" if AudioManager.ui_muted else "🔊"
		ui_mute_button.modulate = Color.RED if AudioManager.ui_muted else Color.WHITE
	
	if voice_mute_button:
		voice_mute_button.text = "🔇" if AudioManager.voice_muted else "🔊"
		voice_mute_button.modulate = Color.RED if AudioManager.voice_muted else Color.WHITE

# Slider change handlers
func _on_master_slider_changed(value: float):
	print("Options: Master slider changed to: ", value)
	AudioManager.set_master_volume(value)
	_play_click_sound()

func _on_music_slider_changed(value: float):
	print("Options: Music slider changed to: ", value)
	AudioManager.set_music_volume(value)
	_play_click_sound()

func _on_sfx_slider_changed(value: float):
	print("Options: SFX slider changed to: ", value)
	AudioManager.set_sfx_volume(value)
	_play_click_sound()

func _on_ui_slider_changed(value: float):
	print("Options: UI slider changed to: ", value)
	AudioManager.set_ui_volume(value)
	_play_click_sound()

func _on_voice_slider_changed(value: float):
	print("Options: Voice slider changed to: ", value)
	AudioManager.set_voice_volume(value)
	_play_click_sound()

# Mute button handlers
func _on_master_mute_pressed():
	AudioManager.toggle_master_mute()
	_play_click_sound()

func _on_music_mute_pressed():
	AudioManager.toggle_music_mute()
	_play_click_sound()

func _on_sfx_mute_pressed():
	AudioManager.toggle_sfx_mute()
	_play_click_sound()

func _on_ui_mute_pressed():
	AudioManager.toggle_ui_mute()
	_play_click_sound()

func _on_voice_mute_pressed():
	AudioManager.toggle_voice_mute()
	_play_click_sound()

# Test button handlers
func _on_test_sfx_pressed():
	# Play a test SFX sound
	AudioManager.play_ui_sound("res://assets/sound_effects/single_click_effect.mp3")

func _on_test_ui_pressed():
	# Play a test UI sound
	_play_click_sound()

# Navigation handlers
func _on_back_button_pressed():
	print("Options: Back button pressed!")
	_play_click_sound()
	# Return to main menu
	print("Options: Changing scene to main menu...")
	SceneChanger.change_scene_to_file("res://scenes/UI/Main_Menu/main_menu.tscn")

func _on_reset_button_pressed():
	_play_click_sound()
	# Reset all audio settings to defaults
	AudioManager.reset_to_defaults()

# AudioManager signal handlers
func _on_audio_manager_volume_changed(bus_name: String, volume: float):
	# Update UI when volume changes from AudioManager
	match bus_name.to_lower():
		"master":
			if master_slider and master_slider.value != volume:
				master_slider.value = volume
		"music":
			if music_slider and music_slider.value != volume:
				music_slider.value = volume
		"sfx":
			if sfx_slider and sfx_slider.value != volume:
				sfx_slider.value = volume
		"ui":
			if ui_slider and ui_slider.value != volume:
				ui_slider.value = volume
		"voice":
			if voice_slider and voice_slider.value != volume:
				voice_slider.value = volume
	
	# Update labels
	_update_volume_labels()

func _on_audio_manager_mute_changed(bus_name: String, muted: bool):
	# Update mute button states when mute changes from AudioManager
	_update_mute_buttons()

func _play_click_sound():
	if click_sound and click_sound.stream:
		click_sound.stop()
		click_sound.play()

# Handle input for quick navigation
func _input(event):
	if event.is_action_pressed("ui_cancel"):
		_on_back_button_pressed()
