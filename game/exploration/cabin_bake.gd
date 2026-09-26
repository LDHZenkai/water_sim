extends RefCounted
## Offline-only mesh baker. Runtime only loads the saved resources.
const DIRECTORY := "res://exploration/generated/cabin_light/"
const FURNITURE := ["round_wooden_table_01", "GothicCabinet_01", "treasure_chest", "wooden_stool_01"]
const CANDLES := [Vector3(-10.85,7.39,0.55), Vector3(-11.1,7.63,0.24)]
var sun_direction := Vector3(-1,0.35,0.22).normalized()
var space: PhysicsDirectSpaceState3D
var cache := {}
var white: Texture2D
var shaders: Dictionary={}

static func targets(cabin: Node3D) -> Dictionary:
 var result := {}
 for i in range(cabin.shell.size()):
  var mesh: MeshInstance3D=cabin.shell[i]
  var mat:=mesh.get_active_material(0)
  if mesh.get_meta("cabin_baked",false) or (mat is BaseMaterial3D and mat.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED):
   result["shell_"+str(i)]=mesh
 for prop in cabin.props:
  if str(prop.name) not in FURNITURE:continue
  var meshes: Array=prop.find_children("*","MeshInstance3D",true,false)
  for i in range(meshes.size()):result[str(prop.name)+"_"+str(i)]=meshes[i]
 return result

static func apply(cabin: Node3D) -> void:
 assert(not cabin.is_inside_tree(), "Bake assignment must precede render pairing")
 var meshes:=targets(cabin)
 for key in meshes:
  var node: MeshInstance3D=meshes[key]
  var path: String=DIRECTORY+key+".res"
  if not ResourceLoader.exists(path):
   push_error("Missing cabin bake; run tools/bake-cabin.sh: "+path)
   continue
  node.mesh=load(path)
  node.material_override=null
  for s in range(node.mesh.get_surface_count()):
   var mat: ShaderMaterial=node.mesh.surface_get_material(s).duplicate()
   mat.set_shader_parameter("candle_on",cabin.settings["cabin-lights"]=="on")
   mat.set_shader_parameter("sun_scale",float(cabin.settings["sun-energy"])/LightingRig.SUN_ENERGY)
   mat.set_shader_parameter("triplanar",key.begins_with("shell_") and cabin.settings["cabin-triplanar"]=="on")
   node.set_surface_override_material(s,mat)
  # Layer 3 excludes these surfaces from the candle's layer-2-only mask.
  node.layers=4
  node.set_meta("cabin_baked",true)

func visible_ray(p: Vector3, target: Vector3) -> bool:
 var query:=PhysicsRayQueryParameters3D.create(p,target,1)
 query.hit_back_faces=true
 return space.intersect_ray(query).is_empty()

func irradiance(p: Vector3, normal: Vector3) -> Array:
 var n:=normal.normalized()
 var key:=str((p*200).round())+str((n*20).round())
 if cache.has(key):return cache[key]
 var origin:=p+n*0.009
 var window:=0.0
 var dominant:=Vector3.ZERO
 # Deterministic stratified quadrature over both actual stern apertures.
 for z in [-0.32,0.51]:
  for j in range(3):
   for k in range(3):
    var source:=Vector3(-12.11,7.2+j*0.35,z+(k-1)*0.24)
    var offset:=source-origin
    var d2:=offset.length_squared()
    var direction:=offset.normalized()
    if visible_ray(origin,source):
     var energy:=maxf(0,-direction.x)/(0.55+d2)*0.96
     window+=maxf(0,n.dot(direction))*energy
     dominant+=direction*energy
 var candle:=0.0
 for i in range(CANDLES.size()):
  var offset: Vector3=CANDLES[i]-origin
  if visible_ray(origin,CANDLES[i]):
   var energy: float=1.0/(0.10+offset.length_squared())*(0.23 if i==0 else 0.07)
   candle+=maxf(0,n.dot(offset.normalized()))*energy
   dominant+=offset.normalized()*energy
 # Direct sun only when the ray crosses one of the real window apertures.
 var sun:=0.0
 var direction:=sun_direction
 var t:=(-12.18-origin.x)/direction.x
 var hit:=origin+direction*t
 if t>0 and hit.y>7.18 and hit.y<7.97 and ((hit.z> -0.67 and hit.z<0.03) or (hit.z>0.16 and hit.z<0.86)):
  if visible_ray(origin,hit):
   sun=maxf(0,n.dot(direction))*0.35
   dominant+=direction*0.35
 var value: Array=[Color(window,candle,sun,1),dominant.normalized() if dominant.length_squared()>0.00001 else n]
 cache[key]=value
 return value

func midpoint(a: Array,b: Array) -> Array:
 return [(a[0]+b[0])*0.5,(a[1]+b[1]).normalized(),(a[2]+b[2])*0.5]

