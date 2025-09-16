class_name LoadingScreen
extends Control

@onready var progress_bar: ProgressBar = $Panel/ProgressBar
@onready var status_label: Label = $Panel/StatusLabel

func _ready():
    visible = false
    progress_bar.value = 0
    status_label.text = ""

func update_progress(value: float, status: String = "") -> void:
    progress_bar.value = clamp(value * 100, 0, 100)
    if status:
        status_label.text = status

func show() -> void:
    visible = true
    update_progress(0, "Loading...")

func hide() -> void:
    visible = false

func _on_visibility_changed() -> void:
    if visible:
        # Reset progress when shown
        update_progress(0, "Loading...")
