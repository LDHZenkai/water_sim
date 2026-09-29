extends Node3D
## The ship's wheel on the poop deck. Walk up, look at it and press E to take
## the helm: A/D put the helm over (the ship only answers with way on), W/S
## set or take in sail, E steps away. While steering, the helmsman stays at
## the wheel but can still look around. A readout shows speed, heading, sail,
## rudder and where the wind is.
const HUB := Vector3(-10.05, 9.36, 0.0)
const DECK := 8.31
## Where the helmsman's feet go, just aft of the wheel.
const STAND := Vector3(-11.0, 8.55, 0.0)
const REACH := 2.3
const SAIL_NAMES := ["furled", "reefed", "working sail", "full sail"]
## Wheel turns 1.5 revolutions lock to lock.
const WHEEL_TURNS := 0.75

var ship: Node3D
var player: CharacterBody3D
var motion: RefCounted
## Live weather (scripts/weather.gd), for the readout's third line.
var weather: Node
var items: Node3D
var steering := false
var wheel: Node3D
var prompt: Label
var readout: Label
var panel: PanelContainer
## Tests drive the rudder directly instead of reading the keyboard.
var test_input := false
var test_steer := 0.0

func build(hull: Node3D, actor: CharacterBody3D, ship_motion: RefCounted, interactables: Node3D, timber: Material) -> void:
 ship = hull
 player = actor
 motion = ship_motion
 items = interactables
 # Read steering before the world integrates the ship this tick.
 process_physics_priority = -60
 _build_wheel(timber)
 _build_ui()

func _build_wheel(timber: Material) -> void:
 var dark := timber.duplicate() as BaseMaterial3D
 dark.albedo_color = Color(0.30, 0.20, 0.12)
 var brass := StandardMaterial3D.new()
 brass.albedo_color = Color(0.72, 0.55, 0.28)
 brass.metallic = 0.9
 brass.roughness = 0.35
 # Pedestal forward of the wheel, carrying the axle, on a low plinth.
 var post_height := HUB.y + 0.1 - DECK
 _part(BoxMesh.new(), Vector3(0.16, post_height, 0.16), Transform3D(Basis.IDENTITY, Vector3(HUB.x + 0.2, DECK + post_height * 0.5, 0.0)), timber, self)
 _part(BoxMesh.new(), Vector3(0.5, 0.08, 0.42), Transform3D(Basis.IDENTITY, Vector3(HUB.x + 0.2, DECK + 0.04, 0.0)), timber, self)
 _part(CylinderMesh.new(), Vector3(0.035, 0.24, 0.035), Transform3D(Basis(Vector3.BACK, PI * 0.5), HUB + Vector3(0.1, 0, 0)), brass, self)
 wheel = Node3D.new()
 wheel.name = "Wheel"
 wheel.position = HUB
 add_child(wheel)
 var rim := TorusMesh.new()
 rim.inner_radius = 0.46
 rim.outer_radius = 0.53
 rim.rings = 48
 rim.ring_segments = 10
 var rim_node := MeshInstance3D.new()
 rim_node.mesh = rim
 rim_node.material_override = dark
 rim_node.rotation = Vector3(0, 0, PI * 0.5)
 wheel.add_child(rim_node)
 for i in range(8):
  var spoke := Basis(Vector3.RIGHT, TAU * float(i) / 8.0)
  _part(CylinderMesh.new(), Vector3(0.02, 1.24, 0.02), Transform3D(spoke, Vector3.ZERO), dark, wheel)
  # Turned handle beyond the rim.
  _part(CylinderMesh.new(), Vector3(0.03, 0.13, 0.03), Transform3D(spoke, spoke * Vector3(0, 0.6, 0)), dark, wheel)
 _part(CylinderMesh.new(), Vector3(0.1, 0.16, 0.1), Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO), brass, wheel)

func _part(mesh: PrimitiveMesh, size: Vector3, pose: Transform3D, material: Material, parent: Node3D) -> MeshInstance3D:
 if mesh is BoxMesh:
  (mesh as BoxMesh).size = size
 elif mesh is CylinderMesh:
  var cylinder := mesh as CylinderMesh
  cylinder.top_radius = size.x
  cylinder.bottom_radius = size.z
  cylinder.height = size.y
  cylinder.radial_segments = 12
  cylinder.rings = 1
 var node := MeshInstance3D.new()
 node.mesh = mesh
 node.material_override = material
 node.transform = pose
 parent.add_child(node)
 return node

