extends MeshInstance3D
# R1: the cap plane and its mesh-derived cross-section use the same height.
# Keep future interior floors above this plane, or use the discard override.
const BILGE_HEIGHT := 2.35
const SEA = preload("res://ocean/default_sea.tres")
const FftOcean = preload("res://ocean/fft_ocean.gd")
const WakeSim = preload("res://ocean/wake_sim.gd")
## Seconds of hull history a frozen capture replays into the wave simulation.
const WAKE_REPLAY := 30.0
var wave_count := 32
var grid := 128
var clip_mode := "occluder"
var bilge: MeshInstance3D
var hull_image: Image
var keel_image: Image
var ship: AnimatableBody3D
var material := ShaderMaterial.new()
var fft: RefCounted
var wake: RefCounted
## Ship motion (buoyancy.gd): supplies the water's drift past the hull.
var motion: RefCounted
var settings: Dictionary = {}
var _last_render_time := NAN

func _ready() -> void:
 var quality = get_node("/root/Quality")
 settings = quality.ocean_settings()
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
 var table: Dictionary = SEA.long_waves(wave_count)
 var waves := PackedVector4Array(table.gpu)
 waves.resize(SEA.MAX_LONG_WAVES)
 material.set_shader_parameter("long_waves", waves)
 material.set_shader_parameter("long_count", table.count)
 var size: int = settings["ocean-detail-size"]
 for i in range(2):
  material.set_shader_parameter("detail"+str(i), load("res://ocean/detail_%d_%d.png" % [size,i]))
 material.set_shader_parameter("sun_direction", get_parent().sun_direction())
 material.set_shader_parameter("sun_energy", float(quality.overrides.get("sun-energy", LightingRig.SUN_ENERGY)))
 material.set_shader_parameter("sun_color", Vector3(LightingRig.SUN_COLOR.r, LightingRig.SUN_COLOR.g, LightingRig.SUN_COLOR.b))
 material.set_shader_parameter("sky_map", _reflection_map())
 material.set_shader_parameter("sky_yaw", get_parent().SKY_YAW)
 material.set_shader_parameter("fog_enabled", quality.overrides.get("fog", "on") == "on")
 material.set_shader_parameter("grid_half", float(grid / 2 - 4))
 # Open-ocean water: pure-water absorption plus a little phytoplankton, and
 # particle backscatter typical of mid-latitude surface water (1/m, RGB).
 _set_optics(Vector3(0.40, 0.06, 0.025), Vector3(0.003, 0.0045, 0.006))
 material.set_shader_parameter("unresolved_variance", 0.004)
 if settings["ocean-fft"] == "on" and FftOcean.supported():
  fft = FftOcean.new(SEA, settings["ocean-fft-size"])
  material.set_shader_parameter("fft_enabled", true)
  material.set_shader_parameter("fft_displacement", fft.displacement)
  material.set_shader_parameter("fft_moments", fft.displacement)
  material.set_shader_parameter("fft_slopes", fft.slopes)
  material.set_shader_parameter("fft_texels", float(fft.n))
  var scales: PackedFloat32Array = fft.shader_scales()
  for i in range(scales.size()):
   material.set_shader_parameter("cascade_scale%d" % i, scales[i])
  # Ripples finer than the last cascade: Cox-Munk total minus what is resolved.
  var resolved: float = SEA.slope_variance(0.0001, fft.bands[-1].z)
  material.set_shader_parameter("unresolved_variance", maxf(SEA.cox_munk_variance()-resolved, 0.002))
 material_override = material
 _build_grid()

func _exit_tree() -> void:
 # Wake first: its uniform sets reference the FFT textures.
 if wake: wake.release()
 if fft: fft.release()
 fft = null
 wake = null

