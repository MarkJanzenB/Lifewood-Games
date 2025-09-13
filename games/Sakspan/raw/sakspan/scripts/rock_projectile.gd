# rock_projectile.gd
extends Area2D

var speed: float = 600.0
var direction: Vector2 = Vector2.RIGHT

func _physics_process(delta: float) -> void:
	position += direction * speed * delta

# This signal will fire when the rock hits something.
func _on_body_entered(body: Node2D) -> void:
	# Check if we hit a hider.
	if body.is_in_group("hider"):
		print("Rock hit a hider!")
		body.eliminate() # Call the hider's eliminate function.
	
	# Destroy the rock after it hits anything.
	queue_free()
