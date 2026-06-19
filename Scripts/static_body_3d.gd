extends StaticBody3D

@export var segment_scene: PackedScene
@export var rope_length: int = 10
@export var segment_offset: float = 0.5 # Distance between segments

var _segments: Array[RigidBody3D] = []

func _ready():
	generate_rope()

func generate_rope():
	var previous_node = self # Start by attaching the first segment to the anchor
	
	for i in range(rope_length):
		# 1. Spawn the segment
		var segment = segment_scene.instantiate()
		add_child(segment)
		if i == rope_length - 1:
	# Maak het laatste segment iets zwaarder zodat het touw strak trekt
			segment.mass = 0.5 
		else:
			segment.mass = 0.1

		# 2. Position it below the previous node
		# (Assuming the anchor is at 0,0,0, segments go down the Y axis)
		segment.global_position = global_position - Vector3(0, i * segment_offset, 0)
		
		# 3. Connect the joint
		var joint = segment.get_node("PinJoint3D") # Or ConeTwistJoint3D
		
		# In Godot 4, joints require NodePaths
		joint.node_a = joint.get_path_to(previous_node)
		joint.node_b = joint.get_path_to(segment)
		
		# 4. Make this segment the new "previous" node for the next loop
		previous_node = segment
		_segments.append(segment)


func update_rope_to_player(player_pos: Vector3) -> void:
	if _segments.is_empty():
		return

	var bottom := _segments[-1]
	var to_target := player_pos - bottom.global_position
	var distance := to_target.length()

	if distance < 0.01:
		bottom.linear_velocity = Vector3.ZERO
		return

	var spring_strength := 1200.0
	var damping := 0.85

	bottom.apply_central_force(to_target.normalized() * spring_strength)
	bottom.linear_velocity *= damping
