extends CharacterBody3D

var speed
const WALK_SPEED = 3.0
const SPRINT_SPEED = 6.0
const JUMP_VELOCITY = 8
const SENSITIVITY = 0.004
const CROUCH_SPEED = 2.0

const STAND_HEIGHT = 1.873
const CROUCH_HEIGHT = 1.189
# We also need to lower the center position so the character doesn't float
const STAND_POS_Y = 0.823
const CROUCH_POS_Y = 0.481

# Snappy Jump Variables
const BASE_GRAVITY = 18.0
const FALL_GRAVITY_MULT = 1.6

#bob variables
const BOB_FREQ = 1.6
const BOB_AMP = 0.03
var t_bob = 0.0
var is_climbing: bool = false
var camera_base_pos := Vector3.ZERO

#fov variables
const BASE_FOV = 70.0
const FOV_CHANGE = 1.5
var can_wall_run: bool = false
var jump_count

# Crouch variables

var _is_crouching: bool = false
var is_first_person = true
var _is_sliding: bool = false
var slide_timer = 0.0
var slide_direction := Vector3.ZERO
const SLIDE_DURATION := 1.4   # seconds
const SLIDE_SPEED := 12.0    # tune to feel right

@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var wall_ray = $Head/RayFacingWall
@onready var ledge_check = $Head/LegdeChecker
@onready var ledge_floor_check = $Head/LegdeChecker/LedgeFloorChecker
@onready var collision = $CollisionShape3D
@onready var ANIMATIONPLAYER = $AnimationPlayer 
@onready var head_check = $ShapeCast3D
@onready var anim_tree = $AnimationTree
@onready var ray_right = %RayRight
@onready var ray_left = %RayLeft
@onready var tp_cam = $CameraPivot/SpringArm3D/ThirdPersonCamera
@onready var camera_pivot = $CameraPivot
@onready var armature = $Char_Rig
@onready var state_machine = anim_tree.get("parameters/playback")

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	camera_base_pos = camera.transform.origin
	head.rotation.y = 0  # make sure head isn't offsetting the body rotation
	camera.make_current()
	
	anim_tree.active = true
	state_machine.start("Movement")

func _physics_process(delta):
	if is_climbing:
		return

	if _is_sliding:
		slide_timer -= delta
		var t = slide_timer / SLIDE_DURATION
		
		# Get current input direction for steering
		var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		var forward = -transform.basis.z
		var right = transform.basis.x
		forward.y = 0
		right.y = 0
		var steer_dir = (forward * -input_dir.y + right * input_dir.x).normalized()
		
		# Blend slide direction with steering input
		var blended = slide_direction.lerp(steer_dir, 0.25) if steer_dir.length() > 0 else slide_direction
		
		velocity.x = blended.x * SLIDE_SPEED * (t * t)
		velocity.z = blended.z * SLIDE_SPEED * (t * t)
		
		if slide_timer <= 0.0:
			_is_sliding = false

	# --- SNAPPY JUMPING SYSTEM ---
	if not is_on_floor():
		if velocity.y > 0:
			velocity.y -= BASE_GRAVITY * delta
		else:
			velocity.y -= (BASE_GRAVITY * FALL_GRAVITY_MULT) * delta

	# Handle Jump / Ledge Climb Trigger
	if Input.is_action_just_pressed("ui_accept") and not _is_crouching:
		if is_on_floor():
		# Normale sprong
			velocity.y = JUMP_VELOCITY
			can_wall_run = false
			jump_count = 1 
			await get_tree().create_timer(0.2).timeout
			can_wall_run = true
		elif jump_count < 2 and not is_on_floor() and not (ray_left.is_colliding() or ray_right.is_colliding() or (wall_ray.is_colliding() and not ledge_check.is_colliding())):
		# Double jump
			velocity.y = JUMP_VELOCITY * 0.9 
			jump_count += 1
			can_wall_run = false
			await get_tree().create_timer(0.2).timeout
			can_wall_run = true
		
		elif check_for_ledge():
			start_ledge_climb()
			return

	#Handle Crouch en Camera toggle 
	if Input.is_action_just_pressed("Camera Toggle"):
		change_person()

