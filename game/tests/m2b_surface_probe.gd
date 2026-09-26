extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var good:=true
 var world=load("res://scenes/main.tscn").instantiate()
 root.add_child(world)
 world.get_node("Player").input_enabled=false
 world.set_physics_process(false)
 var vp:=SubViewport.new()
 vp.world_3d=World3D.new()
 root.add_child(vp)
 for mesh in world.ship_body.find_children("*","MeshInstance3D",true,false):
  if not world.cabin.is_ancestor_of(mesh) and not world.ship_body.get_node("Model").is_ancestor_of(mesh):continue
  var body:=StaticBody3D.new()
  var shape:=CollisionShape3D.new()
  shape.shape=mesh.mesh.create_trimesh_shape()
  shape.shape.backface_collision=true
  body.add_child(shape)
  vp.add_child(body)
  body.transform=world.ship_body.global_transform.affine_inverse()*mesh.global_transform
  body.set_meta("source",str(mesh.get_path()))
  body.set_meta("baked",mesh.get_meta("cabin_baked",false))
  var mat: Material=mesh.get_active_material(0)
  body.set_meta("wood",mat is ShaderMaterial and mat.get_shader_parameter("albedo_map") is Texture2D and "planks_diff" in mat.get_shader_parameter("albedo_map").resource_path)
 await physics_frame
 await physics_frame
 var eye:=Vector3(-9.9,8.03,0.65)
 var basis:=Basis.looking_at(Vector3(-12.1,7.6,0.1)-eye)
 for pixel in [Vector2(530,600),Vector2(180,80),Vector2(1640,210),Vector2(640,410),Vector2(1260,400),Vector2(1360,300)]:
  var xy: Vector2=(pixel/Vector2(1920,1080)*2-Vector2.ONE)*Vector2(1920.0/1080,-1)*tan(deg_to_rad(35))
  var ray:=PhysicsRayQueryParameters3D.create(eye,eye+basis*Vector3(xy.x,xy.y,-1)*10)
  ray.hit_back_faces=true
  var hit:=vp.find_world_3d().direct_space_state.intersect_ray(ray)
  if hit.is_empty():
   good=false
   print("FAIL: probe missed ",pixel)
   continue
  good=good and not hit.is_empty() and hit.collider.get_meta("baked") and hit.collider.get_meta("wood")
  print("PIXEL ",pixel," HIT ",hit.position," ",hit.collider.get_meta("source")," normal ",hit.normal)
 world.free()
 vp.free()
 print("CABIN VISIBLE WOOD: ","PASS" if good else "FAIL")
 quit(0 if good else 1)
