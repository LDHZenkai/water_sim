extends Node3D
const FLOOR := 6.38
const FRONT := -9.25
const BACK := -12.12
var shell_vertices := PackedVector3Array()
var beam_vertices := PackedVector3Array()
var props: Array[Node3D] = []
var environment: Environment
var base_exposure := 1.0
var doors: Array[Node3D] = []
var player: CharacterBody3D
var prompt: Label
var base_ambient := 1.0
var settings := {}
var shell: Array[MeshInstance3D] = []
var lamps: Array[Light3D] = []
var roof: Array = []
var plank: ORMMaterial3D
var deck_material: ORMMaterial3D
var beam_material: ORMMaterial3D
func build(ship: AnimatableBody3D, env: Environment, leaves: Array[Node3D], actor: CharacterBody3D, _knees: Mesh) -> void:
 assert(not is_inside_tree(), "Cabin geometry must be finalized before scenario assignment")
 environment=env
 base_exposure=env.tonemap_exposure
 base_ambient=env.ambient_light_energy
 settings=actor.get_node("/root/Quality").effective
 doors=leaves
 player=actor
 plank=wood("dark_wooden_planks")
 deck_material=wood("dark_wooden_planks")
 deck_material.albedo_color=Color(0.65,0.59,0.49)
 beam_material=wood("dark_wooden_planks")
 beam_material.albedo_color=Color(0.48,0.41,0.32)
 # Sloping sides follow the taper of the upper stern castle.
 var a:=Vector3(FRONT,FLOOR,-1.03)
 var b:=Vector3(FRONT,FLOOR,1.22)
 var c:=Vector3(BACK,FLOOR,0.92)
 var d:=Vector3(BACK,FLOOR,-0.73)
 panel(ship,"Floor",[a,b,c,d],deck_material)
 # Independently sampled from the source hull, 10 mm beneath its underside.
 roof=JSON.parse_string(FileAccess.get_file_as_string("res://exploration/generated/deckhead.json"))
 for i in range(roof.size()-1):
  for j in range(roof[i].size()-1):
   var points: Array=[]
   for index in [Vector2i(i,j),Vector2i(i+1,j),Vector2i(i+1,j+1),Vector2i(i,j+1)]:
    var p: Array=roof[index.x][index.y]
    points.append(Vector3(p[0],p[1],p[2]))
   panel(ship,"Ceiling",points,plank)
 for i in range(roof.size()-1):
  for j in [0,8]:
   var p: Array=roof[i][j]
   var q: Array=roof[i+1][j]
   panel(ship,"SideWall",[Vector3(p[0],FLOOR,p[2]),Vector3(q[0],FLOOR,q[2]),Vector3(q[0],q[1],q[2]),Vector3(p[0],p[1],p[2])],plank)
 # Complete inner bulkhead with two shallow arched apertures matching the
 # extracted leaves. The source wall is single-sided, so it cannot be the lining.
 for span in [Vector2(-1.03,-1.01),Vector2(-0.371,0.565),Vector2(1.204,1.22)]:
  panel(ship,"FrontLining",[Vector3(FRONT,FLOOR,span.x),Vector3(FRONT,8.18,span.x),Vector3(FRONT,8.18,span.y),Vector3(FRONT,FLOOR,span.y)],plank)
 for center in [-0.6905,0.8845]:
  for i in range(12):
   var z0: float=center-0.3195+float(i)/12.0*0.639
   var z1: float=center-0.3195+float(i+1)/12.0*0.639
   var y0:=7.82+0.18*sqrt(maxf(0.0,1.0-pow((z0-center)/0.3195,2)))
   var y1:=7.82+0.18*sqrt(maxf(0.0,1.0-pow((z1-center)/0.3195,2)))
   panel(ship,"ArchLining",[Vector3(FRONT,y0,z0),Vector3(FRONT,8.18,z0),Vector3(FRONT,8.18,z1),Vector3(FRONT,y1,z1)],plank)
 # Two stern lights, with four-sided reveals and narrow glazing bars.
 box(ship,"SternSill",Vector3(BACK,6.75,0.095),Vector3(0.08,0.74,1.65),plank)
 box(ship,"SternHeader",Vector3(BACK,8.37,0.095),Vector3(0.08,0.66,1.65),plank)
 for z in [-0.735,0.095,0.925]:
  box(ship,"WindowPost",Vector3(BACK,7.57,z),Vector3(0.10,0.9,0.075),beam_material)
 for z in [-0.32,0.51]:
  for y in [7.14,8.0]:box(ship,"WindowReveal",Vector3(BACK-0.06,y,z),Vector3(0.20,0.07,0.74),beam_material)
  box(ship,"WindowMullion",Vector3(BACK-0.06,7.57,z),Vector3(0.07,0.86,0.025),beam_material)
  box(ship,"WindowTransom",Vector3(BACK-0.06,7.57,z),Vector3(0.07,0.025,0.74),beam_material)
 # Thin, slightly dirty glass. No refraction or screen sampling.
 for z in [-0.32,0.51]:
  var glass:=MeshInstance3D.new()
  var pane:=QuadMesh.new()
  pane.size=Vector2(0.74,0.84)
  glass.mesh=pane
  glass.position=Vector3(BACK-0.055,7.57,z)
  glass.rotation.y=PI/2
  glass.layers=2
  var material:=StandardMaterial3D.new()
  material.albedo_color=Color(0.35,0.29,0.17,0.10)
  material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
  material.cull_mode=BaseMaterial3D.CULL_DISABLED
  material.roughness=0.32
  material.metallic_specular=0.25
  glass.material_override=material
  glass.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  add_child(glass)
  shell.append(glass)
 # Only aft beams: the forward deckhead cannot provide 1.85 m with a beam.
 for x in [-11.35,-11.85]:
  var limits:=side_limits(x)
  for j in range(8):
   var z0:=lerpf(limits.x,limits.y,float(j)/8)
   var z1:=lerpf(limits.x,limits.y,float(j+1)/8)
   var p:=Vector3(x-0.11,roof_height(x-0.11,z0),z0)
   var q:=Vector3(x+0.11,roof_height(x+0.11,z0),z0)
   var r:=Vector3(x+0.11,roof_height(x+0.11,z1),z1)
   var t:=Vector3(x-0.11,roof_height(x-0.11,z1),z1)
   var drop:=Vector3.UP*0.10
   panel(ship,"BeamBottom",[p-drop,q-drop,r-drop,t-drop],plank)
   panel(ship,"BeamForward",[q-drop,q,r,r-drop],plank)
   panel(ship,"BeamAft",[p,p-drop,t-drop,t],plank)
 panel(ship,"DoorwayFloor",[Vector3(-8.85,FLOOR,-1.03),Vector3(-8.85,FLOOR,1.22),b,a],deck_material)
 # Continuous sloped wooden cornices cover the source hull's inner rail strips.
 for i in range(roof.size()-1):
  for side in [0,8]:
   var p: Array=roof[i][side]
   var q: Array=roof[i+1][side]
   var inward:=0.15 if side==0 else -0.15
   var a0:=Vector3(p[0],p[1]+0.015,p[2]+inward)
   var b0:=Vector3(q[0],q[1]+0.015,q[2]+inward)
   panel(ship,"CorniceFace",[a0,b0,b0-Vector3.UP*0.30,a0-Vector3.UP*0.30],plank)
   panel(ship,"CorniceBottom",[a0-Vector3.UP*0.30,b0-Vector3.UP*0.30,Vector3(q[0],q[1]-0.285,q[2]),Vector3(p[0],p[1]-0.285,p[2])],plank)
 # Diagonal hanging knees: triangular brackets, flush to the beam and lining.
 for x in [-11.35,-11.85]:
  var limits:=side_limits(x)
  for z in [limits.x,limits.y]:
   var inward: float=-1.0 if z>0 else 1.0
   var top:=roof_height(x,z)-0.085
   var points: Array=[Vector3(x-0.09,top,z),Vector3(x-0.09,top-0.45,z),Vector3(x-0.09,top,z+inward*0.32)]
   for side in [-1.0,1.0]:
    var offset:=Vector3(0.18 if side>0 else 0.0,0,0)
    panel(ship,"KneeFace",[points[0]+offset,points[1]+offset,points[2]+offset],plank)
   panel(ship,"KneeDiagonal",[points[1],points[1]+Vector3.RIGHT*0.18,points[2]+Vector3.RIGHT*0.18,points[2]],plank)
 furnish()
 var candle:=OmniLight3D.new()
 candle.name="CandleLight"
 candle.position=Vector3(-10.85,7.39,0.55)
 candle.light_color=Color(1.0,0.57,0.25)
 candle.light_energy=0.75
 candle.omni_range=1.35
 candle.omni_attenuation=2.0
 add_lamp(candle)
 if settings["cabin-bake"]=="off":add_window_fill()
 merge_shell()
 set_meta("bake_inputs",preload("res://exploration/cabin_bake.gd").fingerprint(self))
 if settings["cabin-bake"]=="on":
  preload("res://exploration/cabin_bake.gd").apply(self)
  for mesh in shell:mesh.layers=4
 configure_small_props()
 if settings["cabin-occluder"]=="on":
  actor.get_viewport().use_occlusion_culling=true
  for data in [[Vector3(FRONT,7.35,0.095),Vector3(0.05,1.9,0.85)],[Vector3(-10.7,7.4,-0.9),Vector3(2.7,1.9,0.03)],[Vector3(-10.7,7.4,1.08),Vector3(2.7,1.9,0.03)]]:
   var occluder:=OccluderInstance3D.new()
   var shape:=BoxOccluder3D.new()
   shape.size=data[1]
   occluder.occluder=shape
   occluder.position=data[0]
   add_child(occluder)
 var ui:=CanvasLayer.new()
 add_child(ui)
 prompt=Label.new()
 prompt.position=Vector2(30,80)
 ui.add_child(prompt)

