# rock_projectile.gd (Corrected Version)

extends Area2D

const SPEED: int = 700

# --- THE NEW VARIABLE ---
# This will store a reference to the player who fired the rock.
var owner_player: PlayerCharacter

func _physics_process(delta: float) -> void:
	position += transform.x * SPEED * delta

func _on_body_entered(body: Node2D) -> void:
	var was_hit_processed = false

	if body.is_in_group("hider"):
		var hider = body as PlayerCharacter
		if hider and hider.current_state == PlayerCharacter.PlayerState.ALIVE:
			print("Rock hit a living hider!")
			# --- THE FIX IS HERE ---
			# We now pass our "owner_player" as the attacker.
			hider.eliminate(owner_player)
			was_hit_processed = true

	if body.is_in_group("walls"):
		was_hit_processed = true
		
	if was_hit_processed:
		queue_free()

func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()
