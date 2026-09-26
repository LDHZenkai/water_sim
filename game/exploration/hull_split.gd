@tool
extends RefCounted
# Source face IDs are used only for the audited thin repair. Doors are selected
# by all three vertices in the measured panel bounds, so frames stay in the hull.
static func build(source: Mesh) -> Dictionary:
 assert(source.get_surface_count()==1,"Hull partition requires one source surface")
 var arrays:=source.surface_get_arrays(0)
 var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
 var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
 var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
 var groups: Array=[PackedInt32Array(),PackedInt32Array(),PackedInt32Array(),PackedInt32Array()]
 var audit: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://ocean/generated/hull_audit.json"))
 var repair:=PackedInt32Array(audit.triangle_indices)
 var parents:=PackedInt32Array()
 var unique: Dictionary={}
 for i in range(vertices.size()):
  var key:=vertices[i].snapped(Vector3.ONE*0.0001)
  parents.append(int(unique.get(key,i)))
  unique[key]=parents[i]
 for face in range(indices.size()/3):
  var a:=root_of(parents,indices[face*3])
  for j in range(1,3):parents[root_of(parents,indices[face*3+j])]=a
 var bounds: Dictionary={}
 for i in range(vertices.size()):
  var root:=root_of(parents,i)
  if not bounds.has(root):bounds[root]=AABB(vertices[i],Vector3.ZERO)
  bounds[root]=bounds[root].expand(vertices[i])
 var door_roots: Dictionary={}
 for root in bounds:
  var box: AABB=bounds[root]
  if box.position.x > -8.84 and box.end.x < -8.76 and box.position.y > 6.60 and box.end.y < 7.60:
   if box.position.z > 0.56 and box.end.z < 1.21:door_roots[root]=2
   if box.position.z > -1.02 and box.end.z < -0.36:door_roots[root]=3
 for face in range(indices.size()/3):
  var group: int=door_roots.get(root_of(parents,indices[face*3]),0)
  if group==0 and face in repair:group=1
  for j in range(3):groups[group].append(indices[face*3+j])
 print("DOOR COUNTS ",groups[2].size()/3," ",groups[3].size()/3)
 assert(groups[2].size()==96 and groups[3].size()==96,"Source door selection changed: rerun geometry audit")
 var original_parts: Array=[]
 for group in groups:
  arrays[Mesh.ARRAY_INDEX]=group
  var part:=ArrayMesh.new()
  part.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
  original_parts.append(part)
 assert(preload("res://tests/hull_partition.gd").matches(source,original_parts),"Hull/repair/doors must partition source exactly")
 # The original 0.99 m panels cannot admit a human. Raise the arched opening
 # while holding the bulkhead's top edge, and lower the threshold to deck level.
 for i in range(vertices.size()):
  var p:=vertices[i]
  if p.x>=-9.23 and p.x<=-8.75 and absf(p.z-0.097)<1.18 and p.y>=6.52 and p.y<=8.21:
   var stretch:=1.79/1.13 if p.y<=7.65 else 0.13/0.56
   if p.y<=7.65:p.y=6.29+(p.y-6.52)*stretch
   else:p.y=8.08+(p.y-7.65)*stretch
   normals[i]=Vector3(normals[i].x,normals[i].y/stretch,normals[i].z).normalized()
   vertices[i]=p
 # Move each original knee as a whole, including its disconnected front/back
 # surfaces. Seat its outer edge in the side planking and its top at the beam.
 var knees: Dictionary={}
 var knee_roots: Dictionary={}
 for root in bounds:
  var box: AABB=bounds[root]
  if box.position.x > -12.0 and box.end.x < -9.9 and box.position.y > 7.0 and box.end.y < 8.5 and box.size.x < 0.26 and box.size.z < 0.4:
   var key:=str(box.get_center().x < -10.5)+str(box.get_center().z < 0)
   knee_roots[root]=key
   knees[key]=box if not knees.has(key) else knees[key].merge(box)
 var roof: Array=JSON.parse_string(FileAccess.get_file_as_string("res://exploration/generated/deckhead.json"))
 for i in range(vertices.size()):
  var root:=root_of(parents,i)
  if not knee_roots.has(root):continue
  var box: AABB=knees[knee_roots[root]]
  var target_x: float=-11.35 if box.get_center().x < -10.5 else -11.85
  var row: int=5 if target_x==-11.35 else 6
  var top: float=roof[row][0 if box.get_center().z<0 else 8][1]
  vertices[i].x+=target_x-box.get_center().x
  vertices[i].y+=top-box.end.y
  var t: float=inverse_lerp(-9.25,-12.12,target_x)
  if box.get_center().z < 0:vertices[i].z+=lerpf(-1.03,-0.73,t)-box.position.z
  else:vertices[i].z+=lerpf(1.22,0.92,t)-box.end.z
 # Extract relocated knees from the hull so they receive cabin wood and bake.
 var knee_indices:=PackedInt32Array()
 var hull_indices:=PackedInt32Array()
 for i in range(0,groups[0].size(),3):
  var is_knee:=knee_roots.has(root_of(parents,groups[0][i]))
  for j in range(3):
   if is_knee:knee_indices.append(groups[0][i+j])
   else:hull_indices.append(groups[0][i+j])
 groups[0]=hull_indices
 # The thin-hull repair used to retain duplicate knee faces outside the bake.
 # Remove them from that draw too; cabin.build supplies attached solid knees.
 for group_index in [0,1]:
  var retained:=PackedInt32Array()
  for face_index in range(0,groups[group_index].size(),3):
   var original_knee:=true
   for j in range(3):original_knee=original_knee and inside_original_knee(vertices[groups[group_index][face_index+j]])
   # Some starboard knee edge faces are welded into the main hull component;
   # component bounds alone cannot select them. Audit all three face vertices.
   if original_knee or knee_roots.has(root_of(parents,groups[group_index][face_index])):continue
   for j in range(3):retained.append(groups[group_index][face_index+j])
  groups[group_index]=retained
 var knee_uv:=PackedVector2Array()
 for p in vertices:knee_uv.append(Vector2(p.z,p.y)*0.7)
 var knee_arrays:=arrays.duplicate()
 knee_arrays[Mesh.ARRAY_VERTEX]=vertices
 knee_arrays[Mesh.ARRAY_NORMAL]=normals
 knee_arrays[Mesh.ARRAY_TEX_UV]=knee_uv
 knee_arrays[Mesh.ARRAY_INDEX]=knee_indices
 var knee_mesh:=ArrayMesh.new()
 knee_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,knee_arrays)
 var knee_tool:=SurfaceTool.new()
 knee_tool.create_from(knee_mesh,0)
 knee_tool.generate_tangents()
 knee_mesh=knee_tool.commit()
 arrays[Mesh.ARRAY_VERTEX]=vertices
 arrays[Mesh.ARRAY_NORMAL]=normals
 var parts: Array=[]
 for group in groups:
  arrays[Mesh.ARRAY_INDEX]=group
  var part:=ArrayMesh.new()
  part.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
  parts.append(part)
 # Recalculate normals/tangents after changing arch proportions.
 for part in parts:
  var st:=SurfaceTool.new()
  st.create_from(part,0)
  st.deindex()
  st.index()
  st.generate_tangents()
  part.clear_surfaces()
  st.commit(part)
 for z in [-0.70,0.13]:
  parts[0]=preload("res://exploration/window_cut.gd").subtract(parts[0],AABB(Vector3(-13.5,7.15,z),Vector3(1.35,0.84,0.76)))
 # Measured source gunport lids: x=3.550..4.213 and 6.085..6.759,
 # y=2.78..3.40. Open those ports for the deck guns; retain deck and frames.
 for x in [3.88,6.42]:
  for z in [-3.65,2.70]:
   var aperture:=AABB(Vector3(x-0.29,2.88,z),Vector3(0.58,0.55,0.95))
   for i in [0,1]:parts[i]=preload("res://exploration/window_cut.gd").subtract(parts[i],aperture)
 return {"knees":knee_mesh,"hull":parts[0],"patch":parts[1],"doors":[parts[2],parts[3]],"source_parts":original_parts,"counts":[groups[0].size()/3,groups[1].size()/3,32,32]}

static func root_of(parents: PackedInt32Array, i: int) -> int:
 while parents[i]!=i:
  i=parents[i]
 return i

static func inside_original_knee(p: Vector3) -> bool:
 for bounds in [AABB(Vector3(-10.192,7.055,-1.17),Vector3(0.215,0.49,0.32)),AABB(Vector3(-11.057,7.420,-1.032),Vector3(0.215,0.52,0.318)),AABB(Vector3(-11.932,7.816,-0.917),Vector3(0.257,0.565,0.317))]:
  if bounds.has_point(p) or bounds.has_point(Vector3(p.x,p.y,0.194725-p.z)):return true
 return false