func wood(_id: String) -> ORMMaterial3D:
 var m:=ORMMaterial3D.new()
 m.albedo_texture=load("res://exploration/generated/planks_diff.jpg")
 m.normal_enabled=true
 m.normal_texture=load("res://exploration/generated/planks_nor_gl.jpg")
 m.orm_texture=load("res://exploration/generated/planks_orm.png")
 m.uv1_triplanar=settings["cabin-triplanar"]=="on"
 m.albedo_color=Color(0.78,0.71,0.60)
 m.metallic_specular=0.25
 m.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
 return m

func side_limits(x: float) -> Vector2:
 var t:=inverse_lerp(FRONT,BACK,x)
 return Vector2(lerpf(-1.03,-0.73,t),lerpf(1.22,0.92,t))

func roof_height(x: float,z: float) -> float:
 var row:=0
 while row<roof.size()-2 and x<float(roof[row+1][0][0]):row+=1
 var blend:=clampf(inverse_lerp(roof[row][0][0],roof[row+1][0][0],x),0,1)
 var limits:=side_limits(x)
 var column:=clampf(inverse_lerp(limits.x,limits.y,z)*8,0,8)
 var j:=mini(7,int(column))
 var a:=lerpf(roof[row][j][1],roof[row][j+1][1],column-j)
 var b:=lerpf(roof[row+1][j][1],roof[row+1][j+1][1],column-j)
 return lerpf(a,b,blend)

