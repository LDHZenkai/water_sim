extends SceneTree
# Real player input/carry code, synthetic deck pose, 7200 fixed physics ticks.
func _initialize() -> void:
 call_deferred("run")

func run() -> void:
 var player = load("res://scenes/player.tscn").instantiate()
 # Dummy display cannot capture a mouse; bypass only that display guard.
 var input_script := GDScript.new()
 input_script.source_code = FileAccess.get_file_as_string("res://scripts/player.gd").replace("event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED", "event is InputEventMouseMotion")
 input_script.reload()
 player.set_script(input_script)
 var deck := AnimatableBody3D.new()
 deck.sync_to_physics = false
 root.add_child(deck)
 root.add_child(player)
 player.set_physics_process(false)
 player.deck = deck
 player.test_input = true
 player.sea_height = func(_p): return -100000.0
 Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
 var maximum := 0.0
 var yaw_motion := 0.0
 for tick in range(7200):
  var t := float(tick)/60.0
  deck.basis = Basis.from_euler(Vector3(deg_to_rad(3.0)*sin(t*TAU/13.0),0,deg_to_rad(2.0)*sin(t*TAU/7.0)))
  var event := InputEventMouseMotion.new()
  event.relative = Vector2(10.0+7.0*sin(t*0.7),0)
  var before: Basis = player.basis
  player._unhandled_input(event)
  player._physics_process(1.0/60.0)
  yaw_motion += before.z.angle_to(player.basis.z)
  maximum = maxf(maximum,rad_to_deg(player.global_basis.y.angle_to(deck.global_basis.y)))
 print("Yaw regression: 120 s, max up error=",maximum," deg; accumulated look motion=",yaw_motion," rad")
 var passed := maximum < 0.5 and yaw_motion > 10.0
 print("PASS: yaw keeps player up within 0.5 degrees" if passed else "FAIL: yaw keeps player up within 0.5 degrees")
 player.free()
 deck.free()
 quit(0 if passed else 1)
