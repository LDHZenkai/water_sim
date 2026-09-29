extends CanvasLayer
## Weather menu (Tab): sliders for every weather quantity, presets, and the
## sea's controls. Sliders set targets; the weather eases toward them and the
## sea builds or decays over the "sea builds over" time, so what you ask for
## arrives the way weather does. "Build the sea now" skips the wait.
const KEY := KEY_TAB
## key, label, min, max, step, unit
const ROWS := [
	["wind_speed", "Wind speed", 0.0, 35.0, 0.5, "m/s"],
	["wind_from", "Wind from", 0.0, 359.0, 1.0, "°"],
	["gustiness", "Gusts", 0.0, 1.0, 0.05, "%"],
	["fetch", "Fetch (open water upwind)", 0.7, 2.9, 0.02, "km"],
	["swell_height", "Swell height", 0.0, 8.0, 0.1, "m"],
	["swell_period", "Swell period", 6.0, 18.0, 0.5, "s"],
	["swell_from", "Swell from", 0.0, 359.0, 1.0, "°"],
	["clouds", "Cloud cover", 0.0, 1.0, 0.05, "%"],
	["rain", "Rain", 0.0, 1.0, 0.05, "%"],
	["fog", "Mist and fog", 0.0, 1.0, 0.05, "%"],
	["lightning", "Lightning", 0.0, 1.0, 0.05, "%"],
]
var weather: Node
var hud: Node
var panel: PanelContainer
var sliders := {}
var values := {}
var response: HSlider
var response_value: Label
var dynamic_box: CheckBox
var rogue_box: CheckBox
var summary: Label
var log_label: Label
var _syncing := false
var _mouse_before := Input.MOUSE_MODE_CAPTURED

func setup(live_weather: Node, heads_up: Node) -> void:
	weather = live_weather
	hud = heads_up
	layer = 10
	if not InputMap.has_action("weather_menu"):
		InputMap.add_action("weather_menu")
		var event := InputEventKey.new()
		event.physical_keycode = KEY
		InputMap.action_add_event("weather_menu", event)
	_build()
	panel.visible = false

func _build() -> void:
	panel = PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -470
	panel.offset_right = -16
	panel.offset_top = 16
	panel.offset_bottom = -16
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.045, 0.04, 0.82)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	var title := Label.new()
	title.text = "Weather  ·  Tab to close"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.75))
	box.add_child(title)
	summary = Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_color_override("font_color", Color(0.85, 0.85, 0.8))
	box.add_child(summary)
	var presets := HBoxContainer.new()
	for name in weather.ORDER:
		var button := Button.new()
		button.text = name
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_preset.bind(name))
		presets.add_child(button)
	box.add_child(presets)
	for row in ROWS:
		var head := HBoxContainer.new()
		var label := Label.new()
		label.text = row[1]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(label)
		var value := Label.new()
		value.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
		head.add_child(value)
		box.add_child(head)
		var slider := HSlider.new()
		slider.min_value = row[2]
		slider.max_value = row[3]
		slider.step = row[4]
		slider.focus_mode = Control.FOCUS_NONE
		slider.value_changed.connect(_changed.bind(row[0]))
		box.add_child(slider)
		sliders[row[0]] = slider
		values[row[0]] = value
	var head := HBoxContainer.new()
	var label := Label.new()
	label.text = "Sea builds over"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(label)
	response_value = Label.new()
	response_value.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	head.add_child(response_value)
	box.add_child(head)
	response = HSlider.new()
	response.min_value = 10.0
	response.max_value = 600.0
	response.step = 10.0
	response.focus_mode = Control.FOCUS_NONE
	response.value_changed.connect(func(v: float) -> void: weather.SEA.set("sea_response", v))
	box.add_child(response)
	dynamic_box = CheckBox.new()
	dynamic_box.text = "Weather changes on its own (fronts)"
	dynamic_box.focus_mode = Control.FOCUS_NONE
	dynamic_box.toggled.connect(func(on: bool) -> void: if not _syncing: weather.dynamic = on)
	box.add_child(dynamic_box)
	rogue_box = CheckBox.new()
	rogue_box.text = "Rogue waves in heavy seas (over %.1f m)" % weather.ROGUE_SEA
	rogue_box.focus_mode = Control.FOCUS_NONE
	rogue_box.toggled.connect(func(on: bool) -> void: if not _syncing: weather.rogues = on)
	box.add_child(rogue_box)
	var actions := HBoxContainer.new()
	var settle := Button.new()
	settle.text = "Build the sea now"
	settle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settle.pressed.connect(func() -> void: weather.settle_now())
	actions.add_child(settle)
	var rogue := Button.new()
	rogue.text = "Send a rogue wave"
	rogue.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rogue.pressed.connect(func() -> void: weather.summon_rogue())
	actions.add_child(rogue)
	box.add_child(actions)
	log_label = Label.new()
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.add_theme_font_size_override("font_size", 14)
	log_label.add_theme_color_override("font_color", Color(0.75, 0.78, 0.8))
	box.add_child(log_label)
	for control in [settle, rogue]:
		control.focus_mode = Control.FOCUS_NONE
	for button in presets.get_children():
		button.focus_mode = Control.FOCUS_NONE

func is_open() -> bool:
	return panel.visible

func toggle() -> void:
	panel.visible = not panel.visible
	if panel.visible:
		# The player has found the menu: the key hints can go.
		if hud: hud._hint_left = minf(hud._hint_left, 0.0)
		_mouse_before = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		sync()
	elif _mouse_before == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("weather_menu") and not event.is_echo():
		toggle()
		get_viewport().set_input_as_handled()
	elif panel.visible and event.is_action_pressed("pause"):
		toggle()
		get_viewport().set_input_as_handled()

## Slider positions from the weather's targets.
func sync() -> void:
	_syncing = true
	for key in sliders:
		sliders[key].value = _to_slider(key, float(weather.target[key]))
	response.value = weather.SEA.get("sea_response")
	dynamic_box.button_pressed = weather.dynamic
	rogue_box.button_pressed = weather.rogues
	_syncing = false

static func _to_slider(key: String, value: float) -> float:
	return log(value / 1000.0) / log(10.0) if key == "fetch" else value

static func _from_slider(key: String, value: float) -> float:
	return pow(10.0, value) * 1000.0 if key == "fetch" else value

func _changed(value: float, key: String) -> void:
	if _syncing: return
	weather.set_target(key, _from_slider(key, value))
	_syncing = true
	dynamic_box.button_pressed = false
	_syncing = false

func _preset(name: String) -> void:
	weather.apply_preset(name)
	sync()

static func format(key: String, value: float) -> String:
	match key:
		"wind_speed": return "%.1f m/s (force %d)" % [value, weather_force(value)]
		"wind_from", "swell_from": return "%03d°" % (roundi(value) % 360)
		"fetch": return "%d km" % roundi(value / 1000.0)
		"swell_height": return "%.1f m" % value
		"swell_period": return "%.1f s" % value
	return "%d%%" % roundi(value * 100.0)

static func weather_force(speed: float) -> int:
	return preload("res://scripts/weather.gd").beaufort(speed)

func _process(_delta: float) -> void:
	if not panel.visible: return
	for key in values:
		var wanted := format(key, float(weather.target[key]))
		var now := format(key, float(weather.current[key]))
		values[key].text = wanted if wanted == now else "%s  (now %s)" % [wanted, now]
	response_value.text = "%d s" % roundi(response.value)
	summary.text = weather.describe() + ("  ·  " + weather.preset.to_lower() + " weather, changing" if weather.dynamic else "")
	if hud: log_label.text = "Ship's log: " + hud.ship_log()
