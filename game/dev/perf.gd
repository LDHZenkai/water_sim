extends Node3D
const WARMUP := 3.0
const DURATION := 20.0
# Ship-local camera route: approach the original doors, pass through the open
# leaf into the cabin, return through it, and visit both raised deck systems.
const EYES := [Vector3(3,4.5,1.5),Vector3(8.5,5.95,1.5),Vector3(3,4.5,2.2),Vector3(-2,6.1,1.5),Vector3(-6.5,7.7,0.5),Vector3(-8.0,7.7,0.885),Vector3(-8.55,7.7,0.885),Vector3(-9.5,7.7,0.885),Vector3(-11,7.8,0.4),Vector3(-9.5,7.7,0.885),Vector3(-8.4,7.7,0.885),Vector3(-8.0,8.0,1.5),Vector3(-12,9.0,1.5),Vector3(-11.5,10.3,0.4),Vector3(-2.6,6.25,2.9),Vector3(-1.8,11,1.8),Vector3(-1,16.83,0.2),Vector3(3,4.5,1.5),Vector3(32,3,36),Vector3(49,17,66)]
const TARGETS := [Vector3(12,4.4,0),Vector3(-8,6,0),Vector3(0,26,0),Vector3(-7,6,0),Vector3(-9,7.4,0.8),Vector3(-10,7.6,0.885),Vector3(-10,7.6,0.885),Vector3(-12,7.6,0.1),Vector3(-10.65,7.1,0.1),Vector3(-8,7.7,0.885),Vector3(-7,7.8,0),Vector3(-12,9,1.5),Vector3(-11,10,0),Vector3(4,6,0),Vector3(-1,16,0),Vector3(-1,16,0),Vector3(11,8,0),Vector3(6,3.3,2.6),Vector3(0,10,0),Vector3(0,11,0)]
const SEGMENT_NAMES = ["approach_forecastle","forecastle_return","approach_quarterdeck","quarterdeck","approach","doorway_entry","doorway","cabin","cabin_return","exit","gallery","stern_ladder","poop","shroud_approach","shroud_climb","top_view","dressed_deck","exterior_transition","exterior"]
var segment_gpu: Array=[]
var previous_scale := 1.0
var scales: Array[float] = []
var gpu_ms: Array[float] = []
var render_cpu_ms: Array[float] = []
var samples: Array = []
var dry_run := false
var output := ""
var elapsed := 0.0
var last_tick := 0
var ready_to_measure := false
var frame_ms: Array[float] = []
var draw_calls := 0.0
var primitives := 0.0
var video_memory := 0.0

func _ready() -> void:
	for i in range(SEGMENT_NAMES.size()):segment_gpu.append([])
	seed(1729)
	$World/Player.input_enabled = false
	$World/Player.set_physics_process(false)
	$Camera3D.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if DisplayServer.get_name() != "headless" and DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED:
		push_error("Vsync is not disabled")
		get_tree().quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg == "--dry-run":
			dry_run = true
		elif arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	get_node("/root/PerfEvents").start()
	await $World.cabin_prewarm.warm()
	_move_camera(0.0)
	previous_scale = get_viewport().scaling_3d_scale
	last_tick = Time.get_ticks_usec()
	ready_to_measure=true
	if dry_run:
		# Validate all path samples and the output schema without claiming GPU metrics.
		for i in range(1201):
			_move_camera(float(i) / 60.0)
			$World.cabin.update_visibility($World.ship_body.to_local($Camera3D.position))
			samples.append({"path_seconds":float(i)/60.0,"dry_run":true,"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"physics_process_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,"node_count":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),"events":drain_events()})
			if not $Camera3D.transform.is_finite():
				push_error("Non-finite camera path")
				get_tree().quit(1)
				return
		_finish()

