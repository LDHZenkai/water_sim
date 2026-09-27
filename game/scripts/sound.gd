extends Node
## Procedural sound of the ship at sea, synthesised at start-up (no sound
## files): wind in the rig and a whistle through the shrouds when it pipes
## up, the sea and the rush past the hull, rain, canvas slatting when the
## sails luff, thunder arriving at the speed of sound after each flash,
## timbers creaking as she rolls, and footsteps on the planking.
## Loops are shaped live by bus filters; the cabin muffles everything outside.
const RATE := 22050
const LOOP_SECONDS := 3.0
const SOUND_SPEED := 343.0
var weather: Node
var motion: RefCounted
var player: CharacterBody3D
var sails: RefCounted
## Callable(eye: Vector3) -> bool: under cover.
var indoors: Callable
var rng := RandomNumberGenerator.new()
var _players := {}
var _buses := {}
var _creaks: Array[AudioStreamWAV] = []
var _steps: Array[AudioStreamWAV] = []
var _thunder: AudioStreamWAV
var _pending_thunder: Array[Dictionary] = []
var _creak_wait := 2.0
var _clock := 0.0
var enabled := false

func setup(live_weather: Node, ship_motion: RefCounted, actor: CharacterBody3D, rig: RefCounted, cover: Callable) -> void:
	weather = live_weather
	motion = ship_motion
	player = actor
	sails = rig
	indoors = cover
	# Nothing to hear headless (tests), and synthesis costs start-up time.
	enabled = DisplayServer.get_name() != "headless" and not OS.has_feature("movie")
	if not enabled: return
	rng.seed = 777
	_bus("Outside", "Master", [_low_pass(20000.0)])
	_bus("Wind", "Outside", [_low_pass(800.0)])
	_bus("Whistle", "Outside", [_band_pass(1800.0, 4.0)])
	_bus("Sea", "Outside", [_low_pass(700.0)])
	_bus("Rain", "Outside", [_high_pass(1500.0)])
	_bus("Canvas", "Outside", [_band_pass(350.0, 1.0)])
	_bus("Thunder", "Master", [_low_pass(2000.0)])
	_bus("Ship", "Master", [])
	_loop("wind", _noise("pink"), "Wind")
	_loop("whistle", _noise("white"), "Whistle")
	_loop("sea", _noise("brown"), "Sea")
	_loop("rush", _noise("pink"), "Sea")
	_loop("rain", _noise("white"), "Rain")
	_loop("flap", _flap(), "Canvas")
	_thunder = _make_thunder()
	for i in range(3): _creaks.append(_make_creak(i))
	for i in range(4): _steps.append(_make_step(i))
	player.footstep.connect(_footstep)
	weather.lightning_strike.connect(_strike)

func _bus(name: String, send: String, effects: Array) -> void:
	var index := AudioServer.get_bus_index(name)
	if index < 0:
		index = AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, name)
		for effect in effects: AudioServer.add_bus_effect(index, effect)
	AudioServer.set_bus_send(index, send)
	_buses[name] = index

static func _low_pass(cutoff: float) -> AudioEffectLowPassFilter:
	var effect := AudioEffectLowPassFilter.new()
	effect.cutoff_hz = cutoff
	return effect

static func _high_pass(cutoff: float) -> AudioEffectHighPassFilter:
	var effect := AudioEffectHighPassFilter.new()
	effect.cutoff_hz = cutoff
	return effect

static func _band_pass(cutoff: float, resonance: float) -> AudioEffectBandPassFilter:
	var effect := AudioEffectBandPassFilter.new()
	effect.cutoff_hz = cutoff
	effect.resonance = resonance
	return effect

func _effect(bus: String, index := 0) -> AudioEffect:
	return AudioServer.get_bus_effect(_buses[bus], index)

