extends Resource
## Physical sea state shared by the CPU (buoyancy, swimming, tests) and GPU.
## Wind sea: fetch-limited JONSWAP (Hasselmann et al. 1973) with
## Donelan-Banner (1985) directional spreading. Swell: a narrow JONSWAP scaled
## to its significant height, with Gaussian spreading about its heading.
## Waves longer than split_wavelength become explicit components evaluated
## identically here and in the ocean vertex shader. Shorter waves only exist in
## the GPU FFT cascades (fft_ocean.gd), sampled from the same spectrum, so the
## two bands never double count energy.
const GRAVITY := 9.81
const MAX_LONG_WAVES := 64

@export_group("Wind sea")
## Wind speed 10 m above the surface, m/s.
@export var wind_speed := 8.0
## Open water upwind, m. Short fetch gives a young, steep, short sea.
@export var fetch := 30000.0
## Radians; wind waves travel along (cos, sin) in world XZ.
@export var wind_heading := 1.7
## JONSWAP peak enhancement gamma (1 = Pierson-Moskowitz, 3.3 = mean North Sea).
@export var peak_enhancement := 3.3
@export_group("Swell")
## Significant height Hs of the swell system, m.
@export var swell_height := 2.4
## Swell peak period, s.
@export var swell_period := 12.0
@export var swell_heading := 1.0
## Directional standard deviation, radians. Old swell is narrow.
@export var swell_spread := 0.15
@export var swell_enhancement := 5.0
@export_group("Surface")
## Horizontal (Lagrangian) displacement scale: 0 is linear Airy, 1 is full
## Tessendorf choppiness. Sharpens crests and makes the Jacobian fold.
@export var choppiness := 0.85
## Waves at least this long are explicit components (CPU and vertex shader).
@export var split_wavelength := 12.0
## Water velocity past the ship, m/s (Galilean frame: a ship making way).
@export var current := Vector2.ZERO
@export var noise_seed := 1729

var _tables := {}
var _swell_scale := {}

func wind_peak() -> float:
 # Fetch-limited peak, never below the fully developed Pierson-Moskowitz peak.
 return maxf(22.0*pow(GRAVITY*GRAVITY/(wind_speed*fetch),1.0/3.0),0.855*GRAVITY/wind_speed)

func wind_alpha() -> float:
 return maxf(0.076*pow(wind_speed*wind_speed/(fetch*GRAVITY),0.22),0.0081)

func swell_peak() -> float:
 return TAU/swell_period

func swell_alpha() -> float:
 # Scale the unit-alpha shape so its variance is Hs^2/16.
 var key := Vector3(swell_height,swell_period,swell_enhancement)
 if _swell_scale.has(key): return _swell_scale[key]
 var peak := swell_peak()
 var total := 0.0
 var step := peak*0.002
 var omega := peak*0.3+step*0.5
 while omega < peak*10.0:
  total += jonswap(omega,peak,1.0,swell_enhancement)*step
  omega += step
 _swell_scale[key] = swell_height*swell_height/16.0/total if total > 0.0 else 0.0
 return _swell_scale[key]

static func jonswap(omega: float, peak: float, alpha: float, gamma: float) -> float:
 if omega <= 0.0 or peak <= 0.0: return 0.0
 var sigma := 0.07 if omega <= peak else 0.09
 var shape := exp(-pow(omega-peak,2.0)/(2.0*sigma*sigma*peak*peak))
 return alpha*GRAVITY*GRAVITY/pow(omega,5.0)*exp(-1.25*pow(peak/omega,4.0))*pow(gamma,shape)

## Donelan-Banner sech^2 spreading width at omega/omega_peak.
static func donelan_beta(ratio: float) -> float:
 if ratio < 0.95: return 2.61*pow(maxf(ratio,0.56),1.3)
 if ratio < 1.6: return 2.28*pow(ratio,-1.3)
 return pow(10.0,-0.4+0.8393*exp(-0.567*log(ratio*ratio)))

## Frequency spectra (wind, swell), m^2 s.
func frequency_spectrum(omega: float) -> Vector2:
 return Vector2(jonswap(omega,wind_peak(),wind_alpha(),peak_enhancement),jonswap(omega,swell_peak(),swell_alpha(),swell_enhancement))

