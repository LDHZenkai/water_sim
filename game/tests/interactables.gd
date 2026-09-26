extends SceneTree
var good:=true
func check(value: bool,label: String) -> void:
 good=good and value
 print("PASS: " if value else "FAIL: ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var world=load("res://scenes/main.tscn").instantiate()
 root.add_child(world)
 world.freeze_at(12)
 var player=world.get_node("Player")
 player.set_physics_process(false)
 player.set_process(false)
 var items=world.interactables
 items.set_process(false)
 world.cabin.set_process(false)
 world.cabin.visible=true
 await physics_frame
 await physics_frame
 # Doors remain available even when the new interactables are switched off.
 var door: Node3D=world.doors[0]
 player.head.global_position=door.interaction_point()+world.ship_body.global_basis.x*0.8
 player.camera.global_position=player.head.global_position
 player.camera.look_at(door.interaction_point())
 check(world.cabin.nearest_door()==door,"cabin door remains selectable with interactables override")
 for mesh in items.held.find_children("*","MeshInstance3D",true,false):
  for surface in range(mesh.mesh.get_surface_count()):
   var material: Material=mesh.get_active_material(surface)
   check(material is ShaderMaterial and material.get_shader_parameter("albedo_map") is Texture2D and "seadogs_compass_diff" in material.get_shader_parameter("albedo_map").resource_path,"held compass retains real textured material "+str(mesh.name))
 var enabled: bool=world.cabin.settings["interactables"]=="on"
 items.interact("chest")
 for i in range(120):items._process(1.0/60)
 check(items.opened==enabled and (items.lid.rotation.x< -1.7)==enabled,"chest hinge opens smoothly / respects override")
 # Sweep the actual baked vertices through the full animation, independently
 # of tour framing. The stern reveal extends 0.04 m inboard of BACK; require another 2 cm.
 var saved_lid_angle: float=items.lid.rotation.x
 var clear:=true
 var lining_normals:=0
 var lid_arrays: Array=items.lid.mesh.surface_get_arrays(0)
 for n in lid_arrays[Mesh.ARRAY_NORMAL]:
  if n.y< -0.5:lining_normals+=1
 for degrees in range(106):
  items.lid.rotation.x=deg_to_rad(-degrees)
  var pose: Transform3D=world.cabin.global_transform.affine_inverse()*items.lid.global_transform
  for v in lid_arrays[Mesh.ARRAY_VERTEX]:
   var p: Vector3=pose*v
   if p.y>=7.105 and p.y<=7.175 and p.x<=world.cabin.BACK+0.06:clear=false
 items.lid.rotation.x=saved_lid_angle
 check(clear,"chest lid clears stern window reveal throughout swing")
 check(lining_normals>100,"chest canopy includes inward-facing geometry")
 check(items.compass.find_child("*lid*",true,false)==null,"anachronistic compass sighting ring removed")
 items.interact("chest")
 for i in range(120):items._process(1.0/60)
 check(absf(items.lid.rotation.x)<0.001,"chest closes")
 items.interact("compass")
 items._process(1.0)
 check(items.held.visible==enabled and items.compass.visible!=enabled,"retained held compass visibility")
 if enabled:
  player.camera.rotate_y(1.2)
  for i in range(90):items._process(1.0/60)
  var up: Vector3=items.needle.global_basis.y.normalized()
  var north: Vector3=(Vector3.FORWARD-up*Vector3.FORWARD.dot(up)).normalized()
  check((-items.needle.global_basis.z.normalized()).dot(north)>0.999,"broad diamond (-Z in source atlas) needle end settles toward projected world north")
 items.raised=false
 items._process(1.0)
 check(not items.held.visible and items.compass.visible,"compass release restores table copy")
 var before: bool=items.deck_props.flame.visible
 items.interact("lantern")
 check(items.deck_props.flame.visible==(not before if enabled else before),"deck flame toggles without adding lights")
 check(world.deck_props.find_children("*","Light3D",true,false).is_empty(),"deck lantern emissive only")
 items.set_candle(false)
 for mesh in world.cabin.shell:
  for s in range(mesh.mesh.get_surface_count()):
   var mat: Material=mesh.get_active_material(s)
   if mat is ShaderMaterial and "candle_on" in mat.shader.code:
    check(not mat.get_shader_parameter("candle_on") and mat.get_shader_parameter("sun_scale")>0,"candle off retains daylight scale")
 # Look-at selection rejects distance and facing, using the real camera/raycast.
 player.camera.global_position=world.ship_body.to_global(Vector3(-10.9,7.7,0.3))
 player.camera.look_at(items.chest.global_position+Vector3.UP*0.45)
 check((items.target()=="chest")==enabled,"near visible chest selected")
 player.camera.rotate_y(PI)
 check(items.target()!="chest","looking away removes prompt")
 player.camera.global_position+=Vector3.UP*4
 player.camera.look_at(items.chest.global_position)
 check(items.target()=="","beyond two metres removes prompt")
 for prop in world.deck_props.props:
  var count:=0
  for mesh in prop.find_children("*","MeshInstance3D",true,false):
   count+=mesh.mesh.get_faces().size()/3
   check(mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"deck prop shadow cost disabled")
  check(count<=30000,"deck base mesh budget "+str(prop.name)+" triangles="+str(count))
 print("INTERACTABLES: ","PASS" if good else "FAIL")
 world.free()
 quit(0 if good else 1)
