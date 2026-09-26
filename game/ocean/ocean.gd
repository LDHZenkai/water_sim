extends MeshInstance3D
# R1: the cap plane and its mesh-derived cross-section use the same height.
# Keep future interior floors above this plane, or use the discard override.
const BILGE_HEIGHT := 2.35
const PROFILE = preload("res://ocean/default_waves.tres")
var wave_count := 5
var grid := 128
var clip_mode := "occluder"
var bilge: MeshInstance3D
var hull_image: Image
var ship: AnimatableBody3D
var material := ShaderMaterial.new()

func _ready() -> void:
 var quality = get_node("/root/Quality")
 var settings: Dictionary = quality.ocean_settings()
 wave_count = settings["ocean-waves"]
 grid = settings["ocean-grid"]
 visible = settings["ocean"] != "off"
 cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
 clip_mode = settings["ocean-clip"]
 var shader_tier: String = settings["ocean-shader"]
 var order: String = settings["ocean-order"]
 # Compile separate variants: a runtime branch around discard still kills early-Z.
 var source := FileAccess.get_file_as_string("res://ocean/ocean_low.gdshader" if shader_tier == "low" else "res://ocean/ocean.gdshader")
 if settings["ocean-debug"] == "rings":
  source = source.substr(0, source.find("void fragment()")) + FileAccess.get_file_as_string("res://ocean/debug_rings.gdshaderinc")
  source = source.replace("specular_schlick_ggx", "unshaded, fog_disabled")
 if clip_mode == "discard":
  source = source.replace("// HULL_CLIP", "if (inside_hull(local)) discard;")
 if order == "after":
  source = source.replace("render_mode ", "render_mode depth_draw_always, ")
  source = source.replace("// QUEUE", "ALPHA = 1.0;")
 material.shader = Shader.new()
 material.shader.code = source
 material.render_priority = -128
 # Opaque front depth layer for the before arm; after uses the alpha queue
 # and writes depth before ropes/glass (whose priority is zero).
 sorting_use_aabb_center = false
 sorting_offset = 100000.0 if order == "before" else 0.0
 material.set_shader_parameter("waves", PROFILE.waves)
 material.set_shader_parameter("wave_count", wave_count)
 var size: int = settings["ocean-detail-size"]
 for i in range(2):
  material.set_shader_parameter("detail"+str(i), load("res://ocean/detail_%d_%d.png" % [size,i]))
 material.set_shader_parameter("sun_direction", get_parent().sun_direction())
 material.set_shader_parameter("sun_energy", float(quality.overrides.get("sun-energy", LightingRig.SUN_ENERGY)))
 material.set_shader_parameter("sky_map", _reflection_map())
 material.set_shader_parameter("sky_yaw", get_parent().SKY_YAW)
 material.set_shader_parameter("fog_enabled", quality.overrides.get("fog", "on") == "on")
 material.set_shader_parameter("grid_half", float(grid / 2 - 4))
 material_override = material
 _build_grid()

func _build_grid() -> void:
 var vertices := PackedVector3Array()
 var indices := PackedInt32Array()
 # One welded lattice: every ring and skirt edge uses shared indices.
 # Never duplicate ring borders: the displacement and LOD must match exactly.
 # Dense 400 m patch, then graded rings to 3 km and the distant skirt.
 for z in range(grid+1):
  for x in range(grid+1):
   vertices.append(Vector3(_coordinate(x),0,_coordinate(z)))
 for z in range(grid):
  for x in range(grid):
   var a := z*(grid+1)+x
   indices.append_array(PackedInt32Array([a,a+1,a+grid+1,a+1,a+grid+2,a+grid+1]))
 var arrays := []
 arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX] = vertices
 arrays[Mesh.ARRAY_INDEX] = indices
 var result := ArrayMesh.new()
 result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
 mesh = result
 custom_aabb = AABB(Vector3(-24000,-5,-24000),Vector3(48000,10,48000))

func _coordinate(i: int) -> float:
 var index := absi(i-grid/2)
 var half := grid/2
 var sign_value := signf(float(i-grid/2))
 if index == half: return sign_value*24000.0
 if index == half-1: return sign_value*3000.0
 if index == half-2: return sign_value*1600.0
 if index == half-3: return sign_value*800.0
 var u := float(index)/float(half-4)
 return sign_value*pow(u,1.6)*400.0