func significant_height() -> float:
 var total := 0.0
 var omega := 0.05
 while omega < 40.0:
  var s := frequency_spectrum(omega)
  total += (s.x+s.y)*0.002
  omega += 0.002
 return 4.0*sqrt(total)

## Height variance of the spectrum between two wavenumbers, m^2.
func height_variance(k_low: float, k_high: float) -> float:
 if k_high <= k_low: return 0.0
 var low := log(sqrt(GRAVITY*maxf(k_low,0.0001)))
 var high := log(sqrt(GRAVITY*k_high))
 var total := 0.0
 var steps := 4096
 var step := (high-low)/float(steps)
 for i in range(steps):
  var omega := exp(low+(float(i)+0.5)*step)
  var s := frequency_spectrum(omega)
  total += (s.x+s.y)*omega*step
 return total

## Mean square slope (both axes) of the spectrum between two wavenumbers.
func slope_variance(k_low: float, k_high: float) -> float:
 if k_high <= k_low: return 0.0
 var low := log(sqrt(GRAVITY*maxf(k_low,0.0001)))
 var high := log(sqrt(GRAVITY*k_high))
 var total := 0.0
 var steps := 4096
 var step := (high-low)/float(steps)
 for i in range(steps):
  var omega := exp(low+(float(i)+0.5)*step)
  var s := frequency_spectrum(omega)
  var k := omega*omega/GRAVITY
  total += (s.x+s.y)*k*k*omega*step
 return total

## Cox and Munk (1954) sun-glitter measurement of total mean square slope.
func cox_munk_variance() -> float:
 return 0.003+0.00512*wind_speed

func split_frequency() -> float:
 return sqrt(GRAVITY*TAU/split_wavelength)

func _signature() -> String:
 return var_to_str([wind_speed,fetch,wind_heading,peak_enhancement,swell_height,swell_period,swell_heading,swell_spread,swell_enhancement,choppiness,split_wavelength,noise_seed])

## Cumulative energy table of one system between low and high (rad/s).
func _band(system: int, low: float, high: float) -> Dictionary:
 var omegas := PackedFloat64Array()
 var cumulative := PackedFloat64Array()
 var total := 0.0
 if high > low:
  var steps := 2048
  var step := (high-low)/float(steps)
  omegas.append(low)
  cumulative.append(0.0)
  for i in range(steps):
   var omega := low+(float(i)+0.5)*step
   var s := frequency_spectrum(omega)
   total += (s.x if system == 0 else s.y)*step
   omegas.append(low+float(i+1)*step)
   cumulative.append(total)
 return {"energy":total,"omegas":omegas,"cumulative":cumulative}

static func _quantile(band: Dictionary, u: float) -> float:
 var cumulative: PackedFloat64Array = band.cumulative
 var omegas: PackedFloat64Array = band.omegas
 var target: float = u*float(band.energy)
 var index := cumulative.bsearch(target)
 index = clampi(index,1,cumulative.size()-1)
 var a := cumulative[index-1]
 var b := cumulative[index]
 var f := 0.0 if b <= a else (target-a)/(b-a)
 return lerpf(omegas[index-1],omegas[index],f)

