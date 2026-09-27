extends CanvasLayer
## On-screen voice of the ship: the lookout's and the weather's notices
## (squalls, fronts, rogue waves), the helmsman's warnings (surfing,
## broaching, overpressed canvas) and how the player is keeping their feet.
## A key hint fades after the first seconds.
var weather: Node
var motion: RefCounted
var player: CharacterBody3D
var notice_label: Label
var status_label: Label
var hint_label: Label
var _notice_left := 0.0
var _hint_left := 14.0
var _cooldown := {}
var _surfing := 0.0
## The ship's log: shown in the weather menu.
var voyage := {"distance": 0.0, "top_speed": 0.0, "longest_surf": 0.0, "knockdowns": 0}

func setup(live_weather: Node, ship_motion: RefCounted, actor: CharacterBody3D) -> void:
	weather = live_weather
	motion = ship_motion
	player = actor
	layer = 5
	notice_label = _label(28, Color(1.0, 0.93, 0.78))
	notice_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	notice_label.offset_left = -600
	notice_label.offset_right = 600
	notice_label.offset_top = 70
	notice_label.offset_bottom = 120
	status_label = _label(18, Color(0.95, 0.85, 0.7))
	status_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	status_label.offset_left = -400
	status_label.offset_right = 400
	status_label.offset_top = -150
	status_label.offset_bottom = -120
	hint_label = _label(16, Color(0.9, 0.88, 0.82))
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	hint_label.offset_left = -520
	hint_label.offset_right = -24
	hint_label.offset_top = 20
	hint_label.offset_bottom = 120
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint_label.text = "Tab · weather\nE · take the helm (at the wheel on the poop deck)\nQ · hold to brace against the ship's motion"
	weather.notice.connect(show_notice)

func _label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

func show_notice(text: String, seconds: float) -> void:
	notice_label.text = text
	_notice_left = seconds

## A notice at most once per cooldown seconds.
func _warn(key: String, text: String, cooldown: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < float(_cooldown.get(key, -INF)): return
	_cooldown[key] = now + cooldown
	show_notice(text, 4.0)

func _process(delta: float) -> void:
	if weather == null: return
	_notice_left -= delta
	notice_label.modulate.a = clampf(_notice_left, 0.0, 1.0)
	_hint_left -= delta
	hint_label.modulate.a = clampf(_hint_left / 3.0, 0.0, 1.0)
	var frozen: bool = get_node("/root/SimClock").frozen
	if frozen: return
	# The log.
	voyage.distance += float(motion.speed) * delta
	voyage.top_speed = maxf(voyage.top_speed, motion.knots())
	if float(motion.surf) > 0.25:
		_surfing += delta
		voyage.longest_surf = maxf(voyage.longest_surf, _surfing)
		if _surfing > 1.5: _warn("surf", "Surfing down the face of a sea!", 20.0)
	else:
		_surfing = 0.0
	if absf(float(motion.broach)) > 0.004: _warn("broach", "She's broaching! Meet her with the helm.", 15.0)
	if motion.overpressed(): _warn("heel", "Overpressed. Take in sail (S at the helm).", 30.0)
	# Keeping one's feet.
	var legs = player.sea_legs
	var status := ""
	if legs.sliding: status = "Sliding! Hold Q to brace"
	elif legs.off_balance > 0.25 and not player.braced: status = "Losing your footing. Q to brace"
	elif player.braced and not player.at_helm and legs.lateral.length() > 0.15: status = "Braced"
	status_label.text = status

func ship_log() -> String:
	var met: Dictionary = weather.rogues_met
	return "Sailed %.2f nm · best %.1f kn · longest surf %.0f s · rogue waves met bow-on %d, knocked down %d, pooped %d" % [voyage.distance / 1852.0, voyage.top_speed, voyage.longest_surf, met.bow, met.beam, met.stern]
