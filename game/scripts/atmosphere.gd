extends Node3D
## Renders the weather: a cloud deck drifting with the wind (sky shader),
## sunlight and shadows dimming under overcast, fog closing in with rain,
## rain blown by the apparent wind, and lightning bolts with a flash that
## lights the cloud base. Reads weather.gd; owns no weather state itself.
var weather: Node
var motion: RefCounted
var environment: Environment
var sun: DirectionalLight3D
var sky_material: ShaderMaterial
var ocean: Node
## Callable(eye: Vector3) -> bool: true under cover (no rain inside the cabin).
var indoors: Callable
## The cabin owns exposure and ambient (it darkens them indoors); the weather
## sets its outdoor baselines instead of fighting it for the environment.
var cabin: Node3D
var rain: GPUParticles3D
var rain_material: ParticleProcessMaterial
const RAIN_MAX := 8000
var flash_light: DirectionalLight3D
var cloud_offset := Vector2.ZERO
var _last_eye := Vector3.ZERO
var flash := 0.0
var _base := {}
var _bolts: Array[Dictionary] = []
var _bolt_material: StandardMaterial3D
var rng := RandomNumberGenerator.new()

func setup(live_weather: Node, ship_motion: RefCounted, env: Environment, light: DirectionalLight3D, sea: Node, cover: Callable, tier: String) -> void:
	weather = live_weather
	motion = ship_motion
	environment = env
	sun = light
	ocean = sea
	indoors = cover
	sky_material = environment.sky.sky_material as ShaderMaterial
	# The cloud deck moves, so reflections and ambient update a little each frame.
	environment.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	_base = {"sun": sun.light_energy, "ambient": environment.ambient_light_energy, "exposure": environment.tonemap_exposure, "fog_begin": environment.fog_depth_begin, "fog_end": environment.fog_depth_end, "fog_curve": environment.fog_depth_curve, "fog_color": environment.fog_light_color, "fog_scatter": environment.fog_sun_scatter, "shadow_distance": sun.directional_shadow_max_distance}
	rng.seed = 4242
	_build_rain(RAIN_MAX if tier == "high" else RAIN_MAX / 2)
	flash_light = DirectionalLight3D.new()
	flash_light.name = "LightningFlash"
	flash_light.light_color = Color(0.78, 0.84, 1.0)
	flash_light.light_energy = 0.0
	flash_light.shadow_enabled = false
	add_child(flash_light)
	_bolt_material = StandardMaterial3D.new()
	_bolt_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bolt_material.albedo_color = Color(0.85, 0.9, 1.0)
	_bolt_material.emission_enabled = true
	_bolt_material.emission = Color(0.8, 0.86, 1.0)
	_bolt_material.emission_energy_multiplier = 8.0
	_bolt_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bolt_material.disable_fog = true
	weather.lightning_strike.connect(_strike)

## Rain: drops as thin streaks, each aligned with its velocity and turned to
## face the eye (the blur of a drop over ~1/60 s), spawned upwind of the eye
## so that wind-driven rain still streams past it.
func _build_rain(amount: int) -> void:
	rain = GPUParticles3D.new()
	rain.name = "Rain"
	rain.amount = amount
	rain.lifetime = 1.4
	rain.preprocess = 1.4
	rain.local_coords = false
	rain.visibility_aabb = AABB(Vector3(-60, -40, -60), Vector3(120, 80, 120))
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rain_material = ParticleProcessMaterial.new()
	rain_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	rain_material.emission_box_extents = Vector3(14, 3, 14)
	rain_material.direction = Vector3(0, -1, 0)
	rain_material.spread = 1.5
	rain_material.initial_velocity_min = 9.0
	rain_material.initial_velocity_max = 10.0
	rain_material.gravity = Vector3.ZERO
	rain_material.particle_flag_align_y = true
	rain.process_material = rain_material
	# 2 mm drops blurred over ~1/40 s: thin streaks along their velocity.
	var streak := QuadMesh.new()
	streak.size = Vector2(0.007, 0.7)
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/rain_streak.gdshader")
	streak.material = material
	rain.draw_pass_1 = streak
	rain.amount_ratio = 0.0
	rain.emitting = false
	add_child(rain)

