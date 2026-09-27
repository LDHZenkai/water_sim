extends RefCounted
## GPU spectral ocean for the short-wave band (shorter than the sea state's
## split wavelength). Tessendorf (2001) FFT synthesis on the main
## RenderingDevice: three cascades with incommensurate tile sizes, each owning
## one annulus of wavenumbers, so the combined surface has no visible repeat.
## Outputs are Texture2DArrayRD (one layer per cascade) sampled directly by the
## ocean shader:
##   displacement (Dx, Y, Dz, slope^2)   slopes (sx, sz, whitecap foam, J)
## Both carry full mip chains so distant water filters instead of shimmering.
const SIZES := [167.3, 29.7, 5.27]
## Frequencies are quantised so the field repeats exactly every period; the
## wrapped time then keeps float precision however long the session runs.
const REPEAT_PERIOD := 1024.0
## Per cascade: whitecap e-folding time (s), Jacobian threshold, gain.
const FOAM := [Vector3(3.5,0.7,2.5),Vector3(1.6,0.62,2.0),Vector3(0.4,0.0,0.0)]
const SHADERS := ["spectrum_init","spectrum_update","fft","cascade_resolve","mip_down"]

var sea: Resource
var n := 256
var levels := 9
var bands: Array[Vector3] = []
var displacement := Texture2DArrayRD.new()
var slopes := Texture2DArrayRD.new()
var rd: RenderingDevice
var _spirv := {}
var _pipelines := {}
var _owned: Array[RID] = []
var _uniform_sets: Array[RID] = []
var _h0: RID
var _planes: RID
var _cascades: RID
var _textures: Array[RID] = []
var _views := []
var _update_set: RID
var _fft_set: RID
var _resolve_sets: Array[RID] = []
var _mip_sets := []
var _history_time := NAN
var _init_set: RID
## Spectrum parameters last written into h0 (sea_state.gpu_spectrum()).
var _spectrum := PackedFloat32Array()

static func supported() -> bool:
 return RenderingServer.get_rendering_device() != null

func _init(sea_state: Resource, size: int) -> void:
 sea = sea_state
 n = size
 levels = int(round(log(float(n))/log(2.0)))+1
 bands = cascade_bands(sea, n)
 _spectrum = sea.gpu_spectrum()
 for name in SHADERS:
  _spirv[name] = preload("res://ocean/compute/compute_shader.gd").spirv(name)
 RenderingServer.call_on_render_thread(_create)

## (tile size, k_low, k_high) per cascade. Each cascade keeps up to half its
## Nyquist wavenumber (the last goes to 3/4): well sampled, no gaps, no overlap.
static func cascade_bands(sea_state: Resource, size: int) -> Array[Vector3]:
 var result: Array[Vector3] = []
 var low: float = sea_state.split_frequency()*sea_state.split_frequency()/sea_state.GRAVITY
 for i in range(SIZES.size()):
  var nyquist: float = PI*float(size)/float(SIZES[i])
  var high: float = nyquist*(0.75 if i == SIZES.size()-1 else 0.5)
  result.append(Vector3(SIZES[i],low,maxf(high,low)))
  low = maxf(high,low)
 return result

static func _bytes(values: Array) -> PackedByteArray:
 var bytes := PackedByteArray()
 bytes.resize(maxi(16,int(ceil(values.size()/4.0))*16))
 for i in range(values.size()):
  if typeof(values[i]) == TYPE_INT: bytes.encode_u32(i*4,values[i])
  else: bytes.encode_float(i*4,values[i])
 return bytes

static func _uniform(binding: int, type: int, rid: RID) -> RDUniform:
 var uniform := RDUniform.new()
 uniform.binding = binding
 uniform.uniform_type = type
 uniform.add_id(rid)
 return uniform

func _own(rid: RID) -> RID:
 _owned.append(rid)
 return rid

func _make_set(shader: String, uniforms: Array[RDUniform]) -> RID:
 var uniform_set := rd.uniform_set_create(uniforms,_pipelines[shader].shader,0)
 _uniform_sets.append(uniform_set)
 return _own(uniform_set)

