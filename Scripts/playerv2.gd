extends CharacterBody3D

# Constants: Movement
const WALK_SPEED = 5.0
const SPRINT_SPEED = 9.0
const CROUCH_SPEED = 2.0
const JUMP_VELOCITY = 8

# Constants: Gravity & Jump
const BASE_GRAVITY = 18.0
const FALL_GRAVITY_MULT = 1.6

# Constants: Camera & FOV
const SENSITIVITY = 0.004
const BASE_FOV = 70.0
const FOV_CHANGE = 1.5

# Constants: Head Bob
const BOB_FREQ = 1.6
const BOB_AMP = 0.03

# Constants: Crouch / Slide
const STAND_HEIGHT = 1.873
const CROUCH_HEIGHT = 1.189
const STAND_POS_Y = 0.823
const CROUCH_POS_Y = 0.481

const SLIDE_DURATION := 0.85
const SLIDE_MIN_START_SPEED := 13.0
const SLIDE_START_BOOST := 4.0
const SLIDE_FRICTION := 5.0
const SLIDE_STEER_FORCE := 5.0

# Constants: Rope Swing
const SWING_GRAVITY := 15.0
const SWING_INPUT_FORCE := 10.0
const SWING_MIN_LENGTH := 1.5
const SWING_RELEASE_BOOST := 1.3
const SWING_DAMPING := 0.99
const SWING_MAX_SPEED := 25.0

# State: Movement
var speed: float
var jump_count: int
var can_wall_run: bool = false
var t_bob: float = 0.0
var camera_base_pos := Vector3.ZERO

# State: Crouch / Slide
var _is_crouching: bool = false
var _is_sliding: bool = false
var slide_timer: float = 0.0
var slide_direction := Vector3.ZERO
var slide_velocity := Vector3.ZERO

# State: Ledge Climb
var _is_climbing: bool = false

# State: Camera
var is_first_person: bool = false

# State: Rope Swing
var _is_swinging: bool = false
var _swing_pivot: Vector3
var _swing_length: float = 0.0
var _near_rope: Node3D = null
var _swing_anchor_body: StaticBody3D = null

# Node References: Scene tree
@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var wall_ray = $Head/RayFacingWall
@onready var ledge_check = $Head/LegdeChecker
@onready var ledge_floor_check = $Head/LegdeChecker/LedgeFloorChecker
@onready var collision = $CollisionShape3D
@onready var head_check = $StandCheck
@onready var anim_tree = $AnimationTree
@onready var ray_right = %RayRight
@onready var ray_left = %RayLeft
@onready var tp_cam = $CameraPivot/SpringArm3D/ThirdPersonCamera
@onready var state_machine = anim_tree.get("parameters/playback")
@onready var push_zone = $PushZone if has_node("PushZone") else null


# _ready
func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	camera_base_pos = camera.transform.origin
	head.rotation.y = 0
	camera.make_current()
	head_check.add_exception(self)
	add_to_group("player")

	var stand_top = STAND_POS_Y + STAND_HEIGHT / 2.0
	var crouch_top = CROUCH_POS_Y + CROUCH_HEIGHT / 2.0
	head_check.position.y = crouch_top
	head_check.target_position = Vector3(0, stand_top - crouch_top, 0)

	if push_zone:
		push_zone.body_entered.connect(_on_rope_zone_entered)
		push_zone.body_exited.connect(_on_rope_zone_exited)

	anim_tree.active = true
	state_machine.start("Movement")


# _physics_process  (orchestrator — delegates to sub-methods)

func _physics_process(delta):
	if _is_climbing:
		return

	if _is_swinging:
		_swing_physics(delta)
		return

	_apply_snappy_gravity(delta)
	_handle_rope_grab_input()
	_handle_jump_or_ledge()
	_handle_camera_toggle()
	_handle_sprint_speed()
	_handle_movement(delta)
	_handle_crouch_slide_input()
	_apply_headbob_and_fov(delta)
	_apply_collision_crouch(delta)

	move_and_slide()


# Gravity
func _apply_snappy_gravity(delta: float) -> void:
	if not is_on_floor():
		if velocity.y > 0:
			velocity.y -= BASE_GRAVITY * delta
		else:
			velocity.y -= (BASE_GRAVITY * FALL_GRAVITY_MULT) * delta


