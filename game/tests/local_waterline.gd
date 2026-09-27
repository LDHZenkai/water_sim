extends RefCounted
# Independent geometry oracle: local bottom from source vertices within 0.30 m;
# deck edge from upward triangles connected in height to the walking surface.
const SEA = preload("res://ocean/default_sea.tres")

static func samples(world: Node3D) -> Array[Dictionary]:
 var faces: PackedVector3Array = world.hull_source_mesh.get_faces()
 var hull: MeshInstance3D
 for node in world.ship_body.get_node("Model").find_children("*", "MeshInstance3D"):
  if "hull" in node.name: hull = node
 var xf: Transform3D = world.ship_body.global_transform.affine_inverse()*hull.global_transform
 for i in range(faces.size()): faces[i] = xf*faces[i]
 var result: Array[Dictionary] = []
 var outline: Image = world.ocean.hull_image
 var row := int(round(2.6/5.0*63.0))
 for col in range(0,192,4):
  var bounds := outline.get_pixel(col,row)
  if bounds.r >= bounds.g: continue
  var x := -14.0+float(col)/191.0*35.0
  var bottom := INF
  # Vertex neighbourhood excludes a long sloping keel triangle's remote heel.
  for vertex in faces:
   if absf(vertex.x-x)<=0.30: bottom=minf(bottom,vertex.y)
  # Padding in the render mask is not part of the design-waterline footprint.
  if bottom>=0.6: continue
  var decks := [-INF, -INF]
  for i in range(0,faces.size(),3):
   var a := faces[i]
   var b := faces[i+1]
   var c := faces[i+2]
   if x < minf(a.x,minf(b.x,c.x)) or x > maxf(a.x,maxf(b.x,c.x)): continue
   var normal := (c-a).cross(b-a).normalized()
   if normal.y < 0.8: continue
   for side in range(2):
    var z: float=(bounds.r if side==0 else bounds.g)*0.5
    var hit=Geometry3D.ray_intersects_triangle(Vector3(x,35,z),Vector3.DOWN,a,b,c)
    if hit!=null: decks[side]=maxf(decks[side],hit.y)
  # Trace that walking surface outward to its edge, taking its lowest height.
  var edge_decks := decks.duplicate()
  for i in range(0,faces.size(),3):
   var a := faces[i]
   var b := faces[i+1]
   var c := faces[i+2]
   if x < minf(a.x,minf(b.x,c.x)) or x > maxf(a.x,maxf(b.x,c.x)): continue
   if (c-a).cross(b-a).normalized().y<0.8: continue
   for edge in [[a,b],[b,c],[c,a]]:
    var p: Vector3=edge[0]
    var q: Vector3=edge[1]
    if absf(p.x-q.x)<0.000001 or x<minf(p.x,q.x) or x>maxf(p.x,q.x): continue
    var hit := p.lerp(q,(x-p.x)/(q.x-p.x))
    for side in range(2):
     if (hit.z<bounds.r*0.5 if side==0 else hit.z>bounds.g*0.5) and absf(hit.y-decks[side])<0.25:
      edge_decks[side]=minf(edge_decks[side],hit.y)
  decks=edge_decks
  for side in range(2):
   result.append({"point":Vector3(x,0.6,bounds.r if side==0 else bounds.g),"bottom":bottom,"deck":decks[side]})
 return result

