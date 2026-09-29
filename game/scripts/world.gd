extends Node3D

const SHIP_SCENE = preload("res://scenes/ship.tscn")
# Estimated model-space waterline: rounded dark bilge below, lowest gunports above.
const WATERLINE := 0.6
const SUN_UV := Vector2(0.600361134, 0.394015681)
const SKY_YAW := deg_to_rad(89.8)
var ship_body: AnimatableBody3D
var next_ship_pose := Transform3D(Basis.IDENTITY, Vector3(0,-WATERLINE,0))
var ocean: MeshInstance3D
var hull_source_mesh: Mesh
var hull_partition: Dictionary
var doors: Array[Node3D] = []
var cabin: Node3D
var cabin_prewarm: Node3D
var deck_props: Node3D
var interactables: Node3D
var rigging_climb: Node3D
var exterior_shadow_distance := 50.0
var decks: Node3D
var buoyancy = preload("res://ocean/buoyancy.gd").new()
var helm: Node3D
var sails_mesh: MeshInstance3D
## Wind-driven sails (exploration/sails.gd).
var sail_rig: RefCounted
## Live weather driving the sea, the wind on the rig and the sky.
var weather: Node
var atmosphere: Node3D
var hud: CanvasLayer
var weather_menu: CanvasLayer
var sound: Node

func _ready() -> void:
	seed(1729)
	process_physics_priority = -50
	# Sailing: the hull stays at the origin and the sea drifts past it.
	var ship_settings: Dictionary = get_node("/root/Quality").ocean_settings()
	# Weather first: it sets the sea state the ship starts sailing in.
	weather = preload("res://scripts/weather.gd").new()
	weather.name = "Weather"
	add_child(weather)
	weather.setup(buoyancy, ship_settings["ocean-waves"], ship_settings["weather"], ship_settings["weather-dynamic"] == "on")
	weather.rogue_passed.connect(func(how: String, side: float) -> void: buoyancy.strike(how, side))
	buoyancy.start_sail = ship_settings["sails"]
	var knots: float = ship_settings["ship-speed"]
	buoyancy.start_speed = knots*0.514444 if knots >= 0.0 else -1.0
	buoyancy.reset_navigation()
	_build_ship()
	decks = preload("res://exploration/decks.gd").new()
	decks.name = "Decks"
	ship_body.add_child(decks)
	decks.build(ship_body)
	$Player.climb_query = decks.climb_at
	_build_sea()
	_build_light()
	atmosphere = preload("res://scripts/atmosphere.gd").new()
	atmosphere.name = "WeatherEffects"
	add_child(atmosphere)
	atmosphere.setup(weather, buoyancy, $Atmosphere.environment, $Sun, ocean, _indoors, get_node("/root/Quality").tier)
	rigging_climb=preload("res://exploration/rigging_climb.gd").new()
	rigging_climb.name="RiggingClimb"
	rigging_climb.build(ship_body,ship_body.get_node("Model"),get_node("/root/Quality").effective)
	ship_body.add_child(rigging_climb)
	rigging_climb.configure_gates(decks)
	$Player.rigging_climb=rigging_climb
	cabin = preload("res://exploration/cabin.gd").new()
	cabin.name = "Cabin"
	cabin.build(ship_body,$Atmosphere.environment,doors,$Player,hull_partition.knees)
	ship_body.add_child(cabin)
	atmosphere.cabin = cabin
	deck_props=preload("res://exploration/deck_props.gd").new()
	deck_props.build(ship_body,get_node("/root/Quality").effective)
	ship_body.add_child(deck_props)
	interactables=preload("res://exploration/interactables.gd").new()
	interactables.build(cabin,deck_props,$Player)
	ship_body.add_child(interactables)
	helm=preload("res://exploration/helm.gd").new()
	helm.name="Helm"
	ship_body.add_child(helm)
	helm.build(ship_body,$Player,buoyancy,interactables,deck_props.timber)
	helm.weather = weather
	hud = preload("res://scripts/hud.gd").new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(weather, buoyancy, $Player)
	weather_menu = preload("res://scripts/weather_menu.gd").new()
	weather_menu.name = "WeatherMenu"
	add_child(weather_menu)
	weather_menu.setup(weather, hud)
	sound = preload("res://scripts/sound.gd").new()
	sound.name = "Sound"
	add_child(sound)
	sound.setup(weather, buoyancy, $Player, sail_rig, _indoors)
	cabin_prewarm=preload("res://exploration/cabin_prewarm.gd").new()
	cabin_prewarm.build(cabin,[deck_props,interactables,rigging_climb,ship_body.get_node("Model"),doors[0],doors[1]])
	add_child(cabin_prewarm)
	call_deferred("_warm_main")
	$Player.global_position = ship_body.get_node("SpawnPoint").global_position
	$Player.spawn_point = ship_body.get_node("SpawnPoint")
	$Player.sea_height = ocean.surface_at
	$Player.splashed.connect(func(): ocean.disturb($Player.global_position, 0.7, 0.6))
	$Player.inside_hull = ocean.contains_point
	$Player.deck = ship_body
	$Player.deck_pose = func(): return global_transform * next_ship_pose
	$Player.motion = buoyancy

