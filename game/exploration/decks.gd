extends Node3D
# All dimensions are in the original hull's metre coordinates.
var ramps: Array[CollisionShape3D] = []
var rails: Array[Dictionary] = []
var climbs: Array[AABB] = []
var footprint := PackedVector2Array()
var targets := {
 "cabin": Vector3(-10.1,6.38,0.1),
 "main_deck": Vector3(3,2.76,1.5),
 "quarterdeck": Vector3(-3,4.5,1.5),
 "upper_quarterdeck": Vector3(-6.4,6.04,0.7),
 "forecastle": Vector3(9,4.35,1.8),
 "bowsprit_root": Vector3(13,3.9,0),
 "poop_deck": Vector3(-11.5,8.75,0.4),
}
func build(ship: AnimatableBody3D) -> void:
 for side in [-1.0,1.0]:
  ramp(ship,"MainStairs"+str(side),Vector3(0.65,2.80,0.097+side*1.985),Vector3(-0.45,4.60,0.097+side*1.985),0.66)
 # Source ladder: x=6.552..6.934, z=-1.357..-0.713, y=2.846..4.310.
 # There is no matching starboard staircase in the model.
 climbs.append(AABB(Vector3(6.05,2.65,-1.55),Vector3(1.4,2.45,1.03)))
 # Quarterdeck ladder side pieces: x=-5.209..-4.776, z=-0.208..0.510.
 climbs.append(AABB(Vector3(-5.65,4.4,-0.46),Vector3(1.35,2.35,1.22)))
 # Side galleries climb gradually; the final narrow ladders are vertical volumes.
 for side in [-1.0,1.0]:
  ramp(ship,"SternStairApproach"+str(side),Vector3(-6.3,6.0,side*0.7),Vector3(-8.1,7.7,side*1.65),0.8)
  ramp(ship,"SternGallery"+str(side),Vector3(-8.1,7.7,side*1.65),Vector3(-12.0,7.7,side*1.5),0.8)
  climbs.append(AABB(Vector3(-12.4,7.05,side*1.05-0.45),Vector3(0.85,3.2,0.9)))
 for z in [-0.69,0.885]:
  ramp(ship,"DoorThreshold",Vector3(-8.2,6.30,z),Vector3(-9.25,6.38,z),0.58)
 ramp(ship,"BowApproach",Vector3(8.5,4.25,1.1),Vector3(10.4,5.65,0.8),0.8)
 ramp(ship,"BowDescent",Vector3(10.4,5.65,0.8),Vector3(12.0,3.95,0),0.8)
 var outline := [Vector2(-12.8,-1.85),Vector2(-11,-2.5),Vector2(-8,-2.9),Vector2(-5,-3.25),Vector2(0,-3.4),Vector2(6,-3.35),Vector2(9,-2.9),Vector2(11,-1.8),Vector2(13,-0.9),Vector2(16,-0.4),Vector2(16,0.4),Vector2(13,0.9),Vector2(11,1.8),Vector2(9,2.9),Vector2(6,3.35),Vector2(0,3.4),Vector2(-5,3.25),Vector2(-8,2.9),Vector2(-11,2.5),Vector2(-12.8,1.85)]
 footprint=PackedVector2Array(outline)
 for i in range(outline.size()):
  var a: Vector2=outline[i]
  var b: Vector2=outline[(i+1)%outline.size()]
  subdivided_wall(ship,"Bulwark%02d"%i,Vector3(a.x,6,a.y),Vector3(b.x,6,b.y),10.0)
 for span in [Vector2(-1.8,-1.4),Vector2(-0.7,0.85),Vector2(1.61,1.8)]:
  wall(ship,"ForeLedge",Vector3(7.0,4.85,span.x),Vector3(7.0,4.85,span.y),1.3)
  rails.back()["outward"]=Vector3.LEFT
 # Guard the unrailed inner edges of raised decks, leaving the stair approaches.
 for side in [-1.0,1.0]:
  wall(ship,"MainLedge"+str(side),Vector3(-0.65,5.0,side*0.15),Vector3(-0.65,5.0,side*1.57),1.3)
  rails.back()["outward"]=Vector3.RIGHT
  wall(ship,"QuarterLedge"+str(side),Vector3(-5.5,6.65,side*0.8),Vector3(-5.5,6.65,side*2.2),1.3)
  rails.back()["outward"]=Vector3.RIGHT
 for side in [-1.0,1.0]:
  subdivided_wall(ship,"QuarterSide",Vector3(-0.8,5.0,side*2.5),Vector3(-5.5,5.3,side*2.2),1.2)
  wall(ship,"UpperQuarterSide",Vector3(-5.5,6.6,side*2.1),Vector3(-8.8,6.6,side*1.28),0.9)
 var poop: Array[Vector3]=[Vector3(-12.4,9.05,-0.73),Vector3(-8.9,9.05,-1.03),Vector3(-8.9,9.05,1.22),Vector3(-12.4,9.05,0.92)]
 for i in range(poop.size()):
  var a: Vector3=poop[i]
  var b: Vector3=poop[(i+1)%poop.size()]
  wall(ship,"PoopRail",a,b,0.9)
  var tangent: Vector3=(b-a).normalized()
  rails.back()["outward"]=Vector3(tangent.z,0,-tangent.x)
 for key in targets:
  var marker:=Marker3D.new()
  marker.name=key
  marker.position=targets[key]
  add_child(marker)

 collision_debug(ship)

