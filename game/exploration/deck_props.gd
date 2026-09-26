extends Node3D
var props: Array[Node3D]=[]
var lantern: Node3D
var flame: MeshInstance3D
var lamps: Array=[]
var timber: ORMMaterial3D
var rope_tool: SurfaceTool
var rope_material: StandardMaterial3D
func build(ship: Node3D,settings: Dictionary) -> void:
 visible=settings["deck-props"]=="on"
 timber=ORMMaterial3D.new()
 timber.albedo_texture=load("res://exploration/generated/planks_diff.jpg")
 timber.normal_enabled=true
 timber.normal_texture=load("res://exploration/generated/planks_nor_gl.jpg")
 timber.orm_texture=load("res://exploration/generated/planks_orm.png")
 timber.albedo_color=Color(0.48,0.41,0.32)
 timber.uv1_triplanar=true
 timber.uv1_scale=Vector3.ONE*3
 timber.metallic_specular=0.2
 wood_cradles(ship)
 rope_tool=SurfaceTool.new()
 rope_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
 rope_material=StandardMaterial3D.new()
 rope_material.albedo_color=Color(0.25,0.19,0.11)
 rope_material.roughness=1
 for x in [3.88,6.42]:
  for side in [-1.0,1.0]:
   var cannon:=prop("cannon_01",Vector3(x,2.78,side*2.85),0 if side>0 else PI,0.75)
   solid(ship,cannon.position+Vector3(0,0.25,0),Vector3(0.7,0.5,0.65),visible)
 for offset in [Vector3.ZERO,Vector3(0.55,0,0),Vector3(0.25,0,0.53)]:
  var barrel:=prop("wooden_barrels_01",Vector3(-3.3,4.46,-1.25)+offset,0,0.65,0)
  solid(ship,barrel.position+Vector3.UP*0.3,Vector3(0.48,0.6,0.48),visible)
  lash(barrel.position+Vector3.UP*0.35,0.26)
 lash(Vector3(-3.03,4.81,-1.02),0.58)
 # Foremast cluster, outboard of the central ladder approach and shroud routes.
 for offset in [Vector3(0,0,0),Vector3(0.52,0.085,0),Vector3(0.26,0.054,0.48)]:
  var barrel:=prop("wooden_barrels_01",Vector3(8.9,4.321,-0.9)+offset,0,0.62,0)
  solid(ship,barrel.position+Vector3.UP*0.3,Vector3(0.46,0.6,0.46),visible)
  lash(barrel.position+Vector3.UP*0.23,0.25)
  lash(barrel.position+Vector3.UP*0.46,0.25)
 for y in [4.64,4.84]:lash(Vector3(9.16,y,-0.69),0.56)
 for y in [0.0,0.35]:
  var crate:=prop("wooden_crate_01",Vector3(5.4,2.82,1.0)+Vector3.UP*y,0,0.35)
  solid(ship,crate.position+Vector3.UP*0.175,Vector3(0.8,0.35,0.41),visible)
 for z in [0.88,1.12]:line(Vector3(4.99,2.84,z),Vector3(4.99,3.55,z));line(Vector3(4.99,3.55,z),Vector3(5.81,3.55,z));line(Vector3(5.81,3.55,z),Vector3(5.81,2.84,z))
 prop("wooden_bucket_01",Vector3(5.3,2.84,-2.8),0,0.42)
 for radius in [0.18,0.21,0.24,0.27]:lash(Vector3(5.2,2.86,-2.4),radius)
 lantern=prop("wooden_lantern_01",Vector3(-11.9,9.13,0.65),0,0.43)
 flame=MeshInstance3D.new()
 var quad:=QuadMesh.new()
 quad.size=Vector2(0.035,0.08)
 flame.mesh=quad
 flame.position=lantern.position+Vector3.UP*0.2
 flame.rotation.y=PI/2
 var mat:=ShaderMaterial.new()
 mat.shader=preload("res://exploration/candle_flame.gdshader")
 flame.material_override=mat
 flame.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 add_child(flame)
 line(Vector3(-11.9,9.56,0.65),Vector3(-11.9,9.58,0.78))
 var rope:=MeshInstance3D.new()
 rope.name="CargoLashingsAndCoils"
 rope.mesh=rope_tool.commit()
 rope.material_override=rope_material
 rope.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 add_child(rope)
 # Emissive only: no deck punctual lights or lamp pairing cost.
