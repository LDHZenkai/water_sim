extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var world=load("res://scenes/main.tscn").instantiate()
 root.add_child(world)
 world.freeze_at(12.0)
 world.get_node("Player").set_physics_process(false)
 var events:=root.get_node("PerfEvents")
 events.start()
 var meshes: Array=world.cabin.find_children("*","MeshInstance3D",true,false)
 meshes.append_array(world.interactables.find_children("*","MeshInstance3D",true,false))
 meshes.append_array(world.deck_props.find_children("*","MeshInstance3D",true,false))
 var state: Array=[]
 for mesh in meshes:state.append([mesh,mesh.mesh.get_rid(),mesh.layers,mesh.get_parent()])
 var nodes:=root.get_tree().get_node_count()
 await world.cabin_prewarm.warm()
 var good: bool=world.cabin_prewarm.complete and nodes==get_node_count()
 # Every runtime prop surface gets a retained swatch using its real material.
 for mesh in meshes:
  for surface in range(mesh.mesh.get_surface_count()):
   var found:=false
   for swatch in world.cabin_prewarm.find_children("*","MeshInstance3D",true,false):
    if swatch.material_override==mesh.get_active_material(surface):found=true;break
   good=good and found
 var camera: Camera3D=world.get_viewport().get_camera_3d()
 var saved_pose:=camera.global_transform
 var sun: DirectionalLight3D=world.get_node("Sun")
 var shadow_enabled:=sun.shadow_enabled
 var shadow_mode:=sun.directional_shadow_mode
 camera.global_position=world.ship_body.to_global(Vector3(-10.5,7.8,0.1))
 world._process(0.0)
 good=good and is_equal_approx(sun.directional_shadow_max_distance,18.0)
 camera.global_position=world.ship_body.to_global(Vector3(-8,7.8,0.1))
 world._process(0.0)
 good=good and is_equal_approx(sun.directional_shadow_max_distance,world.exterior_shadow_distance)
 good=good and sun.shadow_enabled==shadow_enabled and sun.directional_shadow_mode==shadow_mode
 camera.global_transform=saved_pose
 for step in range(80):
  world.interactables.interact("chest")
  world.interactables.interact("lantern")
  world.interactables.interact("cabin_lantern")
  world.interactables.raised=step%2==0
  world.interactables._process(0.1)
  for door in world.doors:
   door.set_open(step%2==0,true)
   door._physics_process(1.0/60.0)
  world.cabin.update_visibility(Vector3(-10,7.9,0.1) if step%2==0 else Vector3(0,5,0))
  world.cabin.update_prop_lod(Vector3(100,100,100) if step%2==0 else world.ship_body.to_global(Vector3(-10,7.8,0.1)))
  for entry in state:
   good=good and is_instance_valid(entry[0]) and entry[0].mesh.get_rid()==entry[1] and entry[0].layers==entry[2] and entry[0].get_parent()==entry[3]
 good=good and nodes==get_node_count()
 var player=world.get_node("Player")
 player.test_input=true
 # Exercise actual event producers; perf's camera-only route disables physics.
 for feet in [Vector3(-8.8,6.4,0.885),Vector3(-7,6.4,0),world.decks.climbs[0].get_center(),Vector3(-7,6.4,0)]:
  player.ship_position=feet
  player.global_position=world.ship_body.to_global(feet)
  player.ship_velocity=Vector3.ZERO
  player._physics_process(1.0/60.0)
 var names: Array=[]
 for event in events.events:names.append(event.event)
 for expected in ["door_open","door_close","interior_visibility","auto_duck_start","auto_duck_end","climb_volume_enter","climb_volume_exit","cabin_prewarm_start","cabin_prewarm_end"]:
  if expected not in names:printerr("Missing event ",expected)
  good=good and expected in names
 print("CABIN LIFECYCLE: ","PASS" if good else "FAIL"," (80 reveals; stable mesh RIDs/layers/parents/node count; retained prewarm; event hooks)")
 world.free()
 quit(0 if good else 1)