func triangle(st: SurfaceTool, a: Array,b: Array,c: Array,pose: Transform3D,depth: int=0) -> void:
 var ab: float=(pose.basis*(a[0]-b[0])).length_squared()
 var bc: float=(pose.basis*(b[0]-c[0])).length_squared()
 var ca: float=(pose.basis*(c[0]-a[0])).length_squared()
 if maxf(ab,maxf(bc,ca))>0.04 and depth<9:
  if ab>=bc and ab>=ca:
   var m:=midpoint(a,b)
   triangle(st,a,m,c,pose,depth+1);triangle(st,m,b,c,pose,depth+1)
  elif bc>=ca:
   var m:=midpoint(b,c)
   triangle(st,a,b,m,pose,depth+1);triangle(st,a,m,c,pose,depth+1)
  else:
   var m:=midpoint(c,a)
   triangle(st,a,b,m,pose,depth+1);triangle(st,m,b,c,pose,depth+1)
  return
 for v in [a,b,c]:
  st.set_normal(v[1])
  st.set_uv(v[2])
  var lighting:=irradiance(pose*v[0],pose.basis.inverse().transposed()*v[1])
  var direction: Vector3=(pose.basis.inverse()*lighting[1]).normalized()
  st.set_color(lighting[0])
  st.set_custom(0,Color(direction.x,direction.y,direction.z,maxf(0.25,v[1].dot(direction))))
  st.add_vertex(v[0])

func shader_for(cull_mode: int) -> Shader:
 if not shaders.has(cull_mode):
  var shader: Shader=load("res://exploration/cabin_baked.gdshader")
  if cull_mode!=BaseMaterial3D.CULL_BACK:
   var variant:=Shader.new()
   variant.code=shader.code.replace("cull_back", "cull_disabled" if cull_mode==BaseMaterial3D.CULL_DISABLED else "cull_front")
   shader=variant
  shaders[cull_mode]=shader
 return shaders[cull_mode]

func bake_mesh(node: MeshInstance3D,pose: Transform3D,is_shell: bool=false) -> ArrayMesh:
 var mesh:=ArrayMesh.new()
 var cull_modes:=PackedInt32Array()
 # Merge surfaces that share their source material within each static prop.
 var groups: Dictionary={}
 for s in range(node.mesh.get_surface_count()):
  var source: BaseMaterial3D=node.get_active_material(s)
  if not groups.has(source):
   var tool:=SurfaceTool.new()
   tool.begin(Mesh.PRIMITIVE_TRIANGLES)
   tool.set_custom_format(0,SurfaceTool.CUSTOM_RGBA_FLOAT)
   groups[source]=tool
  var arrays:=node.mesh.surface_get_arrays(s)
  var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
  var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
  var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
  var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
  if indices.is_empty():
   for i in range(vertices.size()):indices.append(i)
  for i in range(0,indices.size(),3):
   var v:=[]
   for j in range(3):
    var index:=indices[i+j]
    v.append([vertices[index],normals[index],uv[index] if not uv.is_empty() else Vector2.ZERO])
   triangle(groups[source],v[0],v[1],v[2],pose)
 for source in groups:
  var st: SurfaceTool=groups[source]
  st.generate_tangents()
  st.index()
  st.commit(mesh)
  var material:=ShaderMaterial.new()
  material.shader=shader_for(source.cull_mode)
  cull_modes.append(source.cull_mode)
  material.set_shader_parameter("albedo_map",source.albedo_texture if source.albedo_texture else white)
  material.set_shader_parameter("tint",source.albedo_color)
  # Closed-pose irradiance overstates the open chest. Suppress its bounce and
  # direct terms uniformly; no new runtime light/shader feature is introduced.
  if "treasure_chest" in str(node.name) or "treasure_chest" in str(node.get_parent().name):
   material.set_shader_parameter("light_scale",0.55)
  material.set_shader_parameter("has_normal",source.normal_enabled and source.normal_texture!=null)
  if source.normal_texture:material.set_shader_parameter("normal_map",source.normal_texture)
  material.set_shader_parameter("normal_strength",source.normal_scale)
  if not is_shell:
   material.set_shader_parameter("candle_local",pose.affine_inverse()*CANDLES[0])
   material.set_shader_parameter("specular_amount",source.metallic_specular*0.24)
   material.set_shader_parameter("specular_power",lerpf(96,8,source.roughness))
  mesh.surface_set_material(mesh.get_surface_count()-1,material)
 mesh.set_meta("source_cull_modes",cull_modes)
 return mesh

static func fingerprint(cabin: Node3D) -> String:
 var hash:=HashingContext.new()
 hash.start(HashingContext.HASH_SHA256)
 # Include all opaque occluders, not just bake recipients.
 for node in cabin.find_children("*","MeshInstance3D",true,false):
  var material: Material=node.get_active_material(0)
  if material is ShaderMaterial:continue
  if material is BaseMaterial3D and material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED:continue
  hash.update(var_to_bytes(cabin.relative_pose(node,cabin)))
  for surface in range(node.mesh.get_surface_count()):
   hash.update(var_to_bytes(node.mesh.surface_get_arrays(surface)))
 for path in ["res://exploration/cabin.gd","res://exploration/cabin_bake.gd","res://exploration/build_cabin_light.gd","res://scripts/world.gd","res://exploration/generated/deckhead.json"]:
  hash.update(FileAccess.get_file_as_bytes(path))
 hash.update(var_to_bytes(CANDLES))
 return hash.finish().hex_encode()
