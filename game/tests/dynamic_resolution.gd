extends SceneTree
func _initialize() -> void:
 var controller:=preload("res://autoloads/dynamic_resolution.gd").new()
 controller.reset(1.0)
 var good:=true
 var resizes:=0
 var last_resize:=-100
 for i in range(600):
  var previous: float=controller.scale
  controller.step(25.0,1.0/60)
  if controller.scale!=previous:
   good=good and i-last_resize>=15
   last_resize=i
   resizes+=1
 good=good and resizes<=10
 good=good and is_equal_approx(controller.scale,0.8)
 for i in range(600):controller.step(10.0,1.0/60)
 good=good and is_equal_approx(controller.scale,1.0)
 controller.reset(0.9)
 for i in range(600):controller.step(16.5 if i%2==0 else 17.0,1.0/60)
 good=good and is_equal_approx(controller.scale,0.9)
 good=good and controller.step(0.0,1.0/60)==controller.scale
 controller.reset(0.7)
 for i in range(600):controller.step(25.0,1.0/60)
 good=good and is_equal_approx(controller.scale,0.7)
 print("DYNRES TEST: ","PASS" if good else "FAIL", " (bounds, recovery, hysteresis, missing GPU timing, explicit scale)")
 quit(0 if good else 1)
