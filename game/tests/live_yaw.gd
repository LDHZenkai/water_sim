extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var world=load("res://scenes/main.tscn").instantiate()
 # Exercise a rotated/translated parent: deck_pose must really be global.
 world.position=Vector3(50,4,-30)
 world.rotation.y=0.4
 root.add_child(world)
 var player: CharacterBody3D=world.get_node("Player")
 player.test_input=true
 var up_error:=0.0
 var immediate:=0.0
 var motion:=0.0
 for tick in range(1800):
  await physics_frame
  await process_frame
  var pose: Transform3D=world.global_transform*world.next_ship_pose
  up_error=maxf(up_error,rad_to_deg(player.global_basis.y.angle_to(pose.basis.y)))
  var event:=InputEventMouseMotion.new()
  event.relative=Vector2(8,0)
  var before: float=player.ship_yaw
  player._process(0.0)
  var camera_before: Vector3=player.camera.global_basis.z
  player._unhandled_input(event)
  player._process(0.0)
  motion+=absf(wrapf(player.ship_yaw-before,-PI,PI))
  immediate+=camera_before.angle_to(player.camera.global_basis.z)
 print("LIVE YAW: 30 s rolling main scene, transformed parent; up error=",up_error," deg; mouse yaw=",motion," rad; immediate camera motion=",immediate," rad")
 var good:=up_error<0.5 and motion>20 and immediate>20
 world.free()
 quit(0 if good else 1)
