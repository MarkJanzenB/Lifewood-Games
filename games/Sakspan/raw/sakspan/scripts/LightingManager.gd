# LightingManager.gd - Manages Among Us style lighting system
extends Node

class_name LightingManager

# Lighting configuration
@export var global_darkness_color: Color = Color(0.2, 0.2, 0.3, 1.0)  # Darker for better light contrast
@export var flashlight_energy: float = 3.5  # Increased to overcome darkness
@export var flashlight_range: float = 1200.0  # Massive range to reach screen edges
@export var ambient_light_energy: float = 0.3

# Node references
var canvas_modulate: CanvasModulate
var players: Array[PlayerCharacter] = []

signal lighting_initialized

func _ready():
	print("[LightingManager] Initializing Among Us style lighting system...")
	
	# Add to group for easy discovery
	add_to_group("lighting_manager")
	
	call_deferred("_setup_global_lighting")

func _setup_global_lighting():
	"""Setup the global lighting system (darkness disabled for 2D light occlusion)"""
	# DISABLED: Global darkness overlay - user will use 2D light occlusion instead
	# canvas_modulate = CanvasModulate.new()
	# canvas_modulate.color = global_darkness_color
	# canvas_modulate.name = "GlobalDarkness"
	
	print("[LightingManager] ✅ Global darkness disabled - using 2D light occlusion instead")
	
	# Setup player lighting
	_setup_player_lighting()
	
	lighting_initialized.emit()

func _setup_player_lighting():
	"""Configure lighting for all players"""
	# Find all players in the scene
	var player_nodes = get_tree().get_nodes_in_group("player")
	
	for node in player_nodes:
		var player = node as PlayerCharacter
		if player:
			_configure_player_flashlight(player)
			players.append(player)
	
	print("[LightingManager] ✅ Configured lighting for ", players.size(), " players")

func _configure_player_flashlight(player: PlayerCharacter):
	"""Configure the flashlight (vision cone light) for a player"""
	if not player.vision_light:
		print("[LightingManager] ⚠️ No vision_light found for player: ", player.player_name)
		return
	
	var light = player.vision_light
	
	# Configure flashlight properties
	light.enabled = true
	light.energy = flashlight_energy
	light.range_z_max = 1024  # Ensure light affects all layers
	light.range_z_min = -1024
	
	# Create a flashlight texture if it doesn't exist
	if not light.texture:
		light.texture = _create_flashlight_texture()
	
	# Scale the light to match vision cone range
	var scale_factor = flashlight_range / 100.0  # Adjust based on your needs
	light.texture_scale = scale_factor
	
	# Set light color (slightly warm white)
	light.color = Color(1.0, 0.95, 0.8, 1.0)
	
	# CRITICAL: Make sure players can be illuminated by other players' lights
	_configure_player_lighting_interaction(player)
	
	print("[LightingManager] ✅ Configured flashlight for: ", player.player_name)

func _configure_player_lighting_interaction(player: PlayerCharacter):
	"""Configure player to be properly lit by other players' flashlights"""
	if not player.animated_sprite:
		return
	
	# Ensure the player sprite can receive light from other sources
	var sprite = player.animated_sprite
	
	# Set the sprite to use light from the environment
	sprite.use_parent_material = false
	
	# Create or configure a CanvasItemMaterial for proper lighting
	if not sprite.material:
		var material = CanvasItemMaterial.new()
		material.light_mode = CanvasItemMaterial.LIGHT_MODE_NORMAL
		sprite.material = material
	else:
		# Ensure existing material allows lighting
		if sprite.material is CanvasItemMaterial:
			var material = sprite.material as CanvasItemMaterial
			material.light_mode = CanvasItemMaterial.LIGHT_MODE_NORMAL
	
	print("[LightingManager] ✅ Configured lighting interaction for: ", player.player_name)

func _create_flashlight_texture() -> Texture2D:
	"""Create a cone-shaped gradient texture for the flashlight"""
	var image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var center = Vector2(128, 128)
	
	# Create a cone gradient
	for x in range(256):
		for y in range(256):
			var pos = Vector2(x, y)
			var distance = center.distance_to(pos)
			var angle = center.angle_to_point(pos)
			
			# Create cone shape (adjust angle range as needed)
			var cone_angle = PI / 3  # 60 degrees
			var normalized_angle = abs(angle)
			
			if normalized_angle <= cone_angle / 2:
				# Inside cone
				var intensity = 1.0 - (distance / 128.0)
				intensity = max(0.0, intensity)
				
				# Fade edges of cone
				var angle_fade = 1.0 - (normalized_angle / (cone_angle / 2))
				intensity *= angle_fade
				
				image.set_pixel(x, y, Color(1, 1, 1, intensity))
			else:
				# Outside cone
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	
	var texture = ImageTexture.new()
	texture.set_image(image)
	return texture

func update_player_flashlight_direction(player: PlayerCharacter, direction: Vector2):
	"""Update the direction of a player's flashlight"""
	if not player or not player.vision_light:
		return
	
	# The vision cone already handles rotation in handle_visuals()
	# We just need to ensure the light is properly oriented
	var light = player.vision_light
	
	# Ensure light is enabled for the local player
	if player.is_multiplayer_authority():
		light.enabled = true
		light.energy = flashlight_energy
	else:
		# Other players have dimmer lights
		light.energy = flashlight_energy * 0.7

func set_lighting_mode(mode: String):
	"""Change lighting mode (normal, emergency, etc.)"""
	match mode:
		"normal":
			if canvas_modulate:
				canvas_modulate.color = global_darkness_color
		"emergency":
			if canvas_modulate:
				canvas_modulate.color = Color(0.2, 0.05, 0.05, 1.0)  # Red emergency lighting
		"bright":
			if canvas_modulate:
				canvas_modulate.color = Color(0.4, 0.4, 0.4, 1.0)  # Brighter for testing

func toggle_flashlight(player: PlayerCharacter, enabled: bool):
	"""Toggle a player's flashlight on/off"""
	if not player or not player.vision_light:
		return
	
	player.vision_light.enabled = enabled
	print("[LightingManager] Flashlight ", "enabled" if enabled else "disabled", " for: ", player.player_name)

func add_emergency_lighting():
	"""Add emergency lighting effects (red flashing, etc.)"""
	# This could be expanded for special game events
	set_lighting_mode("emergency")
	
	# Could add flashing effects, sparks, etc.
	var tween = create_tween()
	tween.set_loops()
	tween.tween_method(_flash_emergency_light, 0.0, 1.0, 1.0)
	tween.tween_method(_flash_emergency_light, 1.0, 0.0, 1.0)

func _flash_emergency_light(intensity: float):
	"""Flash emergency lighting"""
	if canvas_modulate:
		var red_intensity = 0.05 + (intensity * 0.15)
		canvas_modulate.color = Color(red_intensity, 0.02, 0.02, 1.0)

func cleanup():
	"""Clean up lighting system"""
	if canvas_modulate and is_instance_valid(canvas_modulate):
		canvas_modulate.queue_free()
	
	players.clear()
	print("[LightingManager] ✅ Lighting system cleaned up")
