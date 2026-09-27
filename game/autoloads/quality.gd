extends Node
## Both harnesses start native without MSAA; Low may adapt resolution.
var tier := "low"
var overrides: Dictionary = {}
var effective: Dictionary = {}
var dynamic_resolution = preload("res://autoloads/dynamic_resolution.gd").new()
var requested_size := Vector2i.ZERO

func _ready() -> void:
	tier = "high" if RenderingServer.get_current_rendering_method() == "forward_plus" else "low"
	for arg in OS.get_cmdline_user_args():
		var key := arg.get_slice("=", 0).trim_prefix("--")
		var value := arg.get_slice("=", 1)
		if key == "quality":
			tier = value
		elif key == "expect":
			requested_size = Vector2i(int(value.get_slice("x", 0)), int(value.get_slice("x", 1)))
		elif key in ["rigging-material","deck-props", "rigging-climb-debug", "interactables", "dynres", "cabin-bake", "cabin-props", "cabin-shadows", "cabin-triplanar", "cabin-shell", "cabin-lights", "cabin-occluder", "stairs", "collision-debug", "msaa", "glow", "render-scale", "fsr", "shadow-quality", "sun-energy", "exposure", "ocean", "ocean-waves", "ocean-grid", "ocean-order", "ocean-clip", "ocean-shader", "ocean-debug", "ocean-fft", "ocean-wake", "ship-speed", "sails", "hull-cull", "fog", "aniso", "shadows", "rigging"]: 
			overrides[key] = value
	if tier not in ["low", "high"]:
		push_error("Unknown quality: " + tier)
		get_tree().quit(2)
	for key in ["ocean-waves", "ocean-grid"]:
		if key in overrides:
			var value := str(overrides[key])
			var number := int(value)
			var valid := value.is_valid_int()
			valid = valid and (number >= 8 and number <= 64 if key == "ocean-waves" else number >= 32 and number <= 256 and number % 2 == 0)
			if not valid:
				push_error("Invalid " + key + ": " + value)
				get_tree().quit(2)
	if "ship-speed" in overrides and (not str(overrides["ship-speed"]).is_valid_float() or float(overrides["ship-speed"]) < 0.0 or float(overrides["ship-speed"]) > 12.0):
		push_error("Ship speed must be 0..12 knots")
		get_tree().quit(2)
	if overrides.get("ocean", "on") not in ["on", "off"]:
		push_error("Ocean must be on or off")
		get_tree().quit(2)
	var choices_by_key := {"rigging-material":["opaque","legacy"],"deck-props":["on","off"], "rigging-climb-debug":["on","off","volumes"], "interactables":["on","off"], "dynres": ["on", "off"], "cabin-bake": ["on", "off"], "cabin-props": ["on", "off", "lite"], "cabin-shadows": ["on", "off"], "cabin-triplanar": ["on", "off"], "cabin-shell": ["on", "off"], "cabin-lights": ["on", "off"], "cabin-occluder": ["on", "off"], "stairs": ["on", "off"], "collision-debug": ["off", "on"], "ocean-debug": ["off", "rings"], "hull-cull": ["back", "disabled"], "fog": ["on", "off"], "aniso": ["1", "4", "16"], "shadows": ["on", "off"], "rigging": ["on", "off"], "ocean-order": ["before", "after"], "ocean-fft": ["on", "off"], "ocean-wake": ["on", "off"], "sails": ["0", "1", "2", "3"], "ocean-clip": ["discard", "occluder", "off"], "ocean-shader": ["low", "high"]}
	for key in choices_by_key:
		var choices: Array = choices_by_key[key]
		if key in overrides and overrides[key] not in choices:
			push_error("Invalid " + key)
			get_tree().quit(2)
	if requested_size != Vector2i.ZERO:
		# Movie Maker uses the viewport, not the --resolution window dimensions.
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		get_window().content_scale_size = requested_size
		get_window().size = requested_size

