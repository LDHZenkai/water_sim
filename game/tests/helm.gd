extends SceneTree
# Sailing and helm checks (headless):
#   godot --headless --path game -s res://tests/helm.gd
# Sailing physics: speed on each point of sail, no drive head to wind,
# stopping when furled, turn rate, no steerage without way on, determinism.
# Helm: take the wheel in the main scene, steer and set sail while the ship
# turns under the helmsman, then step away.
const Motion = preload("res://ocean/buoyancy.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
 print("PASS: " if ok else "FAIL: ", label)
 if not ok: failures += 1

func _initialize() -> void:
 create_timer(300).timeout.connect(func(): printerr("FAIL: helm watchdog"); quit(1))
 call_deferred("run")

func run() -> void:
 _test_sailing()
 await _test_helm()
 print("Helm: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
 quit(0 if failures == 0 else 1)

static func _sail(motion: RefCounted, seconds: float) -> void:
 for i in range(int(seconds * 60.0)):
  motion._navigate(1.0 / 60.0)

func _test_sailing() -> void:
 var motion = Motion.new()
 var wind: Vector2 = Motion.wind()
 var from := -wind.normalized()
 # Heading whose bow points at direction d (bow = (cos h, -sin h)).
 var toward := func(d: Vector2) -> float: return atan2(-d.y, d.x)
 var beam: float = motion.steady_speed(1.0, 0.0) / 0.514444
 var broad: float = motion.steady_speed(1.0, toward.call(from.rotated(deg_to_rad(135.0)))) / 0.514444
 var running: float = motion.steady_speed(1.0, toward.call(-from)) / 0.514444
 var close: float = motion.steady_speed(1.0, toward.call(from.rotated(deg_to_rad(40.0)))) / 0.514444
 print("SAILING full canvas in ", wind.length(), " m/s wind: beam reach ", beam, " kn, broad reach ", broad, " kn, running ", running, " kn, 40 deg off the wind ", close, " kn")
 check(beam > 5.0 and beam < 7.0, "beam reach makes 5..7 knots (default heading)")
 check(broad > beam, "a square rig is fastest on a broad reach")
 check(running < broad, "running is slower than a broad reach (apparent wind drops)")
 check(close < 0.5, "no drive 40 degrees off the wind (square rig)")
 # Head to wind: loses way.
 motion.start_heading = toward.call(from)
 motion.reset_navigation()
 motion.speed = 3.0
 _sail(motion, 120.0)
 check(motion.knots() < 1.0, "head to wind the ship loses way within 2 minutes")
 # Furling stops the ship.
 motion.start_heading = 0.0
 motion.reset_navigation()
 motion.sail = 0
 _sail(motion, 150.0)
 check(motion.knots() < 1.0, "furled, the ship slows below 1 knot within 150 s")
 # Bear away under full rudder: turn rate of a galleon.
 motion.reset_navigation()
 motion.rudder_input = -1.0
 var start: float = motion.heading
 var turned := 0.0
 var last: float = motion.heading
 var elapsed := 0.0
 while -turned < PI * 0.5 and elapsed < 180.0:
  motion._navigate(1.0 / 60.0)
  elapsed += 1.0 / 60.0
  turned += wrapf(motion.heading - last, -PI, PI)
  last = motion.heading
 print("SAILING 90 degree turn to starboard under full rudder: ", elapsed, " s")
 check(elapsed > 25.0 and elapsed < 90.0, "full rudder turns 90 degrees in 25..90 s")
 check(motion.rudder < -deg_to_rad(34.0), "rudder reaches full starboard helm")
 # Rudder does nothing without way on.
 motion.start_sail = 0
 motion.start_speed = 0.0
 motion.reset_navigation()
 motion.rudder_input = 1.0
 _sail(motion, 30.0)
 check(absf(motion.heading) < deg_to_rad(1.0), "no steerage without way on")
 # Drift is the distance sailed; the pose is deterministic.
 motion.start_sail = 3
 motion.start_speed = -1.0
 var a: Transform3D = motion.pose_at(20.0, 32)
 var drift_a: Vector2 = motion.drift
 var b: Transform3D = motion.pose_at(20.0, 32)
 check(a.is_equal_approx(b) and drift_a.is_equal_approx(motion.drift), "fixed-step pose and drift are deterministic")
 check(absf(drift_a.length() - motion.speed * 20.0) < 1.0, "water drifts past the hull by the distance sailed")

func _test_helm() -> void:
 var world = load("res://scenes/main.tscn").instantiate()
 root.add_child(world)
 var player: CharacterBody3D = world.get_node("Player")
 var helm: Node3D = world.helm
 var motion = world.buoyancy
 player.test_input = true
 player.move_input = Vector2.ZERO
 for i in range(30): await physics_frame
 check(helm != null and helm.wheel != null, "the ship has a wheel")
 print("HELM readout: ", helm.describe().replace("\n", " | "))
 check("kn" in helm.describe() and "Heading 090" in helm.describe(), "readout shows speed and an easterly heading")
 # Heading east with the wind from the north: the wind is on the port side.
 check("from 007" in helm.describe() and "port tack" in helm.describe(), "readout gives the wind's bearing and the tack")
 # Stand at the wheel and look at it.
 player.ship_position = helm.STAND
 player._carry_initialized = true
 player.ship_yaw = -PI * 0.5
 for i in range(20): await physics_frame
 await process_frame
 player.camera.look_at(world.ship_body.to_global(helm.HUB))
 check(helm.in_reach(), "the wheel is in reach when standing at it")
 helm.take()
 check(helm.steering and player.at_helm, "taking the helm")
 helm.test_input = true
 helm.test_steer = -1.0
 player.move_input = Vector2(1, -1)
 var heading_before: float = motion.heading
 var drift_max := 0.0
 for i in range(600):
  await physics_frame
  drift_max = maxf(drift_max, Vector2(player.ship_position.x - helm.STAND.x, player.ship_position.z - helm.STAND.z).length())
 var turned: float = rad_to_deg(wrapf(motion.heading - heading_before, -PI, PI))
 print("HELM 10 s of starboard helm: turned ", turned, " deg; rudder ", rad_to_deg(motion.rudder), " deg; helmsman moved ", drift_max, " m")
 check(turned < -5.0, "starboard helm turns the ship to starboard")
 check(drift_max < 0.3, "the helmsman stays at the wheel while the ship turns (ignores walk input)")
 check(absf(helm.wheel.rotation.x) > 1.0, "the wheel turns with the rudder")
 var sail: int = motion.sail
 var press := InputEventAction.new()
 press.action = "move_back"
 press.pressed = true
 helm._unhandled_input(press)
 check(motion.sail == sail - 1, "S takes in sail")
 press.action = "move_forward"
 helm._unhandled_input(press)
 check(motion.sail == sail, "W sets sail")
 helm.leave()
 check(not helm.steering and not player.at_helm, "stepping away from the helm")
 for i in range(240): await physics_frame
 check(absf(motion.rudder) < deg_to_rad(1.0), "an abandoned helm returns amidships")
 motion.sail = 0
 motion.canvas = 0.0
 await process_frame
 await process_frame
 check(not world.sails_mesh.visible, "furled canvas hides the sails")
 world.queue_free()
 await process_frame
