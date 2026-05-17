extends CharacterBody3D

const SPEED = 15
const JUMP_VELOCITY = 14
const MAX_JUMP_HEIGHT = 10

# Separate gravity for rise and fall for more control
const RISE_GRAVITY = 30.0
const FALL_GRAVITY = 50.0

var jump_start_y := 0.0
var is_jumping := false

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		# Smooth cap — bleed off velocity near the top instead of hard cut
		if is_jumping and position.y >= jump_start_y + MAX_JUMP_HEIGHT * 0.75:
			var remaining = (jump_start_y + MAX_JUMP_HEIGHT) - position.y
			var blend = clamp(remaining / (MAX_JUMP_HEIGHT * 0.25), 0.0, 1.0)
			velocity.y = lerp(0.0, velocity.y, blend)

		if velocity.y < 0:
			velocity.y -= FALL_GRAVITY * delta
		else:
			velocity.y -= RISE_GRAVITY * delta
	else:
		is_jumping = false
		if Input.is_action_pressed("ui_accept"):
			velocity.y = JUMP_VELOCITY
			jump_start_y = position.y
			is_jumping = true

	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
