extends SceneTree
var good:=true
func check(value: bool,label: String) -> void:
 good=good and value
 print("PASS: " if value else "FAIL: ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var world=load("res://scenes/main.tscn").instantiate()
 root.add_child(world)
 var cabin: Node3D=world.cabin
 if OS.get_cmdline_user_args().has("--inject-stale-geometry"):
  assert(cabin.settings["cabin-bake"]=="off")
  cabin.shell[0].position.x+=0.01
  cabin.set_meta("bake_inputs",preload("res://exploration/cabin_bake.gd").fingerprint(cabin))
 var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://exploration/generated/cabin_light/manifest.json"))
 check(manifest.get("source_sha256","")==cabin.get_meta("bake_inputs"),"bake geometry/light input SHA256 is current")
 var enabled: bool=cabin.settings["cabin-bake"]=="on"
 if not enabled:
  check(manifest.get("source_sha256","")==preload("res://exploration/cabin_bake.gd").fingerprint(cabin),"live source signature agrees after runtime-only flame assembly")
 var count:=0
 var window_near:=0.0
 var window_far:=0.0
 var near_count:=0
 var far_count:=0
 var candle_peak:=0.0
 var candle_far:=0.0
 var table_far_count:=0
 for key in preload("res://exploration/cabin_bake.gd").targets(cabin):
  var node: MeshInstance3D=preload("res://exploration/cabin_bake.gd").targets(cabin)[key]
  check(node.get_meta("cabin_baked",false)==enabled,"bake selection "+key)
  if not enabled:continue
  var pose:=cabin.global_transform.affine_inverse()*node.global_transform
  check(node.layers==4,"baked surface excluded from runtime candle "+key)
  for s in range(node.mesh.get_surface_count()):
   var material: ShaderMaterial=node.get_active_material(s)
   var cull_modes: PackedInt32Array=node.mesh.get_meta("source_cull_modes")
   check(["cull_back","cull_front","cull_disabled"][cull_modes[s]] in material.shader.code,"preserved material sidedness "+key)
   check("unshaded" in material.shader.code,"baked shader bypasses runtime lighting "+key)
   check(material.get_shader_parameter("candle_on")==(cabin.settings["cabin-lights"]=="on"),"light override "+key)
   var arrays:=node.mesh.surface_get_arrays(s)
   var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
   var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
   var directional: PackedFloat32Array=arrays[Mesh.ARRAY_CUSTOM0]
   check(directional.size()==vertices.size()*4,"stored dominant direction and reference response "+key)
   check(not arrays[Mesh.ARRAY_TANGENT].is_empty(),"normal-map tangent basis "+key)
   check(material.get_shader_parameter("has_normal") and material.get_shader_parameter("normal_map")!=null,"normal texture preserved "+key)
   check(colors.size()==vertices.size(),"stored per-vertex irradiance "+key)
   for i in range(vertices.size()):
    if directional.size()==vertices.size()*4:
     var direction:=Vector3(directional[i*4],directional[i*4+1],directional[i*4+2])
     good=good and direction.is_finite() and absf(direction.length()-1.0)<0.01
    var p: Vector3=pose*vertices[i]
    var color:=colors[i]
    count+=1
    if key.begins_with("shell_") and p.y>7.2 and p.y<7.95 and (p.z< -0.6 or p.z>0.8):
     if p.x< -11.6:
      window_near+=color.r
      near_count+=1
     elif p.x> -9.8:
      window_far+=color.r
      far_count+=1
    if key.begins_with("round_wooden_table") and absf(p.y-7.13)<0.02:
     if Vector2(p.x+10.85,p.z-0.55).length()<0.25:candle_peak=maxf(candle_peak,color.g)
     elif Vector2(p.x+10.85,p.z-0.55).length()>0.65:
      candle_far+=color.g
      table_far_count+=1
 if enabled:
  window_near/=maxi(1,near_count)
  window_far/=maxi(1,far_count)
  candle_far/=maxi(1,table_far_count)
  print("BAKE DATA: vertices=",count," window near/far=",window_near,"/",window_far," candle peak/far=",candle_peak,"/",candle_far)
  check(near_count>0 and far_count>0 and window_near>window_far+0.01 and window_near>0.18,"shell golden window gradient is non-trivial")
  check(candle_peak>candle_far+0.15,"table has a localized candle pool")
  check(window_near*(1.0-0.40)>window_far*(1.0-0.40),"window-facing region is warmer (red minus blue)")
 check(cabin.lamps.size()==(1 if enabled else 2),"one baked runtime lamp / original fallback lamps")
 for lamp in cabin.lamps:
  check(not lamp.shadow_enabled and lamp.light_cull_mask==2,"shadowless prop-only light mask")
  if enabled:check(lamp is OmniLight3D and lamp.omni_range<=2.5,"bounded candle radius")
 for entry in cabin.small_materials:
  var material: BaseMaterial3D=entry[1]
  for texture in [material.albedo_texture,material.normal_texture]:
   if texture:check(maxi(texture.get_width(),texture.get_height())<=512,"small prop 512px texture LOD "+texture.resource_path)
 cabin.update_prop_lod(Vector3(100,100,100))
 for entry in cabin.small_materials:check(entry[1].normal_enabled and entry[1].normal_scale==0.0,"distant small prop normal disabled")
 for entry in cabin.small_materials:
  cabin.update_prop_lod(entry[0].global_position)
  check(entry[1].normal_enabled and entry[1].normal_scale==1.0,"near small prop normal restored")
 world.free()
 print("CABIN BAKE TEST: ","PASS" if good else "FAIL")
 quit(0 if good else 1)
