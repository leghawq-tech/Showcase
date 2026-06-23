extends Control

@onready var pause_panel = $PausePanel
@onready var timer_label = $TimerLabel

var _elapsed: float = 0.0
var _running: bool = false

func _ready():
	pause_panel.hide()

func _process(delta):
	if _running:
		_elapsed += delta
		timer_label.text = _format_time(_elapsed)

func start_timer():
	reset_timer()
	_running = true

func stop_timer():
	_running = false

func reset_timer():
	_elapsed = 0.0
	_running = false
	timer_label.text = "00:00.000"

func _format_time(seconds: float) -> String:
	var mins = int(seconds / 60)
	var secs = int(seconds) % 60
	var millis = int(seconds * 1000) % 1000
	return "%02d:%02d.%03d" % [mins, secs, millis]

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):
		toggle_pause()
		get_viewport().set_input_as_handled()

func toggle_pause():
	get_tree().paused = not get_tree().paused
	pause_panel.visible = get_tree().paused
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if get_tree().paused else Input.MOUSE_MODE_CAPTURED)

func _on_resume_pressed():
	toggle_pause()

func _on_quit_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")