func _create() -> void:
 rd = RenderingServer.get_rendering_device()
 for name in SHADERS:
  var shader := _own(rd.shader_create_from_spirv(_spirv[name]))
  _pipelines[name] = {"shader":shader,"pipeline":_own(rd.compute_pipeline_create(shader))}
 var cascade_data := PackedFloat32Array()
 for i in range(bands.size()):
  cascade_data.append_array([bands[i].x,bands[i].y,bands[i].z,FOAM[i].x])
 var layers := SIZES.size()
 _cascades = _own(rd.storage_buffer_create(cascade_data.size()*4,cascade_data.to_byte_array()))
 _h0 = _own(rd.storage_buffer_create(n*n*layers*16))
 _planes = _own(rd.storage_buffer_create(n*n*layers*4*8))
 var format := RDTextureFormat.new()
 format.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
 format.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
 format.width = n
 format.height = n
 format.array_layers = layers
 format.mipmaps = levels
 format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
 for t in range(2):
  var texture := _own(rd.texture_create(format,RDTextureView.new()))
  rd.texture_clear(texture,Color(0,0,0,0),0,levels,0,layers)
  _textures.append(texture)
  var per_layer := []
  for layer in range(layers):
   var per_level: Array[RID] = []
   for level in range(levels):
    per_level.append(_own(rd.texture_create_shared_from_slice(RDTextureView.new(),texture,layer,level,1,RenderingDevice.TEXTURE_SLICE_2D)))
   per_layer.append(per_level)
  _views.append(per_layer)
 var buffer := RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
 var image := RenderingDevice.UNIFORM_TYPE_IMAGE
 var init_set := _make_set("spectrum_init",[_uniform(0,buffer,_h0),_uniform(1,buffer,_cascades)])
 _update_set = _make_set("spectrum_update",[_uniform(0,buffer,_h0),_uniform(1,buffer,_planes),_uniform(2,buffer,_cascades)])
 _fft_set = _make_set("fft",[_uniform(0,buffer,_planes)])
 for layer in range(layers):
  _resolve_sets.append(_make_set("cascade_resolve",[_uniform(0,buffer,_planes),_uniform(1,image,_views[0][layer][0]),_uniform(2,image,_views[1][layer][0])]))
  var per_level: Array[RID] = []
  for level in range(1,levels):
   per_level.append(_make_set("mip_down",[_uniform(0,image,_views[0][layer][level-1]),_uniform(1,image,_views[0][layer][level]),_uniform(2,image,_views[1][layer][level-1]),_uniform(3,image,_views[1][layer][level])]))
  _mip_sets.append(per_level)
 _init_set = init_set
 _initialise(_spectrum)
 displacement.texture_rd_rid = _textures[0]
 slopes.texture_rd_rid = _textures[1]

func _initialise(spectrum: PackedFloat32Array) -> void:
 var values: Array = Array(spectrum)
 values.append_array([n,SIZES.size(),TAU/REPEAT_PERIOD,0.0])
 var list := rd.compute_list_begin()
 rd.compute_list_bind_compute_pipeline(list,_pipelines.spectrum_init.pipeline)
 rd.compute_list_bind_uniform_set(list,_init_set,0)
 var push := _bytes(values)
 rd.compute_list_set_push_constant(list,push,push.size())
 rd.compute_list_dispatch(list,ceili(n/8.0),ceili(n/8.0),SIZES.size())
 rd.compute_list_end()

## Rewrite h0 when the weather changes the spectrum. The Gaussian noise is a
## hash of each mode, so only amplitudes move: a gradual change in wind gives
## a gradual change in the short waves, never a new random sea.
func refresh(spectrum: PackedFloat32Array) -> bool:
 if spectrum.size() == _spectrum.size():
  var same := true
  for i in range(spectrum.size()):
   if absf(spectrum[i] - _spectrum[i]) > 1e-5 * maxf(1.0, absf(_spectrum[i])): same = false
  if same: return false
 _spectrum = spectrum
 RenderingServer.call_on_render_thread(func() -> void: if rd != null: _initialise(spectrum))
 return true

## Queue one synthesis at time (s). dt drives whitecap decay; a jump in time
## (first frame, frozen capture) replays a few seconds so foam trails exist.
func update(time: float, dt: float) -> void:
 RenderingServer.call_on_render_thread(_step.bind(time,dt))

