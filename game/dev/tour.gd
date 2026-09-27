extends Node3D
## Each shot freezes the shared clock and integrates the hull to that exact time.
const SHOTS := [
 {"name":"24_storm_poop_deck","eye":Vector3(-11.5,10.35,0.4),"target":Vector3(4,6,-3),"fov":72.0,"ship":true,"weather":"Storm","sail":1,"lightning":Vector3(0.9,0,-0.4)},
 {"name":"25_storm_exterior","eye":Vector3(55,7,45),"target":Vector3(0,9,0),"fov":42.0,"ship":true,"weather":"Storm","sail":1,"lightning":Vector3(-0.8,0,-0.6)},
 {"name":"26_gale_sails","eye":Vector3(-1.2,4.49,2.0),"target":Vector3(7,19,-1),"fov":78.0,"ship":true,"weather":"Gale","sail":3},
 {"name":"27_rogue_wave","eye":Vector3(-11.5,10.35,0.4),"target":Vector3(0,0,0),"fov":70.0,"ship":true,"weather":"Gale","sail":2,"rogue":7.0},
 {"name":"28_weather_menu","eye":Vector3(-11.5,10.35,0.4),"target":Vector3(4,5,0),"fov":62.0,"ship":true,"weather":"Fresh","sail":3,"menu":true},
 {"name":"29_calm_exterior","eye":Vector3(70,4,90),"target":Vector3(0,10,0),"fov":34.0,"weather":"Calm","sail":3},
 {"name":"30_storm_helm","eye":Vector3(-11.0,10.2,0.0),"target":Vector3(10,6.5,0),"fov":70.0,"ship":true,"weather":"Storm","sail":2,"helm":true},
 {"name":"23_at_the_helm","eye":Vector3(-11.0,10.2,0.0),"target":Vector3(10,6.5,0),"fov":70.0,"ship":true},
 {"name":"20_sea_from_fighting_top","eye":Vector3(0.12,16.83,0.1),"target":Vector3(-6,-2,26),"fov":62.0,"ship":true},
 {"name":"21_bow_waterline","eye":Vector3(24,2.2,9),"target":Vector3(8,0.2,0),"fov":48.0,"ship":true},
 {"name":"22_stern_wake","eye":Vector3(-34,13,16),"target":Vector3(-12,0,0),"fov":55.0,"ship":true},
 {"name":"15_shroud_climb","eye":Vector3(-1.8442,11.615,1.8991),"target":Vector3(-1.1,16,0.8),"fov":70.0,"ship":true},
 {"name":"16_fighting_top_view","eye":Vector3(0.12,16.83,0.1),"target":Vector3(11,8,0),"fov":70.0,"ship":true},
 {"name":"17_deck_dressing","eye":Vector3(0.1,4.45,1.8),"target":Vector3(6,3.2,1.5),"fov":72.0,"ship":true},
 {"name":"18_chest_open","eye":Vector3(-11.08,7.75,-0.46),"target":Vector3(-11.72,6.98,-0.25),"fov":70.0,"ship":true},
 {"name":"19_compass_held","eye":Vector3(3,4.49,1.5),"target":Vector3(12,4.0,0),"fov":62.0,"ship":true},
	{"name": "14_cabin_doorway", "eye": Vector3(-8.0,7.95,0.885), "target": Vector3(-10.6,7.6,0.1), "fov": 68.0, "ship": true},
	{"name": "08_cabin_interior", "eye": Vector3(-9.9,8.03,0.65), "target": Vector3(-12.1,7.6,0.1), "fov": 70.0, "ship": true},
	{"name": "09_cabin_table", "eye": Vector3(-9.85,7.8,0.55), "target": Vector3(-10.65,7.0,0.1), "fov": 62.0, "ship": true},
	{"name": "10_poop_deck", "eye": Vector3(-11.5,10.35,0.4), "target": Vector3(4,5,0), "fov": 62.0, "ship": true},
	{"name": "11_forecastle", "eye": Vector3(9,6.0,1.5), "target": Vector3(-8,6,0), "fov": 62.0, "ship": true},
	{"name": "12_quarterdeck_stairs", "eye": Vector3(-3.0,6.15,1.2), "target": Vector3(-6.5,6.3,0), "fov": 62.0, "ship": true},
	{"name": "13_ocean_debug_rings", "eye": Vector3(70, 4, 90), "target": Vector3(0, 10, 0), "fov": 34.0},
	{"name": "01_ship_exterior_sea_level", "eye": Vector3(-90, 3, -12), "target": Vector3(2, 12, 0), "fov": 24.0},
	{"name": "02_ship_exterior_wide", "eye": Vector3(70, 4, 90), "target": Vector3(0, 10, 0), "fov": 34.0},
	{"name": "03_main_deck_looking_forward", "eye": Vector3(0, 4.49, 2.5), "target": Vector3(13, 4.4, 0), "fov": 62.0},
	{"name": "04_helm", "eye": Vector3(-8, 9, -0.9), "target": Vector3(8, 8, 0), "fov": 62.0},
	{"name": "05_into_the_sun", "eye": Vector3(3, 4.49, 1.5), "target": Vector3(15, 10, 10), "fov": 62.0},
	{"name": "06_ocean_close", "eye": Vector3(20, 1.3, -18), "target": Vector3(100, 1.0, 70), "fov": 48.0},
	{"name": "07_ship_rolling", "eye": Vector3(38, 2, -40), "target": Vector3(1, 8, 0), "fov": 36.0},
]