static func run(world: Node3D, check: Callable, flood_control: bool = false) -> void:
 var perimeter := samples(world)
 var valid := perimeter.size()>50
 for sample in perimeter: valid = valid and is_finite(sample.bottom) and is_finite(sample.deck)
 check.call(valid,"local deck and bottom geometry found at every perimeter sample")
 if not valid:
  for s in perimeter:
   if not is_finite(s.deck): print("MISSING DECK ",s)
  return
 var cap: PackedVector3Array = world.ocean.bilge.mesh.get_faces()
 check.call(cap.size()>0,"occluder cap has geometry")
 var cap_height := cap[0].y
 var floor_clear := INF
 for sample in perimeter: floor_clear=minf(floor_clear,sample.deck-cap_height)
 check.call(floor_clear>=0.30,"bilge cap remains >=0.30 m below local walking decks")
 # Sample the actual cap vertices and triangle centroids, including both ends.
 var cap_points: Array[Vector3] = []
 for i in range(0,cap.size(),24):
  cap_points.append(cap[i])
  cap_points.append(cap[i+2])
  cap_points.append((cap[i]+cap[i+1]+cap[i+2])/3.0)
 for count in [24,32]:
  var motion = preload("res://ocean/buoyancy.gd").new()
  var deck_clear := INF
  var wet := INF
  var cap_clear := INF
  var wet_point := Vector3.ZERO
  var max_pitch := 0.0
  var max_roll := 0.0
  var pitch_windows := [0.0,0.0,0.0,0.0]
  var roll_windows := [0.0,0.0,0.0,0.0]
  var final_pose := Transform3D.IDENTITY
  for i in range(7200):
   var t := float(i+1)/60.0
   var pose: Transform3D=motion.step(t,1.0/60.0,count)
   # Negative control sinks the hull by 2 m without altering the thresholds.
   if flood_control: pose.origin.y-=2.0
   final_pose=pose
   max_pitch=maxf(max_pitch,absf(rad_to_deg(motion.pitch)))
   # Waves' roll about the steady heel the sails put on the hull.
   max_roll=maxf(max_roll,absf(rad_to_deg(motion.roll-motion.heel)))
   pitch_windows[i/1800]=maxf(pitch_windows[i/1800],absf(rad_to_deg(motion.pitch)))
   roll_windows[i/1800]=maxf(roll_windows[i/1800],absf(rad_to_deg(motion.roll-motion.heel)))
   if i%6!=0: continue
   var probes := PackedVector2Array()
   var placed: Array[Vector3] = []
   for sample in perimeter:
    placed.append(pose*sample.point)
   for point in cap_points:
    placed.append(pose*point)
   for p in placed: probes.append(Vector2(p.x,p.z))
   var heights: PackedFloat64Array=SEA.heights(probes,t,count,motion.drift)
   for j in range(perimeter.size()):
    var sample: Dictionary=perimeter[j]
    var p: Vector3=placed[j]
    var water: Vector3=pose.affine_inverse()*Vector3(p.x,heights[j],p.z)
    deck_clear=minf(deck_clear,sample.deck-water.y)
    if water.y-sample.bottom<wet:
     wet=water.y-sample.bottom
     wet_point=sample.point
   for j in range(cap_points.size()):
    var p: Vector3=placed[perimeter.size()+j]
    var water: Vector3=pose.affine_inverse()*Vector3(p.x,heights[perimeter.size()+j],p.z)
    cap_clear=minf(cap_clear,cap_points[j].y-water.y)
  print("LOCAL ",count," waves: samples=",perimeter.size()," deck clearance=",deck_clear," m; wet depth=",wet," m at ",wet_point,"; cap clearance=",cap_clear," m")
  print("MOTION ",count," waves: pitch=",max_pitch," roll about heel=",max_roll," heel=",rad_to_deg(motion.heel),"; pitch windows=",pitch_windows,"; roll windows=",roll_windows)
  check.call(deck_clear>=0.30,"local deck clearance >=0.30 m, tier "+str(count))
  check.call(wet>=0.40,"local bottom submergence >=0.40 m including bow/stern, tier "+str(count))
  check.call(cap_clear>=0.10,"ocean below actual bilge cap by >=0.10 m, tier "+str(count))
  check.call(max_pitch>=0.5 and max_pitch<=4.0 and max_roll>=0.75 and max_roll<=3.0,"physical pitch 0.5..4 and roll 0.75..3 degrees, tier "+str(count))
  # A random sea's 30 s peaks scatter by ~10% window to window; a diverging
  # (under-damped) hull would grow far faster than 12% over 90 s.
  check.call(pitch_windows[3]<=maxf(pitch_windows[0],pitch_windows[1])*1.12+0.15 and roll_windows[3]<=maxf(roll_windows[0],roll_windows[1])*1.12+0.15,"pitch and roll do not grow over 120 s, tier "+str(count))
  if not flood_control:
   check.call(final_pose.is_equal_approx(motion.pose_at(120.0,count)),"frozen capture pose equals fixed-step simulation, tier "+str(count))