# Handle Sprint
	if Input.is_action_pressed("sprint") and not _is_crouching:
		speed = SPRINT_SPEED
	elif not _is_crouching:
		speed = WALK_SPEED
	elif _is_crouching:
		speed = CROUCH_SPEED

	# Get the input direction and handle the movement/deceleration.
	var input_dir2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var forward = -transform.basis.z
	var right = transform.basis.x
	forward.y = 0
	right.y = 0
	var direction = (forward * -input_dir2.y + right * input_dir2.x).normalized()
	
	if not is_on_floor() and can_wall_run == true and Input.is_action_pressed("ui_accept") and (ray_left.is_colliding() or ray_right.is_colliding()):
		velocity.y = 0
	else:
		_normal_run(direction, delta)
		var curr_speed = Vector2(velocity.x, velocity.z).length()
		anim_tree.set("parameters/Movement/blend_position", curr_speed)

	if Input.is_action_just_pressed("crouch"):
		if _is_crouching == false and is_on_floor():
			_is_crouching = true
			state_machine.travel("CrouchIdle")
		elif _is_crouching == true and head_check.is_colliding() == false:
			_is_crouching = false
			state_machine.travel("Movement")

	# Head bob
	t_bob += delta * velocity.length() * float(is_on_floor())
	camera.transform.origin = camera_base_pos + _headbob(t_bob)
	
	# FOV
	var velocity_clamped = clamp(velocity.length(), 0.5, SPRINT_SPEED * 2)
	var target_fov = BASE_FOV + FOV_CHANGE * velocity_clamped
	camera.fov = lerp(camera.fov, target_fov, delta * 8.0)
	tp_cam.fov = lerp(camera.fov, target_fov, delta * 8.0)
	
	# --- COLLISION CAPSULE
	var target_height = CROUCH_HEIGHT if _is_crouching else STAND_HEIGHT
	var target_pos_y = CROUCH_POS_Y if _is_crouching else STAND_POS_Y
	collision.shape.height = lerp(collision.shape.height, target_height, delta * 10.0)
	collision.position.y = lerp(collision.position.y, target_pos_y, delta * 10.0)
	
	move_and_slide()

func _normal_run(direction, delta):
	if direction:
		velocity.x = lerp(velocity.x, direction.x * speed, delta * 7.0)
		velocity.z = lerp(velocity.z, direction.z * speed, delta * 7.0)
	else:
		velocity.x = lerp(velocity.x, direction.x * speed, delta * 7.0)
		velocity.z = lerp(velocity.z, direction.z * speed, delta * 7.0)

func _headbob(time) -> Vector3:
	var pos = Vector3.ZERO
	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	pos.x = cos(time * BOB_FREQ / 2) * BOB_AMP
	return pos


# --- LEDGE CLIMBING LOGIC ---
func check_for_ledge() -> bool:
	if wall_ray.is_colliding() and not ledge_check.is_colliding():
		if ledge_floor_check.is_colliding():
			return true
	return false

func start_ledge_climb() -> void:
	is_climbing = true
	velocity = Vector3.ZERO

	var wall_normal = wall_ray.get_collision_normal()
	var wall_point = wall_ray.get_collision_point()
	var exact_ledge_y = ledge_floor_check.get_collision_point().y
	var climb_up_pos = Vector3(global_position.x, exact_ledge_y + 1.1, global_position.z)
	var climb_forward_pos = wall_point - (wall_normal * 0.6)
	climb_forward_pos.y = exact_ledge_y + 1.01

	var tween = create_tween().set_parallel(false)
	tween.tween_property(self, "global_position:y", climb_up_pos.y, 0.3)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", climb_forward_pos, 0.25)\
		.set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(finish_climbing)

func finish_climbing() -> void:
	is_climbing = false

func change_person() -> void:
	is_first_person = !is_first_person
	if is_first_person:
		camera.make_current()
	else:
		tp_cam.make_current()

func _unhandled_input(event):
	if is_climbing:
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * SENSITIVITY)
		camera.rotate_x(-event.relative.y * SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-60), deg_to_rad(70))
		
		tp_cam.rotate_x(-event.relative.y * SENSITIVITY)
		tp_cam.rotation.x = clamp(camera.rotation.x, deg_to_rad(-60), deg_to_rad(30))