func _ready() -> void:
	seed(1729)
	$World/Player.input_enabled = false
	$World/Player.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var name := "01_ship_exterior_sea_level"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			name = arg.get_slice("=", 1)
	var data: Dictionary = {}
	for candidate in SHOTS:
		if candidate.name == name:
			data = candidate
	if data.is_empty():
		push_error("Invalid tour shot: " + name)
		get_tree().quit(2)
		return
	var shot_time := 12.0
	if name == "07_ship_rolling":
		var motion = preload("res://ocean/buoyancy.gd").new()
		var largest := 0.0
		var hz := float(Engine.physics_ticks_per_second)
		for tick in range(int(30.0*hz)):
			var t := float(tick+1)/hz
			motion.step(t,1.0/hz,$World.ocean.wave_count)
			if absf(motion.roll)>largest:
				largest=absf(motion.roll)
				shot_time=t
	if data.has("weather"):
		# The sea and sky of that weather, fully developed.
		$World.weather.apply_preset(data.weather)
		$World.weather.target.gustiness = 0.0
		$World.weather.settle_now()
		$World.buoyancy.start_sail = data.get("sail", 3)
	$World.freeze_at(shot_time)
	for door in $World.doors: door.set_open(name.begins_with("08_") or name.begins_with("09_") or name.begins_with("14_") or name.begins_with("18_"),true)
	await $World.cabin_prewarm.warm()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var eye: Vector3 = data.eye
	var target: Vector3 = data.target
	if data.get("ship",false) or name in ["03_main_deck_looking_forward", "04_helm", "05_into_the_sun"]:
		eye = $World.ship_body.to_global(eye)
		target = $World.ship_body.to_global(target)
	if name == "04_helm":
		var ray := PhysicsRayQueryParameters3D.create(Vector3(eye.x, 12, eye.z), Vector3(eye.x, 3, eye.z), 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty():
			push_error("Quarterdeck eye-height ray missed")
			get_tree().quit(1)
			return
		eye.y = hit.position.y + 1.65
		target.y = eye.y
		print("QUARTERDECK: surface=", hit.position, " eye=", eye)
	if name == "06_ocean_close":
		var sun: Vector3 = $World.sun_direction()
		target = eye + Vector3(sun.x, -0.02, sun.z).normalized()*100.0
	if name == "05_into_the_sun":
		target = eye + $World.sun_direction() * 100.0
	var requested: Vector2i = get_node("/root/Quality").requested_size
	if requested != Vector2i.ZERO and Vector2i(get_viewport().get_visible_rect().size) != requested:
		push_error("Tour viewport does not match requested dimensions")
		get_tree().quit(1)
		return
	$Camera3D.position = eye
	$Camera3D.look_at(target)
	$Camera3D.fov = data.fov
	$Camera3D.make_current()
	$World.interactables.opened=name=="18_chest_open"
	$World.interactables.lid.rotation.x=deg_to_rad(-105) if name=="18_chest_open" else 0.0
	$World.interactables.raised=name=="19_compass_held"
	$World.interactables._process(1.0)
	# Photos without the start-up key hints.
	$World.hud._hint_left = 0.0
	if name == "23_at_the_helm" or data.get("helm", false):
		$World.helm.panel.visible = true
		$World.helm.readout.text = $World.helm.describe() + ("\n" + $World.helm.conditions() if data.get("helm", false) else "")
	if data.has("rogue"):
		# A rogue wave focusing on the ship a few seconds after the shot, seen
		# from the poop deck looking where it comes from.
		var motion = $World.buoyancy
		var lead: float = data.rogue
		var focus: Vector2 = -(motion.drift + motion.water_velocity() * lead)
		var sea = $World.weather.SEA
		sea.spawn_rogue(0.0, shot_time + lead, focus, 2.0 * sea.live_height(shot_time, $World.ocean.wave_count), $World.ocean.wave_count)
		var from: Vector2 = -sea.rogue().direction
		$Camera3D.look_at(eye + Vector3(from.x, -0.12, from.y) * 100.0)
		print("ROGUE: crest ", sea.rogue().crest, " m from ", from, " focus in ", lead, " s")
	if data.has("lightning"):
		$World.atmosphere._strike((data.lightning as Vector3).normalized(), 2200.0, 1.0)
	if data.get("menu", false):
		$World.weather_menu.toggle()
	print("TOUR: ", data.name, " seed=1729 sim_time=", get_node("/root/SimClock").time, "; viewport=", get_viewport().get_visible_rect().size)
