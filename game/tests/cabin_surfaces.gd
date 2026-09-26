extends SceneTree
var good:=true
func check(ok: bool,label: String) -> void:
 good=good and ok
 print("PASS: " if ok else "FAIL: ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var world=load("res://scenes/main.tscn").instantiate()
 root.add_child(world)
 var cabin=world.cabin
 var stray:=0
 # Check render geometry outside the Cabin subtree too. The previous test only
 # tested the replacement knees and missed the still-rendered source hull.
 for key in ["hull","patch"]:
  var points: PackedVector3Array=world.hull_partition[key].get_faces()
  for i in range(0,points.size(),3):
   var p: Vector3=(points[i]+points[i+1]+points[i+2])/3
   if p.x>=cabin.FRONT-0.01 or p.x<=cabin.BACK+0.01 or p.y<=cabin.FLOOR+0.03:continue
   var limits: Vector2=cabin.side_limits(p.x)
   if p.z<=limits.x+0.01 or p.z>=limits.y-0.01:continue
   if p.y<cabin.roof_height(p.x,p.z)-0.01:stray+=1
 check(stray==0,"no unbaked source hull faces inside cabin lining; count="+str(stray))
 for mesh in cabin.shell:
  var mat: Material=mesh.get_active_material(0)
  if mat is BaseMaterial3D and mat.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED:continue # window glass
  var tex: Texture2D=mat.get_shader_parameter("albedo_map") if mat is ShaderMaterial else mat.albedo_texture
  check(tex!=null and tex.resource_path.ends_with("planks_diff.jpg"),"structural wood albedo "+str(mesh.name))
  check(mesh.get_meta("cabin_baked",false)==(cabin.settings["cabin-bake"]=="on"),"structural bake "+str(mesh.name))
 for prop in cabin.props:
  if str(prop.name) not in preload("res://exploration/cabin_bake.gd").FURNITURE:continue
  for mesh in prop.find_children("*","MeshInstance3D",true,false):
   var mat: Material=mesh.get_active_material(0)
   var tex: Texture2D=mat.get_shader_parameter("albedo_map") if mat is ShaderMaterial else mat.albedo_texture
   check(tex!=null,"prop wood albedo "+str(prop.name))
   check(mesh.get_meta("cabin_baked",false)==(cabin.settings["cabin-bake"]=="on"),"prop bake "+str(prop.name))
 world.free()
 print("CABIN SURFACES: ","PASS" if good else "FAIL")
 quit(0 if good else 1)
