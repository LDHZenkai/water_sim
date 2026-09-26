extends SceneTree
var failures := 0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, label: String) -> void:
 print("PASS: " if ok else "FAIL: ",label)
 if not ok:failures+=1
func run() -> void:
 var world=load("res://scenes/main.tscn").instantiate()
 root.add_child(world)
 world.freeze_at(0)
 var player=world.get_node("Player")
 player.input_enabled=false
 player.set_physics_process(false)
 var cabin=world.cabin
 var camera:=Camera3D.new()
 root.add_child(camera)
 camera.make_current()
 # Keep the player on deck; exercise _process through the viewport camera.
 for eye in [Vector3(-9.9,8.03,0.65),Vector3(-9.85,7.8,0.55)]:
  camera.global_position=world.ship_body.to_global(eye)
  await process_frame
  await process_frame
  var visible_shell: bool=not cabin.shell.is_empty()
  var masks:=true
  for mesh in cabin.shell:
   visible_shell=visible_shell and mesh.is_visible_in_tree()
   masks=masks and (mesh.layers & camera.cull_mask)!=0
  check(root.get_camera_3d()==camera and visible_shell,"non-player camera inside: shell visible at "+str(eye))
  check(masks,"active camera renders shell layers")
 # Test the actual merged render triangles, not the pre-merge collision mesh.
 # Godot fronts are clockwise: reverse cross product gives the front normal.
 var center:=Vector3(-10.685,7.45,0.095)
 var directions:={"front wall":Vector3.RIGHT,"stern wall":Vector3.LEFT,"port wall":Vector3.FORWARD,"starboard wall":Vector3.BACK,"ceiling":Vector3.UP,"floor":Vector3.DOWN}
 for label in directions:
  var direction: Vector3=directions[label]
  var distance:=INF
  for mesh in cabin.shell:
   var faces: PackedVector3Array=mesh.mesh.get_faces()
   for i in range(0,faces.size(),3):
    var a: Vector3=mesh.transform*faces[i]
    var b: Vector3=mesh.transform*faces[i+1]
    var c: Vector3=mesh.transform*faces[i+2]
    var normal: Vector3=(c-a).cross(b-a).normalized()
    if normal.dot(direction)>=-0.0001:continue
    var hit=Geometry3D.ray_intersects_triangle(center,direction,a,b,c)
    if hit!=null:distance=minf(distance,center.distance_to(hit))
  check(distance<3.0,"centre ray hits merged shell front face: "+label+" distance="+str(distance))
 # Reverse player/camera positions to catch accidental player-based culling.
 player.global_position=world.ship_body.to_global(center)
 camera.global_position=world.ship_body.to_global(Vector3(-8,7.95,0.885))
 for door in cabin.doors:
  check(not door.opened and absf(door.angle)<0.001,"door closed")
 await process_frame
 await process_frame
 var hidden: bool=not cabin.visible
 for mesh in cabin.shell:hidden=hidden and not mesh.is_visible_in_tree()
 check(hidden,"outside camera / inside player / closed doors: interior hidden")
 print("CABIN VISIBILITY: ","PASS" if failures==0 else "FAIL"," (",failures," failures)")
 camera.free()
 world.free()
 quit(0 if failures==0 else 1)
