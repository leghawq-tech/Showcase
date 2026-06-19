extends Node3D

@onready var rope_visual: MeshInstance3D = $RopeVisual
@onready var top_point: Marker3D = $TopPoint
@onready var bottom_point: Marker3D = $BottomPoint

func _ready() -> void:
	reset_rope_visual()


func update_rope_visual(start_pos: Vector3, end_pos: Vector3) -> void:
	var direction: Vector3 = end_pos - start_pos
	var length: float = direction.length()

	if length <= 0.01:
		return

	var y_axis: Vector3 = direction.normalized()
	var temp_axis: Vector3 = Vector3.FORWARD

	if abs(y_axis.dot(temp_axis)) > 0.99:
		temp_axis = Vector3.RIGHT

	var x_axis: Vector3 = temp_axis.cross(y_axis).normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()

	var midpoint: Vector3 = start_pos + direction * 0.5

	var basis := Basis(x_axis, y_axis, z_axis)
	basis = basis.scaled(Vector3(1, length, 1))

	rope_visual.global_transform = Transform3D(basis, midpoint)


func reset_rope_visual() -> void:
	update_rope_visual(top_point.global_position, bottom_point.global_position)
