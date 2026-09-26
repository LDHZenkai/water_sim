extends Node3D
## Retained material swatches in the actual viewport: never free/rebase paired
## geometry after startup. Hide the swatches once all materials have been drawn.
var camera: Camera3D
var curtain: CanvasLayer
var complete := false
var running := false
signal finished
func build(cabin: Node3D, extras: Array=[]) -> void:
 position=Vector3(10000,10000,10000)
 camera=Camera3D.new()
 camera.projection=Camera3D.PROJECTION_ORTHOGONAL
 camera.size=20
 camera.far=30
 add_child(camera)
 var meshes:=cabin.find_children("*","MeshInstance3D",true,false)
 for extra in extras:meshes.append_array(extra.find_children("*","MeshInstance3D",true,false))
 # Fit every swatch; the old fixed rows could silently fall outside the view.
 var surface_count:=0
 for source in meshes:surface_count+=source.mesh.get_surface_count()
 var columns:=ceili(sqrt(float(surface_count)))
 var rows:=ceili(float(surface_count)/columns)
 camera.size=maxf(float(columns),float(rows))*0.9+2.0
 var index:=0
 for source in meshes:
  for surface in range(source.mesh.get_surface_count()):
   var swatch:=MeshInstance3D.new()
   # Retain the exact vertex format (including the directional bake channel).
   var mesh:=ArrayMesh.new()
   mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,source.mesh.surface_get_arrays(surface),[],{},source.mesh.surface_get_format(surface) if source.mesh is ArrayMesh else 0)
   swatch.mesh=mesh
   swatch.material_override=source.get_active_material(surface)
   swatch.layers=source.layers
   swatch.cast_shadow=source.cast_shadow
   var bounds:=mesh.get_aabb()
   var factor:=0.6/maxf(0.001,maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z)))
   swatch.scale=Vector3.ONE*factor
   swatch.position=Vector3((index%columns-(columns-1)*0.5)*0.85,(floori(float(index)/columns)-(rows-1)*0.5)*0.85,-8)-bounds.get_center()*factor
   swatch.ignore_occlusion_culling=true
   add_child(swatch)
   index+=1
 for source in cabin.lamps:
  var lamp: Light3D=source.duplicate()
  lamp.position=Vector3(0,0,-4)
  lamp.rotation=Vector3.ZERO
  if lamp is OmniLight3D:lamp.omni_range=20
  if lamp is SpotLight3D:
   lamp.spot_range=20
   lamp.spot_angle=85
  add_child(lamp)
 curtain=CanvasLayer.new()
 curtain.layer=100
 var black:=ColorRect.new()
 black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 black.color=Color.BLACK
 black.mouse_filter=Control.MOUSE_FILTER_IGNORE
 curtain.add_child(black)
 add_child(curtain)
 curtain.hide()
 hide()
func warm() -> void:
 if complete:return
 if running:
  await finished
  return
 running=true
 var previous:=get_viewport().get_camera_3d()
 show()
 curtain.show()
 camera.make_current()
 get_node("/root/PerfEvents").mark("cabin_prewarm_start")
 # Six directions expose horizontal faces too (the compass is edge-on in
 # both old yaw-only poses), including reversed lid lining and glass.
 for rotation_value in [Vector3.ZERO,Vector3(0,PI,0),Vector3(PI/2,0,0),Vector3(-PI/2,0,0),Vector3(0,PI/2,0),Vector3(0,-PI/2,0)]:
  for child in get_children():
   if child is MeshInstance3D:child.rotation=rotation_value
  for frame in range(2):
   if DisplayServer.get_name()=="headless":await get_tree().process_frame
   else:await RenderingServer.frame_post_draw
 hide()
 curtain.hide()
 if is_instance_valid(previous):previous.make_current()
 else:camera.clear_current()
 complete=true
 running=false
 get_node("/root/PerfEvents").mark("cabin_prewarm_end")
 finished.emit()