## Diffuse "albedo" of the water column from its inherent optical properties:
## irradiance reflectance ~0.33 b/(a+b) (Gordon), halved by the surface.
func _set_optics(absorption: Vector3, backscatter: Vector3) -> void:
 var ratio := Vector3(backscatter.x/(absorption.x+backscatter.x), backscatter.y/(absorption.y+backscatter.y), backscatter.z/(absorption.z+backscatter.z))
 material.set_shader_parameter("absorption", absorption)
 material.set_shader_parameter("backscatter", backscatter)
 material.set_shader_parameter("water_albedo", ratio*0.165)

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
 var water_drift := render_drift()
 material.set_shader_parameter("sim_time", time)
 material.set_shader_parameter("long_phases", SEA.phases(time, wave_count, water_drift))
 if fft:
  var dt := 0.0 if is_nan(_last_render_time) else time-_last_render_time
  fft.update(time, dt if dt >= 0.0 else -1.0)
  var offsets: PackedVector2Array = fft.shader_offsets(water_drift)
  for i in range(offsets.size()):
   material.set_shader_parameter("cascade_offset%d" % i, offsets[i])
 _last_render_time = time
 if wake:
  wake.flush()
  material.set_shader_parameter("wake_rect", wake.shader_rect())
 if ship:
  material.set_shader_parameter("world_to_ship", ship.get_global_transform_interpolated().affine_inverse())

func _physics_process(delta: float) -> void:
 # World (priority -50) has already posed the hull for this tick.
 if wake and ship and not get_node("/root/SimClock").frozen:
  wake.step(ship.global_transform, get_node("/root/SimClock").time, delta, drift(), current())

## Callable for buoyancy.pose_at(): replays the hull's last seconds into the
## wave simulation so a frozen capture shows its real, settled wake.
func wake_replay(time: float) -> Callable:
 if wake == null: return Callable()
 wake.reset()
 var parent := get_parent() as Node3D
 return func(pose: Transform3D, t: float, dt: float) -> void:
  if t > time-WAKE_REPLAY: wake.step(parent.global_transform*pose, t, dt, drift(), current())

## A splash in the reactive simulation (no-op without a RenderingDevice).
func disturb(point: Vector3, radius: float, depth: float) -> void:
 if wake: wake.disturb(point, radius, depth)

## Water displacement past the ship at the current physics tick.
func drift() -> Vector2:
 return motion.drift if motion else Vector2.ZERO

## Water velocity past the ship.
func current() -> Vector2:
 return motion.water_velocity() if motion else Vector2.ZERO

## Drift between physics ticks, matching the interpolated render time.
func render_drift() -> Vector2:
 if motion == null: return Vector2.ZERO
 if get_node("/root/SimClock").frozen: return motion.drift
 return motion.drift_at(Engine.get_physics_interpolation_fraction())

func surface_at(p: Vector3) -> float:
 return SEA.surface(p.x,p.z,get_node("/root/SimClock").time,wave_count,drift()).position.y

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
 _build_keel(image)
 _start_wake()

## Lowest hull point under each ship-local XZ cell (100 = open water), on the
## same 39 x 12 m frame as the contact distance field. The reactive wave
## simulation reads it as the hull's draft below the incident surface.
func _build_keel(bounds: Image) -> void:
 var width := 192
 var height := 64
 var keel := PackedFloat32Array()
 keel.resize(width*height)
 keel.fill(100.0)
 var data := bounds.get_data().to_float32_array()
 for x in range(width):
  var px := -16.0+float(x)*39.0/float(width-1)
  if px < -14.0 or px > 21.0: continue
  var col := int(round((px+14.0)/35.0*191.0))
  for row in range(64):
   var low := data[(row*192+col)*2]
   var high := data[(row*192+col)*2+1]
   if low >= high: continue
   var y := -2.0+float(row)/63.0*5.0
   for z in range(maxi(0,int(ceil((low+6.0)/12.0*float(height-1)))),mini(height-1,int(floor((high+6.0)/12.0*float(height-1))))+1):
    if keel[z*width+x] > 50.0: keel[z*width+x] = y
 keel_image = Image.create_from_data(width,height,false,Image.FORMAT_RF,keel.to_byte_array())

func _start_wake() -> void:
 if wake or settings.get("ocean-wake","off") != "on" or not FftOcean.supported(): return
 # The FFT textures are created on the render thread; resolve them there too.
 var chop := Callable()
 if fft:
  var source: RefCounted = fft
  chop = func() -> RID: return source._textures[0] if not source._textures.is_empty() else RID()
 wake = WakeSim.new(SEA, wave_count, settings["ocean-wake-size"], settings["ocean-wake-extent"], ImageTexture.create_from_image(keel_image), chop, FftOcean.SIZES)
 material.set_shader_parameter("wake_enabled", true)
 material.set_shader_parameter("wake_map", wake.texture)

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
