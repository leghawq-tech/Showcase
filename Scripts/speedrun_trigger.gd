extends Node3D

enum TriggerType { START, FINISH }

@export var trigger_type: TriggerType = TriggerType.START

signal triggered

@onready var area: Area3D = $Area3D

func _ready():
	area.body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if body.is_in_group("player"):
		triggered.emit()
