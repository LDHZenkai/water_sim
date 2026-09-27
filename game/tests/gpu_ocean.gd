extends SceneTree
# GPU ocean physics checks. Needs a RenderingDevice, so run windowed (e.g.
# under Xvfb), not --headless:  godot --path game -s res://tests/gpu_ocean.gd
# 1. FFT cascades: height and slope variance match the spectrum in each band,
#    crests are compressed (J < 1), the field repeats exactly with its period.
# 2. Wake solver: still water stays still; a heaving hull radiates waves whose
#    wavelength obeys deep-water dispersion; a current draws a Kelvin wake
#    (downstream only, inside the 19.5 degree wedge); the sponge absorbs.
const SeaState = preload("res://ocean/sea_state.gd")
const FftOcean = preload("res://ocean/fft_ocean.gd")
const WakeSim = preload("res://ocean/wake_sim.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
 print("PASS: " if ok else "FAIL: ", label)
 if not ok: failures += 1

func _initialize() -> void:
 create_timer(600).timeout.connect(func(): printerr("FAIL: gpu_ocean watchdog"); quit(1))
 call_deferred("run")

func run() -> void:
 if RenderingServer.get_rendering_device() == null:
  print("SKIP: no RenderingDevice (run windowed, not --headless)")
  quit(0)
  return
 await _test_fft()
 await _test_wake()
 print("GPU ocean: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
 quit(0 if failures == 0 else 1)

func _test_fft() -> void:
 var sea = load("res://ocean/default_sea.tres")
 var fft = FftOcean.new(sea, 256)
 fft.update(37.0, 0.0)
 await process_frame
 var first: Array[Image] = []
 for layer in range(3):
  var displacement: Image = fft.read_layer(0, layer)
  var slopes: Image = fft.read_layer(1, layer)
  first.append(displacement)
  var band: Vector3 = fft.bands[layer]
  var mean := 0.0
  var squares := 0.0
  var slope_squares := 0.0
  var covariance := 0.0
  var jacobian_mean := 0.0
  var jacobian_min := INF
  var cells := 256*256
  for y in range(256):
   for x in range(256):
    var d := displacement.get_pixel(x, y)
    var s := slopes.get_pixel(x, y)
    mean += d.g/cells
    squares += d.g*d.g/cells
    slope_squares += (s.r*s.r+s.g*s.g)/cells
    jacobian_mean += s.a/cells
    covariance += d.g*s.a/cells
    jacobian_min = minf(jacobian_min, s.a)
  var variance := squares-mean*mean
  var expected: float = sea.height_variance(band.y, band.z)
  var expected_slope: float = sea.slope_variance(band.y, band.z)
  var correlation := covariance-mean*jacobian_mean
  print("CASCADE ", layer, ": tile=", band.x, " m band=", band.y, "..", band.z, " rad/m; height var=", variance, " (spectrum ", expected, "); slope var=", slope_squares, " (spectrum ", expected_slope, "); J mean=", jacobian_mean, " min=", jacobian_min, " cov(Y,J)=", correlation)
  check(absf(variance/expected-1.0) < 0.25, "cascade %d height variance within 25%% of the spectrum" % layer)
  check(absf(slope_squares/expected_slope-1.0) < 0.35, "cascade %d slope variance within 35%% of the spectrum" % layer)
  check(absf(mean) < 0.05*sqrt(expected)+1e-4, "cascade %d has zero mean height" % layer)
  check(correlation < 0.0, "cascade %d crests are compressed (height and Jacobian anti-correlated)" % layer)
  check(absf(jacobian_mean-1.0) < 0.05, "cascade %d Jacobian averages to 1 (area preserving)" % layer)
 # Quantised dispersion: the whole field repeats exactly after the period.
 fft.update(37.0+FftOcean.REPEAT_PERIOD, 0.0)
 await process_frame
 var repeat_error := 0.0
 for layer in range(3):
  var again: Image = fft.read_layer(0, layer)
  for y in range(0, 256, 4):
   for x in range(0, 256, 4):
    repeat_error = maxf(repeat_error, absf(again.get_pixel(x, y).g-first[layer].get_pixel(x, y).g))
 print("FFT repeat error after ", FftOcean.REPEAT_PERIOD, " s: ", repeat_error, " m")
 check(repeat_error < 0.002, "FFT field repeats exactly with its quantised period")
 fft.release()
 await process_frame

## Flat sea and a smooth parabolic hull (20 x 6 m, 2 m draft amidships,
## fine ends like a real hull) on a 128 m domain.
func _wake(current: Vector2) -> Array:
 var sea = SeaState.new()
 sea.wind_speed = 0.5
 sea.fetch = 1000.0
 sea.swell_height = 0.0001
 sea.current = current
 var keel := PackedFloat32Array()
 for z in range(64):
  for x in range(192):
   var px := -16.0+float(x)*39.0/191.0
   var pz := -6.0+float(z)*12.0/63.0
   var draft := 2.0*(1.0-pow(px/10.0,2.0))*(1.0-pow(pz/3.0,2.0))
   keel.append(0.6-draft if absf(px) < 10.0 and absf(pz) < 3.0 else 100.0)
 var image := Image.create_from_data(192, 64, false, Image.FORMAT_RF, keel.to_byte_array())
 var wake = WakeSim.new(sea, 8, 256, 128.0, ImageTexture.create_from_image(image), Callable(), [])
 await process_frame
 return [wake, sea]

func _test_wake() -> void:
 var made: Array = await _wake(Vector2.ZERO)
 var wake = made[0]
 var dt := 1.0/60.0
 var rest := Transform3D(Basis.IDENTITY, Vector3(0, -0.6, 0))
 for i in range(120):
  wake.step(rest, float(i)*dt, dt)
 wake.flush()
 await process_frame
 var still: Image = wake.read_layer(0)
 var still_flow: Image = wake.read_layer(1)
 var still_max := 0.0
 var covered_max := 0.0
 for y in range(256):
  for x in range(256):
   var h := absf(still.get_pixel(x, y).r)
   # Under the hull (P > 0) the rendered surface is hidden by the hull.
   if still_flow.get_pixel(x, y).b > 0.0: covered_max = maxf(covered_max, h)
   else: still_max = maxf(still_max, h)
 print("WAKE still water: max |deviation| after 2 s = ", still_max, " m in open water, ", covered_max, " m under the hull")
 # Pointwise start vs per-mode discrete equilibrium (theta^2/12) plus grid
 # viscosity leave a few mm at the hull's kinks; far below visible chop.
 check(still_max < 0.01, "a resting hull in still water stays still (< 1 cm, no startup ring)")
 # Heave at 3 s period: radiated waves must have lambda = 2 pi g / w^2.
 var period := 3.0
 var t := 2.0
 for i in range(int(14.0/dt)):
  t += dt
  var pose := Transform3D(Basis.IDENTITY, Vector3(0, -0.6+0.25*sin(TAU*t/period), 0))
  wake.step(pose, t, dt)
  if i % 60 == 0: wake.flush()
 wake.flush()
 await process_frame
 var field: Image = wake.read_layer(0)
 var corner: Vector2 = wake.corner
 var texel: float = wake.texel
 var crossings: Array[float] = []
 var previous := 0.0
 var peak := 0.0
 for i in range(256):
  var z := corner.y+(float(i)+0.5)*texel
  if z < 12.0 or z > 48.0: continue
  var x := int(round((0.0-corner.x)/texel-0.5))
  var h: float = field.get_pixel(x, i).r
  peak = maxf(peak, absf(h))
  if previous != 0.0 and signf(h) != signf(previous):
   crossings.append(z)
  previous = h
 var measured := 0.0
 if crossings.size() >= 3:
  measured = 2.0*(crossings[-1]-crossings[0])/float(crossings.size()-1)
 var expected := TAU*9.81/pow(TAU/period, 2.0)
 print("WAKE heave radiation: peak=", peak, " m, crossings=", crossings.size(), ", wavelength=", measured, " m (deep-water dispersion ", expected, " m)")
 check(peak > 0.005 and peak < 0.5, "a heaving hull radiates bounded waves")
 check(absf(measured/expected-1.0) < 0.15, "radiated wavelength obeys w^2 = g k within 15%")
 # Stop and let the sponge absorb everything.
 for i in range(int(40.0/dt)):
  t += dt
  wake.step(rest, t, dt)
  if i % 60 == 0: wake.flush()
 wake.flush()
 await process_frame
 var after: Image = wake.read_layer(0)
 var residual := 0.0
 for y in range(0, 256, 2):
  for x in range(0, 256, 2):
   residual = maxf(residual, absf(after.get_pixel(x, y).r))
 print("WAKE after 40 s at rest: max |deviation| = ", residual, " m")
 check(residual < peak*0.25, "the sponge boundary absorbs radiated waves")
 wake.release()
 await process_frame
 # Current past a still hull: steady Kelvin wake, downstream only.
 made = await _wake(Vector2(-2.5, 0.0))
 wake = made[0]
 t = 0.0
 for i in range(int(40.0/dt)):
  t += dt
  wake.step(rest, t, dt)
  if i % 60 == 0: wake.flush()
 wake.flush()
 await process_frame
 field = wake.read_layer(0)
 corner = wake.corner
 var upstream := 0.0
 var downstream := 0.0
 var peak_at := Vector2.ZERO
 var inside := 0.0
 var outside := 0.0
 for y in range(256):
  for x in range(256):
   var p := corner+(Vector2(x, y)+Vector2(0.5, 0.5))*texel
   var h: float = field.get_pixel(x, y).r
   if absf(p.y) < 3.5 and absf(p.x) < 10.5: continue
   if absf(h) > absf(downstream) and p.x < -20.0 and p.x > -40.0: peak_at = p
   if p.x > 20.0 and p.x < 40.0: upstream = maxf(upstream, absf(h))
   if p.x < -20.0 and p.x > -40.0: downstream = maxf(downstream, absf(h))
   if p.x < -15.0 and p.x > -45.0:
    var behind := -10.0-p.x
    if absf(p.y) < 3.0+behind*tan(deg_to_rad(24.0)): inside += h*h
    else: outside += h*h
 print("WAKE with 2.5 m/s current: upstream max=", upstream, " m, downstream max=", downstream, " m at ", peak_at, ", energy inside 24 deg wedge=", inside/(inside+outside+1e-12))
 check(downstream > 3.0*upstream, "the wake trails downstream of the hull")
 check(downstream < 0.6, "wake height is plausible for a 20 m hull at 5 knots")
 check(inside/(inside+outside+1e-12) > 0.8, "wake energy stays inside the Kelvin wedge")
 wake.release()
 await process_frame
