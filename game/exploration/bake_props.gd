extends SceneTree
# Offline Godot meshoptimizer LOD generation, promoted to the actual base mesh.
const IDS = ["round_wooden_table_01","seadogs_compass","wooden_candlestick","brass_candleholders","treasure_chest","GothicCabinet_01","WoodenChair_01","wooden_stool_01","wine_bottles_01","jug_01","vintage_oil_lamp","wooden_handle_saber","cannon_01","wooden_barrels_01","wooden_crate_01","wooden_bucket_01","wooden_lantern_01"]
func _initialize() -> void:call_deferred("bake")
func bake() -> void:
 var report := []
 for id in IDS:
  var directory: String="res://assets/polyhaven/models/"+id
  var path := ""
  for file in DirAccess.get_files_at(directory):
   if file.ends_with(".gltf"):path=directory+"/"+file
  var model: Node3D=load(path).instantiate()
  root.add_child(model)
  var bounds := AABB()
  var first := true
  for node in model.find_children("*","MeshInstance3D"):
   var b: AABB=node.global_transform*node.get_aabb()
   bounds=b if first else bounds.merge(b)
   first=false
  print("NATIVE SIZE ",id," ",bounds)
  var meshes := model.find_children("*","MeshInstance3D")
  var total := 0
  for node in meshes:total+=node.mesh.get_faces().size()/3
  var budget := 14000 if id not in ["treasure_chest","GothicCabinet_01","round_wooden_table_01","WoodenChair_01","cannon_01","wooden_barrels_01","wooden_crate_01"] else 28000
  if id=="wooden_candlestick":budget=4800
  var baked_total := 0
  for node in meshes:
   var source: Mesh=node.mesh
   var reduced := ArrayMesh.new()
   for s in range(source.get_surface_count()):
    var arrays:=source.surface_get_arrays(s)
    var original: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
    var allowance:=maxi(12,int(float(original.size()/3)/total*budget))
    # Preserve the two large chest panels; reduce the small repeated fittings
    # further so the later irradiance subdivision still fits 30,000 triangles.
    if id=="treasure_chest" and original.size()/3<5000:allowance=maxi(12,allowance/4)
    if original.size()/3>allowance:
     var importer:=ImporterMesh.new()
     importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,arrays)
     importer.generate_lods(60,60,[])
     var chosen:=original
     for lod in range(importer.get_surface_lod_count(0)):
      var candidate:=importer.get_surface_lod_indices(0,lod)
      chosen=candidate
      if candidate.size()/3<=allowance:break
     arrays[Mesh.ARRAY_INDEX]=chosen
    baked_total+=arrays[Mesh.ARRAY_INDEX].size()/3
    reduced.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
    var mat: Material=source.surface_get_material(s)
    if mat is StandardMaterial3D:
     mat=mat.duplicate()
     # Open jug/cabinet/back panels retain source sidedness.
     if id not in ["jug_01","GothicCabinet_01"]:mat.cull_mode=BaseMaterial3D.CULL_BACK
     mat.refraction_enabled=false
     if id=="round_wooden_table_01":
      mat.roughness_texture=null
      mat.roughness=0.55
      mat.albedo_color=Color(0.72,0.66,0.59)
     if id=="jug_01":mat.albedo_color=Color(0.6,0.56,0.49)
    reduced.surface_set_material(s,mat)
   var compact:=ArrayMesh.new()
   for s in range(reduced.get_surface_count()):
    var surface:=SurfaceTool.new()
    surface.create_from(reduced,s)
    surface.deindex()
    surface.index()
    surface.commit(compact)
    compact.surface_set_material(s,reduced.surface_get_material(s))
   node.mesh=compact
  if baked_total>budget:
   push_error("LOD reduction did not reach budget: "+id+" "+str(baked_total))
   quit(1)
   return
  var packed:=PackedScene.new()
  packed.pack(model)
  assert(ResourceSaver.save(packed,"res://exploration/generated/"+id+".scn")==OK)
  report.append({"id":id,"source_triangles":total,"base_triangles":baked_total,"budget":budget,"baked_ceiling":30000 if id=="treasure_chest" else budget})
  model.free()
 var file:=FileAccess.open("res://exploration/generated/prop_budgets.json",FileAccess.WRITE)
 file.store_string(JSON.stringify(report,"  "))
 print("BAKED PROPS: ",JSON.stringify(report))
 quit()
