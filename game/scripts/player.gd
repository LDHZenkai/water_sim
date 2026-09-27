extends CharacterBody3D

const ACTION_KEYS := {"move_forward": KEY_W, "move_back": KEY_S,
	"move_left": KEY_A, "move_right": KEY_D, "sprint": KEY_SHIFT,
	"crouch": KEY_C, "jump": KEY_SPACE, "interact": KEY_E, "pause": KEY_ESCAPE,
	"brace": KEY_Q}
signal footstep
signal splashed
@export var walk_speed := 1.6
## A hurried jog: nobody sprints flat out on a pitching deck.
@export var sprint_speed := 3.4
@export var mouse_sensitivity := 0.002
## Gait: the head rises and falls once per step and sways once per stride.
@export_range(0.0, 0.04) var head_bob_amount := 0.015
@export_range(0.0, 0.04) var head_sway_amount := 0.018
## Step length, m: ~1.9 steps/s walking, ~2.9 running.
const STEP_WALK := 0.8
const STEP_RUN := 1.5
var input_enabled := true
var move_input := Vector2.ZERO
var test_input := false
var test_sprint := false
var test_crouch := false
var spawn_point: Marker3D
@export_range(0.0, 1.0) var camera_roll_amount := 0.18
var deck: AnimatableBody3D
var sea_height: Callable
var inside_hull: Callable
var ship_space_carry := true
var ship_position := Vector3.ZERO
var ship_velocity := Vector3.ZERO
var _carry_initialized := false
var ship_yaw := -PI / 2.0
var rigging_climb: Node3D
var climb_release:=0.0 # Kept for existing instrumentation; release is now geometric.
var attached_route: Dictionary={}
var released_route: Dictionary={}
var climb_query: Callable
var deck_pose: Callable
var auto_duck := false
## Standing at the ship's wheel (exploration/helm.gd): WASD steer, not walk.
var at_helm := false
## Sea legs (scripts/sea_legs.gd): apparent gravity on the moving deck,
## staggering, sliding, bracing (hold Q) and the head's lag.
var sea_legs = preload("res://scripts/sea_legs.gd").new()
## Ship motion model (buoyancy.gd): the hull's own surge and turn are felt too.
var motion: RefCounted
## Wet planking (rain, spray) loses grip sooner.
var wet := false
var test_brace := false
var braced := false
var stance := "standing"
var _gait := 0.0
var _was_on_floor := true
var _fall_speed := 0.0
var in_climb_volume := false
var standing_shape := CapsuleShape3D.new()
var standing_query := PhysicsShapeQueryParameters3D.new()
var _eye_height := 1.65
var _pitch := 0.0
var _bob_phase := 0.0
var _step_distance := 0.0
var _respawning := false
var _fade: ColorRect
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var capsule: CollisionShape3D = $Capsule

func _ready() -> void:
	for action in ACTION_KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventKey.new()
			event.physical_keycode = ACTION_KEYS[action]
			InputMap.action_add_event(action, event)
	standing_shape.radius = 0.22
	standing_shape.height = 1.8
	standing_query.shape = standing_shape
	standing_query.collision_mask = 1
	floor_block_on_wall = false
	floor_stop_on_slope = true
	floor_constant_speed = true
	camera.top_level = true
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	platform_floor_layers = 0
	platform_wall_layers = 0
	rotation.y = -PI / 2.0 # Bow is +X.
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var layer := CanvasLayer.new()
	add_child(layer)
	_fade = ColorRect.new()
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	_fade.hide()

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and (test_input or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED):
		ship_yaw = wrapf(ship_yaw - event.relative.x * mouse_sensitivity, -PI, PI)
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -1.5, 1.5)
		head.rotation.x = _pitch

