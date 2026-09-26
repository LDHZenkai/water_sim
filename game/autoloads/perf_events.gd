extends Node
## Shared transition log; timings use the same monotonic clock as perf samples.
var recording := false
var events: Array = []
func mark(event: String, data: Dictionary = {}) -> void:
 if not recording:return
 events.append({"type":"EVENT", "event":event, "ticks_usec":Time.get_ticks_usec(), "process_frame":Engine.get_process_frames(), "physics_frame":Engine.get_physics_frames(), "data":data})
func start() -> void:
 events.clear()
 recording=true
