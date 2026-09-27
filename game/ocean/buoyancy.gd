extends RefCounted
## Ship motion: sailing (surge, yaw, heading) plus the wave response (heave,
## roll, pitch). The ship stays at the world origin and the sea streams past
## it: `drift` is how far the water has moved relative to the ship, which the
## ocean, the FFT cascades and the wake simulation all apply. This Galilean
## frame is exact, keeps every coordinate small however far the ship sails,
## and still lets the hull turn (the frame translates, it never rotates).
const SEA = preload("res://ocean/default_sea.tres")
var heave := 0.0
var roll := 0.0
var pitch := 0.0
var velocity := Vector3.ZERO
var initialized := false
# Test scale changes the water surface itself, not a clamped output.
var wave_scale := 1.0
# Twelve probes within the measured 23 m waterline footprint.
const PROBE_X := [-10.0, -6.0, -2.0, 2.0, 6.0, 10.0]
const PROBE_Z := [-3.0, 3.0]
var _probes := PackedVector2Array()

## Sail settings: furled, reefed, working, full (fraction of full canvas).
const SAIL_CANVAS := [0.0, 0.35, 0.7, 1.0]
## Canvas set or taken in per second: a crew needs ~7 s from furled to full.
const SAIL_RATE := 0.15
const MAX_RUDDER := deg_to_rad(35.0)
const RUDDER_RATE := deg_to_rad(20.0)
## Surge: a = THRUST * canvas * |apparent wind|^2 * polar
##          - DRAG * u^2 (wave making) - LINEAR_DRAG * u (skin friction).
## Calibrated so a beam reach in 8 m/s wind makes ~6 knots, the hull takes
## ~30 s to gather way (a few hundred tonnes of galleon) and, furled, loses
## it again over a couple of minutes.
const THRUST := 0.0024
const DRAG := 0.004
const LINEAR_DRAG := 0.01
## Yaw: r' = RUDDER_GAIN u^2 sin(d) - YAW_DAMPING u r - YAW_DRAG r|r|.
## Full rudder at 6 knots turns about 2.3 deg/s (a ~150 m circle, 4 hull
## lengths) and settles into the turn over ~6 s. A hard turn bleeds speed.
const RUDDER_GAIN := 0.00133
const YAW_DAMPING := 0.054
const YAW_DRAG := 0.3
const TURN_DRAG := 150.0

## Controls. rudder_input: +1 puts the helm over to turn to port (left).
var sail := 3
var rudder_input := 0.0
## Initial state for reset_navigation(): start_speed < 0 means already
## sailing at the steady speed for start_sail.
var start_sail := 3
var start_heading := 0.0
var start_speed := -1.0
## Navigation state. heading is the yaw about +Y (0 = bow toward +X, east;
## positive turns to port). speed is through the water along the bow, m/s.
var canvas := 1.0
var rudder := 0.0
var heading := 0.0
var speed := 0.0
var yaw_rate := 0.0
var drift := Vector2.ZERO
var drift_previous := Vector2.ZERO

func _init() -> void:
 for x in PROBE_X:
  for z in PROBE_Z:
   _probes.append(Vector2(x, z))
 reset_navigation()

func reset_navigation() -> void:
 sail = clampi(start_sail, 0, SAIL_CANVAS.size() - 1)
 canvas = SAIL_CANVAS[sail]
 rudder = 0.0
 rudder_input = 0.0
 heading = start_heading
 yaw_rate = 0.0
 speed = steady_speed(canvas, heading) if start_speed < 0.0 else start_speed
 drift = Vector2.ZERO
 drift_previous = Vector2.ZERO

## Bow direction in world XZ.
func forward() -> Vector2:
 return Vector2(cos(heading), -sin(heading))

## Water velocity past the ship in world XZ (the ship's velocity reversed).
func water_velocity() -> Vector2:
 return -forward() * speed

func knots() -> float:
 return speed / 0.514444

## True wind in world XZ, from the sea state (the wind the sea was raised by).
static func wind() -> Vector2:
 return Vector2(cos(SEA.wind_heading), sin(SEA.wind_heading)) * SEA.wind_speed

## Angle between the bow and where the apparent wind comes from, radians.
func apparent_wind_angle(direction: Vector2, u: float) -> float:
 var apparent: Vector2 = wind() - direction * u
 if apparent.length() < 0.001: return PI
 return absf(direction.angle_to(-apparent.normalized()))

## Square rig driving force by apparent wind angle: nothing closer than ~48
## deg (yards braced hard, sails lifting), weak with the wind abeam, best with
## the wind on the quarter, a little less dead downwind where the after sails
## blanket the forward ones.
static func polar(angle: float) -> float:
 var a := absf(angle)
 return smoothstep(deg_to_rad(48.0), deg_to_rad(85.0), a) * (1.0 - 0.2 * smoothstep(deg_to_rad(140.0), deg_to_rad(180.0), a))

