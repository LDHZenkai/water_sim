extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var world=load("res://scenes/main.tscn").instantiate()
 root.add_child(world)
 world.freeze_at(0)
 world.get_node("Player").input_enabled=false
 var cabin=world.cabin
 if OS.get_cmdline_user_args().has("--inject-protrusion"):
  for prop in cabin.props:
   if prop.name=="GothicCabinet_01":prop.position.z-=0.5
  print("NEGATIVE CONTROL: cabinet translated 0.5 m through port wall")
 var bad:=0
 var corners:=0
 for prop in cabin.props:
  var meshes: Array=prop.find_children("*","MeshInstance3D",true,false)
  if prop is MeshInstance3D:meshes.append(prop)
  if meshes.is_empty():bad+=1
  for mesh in meshes:
   var bounds: AABB=mesh.get_aabb()
   var transform: Transform3D=cabin.global_transform.affine_inverse()*mesh.global_transform
   for i in range(8):
    var p: Vector3=transform*bounds.get_endpoint(i)
    corners+=1
    var sides: Vector2=cabin.side_limits(p.x)
    # Tight inner skin, floor, stern and forward wall bounds, independent of
    # outside galleries. No exterior ray can excuse a protruding prop.
    var ceiling: float=cabin.roof_height(p.x,p.z)
    if p.x<cabin.BACK+0.01 or p.x>cabin.FRONT-0.01 or p.y<cabin.FLOOR-0.002 or p.y>ceiling-0.01 or p.z<sides.x+0.01 or p.z>sides.y-0.01:
     if bad<8:print("OUTSIDE PROP ",prop.name," corner=",p)
     bad+=1
 # Material batching reduces mesh count; require every prop, not a fixed draw count.
 if cabin.props.size()<12 or corners<8*cabin.props.size():bad+=1
 print("PROP CONTAINMENT: ","PASS" if bad==0 else "FAIL","; corners=",corners," outside=",bad)
 world.free()
 quit(0 if bad==0 else 1)