func _physics_process(delta: float) -> void:
	if not input_enabled or _respawning:
		return
	var carrying := ship_space_carry and is_instance_valid(deck)
	if carrying:
		if not _carry_initialized:
			ship_position = deck.to_local(global_position)
			ship_velocity = deck.global_basis.inverse() * velocity
			_carry_initialized = true
		global_position = deck.to_global(ship_position)
		global_basis = deck.global_basis * Basis(Vector3.UP, ship_yaw)
		up_direction = deck.global_basis.y
		velocity = deck.global_basis * ship_velocity
	# Match the model's steep companionway stairs without lengthening them.
	floor_max_angle = deg_to_rad(70.0) if carrying and ship_position.x>-0.9 and ship_position.x<0.85 and absf(ship_position.z-0.097)>1.4 else deg_to_rad(45.0)
	floor_constant_speed = floor_max_angle<1.0
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var axis := move_input if test_input else Vector2.ZERO
	if captured and not test_input:
		axis = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if at_helm:
		axis = Vector2.ZERO
	if carrying:
		var hull := Vector3.ZERO
		if motion != null:
			var bow: Vector2 = motion.forward() * float(motion.speed)
			hull = Vector3(bow.x, 0.0, bow.y)
		sea_legs.sense(deck.global_transform, ship_position, hull, delta)
	# A person losing their footing cannot walk where they like.
	axis *= 1.0 - clampf(sea_legs.off_balance * 0.5, 0.0, 0.7)
	floor_stop_on_slope = axis.is_zero_approx()
	var crouched := test_crouch if test_input else captured and Input.is_action_pressed("crouch")
	# The low, original arched passage is the only automatic stoop volume.
	var local_feet := deck.to_local(global_position) if carrying else global_position
	var was_ducking := auto_duck
	auto_duck = local_feet.x < -8.15 and local_feet.x > -9.8 and local_feet.y > 6.0 and local_feet.y < 6.7 and (absf(local_feet.z+0.69)<0.42 or absf(local_feet.z-0.885)<0.42)
	if auto_duck!=was_ducking:get_node("/root/PerfEvents").mark("auto_duck_start" if auto_duck else "auto_duck_end")
	crouched = crouched or auto_duck
	# Do not expand into low ceilings.
	if not crouched and (capsule.shape as CapsuleShape3D).height < 1.8:
		standing_query.transform = Transform3D(global_basis, global_position + up_direction * 0.92)
		crouched = not get_world_3d().direct_space_state.intersect_shape(standing_query).is_empty()
	var height := (1.4 if auto_duck else 1.2) if crouched else 1.8
	if not is_equal_approx((capsule.shape as CapsuleShape3D).height, height):
		(capsule.shape as CapsuleShape3D).height = height
	capsule.position.y = height*0.5
	var speed := sprint_speed if (test_sprint if test_input else captured and Input.is_action_pressed("sprint")) else walk_speed
	if crouched and not auto_duck:
		speed = 0.8
	var direction := global_basis * Vector3(axis.x, 0, axis.y)
	var local_velocity := deck.global_basis.inverse()*velocity if carrying else velocity
	var local_direction := deck.global_basis.inverse()*direction if carrying else direction
	var sprinting := speed > walk_speed + 0.01
	braced = at_helm or (test_brace if test_input else captured and Input.is_action_pressed("brace"))
	stance = "braced" if braced else ("crouched" if crouched and not auto_duck else ("standing" if axis.is_zero_approx() else ("running" if sprinting else "walking")))
	if carrying:
		sea_legs.balance(delta, is_on_floor(), stance, wet)
		speed *= sea_legs.walk_factor(Vector2(local_direction.x, local_direction.z).normalized())
		# Bracing: a hand on the rail or a line, shuffling along.
		if braced: speed = minf(speed, 0.7)
	local_velocity.x = local_direction.x * speed + sea_legs.stagger.x
	local_velocity.z = local_direction.z * speed + sea_legs.stagger.z
	if not is_on_floor():
		# Felt weight: lighter as the deck drops away, heavier as it rises.
		local_velocity.y -= 9.81 * (sea_legs.weight if carrying else 1.0) * delta
		_fall_speed = maxf(_fall_speed, -local_velocity.y)
	else:
		local_velocity.y = 0.0
		if captured and Input.is_action_pressed("jump"):
			local_velocity.y = 3.0
	var jump_release:=Input.is_action_just_pressed("jump")
	if jump_release and not attached_route.is_empty():
		released_route=attached_route
		attached_route={}
	if not released_route.is_empty() and not jump_release:
		if is_on_floor() or rigging_climb.distance_to_route(ship_position,released_route)>1.0:
			released_route={}
	climb_release=1.0 if not released_route.is_empty() else 0.0
	var rope_route: Dictionary=rigging_climb.route_at(ship_position) if is_instance_valid(rigging_climb) else {}
	if not attached_route.is_empty() and (rope_route.is_empty() or not is_instance_valid(attached_route.node)):
		attached_route={}
	if attached_route.is_empty() and released_route.is_empty() and not jump_release and not rope_route.is_empty():
		if rigging_climb.wants_grab(ship_position,local_direction,-axis.y,rope_route):attached_route=rope_route
	var rope: bool=not attached_route.is_empty()
	if is_instance_valid(rigging_climb):rigging_climb.update_gates(ship_position,rope)
	var climbing: bool = carrying and climb_query.is_valid() and (climb_query.call(ship_position) or rope)
	if climbing!=in_climb_volume:
		get_node("/root/PerfEvents").mark("climb_volume_enter" if climbing else "climb_volume_exit")
		in_climb_volume=climbing
	if climbing and not Input.is_action_pressed("jump"):
		local_velocity.y = -axis.y * walk_speed
		if rope:local_velocity=rigging_climb.velocity_at(ship_position,-axis.y*walk_speed)
	if carrying and is_on_floor() and floor_max_angle>1.0:
		var floor_normal: Vector3=deck.global_basis.inverse()*get_floor_normal()
		if floor_normal.y>0.1:
			local_velocity.y=-(floor_normal.x*local_velocity.x+floor_normal.z*local_velocity.z)/floor_normal.y
			local_velocity=local_velocity.limit_length(maxf(speed,0.01))
	velocity = deck.global_basis*local_velocity if carrying else local_velocity
	var before_move:=global_position
	var grounded_before:=is_on_floor()
	move_and_slide()
	# A human can step over low hatch coamings. Sweep the full capsule upward,
	# forward and down; never teleport through a wall or into a low ceiling.
	var forward_motion:=direction*speed*delta
	# A staggering body stumbles over coamings the same way.
	var staggering: bool=carrying and sea_legs.stagger.length()>0.3
	if staggering:forward_motion+=deck.global_basis*sea_legs.stagger*delta
	var blocked:=global_position.distance_to(before_move)<forward_motion.length()*0.5
	if (grounded_before or staggering) and (is_on_wall() or staggering) and (not axis.is_zero_approx() or staggering) and blocked and forward_motion.length()>0.0001:
		var rise:=up_direction*0.22
		var raised:=global_transform
		if not test_move(raised,rise):
			raised.origin+=rise
			var step_forward:=forward_motion.normalized()*maxf(0.08,forward_motion.length())
			if not test_move(raised,step_forward):
				raised.origin+=step_forward
				var landing:=KinematicCollision3D.new()
				if test_move(raised,-up_direction*0.24,landing) and landing.get_normal().dot(up_direction)>0.65:
					global_position=raised.origin+landing.get_travel()
	if carrying:
		ship_position = deck.to_local(global_position)
		ship_velocity = deck.global_basis.inverse()*velocity
		# Collision uses the synchronized old deck. Publish the solved local pose
		# against this tick's requested deck pose for matching interpolation.
		var final_deck: Transform3D = deck_pose.call() if deck_pose.is_valid() else deck.global_transform
		global_transform = Transform3D(final_deck.basis * Basis(Vector3.UP, ship_yaw), final_deck * ship_position)
	if is_instance_valid(deck):
		var upright := Basis.from_euler(Vector3(_pitch,global_rotation.y,0))
		var leaning := global_basis*Basis.from_euler(Vector3(_pitch,0,0))
		head.global_basis=upright.slerp(leaning.orthonormalized(),camera_roll_amount)
	# Gait from distance walked over the deck (ship space), not through the world.
	var walked := Vector2(local_velocity.x, local_velocity.z).length() if carrying else Vector2(velocity.x, velocity.z).length()
	var distance := walked * delta if is_on_floor() else 0.0
	var step := STEP_RUN if sprinting else STEP_WALK
	var before_step := floori(_bob_phase / PI)
	_bob_phase += distance / step * PI
	var stepping := clampf(walked / walk_speed, 0.0, 1.0)
	_gait = move_toward(_gait, stepping, delta * 4.0)
	if floori(_bob_phase / PI) != before_step:
		footstep.emit()
	_step_distance += distance
	if is_on_floor() and not _was_on_floor:
		sea_legs.jolt(_fall_speed)
		if _fall_speed > 1.5: footstep.emit()
	if is_on_floor(): _fall_speed = 0.0
	_was_on_floor = is_on_floor()
	_eye_height = move_toward(_eye_height, height-0.15, delta*1.6)
	# Lowest at each heel strike, highest mid-stance; running bounces more.
	var bob := head_bob_amount * (1.8 if sprinting else 1.0)
	head.position.y = _eye_height - cos(2.0 * _bob_phase) * bob * _gait
	head.position.x = sin(_bob_phase) * head_sway_amount * _gait
	var water_y: float = sea_height.call(global_position) if sea_height.is_valid() else 0.0
	var inside: bool = inside_hull.call(global_position) if inside_hull.is_valid() else false
	if global_position.y < water_y + 0.15 and not inside:
		_respawn()

