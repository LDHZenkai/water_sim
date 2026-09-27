extends RefCounted
## Sea legs: what an ordinary 1.8 m person feels standing on this deck.
## The deck is a moving, tilting platform, so the body's "down" is not the
## deck's down. Apparent gravity g - a (a = acceleration of the deck point
## under the feet: heave, plus roll and pitch about axes metres below, plus
## the hull's own surge and turn) tilts, grows and shrinks. High on the poop
## deck or aloft the lever arm makes it far worse than amidships.
## The player walks against it: slower uphill, quicker down; staggers when
## its sideways part is more than the stance can hold (motion-induced
## interruptions: a standing person tips at a lateral/vertical force ratio of
## about 0.25, Graham 1990) and slides when it beats shoe friction. The head
## is a mass on the neck and lags the deck's lurches by a few centimetres.
const G := 9.81
## Lateral/vertical force ratio each stance resists before a stagger step.
const TIPPING := {"walking": 0.2, "running": 0.14, "standing": 0.25, "crouched": 0.4, "braced": 0.9}
## Shoe on deck planking.
const FRICTION_DRY := 0.6
const FRICTION_WET := 0.38
## Neck: ~1.6 Hz, fairly damped.
const HEAD_FREQUENCY := 1.6
const HEAD_DAMPING := 0.55
## Head displacement per m/s^2 of deck acceleration (inertia against the neck).
const HEAD_GAIN := 0.011

## Apparent gravity in ship space (m/s^2) and its parts: the sideways force
## ratio (tan of the apparent tilt; direction the body is pushed, ship XZ)
## and the felt weight (1 = on land).
var gravity := Vector3(0.0, -G, 0.0)
var lateral := Vector2.ZERO
var weight := 1.0
## Involuntary ship-space velocity from losing footing, m/s.
var stagger := Vector3.ZERO
## How far the stance is exceeded (0 = steady).
var off_balance := 0.0
var sliding := false
## Head offset from the neck's spring, ship space, m.
var head := Vector3.ZERO
## Apparent "up" in world space (what the inner ear says is up).
var up := Vector3.UP
var _head_velocity := Vector3.ZERO
var _poses: Array[Transform3D] = []
var _hull_velocity: Array[Vector3] = []
var _acceleration := Vector3.ZERO

func reset() -> void:
	_poses.clear()
	_hull_velocity.clear()
	_acceleration = Vector3.ZERO
	stagger = Vector3.ZERO
	head = Vector3.ZERO
	_head_velocity = Vector3.ZERO

## Once per physics tick with the deck's pose, the feet (ship space) and the
## hull's velocity through the water (world; the frame itself never moves).
func sense(deck: Transform3D, feet: Vector3, hull_velocity: Vector3, delta: float) -> void:
	_poses.append(deck)
	_hull_velocity.append(hull_velocity)
	if _poses.size() > 3:
		_poses.pop_front()
		_hull_velocity.pop_front()
	var raw := Vector3.ZERO
	if _poses.size() == 3 and delta > 0.0:
		# Same point of the deck in three consecutive poses: its acceleration.
		raw = (_poses[2] * feet - 2.0 * (_poses[1] * feet) + _poses[0] * feet) / (delta * delta)
		raw += (_hull_velocity[2] - _hull_velocity[1]) / delta
		# A teleport (a frozen capture, a respawn) is not a force.
		if raw.length() > 60.0:
			raw = Vector3.ZERO
			_poses = [deck]
			_hull_velocity = [hull_velocity]
	# The body integrates over ~0.1 s; tick-to-tick jitter is not felt.
	_acceleration = _acceleration.lerp(raw, 1.0 - exp(-delta / 0.08))
	var apparent := Vector3(0.0, -G, 0.0) - _acceleration
	up = -apparent.normalized()
	gravity = deck.basis.orthonormalized().inverse() * apparent
	var normal := maxf(-gravity.y, 0.5)
	weight = -gravity.y / G
	lateral = Vector2(gravity.x, gravity.z) / normal
	# Neck spring: the head is left behind when the deck lurches.
	var w := TAU * HEAD_FREQUENCY
	var target := -(deck.basis.orthonormalized().inverse() * _acceleration) * HEAD_GAIN
	target.y = clampf(target.y, -0.06, 0.06)
	_head_velocity += ((target - head) * w * w - 2.0 * HEAD_DAMPING * w * _head_velocity) * delta
	head = (head + _head_velocity * delta).limit_length(0.15)

## A jolt to the head (landing from a jump or a fall), m/s downward.
func jolt(speed: float) -> void:
	_head_velocity.y -= clampf(speed, 0.0, 6.0) * 0.35

## Updates the stagger for this tick. stance: a TIPPING key.
func balance(delta: float, on_floor: bool, stance: String, wet: bool) -> void:
	var slope := lateral.length()
	var hold: float = TIPPING.get(stance, 0.25)
	off_balance = maxf(slope - hold, 0.0) / hold
	var s := Vector2(stagger.x, stagger.z)
	sliding = false
	if on_floor:
		var push := Vector2.ZERO
		if slope > hold:
			# Beyond the stance the feet shuffle downhill after the body.
			push = lateral / slope * (slope - hold) * G * 0.6
		var friction := FRICTION_WET if wet else FRICTION_DRY
		if slope > friction and stance != "braced":
			# Beyond friction the shoes let go.
			push += lateral / slope * (slope - friction) * G
			sliding = true
		s += push * delta
		# Each recovering step arrests the stagger.
		s = s.move_toward(Vector2.ZERO, (3.0 if slope <= hold else 0.9) * delta)
	s = s.limit_length(3.5)
	stagger = Vector3(s.x, 0.0, s.y)

## Walking speed factor in ship-space direction d (unit XZ): uphill against
## the apparent slope is hard work, downhill quick; heavy when the deck
## rises under you, light as it falls away.
func walk_factor(direction: Vector2) -> float:
	var along := direction.dot(lateral)
	var factor := clampf(1.0 + 1.2 * along, 0.45, 1.25)
	factor *= lerpf(1.0, 1.0 / clampf(weight, 0.6, 1.5), 0.35)
	return factor * (1.0 - clampf(off_balance * 0.5, 0.0, 0.6))
