extends SceneTree
var failures := 0

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	var watchdog_seconds := 120.0
	if OS.get_environment("CHECK_INJECT_RUNTIME_ERROR") == "1":
		watchdog_seconds = 1.0
	create_timer(watchdog_seconds).timeout.connect(func(): printerr("FAIL: watchdog"); quit(1))
	call_deferred("_run")

func _run() -> void:
	if OS.get_environment("CHECK_INJECT_RUNTIME_ERROR") == "1":
		await physics_frame
		var missing: Node
		missing.get_node("intentional_runtime_failure")
	var main_path: String = ProjectSettings.get_setting("application/run/main_scene")
	var packed = load(main_path)
	check(packed is PackedScene, "configured main scene loads")
	if not packed is PackedScene:
		quit(1)
		return
	var world = packed.instantiate()
	root.add_child(world)
	world.freeze_at(0.0)
	var player = world.get_node("Player")
	player.input_enabled = false
	await physics_frame
	await physics_frame
	var spawn: Vector3 = player.global_position
	var query := PhysicsRayQueryParameters3D.create(spawn, spawn + Vector3.DOWN * 3.0, 1)
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty(), "downward ray from player spawn hits within 3 m")
	if not hit.is_empty():
		check(hit.collider == world.ship_body, "spawn ray hits ship collision")
		check(hit.position.y < spawn.y and hit.normal.y > 0.8, "player feet spawn above walkable deck")
		print("Spawn: ", spawn, "; deck hit: ", hit.position, "; clearance: ", spawn.y - hit.position.y, " m")
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = player.get_node("Capsule").shape
	shape_query.transform = player.get_node("Capsule").global_transform
	shape_query.collision_mask = 1
	check(world.get_world_3d().direct_space_state.intersect_shape(shape_query).is_empty(), "spawn capsule is clear of hull")
	var sun = world.get_node("Sun")
	# Measure the actual loaded HDR pixels, independently of SUN_UV.
	var hdr := load("res://assets/polyhaven/hdris/qwantani_late_afternoon_puresky_4k.hdr") as Texture2D
	var image := hdr.get_image()
	var peak := 0.0
	var pixel := Vector2i.ZERO
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			var c := image.get_pixel(x, y)
			var energy := c.r + c.g + c.b
			if energy > peak:
				peak = energy
				pixel = Vector2i(x, y)
	var uv := (Vector2(pixel) + Vector2(0.5, 0.5)) / Vector2(image.get_size())
	var measured := Vector3(sin(uv.x * TAU) * sin(uv.y * PI), cos(uv.y * PI), -cos(uv.x * TAU) * sin(uv.y * PI)).rotated(Vector3.UP, world.SKY_YAW)
	check(sun.global_basis.z.angle_to(measured) < deg_to_rad(0.6), "sun matches HDRI pixel disk direction within 0.6 degrees")
	var unrotated: Vector3 = sun.global_basis.z.rotated(Vector3.UP, -world.SKY_YAW)
	var shader_uv := Vector2(fposmod(atan2(unrotated.x, -unrotated.z) / TAU, 1.0), acos(unrotated.y) / PI)
	check(shader_uv.distance_to(uv) < 0.003, "shader UV mapping reaches measured HDRI sun pixels")
	print("Measured HDRI disk UV: ", uv, "; peak RGB sum: ", peak)
	player.input_enabled = true
	for i in range(60):
		await physics_frame
	check(player.is_on_floor(), "player settles on deck under gravity")
	print("Settled feet: ", player.position)
	check(absf(player.position.y - hit.get("position", Vector3.ZERO).y) < 0.15, "player remains at deck height")
	player.test_input = true
	player.move_input = Vector2(0, -1)
	var before: Vector3 = player.global_position
	for i in range(60):
		await physics_frame
	check(player.global_position.x - before.x > 1.0 and player.global_position.x - before.x < 1.9, "60 physics frames of forward input move player about 1.6 m")
	check(player.is_on_floor(), "walking player remains on hull")
	check(absf(player.head.global_position.y - player.global_position.y - 1.65) < 0.04, "moving eye stays at human height")
	print("Walk displacement: ", player.global_position - before)
	if OS.get_environment("CHECK_DISABLE_SHIP_CARRY") != "1" and OS.get_environment("CHECK_RIDE_ONLY") != "1":
		_test_textures("res://assets/polyhaven/models")
		_test_waves()
		preload("res://tests/local_waterline.gd").run(world,check)
		preload("res://tests/ocean_grid.gd").run(check)
	await _test_riding(world, player)
	world.queue_free()
	await process_frame
	print("Tests: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)

const SEA = preload("res://ocean/default_sea.tres")
# Independent forward sum and finite-difference Newton inverse over the raw
# component table, deliberately not using SEA.displacement/_sample.
func reference_forward(q: Vector2, time: float, count: int) -> Vector3:
	var table: Dictionary = SEA.long_waves(count)
	var p := Vector3(q.x,0,q.y)
	for i in range(table.count):
		var k := Vector2(table.kx[i],table.kz[i])
		var angle: float = k.dot(q)+table.phase[i]-(table.omega[i]+k.dot(SEA.current))*time
		var direction := k.normalized()
		p.x += table.horizontal[i]*direction.x*cos(angle)
		p.z += table.horizontal[i]*direction.y*cos(angle)
		p.y += table.amplitude[i]*sin(angle)
	return p

func _test_waves() -> void:
	var table: Dictionary = SEA.long_waves(32)
	check(table.count==32,"sea state yields the requested 32 long-wave components")
	var dispersion := 0.0
	var long_variance := 0.0
	var shortest := INF
	for i in range(table.count):
		var k := Vector2(table.kx[i],table.kz[i]).length()
		dispersion = maxf(dispersion,absf(table.omega[i]*table.omega[i]-9.81*k))
		shortest = minf(shortest,TAU/k)
		long_variance += table.amplitude[i]*table.amplitude[i]/2.0
	check(dispersion<1e-6,"every long component obeys deep-water dispersion w^2 = g k")
	check(shortest>=SEA.split_wavelength*0.999,"no long component is shorter than the split wavelength (FFT band owns those)")
	var split_k: float = SEA.split_frequency()*SEA.split_frequency()/9.81
	var expected: float = SEA.height_variance(0.0001,split_k)
	print("Long band: Hs=",4.0*sqrt(long_variance)," m (spectrum ",4.0*sqrt(expected)," m); total sea Hs=",SEA.significant_height()," m")
	check(absf(long_variance/expected-1.0)<0.05,"long components carry the spectrum's long-band energy within 5%")
	var max_height_error := 0.0
	var max_normal_error := 0.0
	var max_inverse_error := 0.0
	var max_batch_error := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 82117
	for count in [24,32]:
		for i in range(64):
			var target := Vector2(rng.randf_range(-180,180),rng.randf_range(-180,180))
			var time := rng.randf_range(0,60)
			var q := target
			for iteration in range(8):
				var p := reference_forward(q,time,count)
				var dx := (reference_forward(q+Vector2(0.01,0),time,count)-reference_forward(q-Vector2(0.01,0),time,count))/0.02
				var dz := (reference_forward(q+Vector2(0,0.01),time,count)-reference_forward(q-Vector2(0,0.01),time,count))/0.02
				var error := Vector2(p.x,p.z)-target
				var determinant := dx.x*dz.z-dz.x*dx.z
				q -= Vector2(dz.z*error.x-dz.x*error.y,-dx.z*error.x+dx.x*error.y)/determinant
			var reference := reference_forward(q,time,count)
			var normal := (reference_forward(q+Vector2(0,0.01),time,count)-reference_forward(q-Vector2(0,0.01),time,count)).cross(reference_forward(q+Vector2(0.01,0),time,count)-reference_forward(q-Vector2(0.01,0),time,count)).normalized()
			var actual: Dictionary = SEA.surface(target.x,target.y,time,count)
			var batch: PackedFloat64Array = SEA.heights(PackedVector2Array([target]),time,count)
			max_height_error = maxf(max_height_error,absf(actual.position.y-reference.y))
			max_batch_error = maxf(max_batch_error,absf(batch[0]-reference.y))
			max_normal_error = maxf(max_normal_error,actual.normal.distance_to(normal))
			max_inverse_error = maxf(max_inverse_error,Vector2(actual.position.x,actual.position.z).distance_to(target))
	print("Wave reference: 128 samples; height error=",max_height_error," m, batched=",max_batch_error," m, inverse residual=",max_inverse_error," m, normal error=",max_normal_error)
	check(max_height_error<0.01 and max_batch_error<0.01 and max_inverse_error<0.01 and max_normal_error<0.002,"long-wave height, batched height, inverse and normal match independent Newton reference")

class RideDriver extends Node:
	var ship: AnimatableBody3D
	var world: Node3D
	var motion = preload("res://ocean/buoyancy.gd").new()
	var strong := false
	var count := 5
	var tick := 0
	func _physics_process(delta: float) -> void:
		tick += 1
		var t := float(tick)/float(Engine.physics_ticks_per_second)
		var pose: Transform3D = motion.step(t,delta,count)
		world.next_ship_pose = pose
		ship.transform=pose

func _test_riding(original_world: Node3D, original_player: CharacterBody3D) -> void:
	original_world.ship_body.collision_layer=0
	original_player.input_enabled=false
	for strong in [false,true]:
		# Fresh bodies prevent cached AnimatableBody velocity from the preceding
		# case's final pose contaminating this independent fixture.
		var world: Node3D=load("res://scenes/main.tscn").instantiate()
		root.add_child(world)
		var player: CharacterBody3D=world.get_node("Player")
		player.test_input=true
		player.move_input=Vector2.ZERO
		player.ship_space_carry=OS.get_environment("CHECK_DISABLE_SHIP_CARRY")!="1"
		# Start each case settled at the same local point.
		root.get_node("SimClock").frozen=true
		world.ship_body.sync_to_physics=false
		world.ship_body.transform=Transform3D(Basis.IDENTITY,Vector3(0,-0.6,0))
		player.global_position=world.ship_body.to_global(Vector3(4.5,3.1,1.5))
		player.velocity=Vector3.ZERO
		player.global_rotation=Vector3(0,-PI/2.0,0)
		player.up_direction=Vector3.UP
		player._carry_initialized=false
		for i in range(90): await physics_frame
		var start: Vector3=world.ship_body.to_local(player.global_position)
		var driver := RideDriver.new()
		driver.ship=world.ship_body
		driver.world=world
		driver.motion.wave_scale=1.5 if strong else 1.0
		driver.count=world.ocean.wave_count
		driver.strong=strong
		driver.process_physics_priority=-50
		world.ship_body.sync_to_physics=true
		root.add_child(driver)
		var max_vertical:=0.0
		var max_drift:=0.0
		var max_roll:=0.0
		var lost_floor:=0
		for i in range(1200):
			await physics_frame
			await process_frame
			var pose: Transform3D=world.ship_body.transform
			var local: Vector3=world.ship_body.to_local(player.global_position)
			max_roll=maxf(max_roll,absf(rad_to_deg(pose.basis.get_euler().x)))
			max_drift=maxf(max_drift,Vector2(local.x-start.x,local.z-start.z).length())
			var up: Vector3=world.ship_body.global_basis.y
			var ray:=PhysicsRayQueryParameters3D.create(player.global_position+up*0.25,player.global_position-up*0.5,1)
			var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(ray)
			if hit.is_empty(): lost_floor+=1
			else:
				var error: float=absf((player.global_position-hit.position).dot(up))
				max_vertical=maxf(max_vertical,error)
		driver.queue_free()
		await process_frame
		print("Ride ", "1.5x sea stress" if strong else "default sea", ": feet=",max_vertical," m, drift=",max_drift," m, roll=",max_roll," deg, missed rays=",lost_floor," carry=",player.ship_space_carry)
		check(max_vertical<0.01 and lost_floor==0,"moving deck feet remain within 1 cm")
		check(max_drift<0.10,"standing player drifts less than 10 cm in 20 seconds")
		world.queue_free()
		await process_frame

func _test_textures(directory: String) -> void:
	var dir := DirAccess.open(directory)
	if dir == null: return
	for file in dir.get_files():
		if not file.ends_with(".import"): continue
		var source := directory.path_join(file.trim_suffix(".import"))
		if not source.ends_with(".jpg") and not source.ends_with(".png"): continue
		var texture := load(source) as Texture2D
		var imported := texture.get_image()
		check(imported != null and imported.has_mipmaps() and imported.is_compressed(), "VRAM compression and mipmaps: " + source.get_file())
	for child in dir.get_directories():
		_test_textures(directory.path_join(child))