func _process(_delta: float) -> void:
	if dry_run or not ready_to_measure:
		return
	var now := Time.get_ticks_usec()
	var dt := float(now - last_tick) / 1000000.0
	last_tick = now
	var previous := elapsed
	elapsed += dt
	_move_camera(elapsed / WARMUP * DURATION if elapsed < WARMUP else minf(elapsed - WARMUP, DURATION))
	if previous >= WARMUP:
		frame_ms.append(dt * 1000.0)
		scales.append(previous_scale)
		var rid := get_viewport().get_viewport_rid()
		var gpu := RenderingServer.viewport_get_measured_render_time_gpu(rid)
		var cpu := RenderingServer.viewport_get_measured_render_time_cpu(rid)
		gpu_ms.append(gpu)
		# Render timestamp belongs to the preceding submitted camera pose.
		var segment := mini(SEGMENT_NAMES.size()-1, int(maxf(0.0, previous-WARMUP)/DURATION*SEGMENT_NAMES.size()))
		segment_gpu[segment].append(gpu)
		render_cpu_ms.append(cpu)
		var frame_primitives := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		var frame_draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var frame_objects := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		samples.append({"scaling_3d_scale": previous_scale, "primitives": frame_primitives, "draw_calls": frame_draws, "objects": frame_objects, "segment_name": SEGMENT_NAMES[segment], "segment": segment, "path_seconds": previous - WARMUP, "frame_ms": dt * 1000.0, "gpu_ms": gpu, "render_cpu_ms": cpu, "process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"physics_process_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,"node_count":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),"ticks_usec":now,"events":drain_events()})
		draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		video_memory += Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	previous_scale = get_viewport().scaling_3d_scale
	if elapsed >= WARMUP + DURATION:
		_finish()

func _move_camera(time: float) -> void:
	var progress := clampf(time / DURATION, 0.0, 1.0) * (EYES.size() - 1)
	var index := mini(int(progress), EYES.size() - 2)
	for door in $World.doors: door.set_open(progress>=4.0 and progress<11.0, dry_run)
	var blend := smoothstep(0.0, 1.0, progress - index)
	var eye_a: Vector3 = $World.ship_body.to_global(EYES[index]) if index < EYES.size()-2 else EYES[index]
	var eye_b: Vector3 = $World.ship_body.to_global(EYES[index + 1]) if index + 1 < EYES.size()-2 else EYES[index + 1]
	var target_a: Vector3 = $World.ship_body.to_global(TARGETS[index]) if index < EYES.size()-2 else TARGETS[index]
	var target_b: Vector3 = $World.ship_body.to_global(TARGETS[index + 1]) if index + 1 < EYES.size()-2 else TARGETS[index + 1]
	$Camera3D.position = eye_a.lerp(eye_b, blend)
	$Camera3D.look_at(target_a.lerp(target_b, blend))

