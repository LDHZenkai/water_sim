extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
 root.get_node("Quality").overrides["cabin-bake"]="off"
 var world=load("res://scenes/main.tscn").instantiate()
 root.add_child(world)
 world.set_process(false)
 world.cabin.set_process(false)
 var viewport:=SubViewport.new()
 viewport.world_3d=World3D.new()
 root.add_child(viewport)
 var cabin: Node3D=world.cabin
 # Dedicated static, ship-local physics world: excludes walking ramps and hull
 # collision proxies, includes the actual shell and every opaque prop triangle.
 for node in cabin.find_children("*","MeshInstance3D",true,false):
  var material: Material=node.get_active_material(0)
  if material is ShaderMaterial:continue
  if material is BaseMaterial3D and material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED:continue
  var body:=StaticBody3D.new()
  var shape:=CollisionShape3D.new()
  shape.shape=node.mesh.create_trimesh_shape()
  body.add_child(shape)
  viewport.add_child(body)
  body.transform=cabin.global_transform.affine_inverse()*node.global_transform
 await physics_frame
 await physics_frame
 var baker:=preload("res://exploration/cabin_bake.gd").new()
 baker.sun_direction=world.sun_direction()
 baker.space=viewport.find_world_3d().direct_space_state
 var img:=Image.create(1,1,false,Image.FORMAT_RGB8)
 img.fill(Color.WHITE)
 baker.white=ImageTexture.create_from_image(img)
 DirAccess.make_dir_recursive_absolute(baker.DIRECTORY)
 var report: Dictionary={}
 for key in baker.targets(cabin):
  var node: MeshInstance3D=baker.targets(cabin)[key]
  var baked:=baker.bake_mesh(node,cabin.global_transform.affine_inverse()*node.global_transform,key.begins_with("shell_"))
  if ResourceSaver.save(baked,baker.DIRECTORY+key+".res")!=OK:
   push_error("Cannot save cabin bake")
   quit(1)
   return
  report[key]=baked.get_faces().size()/3
  print("BAKE: ",key," triangles=",report[key])
 # Retire only obsolete files from this generated bake directory after success.
 for filename in DirAccess.get_files_at(baker.DIRECTORY):
  if filename.ends_with(".res") and not report.has(filename.trim_suffix(".res")):
   DirAccess.remove_absolute(baker.DIRECTORY+filename)
 var budget_path:="res://exploration/generated/prop_budgets.json"
 var budgets: Array=JSON.parse_string(FileAccess.get_file_as_string(budget_path))
 for row in budgets:
  var triangles:=0
  for key in report:
   if str(key).begins_with(str(row.id)+"_"):triangles+=int(report[key])
  if triangles>0:row["baked_triangles"]=triangles
 FileAccess.open(budget_path,FileAccess.WRITE).store_string(JSON.stringify(budgets,"  "))
 report["source_sha256"]=cabin.get_meta("bake_inputs")
 var file:=FileAccess.open(baker.DIRECTORY+"manifest.json",FileAccess.WRITE)
 file.store_string(JSON.stringify(report,"  "))
 world.free()
 viewport.free()
 print("CABIN BAKE: PASS (offline ray-occluded vertex irradiance)")
 quit()
