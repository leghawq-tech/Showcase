extends Node3D

@export var respawn_position: Vector3 = Vector3(0, 2, 0)

@onready var area: Area3D = $Area3D

func _ready() -> void:
	area.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		body.global_position = respawn_position
		
		if body is CharacterBody3D:
			body.velocity = Vector3.ZERO