func prop(id: String,p: Vector3,yaw: float,height: float,variant: int=-1) -> Node3D:
 var holder:=Node3D.new()
 holder.name=id
 var model: Node3D=load("res://exploration/generated/"+id+".scn").instantiate()
 holder.add_child(model)
 if id=="cannon_01":
  var balls:=model.find_children("*ball*","MeshInstance3D",true,false)
  for i in range(balls.size()):balls[i].position=Vector3(-0.65,0.09,-0.20+i*0.20)
  # Close-fitting timber garland, assembled in source-model coordinates.
  for z in [-0.32,0.32]:wood_box(model,Vector3(-0.65,0.06,z),Vector3(0.26,0.12,0.045))
  for x in [-0.77,-0.53]:wood_box(model,Vector3(x,0.06,0),Vector3(0.045,0.12,0.68))
 var meshes:=model.find_children("*","MeshInstance3D",true,false)
 if variant>=0:
  for i in range(meshes.size()):
   if i!=variant:meshes[i].free()
 var bounds:=AABB()
 var first:=true
 for mesh in model.find_children("*","MeshInstance3D",true,false):
  var box: AABB=preload("res://exploration/cabin.gd").relative_pose(mesh,model)*mesh.get_aabb()
  bounds=box if first else bounds.merge(box)
  first=false
  mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 var scale_factor:=height/bounds.size.y
 model.scale=Vector3.ONE*scale_factor
 model.position=Vector3(-bounds.get_center().x,-bounds.position.y,-bounds.get_center().z)*scale_factor
 holder.position=p
 holder.rotation.y=yaw
 add_child(holder)
 props.append(holder)
 return holder
func solid(ship: Node3D,p: Vector3,size: Vector3,enabled: bool) -> void:
 var node:=CollisionShape3D.new()
 var box:=BoxShape3D.new()
 box.size=size
 node.shape=box
 node.position=p
 node.disabled=not enabled
 ship.add_child(node)
func lash(p: Vector3,radius: float) -> void:
 for i in range(24):
  var a:=TAU*i/24.0
  var b:=TAU*(i+1)/24.0
  line(p+Vector3(cos(a)*radius,0,sin(a)*radius),p+Vector3(cos(b)*radius,0,sin(b)*radius))
func line(a: Vector3,b: Vector3) -> void:
 var cylinder:=CylinderMesh.new()
 cylinder.top_radius=0.011
 cylinder.bottom_radius=0.011
 cylinder.height=a.distance_to(b)
 cylinder.radial_segments=6
 cylinder.rings=1
 var pose:=Transform3D(Basis(Quaternion(Vector3.UP,(b-a).normalized())),(a+b)*0.5)
 rope_tool.append_from(cylinder,0,pose)

func wood_box(parent: Node3D,p: Vector3,size: Vector3) -> void:
 var node:=MeshInstance3D.new()
 var box:=BoxMesh.new()
 box.size=size
 node.mesh=box
 node.position=p
 node.material_override=timber
 node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 parent.add_child(node)

func wood_cradles(ship: Node3D) -> void:
 # Re-skin the source pinnace supports using their actual triangles, preserving
 # the V cut-outs against the boat. Two millimetres avoid coplanar flicker.
 var tool:=SurfaceTool.new()
 tool.begin(Mesh.PRIMITIVE_TRIANGLES)
 for hull in ship.get_node("Model").find_children("*","MeshInstance3D",true,false):
  if "hull" not in str(hull.name):continue
  var arrays: Array=hull.mesh.surface_get_arrays(0)
  var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
  var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
  var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
  for i in range(0,indices.size(),3):
   var selected:=true
   for j in range(3):
    var v:=vertices[indices[i+j]]
    selected=selected and ((v.x>=4.15 and v.x<=4.215) or (v.x>=6.549 and v.x<=6.616)) and v.y>=2.878 and v.y<=3.458 and v.z>=-0.395 and v.z<=0.604
   if not selected:continue
   for j in range(3):
    var k:=indices[i+j]
    tool.set_normal(normals[k])
    tool.set_uv(Vector2(vertices[k].z,vertices[k].y)*3)
    tool.add_vertex(vertices[k]+normals[k]*0.002)
 var mesh:=MeshInstance3D.new()
 mesh.name="WoodenPinnaceCradles"
 mesh.mesh=tool.commit()
 mesh.material_override=timber
 mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 add_child(mesh)