func add_lamp(light: Light3D) -> void:
 light.light_cull_mask=2
 light.shadow_enabled=false
 add_child(light)
 lamps.append(light)
 light.visible=settings["cabin-lights"]=="on"

func panel(ship: AnimatableBody3D,label: String,points: Array,material: Material) -> void:
 var st:=SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var u: Vector3=(points[1]-points[0]).normalized()
 var normal: Vector3=(points[1]-points[0]).cross(points[points.size()-1]-points[0]).normalized()
 var v:=normal.cross(u)
 for i in ([0,1,2,2,1,0] if points.size()==3 else [0,1,2,0,2,3,2,1,0,3,2,0]):
  var offset: Vector3=points[i]-points[0]
  st.set_uv(Vector2(offset.dot(u),offset.dot(v))*0.7)
  st.add_vertex(points[i])
  shell_vertices.append(points[i])
  if label.begins_with("Beam"):beam_vertices.append(points[i])
 st.generate_normals()
 st.generate_tangents()
 # append_from must receive indexed panels like the box/primitive meshes.
 # Mixing unindexed panels with indexed boxes drops panels from the merged
 # draw's index buffer, even though their vertices remain in its arrays.
 st.index()
 var visual:=MeshInstance3D.new()
 visual.name=label
 visual.mesh=st.commit()
 visual.material_override=material
 visual.layers=2
 visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON if settings["cabin-shadows"]=="on" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 add_child(visual)
 shell.append(visual)
 var collision:=CollisionShape3D.new()
 collision.name="Cabin"+label
 collision.shape=visual.mesh.create_trimesh_shape()
 ship.add_child(collision)