func apply_to_world(environment: Environment, sun: DirectionalLight3D) -> void:
	var high := tier == "high"
	effective = {"rigging-material":"opaque","deck-props":"on", "rigging-climb-debug":"on", "interactables":"on", "dynres": "off", "cabin-bake": "on", "cabin-props": "on", "cabin-shadows": "off", "cabin-triplanar": "off", "cabin-shell": "on", "cabin-lights": "on", "cabin-occluder": "off", "stairs": "on", "collision-debug": "off", "msaa": 0, "glow": "on" if high else "off", "render-scale": 1.0,
		"hull-cull": "back", "fog": "on", "aniso": 4 if high else 2, "shadows": "on", "rigging": "on",
		"fsr": "off", "shadow-quality": "high" if high else "low",
		"sun-energy": LightingRig.SUN_ENERGY, "exposure": LightingRig.EXPOSURE}
	effective.merge(overrides, true)
	effective.merge(ocean_settings(), true)
	if effective.fsr == "on" and not high:
		push_error("FSR is High-tier only")
		get_tree().quit(2)
		return
	var viewport := get_viewport()
	viewport.anisotropic_filtering_level = {1: Viewport.ANISOTROPY_DISABLED, 2: Viewport.ANISOTROPY_2X, 4: Viewport.ANISOTROPY_4X, 16: Viewport.ANISOTROPY_16X}[int(effective.aniso)]
	effective.aniso = int(effective.aniso)
	sun.shadow_enabled = effective.shadows == "on"
	environment.fog_enabled = effective.fog == "on"
	viewport.msaa_3d = {0: Viewport.MSAA_DISABLED, 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X}[int(effective.msaa)]
	viewport.scaling_3d_scale = float(effective["render-scale"])
	dynamic_resolution.reset(viewport.scaling_3d_scale)
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if effective.fsr == "on" else Viewport.SCALING_3D_MODE_BILINEAR
	var filter_quality: int = {"low": 1, "med": 2, "high": 3}[effective["shadow-quality"]]
	RenderingServer.directional_soft_shadow_filter_set_quality(filter_quality)
	RenderingServer.positional_soft_shadow_filter_set_quality(filter_quality)
	RenderingServer.directional_shadow_atlas_set_size(4096 if high else 2048, true)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if high else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 140.0 if high else 50.0
	sun.directional_shadow_split_1 = 0.25
	sun.light_energy = float(effective["sun-energy"])
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = LightingRig.AMBIENT_ENERGY
	environment.tonemap_exposure = float(effective.exposure)
	environment.glow_enabled = effective.glow == "on"
	print("SETTINGS: ", JSON.stringify(effective), " overrides=", JSON.stringify(overrides))

func ocean_settings() -> Dictionary:
	return {
		"ocean-debug": overrides.get("ocean-debug","off"),
		"ocean": overrides.get("ocean","on"),
		# Explicit long-wave components (sea_state.gd); the same sea on every tier.
		"ocean-waves": int(overrides.get("ocean-waves",32)),
		"ocean-grid": int(overrides.get("ocean-grid",192 if tier=="high" else 128)),
		"ocean-detail-size": 256 if tier=="high" else 128,
		# GPU FFT cascades and the reactive wave simulation around the ship.
		"ocean-fft": overrides.get("ocean-fft","on"),
		"ocean-fft-size": 256 if tier=="high" else 128,
		"ocean-wake": overrides.get("ocean-wake","on"),
		"ocean-wake-size": 256 if tier=="high" else 128,
		"ocean-wake-extent": 128.0 if tier=="high" else 96.0,
		# Starting sail (0 furled .. 3 full) and speed in knots; -1 = the steady
		# speed the wind gives that sail. --ship-speed=0 starts furled and still.
		"sails": int(overrides.get("sails", 0 if str(overrides.get("ship-speed", "")).is_valid_float() and float(overrides["ship-speed"]) == 0.0 else 3)),
		"ship-speed": float(overrides.get("ship-speed", -1.0)),
		"ocean-order": overrides.get("ocean-order","after"),
		"ocean-clip": overrides.get("ocean-clip","occluder"),
		# Claude, 2026-09-25: the full-lit ("high") ocean shader measured the same cost as
		# "low" on the HD 530 (80.1 vs 80.3 fps avg, 53.4 vs 55.3 1% low at 1080p) and looks
		# far better (no milky sea, visible swell, real glitter). So it is the default on
		# every tier; "low" stays as an override. Wave count and grid density stay tiered.
		"ocean-shader": overrides.get("ocean-shader","high"),
	}

func _process(delta: float) -> void:
	if effective.get("dynres","off")!="on":return
	# Frozen photo tours must never depend on GPU speed or previous shots.
	if get_node("/root/SimClock").frozen:return
	var viewport:=get_viewport()
	var gpu_ms:=RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())
	var scale: float=dynamic_resolution.step(gpu_ms,delta)
	if not is_equal_approx(viewport.scaling_3d_scale,scale):
		get_node("/root/PerfEvents").mark("dynres_change", {"from":viewport.scaling_3d_scale,"to":scale})
		viewport.scaling_3d_scale=scale
