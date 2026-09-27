extends RefCounted
## Reactive water around the ship: a local, exactly dispersive linear wave
## simulation (Tessendorf's eWave) on the GPU, stepped with the physics tick.
## The hull is a pressure patch equal to its draft below the incident waves
## (long-wave components + FFT chop), so heave, pitch, roll, chop running
## along the hull and any current past it radiate real, dispersive waves:
## bow and stern slap, reflections off the windward side, a sheltered lee and,
## with a current, a Kelvin wake. Splashes are local surface impulses.
## Output: a two-layer Texture2DArrayRD with mips, sampled by the ocean shader
##   layer 0 (height, dh/dx, dh/dz, foam)   layer 1 (u, w, P, phi)
const SHADERS := ["wake_force","wake_propagate","fft","wake_output","mip_down"]
const STEP_BYTES := 1744
const MAX_IMPULSES := 16
const FOAM_DECAY := 3.5

var sea: Resource
var count := 32
var n := 256
var size := 128.0
var texel := 0.5
var levels := 9
var texture := Texture2DArrayRD.new()
var rd: RenderingDevice
var corner := Vector2.ZERO
var _spirv := {}
var _pipelines := {}
var _owned: Array[RID] = []
var _uniform_sets: Array[RID] = []
var _keel_texture: Texture2D
var _chop_rid := RID()
var _chop_source := Callable()
var _chop_scales := PackedFloat32Array()
var _chop_sizes := PackedFloat32Array()
var _queue: Array[PackedByteArray] = []
var _queue_meta: Array[Vector4] = []
var _queue_current: Array[Vector2] = []
var _impulses: Array[Vector4] = []
var _first := true
var _foam_index := 0
var _step_buffer: RID
var _map: RID
var _force_set: RID
var _fft_sets: Array[RID] = []
var _propagate_set: RID
var _output_sets: Array[RID] = []
var _mip_sets: Array[RID] = []

func _init(sea_state: Resource, wave_count: int, grid: int, domain: float, keel: Texture2D, chop: Callable, chop_sizes: Array) -> void:
 sea = sea_state
 count = wave_count
 n = grid
 size = domain
 texel = size/float(n)
 levels = int(round(log(float(n))/log(2.0)))+1
 _keel_texture = keel
 _chop_source = chop
 for s in chop_sizes: _chop_sizes.append(s)
 for name in SHADERS:
  _spirv[name] = preload("res://ocean/compute/compute_shader.gd").spirv(name)
 RenderingServer.call_on_render_thread(_create)

func _own(rid: RID) -> RID:
 _owned.append(rid)
 return rid

static func _uniform(binding: int, type: int, rids: Array) -> RDUniform:
 var uniform := RDUniform.new()
 uniform.binding = binding
 uniform.uniform_type = type
 for rid in rids: uniform.add_id(rid)
 return uniform

func _make_set(shader: String, uniforms: Array[RDUniform]) -> RID:
 var uniform_set := rd.uniform_set_create(uniforms,_pipelines[shader].shader,0)
 _uniform_sets.append(uniform_set)
 return _own(uniform_set)

func _create() -> void:
 rd = RenderingServer.get_rendering_device()
 for name in SHADERS:
  var shader := _own(rd.shader_create_from_spirv(_spirv[name]))
  _pipelines[name] = {"shader":shader,"pipeline":_own(rd.compute_pipeline_create(shader))}
 var cells := n*n
 var state_a := _own(rd.storage_buffer_create(cells*8))
 var state_b := _own(rd.storage_buffer_create(cells*8))
 var pressure := _own(rd.storage_buffer_create(cells*8))
 _step_buffer = _own(rd.storage_buffer_create(STEP_BYTES))
 var format := RDTextureFormat.new()
 format.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
 format.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
 format.width = n
 format.height = n
 format.array_layers = 2
 format.mipmaps = levels
 format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
 _map = _own(rd.texture_create(format,RDTextureView.new()))
 rd.texture_clear(_map,Color(0,0,0,0),0,levels,0,2)
 var views := []
 for layer in range(2):
  var per_level: Array[RID] = []
  for level in range(levels):
   per_level.append(_own(rd.texture_create_shared_from_slice(RDTextureView.new(),_map,layer,level,1,RenderingDevice.TEXTURE_SLICE_2D)))
  views.append(per_level)
 var foam_format := RDTextureFormat.new()
 foam_format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
 foam_format.width = n
 foam_format.height = n
 foam_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
 var foam: Array[RID] = []
 for i in range(2):
  foam.append(_own(rd.texture_create(foam_format,RDTextureView.new())))
  rd.texture_clear(foam[i],Color(0,0,0,0),0,1,0,1)
 var sampler_state := RDSamplerState.new()
 sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
 sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
 sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
 sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
 var clamp_sampler := _own(rd.sampler_create(sampler_state))
 sampler_state.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
 sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
 sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
 var repeat_sampler := _own(rd.sampler_create(sampler_state))
 var keel_rid := RenderingServer.texture_get_rd_texture(_keel_texture.get_rid())
 if _chop_source.is_valid(): _chop_rid = _chop_source.call()
 var chop := _chop_rid
 if not chop.is_valid():
  # No FFT cascades: bind a flat two-layer stand-in.
  var flat := RDTextureFormat.new()
  flat.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
  flat.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
  flat.width = 1
  flat.height = 1
  flat.array_layers = 2
  flat.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
  chop = _own(rd.texture_create(flat,RDTextureView.new()))
  rd.texture_clear(chop,Color(0,0,0,0),0,1,0,2)
 var buffer := RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
 var image := RenderingDevice.UNIFORM_TYPE_IMAGE
 var sampled := RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
 _force_set = _make_set("wake_force",[_uniform(0,buffer,[state_b]),_uniform(1,buffer,[state_a]),_uniform(2,buffer,[pressure]),_uniform(3,buffer,[_step_buffer]),_uniform(4,sampled,[clamp_sampler,keel_rid]),_uniform(5,sampled,[repeat_sampler,chop])])
 _fft_sets = [_make_set("fft",[_uniform(0,buffer,[state_a])]),_make_set("fft",[_uniform(0,buffer,[state_b])])]
 _propagate_set = _make_set("wake_propagate",[_uniform(0,buffer,[state_a]),_uniform(1,buffer,[state_b])])
 for i in range(2):
  _output_sets.append(_make_set("wake_output",[_uniform(0,buffer,[state_b]),_uniform(1,buffer,[pressure]),_uniform(2,image,[foam[i]]),_uniform(3,image,[foam[1-i]]),_uniform(4,image,[views[0][0]]),_uniform(5,image,[views[1][0]])]))
 for level in range(1,levels):
  _mip_sets.append(_make_set("mip_down",[_uniform(0,image,[views[0][level-1]]),_uniform(1,image,[views[0][level]]),_uniform(2,image,[views[1][level-1]]),_uniform(3,image,[views[1][level]])]))
 texture.texture_rd_rid = _map

