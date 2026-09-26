extends SceneTree
# These are walkable deck approaches, not rays down onto rail ornaments.
const CASES = [
 ["main_port",Vector3(3,2.8,-2),Vector3.FORWARD],
 ["main_starboard",Vector3(3,2.8,2),Vector3.BACK],
 ["forecastle_port",Vector3(9,4.35,-1.8),Vector3.FORWARD],
 ["forecastle_starboard",Vector3(9,4.35,1.8),Vector3.BACK],
 ["forecastle_ledge",Vector3(7.5,4.5,0.1),Vector3.LEFT],
 ["quarter_port",Vector3(-3,4.5,-1.6),Vector3.FORWARD],
 ["quarter_starboard",Vector3(-3,4.5,1.6),Vector3.BACK],
 ["quarter_ledge_port",Vector3(-1.3,4.5,-0.8),Vector3.RIGHT],
 ["quarter_ledge_starboard",Vector3(-1.3,4.5,0.8),Vector3.RIGHT],
 ["upper_port",Vector3(-6.5,6.1,-1),Vector3.FORWARD],
 ["upper_starboard",Vector3(-6.5,6.1,1),Vector3.BACK],
 ["upper_ledge_port",Vector3(-6.2,6.1,-1.5),Vector3.RIGHT],
 ["upper_ledge_starboard",Vector3(-6.2,6.1,1.5),Vector3.RIGHT],
 ["poop_port",Vector3(-11,8.8,-0.35),Vector3.FORWARD],
 ["poop_starboard",Vector3(-11,8.8,0.55),Vector3.BACK],
 ["poop_forward",Vector3(-9.7,8.5,0.1),Vector3.RIGHT],
 ["poop_aft",Vector3(-11.8,8.9,0.1),Vector3.LEFT],
]
func _initialize() -> void:
 create_timer(240).timeout.connect(func(): printerr("FAIL: overboard watchdog"); quit(1))
 call_deferred("run")
func run() -> void:
 var world=load("res://scenes/main.tscn").instantiate()
 root.add_child(world)
 var player: CharacterBody3D=world.get_node("Player")
 player.test_input=true
 player.test_sprint=true
 player.input_enabled=false
 var raw:=StaticBody3D.new()
 raw.collision_layer=4
 var raw_shape:=CollisionShape3D.new()
 raw_shape.shape=world.hull_source_mesh.create_trimesh_shape()
 raw_shape.shape.backface_collision=true
 raw.add_child(raw_shape)
 root.add_child(raw)
 await physics_frame
 await physics_frame
 var failures:=0
 var cases:=0
 for item in CASES:
  for angle in [-15.0,0.0,15.0]:
   cases+=1
   var start: Vector3=item[1]+Vector3.UP*0.12
   player.global_position=world.ship_body.to_global(start)
   player.ship_position=start
   player.ship_velocity=Vector3.ZERO
   player.velocity=Vector3.ZERO
   player._carry_initialized=true
   player._respawning=false
   # Each teleport starts a new walking case, with no previous rope attachment.
   player.attached_route={}
   player.released_route={}
   player.input_enabled=true
   player.move_input=Vector2.ZERO
   for tick in range(60):
    await physics_frame
    await process_frame
   if not player.is_on_floor() or absf(player.ship_position.y-item[1].y)>0.45:
    printerr("FAIL: invalid grounded approach ",item[0]," at ",player.ship_position)
    failures+=1
    player.input_enabled=false
    continue
   start=player.ship_position
   var direction: Vector3=item[2].rotated(Vector3.UP,deg_to_rad(angle))
   player.ship_yaw=atan2(-direction.x,-direction.z)
   player.move_input=Vector2(0,-1)
   var crossed:=false
   for tick in range(75):
    await physics_frame
    await process_frame
    var p: Vector3=player.ship_position
    var query:=PhysicsRayQueryParameters3D.create(Vector3(p.x,31,p.z),Vector3(p.x,-3,p.z),4)
    query.hit_back_faces=true
    var above_hull: bool=not world.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
    if not above_hull or player._respawning or p.y<start.y-0.5:
     crossed=true
     break
   player.input_enabled=false
   if crossed:
    printerr("FAIL: overboard ",item[0]," angle=",angle," start=",start," end=",player.ship_position)
    failures+=1
 print("OVERBOARD: ",cases," sprint approaches on main/forecastle/quarter/upper/poop; ",failures," failures")
 raw.free()
 world.free()
 quit(0 if failures==0 else 1)
