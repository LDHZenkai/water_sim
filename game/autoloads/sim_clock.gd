extends Node
var time := 0.0
var frozen := false
func _ready() -> void:
 process_physics_priority = -100
func _physics_process(delta: float) -> void:
 if not frozen:
  time += delta
func freeze(at_time: float) -> void:
 time = at_time
 frozen = true

func render_time() -> float:
 if frozen: return time
 return time + (Engine.get_physics_interpolation_fraction()-1.0)/float(Engine.physics_ticks_per_second)