func ramp(ship: AnimatableBody3D, label: String, a: Vector3, b: Vector3, width: float) -> void:
 var side: Vector3=(b-a).cross(Vector3.UP).normalized()*width*0.5
 var shape:=ConvexPolygonShape3D.new()
 shape.points=PackedVector3Array([a-side,a+side,b-side,b+side,a-side-Vector3.UP*0.2,a+side-Vector3.UP*0.2,b-side-Vector3.UP*0.2,b+side-Vector3.UP*0.2])
 var node:=CollisionShape3D.new()
 node.name=label
 node.set_meta("route_label",label)
 node.shape=shape
 ship.add_child(node)
 ramps.append(node)
func wall(ship: AnimatableBody3D,label: String,a: Vector3,b: Vector3,height: float) -> void:
 var shape:=BoxShape3D.new()
 shape.size=Vector3(0.12,height,a.distance_to(b)+0.12)
 var node:=CollisionShape3D.new()
 node.name=label
 node.set_meta("route_label",label)
 node.shape=shape
 ship.add_child(node)
 node.position=(a+b)*0.5
 # These are ship-local coordinates; never feed them to global look_at.
 node.basis=Basis.looking_at(b-a,Vector3.UP)
 rails.append({"name":label,"a":a,"b":b,"height":height,"shape":node})

# Explicit diagnostic only; release collision helpers have no visuals at all.
func collision_debug(ship: AnimatableBody3D) -> void:
 if get_node("/root/Quality").overrides.get("collision-debug","off")!="on":return
 var material:=StandardMaterial3D.new()
 material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
 material.albedo_color=Color(1,0,1)
 var helpers: Array=[]
 helpers.append_array(ramps)
 for rail in rails:helpers.append(rail.shape)
 for collision in helpers:
  var visual:=MeshInstance3D.new()
  visual.mesh=collision.shape.get_debug_mesh()
  visual.material_override=material
  visual.transform=collision.transform
  visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  add_child(visual)
 for volume in climbs:
  var visual:=MeshInstance3D.new()
  var mesh:=BoxMesh.new()
  mesh.size=volume.size
  visual.mesh=mesh
  visual.position=volume.get_center()
  visual.material_override=material
  add_child(visual)

func climb_at(p: Vector3) -> bool:
 for volume in climbs:
  if volume.has_point(p): return true
 return false

func subdivided_wall(ship: AnimatableBody3D,label: String,a: Vector3,b: Vector3,height: float) -> void:
 var count:=ceili(a.distance_to(b)/0.65)
 for i in range(count):wall(ship,label+str(i),a.lerp(b,float(i)/count),a.lerp(b,float(i+1)/count),height)
