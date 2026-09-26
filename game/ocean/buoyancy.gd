extends RefCounted
const PROFILE = preload("res://ocean/default_waves.tres")
var heave := 0.0
var roll := 0.0
var pitch := 0.0
var velocity := Vector3.ZERO
var initialized := false
# Test scale changes the water surface itself, not a clamped output.
var wave_scale := 1.0

func target_at(time: float, count: int) -> Vector3:
 # Twelve probes within the measured 23 m waterline footprint.
 var average := 0.0
 var slope_x := 0.0
 var slope_z := 0.0
 for x in [-10.0, -6.0, -2.0, 2.0, 6.0, 10.0]:
  for z in [-3.0, 3.0]:
   var y: float = PROFILE.surface(x,z,time,count).position.y * wave_scale
   average += y / 12.0
   slope_x += x*y / 560.0
   slope_z += z*y / 108.0
 return Vector3(average, -atan(slope_z), atan(slope_x))

func step(time: float, delta: float, count: int) -> Transform3D:
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
 return Transform3D(Basis.from_euler(Vector3(roll,0,pitch)),Vector3(0,heave-0.6,0))

func pose_at(time: float, count: int) -> Transform3D:
 heave=0.0
 roll=0.0
 pitch=0.0
 velocity=Vector3.ZERO
 initialized=false
 var hz := float(Engine.physics_ticks_per_second)
 var pose := Transform3D(Basis.IDENTITY,Vector3(0,-0.6,0))
 for i in range(int(round(time*hz))):
  pose=step(float(i+1)/hz,1.0/hz,count)
 return pose
