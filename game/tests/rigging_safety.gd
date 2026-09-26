extends SceneTree
var good:=true
var world: Node3D
var player: CharacterBody3D
var splashes:=0
var max_roll:=0.0
func check(ok: bool,label: String) -> void:
 good=good and ok
 print("PASS: " if ok else "FAIL: ",label)
func _initialize() -> void:call_deferred("run")
func tick() -> void:
 await physics_frame
 await process_frame
 max_roll=maxf(max_roll,absf(rad_to_deg(world.buoyancy.roll)))
func place(p: Vector3) -> void:
 player.ship_position=p
 player.global_position=world.ship_body.to_global(p)
 player.ship_velocity=Vector3.ZERO
 player.velocity=Vector3.ZERO
 player._carry_initialized=true
 player.move_input=Vector2.ZERO
 # The test also runs against the old controller, which lacks explicit attachment.
 if "attached_route" in player:player.attached_route={}
 if "released_route" in player:player.released_route={}
 player.climb_release=0
func run() -> void:
 world=load("res://scenes/main.tscn").instantiate()
 root.add_child(world)
 player=world.get_node("Player")
 player.test_input=true
 player.splashed.connect(func():splashes+=1)
 for i in range(90):await tick()
 for route in world.rigging_climb.routes:
  # A stationary body or one passing tangentially must not be captured.
  place(route.a+Vector3(0,0.1,-signf(route.a.z)*0.4))
  player.ship_yaw=-PI/2
  player.move_input=Vector2(0,-1)
  for i in range(8):await tick()
  check(not player.in_climb_volume,"passing base does not grab "+route.name)
  for strafe in [-1.0,1.0]:
   # Begin on the real line, with feet inboard; acquire with movement toward it.
   place(route.a+Vector3(0,0.05,-signf(route.a.z)*0.18))
   player.ship_yaw=PI if route.a.z>0 else 0.0
   player.move_input=Vector2(0,-1)
   for i in range(20):await tick()
   check(player.in_climb_volume,"grab base "+route.name)
   player.move_input=Vector2(strafe,0)
   var height: float=player.ship_position.y
   for i in range(15):await tick()
   check(player.in_climb_volume and absf(player.ship_position.y-height)<0.2,"strafe holds line "+route.name+" "+str(strafe))
   # Turn so each tested strafe input points outboard, then jump-release.
   player.ship_yaw=0.0 if strafe*signf(route.a.z)>0 else PI
   # local right transformed at +/-90deg points along ship +/-Z.
   player.ship_yaw=-signf(route.a.z)*strafe*PI/2
   player.move_input=Vector2(strafe,0)
   Input.action_press("jump")
   await tick()
   Input.action_release("jump")
   var shut:=true
   for gate in world.rigging_climb.gates:shut=shut and not gate[0].disabled
   check(shut,"gates close on jump frame "+route.name)
   var outside:=false
   for i in range(100):
    await tick()
    outside=outside or absf(player.ship_position.z)>3.65 or player._respawning
   check(not outside,"jump and strafe outboard contained "+route.name+" "+str(strafe))
  # High release: 1.5 seconds, never reattach while ungrounded and <=1 m away.
  place(route.a.lerp(route.b,0.60))
  var toward: Vector3=route.a-player.ship_position
  player.ship_yaw=atan2(-toward.x,-toward.z)
  player.move_input=Vector2(0,-1)
  for i in range(3):await tick()
  check(player.in_climb_volume,"mid-line attachment "+route.name)
  var before: float=player.ship_position.y
  Input.action_press("jump")
  await tick()
  Input.action_release("jump")
  player.move_input=Vector2.ZERO
  var recaught:=false
  var grounded:=false
  for i in range(90):
   await tick()
   grounded=grounded or player.is_on_floor()
   var a: Vector3=route.a
   var b: Vector3=route.b
   var distance: float=player.ship_position.distance_to(a.lerp(b,clampf((player.ship_position-a).dot(b-a)/(b-a).length_squared(),0,1)))
   if not grounded and distance<=1.0 and player.in_climb_volume:recaught=true
  check(not recaught and (grounded or player.ship_position.y<before-2.0),"jump remains released for 1.5 s "+route.name)
 check(splashes==0 and max_roll>0.5,"rolling ship: 0 overboard; splashes="+str(splashes)+" roll="+str(max_roll))
 world.free()
 print("RIGGING SAFETY: ","PASS" if good else "FAIL")
 quit(0 if good else 1)
