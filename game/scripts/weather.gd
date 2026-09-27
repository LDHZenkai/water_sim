extends Node
## Live weather: wind (with gusts and squalls), swell, cloud, rain, fog and
## lightning. Values ease toward targets (set by the weather menu or, when
## dynamic, by passing weather fronts) and drive everything physical:
## the sea state (sea_state.gd builds a new wind sea as the wind changes and
## the old one decays), the wind on the rig (buoyancy.gd), and the atmosphere
## (atmosphere.gd). In heavy seas it also schedules rogue waves: dispersive
## focusing groups aimed at where the ship will be.
signal lightning_strike(direction: Vector3, distance: float, power: float)
signal notice(text: String, seconds: float)
## How the ship met a rogue wave: "bow" (climbed it), "beam" (knocked down)
## or "stern" (pooped). side: +1 when the wave came from port.
signal rogue_passed(how: String, side: float)

const SEA = preload("res://ocean/default_sea.tres")
const KEYS := ["wind_speed", "wind_from", "gustiness", "fetch", "swell_height", "swell_period", "swell_from", "clouds", "rain", "fog", "lightning"]
## Beaufort-style presets. Bearings are compass degrees the wind or swell
## comes FROM (north = -Z, east = +X). Fetch in metres of open water.
const PRESETS := {
	"Calm": {"wind_speed": 3.0, "gustiness": 0.2, "fetch": 20000.0, "swell_height": 1.0, "swell_period": 10.0, "clouds": 0.1, "rain": 0.0, "fog": 0.05, "lightning": 0.0},
	"Fair": {"wind_speed": 8.0, "gustiness": 0.25, "fetch": 30000.0, "swell_height": 2.4, "swell_period": 12.0, "clouds": 0.25, "rain": 0.0, "fog": 0.1, "lightning": 0.0},
	"Fresh": {"wind_speed": 12.0, "gustiness": 0.35, "fetch": 80000.0, "swell_height": 2.8, "swell_period": 12.0, "clouds": 0.55, "rain": 0.15, "fog": 0.15, "lightning": 0.0},
	"Gale": {"wind_speed": 18.0, "gustiness": 0.45, "fetch": 200000.0, "swell_height": 3.5, "swell_period": 13.0, "clouds": 0.85, "rain": 0.55, "fog": 0.35, "lightning": 0.2},
	"Storm": {"wind_speed": 25.0, "gustiness": 0.55, "fetch": 220000.0, "swell_height": 4.0, "swell_period": 14.0, "clouds": 1.0, "rain": 0.9, "fog": 0.5, "lightning": 0.65},
}
const ORDER := ["Calm", "Fair", "Fresh", "Gale", "Storm"]
## Where a front goes next from each state.
const NEXT := {
	"Calm": {"Calm": 0.2, "Fair": 0.6, "Fresh": 0.2},
	"Fair": {"Calm": 0.2, "Fair": 0.25, "Fresh": 0.4, "Gale": 0.15},
	"Fresh": {"Fair": 0.35, "Fresh": 0.2, "Gale": 0.35, "Storm": 0.1},
	"Gale": {"Fresh": 0.35, "Gale": 0.2, "Storm": 0.45},
	"Storm": {"Gale": 0.65, "Storm": 0.35},
}
## Seconds for each quantity to close most of the gap to its target.
const EASE := {"wind_speed": 60.0, "wind_from": 90.0, "gustiness": 30.0, "fetch": 120.0, "swell_height": 150.0, "swell_period": 150.0, "swell_from": 150.0, "clouds": 45.0, "rain": 30.0, "fog": 60.0, "lightning": 30.0}

var current := {}
var target := {}
## Weather fronts change the targets on their own; any manual change stops it.
var dynamic := true
## Rogue waves may appear in seas above this significant height (m).
var rogues := true
const ROGUE_SEA := 3.5
var preset := "Fair"
var motion: RefCounted
var wave_count := 32
var gust := 1.0
var gust_veer := 0.0
var squall := 0.0
var rng := RandomNumberGenerator.new()
var _time := 0.0
var _phase_ends := 600.0
var _squall_ends := -1.0
var _next_lightning := 0.0
var _next_rogue := INF
var _rogue_warned := false
var _rogue_judged := true
var _gust_phase := PackedFloat32Array()
## Rogue waves met and how, for the ship's log.
var rogues_met := {"bow": 0, "beam": 0, "stern": 0}

func setup(ship_motion: RefCounted, count: int, start: String = "Fair", evolve := true) -> void:
	motion = ship_motion
	wave_count = count
	dynamic = evolve
	rng.seed = 90210
	for i in range(6): _gust_phase.append(rng.randf() * TAU)
	# Start from the sea state file so the default sea is exactly the tested one.
	var sea := sea_defaults()
	SEA.reset_live()
	current = {"wind_speed": sea.wind_speed, "wind_from": from_heading(sea.wind_heading), "gustiness": 0.25, "fetch": sea.fetch, "swell_height": sea.swell_height, "swell_period": sea.swell_period, "swell_from": from_heading(sea.swell_heading), "clouds": 0.25, "rain": 0.0, "fog": 0.1, "lightning": 0.0}
	if start != "Fair": current.merge(PRESETS[start], true)
	preset = start
	target = current.duplicate()
	process_physics_priority = -70
	_apply_to_sea()
	_next_lightning = 5.0

