extends SceneTree
# Reproducible, headless visibility audit. Physics BVH returns nearest triangles,
# including back faces, from every tour eye and the deck/perf approach views.
# Preserve all vertex channels; partition only the index buffer (no duplicate faces).
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 var ship=load("res://scenes/ship.tscn").instantiate()
 root.add_child(ship)
 ship.sync_to_physics=false
 var hull: MeshInstance3D
 for mesh in ship.get_node("Model").find_children("*","MeshInstance3D"):
  if "hull" in mesh.name: hull=mesh
 hull.mesh=hull.get_meta("source_mesh",hull.mesh)
 var body:=StaticBody3D.new()
 var shape:=CollisionShape3D.new()
 shape.shape=hull.mesh.create_trimesh_shape()
 (shape.shape as ConcavePolygonShape3D).backface_collision=true
 body.add_child(shape)
 root.add_child(body)
 body.global_transform=hull.global_transform
 await physics_frame
 await physics_frame
 var arrays:=hull.mesh.surface_get_arrays(0)
 var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
 var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
 var selected: Dictionary={}
 var views: Array=load("res://dev/tour.gd").SHOTS.duplicate(true)
 for i in range(5):
  views.append({"eye":load("res://dev/perf.gd").EYES[i],"target":load("res://dev/perf.gd").TARGETS[i],"fov":62.0})
 var space:=body.get_world_3d().direct_space_state
 for view in views:
  var camera:=Transform3D(Basis.IDENTITY,view.eye).looking_at(view.target,Vector3.UP)
  for y in range(180):
   for x in range(320):
    var ray_dir:=camera.basis*Vector3((float(x)+0.5-160.0)/90.0*tan(deg_to_rad(view.fov)*0.5),(90.0-float(y)-0.5)/90.0*tan(deg_to_rad(view.fov)*0.5),-1).normalized()
    var query:=PhysicsRayQueryParameters3D.create(view.eye,view.eye+ray_dir*300.0)
    query.hit_back_faces=true
    var hit:=space.intersect_ray(query)
    if hit.is_empty() or hit.collider!=body: continue
    var face:int=hit.face_index
    if face<0: continue
    var a:=hull.global_transform*vertices[indices[face*3]]
    var b:=hull.global_transform*vertices[indices[face*3+1]]
    var c:=hull.global_transform*vertices[indices[face*3+2]]
    # Godot front faces are clockwise: cross(b-a,c-a) points inward.
    if (b-a).cross(c-a).dot(ray_dir)<0.0: selected[face]=true
 var kept:=PackedInt32Array()
 var thin:=PackedInt32Array()
 for face in range(indices.size()/3):
  for j in range(3):
   if face in selected: thin.append(indices[face*3+j])
   else: kept.append(indices[face*3+j])
 DirAccess.make_dir_recursive_absolute("res://ocean/generated")
 var main:=ArrayMesh.new()
 arrays[Mesh.ARRAY_INDEX]=kept
 main.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 ResourceSaver.save(main,"res://ocean/generated/hull_back.res")
 if not thin.is_empty():
  var patch:=ArrayMesh.new()
  # Compact every vertex channel; six repair triangles must not upload the hull.
  for channel in range(Mesh.ARRAY_MAX):
   if channel==Mesh.ARRAY_INDEX or arrays[channel]==null: continue
   var original=arrays[channel]
   var compact=original.duplicate()
   compact.clear()
   var stride:int=original.size()/vertices.size()
   for index in thin:
    for component in range(stride): compact.append(original[index*stride+component])
   arrays[channel]=compact
  arrays[Mesh.ARRAY_INDEX]=null
  patch.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
  ResourceSaver.save(patch,"res://ocean/generated/hull_two_sided.res")
 var report={"total_triangles":indices.size()/3,"two_sided_triangles":selected.size(),"views":views.size(),"rays_per_view":320*180,"triangle_indices":selected.keys()}
 var file:=FileAccess.open("res://ocean/generated/hull_audit.json",FileAccess.WRITE)
 file.store_string(JSON.stringify(report,"\t"))
 print("HULL AUDIT: ",selected.size()," / ",indices.size()/3," triangles need two sides in ",views.size()," sampled views")
 ship.free()
 body.free()
 quit()