## Under cover from the weather: inside the great cabin.
func _indoors(eye: Vector3) -> bool:
	return cabin != null and cabin.contains(ship_body.to_local(eye) - Vector3.UP * 1.4)

func _build_ship() -> void:
	ship_body = SHIP_SCENE.instantiate()
	ship_body.name = "Ship"
	ship_body.position.y = -WATERLINE
	ship_body.collision_layer = 1
	ship_body.collision_mask = 2
	add_child(ship_body)
	var model := ship_body.get_node("Model")
	for mesh in model.find_children("*", "MeshInstance3D"):
		var original = mesh.get_active_material(0)
		if "sails" in mesh.name and original is StandardMaterial3D:
			sails_mesh = mesh
			# Opaque cloth (the supplied RGB JPEG has no alpha) that fills, luffs,
			# backs and furls with the apparent wind.
			sail_rig = preload("res://exploration/sails.gd").new()
			sail_rig.build(mesh, original)
		if "rigging" in mesh.name and original is StandardMaterial3D:
			mesh.visible = get_node("/root/Quality").overrides.get("rigging", "on") == "on"
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var rope := ShaderMaterial.new()
			rope.shader = preload("res://scripts/rope_legacy.gdshader") if get_node("/root/Quality").overrides.get("rigging-material","opaque")=="legacy" else preload("res://scripts/rope.gdshader")
			rope.set_shader_parameter("albedo_texture", original.albedo_texture)
			mesh.material_override = rope
		if "hull" in mesh.name:
			hull_source_mesh = mesh.get_meta("source_mesh",mesh.mesh)
			hull_partition = mesh.get_meta("m2_partition",{})
			assert(not hull_partition.is_empty(), "Reimport ship to generate the M2 hull partition")
			mesh.mesh = hull_partition.hull
			var wet := ShaderMaterial.new()
			wet.shader = Shader.new()
			var wet_source := FileAccess.get_file_as_string("res://ocean/wet_hull.gdshader")
			if get_node("/root/Quality").overrides.get("hull-cull", "back") == "disabled":
				wet_source = wet_source.replace("cull_back", "cull_disabled")
			wet.shader.code = wet_source
			wet.set_shader_parameter("albedo_texture", original.albedo_texture)
			wet.set_shader_parameter("albedo_factor", original.albedo_color)
			wet.set_shader_parameter("normal_texture", original.normal_texture)
			wet.set_shader_parameter("orm_texture", original.roughness_texture)
			mesh.material_override = wet
			var collision := CollisionShape3D.new()
			collision.name = "HullTrimesh"
			var solid_faces: PackedVector3Array = hull_partition.hull.get_faces()
			solid_faces.append_array(hull_partition.patch.get_faces())
			var collision_arrays := []
			collision_arrays.resize(Mesh.ARRAY_MAX)
			collision_arrays[Mesh.ARRAY_VERTEX] = solid_faces
			var collision_mesh := ArrayMesh.new()
			collision_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, collision_arrays)
			collision.shape = collision_mesh.create_trimesh_shape()
			ship_body.add_child(collision)
			collision.global_transform = mesh.global_transform
			# Audited nearest back-facing triangles only; disjoint index buffers.
			var thin := MeshInstance3D.new()
			thin.name = "ThinHullPatch"
			thin.mesh = hull_partition.patch
			var two_sided: ShaderMaterial = wet.duplicate()
			two_sided.shader = Shader.new()
			two_sided.shader.code = wet_source.replace("cull_back", "cull_disabled")
			thin.material_override = two_sided
			mesh.add_child(thin)
			for i in range(2):
				var door := preload("res://exploration/door.gd").new()
				door.name = "CabinDoor"+str(i)
				ship_body.add_child(door)
				var door_material: ShaderMaterial = wet.duplicate()
				door_material.shader = Shader.new()
				door_material.shader.code = wet_source.replace("cull_back", "cull_disabled")
				door.build(hull_partition.doors[i], door_material, Vector3(-8.81,6.42,1.204 if i==0 else -1.010), 1.0 if i==0 else -1.0)
				doors.append(door)