## Explicit long-wave components, deterministic for (parameters, count).
## Single-summation model: every component has its own frequency (stratified
## equal-energy quantiles) and a direction drawn from that frequency's
## spreading function, so no two components phase-lock into a pattern.
## Height of component i is a_i sin(k_i.x - w_i t + p_i).
func long_waves(count: int) -> Dictionary:
 count = clampi(count,1,MAX_LONG_WAVES)
 var key := str(count)+_signature()
 if _tables.has(key): return _tables[key]
 var rng := RandomNumberGenerator.new()
 rng.seed = noise_seed
 var split := split_frequency()
 var bands := [_band(0,wind_peak()*0.5,split),_band(1,swell_peak()*0.5,split)]
 var total: float = bands[0].energy+bands[1].energy
 var swell_count := 0
 if total > 0.0:
  swell_count = clampi(roundi(float(count)*bands[1].energy/total),0,count)
  if bands[1].energy > 0.0 and swell_count == 0: swell_count = 1
  if bands[0].energy > 0.0 and swell_count == count and count > 1: swell_count = count-1
 var counts := [count-swell_count,swell_count]
 var table := {"count":count,"kx":PackedFloat64Array(),"kz":PackedFloat64Array(),"omega":PackedFloat64Array(),"amplitude":PackedFloat64Array(),"horizontal":PackedFloat64Array(),"phase":PackedFloat64Array(),"gpu":PackedVector4Array()}
 for system in range(2):
  var n: int = counts[system]
  if n == 0: continue
  var band: Dictionary = bands[system]
  var amplitude := sqrt(2.0*float(band.energy)/float(n))
  # Stratified direction quantiles, shuffled so frequency and direction are independent.
  var direction_u := PackedFloat64Array()
  for i in range(n): direction_u.append((float(i)+rng.randf())/float(n))
  for i in range(n-1,0,-1):
   var j := rng.randi_range(0,i)
   var swap := direction_u[i]
   direction_u[i] = direction_u[j]
   direction_u[j] = swap
  for i in range(n):
   var omega := _quantile(band,(float(i)+rng.randf())/float(n))
   var heading: float
   if system == 0:
    var beta := donelan_beta(omega/wind_peak())
    var x := (2.0*direction_u[i]-1.0)*tanh(beta*PI)
    heading = wind_heading+0.5*log((1.0+x)/(1.0-x))/beta
   else:
    # Inverse normal CDF (Acklam-free approximation via erf inverse series).
    heading = swell_heading+swell_spread*_normal_quantile(direction_u[i])
   var k := omega*omega/GRAVITY
   table.kx.append(k*cos(heading))
   table.kz.append(k*sin(heading))
   table.omega.append(omega)
   table.amplitude.append(amplitude)
   table.horizontal.append(amplitude*choppiness)
   table.phase.append(rng.randf()*TAU)
   table.gpu.append(Vector4(k*cos(heading),k*sin(heading),amplitude,amplitude*choppiness))
 table.count = table.kx.size()
 _tables[key] = table
 return table

static func _normal_quantile(u: float) -> float:
 # Winitzki approximation of the inverse error function; |error| < 2e-3.
 var x := clampf(2.0*u-1.0,-0.999999,0.999999)
 var a := 0.147
 var ln := log(1.0-x*x)
 var first := 2.0/(PI*a)+ln*0.5
 return signf(x)*sqrt(2.0)*sqrt(sqrt(first*first-ln/a)-first)

## Per-component phase offsets at time t, wrapped in double precision so the
## GPU never evaluates sin() of a large float. Includes the current (a
## Galilean shift of the whole wave field past the ship).
func phases(time: float, count: int) -> PackedFloat32Array:
 var table := long_waves(count)
 var result := PackedFloat32Array()
 result.resize(MAX_LONG_WAVES)
 var kx: PackedFloat64Array = table.kx
 var kz: PackedFloat64Array = table.kz
 var omega: PackedFloat64Array = table.omega
 var phase: PackedFloat64Array = table.phase
 for i in range(kx.size()):
  result[i] = fposmod(phase[i]-(omega[i]+kx[i]*current.x+kz[i]*current.y)*time,TAU)
 return result

func _phases64(table: Dictionary, time: float) -> PackedFloat64Array:
 var kx: PackedFloat64Array = table.kx
 var kz: PackedFloat64Array = table.kz
 var omega: PackedFloat64Array = table.omega
 var phase: PackedFloat64Array = table.phase
 var result := PackedFloat64Array()
 result.resize(kx.size())
 for i in range(kx.size()):
  result[i] = fposmod(phase[i]-(omega[i]+kx[i]*current.x+kz[i]*current.y)*time,TAU)
 return result

## Lagrangian forward map at the undisplaced point q. Returns
## [dx, dy, dz, dDx/dqx, dDx/dqz, dDz/dqx, dDz/dqz, dy/dqx, dy/dqz].
func _sample(table: Dictionary, offsets: PackedFloat64Array, q: Vector2) -> PackedFloat64Array:
 var kx: PackedFloat64Array = table.kx
 var kz: PackedFloat64Array = table.kz
 var amplitude: PackedFloat64Array = table.amplitude
 var horizontal: PackedFloat64Array = table.horizontal
 var r := PackedFloat64Array([0,0,0,0,0,0,0,0,0])
 for i in range(kx.size()):
  var ax := kx[i]
  var az := kz[i]
  var k := sqrt(ax*ax+az*az)
  var angle := ax*q.x+az*q.y+offsets[i]
  var s := sin(angle)
  var c := cos(angle)
  var a := amplitude[i]
  var h := horizontal[i]/k
  r[0] += h*ax*c
  r[1] += a*s
  r[2] += h*az*c
  r[3] -= h*ax*ax*s
  r[4] -= h*ax*az*s
  r[5] -= h*az*ax*s
  r[6] -= h*az*az*s
  r[7] += a*ax*c
  r[8] += a*az*c
 return r