func _process(_delta: float) -> void:
 var camera := get_viewport().get_camera_3d()
 if camera:
  var eye := camera.get_global_transform_interpolated().origin
  var snap := 400.0/pow(float(grid/2-4),1.6)
  global_position = Vector3(snappedf(eye.x,snap),0,snappedf(eye.z,snap))
 var time: float = get_node("/root/SimClock").render_time()
 material.set_shader_parameter("sim_time", time)
 var phases := PackedFloat32Array()
 for wave in PROFILE.waves:
  phases.append(fposmod(sqrt(9.81*TAU/wave.z)*time,TAU))
 material.set_shader_parameter("wave_phases", phases)
 if ship:
  material.set_shader_parameter("world_to_ship", ship.get_global_transform_interpolated().affine_inverse())

func surface_at(p: Vector3) -> float:
 return PROFILE.surface(p.x,p.z,get_node("/root/SimClock").time,wave_count).position.y

func build_hull_mask(hull: MeshInstance3D, source_mesh: Mesh = null) -> void:
 # Rasterize hull triangles in ship XY; retain Z interval at each texel.
 # Volume discard also works when the eye is INSIDE the future cabin, unlike
 # a screen silhouette stencil alone. Bounds include 3 cm of the wooden shell.
 var image := Image.create(192,64,false,Image.FORMAT_RGF)
 image.fill(Color(99,-99,0))
 var faces := source_mesh.get_faces() if source_mesh != null else hull.mesh.get_faces()
 var transform_to_ship := ship.global_transform.affine_inverse()*hull.global_transform
 for i in range(0,faces.size(),3):
  var a: Vector3 = transform_to_ship*faces[i]
  var b: Vector3 = transform_to_ship*faces[i+1]
  var c: Vector3 = transform_to_ship*faces[i+2]
  var low := maxi(0,int(floor((minf(a.y,minf(b.y,c.y))+2.0)/5.0*63)))
  var high := mini(63,int(ceil((maxf(a.y,maxf(b.y,c.y))+2.0)/5.0*63)))
  for row in range(low,high+1):
   var y := -2.0+float(row)/63.0*5.0
   var points: Array[Vector3] = []
   for edge in [[a,b],[b,c],[c,a]]:
    var p: Vector3 = edge[0]
    var q: Vector3 = edge[1]
    if absf(q.y-p.y)>0.00001 and y>=minf(p.y,q.y) and y<=maxf(p.y,q.y):
     points.append(p.lerp(q,(y-p.y)/(q.y-p.y)))
   if points.size()<2: continue
   var p := points[0]
   var q := points[1]
   if p.x>q.x:
    var swap := p
    p=q
    q=swap
   for col in range(maxi(0,int(floor((p.x+14.0)/35.0*191))),mini(191,int(ceil((q.x+14.0)/35.0*191)))+1):
    var x := -14.0+float(col)/191.0*35.0
    var z := lerpf(p.z,q.z,clampf((x-p.x)/maxf(q.x-p.x,0.00001),0,1))
    var old := image.get_pixel(col,row)
    image.set_pixel(col,row,Color(minf(old.r,z-0.03),maxf(old.g,z+0.03),0))
 _build_bilge(image)
 _build_contact_distance(image)
 var padded := image.duplicate()
 for y in range(64):
  for x in range(192):
   if image.get_pixel(x,y).r < image.get_pixel(x,y).g: continue
   var low := 99.0
   var high := -99.0
   for offset in [Vector2i(-1,0),Vector2i(1,0),Vector2i(0,-1),Vector2i(0,1)]:
    var q: Vector2i = Vector2i(x,y)+offset
    if q.x<0 or q.x>=192 or q.y<0 or q.y>=64: continue
    var neighbor := image.get_pixelv(q)
    if neighbor.r < neighbor.g:
     low=minf(low,neighbor.r)
     high=maxf(high,neighbor.g)
   padded.set_pixel(x,y,Color(low,high,0))
 image=padded
 hull_image=image
 var texture := ImageTexture.create_from_image(image)
 material.set_shader_parameter("hull_bounds",texture)

