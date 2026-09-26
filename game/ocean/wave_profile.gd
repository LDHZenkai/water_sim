extends Resource
## (direction radians, amplitude metres, wavelength metres, horizontal steepness).
@export var waves := PackedVector4Array()

func displacement(q: Vector2, time: float, count: int) -> Dictionary:
 var p := Vector3(q.x, 0, q.y)
 var dx := Vector3.RIGHT
 var dz := Vector3.BACK
 for i in range(mini(count, waves.size())):
  var w := waves[i]
  var d := Vector2(cos(w.x), sin(w.x))
  var k := TAU / w.z
  var phase := k * d.dot(q) - sqrt(9.81 * k) * time
  var s := sin(phase)
  var c := cos(phase)
  var h := w.y * w.w
  p += Vector3(h * d.x * c, w.y * s, h * d.y * c)
  dx += Vector3(-h*k*d.x*d.x*s, w.y*k*d.x*c, -h*k*d.x*d.y*s)
  dz += Vector3(-h*k*d.x*d.y*s, w.y*k*d.y*c, -h*k*d.y*d.y*s)
 return {"position": p, "normal": dz.cross(dx).normalized()}

func surface(x: float, z: float, time: float, count: int = 5) -> Dictionary:
 var target := Vector2(x, z)
 var q := target
 # Contraction is < 0.1 for this profile; eight iterations are sub-mm.
 for iteration in range(8):
  var p: Vector3 = displacement(q, time, count).position
  q -= Vector2(p.x, p.z) - target
 return displacement(q, time, count)