func _handle_jump_or_ledge() -> void:
	if _is_swinging or not Input.is_action_just_pressed("ui_accept") or _is_crouching:
		return

	if is_on_floor():
		velocity.y = JUMP_VELOCITY
		can_wall_run = false
		jump_count = 1
		await get_tree().create_timer(0.2).timeout
		can_wall_run = true

	elif jump_count < 2 and not is_on_floor() and not _is_crouching \
	and not (ray_left.is_colliding() or ray_right.is_colliding() \
	or (wall_ray.is_colliding() and not ledge_check.is_colliding())):
		velocity.y = JUMP_VELOCITY * 0.9
		jump_count += 1
		can_wall_run = false
		await get_tree().create_timer(0.2).timeout
		can_wall_run = true

	elif check_for_ledge():
		start_ledge_climb()


# Rope Grab Input
func _handle_rope_grab_input() -> void:
	if _near_rope != null and not _is_swinging \
	and Input.is_action_pressed("ui_accept") and not _is_crouching:
		_start_swing()


# Camera Toggle
func _handle_camera_toggle() -> void:
	if Input.is_action_just_pressed("Camera Toggle"):
		change_person()


# Sprint Speed
func _handle_sprint_speed() -> void:
	if Input.is_action_pressed("sprint") and not _is_crouching:
		speed = SPRINT_SPEED
	elif not _is_crouching:
		speed = WALK_SPEED
	else:
		speed = CROUCH_SPEED


# Movement (slide / wall-run / normal)
func _handle_movement(delta: float) -> void:
	var input_dir2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var forward = -transform.basis.z
	var right = transform.basis.x
	forward.y = 0
	right.y = 0
	var direction = (forward * -input_dir2.y + right * input_dir2.x).normalized()

	if _is_sliding:
		handle_slide(direction, delta)
	elif not is_on_floor() and can_wall_run \
	and Input.is_action_pressed("ui_accept") \
	and (ray_left.is_colliding() or ray_right.is_colliding()):
		velocity.y = 0
	else:
		_normal_run(direction, delta)
		var curr_speed = Vector2(velocity.x, velocity.z).length()
		anim_tree.set("parameters/Movement/blend_position", curr_speed)


# Crouch / Slide Input
func _handle_crouch_slide_input() -> void:
	if not Input.is_action_just_pressed("crouch"):
		return

	if not _is_crouching and is_on_floor():
		if Input.is_action_pressed("sprint") \
		and Vector2(velocity.x, velocity.z).length() > WALK_SPEED:
			run_to_slide()
		else:
			_is_crouching = true
			state_machine.travel("CrouchIdle")

	elif _is_crouching and can_stand_up() and not _is_sliding:
		_is_crouching = false
		state_machine.travel("Movement")


# Head Bob & FOV
func _apply_headbob_and_fov(delta: float) -> void:
	t_bob += delta * velocity.length() * float(is_on_floor())
	camera.transform.origin = camera_base_pos + _headbob(t_bob)

	var velocity_clamped = clamp(velocity.length(), 0.5, SPRINT_SPEED * 2)
	var target_fov = BASE_FOV + FOV_CHANGE * velocity_clamped
	camera.fov = lerp(camera.fov, target_fov, delta * 8.0)
	tp_cam.fov = lerp(camera.fov, target_fov, delta * 8.0)


# Collision Capsule (crouch resize)
func _apply_collision_crouch(delta: float) -> void:
	var target_height = CROUCH_HEIGHT if _is_crouching else STAND_HEIGHT
	var target_pos_y = CROUCH_POS_Y if _is_crouching else STAND_POS_Y
	collision.shape.height = lerp(collision.shape.height, target_height, delta * 15)
	collision.position.y = lerp(collision.position.y, target_pos_y, delta * 15)


# Movement Helpers
func _normal_run(direction: Vector3, delta: float) -> void:
	velocity.x = lerp(velocity.x, direction.x * speed, delta * 7.0)
	velocity.z = lerp(velocity.z, direction.z * speed, delta * 7.0)


func _headbob(time: float) -> Vector3:
	var pos = Vector3.ZERO
	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	pos.x = cos(time * BOB_FREQ / 2) * BOB_AMP
	return pos


# Ledge Climbing
func check_for_ledge() -> bool:
	if wall_ray.is_colliding() and not ledge_check.is_colliding():
		if ledge_floor_check.is_colliding():
			return true
	return false

func start_ledge_climb() -> void:
	_is_climbing = true
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
	tween.tween_callback(_finish_climbing)

func _finish_climbing() -> void:
	_is_climbing = false


# Rope Swing — Detection

func _on_rope_zone_entered(body: Node3D) -> void:
	var parent = body.get_parent()
	if parent and parent is StaticBody3D:
		var anchor = parent.get_parent()
		if anchor and anchor.name == "RopeAnchor":
			_near_rope = anchor

