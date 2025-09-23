# res://scenes/UI/Multiplayer/multiplayer_menu.tscn


extends Control

@onready var name_line: LineEdit = $CenterContainer/MainVBox/NameHBox/PlayerNameLineEdit
@onready var randomize_btn: Button = $CenterContainer/MainVBox/NameHBox/RandomizeButton
@onready var click_sound: AudioStreamPlayer = $ClickSound

func _ready():
	# Start background music
	MusicManager.force_start_main_theme()
	# Initialize name field from NetworkManager or generate a default
	var nm: String = NetworkManager.get_local_player_name()
	if nm.is_empty():
		nm = NetworkManager.randomize_local_player_name()
	name_line.text = nm
	name_line.text_submitted.connect(_on_name_submitted)
	name_line.text_changed.connect(_on_name_changed)
	randomize_btn.pressed.connect(func():
		_play_click()
		var new_name: String = NetworkManager.randomize_local_player_name()
		name_line.text = new_name
	)

	$CenterContainer/MainVBox/button_holder/create_lobby_button.pressed.connect(
		func(): 
			_play_click()
			SceneChanger.change_scene_to_file("res://scenes/UI/Create_Lobby/create_lobby_menu.tscn")
	)
	$CenterContainer/MainVBox/button_holder/join_lobby_button.pressed.connect(
		func(): 
			_play_click()
			SceneChanger.change_scene_to_file("res://scenes/UI/Join_Lobby/join_lobby_menu.tscn")
	)
	$CenterContainer/MainVBox/button_holder/back_button.pressed.connect(
		func(): 
			_play_click()
			SceneChanger.change_scene_to_file("res://scenes/UI/Main_Menu/main_menu.tscn")
	)

func _on_name_submitted(new_text: String) -> void:
	NetworkManager.set_local_player_name(new_text)

func _on_name_changed(new_text: String) -> void:
	# Keep NetworkManager updated while typing; sanitize in setter
	NetworkManager.set_local_player_name(new_text)

func _play_click() -> void:
	if click_sound and click_sound.stream:
		click_sound.stop()
		click_sound.play()
