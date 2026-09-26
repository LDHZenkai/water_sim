extends SceneTree
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
 print("PASS: " if ok else "FAIL: ",label)
 if not ok: failures+=1
func run() -> void:
 var world=load("res://scenes/main.tscn").instantiate()
 root.add_child(world)
 world.freeze_at(0)
 if OS.get_environment("WATERLINE_GEOMETRY_ONLY")=="1":
  for sample in preload("res://tests/local_waterline.gd").samples(world): print(sample)
 else:
  preload("res://tests/local_waterline.gd").run(world,check,OS.get_environment("WATERLINE_FLOOD_CONTROL")=="1")
 world.free()
 quit(0 if failures==0 else 1)
