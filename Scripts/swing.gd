extends Area3D

@onready var rope_root: Node3D = $".."

func _ready() -> void:
	print("SWING AREA SCRIPT IS LOADED")

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	print("BODY ENTERED: ", body.name)

	if body.is_in_group("player"):
		print("PLAYER CAN GRAB ROPE")
		body.can_grab_rope = true
		body.current_rope = rope_root

func _on_body_exited(body: Node3D) -> void:
	print("BODY EXITED: ", body.name)

	if body.is_in_group("player"):
		body.can_grab_rope = false
		body.current_rope = null
		body.is_hanging_on_rope = false