## Seamless loop of coloured noise: the tail is crossfaded into the head.
func _noise(color: String) -> AudioStreamWAV:
	var count := int(RATE * LOOP_SECONDS)
	var fade := RATE / 5
	var raw := PackedFloat32Array()
	raw.resize(count + fade)
	var b := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])
	var brown := 0.0
	for i in range(count + fade):
		var white := rng.randf_range(-1.0, 1.0)
		match color:
			"pink":
				# Paul Kellet's pink filter.
				b[0] = 0.99886 * b[0] + white * 0.0555179
				b[1] = 0.99332 * b[1] + white * 0.0750759
				b[2] = 0.96900 * b[2] + white * 0.1538520
				b[3] = 0.86650 * b[3] + white * 0.3104856
				b[4] = 0.55000 * b[4] + white * 0.5329522
				b[5] = -0.7616 * b[5] - white * 0.0168980
				raw[i] = (b[0] + b[1] + b[2] + b[3] + b[4] + b[5] + b[6] + white * 0.5362) * 0.11
				b[6] = white * 0.115926
			"brown":
				brown = (brown + white * 0.02) * 0.998
				raw[i] = brown * 3.5
			_:
				raw[i] = white * 0.5
	for i in range(fade):
		var t := float(i) / float(fade)
		raw[i] = raw[i] * t + raw[count + i] * (1.0 - t)
	raw.resize(count)
	return _wav(raw, true)

## Canvas slatting: bursts of noise a few times a second.
func _flap() -> AudioStreamWAV:
	var count := int(RATE * 2.0)
	var raw := PackedFloat32Array()
	raw.resize(count)
	for i in range(count):
		var t := float(i) / RATE
		var beat := pow(maxf(sin(TAU * 3.5 * t) * 0.5 + 0.5 * sin(TAU * 1.5 * t + 1.0), 0.0), 4.0)
		raw[i] = rng.randf_range(-1.0, 1.0) * beat * 0.9
	return _wav(raw, true)

## A crack, then a long rolling rumble.
func _make_thunder() -> AudioStreamWAV:
	var count := int(RATE * 7.0)
	var raw := PackedFloat32Array()
	raw.resize(count)
	var brown := 0.0
	var swell := 0.0
	for i in range(count):
		var t := float(i) / RATE
		var white := rng.randf_range(-1.0, 1.0)
		brown = (brown + white * 0.03) * 0.997
		if i % 2205 == 0: swell = rng.randf_range(0.4, 1.0)
		var rumble := brown * 4.0 * (1.0 - exp(-t * 6.0)) * exp(-t * 0.45) * swell
		var crack := white * exp(-t * 18.0) * 0.8
		raw[i] = clampf(rumble + crack, -1.0, 1.0)
	return _wav(raw, false)

## Stick-slip pulses through the timbers' resonances.
func _make_creak(variant: int) -> AudioStreamWAV:
	var length := 0.5 + 0.2 * variant
	var count := int(RATE * length)
	var raw := PackedFloat32Array()
	raw.resize(count)
	var modes := [[380.0 + 60.0 * variant, 0.0], [690.0 - 40.0 * variant, 0.0]]
	var phase := 0.0
	var ring := 0.0
	for i in range(count):
		var t := float(i) / RATE
		# Pulse rate glides as the joint loads and unloads.
		var rate: float = lerpf(28.0, 60.0, sin(PI * t / length)) + rng.randf_range(-3.0, 3.0)
		phase += rate / RATE
		if phase >= 1.0:
			phase -= 1.0
			ring = 1.0
		ring *= exp(-1.0 / (RATE * 0.006))
		var value := 0.0
		for mode in modes: value += sin(TAU * mode[0] * t) * ring
		raw[i] = value * 0.35 * sin(PI * t / length)
	return _wav(raw, false)

## A heel on deck planking: a low boom and a knock.
func _make_step(variant: int) -> AudioStreamWAV:
	var count := int(RATE * 0.16)
	var raw := PackedFloat32Array()
	raw.resize(count)
	var boom := 95.0 + 12.0 * variant
	for i in range(count):
		var t := float(i) / RATE
		raw[i] = (sin(TAU * boom * t) * exp(-t * 28.0) * 0.7 + sin(TAU * 2.6 * boom * t) * exp(-t * 60.0) * 0.3 + rng.randf_range(-1.0, 1.0) * exp(-t * 180.0) * 0.4)
	return _wav(raw, false)

static func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = samples.size()
	return wav

func _loop(name: String, stream: AudioStreamWAV, bus: String) -> void:
	var sound := AudioStreamPlayer.new()
	sound.stream = stream
	sound.bus = bus
	sound.volume_db = -80.0
	add_child(sound)
	sound.play(rng.randf() * LOOP_SECONDS * 0.9)
	_players[name] = sound

