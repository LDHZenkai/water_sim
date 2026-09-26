extends SceneTree
var seen := {}
var max_roll := 0.0
var cabin_mode := false
var door_index := 1
var world: Node3D
var player: CharacterBody3D
func _initialize() -> void:
 create_timer(120).timeout.connect(func(): printerr("FAIL: exploration watchdog"); quit(1))
 call_deferred("run")
func run() -> void:
 cabin_mode=OS.get_cmdline_user_args().has("--cabin") or OS.get_cmdline_user_args().has("--cabin-starboard")
 door_index=0 if OS.get_cmdline_user_args().has("--cabin-starboard") else 1
 world=load("res://scenes/main.tscn").instantiate()
 root.add_child(world)
 player=world.get_node("Player")
 if OS.get_cmdline_user_args().has("--block-headroom"):
  var blocker:=CollisionShape3D.new()
  var box:=BoxShape3D.new()
  box.size=Vector3(2.0,0.4,2.0)
  blocker.shape=box
  blocker.position=Vector3(-10.6,8.0,0.1)
  world.ship_body.add_child(blocker)
  print("NEGATIVE CONTROL: cabin headroom blocked")
 player.test_input=true
 player.move_input=Vector2.ZERO
 if OS.get_cmdline_user_args().has("--delete-ramp"):
  for ramp in world.decks.ramps:
   if str(ramp.get_meta("route_label","")).begins_with("MainStairs") and ramp.shape.points[0].z>0:ramp.queue_free()
  print("NEGATIVE CONTROL: deleted starboard main stair ramp")
 for i in range(90): await physics_frame
 var route: Array[Vector3]=[
  Vector3(3,2.76,1.5),Vector3(2.9,2.8,2.2),Vector3(-1.1,4.4,2.2),Vector3(-3,4.5,1.5),
  Vector3(-3.1,4.53,1.55),Vector3(-4.2,4.55,0.75),Vector3(-4.95,6.2,0.15),Vector3(-5.7,6.3,0),
  Vector3(-5.7,6.3,0.65),Vector3(-6.4,6.04,0.7),
  Vector3(-8.1,7.7,1.65),Vector3(-12,7.7,1.5),Vector3(-12,9.9,1.05),Vector3(-11.5,8.75,0.4)]
 if OS.get_cmdline_user_args().has("--forecastle"):
  route=[Vector3(1.8,2.8,1.5),Vector3(1.8,2.8,-1.5),Vector3(5.8,2.8,-1.035),Vector3(6.65,4.5,-1.035),Vector3(7.65,4.35,-1.035),Vector3(9,4.35,1.8),Vector3(8.3,4.25,1.1),Vector3(10.4,5.65,0.8),Vector3(12,3.95,0),Vector3(13,3.9,0)]
 if cabin_mode:
  route=route.slice(0,10)
  route.append_array([Vector3(-6.8,6.1,0.3),Vector3(-7.4,6.2,0),Vector3(-8.2,6.4,-0.69),Vector3(-8.5,6.4,-0.69),Vector3(-9.65,6.38,-0.69),Vector3(-10.1,6.38,0.1),Vector3(-10.6,6.38,-0.45),Vector3(-11.65,6.38,0.1)])
 if door_index==0:
  for i in range(route.size()):
   if route[i].x< -8.19 and route[i].z<0:route[i].z=0.885
 var reached:=true
 for point in route:
  if cabin_mode and point.x<-8.4:
   if not world.doors[door_index].opened:
    player.camera.look_at(world.doors[door_index].interaction_point(),world.ship_body.global_basis.y)
    var event:=InputEventAction.new()
    event.action="interact"
    event.pressed=true
    world.cabin._unhandled_input(event)
    for i in range(90):await physics_frame
  if not await walk_to(point):
   reached=false
   break
 player.move_input=Vector2.ZERO
 for i in range(120):await physics_frame
 visit_targets()
 var required: Array=["main_deck","quarterdeck","upper_quarterdeck","poop_deck"]
 if cabin_mode:required=["main_deck","quarterdeck","upper_quarterdeck","cabin"]
 if OS.get_cmdline_user_args().has("--forecastle"):required=["main_deck","forecastle","bowsprit_root"]
 for label in required:
  if not seen.has(label):
   reached=false
   printerr("FAIL: named target not reached: ",label)
 if cabin_mode:
  var standing: bool=is_equal_approx(player.capsule.shape.height,1.8) and not player.auto_duck
  print("CABIN STANDING: ",standing)
  reached=reached and standing
 reached=reached and player.is_on_floor() and max_roll>0.5
 print("TARGETS: ",seen.keys(),"; max roll=",max_roll," degrees; final grounded=",player.is_on_floor())
 print("REACHABILITY: ","PASS" if reached else "FAIL")
 world.queue_free()
 await process_frame
 quit(0 if reached else 1)

func walk_to(target: Vector3, seconds: float = 18.0) -> bool:
 for i in range(int(seconds*60)):
  visit_targets()
  var local: Vector3=player.ship_position
  var diff:=target-local
  var horizontal:=Vector2(diff.x,diff.z)
  if horizontal.length()<0.20 and absf(diff.y)<0.35:
   player.move_input=Vector2.ZERO
   if cabin_mode and target.x<-9.9:
    for tick in range(20):await physics_frame
    if not player.is_on_floor() or not is_equal_approx(player.capsule.shape.height,1.8) or player.auto_duck:
     printerr("FAIL: cabin standing head clearance at ",target)
     return false
   print("REACHED: ",target," actual=",local)
   return true
  var direction:=Vector3(diff.x,0,diff.z).normalized()
  if horizontal.length()>0.12:
   player.ship_yaw=atan2(-direction.x,-direction.z)
  player.move_input=Vector2(0,-1)
  if horizontal.length()<0.15 and not world.decks.climb_at(local):player.move_input=Vector2.ZERO
  await physics_frame
  await process_frame
  if player._respawning:
   printerr("FAIL: walker splashed at ",local)
   return false
 for y in [0.2,0.8,1.5,1.8]:
  var origin: Vector3=world.ship_body.to_global(player.ship_position+Vector3.UP*y)
  var end: Vector3=origin+world.ship_body.global_basis*Vector3(-1,0,0)
  var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin,end,1))
  if not hit.is_empty():print("FRONT RAY ",y," ",world.ship_body.to_local(hit.position)," shape ",hit.shape)
 print("WALKSTATE floor=",player.is_on_floor()," wall=",player.is_on_wall()," velocity=",player.ship_velocity," angle=",player.floor_max_angle," up=",player.up_direction)
 for j in range(player.get_slide_collision_count()):
  var c:=player.get_slide_collision(j)
  print("BLOCKER normal=",world.ship_body.global_basis.inverse()*c.get_normal()," point=",world.ship_body.to_local(c.get_position())," shape=",c.get_collider_shape())
 printerr("FAIL: target ",target," timed out at ",player.ship_position)
 return false

func visit_targets() -> void:
 max_roll=maxf(max_roll,absf(rad_to_deg(world.buoyancy.roll)))
 if not player.is_on_floor():return
 for label in world.decks.targets:
  var p: Vector3=world.decks.targets[label]
  if Vector2(p.x-player.ship_position.x,p.z-player.ship_position.z).length()<0.35 and absf(p.y-player.ship_position.y)<0.35:
   seen[label]=true