func _build_ui() -> void:
 var ui := CanvasLayer.new()
 add_child(ui)
 prompt = Label.new()
 prompt.position = Vector2(30, 140)
 prompt.add_theme_font_size_override("font_size", 16)
 ui.add_child(prompt)
 panel = PanelContainer.new()
 panel.anchor_left = 0.5
 panel.anchor_right = 0.5
 panel.anchor_top = 1.0
 panel.anchor_bottom = 1.0
 panel.offset_left = -330
 panel.offset_right = 330
 panel.offset_top = -118
 panel.offset_bottom = -20
 var style := StyleBoxFlat.new()
 style.bg_color = Color(0.05, 0.04, 0.03, 0.62)
 style.set_corner_radius_all(6)
 style.content_margin_left = 14
 style.content_margin_right = 14
 style.content_margin_top = 8
 style.content_margin_bottom = 8
 panel.add_theme_stylebox_override("panel", style)
 readout = Label.new()
 readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 readout.add_theme_font_size_override("font_size", 17)
 readout.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
 panel.add_child(readout)
 ui.add_child(panel)
 panel.visible = false

## True when the player stands at the wheel and is looking at it.
func in_reach() -> bool:
 if steering or not player.input_enabled or not is_instance_valid(player.camera): return false
 if items != null and items.get("selected") != "": return false
 var hub := ship.to_global(HUB)
 var delta: Vector3 = hub - player.camera.global_position
 if delta.length() > REACH: return false
 return (-player.camera.global_basis.z).dot(delta.normalized()) > 0.8

func take() -> void:
 steering = true
 player.at_helm = true
 player.move_input = Vector2.ZERO
 player.ship_position = STAND
 player.ship_velocity = Vector3.ZERO
 player._carry_initialized = true
 player.ship_yaw = -PI * 0.5
 player.global_position = ship.to_global(STAND)
 panel.visible = true

func leave() -> void:
 steering = false
 player.at_helm = false
 panel.visible = false

func _unhandled_input(event: InputEvent) -> void:
 if event.is_action_pressed("interact"):
  if steering:
   leave()
   get_viewport().set_input_as_handled()
  elif in_reach():
   take()
   get_viewport().set_input_as_handled()
 elif steering and event.is_action_pressed("move_forward"):
  motion.sail = mini(motion.sail + 1, motion.SAIL_CANVAS.size() - 1)
 elif steering and event.is_action_pressed("move_back"):
  motion.sail = maxi(motion.sail - 1, 0)

func _physics_process(_delta: float) -> void:
 var steer := 0.0
 if steering:
  if test_input: steer = test_steer
  elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED: steer = Input.get_axis("move_right", "move_left")
 motion.rudder_input = steer

func _process(_delta: float) -> void:
 # Seen from the helmsman, port helm turns the wheel anticlockwise.
 wheel.rotation.x = -motion.rudder / motion.MAX_RUDDER * WHEEL_TURNS * TAU
 prompt.text = "E · take the helm" if in_reach() else ""
 if steering: readout.text = describe() + ("\n" + conditions() if weather else "")

## Weather and the ship's warnings: overpressed canvas, surfing, broaching.
func conditions() -> String:
 var line: String = weather.describe() + "    Heel %d°" % roundi(rad_to_deg(absf(motion.heel)))
 if motion.overpressed(): line += "  ·  OVERPRESSED, reef (S)"
 if motion.surf > 0.25: line += "  ·  SURFING"
 if absf(motion.broach) > 0.004: line += "  ·  BROACHING, meet her"
 return line

static func bearing(direction: Vector2) -> float:
 # North is -Z, east is +X (the held compass agrees).
 return fposmod(rad_to_deg(atan2(direction.x, -direction.y)), 360.0)

## Readout text; also used by tests and the tour.
func describe() -> String:
 var heading: float = bearing(motion.forward())
 var wind: Vector2 = motion.wind()
 var from := -wind.normalized()
 var off_bow: float = rad_to_deg(motion.forward().angle_to(from))
 var angle := absf(off_bow)
 # World XZ seen from above has +Z to the south, so a negative angle from the
 # bow is toward -Z: to port when the bow faces east.
 var side := "port" if off_bow < 0.0 else "starboard"
 var point := "in irons, no drive"
 if angle >= 50.0: point = "close-hauled"
 if angle >= 70.0: point = "beam reach"
 if angle >= 110.0: point = "broad reach"
 if angle >= 155.0: point = "running"
 var rudder: float = rad_to_deg(motion.rudder)
 var helm := "amidships" if absf(rudder) < 1.0 else "%d° %s" % [roundi(absf(rudder)), "port" if rudder > 0.0 else "starboard"]
 return "%s   [W/S]      Helm %s   [A/D]      E · leave helm\n%.1f kn    Heading %03d°    Wind %.0f m/s from %03d° · %s, %s tack" % [SAIL_NAMES[motion.sail].capitalize(), helm, motion.knots(), roundi(heading) % 360, wind.length(), roundi(bearing(from)) % 360, point, side]