## The sea state file's own values, remembered before any weather touches the
## shared resource (restored when the world closes).
static func sea_defaults() -> Dictionary:
	if not SEA.has_meta("weather_defaults"):
		# get(): a property read through the preloaded constant is folded at
		# compile time to the file's value, not the live one.
		var values := {}
		for key in ["wind_speed", "wind_heading", "fetch", "swell_height", "swell_period", "swell_heading", "sea_response"]:
			values[key] = SEA.get(key)
		SEA.set_meta("weather_defaults", values)
	return SEA.get_meta("weather_defaults")

func _exit_tree() -> void:
	for key in sea_defaults():
		SEA.set(key, sea_defaults()[key])
	SEA.reset_live()

## Compass bearing (deg, from) <-> heading (rad, toward) in world XZ.
static func from_heading(heading: float) -> float:
	var toward := Vector2(cos(heading), sin(heading))
	return fposmod(rad_to_deg(atan2(-toward.x, toward.y)), 360.0)

static func heading_from(bearing: float) -> float:
	var b := deg_to_rad(bearing)
	# Wind from bearing b blows toward (-sin b, cos b) in XZ.
	return atan2(cos(b), -sin(b))

static func beaufort(speed: float) -> int:
	var limits := [0.5, 1.6, 3.4, 5.5, 8.0, 10.8, 13.9, 17.2, 20.8, 24.5, 28.5, 32.7]
	for i in range(limits.size()):
		if speed < limits[i]: return i
	return 12

static func beaufort_name(force: int) -> String:
	return ["Calm", "Light air", "Light breeze", "Gentle breeze", "Moderate breeze", "Fresh breeze", "Strong breeze", "Near gale", "Gale", "Strong gale", "Storm", "Violent storm", "Hurricane"][clampi(force, 0, 12)]

## Set one target by hand (weather menu). Stops the fronts from overriding it.
func set_target(key: String, value: float) -> void:
	target[key] = value
	dynamic = false

func apply_preset(name: String) -> void:
	target.merge(PRESETS[name], true)
	preset = name

## Skip the build-up: weather and sea jump to the targets now.
func settle_now() -> void:
	current = target.duplicate()
	_apply_to_sea()
	SEA.settle(_time, wave_count)

func sea_height() -> float:
	return SEA.live_height(_time, wave_count)

## Instantaneous wind on the rig (m/s, world XZ, blowing toward).
func wind() -> Vector2:
	var speed: float = current.wind_speed * gust * (1.0 + squall * 0.45)
	var heading := heading_from(current.wind_from + gust_veer)
	return Vector2(cos(heading), sin(heading)) * speed

func _physics_process(delta: float) -> void:
	if get_node("/root/SimClock").frozen or motion == null: return
	_time = get_node("/root/SimClock").time
	if dynamic and _time >= _phase_ends: _next_front()
	for key in KEYS:
		var rate: float = 1.0 - exp(-delta / float(EASE[key]))
		if key.ends_with("_from"):
			current[key] = fposmod(current[key] + wrapf(target[key] - current[key], -180.0, 180.0) * rate, 360.0)
		elif key == "fetch":
			current[key] = exp(lerpf(log(current[key]), log(target[key]), rate))
		else:
			current[key] = lerpf(current[key], target[key], rate)
	_gusts(delta)
	_apply_to_sea()
	SEA.evolve(_time, wave_count)
	motion.wind_vector = wind()
	_lightning()
	_rogue_waves()

func _gusts(delta: float) -> void:
	# Turbulent gusts: incommensurate periods of 7, 19 and 53 s, plus veer.
	var g: float = current.gustiness
	var n := 0.5 * sin(_time * TAU / 7.0 + _gust_phase[0]) + 0.3 * sin(_time * TAU / 19.0 + _gust_phase[1]) + 0.2 * sin(_time * TAU / 53.0 + _gust_phase[2])
	gust = 1.0 + g * 0.45 * n
	gust_veer = g * 10.0 * (0.6 * sin(_time * TAU / 23.0 + _gust_phase[3]) + 0.4 * sin(_time * TAU / 61.0 + _gust_phase[4]))
	# Squalls: short, violent gust fronts with a burst of rain.
	if current.wind_speed > 10.0 and _squall_ends < _time and rng.randf() < delta * current.gustiness / 240.0:
		_squall_ends = _time + rng.randf_range(30.0, 70.0)
		notice.emit("Squall!", 4.0)
	var squalling := 1.0 if _time < _squall_ends else 0.0
	squall = move_toward(squall, squalling, delta / 8.0)

