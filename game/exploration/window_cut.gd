@tool
extends RefCounted
# Subtract a convex box from triangles. Intersections retain interpolated UVs
# and normals; large stern faces are clipped, never simply deleted by centroid.
static func subtract(mesh: Mesh, box: AABB) -> Mesh:
 var a:=mesh.surface_get_arrays(0)
 var vertices: PackedVector3Array=a[Mesh.ARRAY_VERTEX]
 var normals: PackedVector3Array=a[Mesh.ARRAY_NORMAL]
 var uv: PackedVector2Array=a[Mesh.ARRAY_TEX_UV]
 var indices: PackedInt32Array=a[Mesh.ARRAY_INDEX]
 if indices.is_empty():
  for i in range(vertices.size()):indices.append(i)
 var st:=SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for i in range(0,indices.size(),3):
  var polygon: Array=[]
  for j in range(3):
   var k:=indices[i+j]
   polygon.append({"p":vertices[k],"n":normals[k],"uv":uv[k]})
  var bounds:=AABB(polygon[0].p,Vector3.ZERO).expand(polygon[1].p).expand(polygon[2].p)
  if not box.intersects(bounds):
   emit_polygon(st,polygon)
   continue
  for axis in range(3):
   for side in range(2):
    if polygon.is_empty():break
    var limit: float=box.position[axis] if side==0 else box.end[axis]
    var split:=split_plane(polygon,axis,limit,side==0)
    emit_polygon(st,split[1]) # Outside this plane is permanently retained.
    polygon=split[0] # Inside must be tested against the remaining planes.
  # What remains inside all six planes is the aperture.
 st.generate_tangents()
 st.index()
 return st.commit()
static func split_plane(poly: Array, axis: int, limit: float, greater: bool) -> Array:
 var inside: Array=[]
 var outside: Array=[]
 for i in range(poly.size()):
  var a: Dictionary=poly[i]
  var b: Dictionary=poly[(i+1)%poly.size()]
  var da: float=(a.p[axis]-limit)*(1.0 if greater else -1.0)
  var db: float=(b.p[axis]-limit)*(1.0 if greater else -1.0)
  if da>=0:inside.append(a)
  else:outside.append(a)
  if (da>=0)!=(db>=0):
   var t:=da/(da-db)
   var v: Dictionary={"p":a.p.lerp(b.p,t),"n":a.n.lerp(b.n,t).normalized(),"uv":a.uv.lerp(b.uv,t)}
   inside.append(v)
   outside.append(v)
 return [inside,outside]
static func emit_polygon(st: SurfaceTool, poly: Array) -> void:
 for i in range(1,poly.size()-1):
  for j in [0,i,i+1]:
   st.set_normal(poly[j].n)
   st.set_uv(poly[j].uv)
   st.add_vertex(poly[j].p)
