# rock_projectile.gd (New, Simplified Version)

extends Area2D

const SPEED: int = 700 # Increased speed for a better feel

# This function is now much simpler. The rock moves along its own forward direction.
func _physics_process(delta: float) -> void:
	position += transform.x * SPEED * delta

# This is connected to the RockProjectile's "body_entered" signal.
func _on_body_entered(body: Node2D) -> void:
	# Check if we hit a hider.
	if body.is_in_group("hider"):
		print("Rock hit a hider!")
		body.eliminate() # Call the hider's eliminate function.
	
	# Destroy the rock after it hits anything solid (player or wall).
	if body.is_in_group("hider") or body.is_in_group("walls"):
		queue_free()

# This is connected to the new VisibleOnScreenNotifier2D's "screen_exited" signal.
func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	# If the rock flies off-screen, destroy it to save memory.
	queue_free()
