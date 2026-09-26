extends RefCounted
# Compare actual ordered triangles, not just counts. Detect replacement assets,
# duplicates, missing faces and stale generated resources independently of IDs.
static func matches(source: Mesh, parts: Array) -> bool:
 if source.get_surface_count() != 1: return false
 var remaining := {}
 var faces := source.get_faces()
 for i in range(0, faces.size(), 3):
  var key := [faces[i], faces[i+1], faces[i+2]]
  remaining[key] = int(remaining.get(key, 0)) + 1
 for part in parts:
  var actual: PackedVector3Array = part.get_faces()
  for i in range(0, actual.size(), 3):
   var key := [actual[i], actual[i+1], actual[i+2]]
   if not remaining.has(key): return false
   remaining[key] -= 1
   if remaining[key] == 0: remaining.erase(key)
 return remaining.is_empty()
