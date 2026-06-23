extends Control

@onready var main_buttons = $CenterContainer
@onready var settings_panel = $SettingsPanel
@onready var how_to_play_panel = $HowToPlayPanel

@onready var volume_slider = $SettingsPanel/CenterContainer/VBoxContainer/VolumeRow/VolumeSlider
@onready var volume_value = $SettingsPanel/CenterContainer/VBoxContainer/VolumeRow/VolumeValue
@onready var fullscreen_check = $SettingsPanel/CenterContainer/VBoxContainer/FullscreenRow/FullscreenCheck
@onready var aspect_option = $SettingsPanel/CenterContainer/VBoxContainer/AspectRow/AspectOption
@onready var resolution_option = $SettingsPanel/CenterContainer/VBoxContainer/ResolutionRow/ResolutionOption
@onready var cards_container = $HowToPlayPanel/CenterContainer/VBoxContainer/ScrollContainer/CardsContainer

const SETTINGS_PATH := "user://settings.cfg"
const BASE_SCALE_SIZE := Vector2i(1920, 1080)

var resolutions := [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160)
]

var aspect_modes := [
	Window.CONTENT_SCALE_ASPECT_KEEP,
	Window.CONTENT_SCALE_ASPECT_EXPAND,
	Window.CONTENT_SCALE_ASPECT_IGNORE
]

var mechanics := [
	{
		"title": "Jump / Double Jump",
		"desc": "Press Space to jump. Press Space again while in the air to perform a double jump.",
		"key": "Space"
	},
	{
		"title": "Crouch",
		"desc": "Hold Ctrl to crouch. Movement speed is reduced while crouching.",
		"key": "Ctrl"
	},
	{
		"title": "Slide",
		"desc": "Hold Ctrl while running at speed to slide across the ground. Useful for passing under low obstacles.",
		"key": "Ctrl"
	},
	{
		"title": "Sprint",
		"desc": "Hold Shift to run faster than walking speed.",
		"key": "Shift"
	},
	{
		"title": "Wall Run",
		"desc": "Hold Space while airborne and near a wall to stick to it and run along its surface.",
		"key": "Space"
	},
	{
		"title": "Rope Swing",
		"desc": "Hold Space near a rope anchor to grab on and swing. Release Space to let go and fly forward.",
		"key": "Space"
	},
	{
		"title": "Ledge Climb",
		"desc": "Press Space near a ledge to pull yourself up and climb onto it.",
		"key": "Space"
	},
	{
		"title": "Camera Toggle",
		"desc": "Press K to switch between first-person and third-person camera views.",
		"key": "K"
	}
]


func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	_setup_window_scaling()
	_setup_option_buttons()
	_connect_signals()

	settings_panel.hide()
	how_to_play_panel.hide()

	_load_settings()
	_create_how_to_play_cards()


func _setup_window_scaling():
	var root := get_tree().root
	
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.content_scale_factor = 1.0


func _setup_option_buttons():
	aspect_option.clear()
	aspect_option.add_item("Keep")
	aspect_option.add_item("Expand")
	aspect_option.add_item("Ignore")
	aspect_option.selected = 1

	resolution_option.clear()
	for res in resolutions:
		resolution_option.add_item(str(res.x) + " x " + str(res.y))

	var default_index := resolutions.find(BASE_SCALE_SIZE)
	if default_index == -1:
		default_index = 2

	resolution_option.selected = default_index


func _connect_signals():
	_connect_signal_once(volume_slider.value_changed, Callable(self, "_on_volume_value_changed"))
	_connect_signal_once(fullscreen_check.toggled, Callable(self, "_on_fullscreen_toggled"))
	_connect_signal_once(aspect_option.item_selected, Callable(self, "_on_aspect_ratio_selected"))
	_connect_signal_once(resolution_option.item_selected, Callable(self, "_on_resolution_selected"))


func _connect_signal_once(signal_to_connect: Signal, callable: Callable):
	if not signal_to_connect.is_connected(callable):
		signal_to_connect.connect(callable)


func _on_start_pressed():
	get_tree().change_scene_to_file("res://World.tscn")


func _on_quit_pressed():
	get_tree().quit()


func _on_settings_pressed():
	main_buttons.hide()
	settings_panel.show()


