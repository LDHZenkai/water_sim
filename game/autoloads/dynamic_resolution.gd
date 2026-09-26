extends RefCounted
## GPU milliseconds only. Long recovery hold and asymmetric rates prevent hunting.
const TARGET_MS := 16.6
var filtered_ms := 0.0
var high_seconds := 0.0
var low_seconds := 0.0
var scale := 1.0
var desired_scale := 1.0
var resize_seconds := 0.0
var ceiling := 1.0
var floor_scale := 0.8
func reset(base_scale: float) -> void:
 ceiling=base_scale
 # Explicit render-scale remains the ceiling; scales below 0.8 stay fixed.
 floor_scale=minf(0.8,ceiling)
 scale=ceiling
 desired_scale=ceiling
 resize_seconds=0.0
 filtered_ms=0.0
 high_seconds=0.0
 low_seconds=0.0
func step(gpu_ms: float, delta: float) -> float:
 if gpu_ms<=0 or not is_finite(gpu_ms):return scale
 var dt:=clampf(delta,0.0,0.1)
 resize_seconds+=dt
 filtered_ms=gpu_ms if filtered_ms==0 else lerpf(filtered_ms,gpu_ms,1.0-exp(-dt/0.20))
 if filtered_ms>TARGET_MS+0.6:
  high_seconds+=dt
  low_seconds=0.0
  if high_seconds>0.18:desired_scale=maxf(floor_scale,desired_scale-dt*0.12)
 elif filtered_ms<TARGET_MS-1.8:
  low_seconds+=dt
  high_seconds=0.0
  if low_seconds>0.9:desired_scale=minf(ceiling,desired_scale+dt*0.06)
 else:
  high_seconds=0.0
  low_seconds=0.0
 # Mobile reallocates render buffers when scale changes: apply eased demand
 # at most four times per second, on a 2% grid, with exact endpoint recovery.
 var endpoint:=is_equal_approx(desired_scale,ceiling) or is_equal_approx(desired_scale,floor_scale)
 if resize_seconds>=0.25 and (absf(desired_scale-scale)>=0.02 or endpoint):
  scale=clampf(snappedf(desired_scale,0.02),floor_scale,ceiling)
  if endpoint:scale=desired_scale
  resize_seconds=0.0
 return scale
