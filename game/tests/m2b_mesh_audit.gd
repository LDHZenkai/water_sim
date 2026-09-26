extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var world=load("res://scenes/main.tscn").instantiate()
 root.add_child(world)
 var targets: Dictionary=preload("res://exploration/cabin_bake.gd").targets(world.cabin)
 for mesh in world.ship_body.find_children("*","MeshInstance3D",true,false):
  if not world.cabin.is_ancestor_of(mesh) and not world.ship_body.get_node("Model").is_ancestor_of(mesh):continue
  var pose: Transform3D=world.ship_body.global_transform.affine_inverse()*mesh.global_transform
  print("MESH ",mesh.get_path()," bounds=",pose*mesh.get_aabb()," triangles=",mesh.mesh.get_faces().size()/3," bake=",mesh in targets.values()," baked=",mesh.get_meta("cabin_baked",false))
  for s in range(mesh.mesh.get_surface_count()):
   var mat: Material=mesh.get_active_material(s)
   print(" MATERIAL ",mat)
   if mat is BaseMaterial3D:print(" ALBEDO ",mat.albedo_texture," cull=",mat.cull_mode," alpha=",mat.transparency)
   if mat is ShaderMaterial:
    for key in ["albedo_map","albedo_texture"]:print(" ",key,"=",mat.get_shader_parameter(key))
 var fresh: Dictionary=preload("res://exploration/hull_split.gd").build(world.hull_source_mesh)
 print("PARTITION cached/fresh hull=",world.hull_partition.hull.get_faces().size(),"/",fresh.hull.get_faces().size()," patch=",world.hull_partition.patch.get_faces().size(),"/",fresh.patch.get_faces().size())
 world.free()
 quit()