func _on_how_to_play_pressed():
	main_buttons.hide()
	how_to_play_panel.show()


func _on_settings_back_pressed():
	settings_panel.hide()
	_save_settings()
	main_buttons.show()


func _on_how_to_play_back_pressed():
	how_to_play_panel.hide()
	main_buttons.show()


func _on_volume_value_changed(value: float):
	var volume_linear := value / 100.0

	if volume_linear <= 0.0:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), -80.0)
	else:
		var db := linear_to_db(volume_linear)
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), db)

	volume_value.text = str(int(value)) + "%"


func _on_fullscreen_toggled(toggled: bool):
	if toggled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_apply_selected_resolution()


func _on_aspect_ratio_selected(index: int):
	if index < 0 or index >= aspect_modes.size():
		return

	get_window().content_scale_aspect = aspect_modes[index]


func _on_resolution_selected(index: int):
	if index < 0 or index >= resolutions.size():
		return

	# Resolution veranderen zie je alleen goed in windowed mode.
	# Fullscreen gebruikt meestal gewoon je monitorresolutie.
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		fullscreen_check.set_pressed_no_signal(false)

	_apply_resolution(resolutions[index])


func _apply_selected_resolution():
	var index: int = resolution_option.selected

	if index < 0 or index >= resolutions.size():
		return

	_apply_resolution(resolutions[index])


func _apply_resolution(new_size: Vector2i):
	get_window().size = new_size

	# Window netjes centreren.
	var screen := DisplayServer.window_get_current_screen()
	var screen_size := DisplayServer.screen_get_size(screen)
	var centered_position := (screen_size - new_size) / 2

	DisplayServer.window_set_position(centered_position)


func _save_settings():
	var config := ConfigFile.new()

	config.set_value("audio", "master_volume", volume_slider.value)
	config.set_value("display", "fullscreen", fullscreen_check.button_pressed)
	config.set_value("display", "aspect_ratio", aspect_option.selected)
	config.set_value("display", "resolution", resolution_option.selected)

	var error := config.save(SETTINGS_PATH)

	if error != OK:
		print("Could not save settings. Error: ", error)


func _load_settings():
	var config := ConfigFile.new()
	var error := config.load(SETTINGS_PATH)

	if error != OK:
		# Geen settings file gevonden. Gebruik defaults.
		_on_volume_value_changed(volume_slider.value)
		_on_aspect_ratio_selected(aspect_option.selected)
		_apply_selected_resolution()
		return

	if config.has_section_key("audio", "master_volume"):
		var saved_volume = config.get_value("audio", "master_volume")
		volume_slider.set_value_no_signal(saved_volume)
		_on_volume_value_changed(saved_volume)

	if config.has_section_key("display", "aspect_ratio"):
		var saved_aspect = int(config.get_value("display", "aspect_ratio"))

		if saved_aspect >= 0 and saved_aspect < aspect_modes.size():
			aspect_option.select(saved_aspect)
			_on_aspect_ratio_selected(saved_aspect)

	if config.has_section_key("display", "resolution"):
		var saved_resolution = int(config.get_value("display", "resolution"))

		if saved_resolution >= 0 and saved_resolution < resolutions.size():
			resolution_option.select(saved_resolution)

	if config.has_section_key("display", "fullscreen"):
		var saved_fullscreen = bool(config.get_value("display", "fullscreen"))
		fullscreen_check.set_pressed_no_signal(saved_fullscreen)
		_on_fullscreen_toggled(saved_fullscreen)
	else:
		_apply_selected_resolution()


func _create_how_to_play_cards():
	# Voorkomt dubbele cards als je deze functie ooit opnieuw aanroept.
	for child in cards_container.get_children():
		child.queue_free()

	for mech in mechanics:
		var title_label := Label.new()
		title_label.text = mech["title"] + "  —  " + mech["key"]
		title_label.add_theme_font_size_override("font_size", 18)
		title_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95, 1))
		cards_container.add_child(title_label)

		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 20)
		margin.add_theme_constant_override("margin_bottom", 12)

		var desc_label := Label.new()
		desc_label.text = mech["desc"]
		desc_label.add_theme_font_size_override("font_size", 14)
		desc_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.72, 1))
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		margin.add_child(desc_label)
		cards_container.add_child(margin)
