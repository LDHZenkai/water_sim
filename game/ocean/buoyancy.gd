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
##          - D(u) u^2 (wave making) - LINEAR_DRAG * u (skin friction).
## Calibrated so a beam reach in 8 m/s wind makes ~6 knots, the hull takes
## ~30 s to gather way (a few hundred tonnes of galleon) and, furled, loses
## it again over a couple of minutes.
const THRUST := 0.0024
const DRAG := 0.004
const LINEAR_DRAG := 0.01
## Wave-making resistance climbs steeply toward hull speed (1.34 sqrt(LWL ft)
## knots: ~13 kn for a 30 m waterline), so a gale cannot drive her much past
## 11 knots. Only surfing down a sea carries her beyond it.
const HULL_SPEED := 6.8
## Yaw: r' = RUDDER_GAIN u^2 sin(d) - YAW_DAMPING u r - YAW_DRAG r|r|.
## Full rudder at 6 knots turns about 2.3 deg/s (a ~150 m circle, 4 hull
## lengths) and settles into the turn over ~6 s. A hard turn bleeds speed.
const RUDDER_GAIN := 0.00133
const YAW_DAMPING := 0.054
const YAW_DRAG := 0.3
const TURN_DRAG := 150.0
## Heel from the sails' side force per (m/s)^2 of apparent wind at full
## canvas: ~2 deg in a fresh 8 m/s breeze, ~11 deg in a gale (reef!).
const HEEL_GAIN := 0.00049
## Degrees of heel beyond which the rig is overpressed.
const OVERPRESSED := deg_to_rad(12.0)
## Surf-riding: gravity along the hull-averaged wave slope drives the hull
## only once it moves at a good fraction of the celerity of hull-length waves
## (~7.4 m/s) in a following sea; slower, the water just orbits under it.
const HULL_WAVE_CELERITY := 7.4
const SURF_GAIN := 0.8
## Broaching: surfing down a face at an angle swings the hull broadside.
const BROACH_GAIN := 0.025

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
## Wind on the rig in world XZ (blowing toward); weather.gd sets it every
## tick, gusts included. Defaults to the sea state's wind.
var wind_vector := Vector2.ZERO
## Heel from the sails (rad, + to starboard), and the wave forces on the hull.
var heel := 0.0
var surf := 0.0
var broach := 0.0
## Long-wave count used for the surf/broach wave direction.
var wave_count := 32

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
 wind_vector = SEA.wind()
 speed = steady_speed(canvas, heading) if start_speed < 0.0 else start_speed
 drift = Vector2.ZERO
 drift_previous = Vector2.ZERO
 heel = heel_target(canvas, forward(), speed)
 surf = 0.0
 broach = 0.0

## Bow direction in world XZ.
func forward() -> Vector2:
 return Vector2(cos(heading), -sin(heading))

## Water velocity past the ship in world XZ (the ship's velocity reversed).
func water_velocity() -> Vector2:
 return -forward() * speed

func knots() -> float:
 return speed / 0.514444

## True wind on the rig in world XZ (blowing toward).
func wind() -> Vector2:
 return wind_vector

## Sails' side force as heel: most with the wind forward of the beam, none
## dead downwind or with the sails luffing. + heels to starboard.
func heel_target(amount: float, direction: Vector2, u: float) -> float:
 var apparent: Vector2 = wind() - direction * u
 var angle := apparent_wind_angle(direction, u)
 var side := sin(angle) * smoothstep(deg_to_rad(20.0), deg_to_rad(60.0), angle)
 # Starboard in world XZ is (-dir.y, dir.x); wind blowing that way heels +.
 var lateral := signf(apparent.dot(Vector2(-direction.y, direction.x)))
 return HEEL_GAIN * amount * apparent.length_squared() * side * lateral

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

## Quadratic (wave-making) drag coefficient at speed u.
static func wave_drag(u: float) -> float:
 return DRAG * (1.0 + pow(u / HULL_SPEED, 4.0))

