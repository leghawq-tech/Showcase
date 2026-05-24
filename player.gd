extends CharacterBody3D

var speed
const WALK_SPEED = 6.0
const SPRINT_SPEED = 9.0
const JUMP_VELOCITY = 6.5
const SENSITIVITY = 0.004

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

@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var wall_ray = $Head/RayFacingWall
@onready var ledge_check = $Head/LegdeChecker
@onready var ledge_floor_check = $Head/LegdeChecker/LedgeFloorChecker  # Added new downward ray
var is_first_person = true

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	camera_base_pos = camera.transform.origin
	
func _unhandled_input(event):
	if is_climbing:
		return
		
	if event is InputEventMouseMotion:
		head.rotate_y(-event.relative.x * SENSITIVITY)
		camera.rotate_x(-event.relative.y * SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-60), deg_to_rad(70))

func _physics_process(delta):
	if is_climbing:
		return

	# --- SNAPPY JUMPING SYSTEM ---
	if not is_on_floor():
		if velocity.y > 0:
			velocity.y -= BASE_GRAVITY * delta
		else:
			velocity.y -= (BASE_GRAVITY * FALL_GRAVITY_MULT) * delta

	# Handle Jump / Ledge Climb Trigger
	if Input.is_action_just_pressed("ui_accept"):
		if is_on_floor():
			velocity.y = JUMP_VELOCITY
		elif check_for_ledge():
			start_ledge_climb()
			return

	# Handle Sprint.
	if Input.is_action_pressed("sprint"):
		speed = SPRINT_SPEED
	else:
		speed = WALK_SPEED

	# Get the input direction and handle the movement/deceleration.
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if is_on_floor():
		if direction:
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
		else:
			velocity.x = lerp(velocity.x, direction.x * speed, delta * 7.0)
			velocity.z = lerp(velocity.z, direction.z * speed, delta * 7.0)
	else:
		velocity.x = lerp(velocity.x, direction.x * speed, delta * 3.0)
		velocity.z = lerp(velocity.z, direction.z * speed, delta * 3.0)
	
	# Head bob
	t_bob += delta * velocity.length() * float(is_on_floor())
	camera.transform.origin = camera_base_pos + _headbob(t_bob)
	
	# FOV
	var velocity_clamped = clamp(velocity.length(), 0.5, SPRINT_SPEED * 2)
	var target_fov = BASE_FOV + FOV_CHANGE * velocity_clamped
	camera.fov = lerp(camera.fov, target_fov, delta * 8.0)
	
	move_and_slide()


func _headbob(time) -> Vector3:
	var pos = Vector3.ZERO
	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	pos.x = cos(time * BOB_FREQ / 2) * BOB_AMP
	return pos

# --- LEDGE CLIMBING LOGIC ---

func check_for_ledge() -> bool:
	# Check if chest hits a wall, head space is clear, AND the downward ray finds a surface to stand on
	if wall_ray.is_colliding() and not ledge_check.is_colliding():
		if ledge_floor_check.is_colliding():
			return true
	return false

func start_ledge_climb() -> void:
	is_climbing = true
	velocity = Vector3.ZERO

	var wall_normal = wall_ray.get_collision_normal()
	var wall_point = wall_ray.get_collision_point()
	
	# GRAB EXACT SURFACE HEIGHT: Instead of using the ray's origin, we look at the exact collision spot.
	var exact_ledge_y = ledge_floor_check.get_collision_point().y
	
	# Define a 2-step animation path using the new precise height
	# Note: 1.01 matches a standard CharacterBody3D capsule pivot point standing perfectly on a floor.
	var climb_up_pos = Vector3(global_position.x, exact_ledge_y + 1.1, global_position.z)
	var climb_forward_pos = wall_point - (wall_normal * 0.6)
	climb_forward_pos.y = exact_ledge_y + 1.01

	var tween = create_tween().set_parallel(false)
	
	# Step 1: Smoothly pull up vertically
	tween.tween_property(self, "global_position:y", climb_up_pos.y, 0.3)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		
	# Step 2: Push forward onto solid ground
	tween.tween_property(self, "global_position", climb_forward_pos, 0.25)\
		.set_trans(Tween.TRANS_LINEAR)
		
	tween.tween_callback(finish_climbing)

func finish_climbing() -> void:
	is_climbing = false

func change_person() -> void:
	is_first_person = !is_first_person # Wissel de boolean om
	if is_first_person:
		camera_base_pos = Vector3(0, 0, 0) # Of je originele ooghoogte
	else:
		camera_base_pos = Vector3(0, 1.5, 3.0) # 3 meter naar achteren
	print("Perspectief veranderd")
	
func _input(ev):
	if Input.is_key_pressed(KEY_K):
		change_person()