func box(ship: AnimatableBody3D,label: String,center: Vector3,size: Vector3,material: Material) -> void:
 var visual:=MeshInstance3D.new()
 visual.name=label
 var mesh:=BoxMesh.new()
 mesh.size=size
 var arrays:=mesh.surface_get_arrays(0)
 var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
 var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
 var uv:=PackedVector2Array()
 for i in range(vertices.size()):
  var p:=vertices[i]+center
  var n:=normals[i].abs()
  uv.append((Vector2(p.x,p.z) if n.y>0.5 else (Vector2(p.x,p.y) if n.z>0.5 else Vector2(p.z,p.y)))*0.7)
 arrays[Mesh.ARRAY_TEX_UV]=uv
 var mapped:=ArrayMesh.new()
 mapped.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 visual.mesh=mapped
 visual.position=center
 visual.material_override=material
 visual.layers=2
 visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON if settings["cabin-shadows"]=="on" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 add_child(visual)
 shell.append(visual)
 for vertex in mesh.get_faces():shell_vertices.append(center+vertex)
 var collision:=CollisionShape3D.new()
 var shape:=BoxShape3D.new()
 shape.size=size
 collision.shape=shape
 collision.position=center
 collision.name="Cabin"+label
 ship.add_child(collision)

func prop(id: String,location: Vector3,yaw: float=0.0,height: float=0.0,variant: int=-1) -> Node3D:
 var model: Node3D=load("res://exploration/generated/"+id+".scn").instantiate()
 var holder:=Node3D.new()
 holder.name=id
 add_child(holder)
 holder.add_child(model)
 # Some Poly Haven files are a row of alternatives, not one assembled prop.
 var nodes:=model.find_children("*","MeshInstance3D")
 if variant>=0:
  for i in range(nodes.size()):
   if i!=variant:nodes[i].free()
 var bounds:=AABB()
 var first:=true
 for node in model.find_children("*","MeshInstance3D"):
  var b: AABB=(relative_pose(node,model))*node.get_aabb()
  bounds=b if first else bounds.merge(b)
  first=false
  node.layers=2
  node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON if settings["cabin-shadows"]=="on" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 # Furniture is calibrated to an explicit usable height; small props remain 1:1.
 var factor:=height/bounds.size.y if height>0 else 1.0
 model.scale=Vector3.ONE*factor
 model.position=Vector3(-bounds.get_center().x,-bounds.position.y,-bounds.get_center().z)*factor
 holder.position=location
 holder.rotation.y=yaw
 holder.set_meta("fitted_size",bounds.size*factor)
 holder.set_meta("native_scale",factor)
 if id=="treasure_chest":
  var lid: MeshInstance3D=holder.find_child("treasure_chest_lid",true,false)
  var lock: MeshInstance3D=holder.find_child("treasure_chest_lock",true,false)
  var tool:=SurfaceTool.new()
  tool.begin(Mesh.PRIMITIVE_TRIANGLES)
  tool.append_from(lid.mesh,0,Transform3D.IDENTITY)
  # Duplicate the wooden canopy inward with reversed winding/normals. Keep
  # the original atlas and cull_back; hardware still draws one face per side.
  var arrays:=lid.mesh.surface_get_arrays(0)
  var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
  var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
  var uvs: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
  var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
  for i in range(0,indices.size(),3):
   # Only the curved canopy needs a lining; do not duplicate rim/hasp metal.
   if (normals[indices[i]]+normals[indices[i+1]]+normals[indices[i+2]]).y<0.6:continue
   for j in [2,1,0]:
    var k:=indices[i+j]
    tool.set_normal(-normals[k])
    tool.set_uv(uvs[k])
    tool.add_vertex(vertices[k]-normals[k]*0.003)
  tool.append_from(lock.mesh,0,relative_pose(lid,holder).affine_inverse()*relative_pose(lock,holder))
  var material:=lid.get_active_material(0)
  lid.mesh=tool.commit()
  lid.material_override=material
  lock.free()
 if id=="seadogs_compass":
  holder.find_child("*lid*",true,false).free()
 merge_prop_surfaces(holder)
 if id=="wooden_lantern_01":
  for mesh in holder.find_children("*","MeshInstance3D",true,false):mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 props.append(holder)
 holder.visible=settings["cabin-props"]!="off" and not (settings["cabin-props"]=="lite" and id in ["wooden_candlestick","treasure_chest"])
 return holder

