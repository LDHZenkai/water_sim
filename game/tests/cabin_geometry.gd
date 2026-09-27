extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var world=load("res://scenes/main.tscn").instantiate()
 root.add_child(world)
 world.freeze_at(0)
 world.get_node("Player").input_enabled=false
 var raw:=StaticBody3D.new()
 raw.collision_layer=4
 var shape:=CollisionShape3D.new()
 shape.shape=world.hull_source_mesh.create_trimesh_shape()
 shape.shape.backface_collision=true
 raw.add_child(shape)
 root.add_child(raw)
 await physics_frame
 await physics_frame
 var bad:=0
 var space:=raw.get_world_3d().direct_space_state
 for p in world.cabin.shell_vertices:
  var outside:=false
  # The source skin is single-sided and non-manifold (no closed inner volume).
  # Define the lining envelope 15 mm inboard of the exterior source section;
  # cast from outside so internal beams are not mistaken for hull sides.
  for sign_value in [-1.0,1.0]:
   var q:=PhysicsRayQueryParameters3D.create(Vector3(p.x,p.y,sign_value*5),Vector3(p.x,p.y,0.095),4)
   q.hit_back_faces=true
   var hit: Dictionary=space.intersect_ray(q)
   if hit.is_empty() or (p.z-hit.position.z)*sign_value> -0.015:
    outside=true
    if bad<2:print("BOUND ",p," sign=",sign_value," hit=",hit.get("position","miss"))
  if outside:
   bad+=1
   if bad<12:printerr("OUTSIDE shell vertex: ",p)
 print("HULL TRIANGLES: source=",world.hull_source_mesh.get_faces().size()/3," retained/patch/doors before windows=",world.hull_partition.counts," after window clipping=",world.hull_partition.hull.get_faces().size()/3)
 print("CABIN containment: ",world.cabin.shell_vertices.size()," vertices; outside=",bad)
 # Stern windows must see open sea through the actual modified hull collision.
 shape.shape=world.hull_partition.hull.create_trimesh_shape()
 shape.shape.backface_collision=true
 await physics_frame
 var open_windows:=true
 for z in [-0.32,0.51]:
  var from: Vector3=Vector3(-11.8,7.7,z+0.15)
  var to: Vector3=Vector3(-15,7.7,z+0.15)
  var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,4))
  if not hit.is_empty():
   open_windows=false
   printerr("BLOCKED window: ",hit.position)
 print("CABIN stern-window sea rays: ",open_windows)
 var clearance:=INF
 var motion=preload("res://ocean/buoyancy.gd").new()
 var profile=preload("res://ocean/default_sea.tres")
 for tick in range(7200):
  var time:=float(tick+1)/60.0
  var pose: Transform3D=motion.step(time,1.0/60.0,32)
  if tick%6!=0:continue
  for x in [-12.12,-10.5,-8.94]:
   for z in [-0.7,0.1,0.9]:
    var floor_point: Vector3=pose*Vector3(x,world.cabin.FLOOR,z)
    var water: Vector3=profile.surface(floor_point.x,floor_point.z,time,32).position
    clearance=minf(clearance,(pose.affine_inverse()*floor_point).y-(pose.affine_inverse()*water).y)
 print("CABIN floor minimum water clearance (120 s, 32 waves): ",clearance," m")
 raw.free()
 world.free()
 quit(0 if bad==0 and open_windows and clearance>=0.9 else 1)