func _process(delta: float) -> void:
	if weather == null or weather.current.is_empty(): return
	var w: Dictionary = weather.current
	var clouds: float = w.clouds
	var overcast := smoothstep(0.35, 1.0, clouds)
	var storm := clampf((clouds - 0.55) / 0.45, 0.0, 1.0) * (0.45 + 0.55 * float(w.rain))
	# Cloud deck ~2 km up drifts with the wind at altitude (x1.5), relative to the ship.
	var wind: Vector2 = motion.wind() * 1.5 + motion.water_velocity()
	if not get_node("/root/SimClock").frozen:
		cloud_offset += wind * delta / 1250.0
	var frozen: bool = get_node("/root/SimClock").frozen
	# The flash is gone in a sixth of a second (a frozen capture keeps the bolt).
	flash = move_toward(flash, 0.0, delta * 6.0)
	sky_material.set_shader_parameter("cloud_cover", clouds)
	sky_material.set_shader_parameter("cloud_offset", cloud_offset)
	sky_material.set_shader_parameter("storm", storm)
	sky_material.set_shader_parameter("flash", flash)
	# Under a full overcast the sun is a faint glow: no glitter, soft shadows.
	var daylight := 1.0 - 0.985 * overcast
	sun.light_energy = float(_base.sun) * daylight
	sun.shadow_opacity = lerpf(1.0, 0.2, overcast)
	var ambient := float(_base.ambient) * lerpf(1.0, 0.55, overcast) * lerpf(1.0, 0.7, storm) + flash * 1.5
	# The eye adapts a little to the gloom, not all the way.
	var exposure := float(_base.exposure) * lerpf(1.0, 1.25, overcast)
	if cabin:
		cabin.base_ambient = ambient
		cabin.base_exposure = exposure
	else:
		environment.ambient_light_energy = ambient
		environment.tonemap_exposure = exposure
	# Rain and mist bring the horizon in.
	var murk := clampf(maxf(float(w.fog), float(w.rain) * 0.7), 0.0, 1.0)
	# Heavy rain: a few hundred metres' visibility, thickening close in.
	environment.fog_depth_begin = lerpf(float(_base.fog_begin), 15.0, murk)
	environment.fog_depth_end = lerpf(float(_base.fog_end), 700.0, pow(murk, 0.6))
	environment.fog_depth_curve = lerpf(float(_base.fog_curve), 0.9, murk)
	# The fog takes the overcast deck's colour at the horizon (aligned_sky's
	# overcast_color), so sea and sky dissolve into each other in the rain.
	# (The sky works in linear light; Environment colours are sRGB.)
	var deck := (Color(0.30, 0.32, 0.35) * lerpf(0.85, 0.28, storm) * 0.9).linear_to_srgb()
	environment.fog_light_color = (_base.fog_color as Color).lerp(deck, overcast)
	environment.fog_sun_scatter = lerpf(float(_base.fog_scatter), 0.0, overcast)
	environment.fog_sky_affect = murk * 0.35
	flash_light.light_energy = flash * 3.0
	if ocean and ocean.material:
		ocean.material.set_shader_parameter("sun_energy", float(_base.sun) * daylight)
		ocean.rain_roughness = float(w.rain) * 0.012
	_rain(float(w.rain))
	_update_bolts(0.0 if frozen else delta)

func _rain(amount: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	var eye := camera.global_position
	var covered: bool = indoors.is_valid() and indoors.call(eye)
	var ratio := 0.0 if covered else amount
	var jumped := eye.distance_to(_last_eye) > 15.0
	_last_eye = eye
	if ratio > 0.01 and (not rain.emitting or jumped):
		# Starting, stepping out of the cabin, or a cut to another camera:
		# fill the air around the eye at once.
		rain.emitting = true
		rain.restart()
	elif ratio <= 0.01:
		rain.emitting = false
	rain.amount_ratio = ratio
	# Drops fall at ~9 m/s and ride the apparent wind (true wind + the ship's
	# own way through the water): in a gale they drive almost flat. They are
	# released upwind by as far as they travel in the time they take to fall
	# to eye level, so the stream passes through the viewer.
	var apparent: Vector2 = motion.wind() + motion.water_velocity()
	var velocity := Vector3(apparent.x, -9.0, apparent.y)
	var height := 8.0
	rain.global_position = eye + Vector3.UP * height - Vector3(apparent.x, 0.0, apparent.y) * (height / 9.0)
	rain_material.direction = velocity.normalized()
	rain_material.initial_velocity_min = velocity.length() * 0.95
	rain_material.initial_velocity_max = velocity.length() * 1.05

func _strike(direction: Vector3, distance: float, power: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var origin := camera.global_position if camera else Vector3.ZERO
	var ground := origin + direction * distance
	ground.y = 0.0
	var mesh := _bolt_mesh(ground, 1500.0, distance)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _bolt_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	_bolts.append({"node": node, "age": 0.0, "power": power})
	flash_light.rotation = Vector3.ZERO
	flash_light.look_at_from_position(Vector3.ZERO, -direction + Vector3.DOWN * 0.6, Vector3.UP)
	flash = maxf(flash, power * clampf(3000.0 / distance, 0.4, 1.0))

## Jagged ribbon from cloud base to sea with a couple of forks; width grows
## with distance so a distant bolt stays a few pixels wide.
func _bolt_mesh(ground: Vector3, height: float, distance: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# At least ~2 px wide at 1080p whatever the distance.
	var width := clampf(distance * 0.0024, 2.0, 16.0)
	var points := _jagged(ground + Vector3(rng.randf_range(-200, 200), height, rng.randf_range(-200, 200)), ground, 22, 60.0)
	_ribbon(st, points, width)
	for fork in range(2):
		var start: Vector3 = points[rng.randi_range(4, 12)]
		var end := start.lerp(ground, 0.5) + Vector3(rng.randf_range(-250, 250), 0, rng.randf_range(-250, 250))
		_ribbon(st, _jagged(start, end, 10, 40.0), width * 0.5)
	return st.commit()

func _jagged(a: Vector3, b: Vector3, segments: int, roughness: float) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var p := a.lerp(b, t)
		if i > 0 and i < segments:
			p += Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 0.3), rng.randf_range(-1, 1)) * roughness
		result.append(p)
	return result

func _ribbon(st: SurfaceTool, points: Array[Vector3], width: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var eye := camera.global_position if camera else Vector3.ZERO
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var side := (b - a).cross(eye - a).normalized() * width * 0.5
		for v in [a - side, a + side, b + side, a - side, b + side, b - side]:
			st.add_vertex(v)

func _update_bolts(delta: float) -> void:
	for i in range(_bolts.size() - 1, -1, -1):
		var bolt: Dictionary = _bolts[i]
		bolt.age += delta
		var node: MeshInstance3D = bolt.node
		# Two or three return strokes, then gone.
		var age: float = bolt.age
		node.visible = age < 0.08 or (age > 0.14 and age < 0.2) or (age > 0.28 and age < 0.34 and bolt.power > 0.7)
		if age > 0.4:
			node.queue_free()
			_bolts.remove_at(i)