func furnish() -> void:
 prop("wooden_lantern_01",Vector3(-9.65,FLOOR,0.68),0,0.40)
 prop("round_wooden_table_01",Vector3(-10.85,FLOOR,0.30),0,0.75)
 prop("seadogs_compass",Vector3(-10.65,FLOOR+0.75,0.39))
 prop("wooden_candlestick",Vector3(-10.85,FLOOR+0.75,0.55))
 prop("brass_candleholders",Vector3(-11.1,FLOOR+0.75,0.24),0,0,1)
 prop("treasure_chest",Vector3(-11.51,FLOOR,-0.25),PI/2)
 # A 1.55 m cabinet sized as ship furniture, with its back safely inboard.
 prop("GothicCabinet_01",Vector3(-9.95,FLOOR,-0.43),0,1.55)
 prop("wooden_stool_01",Vector3(-11.72,FLOOR,0.60))
 prop("wine_bottles_01",Vector3(-10.92,FLOOR+0.75,0.05),0,0,1)
 prop("jug_01",Vector3(-10.67,FLOOR+0.75,0.04))
 var saber:=prop("wooden_handle_saber",Vector3(-10.6,7.1,-0.85),PI/2)
 saber.position.z=side_limits(-10.6).x+0.035
 for y in [7.20,7.74]:
  var peg:=MeshInstance3D.new()
  var peg_mesh:=CylinderMesh.new()
  peg_mesh.top_radius=0.009
  peg_mesh.bottom_radius=0.012
  peg_mesh.height=0.06
  peg_mesh.radial_segments=8
  peg.mesh=peg_mesh
  peg.position=Vector3(-10.6,y,side_limits(-10.6).x+0.025)
  peg.rotation.x=PI/2
  peg.material_override=beam_material
  add_child(peg)
  shell.append(peg)
  for vertex in peg_mesh.get_faces():shell_vertices.append(peg.transform*vertex)
 var mat:=MeshInstance3D.new()
 mat.name="AllardChart"
 var plane:=PlaneMesh.new()
 plane.size=Vector2(0.42,0.30)
 mat.mesh=plane
 mat.position=Vector3(-10.77,FLOOR+0.754,0.28)
 var paper:=StandardMaterial3D.new()
 paper.albedo_texture=load("res://assets/public_domain/van_der_hagen_1690_british_isles.jpg")
 paper.albedo_color=Color(0.58,0.49,0.34)
 paper.roughness=0.85
 paper.metallic_specular=0.0
 mat.material_override=paper
 mat.layers=2
 mat.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 add_child(mat)
 props.append(mat)
 mat.visible=settings["cabin-props"]!="off"
 var flame:=MeshInstance3D.new()
 flame.name="CandleFlame"
 var flame_mesh:=QuadMesh.new()
 flame_mesh.size=Vector2(0.022,0.047)
 flame.mesh=flame_mesh
 flame.position=Vector3(-10.85,FLOOR+0.75+0.242,0.55)
 flame.rotation.y=PI/2
 flame.layers=2
 var flame_material:=ShaderMaterial.new()
 flame_material.shader=preload("res://exploration/candle_flame.gdshader")
 flame.material_override=flame_material
 flame.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 add_child(flame)
 props.append(flame)
 flame.visible=settings["cabin-lights"]=="on" and settings["cabin-props"]=="on"
 # Compass weights the forward corner of the chart.