func _one_shot(stream: AudioStreamWAV, bus: String, volume_db: float, pitch := 1.0) -> void:
	var sound := AudioStreamPlayer.new()
	sound.stream = stream
	sound.bus = bus
	sound.volume_db = volume_db
	sound.pitch_scale = pitch
	add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()

## Linear loudness 0..1+ to decibels, silent at 0.
static func _db(loudness: float) -> float:
	return linear_to_db(maxf(loudness, 0.0001))

func _level(name: String, loudness: float, smoothing: float, delta: float) -> void:
	var sound: AudioStreamPlayer = _players[name]
	var now := db_to_linear(sound.volume_db)
	sound.volume_db = _db(lerpf(now, loudness, 1.0 - exp(-delta / smoothing)))

func _process(delta: float) -> void:
	if not enabled or weather.current.is_empty(): return
	_clock += delta
	var w: Dictionary = weather.current
	var apparent: Vector2 = motion.wind() - motion.forward() * float(motion.speed)
	var gale := apparent.length()
	var camera := get_viewport().get_camera_3d()
	var covered: bool = camera != null and indoors.is_valid() and indoors.call(camera.global_position)
	# Wind: louder and brighter with the apparent wind; the rig whistles in a blow.
	_level("wind", clampf(gale / 22.0, 0.0, 1.3) * 0.55, 0.3, delta)
	(_effect("Wind") as AudioEffectLowPassFilter).cutoff_hz = 250.0 + gale * 55.0
	_level("whistle", smoothstep(11.0, 24.0, gale) * 0.12 * float(weather.gust), 0.5, delta)
	(_effect("Whistle") as AudioEffectBandPassFilter).cutoff_hz = 1300.0 + gale * 40.0 + 200.0 * sin(_clock * 0.7)
	# The sea: rumble with its height, rush along the hull with speed and pitching.
	var sea: float = weather.sea_height()
	_level("sea", clampf(0.15 + sea / 6.0, 0.0, 1.0) * 0.6, 0.5, delta)
	var pitching: float = absf(float(motion.velocity.z)) * 4.0 + absf(float(motion.velocity.y)) * 2.0
	_level("rush", clampf(float(motion.speed) / 6.0 + pitching, 0.0, 1.2) * 0.3, 0.25, delta)
	_level("rain", float(w.rain) * 0.5, 0.8, delta)
	var luff: float = sails.luff if sails else 0.0
	_level("flap", luff * clampf(gale / 12.0, 0.0, 1.5) * 0.5 * float(motion.canvas), 0.3, delta)
	# Inside the great cabin the weather is muffled through the bulkheads.
	(_effect("Outside") as AudioEffectLowPassFilter).cutoff_hz = lerpf((_effect("Outside") as AudioEffectLowPassFilter).cutoff_hz, 700.0 if covered else 20000.0, 1.0 - exp(-delta / 0.2))
	_creak(delta)
	for i in range(_pending_thunder.size() - 1, -1, -1):
		var clap: Dictionary = _pending_thunder[i]
		clap.wait -= delta
		if clap.wait <= 0.0:
			(_effect("Thunder") as AudioEffectLowPassFilter).cutoff_hz = clampf(12000000.0 / (clap.distance * clap.distance) + 150.0, 150.0, 4000.0)
			_one_shot(_thunder, "Thunder", _db(clampf(2500.0 / clap.distance, 0.15, 1.0) * clap.power), rng.randf_range(0.85, 1.1))
			_pending_thunder.remove_at(i)

## Timbers work as she rolls and pitches: more often, louder, in a seaway.
func _creak(delta: float) -> void:
	var working: float = absf(float(motion.velocity.y)) * 6.0 + absf(float(motion.velocity.z)) * 8.0
	_creak_wait -= delta * (0.3 + working)
	if _creak_wait > 0.0: return
	_creak_wait = rng.randf_range(2.0, 5.0)
	_one_shot(_creaks[rng.randi_range(0, _creaks.size() - 1)], "Ship", _db(clampf(0.1 + working * 0.3, 0.1, 0.7)), rng.randf_range(0.8, 1.25))

func _footstep() -> void:
	if not enabled: return
	_one_shot(_steps[rng.randi_range(0, _steps.size() - 1)], "Ship", _db(0.45), rng.randf_range(0.9, 1.1))

func _strike(_direction: Vector3, distance: float, power: float) -> void:
	_pending_thunder.append({"wait": distance / SOUND_SPEED, "distance": distance, "power": power})
