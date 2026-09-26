extends RefCounted
# All rings, including the horizon skirt, must be one manifold disk. Shared
# indices imply bit-identical displacement and LOD on both sides of a seam.
static func run(check: Callable) -> void:
 for size in [32,128,192,256]:
  var ocean=preload("res://ocean/ocean.gd").new()
  ocean.grid=size
  ocean._build_grid()
  var arrays: Array=ocean.mesh.surface_get_arrays(0)
  var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
  var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
  var edges := {}
  var positions := {}
  var good := true
  for p in vertices:
   if positions.has(p): good=false
   positions[p]=true
  for i in range(0,indices.size(),3):
   var a:=indices[i]
   var b:=indices[i+1]
   var c:=indices[i+2]
   good=good and (vertices[c]-vertices[a]).cross(vertices[b]-vertices[a]).y>0.0
   for pair in [Vector2i(a,b),Vector2i(b,c),Vector2i(c,a)]:
    var key:=Vector2i(mini(pair.x,pair.y),maxi(pair.x,pair.y))
    edges[key]=int(edges.get(key,0))+1
  var boundary:=0
  for pair in edges:
   var count: int=edges[pair]
   if count==1:
    boundary+=1
    var a: Vector3=vertices[pair.x]
    var b: Vector3=vertices[pair.y]
    good=good and ((absf(a.x)==24000 and a.x==b.x) or (absf(a.z)==24000 and a.z==b.z))
   else: good=good and count==2
  good=good and boundary==size*4
  check.call(good,"watertight indexed rings: grid %d, %d triangles, only %d outer boundary edges" % [size,indices.size()/3,boundary])
  ocean.free()
