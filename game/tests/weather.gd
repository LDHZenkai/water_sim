extends SceneTree
# Weather, sea state, the novel mechanic and life on deck (headless):
#   godot --headless --path game -s res://tests/weather.gd
# Sea: a changing wind builds a new sea without jumps; the sea settles to the
# new state's height; a rogue wave focuses to its crest at the ship and is
# unremarkable half a minute earlier. Ship: surfing in a following sea,
# broaching on the quarter, heel overpressing the rig in a storm, knockdowns.
# World: sails fill and are taken aback, the weather menu drives the weather,
# notices reach the HUD, an unbraced player is thrown across the deck by a
# knockdown while a braced one holds on, and the sea file is restored.
const Motion = preload("res://ocean/buoyancy.gd")
const Weather = preload("res://scripts/weather.gd")
const SEA = preload("res://ocean/default_sea.tres")
var failures := 0

func check(ok: bool, label: String) -> void:
 print("PASS: " if ok else "FAIL: ", label)
 if not ok: failures += 1

func _initialize() -> void:
 create_timer(600).timeout.connect(func(): printerr("FAIL: weather watchdog"); quit(1))
 call_deferred("run")

func run() -> void:
 var defaults: Dictionary = Weather.sea_defaults()
 _test_conventions()
 _test_sea_layers()
 _restore(defaults)
 _test_rogue()
 _restore(defaults)
 _test_surf_and_heel()
 _restore(defaults)
 await _test_world()
 check(is_equal_approx(SEA.get("wind_speed"), defaults.wind_speed) and SEA.rogue().is_empty() and is_same(SEA.components(0.0, 32), SEA.long_waves(32)), "closing the world restores the sea state file")
 print("Weather: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
 quit(0 if failures == 0 else 1)

func _restore(defaults: Dictionary) -> void:
 for key in defaults: SEA.set(key, defaults[key])
 SEA.reset_live()

func _test_conventions() -> void:
 var ok := true
 for bearing in [0.0, 45.0, 90.0, 180.0, 270.0, 333.0]:
  ok = ok and absf(wrapf(Weather.from_heading(Weather.heading_from(bearing)) - bearing, -180.0, 180.0)) < 0.01
 check(ok, "compass bearing <-> heading round trip")
 # Wind from the north blows toward +Z (south).
 var h := Weather.heading_from(0.0)
 check(Vector2(cos(h), sin(h)).distance_to(Vector2(0, 1)) < 0.001, "wind from 000 blows toward the south (+Z)")
 check(Weather.beaufort(8.0) == 5 and Weather.beaufort(25.0) == 10, "Beaufort force from wind speed")

## A storm arriving: the new sea grows in over sea_response while the old one
## decays; heights at a fixed point never jump between ticks.
func _test_sea_layers() -> void:
 SEA.reset_live()
 SEA.evolve(0.0, 32)
 var calm_height: float = SEA.live_height(0.0, 32)
 SEA.set("wind_speed", 25.0)
 SEA.set("fetch", 400000.0)
 SEA.set("swell_height", 4.5)
 SEA.set("swell_period", 14.0)
 var storm_height: float = SEA.live_height(0.0, 32) # still the old layer
 var target: float = 4.0 * sqrt(_variance(SEA.long_waves(32)))
 var worst := 0.0
 var previous := NAN
 var t := 0.0
 var dt := 1.0 / 60.0
 var response: float = SEA.get("sea_response")
 while t < response * 2.2:
  SEA.evolve(t, 32)
  var y: float = SEA.heights(PackedVector2Array([Vector2(3.0, -2.0)]), t, 32)[0]
  if not is_nan(previous): worst = maxf(worst, absf(y - previous))
  previous = y
  t += dt
 var final: float = SEA.live_height(t, 32)
 print("SEA fair ", calm_height, " m -> storm long band ", target, " m; after build-up ", final, " m; worst tick step ", worst, " m")
 check(absf(storm_height - calm_height) < 0.01, "a new wind does not change the sea instantly")
 check(absf(final - target) < 0.05 * target, "the sea settles to the new state's height")
 check(worst < 0.12, "no jumps in the surface while the sea builds (<12 cm per tick)")
 SEA.settle(t, 32)
 check(absf(SEA.live_height(t, 32) - target) < 0.01, "settle jumps to the new sea")

static func _variance(table: Dictionary) -> float:
 var v := 0.0
 for i in range(table.count): v += table.amplitude[i] * table.amplitude[i] * 0.5
 return v

## Dispersive focusing: the rogue group is dispersed until its focus time.
func _test_rogue() -> void:
 SEA.reset_live()
 SEA.evolve(0.0, 32)
 var focus := Vector2(-120.0, 35.0)
 SEA.spawn_rogue(0.0, 60.0, focus, 8.0, 32)
 var rogue: Dictionary = SEA.rogue()
 var at_focus := _group_height(rogue.table, focus, 60.0)
 var early := 0.0
 for dx in range(-60, 61, 4):
  early = maxf(early, _group_height(rogue.table, focus + Vector2(dx, 0.0), 30.0))
 print("ROGUE group crest ", at_focus, " m at the focus; highest within 60 m half a minute earlier ", early, " m")
 check(at_focus > 7.9, "the group focuses to its full crest at the focus point and time")
 check(early < 0.5 * at_focus, "30 s earlier the group is dispersed (under half the crest)")
 var surface: float = SEA.surface(focus.x, focus.y, 60.0, 32).position.y
 check(surface > 6.0, "the live surface stands over 6 m at the focus")
 SEA.evolve(200.0, 32)
 check(SEA.rogue().is_empty(), "the rogue group is dropped after it passes")

static func _group_height(table: Dictionary, p: Vector2, t: float) -> float:
 var y := 0.0
 for i in range(table.count):
  y += table.amplitude[i] * sin(table.kx[i] * p.x + table.kz[i] * p.y - table.omega[i] * t + table.phase[i])
 return y

func _test_surf_and_heel() -> void:
 # A big sea running east; the ship running before it at speed.
 SEA.set("wind_speed", 20.0)
 SEA.set("wind_heading", 0.0)
 SEA.set("fetch", 300000.0)
 SEA.set("swell_height", 4.0)
 SEA.set("swell_period", 12.0)
 SEA.set("swell_heading", 0.0)
 SEA.reset_live()
 var motion = Motion.new()
 motion.start_heading = 0.0
 motion.reset_navigation()
 motion.wind_vector = Vector2(20.0, 0.0)
 motion.speed = 6.5
 var surf_max := 0.0
 var fastest := 0.0
 for i in range(60 * 90):
  motion.wind_vector = Vector2(20.0, 0.0)
  motion.step(float(i) / 60.0, 1.0 / 60.0, 32)
  surf_max = maxf(surf_max, motion.surf)
  fastest = maxf(fastest, motion.speed)
 var steady: float = motion.steady_speed(1.0, 0.0)
 print("SURF running before a 20 m/s gale: surf up to ", surf_max, " m/s^2; top speed ", fastest / 0.514444, " kn (steady ", steady / 0.514444, " kn)")
 check(surf_max > 0.3, "a following sea drives the hull down its faces (surfing)")
 check(fastest > steady * 1.05, "surfing carries her faster than the wind alone")
 # On the quarter: the same seas slew her round.
 motion.start_heading = deg_to_rad(40.0)
 motion.reset_navigation()
 motion.speed = 6.5
 var broach_max := 0.0
 for i in range(60 * 90):
  motion.wind_vector = Vector2(20.0, 0.0)
  motion.step(float(i) / 60.0, 1.0 / 60.0, 32)
  broach_max = maxf(broach_max, absf(motion.broach))
 print("BROACH with the sea on the quarter: yaw forcing up to ", broach_max, " rad/s^2")
 check(broach_max > 0.004, "a sea on the quarter makes her broach")
 # Heel: a storm on the beam overpresses full canvas; reefed she stands up.
 motion.start_heading = PI * 0.5
 motion.reset_navigation()
 # Heading north, a storm blowing east: wind on the port beam.
 motion.wind_vector = Vector2(25.0, 0.0)
 var full: float = motion.heel_target(1.0, motion.forward(), 6.0)
 var reefed: float = motion.heel_target(0.35, motion.forward(), 6.0)
 print("HEEL beam storm: full canvas ", rad_to_deg(full), " deg, reefed ", rad_to_deg(reefed), " deg")
 check(absf(full) > motion.OVERPRESSED, "full canvas in a storm is overpressed")
 check(absf(reefed) < motion.OVERPRESSED, "reefed down she carries it")
 # Knockdown: a breaking sea on the beam throws her over.
 SEA.reset_live()
 motion.start_heading = 0.0
 motion.wind_vector = Vector2(0.0, 8.0)
 motion.pose_at(10.0, 32)
 motion.strike("beam", 1.0)
 var roll_max := 0.0
 for i in range(60 * 10):
  motion.step(10.0 + float(i) / 60.0, 1.0 / 60.0, 32)
  roll_max = maxf(roll_max, motion.roll)
 print("KNOCKDOWN beam sea from port: rolled ", rad_to_deg(roll_max), " deg to starboard")
 check(roll_max > deg_to_rad(20.0) and roll_max < deg_to_rad(45.0), "a beam-on breaking sea knocks her down 20..45 degrees")

func _test_world() -> void:
 var world = load("res://scenes/main.tscn").instantiate()
 root.add_child(world)
 var player: CharacterBody3D = world.get_node("Player")
 var weather: Node = world.weather
 var motion = world.buoyancy
 player.test_input = true
 player.move_input = Vector2.ZERO
 weather.current.gustiness = 0.0
 weather.target.gustiness = 0.0
 for i in range(10): await physics_frame
 check(weather.current.wind_speed == 8.0 and weather.dynamic, "the voyage starts in fair, changing weather")
 # Sails.
 var rig = world.sail_rig
 check(rig != null and rig.sail_count == 4, "four square sails rigged for the wind")
 for i in range(150): await process_frame
 print("SAILS on a beam reach: fill ", rig.fill, ", luff ", rig.luff)
 check(rig.fill > 0.5 and rig.luff < 0.2, "on a beam reach the sails fill")
 # Head to wind: wind from the bow (heading east, 090).
 weather.current.wind_from = 90.0
 weather.target.wind_from = 90.0
 for i in range(240): await process_frame
 print("SAILS head to wind: fill ", rig.fill)
 check(rig.fill < -0.2, "head to wind the sails are taken aback")
 weather.current.wind_from = 7.0
 weather.target.wind_from = 7.0
 # HUD notices.
 weather.notice.emit("A test notice", 2.0)
 check(world.hud.notice_label.text == "A test notice", "weather notices reach the HUD")
 # Weather menu.
 var menu = world.weather_menu
 menu.toggle()
 check(menu.is_open(), "Tab opens the weather menu")
 menu.sliders["wind_speed"].value = 20.0
 check(weather.target.wind_speed == 20.0 and not weather.dynamic, "a slider sets the wind and stops the fronts")
 menu._preset("Storm")
 check(weather.target.wind_speed == 25.0 and is_equal_approx(menu.sliders["wind_speed"].value, 25.0) and absf(menu.sliders["fetch"].value - log(Weather.PRESETS.Storm.fetch / 1000.0) / log(10.0)) < 0.02, "a preset sets every target and the sliders follow")
 for i in range(5): await physics_frame
 check(weather.current.wind_speed > 8.0 and weather.current.wind_speed < 12.0, "the wind freshens gradually toward the target")
 menu.toggle()
 check(not menu.is_open(), "Tab closes the menu")
 weather.apply_preset("Fair")
 weather.target.gustiness = 0.0
 weather.settle_now()
 # A knockdown throws an unbraced player across the deck; braced, they hold.
 var thrown := await _knockdown(world, player, false)
 var held := await _knockdown(world, player, true)
 print("DECK knockdown: unbraced player thrown ", thrown, " m; braced ", held, " m")
 check(thrown > 0.8, "a knockdown throws an unbraced player across the deck")
 check(held < 0.3, "a braced player holds on")
 # A rogue wave summoned from the menu is called by the lookout.
 var calls: Array[String] = []
 weather.notice.connect(func(text: String, _s: float) -> void: calls.append(text))
 weather.summon_rogue(25.0)
 for i in range(60 * 5): await physics_frame
 check(calls.any(func(c: String) -> bool: return c.begins_with("Rogue wave!")), "the lookout calls a rogue wave's bearing")
 for i in range(60 * 22): await physics_frame
 check(calls.any(func(c: String) -> bool: return "rogue wave" in c.to_lower() and not c.begins_with("Rogue wave!")), "the rogue wave's outcome is judged when it arrives")
 var met: Dictionary = weather.rogues_met
 check(met.bow + met.beam + met.stern == 1, "the ship's log counts the rogue wave")
 world.queue_free()
 await process_frame
 await process_frame

## Ship-space distance the player is carried by a beam knockdown in 5 s.
func _knockdown(world: Node, player: CharacterBody3D, braced: bool) -> float:
 # x = 3.5 is clear deck from rail to rail (no hatch or gratings).
 var start := Vector3(3.5, 2.8, -1.5)
 player.global_position = world.ship_body.to_global(start + Vector3.UP * 0.1)
 player.ship_position = start + Vector3.UP * 0.1
 player.ship_velocity = Vector3.ZERO
 player._carry_initialized = true
 player.sea_legs.reset()
 player.test_brace = braced
 player.move_input = Vector2.ZERO
 # Let the ship settle from any previous knockdown.
 for i in range(60 * 20): await physics_frame
 var before: Vector3 = player.ship_position
 world.buoyancy.strike("beam", 1.0)
 var furthest := 0.0
 for i in range(60 * 5):
  await physics_frame
  furthest = maxf(furthest, Vector2(player.ship_position.x - before.x, player.ship_position.z - before.z).length())
 player.test_brace = false
 print("DECK after the knockdown the player is at ", player.ship_position, (" (braced)" if braced else ""))
 check(not player._respawning and absf(player.ship_position.z) < 2.8 and player.ship_position.y > 2.3, "the player stays aboard, fetched up against the bulwark")
 return furthest