func _reflection_map() -> ImageTexture:
 # Small mipmapped radiance approximation. Static sky: paid once at startup.
 var source: Image = preload("res://assets/polyhaven/hdris/qwantani_late_afternoon_puresky_4k.hdr").get_image().duplicate()
 source.resize(256, 128, Image.INTERPOLATE_LANCZOS)
 source.generate_mipmaps()
 return ImageTexture.create_from_image(source)

func _build_bilge(bounds: Image) -> void:
 if clip_mode != "occluder": return
 # Opaque cap inside the wooden shell, above design waterline but below deck.
 # It writes ordinary depth; no stencil, alpha or fragment discard.
 var vertices := PackedVector3Array()
 var row := int(round((BILGE_HEIGHT + 2.0) / 5.0 * 63.0))
 for x in range(191):
  var a := bounds.get_pixel(x, row)
  var b := bounds.get_pixel(x + 1, row)
  if a.r >= a.g or b.r >= b.g: continue
  var x0 := -14.0 + float(x) / 191.0 * 35.0
  var x1 := -14.0 + float(x + 1) / 191.0 * 35.0
  var p := Vector3(x0, BILGE_HEIGHT, a.r + 0.03)
  var q := Vector3(x0, BILGE_HEIGHT, a.g - 0.03)
  var r := Vector3(x1, BILGE_HEIGHT, b.r + 0.03)
  var s := Vector3(x1, BILGE_HEIGHT, b.g - 0.03)
  vertices.append_array(PackedVector3Array([p,r,q,r,s,q]))
 var arrays := []
 arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX] = vertices
 var cap := ArrayMesh.new()
 cap.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
 bilge = MeshInstance3D.new()
 bilge.name = "OpaqueBilge"
 bilge.mesh = cap
 var dark := StandardMaterial3D.new()
 dark.disable_fog = true
 dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 dark.cull_mode = BaseMaterial3D.CULL_DISABLED
 dark.albedo_color = Color(0.018, 0.012, 0.008)
 bilge.material_override = dark
 bilge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 bilge.visible = visible
 ship.add_child(bilge)

func contains_point(world_point: Vector3) -> bool:
 if hull_image == null: return false
 var p := ship.to_local(world_point)
 if p.x < -14.0 or p.x > 21.0 or p.y < -2.0 or p.y > 3.0: return false
 var x := int(round((p.x+14.0)/35.0*191.0))
 var y := int(round((p.y+2.0)/5.0*63.0))
 var bounds := hull_image.get_pixel(x,y)
 return p.z > bounds.r and p.z < bounds.g

func _build_contact_distance(bounds: Image) -> void:
 # Two-pass chamfer distance in ship XZ. Unlike Z-only intervals this also
 # gives bow and stern contact foam. Built once; a single small R float map.
 var width := 192
 var height := 64
 var dx := 39.0/float(width-1)
 var dz := 12.0/float(height-1)
 var diagonal := sqrt(dx*dx+dz*dz)
 var distances := PackedFloat32Array()
 distances.resize(width*height)
 distances.fill(100.0)
 var row := int(round(2.6/5.0*63.0))
 for z in range(height):
  for x in range(width):
   var px := -16.0+x*dx
   if px < -14.0 or px > 21.0: continue
   var interval := bounds.get_pixel(int(round((px+14.0)/35.0*191.0)),row)
   var pz := -6.0+z*dz
   if pz > interval.r and pz < interval.g:
    distances[z*width+x]=0.0
 for direction in [1,-1]:
  for zi in range(height):
   var z: int = zi if direction == 1 else height-1-zi
   for xi in range(width):
    var x: int = xi if direction == 1 else width-1-xi
    var index := z*width+x
    for offset in [Vector2i(-direction,0),Vector2i(0,-direction),Vector2i(-direction,-direction),Vector2i(direction,-direction)]:
     var q: Vector2i=Vector2i(x,z)+offset
     if q.x<0 or q.x>=width or q.y<0 or q.y>=height: continue
     var cost: float = diagonal if offset.x != 0 and offset.y != 0 else (dx if offset.x != 0 else dz)
     distances[index]=minf(distances[index],distances[q.y*width+q.x]+cost)
 var field := Image.create(width,height,false,Image.FORMAT_RF)
 for z in range(height):
  for x in range(width):
   field.set_pixel(x,z,Color(distances[z*width+x],0,0))
 material.set_shader_parameter("hull_distance",ImageTexture.create_from_image(field))