## Domain placement: centred on the ship, pushed downstream so the wake has
## room, snapped to whole texels so the field shifts without resampling.
func _corner_for(ship_global: Transform3D, current: Vector2) -> Vector2:
 var center := Vector2(ship_global.origin.x,ship_global.origin.z)
 if current.length() > 0.01:
  center += current.normalized()*size*0.22
 return Vector2(floor((center.x-size*0.5)/texel)*texel,floor((center.y-size*0.5)/texel)*texel)

static func _mat4(transform: Transform3D) -> PackedFloat32Array:
 var b := transform.basis
 var o := transform.origin
 return PackedFloat32Array([b.x.x,b.x.y,b.x.z,0.0,b.y.x,b.y.y,b.y.z,0.0,b.z.x,b.z.y,b.z.z,0.0,o.x,o.y,o.z,1.0])

## Queue one physics tick with the hull's global pose at time. drift is how
## far the water has moved past the ship (buoyancy.gd), current its velocity.
func step(ship_global: Transform3D, time: float, dt: float, drift := Vector2.ZERO, current := Vector2.ZERO) -> void:
 var next_corner := _corner_for(ship_global, current)
 var shift := Vector2i(0,0)
 if not _first:
  shift = Vector2i(roundi((next_corner.x-corner.x)/texel),roundi((next_corner.y-corner.y)/texel))
 corner = next_corner
 var floats := PackedFloat32Array()
 floats.append_array(_mat4(ship_global.affine_inverse()))
 floats.append_array(_mat4(ship_global))
 floats.append_array([corner.x,corner.y,texel,float(n)])
 floats.append_array([current.x,current.y,dt,2.0 if _first else 0.0])
 var bytes := floats.to_byte_array()
 var table: Dictionary = sea.long_waves(count)
 var impulses := _impulses.slice(0,MAX_IMPULSES)
 _impulses.clear()
 var ints := PackedInt32Array([shift.x,shift.y,impulses.size(),int(table.count)])
 bytes.append_array(ints.to_byte_array())
 var chop := PackedFloat32Array()
 for c in range(2):
  if _chop_rid.is_valid():
   chop.append_array([1.0/_chop_sizes[c],fposmod(drift.x,_chop_sizes[c]),fposmod(drift.y,_chop_sizes[c]),1.0])
  else:
   chop.append_array([0.0,0.0,0.0,0.0])
 for i in range(MAX_IMPULSES):
  var impulse: Vector4 = impulses[i] if i < impulses.size() else Vector4(0,0,1,0)
  chop.append_array([impulse.x,impulse.y,impulse.z,impulse.w])
 var waves: PackedVector4Array = table.gpu
 for i in range(sea.MAX_LONG_WAVES):
  var w: Vector4 = waves[i] if i < waves.size() else Vector4.ZERO
  chop.append_array([w.x,w.y,w.z,w.w])
 chop.append_array(sea.phases(time,count,drift))
 bytes.append_array(chop.to_byte_array())
 assert(bytes.size() == STEP_BYTES)
 _queue.append(bytes)
 _queue_meta.append(Vector4(dt,float(shift.x),float(shift.y),0))
 _queue_current.append(current)
 _first = false

