extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var world=load("res://scenes/main.tscn").instantiate()
 root.add_child(world)
 for node in world.find_children("*","MeshInstance3D",true,false):
  if "Prewarm" in str(node.get_path()):continue
  var pose: Transform3D=world.ship_body.global_transform.affine_inverse()*node.global_transform
  var count:=0
  for p in node.mesh.get_faces():
   if AABB(Vector3(-12.2,6.35,-1.1),Vector3(3,2.5,2.4)).has_point(pose*p):count+=1
  if count==0 and not world.cabin.is_ancestor_of(node):continue
  for s in range(node.mesh.get_surface_count()):
   var mat: Material=node.get_active_material(s)
   var tex: Texture2D
   if mat is BaseMaterial3D:tex=mat.albedo_texture
   if mat is ShaderMaterial:
    tex=mat.get_shader_parameter("albedo_map") if "albedo_map" in mat.shader.code else mat.get_shader_parameter("albedo_texture")
   print("AUDIT ",node.get_path()," cabin_vertices=",count," material=",mat," albedo=",tex.resource_path if tex else "NONE"," baked=",node.get_meta("cabin_baked",false))
 for node in world.ship_body.get_node("Model").find_children("*","MeshInstance3D"):
  print("SHIP ",node.name," triangles=",node.mesh.get_faces().size()/3," mat=",node.get_active_material(0))
 world.free()
 quit()