func _on_rope_zone_exited(body: Node3D) -> void:
	var parent = body.get_parent()
	if parent and parent is StaticBody3D:
		var anchor = parent.get_parent()
		if anchor and anchor == _near_rope:
			_near_rope = null

# Rope Swing — Physics
func _start_swing() -> void:
	_is_swinging = true
	_swing_anchor_body = _near_rope.get_node("StaticBody3D")
	_swing_pivot = _swing_anchor_body.global_position
	_swing_length = max(_swing_pivot.distance_to(global_position), SWING_MIN_LENGTH)

func _swing_physics(delta: float) -> void:
	var to_pivot := _swing_pivot - global_position
	var rope_dir := to_pivot.normalized()

	var gravity_vec := Vector3(0, -SWING_GRAVITY, 0)
	var radial_g := gravity_vec.dot(rope_dir) * rope_dir
	velocity += (gravity_vec - radial_g) * delta

	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var move_dir := Vector3(input_dir.x, 0, input_dir.y).normalized()
	if move_dir.length() > 0:
		var radial_input := move_dir.dot(rope_dir) * rope_dir
		velocity += (move_dir - radial_input) * SWING_INPUT_FORCE * delta

	velocity *= SWING_DAMPING
	velocity = velocity.limit_length(SWING_MAX_SPEED)
	move_and_slide()
	_constrain_swing()
	if _swing_anchor_body and _swing_anchor_body.has_method("update_rope_to_player"):
		_swing_anchor_body.update_rope_to_player(global_position)

func _constrain_swing() -> void:
	var to_pivot := _swing_pivot - global_position
	var distance := to_pivot.length()
	if distance == 0:
		return

	if distance > _swing_length:
		var dir := to_pivot.normalized()
		global_position = _swing_pivot - dir * _swing_length

		var outward_speed := velocity.dot(-dir)
		if outward_speed > 0:
			velocity -= (-dir) * outward_speed

	if not Input.is_action_pressed("ui_accept"):
		_release_swing()

func _release_swing() -> void:
	_is_swinging = false
	velocity *= SWING_RELEASE_BOOST
	_swing_anchor_body = null

# Camera: First / Third Person
func change_person() -> void:
	is_first_person = !is_first_person
	if is_first_person:
		camera.make_current()
	else:
		tp_cam.make_current()

func _unhandled_input(event):
	if _is_climbing:
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * SENSITIVITY)
		camera.rotate_x(-event.relative.y * SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-60), deg_to_rad(70))

		tp_cam.rotate_x(-event.relative.y * SENSITIVITY)
		tp_cam.rotation.x = clamp(camera.rotation.x, deg_to_rad(-60), deg_to_rad(30))


# Slide

func run_to_slide() -> void:
	if not is_on_floor() or _is_sliding:
		return

	var horizontal_velocity := Vector3(velocity.x, 0, velocity.z)
	var current_speed := horizontal_velocity.length()

	if current_speed < WALK_SPEED:
		return

	_is_sliding = true
	_is_crouching = true
	slide_timer = SLIDE_DURATION

	if horizontal_velocity.length() > 0.1:
		slide_direction = horizontal_velocity.normalized()
	else:
		slide_direction = -transform.basis.z
		slide_direction.y = 0
		slide_direction = slide_direction.normalized()

	var start_speed = max(current_speed + SLIDE_START_BOOST, SLIDE_MIN_START_SPEED)
	slide_velocity = slide_direction * start_speed

	state_machine.travel("CrouchIdle")

func handle_slide(direction: Vector3, delta: float) -> void:
	slide_timer -= delta

	if direction.length() > 0:
		slide_direction = (slide_direction + direction * SLIDE_STEER_FORCE * delta).normalized()

	var current_slide_speed := slide_velocity.length()
	current_slide_speed = move_toward(current_slide_speed, 0.0, SLIDE_FRICTION * delta)

	slide_velocity = slide_direction * current_slide_speed

	velocity.x = slide_velocity.x
	velocity.z = slide_velocity.z

	if slide_timer <= 0.0 or current_slide_speed < WALK_SPEED:
		_is_sliding = false

		if Input.is_action_pressed("crouch"):
			_is_crouching = true
			state_machine.travel("CrouchIdle")
		elif head_check.is_colliding() == false:
			_is_crouching = false
			state_machine.travel("Movement")
		else:
			_is_crouching = true
			state_machine.travel("CrouchIdle")

func can_stand_up() -> bool:
	head_check.force_shapecast_update()
	return not head_check.is_colliding()