## A splash: the surface is punched down by depth (m) over radius (m).
func disturb(point: Vector3, radius: float, depth: float) -> void:
 if _impulses.size() < MAX_IMPULSES:
  _impulses.append(Vector4(point.x,point.z,radius,depth))

func reset() -> void:
 _first = true
 _queue.clear()
 _queue_meta.clear()
 _queue_current.clear()

## Run every queued step on the render thread, then rebuild the mips.
func flush() -> void:
 if _queue.is_empty(): return
 var steps := _queue.duplicate()
 var meta := _queue_meta.duplicate()
 var currents := _queue_current.duplicate()
 _queue.clear()
 _queue_meta.clear()
 _queue_current.clear()
 RenderingServer.call_on_render_thread(_run.bind(steps,meta,currents))

func _run(steps: Array[PackedByteArray], meta: Array[Vector4], currents: Array[Vector2]) -> void:
 if rd == null: return
 var groups := ceili(n/8.0)
 # Grid-scale damping only: Nyquist decays over ~10 s. The exact propagator
 # is stable without it, and more would erode the hull's static depression.
 var viscosity := texel*texel/(PI*PI*10.0)
 for i in range(steps.size()):
  rd.buffer_update(_step_buffer,0,STEP_BYTES,steps[i])
  var dt := meta[i].x
  var current := currents[i]
  var list := rd.compute_list_begin()
  rd.compute_list_bind_compute_pipeline(list,_pipelines.wake_force.pipeline)
  rd.compute_list_bind_uniform_set(list,_force_set,0)
  rd.compute_list_dispatch(list,groups,groups,1)
  rd.compute_list_add_barrier(list)
  _fft(list,0,-1.0)
  rd.compute_list_bind_compute_pipeline(list,_pipelines.wake_propagate.pipeline)
  rd.compute_list_bind_uniform_set(list,_propagate_set,0)
  var push := _bytes([n,size,dt,viscosity,current.x,current.y,0.0,0.0])
  rd.compute_list_set_push_constant(list,push,push.size())
  rd.compute_list_dispatch(list,groups,groups,1)
  rd.compute_list_add_barrier(list)
  _fft(list,1,1.0)
  rd.compute_list_bind_compute_pipeline(list,_pipelines.wake_output.pipeline)
  rd.compute_list_bind_uniform_set(list,_output_sets[_foam_index],0)
  push = _bytes([n,texel,dt,FOAM_DECAY,current.x,current.y,int(meta[i].y),int(meta[i].z)])
  rd.compute_list_set_push_constant(list,push,push.size())
  rd.compute_list_dispatch(list,groups,groups,1)
  rd.compute_list_end()
  _foam_index = 1-_foam_index
 var list := rd.compute_list_begin()
 rd.compute_list_bind_compute_pipeline(list,_pipelines.mip_down.pipeline)
 for level in range(1,levels):
  var extent := maxi(1,n >> level)
  rd.compute_list_bind_uniform_set(list,_mip_sets[level-1],0)
  rd.compute_list_dispatch(list,ceili(extent/8.0),ceili(extent/8.0),1)
  rd.compute_list_add_barrier(list)
 rd.compute_list_end()

func _fft(list: int, buffer: int, direction: float) -> void:
 rd.compute_list_bind_compute_pipeline(list,_pipelines.fft.pipeline)
 rd.compute_list_bind_uniform_set(list,_fft_sets[buffer],0)
 for columns in [0,1]:
  var push := _bytes([n,columns,direction,0])
  rd.compute_list_set_push_constant(list,push,push.size())
  rd.compute_list_dispatch(list,n,1,1)
  rd.compute_list_add_barrier(list)

static func _bytes(values: Array) -> PackedByteArray:
 var bytes := PackedByteArray()
 bytes.resize(maxi(16,int(ceil(values.size()/4.0))*16))
 for i in range(values.size()):
  if typeof(values[i]) == TYPE_INT: bytes.encode_s32(i*4,values[i])
  else: bytes.encode_float(i*4,values[i])
 return bytes

## (corner x, corner z, 1/size, edge fade) for the ocean shader.
func shader_rect() -> Vector4:
 return Vector4(corner.x,corner.y,1.0/size,0.1)

## Synchronous readback of one layer (tests only: stalls the GPU).
func read_layer(layer: int) -> Image:
 var data := rd.texture_get_data(_map,layer)
 return Image.create_from_data(n,n,false,Image.FORMAT_RGBAH,data.slice(0,n*n*8))

func release() -> void:
 var owned := _owned.duplicate()
 var sets := _uniform_sets.duplicate()
 _owned.clear()
 _uniform_sets.clear()
 texture.texture_rd_rid = RID()
 if rd != null:
  RenderingServer.call_on_render_thread(_free.bind(rd,owned,sets))
 rd = null

static func _free(device: RenderingDevice, owned: Array[RID], sets: Array[RID]) -> void:
 # Uniform sets die with any resource they use; skip the ones already gone.
 for i in range(owned.size()-1,-1,-1):
  if owned[i] in sets and not device.uniform_set_is_valid(owned[i]): continue
  if owned[i].is_valid():
   device.free_rid(owned[i])