func thrust(amount: float, direction: Vector2, u: float) -> float:
 var apparent: Vector2 = wind() - direction * u
 return THRUST * amount * apparent.length_squared() * polar(apparent_wind_angle(direction, u))

func steady_speed(amount: float, yaw: float) -> float:
 var direction := Vector2(cos(yaw), -sin(yaw))
 var u := 2.0
 for i in range(40):
  # Positive root of DRAG u^2 + LINEAR_DRAG u = thrust.
  var t := maxf(thrust(amount, direction, u), 0.0)
  u = lerpf(u, (-LINEAR_DRAG + sqrt(LINEAR_DRAG * LINEAR_DRAG + 4.0 * DRAG * t)) / (2.0 * DRAG), 0.5)
 return u

func _navigate(delta: float) -> void:
 canvas = move_toward(canvas, SAIL_CANVAS[clampi(sail, 0, SAIL_CANVAS.size() - 1)], SAIL_RATE * delta)
 # A helm left alone drifts back amidships.
 rudder = move_toward(rudder, clampf(rudder_input, -1.0, 1.0) * MAX_RUDDER, RUDDER_RATE * delta)
 var direction := forward()
 var drag := (DRAG * speed * absf(speed) + LINEAR_DRAG * speed) * (1.0 + TURN_DRAG * yaw_rate * yaw_rate)
 speed = maxf(speed + (thrust(canvas, direction, speed) - drag) * delta, 0.0)
 # Rudder force grows with flow past it: no steerage without way on.
 var yaw_acceleration := RUDDER_GAIN * speed * speed * sin(rudder) - YAW_DAMPING * (speed + 0.3) * yaw_rate - YAW_DRAG * yaw_rate * absf(yaw_rate)
 yaw_rate += yaw_acceleration * delta
 heading = wrapf(heading + yaw_rate * delta, -PI, PI)
 drift_previous = drift
 drift += water_velocity() * delta

## Drift interpolated between physics ticks for rendering.
func drift_at(fraction: float) -> Vector2:
 return drift_previous.lerp(drift, fraction)

func target_at(time: float, count: int) -> Vector3:
 # The explicit long-wave band is the only part of the spectrum long enough
 # to move a 35 m hull; the FFT band (< split wavelength) averages out.
 # Probes turn with the hull; the water under them has drifted.
 var basis := Basis(Vector3.UP, heading)
 var points := PackedVector2Array()
 for probe in _probes:
  var p: Vector3 = basis * Vector3(probe.x, 0.0, probe.y)
  points.append(Vector2(p.x, p.z))
 var heights := SEA.heights(points, time, count, drift)
 var average := 0.0
 var slope_x := 0.0
 var slope_z := 0.0
 for i in range(_probes.size()):
  var y: float = heights[i] * wave_scale
  average += y / 12.0
  slope_x += _probes[i].x*y / 560.0
  slope_z += _probes[i].y*y / 108.0
 return Vector3(average, -atan(slope_z), atan(slope_x))

func step(time: float, delta: float, count: int) -> Transform3D:
 _navigate(delta)
 var target := target_at(time,count)
 # Kinematic heave; physical angular restoring torque and absolute damping.
 # No angular target velocity or acceleration feed-forward.
 if not initialized:
  initialized = true
 heave = target.x
 # Short pitch response follows the long swell; roll remains the slow mode.
 var omega := Vector2(TAU/14.0, TAU/2.5)
 var angle := Vector2(roll, pitch)
 var rate := Vector2(velocity.y, velocity.z)
 var acceleration := omega*omega*(Vector2(target.y,target.z)-angle) - 2.0*Vector2(0.35,0.4)*omega*rate
 rate += acceleration*delta
 angle += rate*delta
 roll = angle.x
 pitch = angle.y
 velocity = Vector3(0,rate.x,rate.y)
 return Transform3D(Basis(Vector3.UP, heading)*Basis.from_euler(Vector3(roll,0,pitch)),Vector3(0,heave-0.6,0))

## Fixed-step pose at time from the start state. on_step(pose, t, dt) sees
## every intermediate tick (the reactive wave simulation replays the hull's
## recent history with it).
func pose_at(time: float, count: int, on_step: Callable = Callable()) -> Transform3D:
 heave=0.0
 roll=0.0
 pitch=0.0
 velocity=Vector3.ZERO
 initialized=false
 reset_navigation()
 var hz := float(Engine.physics_ticks_per_second)
 var pose := Transform3D(Basis(Vector3.UP, heading),Vector3(0,-0.6,0))
 for i in range(int(round(time*hz))):
  pose=step(float(i+1)/hz,1.0/hz,count)
  if on_step.is_valid(): on_step.call(pose,float(i+1)/hz,1.0/hz)
 return pose