func _build_sea() -> void:
	ocean = preload("res://ocean/ocean.gd").new()
	ocean.name = "Ocean"
	ocean.ship = ship_body
	ocean.motion = buoyancy
	add_child(ocean)
	for mesh in ship_body.get_node("Model").find_children("*", "MeshInstance3D"):
		if "hull" in mesh.name:
			ocean.build_hull_mask(mesh, hull_source_mesh)

func _physics_process(delta: float) -> void:
	if not get_node("/root/SimClock").frozen:
		next_ship_pose = buoyancy.step(get_node("/root/SimClock").time, delta, ocean.wave_count)
		ship_body.transform = next_ship_pose

func freeze_at(time: float) -> void:
	get_node("/root/SimClock").freeze(time)
	# Capture placement is a teleport, not platform movement.
	ship_body.sync_to_physics = false
	next_ship_pose = buoyancy.pose_at(time, ocean.wave_count, ocean.wake_replay(time))
	ship_body.transform = next_ship_pose
	ship_body.reset_physics_interpolation()

static func sun_direction() -> Vector3:
	var azimuth := SUN_UV.x * TAU
	var polar := SUN_UV.y * PI
	return Vector3(sin(azimuth) * sin(polar), cos(polar), -cos(azimuth) * sin(polar)).rotated(Vector3.UP, SKY_YAW)

func _build_light() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/aligned_sky.gdshader")
	material.set_shader_parameter("panorama", preload("res://assets/polyhaven/hdris/qwantani_late_afternoon_puresky_4k.hdr"))
	material.set_shader_parameter("yaw", SKY_YAW)
	material.set_shader_parameter("sun_direction", sun_direction().rotated(Vector3.UP,-SKY_YAW))
	material.set_shader_parameter("horizon_map", ocean.material.get_shader_parameter("sky_map"))
	sky.sky_material = material
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	environment.sky = sky
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_depth_begin = 250.0
	environment.fog_depth_end = 3000.0
	environment.fog_depth_curve = 1.5
	environment.fog_density = 1.0
	environment.fog_light_color = Color(0.45, 0.42, 0.38)
	environment.fog_sun_scatter = 0.3
	environment.fog_aerial_perspective = 0.0
	environment.fog_sky_affect = 0.0
	environment.glow_intensity = 0.18
	environment.glow_bloom = 0.0
	var world_environment := WorldEnvironment.new()
	world_environment.name = "Atmosphere"
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = LightingRig.SUN_COLOR
	sun.shadow_enabled = true
	add_child(sun)
	sun.look_at(-sun_direction(), Vector3.UP)
	get_node("/root/Quality").apply_to_world(environment, sun)
	exterior_shadow_distance=sun.directional_shadow_max_distance

func _warm_main() -> void:
	if get_tree().current_scene==self:
		var was_enabled: bool=$Player.input_enabled
		$Player.input_enabled=false
		await cabin_prewarm.warm()
		$Player.input_enabled=was_enabled

func _process(delta: float) -> void:
	if sail_rig: sail_rig.update(buoyancy, delta)
	# Rain and heavy spray wet the planking: footing goes sooner.
	$Player.wet = float(weather.current.rain) > 0.25 or weather.sea_height() > 4.5
	var camera:=get_viewport().get_camera_3d()
	if camera==null or cabin==null:return
	var settings: Dictionary=get_node("/root/Quality").effective
	# Keep the selected cascade mode, shadow resolution and on/off overrides.
	# Indoor views need nearby doorway shadows, not the complete 50/140 m map.
	# Spatial blending is deterministic and avoids a doorway toggle/pipeline change.
	var eye:=ship_body.to_local(camera.global_position)
	var amount:=0.0
	if settings["cabin-shell"]=="on" and cabin.contains(eye-Vector3.UP*1.4):
		amount=smoothstep(cabin.FRONT,cabin.FRONT-0.7,eye.x)
	$Sun.directional_shadow_max_distance=lerpf(exterior_shadow_distance,minf(18.0,exterior_shadow_distance),amount)