func steady_speed(amount: float, yaw: float) -> float:
 var direction := Vector2(cos(yaw), -sin(yaw))
 var u := 2.0
 for i in range(60):
  # Positive root of D(u) u^2 + LINEAR_DRAG u = thrust.
  var t := maxf(thrust(amount, direction, u), 0.0)
  var d := wave_drag(u)
  u = lerpf(u, (-LINEAR_DRAG + sqrt(LINEAR_DRAG * LINEAR_DRAG + 4.0 * d * t)) / (2.0 * d), 0.5)
 return u

func overpressed() -> bool:
 return absf(heel) > OVERPRESSED

func _navigate(delta: float) -> void:
 canvas = move_toward(canvas, SAIL_CANVAS[clampi(sail, 0, SAIL_CANVAS.size() - 1)], SAIL_RATE * delta)
 # A helm left alone drifts back amidships.
 rudder = move_toward(rudder, clampf(rudder_input, -1.0, 1.0) * MAX_RUDDER, RUDDER_RATE * delta)
 var direction := forward()
 var drag := (wave_drag(speed) * speed * absf(speed) + LINEAR_DRAG * speed) * (1.0 + TURN_DRAG * yaw_rate * yaw_rate)
 speed = maxf(speed + (thrust(canvas, direction, speed) - drag + surf) * delta, 0.0)
 # Rudder force grows with flow past it: no steerage without way on.
 var yaw_acceleration := RUDDER_GAIN * speed * speed * sin(rudder) - YAW_DAMPING * (speed + 0.3) * yaw_rate - YAW_DRAG * yaw_rate * absf(yaw_rate) + broach
 yaw_rate += yaw_acceleration * delta
 heading = wrapf(heading + yaw_rate * delta, -PI, PI)
 drift_previous = drift
 drift += water_velocity() * delta
 # The hull answers the sails' heeling moment over a few seconds.
 heel = lerpf(heel, heel_target(canvas, forward(), speed), 1.0 - exp(-delta / 3.0))

## A breaking crest the linear sea cannot carry (weather.gd rogue waves).
## Beam-on it throws the hull over; from astern it slews her round and
## sweeps the deck; bow-on she climbs it and loses way. side = +1 when the
## sea came from port.
func strike(how: String, side: float) -> void:
 match how:
  "beam":
   velocity.y += 0.32 * side
   speed *= 0.6
  "stern":
   yaw_rate += 0.06 * side
   velocity.y += 0.12 * side
   speed *= 0.8
  _:
   velocity.z += 0.1
   speed *= 0.5

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

## Surf-riding and broaching from the hull-averaged wave slope (pitch target,
## + bow up) and the dominant wave direction; used on the next tick.
func _wave_forces(time: float, count: int, pitch_target: float) -> void:
 var dominant: Dictionary = SEA.dominant_wave(time, count)
 var travel: Vector2 = dominant.direction
 var following := forward().dot(travel)
 var riding := smoothstep(0.3, 0.7, speed / HULL_WAVE_CELERITY) * smoothstep(0.2, 0.6, following)
 surf = -9.81 * sin(pitch_target) * SURF_GAIN * riding
 var angle := travel.angle_to(forward())
 broach = BROACH_GAIN * maxf(surf, 0.0) * sin(2.0 * angle)

func step(time: float, delta: float, count: int) -> Transform3D:
 _navigate(delta)
 var target := target_at(time,count)
 _wave_forces(time, count, target.z)
 # Kinematic heave; physical angular restoring torque and absolute damping.
 # No angular target velocity or acceleration feed-forward.
 if not initialized:
  initialized = true
 heave = target.x
 # Short pitch response follows the long swell; roll remains the slow mode.
 var omega := Vector2(TAU/14.0, TAU/2.5)
 var angle := Vector2(roll, pitch)
 var rate := Vector2(velocity.y, velocity.z)
 var acceleration := omega*omega*(Vector2(target.y+heel,target.z)-angle) - 2.0*Vector2(0.35,0.4)*omega*rate
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
