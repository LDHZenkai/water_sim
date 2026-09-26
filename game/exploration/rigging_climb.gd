extends Node3D
## Ship-local oriented capsules follow measured ratline bands in the source mesh.
var routes: Array[Dictionary]=[]
var enabled:=true
var gates: Array=[]
func build(ship: AnimatableBody3D, model: Node3D, settings: Dictionary) -> void:
 enabled=settings.get("rigging-climb-debug","on")!="off"
 var vertices:=PackedVector3Array()
 for mesh in model.find_children("*","MeshInstance3D"):
  if "rigging" in str(mesh.name):
   for p in mesh.mesh.get_faces():vertices.append(mesh.transform*p)
 for data in [["main",-2.7,-1.1,4.6,15.18,-0.92,2.15],["fore",8.7,9.7,4.5,11.95,9.97,1.85]]:
  for side in [-1.0,1.0]:
   # Fit center to actual rope vertices in narrow height bands. Bounds reject
   # stays/yards; both endpoints retain provenance from the imported rigging.
   var a:=sample_band(vertices,Vector3(data[1],data[3],side*2.75),Vector3(0.8,0.3,0.5))
   var b:=sample_band(vertices,Vector3(data[2],data[4]-0.5,side*1.05),Vector3(0.55,0.3,0.35))
   a.y=data[3]
   # Feet stay inboard of the line gripped at chest height, behind the rail.
   a.z-=side*0.45
   b.y=data[4]+0.15
   b.z=side*0.73+0.1
   var marker:=Node3D.new()
   marker.name=str(data[0])+ ("_port" if side<0 else "_starboard")
   marker.position=a
   marker.basis=Basis.looking_at(b-a,Vector3.UP)
   add_child(marker)
   routes.append({"name":str(marker.name),"a":a,"b":b,"node":marker,"samples":true})
   if settings.get("rigging-climb-debug","on")=="volumes":
    var mesh:=MeshInstance3D.new()
    var box:=BoxMesh.new()
    box.size=Vector3(0.8,0.8,a.distance_to(b))
    mesh.mesh=box
    mesh.position.z=-a.distance_to(b)*0.5
    var material:=StandardMaterial3D.new()
    material.albedo_color=Color(0.8,0.3,0.1)
    mesh.material_override=material
    marker.add_child(mesh)
  var center:=Vector3(data[5],data[4],0.1)
  var width: float=data[6]
  # A central deck and two wings leave real access hatches over the shrouds;
  # an uninterrupted slab would block the climber's head from below.
  rail(ship,center-Vector3.UP*0.06,Vector3(width,0.12,0.65))
  for wing in [-1.0,1.0]:
   rail(ship,center+Vector3(wing*(width*0.25+0.25),-0.06,0),Vector3(width*0.5-0.5,0.12,width))
  # Leave openings at each shroud landing, protected by the climb capsule.
  for sign_x in [-1.0,1.0]:
   rail(ship,center+Vector3(sign_x*width*0.5,0.6,0),Vector3(0.08,1.2,width))
  for sign_z in [-1.0,1.0]:
   for sign_x in [-1.0,1.0]:
    rail(ship,center+Vector3(sign_x*(width*0.25+0.2),0.6,sign_z*width*0.5),Vector3(width*0.5-0.4,1.2,0.08))
func sample_band(vertices: PackedVector3Array, center: Vector3, half: Vector3) -> Vector3:
 var sum:=Vector3.ZERO
 var count:=0
 for p in vertices:
  if AABB(center-half,half*2).has_point(p):
   sum+=p
   count+=1
 assert(count>0,"Ratline geometry band is empty")
 return sum/maxi(1,count)
func rail(ship: Node3D,p: Vector3,size: Vector3) -> void:
 var node:=CollisionShape3D.new()
 var shape:=BoxShape3D.new()
 shape.size=size
 node.shape=shape
 node.position=p
 ship.add_child(node)
func route_at(p: Vector3) -> Dictionary:
 if not enabled:return {}
 for route in routes:
  if not is_instance_valid(route.node):continue
  var a: Vector3=route.a
  var b: Vector3=route.b
  var t:=clampf((p-a).dot(b-a)/(b-a).length_squared(),0,1)
  if p.distance_to(a.lerp(b,t))<(0.60 if t<0.07 else 0.65):return route
 return {}
func velocity_at(p: Vector3, amount: float) -> Vector3:
 var route:=route_at(p)
 if route.is_empty():return Vector3.ZERO
 var a: Vector3=route.a
 var b: Vector3=route.b
 var axis: Vector3=(b-a).normalized()
 var t:=clampf((p-a).dot(b-a)/(b-a).length_squared(),0,1)
 if amount<0 and p.y<a.y+1.4:
  return Vector3(0,-0.15,-signf(a.z)*absf(amount))
 if amount>0 and p.y>b.y:
  return Vector3(0,0.15,-signf(b.z)*absf(amount))
 var correction: Vector3=a.lerp(b,t)-p
 # No body lean or camera pitch forced by the slope.
 return axis*amount+correction*3.0

func configure_gates(decks: Node3D) -> void:
 for rail_data in decks.rails:
  if not (str(rail_data.name).begins_with("Bulwark") or str(rail_data.name).begins_with("QuarterSide")):continue
  for route in routes:
   var p: Vector3=rail_data.shape.position
   if Vector2(p.x-route.a.x,p.z-route.a.z).length()<1.1:
    gates.append([rail_data.shape,route])
    break
func update_gates(p: Vector3, climbing: bool) -> void:
 for entry in gates:
  var open: bool=climbing and p.distance_to(entry[1].a)<2.5
  entry[0].disabled=open

func distance_to_route(p: Vector3,route: Dictionary) -> float:
 var a: Vector3=route.a
 var b: Vector3=route.b
 return p.distance_to(a.lerp(b,clampf((p-a).dot(b-a)/(b-a).length_squared(),0,1)))

func wants_grab(p: Vector3,direction: Vector3,vertical_input: float,route: Dictionary) -> bool:
 if route.is_empty():return false
 if p.y>route.b.y-0.25:return vertical_input< -0.1
 var toward: Vector3=route.a-p
 toward.y=0
 var horizontal:=Vector3(direction.x,0,direction.z)
 return vertical_input>0.1 and horizontal.length()>0.1 and (toward.length()<0.08 or horizontal.normalized().dot(toward.normalized())>0.5)