func merge_shell() -> void:
 var groups := {}
 for visual in shell:
  var mat: Material=visual.material_override
  if not groups.has(mat):
   groups[mat]=SurfaceTool.new()
   groups[mat].begin(Mesh.PRIMITIVE_TRIANGLES)
  groups[mat].append_from(visual.mesh,0,visual.transform)
  visual.free()
 shell.clear()
 for mat in groups:
  var visual:=MeshInstance3D.new()
  visual.name="CabinShell"
  visual.mesh=groups[mat].commit()
  visual.material_override=mat
  visual.layers=2
  visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON if settings["cabin-shadows"]=="on" and not (mat is StandardMaterial3D and mat.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  add_child(visual)
  shell.append(visual)
  visual.visible=settings["cabin-shell"]=="on"

func update_visibility(eye: Vector3) -> void:
 # Inside always visible. Outside, only an open/animating door near its portal
 # can reveal the cabin. Shut exterior views submit no cabin geometry/lights.
 var show_interior:=contains(eye-Vector3.UP*1.4)
 for door in doors:
  if (door.opened or absf(door.angle)>0.001) and eye.distance_to(Vector3(-8.8,7.3,door.position.z))<4.5:
   show_interior=true
 if visible!=show_interior:
  get_node("/root/PerfEvents").mark("interior_visibility", {"visible":show_interior})
  visible=show_interior

func contains(p: Vector3) -> bool:
 return p.x<FRONT and p.x>BACK and p.y>FLOOR-0.2 and p.y<8.72 and absf(p.z-0.095)<1.15
func exposure_at(p: Vector3) -> float:
 var amount:=smoothstep(FRONT+0.65,FRONT-0.65,p.x) if p.x>BACK-0.2 and p.y<8.2 and p.y>FLOOR-0.3 and absf(p.z-0.095)<1.3 else 0.0
 return base_exposure*lerpf(1.0,1.05,amount)
func _process(delta: float) -> void:
 if environment==null:return
 var camera:=get_viewport().get_camera_3d()
 if camera:
  var local_eye: Vector3=get_parent().to_local(camera.global_position)
  update_visibility(local_eye)
  if visible:update_prop_lod(camera.global_position)
  var inside:=contains(local_eye-Vector3.UP*1.4)
  environment.ambient_light_energy=base_ambient*(0.2 if inside else 1.0)
  var desired:=exposure_at(get_parent().to_local(camera.global_position)-Vector3.UP*1.65)
  var frozen: bool=get_node("/root/SimClock").frozen
  environment.tonemap_exposure=desired if frozen else lerpf(environment.tonemap_exposure,desired,1.0-exp(-delta*3.0))
 var door:=nearest_door()
 prompt.text="E — open cabin door · auto-duck doorway" if door!=null and not door.opened else ("E — close cabin door · auto-duck doorway" if door!=null else "")
func nearest_door() -> Node3D:
 if not player.input_enabled:return null
 var closest: Node3D
 var distance:=1.8
 for door in doors:
  var candidate: float=player.head.global_position.distance_to(door.interaction_point())
  var looking: Vector3=door.interaction_point()-player.camera.global_position
  if (-player.camera.global_basis.z).dot(looking.normalized())<0.65:continue
  if candidate<distance:
   closest=door
   distance=candidate
 return closest
func _unhandled_input(event: InputEvent) -> void:
 if event.is_action_pressed("interact"):
  var door:=nearest_door()
  if door!=null:door.interact()

func add_window_fill() -> void:
 var fill:=SpotLight3D.new()
 fill.name="SternWindowFill"
 fill.position=Vector3(-12.0,7.8,0.095)
 add_lamp(fill)
 fill.basis=Basis.looking_at(Vector3(-9.3,7.0,0.095)-fill.position)
 fill.light_color=Color(1.0,0.72,0.40)
 fill.light_energy=1.6
 fill.spot_range=3.4
 fill.spot_angle=72
 fill.spot_attenuation=1.5

var small_materials: Array = []
func configure_small_props() -> void:
 for holder in props:
  var size: Vector3=holder.get_meta("fitted_size",Vector3.ONE)
  if holder.name=="AllardChart":size=Vector3(0.42,0,0.30)
  var meshes: Array=holder.find_children("*","MeshInstance3D",true,false)
  if holder is MeshInstance3D:meshes.append(holder)
  for mesh in meshes:
   if maxf(size.x,maxf(size.y,size.z))>=0.5:
    if settings["cabin-bake"]=="on":mesh.layers=4
    continue
   for s in range(mesh.mesh.get_surface_count()):
    var source: Material=mesh.get_active_material(s)
    if source is BaseMaterial3D and source.normal_enabled:
     var material: BaseMaterial3D=source.duplicate()
     if mesh.material_override!=null:mesh.material_override=material
     else:mesh.set_surface_override_material(s,material)
     small_materials.append([mesh,material])

func update_prop_lod(eye: Vector3) -> void:
 for entry in small_materials:
  var mesh: MeshInstance3D=entry[0]
  var material: BaseMaterial3D=entry[1]
  # Keep the shader feature stable; fade normal strength without new pipelines.
  var strength:=1.0-smoothstep(2.5,3.0,eye.distance_to(mesh.global_position))
  if not is_equal_approx(material.normal_scale,strength):material.normal_scale=strength

func material_key(material: Material) -> String:
 # Generated prop materials can be equivalent copies, not the same Resource.
 var values: Dictionary={"class":material.get_class()}
 for property in material.get_property_list():
  var key: String=property.name
  if not (property.usage & PROPERTY_USAGE_STORAGE) or key.begins_with("resource_"):continue
  var value: Variant=material.get(key)
  if value is Resource:
   values[key]=value.resource_path if not value.resource_path.is_empty() else value.get_instance_id()
  else:values[key]=value
 return var_to_str(values)

func merge_prop_surfaces(holder: Node3D) -> void:
 var meshes:=holder.find_children("*","MeshInstance3D",true,false)
 var groups: Dictionary={}
 var surface_count:=0
 for mesh in meshes:
  if moving_part(mesh,holder):continue
  for s in range(mesh.mesh.get_surface_count()):
   var material: Material=mesh.get_active_material(s)
   var key:=material_key(material)
   surface_count+=1
   if not groups.has(key):groups[key]={"material":material,"entries":[]}
   groups[key].entries.append([mesh,s])
 if groups.size()==surface_count:return
 for key in groups:
  var st:=SurfaceTool.new()
  st.begin(Mesh.PRIMITIVE_TRIANGLES)
  for entry in groups[key].entries:
   var mesh: MeshInstance3D=entry[0]
   st.append_from(mesh.mesh,entry[1],relative_pose(mesh,holder))
  var merged:=MeshInstance3D.new()
  merged.name="StaticMaterialBatch"
  merged.mesh=st.commit()
  merged.material_override=groups[key].material
  merged.layers=2
  merged.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON if settings["cabin-shadows"]=="on" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  holder.add_child(merged)
 for mesh in meshes:
  if not moving_part(mesh,holder):mesh.free()

static func relative_pose(node: Node3D, ancestor: Node3D) -> Transform3D:
 var pose:=Transform3D.IDENTITY
 while node!=ancestor:
  pose=node.transform*pose
  node=node.get_parent()
 return pose

func moving_part(mesh: Node3D, holder: Node3D) -> bool:
 if holder.name=="seadogs_compass":return "needle" in str(mesh.name) or "lid" in str(mesh.name)
 if holder.name=="treasure_chest":
  var lid:=holder.find_child("*lid*",true,false)
  return mesh==lid or (lid!=null and lid.is_ancestor_of(mesh))
 return false
