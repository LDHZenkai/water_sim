extends SceneTree
var good:=true
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
 good=good and ok
 print("PASS: " if ok else "FAIL: ",label)
func run() -> void:
 var world=load("res://scenes/main.tscn").instantiate()
 root.add_child(world)
 var cabin: Node3D=world.cabin
 var targets: Dictionary=preload("res://exploration/cabin_bake.gd").targets(cabin)
 # Glass, flames, chart, metal/glass utensils and small PBR props intentionally
 # use their own materials; every opaque structural/furniture surface is baked.
 for mesh in cabin.find_children("*","MeshInstance3D",true,false):
  var structural: bool=mesh in cabin.shell
  var expected:=structural
  for prop in cabin.props:
   if prop.name in preload("res://exploration/cabin_bake.gd").FURNITURE and prop.is_ancestor_of(mesh):expected=true
  for s in range(mesh.mesh.get_surface_count()):
   var mat: Material=mesh.get_active_material(s)
   var texture: Texture2D
   if mat is BaseMaterial3D:
    texture=mat.albedo_texture
    if mat.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED:expected=false
   elif mat is ShaderMaterial:texture=mat.get_shader_parameter("albedo_map")
   print("CABIN MESH ",mesh.get_path()," surface=",s," material=",mat," albedo=",texture," target=",mesh in targets.values()," baked=",mesh.get_meta("cabin_baked",false)," required=",expected)
   if expected:
    check(texture!=null and ("planks_diff" in texture.resource_path if structural else "_diff" in texture.resource_path),"structural/prop wood albedo "+str(mesh.get_path()))
    check(mesh in targets.values() and mesh.get_meta("cabin_baked",false),"structural/prop wood enters bake "+str(mesh.get_path()))
 world.free()
 print("CABIN WOOD AUDIT: ","PASS" if good else "FAIL")
 quit(0 if good else 1)