func _finish() -> void:
	set_process(false)
	var quality = get_node("/root/Quality")
	var actual := Vector2i(get_viewport().get_visible_rect().size)
	if not dry_run:
		actual = Vector2i(get_viewport().get_texture().get_size())
	if quality.requested_size != Vector2i.ZERO and actual != quality.requested_size:
		push_error("Viewport mismatch: requested %s actual %s" % [quality.requested_size, actual])
		get_tree().quit(1)
		return
	var synthetic: Array[float] = []
	synthetic.resize(100)
	synthetic.fill(10.0)
	synthetic[99] = 50.0
	var stats := statistics(synthetic)
	if not is_equal_approx(stats.average_fps, 100000.0 / 1040.0) or stats.one_percent_low_fps != 20.0 or stats.worst_frame_ms != 50.0:
		push_error("Statistics self-test failed")
		get_tree().quit(1)
		return
	var segment_test := segment_statistics([[1.0, 4.0, 8.0]])
	if segment_test[0].p50_gpu_ms != 4.0 or segment_test[0].p95_gpu_ms != 8.0:
		push_error("Segment percentile self-test failed")
		get_tree().quit(1)
		return
	var report := {
		"schema_version": 6, "statistics_self_test": "PASS",
		"event_types":["door_open","door_close","interior_visibility","auto_duck_start","auto_duck_end","dynres_change","climb_volume_enter","climb_volume_exit","cabin_prewarm_start","cabin_prewarm_end"],
		"monitor_units":{"process_ms":"Performance.TIME_PROCESS * 1000","physics_process_ms":"Performance.TIME_PHYSICS_PROCESS * 1000","node_count":"Performance.OBJECT_NODE_COUNT"},
		"overrides": quality.overrides, "settings": quality.effective,
		"gpu_adapter": RenderingServer.get_video_adapter_name(),
		"vsync_mode": null if dry_run else DisplayServer.window_get_vsync_mode(),
		"internal_3d_size_from_scale": [int(actual.x * get_viewport().scaling_3d_scale), int(actual.y * get_viewport().scaling_3d_scale)],
		"scaling_3d_scale": get_viewport().scaling_3d_scale,
		"scaling_3d_mode": get_viewport().scaling_3d_mode,
		"gpu_by_segment": segment_statistics(segment_gpu), "average_gpu_ms": null, "average_render_cpu_ms": null, "samples": samples, "dry_run": dry_run, "quality": get_node("/root/Quality").tier,
		"renderer": RenderingServer.get_current_rendering_method(),
		"resolution": [actual.x, actual.y],
		"render_target_size": [actual.x, actual.y],
		"warmup_seconds": WARMUP, "path_seconds": DURATION, "frame_count": frame_ms.size(),
		"average_fps": null, "one_percent_low_fps": null, "worst_frame_ms": null, "worst_frame_segment":null, "worst_frame_path_seconds":null,
		"average_draw_calls": null, "average_primitives": null, "average_video_memory_bytes": null,
		"path_note": "M2b: main shroud climb, fighting top, dressed deck, forecastle, quarterdeck, arched door entry, cabin table, door exit, poop deck, exterior"
	}
	if not dry_run:
		if frame_ms.is_empty():
			push_error("No performance samples")
			get_tree().quit(1)
			return
		report.merge(statistics(frame_ms), true)
		for sample in samples:
			if sample.frame_ms==report.worst_frame_ms:
				report.worst_frame_segment=sample.segment_name
				report.worst_frame_path_seconds=sample.path_seconds
				break
		report.average_gpu_ms = mean(gpu_ms)
		report.average_render_cpu_ms = mean(render_cpu_ms)
		var refresh := DisplayServer.screen_get_refresh_rate()
		if refresh > 0 and absf(report.average_fps - refresh) / refresh < 0.02:
			push_warning("Frame rate is within 2% of display refresh; check compositor pacing")
		report.average_draw_calls = draw_calls / frame_ms.size()
		report.average_primitives = primitives / frame_ms.size()
		report.average_video_memory_bytes = video_memory / frame_ms.size()
	for group in report.gpu_by_segment:
		var count := 0
		var totals := {"primitives":0.0,"draw_calls":0.0,"objects":0.0}
		for sample in samples:
			if not sample.has("segment") or sample.segment!=group.segment:continue
			count+=1
			for key in totals:totals[key]+=sample[key]
		for key in totals:group["average_"+key]=totals[key]/count if count>0 else null

	report["dynamic_resolution"]={"enabled":quality.effective["dynres"]=="on", "min_scale":null if dry_run else scales.min(), "mean_scale":null if dry_run else mean(scales), "fraction_below_1":null}
	if not dry_run:
		var below:=0
		for scale in scales:
			if scale<0.99999:below+=1
		report.dynamic_resolution.fraction_below_1=float(below)/scales.size()
	# The shell harness supplies a separate full path measurement, never an estimate.
	report["dynres_off_result"]=null
	report["dynres_off_note"]="Run tools/perf.sh to include the independent dynres-off pass."
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write performance report: " + output)
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("PERF: ", "dry-run PASS (1201 camera samples; statistics self-test PASS; GPU metrics null)" if dry_run else "measured 20 s path", "; report: ", output)
	get_tree().quit()

static func mean(values: Array[float]) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total / maxi(1, values.size())

static func statistics(values: Array[float]) -> Dictionary:
	var ordered := values.duplicate()
	ordered.sort()
	ordered.reverse()
	var count := maxi(1, int(ceil(ordered.size() * 0.01)))
	var worst: Array[float] = []
	for i in range(count):
		worst.append(ordered[i])
	return {"average_fps": 1000.0 / mean(values),
		"one_percent_low_fps": 1000.0 / mean(worst), "worst_frame_ms": ordered[0]}

static func segment_statistics(groups: Array) -> Array:
	var result := []
	for i in range(groups.size()):
		var values: Array = groups[i].duplicate()
		values.sort()
		result.append({"segment": i, "name": SEGMENT_NAMES[i], "start_seconds": i*DURATION/SEGMENT_NAMES.size(),
			"end_seconds": (i+1)*DURATION/SEGMENT_NAMES.size(), "samples": values.size(),
			"p50_gpu_ms": null if values.is_empty() else values[int((values.size()-1)*0.50)],
			"p95_gpu_ms": null if values.is_empty() else values[int(ceil((values.size()-1)*0.95))]})
	return result

func drain_events() -> Array:
	var events: Array=get_node("/root/PerfEvents").events.duplicate()
	get_node("/root/PerfEvents").events.clear()
	return events
