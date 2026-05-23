extends CharacterBody3D

@export var move_speed: float = 9.0
@export var acceleration: float = 60.0
@export var friction: float = 50.0
@export var jump_force: float = 10.0
@export var gravity: float = 30.0
@export var camera_sensitivity: float = 0.003
@export var camera_distance: float = 0
@export var camera_vertical_angle_min: float = -60.0
@export var camera_vertical_angle_max: float = 10.0

@onready var camera_pivot: Node3D = get_parent().get_node("CameraPivot")
@onready var spring_arm: SpringArm3D = camera_pivot.get_node("SpringArm3D")

var camera_yaw: float = 0.0
var camera_pitch: float = deg_to_rad(-20.0)

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	spring_arm.spring_length = camera_distance

func _unhandled_input(event: InputEvent):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		camera_yaw   -= event.relative.x * camera_sensitivity
		camera_pitch -= event.relative.y * camera_sensitivity
		camera_pitch  = clamp(
			camera_pitch,
			deg_to_rad(camera_vertical_angle_min),
			deg_to_rad(camera_vertical_angle_max)
		)
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta: float):
	# --- Camera pivot follows player ---
	camera_pivot.global_position = global_position
	camera_pivot.rotation.y = camera_yaw
	camera_pivot.rotation.x = camera_pitch

	# --- Read input ---
	var input_dir = Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down")
	)

	# --- Movement direction relative to camera ---
	var cam_basis = camera_pivot.global_transform.basis
	var forward = -cam_basis.z
	var right    =  cam_basis.x
	forward.y = 0.0
	right.y   = 0.0
	forward = forward.normalized()
	right   = right.normalized()

	var move_dir = (forward * -input_dir.y + right * input_dir.x)

	# --- Acceleration / friction (now frame-rate independent and properly scaled) ---
	if move_dir.length_squared() > 0.001:
		var target = move_dir.normalized() * move_speed
		velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
		velocity.z = move_toward(velocity.z, target.z, acceleration * delta)

		# Rotate player to face movement direction
		var target_angle = atan2(move_dir.x, move_dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, delta * 12.0)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, friction * delta)

	# --- Gravity ---
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.5

	# --- Jump ---
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_force

	move_and_slide()