## Forward map as a dictionary (position of the displaced point and normal).
func displacement(q: Vector2, time: float, count: int) -> Dictionary:
 var table := long_waves(count)
 var r := _sample(table,_phases64(table,time),q)
 return {"position":Vector3(q.x+r[0],r[1],q.y+r[2]),"normal":_normal(r)}

static func _normal(r: PackedFloat64Array) -> Vector3:
 var tx := Vector3(1.0+r[3],r[7],r[5])
 var tz := Vector3(r[4],r[8],1.0+r[6])
 return tz.cross(tx).normalized()

## Surface through the world point (x, z) at time t: Newton inversion of the
## horizontal Lagrangian map with its exact 2x2 Jacobian.
func surface(x: float, z: float, time: float, count: int = 32) -> Dictionary:
 var table := long_waves(count)
 var offsets := _phases64(table,time)
 var target := Vector2(x,z)
 var q := target
 var r: PackedFloat64Array
 for iteration in range(4):
  r = _sample(table,offsets,q)
  var ex := q.x+r[0]-x
  var ez := q.y+r[2]-z
  var a := 1.0+r[3]
  var b := r[4]
  var c := r[5]
  var d := 1.0+r[6]
  var det := a*d-b*c
  q -= Vector2(d*ex-b*ez,-c*ex+a*ez)/det
 r = _sample(table,offsets,q)
 return {"position":Vector3(q.x+r[0],r[1],q.y+r[2]),"normal":_normal(r)}

## Batched heights for buoyancy probes (two Newton steps; sub-mm here because
## the long band is gentle). One pass over the components per iteration.
func heights(points: PackedVector2Array, time: float, count: int) -> PackedFloat64Array:
 var table := long_waves(count)
 var offsets := _phases64(table,time)
 var kx: PackedFloat64Array = table.kx
 var kz: PackedFloat64Array = table.kz
 var amplitude: PackedFloat64Array = table.amplitude
 var horizontal: PackedFloat64Array = table.horizontal
 var n := kx.size()
 var inverse_k := PackedFloat64Array()
 inverse_k.resize(n)
 for i in range(n): inverse_k[i] = horizontal[i]/sqrt(kx[i]*kx[i]+kz[i]*kz[i])
 var result := PackedFloat64Array()
 result.resize(points.size())
 for p in range(points.size()):
  var tx := points[p].x
  var tz := points[p].y
  var qx := tx
  var qz := tz
  var height := 0.0
  for iteration in range(3):
   var dx := 0.0
   var dz := 0.0
   var jxx := 1.0
   var jxz := 0.0
   var jzz := 1.0
   height = 0.0
   for i in range(n):
    var ax := kx[i]
    var az := kz[i]
    var angle := ax*qx+az*qz+offsets[i]
    var s := sin(angle)
    var c := cos(angle)
    var h := inverse_k[i]
    height += amplitude[i]*s
    dx += h*ax*c
    dz += h*az*c
    var hs := h*s
    jxx -= hs*ax*ax
    jxz -= hs*ax*az
    jzz -= hs*az*az
   if iteration == 2: break
   var ex := qx+dx-tx
   var ez := qz+dz-tz
   var det := jxx*jzz-jxz*jxz
   qx -= (jzz*ex-jxz*ez)/det
   qz -= (-jxz*ex+jxx*ez)/det
  result[p] = height
 return result

## Parameters for the GPU spectrum (fft_ocean.gd push constants).
func gpu_spectrum() -> PackedFloat32Array:
 return PackedFloat32Array([wind_alpha(),wind_peak(),peak_enhancement,wind_heading,swell_alpha(),swell_peak(),swell_enhancement,swell_heading,swell_spread,split_frequency()*split_frequency()/GRAVITY,choppiness,float(noise_seed)])
