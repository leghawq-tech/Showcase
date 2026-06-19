extends CharacterBody3D

var speed
const WALK_SPEED = 5.0
const SPRINT_SPEED = 9.0
const JUMP_VELOCITY = 8
const SENSITIVITY = 0.004
const CROUCH_SPEED = 2.0

var _is_crouching: bool = false

var is_first_person: bool = false
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

var can_grab_rope: bool = false
var current_rope: Node3D = null
var is_hanging_on_rope: bool = false
var rope_grab_point: Vector3
var rope_hang_offset: Vector3 = Vector3(0, -1.2, 0)

# Crouch variables

var _is_sliding: bool = false
var slide_timer = 0.0
var slide_direction := Vector3.ZERO
var slide_velocity := Vector3.ZERO


const SLIDE_DURATION := 0.85
const SLIDE_MIN_START_SPEED := 13.0
const SLIDE_START_BOOST := 4.0
const SLIDE_FRICTION := 5.0
const SLIDE_STEER_FORCE := 5.0

@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var wall_ray = $Head/RayFacingWall
@onready var ledge_check = $Head/LegdeChecker
@onready var ledge_floor_check = $Head/LegdeChecker/LedgeFloorChecker
@onready var collision = $CollisionShape3D
@onready var ANIMATIONPLAYER = $AnimationPlayer 
@onready var head_check = $StandCheck
@onready var anim_tree = $AnimationTree
@onready var ray_right = %RayRight
@onready var ray_left = %RayLeft
@onready var tp_cam = $CameraPivot/SpringArm3D/ThirdPersonCamera
@onready var camera_pivot = $CameraPivot
@onready var armature = $Char_Rig
@onready var state_machine = anim_tree.get("parameters/playback")
@onready var rope_grab_marker: Marker3D = $RopeGrabPoint

var rope_pivot: Vector3
var rope_length: float = 0.0

@export var rope_gravity: float = 20.0
@export var rope_input_force: float = 22.0
@export var min_rope_length: float = 1.2



func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	camera_base_pos = camera.transform.origin
	head.rotation.y = 0  # make sure head isn't offsetting the body rotation
	camera.make_current()
	head_check.add_exception(self)
	add_to_group("player")
	print("PLAYER GROUPS: ", get_groups())
	
	var stand_top = STAND_POS_Y + STAND_HEIGHT / 2.0
	var crouch_top = CROUCH_POS_Y + CROUCH_HEIGHT / 2.0
	
	head_check.position.y = crouch_top
	head_check.target_position = Vector3(0, stand_top - crouch_top, 0)
	
	anim_tree.active = true
	state_machine.start("Movement")

func _physics_process(delta):
	if is_climbing:
		return

	handle_rope_grab(delta)
	if is_hanging_on_rope:
		swing_on_rope(delta)
		return

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
		elif jump_count < 2 and not is_on_floor() and not _is_crouching and not (ray_left.is_colliding() or ray_right.is_colliding() or (wall_ray.is_colliding() and not ledge_check.is_colliding())):
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
	
	if _is_sliding:
		handle_slide(direction, delta)
	elif not is_on_floor() and can_wall_run == true and Input.is_action_pressed("ui_accept") and (ray_left.is_colliding() or ray_right.is_colliding()):
		velocity.y = 0
	else:
		_normal_run(direction, delta)
		var curr_speed = Vector2(velocity.x, velocity.z).length()
		anim_tree.set("parameters/Movement/blend_position", curr_speed)

	if Input.is_action_just_pressed("crouch"):
		if _is_crouching == false and is_on_floor():
			if Input.is_action_pressed("sprint") and Vector2(velocity.x, velocity.z).length() > WALK_SPEED:
				run_to_slide()
			else:
				_is_crouching = true
				state_machine.travel("CrouchIdle")
		
		elif _is_crouching == true and can_stand_up() and not _is_sliding:
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
	collision.shape.height = lerp(collision.shape.height, target_height, delta * 15)
	collision.position.y = lerp(collision.position.y, target_pos_y, delta * 15)
	
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

func handle_rope_grab(_delta: float) -> void:
	var wants_to_grab := can_grab_rope and current_rope != null and Input.is_action_pressed("ui_accept")

	if wants_to_grab:
		if not is_hanging_on_rope:
			start_rope_swing()

		is_hanging_on_rope = true
	else:
		is_hanging_on_rope = false


func start_rope_swing() -> void:
	var top_point: Marker3D = current_rope.get_node("TopPoint")

	rope_pivot = top_point.global_position

	var closest_grab_point := get_closest_point_on_rope()

	# Zet je hand/borst marker op het punt waar je het touw pakt
	var marker_offset: Vector3 = rope_grab_marker.global_position - global_position
	global_position = closest_grab_point - marker_offset

	# Lengte van het touw vanaf bovenkant naar waar je hem pakt
	rope_length = rope_pivot.distance_to(closest_grab_point)
	rope_length = max(rope_length, min_rope_length)


func swing_on_rope(delta: float) -> void:
	velocity.y -= rope_gravity * delta

	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var move_dir := Vector3(input_dir.x, 0, input_dir.y).normalized()

	if move_dir.length() > 0:
		velocity += move_dir * rope_input_force * delta

	move_and_slide()
	constrain_to_rope()

	if current_rope and current_rope.has_method("update_rope_visual"):
		current_rope.update_rope_visual(rope_pivot, rope_grab_marker.global_position)


func constrain_to_rope() -> void:
	var marker_offset: Vector3 = rope_grab_marker.global_position - global_position
	var marker_pos: Vector3 = rope_grab_marker.global_position

	var from_pivot: Vector3 = marker_pos - rope_pivot
	var distance: float = from_pivot.length()

	if distance == 0:
		return

	if distance > rope_length:
		var rope_dir: Vector3 = from_pivot.normalized()

		var corrected_marker_pos: Vector3 = rope_pivot + rope_dir * rope_length
		global_position = corrected_marker_pos - marker_offset

		# Haal snelheid weg die van het touw af trekt
		var outward_speed: float = velocity.dot(rope_dir)
		if outward_speed > 0:
			velocity -= rope_dir * outward_speed


func get_closest_point_on_rope() -> Vector3:
	var top_point: Marker3D = current_rope.get_node("TopPoint")
	var bottom_point: Marker3D = current_rope.get_node("BottomPoint")

	var top: Vector3 = top_point.global_position
	var bottom: Vector3 = bottom_point.global_position

	return get_closest_point_on_line(top, bottom, rope_grab_marker.global_position)


func get_closest_point_on_line(a: Vector3, b: Vector3, point: Vector3) -> Vector3:
	var ab: Vector3 = b - a
	var t: float = (point - a).dot(ab) / ab.dot(ab)
	t = clamp(t, 0.0, 1.0)

	return a + ab * t

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
		
func run_to_slide() -> void:
	if not is_on_floor():
		return
	
	if _is_sliding:
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
