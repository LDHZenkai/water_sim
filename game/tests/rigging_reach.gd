extends SceneTree
var world: Node3D
var player: CharacterBody3D
var max_roll:=0.0
func _initialize() -> void:call_deferred("run")
func run() -> void:
 world=load("res://scenes/main.tscn").instantiate()
 root.add_child(world)
 player=world.get_node("Player")
 player.test_input=true
 var port:=OS.get_cmdline_user_args().has("--port-climbs")
 var negative:=OS.get_cmdline_user_args().has("--delete-climb")
 var routes: Array=world.rigging_climb.routes
 for route in routes:print("ROPE ",route.name," ",route.a," -> ",route.b)
 if negative:
  routes[1].node.free()
  print("NEGATIVE CONTROL: deleted main_starboard climb volume")
 for i in range(90):await physics_frame
 var good:=true
 # Walk to main shrouds from main deck via the existing stair, then fore shrouds.
 var approach: Array[Vector3]=[Vector3(2.9,2.8,2.2),Vector3(-1.1,4.4,2.2),Vector3(-2,4.5,2.15)]
 if port:approach=[Vector3(1.8,2.8,1.5),Vector3(1.8,2.8,-1.5),Vector3(2.9,2.8,-2.0),Vector3(-1.1,4.4,-2.0),Vector3(-2,4.5,-1.95)]
 for target in approach:
  if not await walk(target):good=false;break
 if good:good=await climb(routes[0 if port else 1])
 if good:
  var transfer: Array[Vector3]=[Vector3(-1.1,4.5,2.2),Vector3(1.0,2.8,2.2),Vector3(1.8,2.8,1.5),Vector3(1.8,2.8,-1.5),Vector3(5.8,2.8,-1.035),Vector3(6.65,4.5,-1.035),Vector3(7.65,4.35,-1.035),Vector3(8.5,4.35,1.8)]
  if port:transfer=[Vector3(-1.1,4.5,-2.0),Vector3(1.0,2.8,-2.0),Vector3(1.8,2.8,-1.5),Vector3(5.8,2.8,-1.035),Vector3(6.65,4.5,-1.035),Vector3(7.65,4.35,-1.035),Vector3(8.5,4.35,-1.8)]
  for target in transfer:
   if not await walk(target):good=false;break
 if good:good=await climb(routes[2 if port else 3])
 player.move_input=Vector2.ZERO
 for i in range(60):await physics_frame
 good=good and max_roll>0.5 and player.is_on_floor()
 print("RIGGING REACHABILITY: ","PASS" if good else "FAIL"," max_roll=",max_roll," final grounded=",player.is_on_floor())
 world.free()
 quit(0 if good else 1)
func tick() -> void:
 max_roll=maxf(max_roll,absf(rad_to_deg(world.buoyancy.roll)))
 await physics_frame
 await process_frame
func walk(target: Vector3) -> bool:
 for i in range(1200):
  var d: Vector3=target-player.ship_position
  if Vector2(d.x,d.z).length()<0.22 and absf(d.y)<0.4:
   player.move_input=Vector2.ZERO
   print("REACHED ",target," actual ",player.ship_position)
   return true
  player.ship_yaw=atan2(-d.x,-d.z)
  player.move_input=Vector2(0,-1)
  await tick()
 print("FAIL: walk ",target," actual ",player.ship_position)
 return false
func climb(route: Dictionary) -> bool:
 for i in range(600):
  if not world.rigging_climb.route_at(player.ship_position).is_empty():break
  var d: Vector3=route.a-player.ship_position
  player.ship_yaw=atan2(-d.x,-d.z)
  player.move_input=Vector2(0,-1)
  await tick()
 player.move_input=Vector2(0,-1)
 for i in range(1000):
  await tick()
  if player.ship_position.y>route.b.y-0.05:break
 if player.ship_position.y<route.b.y-0.1:
  print("FAIL: top unreachable ",route.name," actual ",player.ship_position)
  return false
 print("TOP REACHED ",route.name," actual ",player.ship_position)
 player.ship_yaw=0.0 if route.a.z>0 else PI
 player.move_input=Vector2(0,-1)
 for i in range(30):await tick()
 player.move_input=Vector2.ZERO
 for i in range(35):await tick()
 if not player.is_on_floor():
  print("FAIL: top is not walkable ",player.ship_position)
  return false
 print("TOP GROUNDED ",route.name)
 player.ship_yaw=-signf(route.a.z)*PI/2
 player.move_input=Vector2(1,0)
 for i in range(24):await tick()
 player.move_input=Vector2(0,1)
 for i in range(1000):
  await tick()
  if player.ship_position.y<route.a.y+1.4:break
 if player.ship_position.y>route.a.y+1.5:
  print("FAIL: descent ",route.name," actual ",player.ship_position)
  return false
 # Continue descending: the bottom exit guides feet inward before releasing.
 player.move_input=Vector2(0,1)
 for i in range(60):await tick()
 player.move_input=Vector2.ZERO
 print("DECK RETURN ",route.name," actual ",player.ship_position)
 return true
