extends CharacterBody2D

# -------------------------------  
# 1️⃣ Player Movement & Speed
const SPEED = 100

# -------------------------------  
# 2️⃣ Vision Settings
const VISION_ANGLE = 45            # degrees for vision cone
const VISION_DISTANCE = 100        # reduced distance
const VISION_COLOR = Color(0.5, 1, 0.5, 0.3)  # light green with transparency
const ARC_SEGMENTS = 20            # smoothness of semi-circle

# -------------------------------  
# 3️⃣ Player State
var current_dir = "down"

# -------------------------------  
# 4️⃣ Animation Mapping
var anim_map = {
	"up": {"walk": "back_walk", "idle": "back_idle"},
	"down": {"walk": "front_walk", "idle": "idle"},
	"left": {"walk": "front_walk", "idle": "idle"},
	"right": {"walk": "front_walk", "idle": "idle"},
}

# -------------------------------  
# 5️⃣ Vision Cone Node
var vision_cone: Polygon2D

# -------------------------------  
# 6️⃣ Ready Function
func _ready():
	# Create the vision cone dynamically
	vision_cone = Polygon2D.new()
	vision_cone.color = VISION_COLOR
	add_child(vision_cone)

# -------------------------------  
# 7️⃣ Physics Process
func _physics_process(delta):
	player_movement(delta)
	face_mouse()
	update_vision_cone()
	check_vision()

# -------------------------------  
# 8️⃣ Player Movement Function
func player_movement(delta):
	var input_vector = Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	
	if input_vector != Vector2.ZERO:
		input_vector = input_vector.normalized()
		velocity = input_vector * SPEED
		play_anim("walk")
	else:
		velocity = Vector2.ZERO
		play_anim("idle")
	
	move_and_slide()

# -------------------------------  
# 9️⃣ Face Mouse Function
func face_mouse():
	var sprite = $AnimatedSprite2D
	if not sprite:
		return
	
	var mouse_pos = get_global_mouse_position()
	var dir = (mouse_pos - global_position).normalized()
	sprite.flip_h = dir.x < 0
	# rotation = dir.angle() # Optional

# -------------------------------  
# 10️⃣ Play Animation Function
func play_anim(state):
	var sprite = $AnimatedSprite2D
	if not sprite:
		return

	if velocity.y < 0:
		sprite.play(anim_map["up"][state])
	elif velocity.y > 0:
		sprite.play(anim_map["down"][state])
	elif velocity.x < 0:
		sprite.play(anim_map["left"][state])
	else:
		sprite.play(anim_map["right"][state])

# -------------------------------  
# 11️⃣ Vision Cone (Semi-circle)
func update_vision_cone():
	var mouse_pos = get_global_mouse_position()
	var dir = (mouse_pos - global_position).normalized()
	var half_angle = deg_to_rad(VISION_ANGLE / 2)
	
	var points = [Vector2.ZERO]  # start at player center
	for i in range(ARC_SEGMENTS + 1):
		var t = float(i) / ARC_SEGMENTS
		var angle = lerp(-half_angle, half_angle, t)
		var point = dir.rotated(angle) * VISION_DISTANCE
		points.append(point)
	
	vision_cone.polygon = points

# -------------------------------  
# 12️⃣ Vision Detection
func check_vision():
	var mouse_pos = get_global_mouse_position()
	var forward = (mouse_pos - global_position).normalized()
	var objects_in_range = get_tree().get_nodes_in_group("detectable")
	
	for obj in objects_in_range:
		if not obj:
			continue
		var to_obj = (obj.global_position - global_position)
		var distance = to_obj.length()
		var angle = rad_to_deg(forward.angle_to(to_obj.normalized()))
		
		if distance <= VISION_DISTANCE and abs(angle) <= VISION_ANGLE/2:
			obj.visible = true
		else:
			obj.visible = false
