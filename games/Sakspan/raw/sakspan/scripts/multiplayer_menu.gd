extends Control

func _ready():
	$CenterContainer/button_holder/create_lobby_button.pressed.connect(
		func(): SceneChanger.change_scene_to_file("res://scenes/UI/Create_Lobby/create_lobby_menu.tscn")
	)
	$CenterContainer/button_holder/join_lobby_button.pressed.connect(
		func(): SceneChanger.change_scene_to_file("res://scenes/UI/Join_Lobby/join_lobby_menu.tscn")
	)
	$CenterContainer/button_holder/back_button.pressed.connect(
		func(): SceneChanger.change_scene_to_file("res://scenes/UI/Main_Menu/main_menu.tscn")
	)