func _apply_to_sea() -> void:
	# set(): SEA is a preloaded constant, its properties are not assignable by name.
	SEA.set("wind_speed", maxf(current.wind_speed, 0.5))
	SEA.set("wind_heading", heading_from(current.wind_from))
	SEA.set("fetch", current.fetch)
	SEA.set("swell_height", current.swell_height)
	SEA.set("swell_period", current.swell_period)
	SEA.set("swell_heading", heading_from(current.swell_from))

## A new front: pick where the weather goes and how long it takes, veer the wind.
func _next_front() -> void:
	var roll := rng.randf()
	var choices: Dictionary = NEXT[preset]
	var next := preset
	for name in choices:
		roll -= float(choices[name])
		if roll <= 0.0:
			next = name
			break
	target.merge(PRESETS[next], true)
	target.wind_from = fposmod(target.wind_from + rng.randf_range(-35.0, 35.0), 360.0)
	if next != preset:
		var worse := ORDER.find(next) > ORDER.find(preset)
		notice.emit(("The weather is worsening: " if worse else "The weather is easing: ") + next.to_lower(), 6.0)
	preset = next
	_phase_ends = _time + rng.randf_range(180.0, 420.0)

func _lightning() -> void:
	var activity: float = current.lightning * (0.6 + 0.4 * current.rain)
	if activity < 0.02 or _time < _next_lightning: return
	_next_lightning = _time + rng.randf_range(4.0, 40.0) / activity
	var bearing := rng.randf() * TAU
	var distance := rng.randf_range(600.0, 6000.0) * lerpf(1.3, 0.6, activity)
	lightning_strike.emit(Vector3(cos(bearing), 0.0, sin(bearing)), distance, rng.randf_range(0.5, 1.0))

## Rogue waves in heavy seas (or when summoned): a focusing group aimed at the
## ship's water position ~50 s ahead. The lookout calls it; meet it bow-on.
func _rogue_waves() -> void:
	var height := sea_height()
	if rogues and height > ROGUE_SEA and _next_rogue == INF:
		_next_rogue = _time + rng.randf_range(120.0, 360.0)
	if height <= ROGUE_SEA and SEA.rogue().is_empty():
		_next_rogue = INF
	if _time >= _next_rogue:
		summon_rogue()
	var rogue: Dictionary = SEA.rogue()
	if rogue.is_empty(): return
	var until: float = float(rogue.focus_time) - _time
	if not _rogue_warned and until < 22.0:
		_rogue_warned = true
		var comes_from: Vector2 = -rogue.direction
		var relative := rad_to_deg(motion.forward().angle_to(comes_from))
		notice.emit("Rogue wave! Bearing %03d°, %s — turn into it!" % [roundi(fposmod(rad_to_deg(atan2(comes_from.x, -comes_from.y)), 360.0)), _relative_bearing(relative)], 8.0)
	if not _rogue_judged and until < 0.0:
		_rogue_judged = true
		var off_bow: float = rad_to_deg(motion.forward().angle_to(-rogue.direction))
		var into := absf(off_bow)
		var how := "bow" if into < 35.0 else ("stern" if into > 145.0 else "beam")
		rogues_met[how] += 1
		notice.emit({"bow": "Met the rogue wave bow-on!", "beam": "Knocked down by the rogue wave!", "stern": "Pooped! The rogue wave broke over the stern."}[how], 6.0)
		rogue_passed.emit(how, 1.0 if off_bow < 0.0 else -1.0)

static func _relative_bearing(degrees: float) -> String:
	# Negative angle from the bow is to port (world +Z is south).
	var side := "port" if degrees < 0.0 else "starboard"
	var a := absf(degrees)
	if a < 20.0: return "dead ahead"
	if a > 160.0: return "dead astern"
	if a < 70.0: return "off the %s bow" % side
	if a < 110.0: return "on the %s beam" % side
	return "off the %s quarter" % side

## Send a rogue wave now (menu, or the storm itself). Crest ~ 2 x Hs, at least 4 m.
func summon_rogue(lead := 50.0) -> void:
	var focus_time := _time + lead
	var water_position: Vector2 = -(motion.drift + motion.water_velocity() * lead)
	var crest := maxf(2.0 * sea_height(), 4.0)
	SEA.spawn_rogue(_time, focus_time, water_position, crest, wave_count)
	_next_rogue = INF if not rogues else _time + rng.randf_range(300.0, 600.0)
	_rogue_warned = false
	_rogue_judged = false

func describe() -> String:
	var force := beaufort(current.wind_speed)
	return "Force %d, %s, %.0f m/s from %03d°; sea %.1f m" % [force, beaufort_name(force).to_lower(), current.wind_speed, roundi(current.wind_from) % 360, sea_height()]