func _step(time: float, dt: float) -> void:
 if rd == null: return
 var continuous := not is_nan(_history_time) and dt > 0.0 and absf(time-dt-_history_time) < 0.25
 if not continuous and not (is_equal_approx(time,_history_time) and dt <= 0.0):
  for i in range(40):
   _synthesise(time-4.0+float(i)*0.1,0.1,false)
  dt = 0.1
 _synthesise(time,dt,true)
 _history_time = time

func _synthesise(time: float, dt: float, mips: bool) -> void:
 var layers := SIZES.size()
 var list := rd.compute_list_begin()
 rd.compute_list_bind_compute_pipeline(list,_pipelines.spectrum_update.pipeline)
 rd.compute_list_bind_uniform_set(list,_update_set,0)
 var push := _bytes([fposmod(time,REPEAT_PERIOD),TAU/REPEAT_PERIOD,n,layers])
 rd.compute_list_set_push_constant(list,push,push.size())
 rd.compute_list_dispatch(list,ceili(n/8.0),ceili(n/8.0),layers)
 rd.compute_list_add_barrier(list)
 rd.compute_list_bind_compute_pipeline(list,_pipelines.fft.pipeline)
 rd.compute_list_bind_uniform_set(list,_fft_set,0)
 for columns in [0,1]:
  push = _bytes([n,columns,1.0,0])
  rd.compute_list_set_push_constant(list,push,push.size())
  rd.compute_list_dispatch(list,n,layers*4,1)
  rd.compute_list_add_barrier(list)
 rd.compute_list_bind_compute_pipeline(list,_pipelines.cascade_resolve.pipeline)
 for layer in range(layers):
  rd.compute_list_bind_uniform_set(list,_resolve_sets[layer],0)
  push = _bytes([n,layer,float(sea.choppiness),dt,FOAM[layer].x,FOAM[layer].y,FOAM[layer].z,0.0])
  rd.compute_list_set_push_constant(list,push,push.size())
  rd.compute_list_dispatch(list,ceili(n/8.0),ceili(n/8.0),1)
 rd.compute_list_end()
 if mips:
  # A fresh list: mip_down takes no push constants.
  list = rd.compute_list_begin()
  rd.compute_list_bind_compute_pipeline(list,_pipelines.mip_down.pipeline)
  for level in range(1,levels):
   var size := maxi(1,n >> level)
   for layer in range(layers):
    rd.compute_list_bind_uniform_set(list,_mip_sets[layer][level-1],0)
    rd.compute_list_dispatch(list,ceili(size/8.0),ceili(size/8.0),1)
   rd.compute_list_add_barrier(list)
  rd.compute_list_end()

## Scale (1/tile) and sampling offset of each cascade for the ocean shader.
## The offset carries the pattern with the water drifting past the ship.
func shader_scales() -> PackedFloat32Array:
 var result := PackedFloat32Array()
 for size in SIZES: result.append(1.0/size)
 return result

func shader_offsets(drift: Vector2) -> PackedVector2Array:
 var result := PackedVector2Array()
 for size in SIZES:
  result.append(Vector2(fposmod(drift.x,size),fposmod(drift.y,size)))
 return result

## Synchronous readback of one cascade (tests only: stalls the GPU).
func read_layer(texture: int, layer: int) -> Image:
 # texture 0: displacement, 1: slopes
 var data := rd.texture_get_data(_textures[texture],layer)
 return Image.create_from_data(n,n,false,Image.FORMAT_RGBAH,data.slice(0,n*n*8))

func release() -> void:
 var owned := _owned.duplicate()
 var sets := _uniform_sets.duplicate()
 _owned.clear()
 _uniform_sets.clear()
 displacement.texture_rd_rid = RID()
 slopes.texture_rd_rid = RID()
 if rd != null:
  RenderingServer.call_on_render_thread(_free.bind(rd,owned,sets))
 rd = null

static func _free(device: RenderingDevice, owned: Array[RID], sets: Array[RID]) -> void:
 # Uniform sets die with any resource they use; skip the ones already gone.
 for i in range(owned.size()-1,-1,-1):
  if owned[i] in sets and not device.uniform_set_is_valid(owned[i]): continue
  if owned[i].is_valid(): device.free_rid(owned[i])
