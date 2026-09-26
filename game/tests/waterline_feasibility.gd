extends SceneTree
# Diagnostic independent of buoyancy: three equally spaced sections of the
# measured waterline. Mean port/starboard heights cancel the plane's roll term.
# A linear plane cannot fit their second difference with max error < |D2|/4.
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 var world=load("res://scenes/main.tscn").instantiate()
 root.add_child(world)
 var bounds: Image=world.ocean.hull_image
 var row:=int(round(2.6/5.0*63.0))
 var profile=load("res://ocean/default_waves.tres")
 var maximum:=0.0
 var at_time:=0.0
 for tick in range(1200):
  var t:=float(tick)/10.0
  var heights: Array[float]=[]
  for col in [16,76,136]:
   var x:float=-14.0+float(col)/191.0*35.0
   var span:=bounds.get_pixel(col,row)
   heights.append((profile.surface(x,span.r,t,5).position.y+profile.surface(x,span.g,t,5).position.y)*0.5)
  var bound:float=absf(heights[0]-2.0*heights[1]+heights[2])/4.0
  if bound>maximum:
   maximum=bound
   at_time=t
 print("WATERLINE DIAGNOSTIC: minimum plane residual from 3-section curvature >= ",maximum," m at t=",at_time," s (unrotated footprint; section centre Z differs by <0.002 m)")
 world.free()
 quit()