func _respawn() -> void:
	_respawning = true
	_fade.show()
	splashed.emit() # Splash audio/particles are M4/M1b hooks.
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.25)
	await tween.finished
	if is_instance_valid(spawn_point):
		global_transform = spawn_point.global_transform
		rotation.y = -PI / 2.0
		reset_physics_interpolation()
	_carry_initialized = false
	ship_yaw = -PI / 2.0
	velocity = Vector3.ZERO
	sea_legs.reset()
	tween = create_tween()
	tween.tween_property(_fade, "color:a", 0.0, 0.35)
	await tween.finished
	_fade.hide()
	_respawning = false

func _process(_delta: float) -> void:
	if not input_enabled or not is_instance_valid(deck): return
	# The rendered ship supplies roll/pitch; mouse yaw is read directly, never
	# interpolated through last tick's body yaw (which reintroduces one tick lag).
	var deck_basis := deck.get_global_transform_interpolated().basis
	var yaw_basis := deck_basis * Basis(Vector3.UP, ship_yaw)
	var looking := yaw_basis * Basis(Vector3.RIGHT, _pitch)
	var upright := Basis.from_euler(Vector3(_pitch, yaw_basis.get_euler().y, 0))
	# The inner ear holds the head to apparent gravity, not the true vertical:
	# a lurch of the deck tilts the horizon for a moment.
	var felt: Vector3 = sea_legs.up
	if felt.angle_to(Vector3.UP) > 0.0005:
		var lean := Basis(Quaternion(Vector3.UP, felt).slerp(Quaternion.IDENTITY, 0.5))
		upright = lean * upright
	head.global_basis = upright.slerp(looking.orthonormalized(), camera_roll_amount)
	# Camera is independent of body interpolation; otherwise that parent would
	# interpolate mouse yaw again after this render-time correction.
	var eye := get_global_transform_interpolated().origin + deck_basis.y * head.position.y
	# Gait sway to the side, and the neck's lag behind the deck's lurches.
	eye += (yaw_basis * Vector3.RIGHT) * head.position.x + deck_basis * sea_legs.head
	camera.global_transform = Transform3D(head.global_basis, eye)
