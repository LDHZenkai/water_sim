extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var world=load("res://scenes/main.tscn").instantiate()
 root.add_child(world)
 world.freeze_at(0)
 world.get_node("Player").input_enabled=false
 await physics_frame
 var good:=true
 var settings: Dictionary=root.get_node("Quality").effective
 for node in world.decks.find_children("*","VisualInstance3D",true,false):
  if node.is_visible_in_tree() and settings["collision-debug"]!="on":good=false
 for ramp in world.decks.ramps:
  for child in ramp.find_children("*","VisualInstance3D",true,false):
   if child.is_visible_in_tree():good=false
 for rail in world.decks.rails:
  for child in rail.shape.find_children("*","VisualInstance3D",true,false):
   if child.is_visible_in_tree():good=false
 print("COLLISION ONLY: ","PASS" if good else "FAIL")
 good=good and (world.decks.find_children("*","VisualInstance3D",true,false).size()>0)==(settings["collision-debug"]=="on")
 var cabin=world.cabin
 cabin.update_visibility(Vector3(0,5,0))
 good=good and not cabin.visible
 cabin.update_visibility(Vector3(-10.5,7.9,0.1))
 good=good and cabin.visible
 for light in cabin.lamps:good=good and light.light_cull_mask==2 and not light.shadow_enabled
 good=good and cabin.plank.uv1_triplanar==(settings["cabin-triplanar"]=="on")
 for mesh in cabin.shell:good=good and mesh.visible==(settings["cabin-shell"]=="on")
 for light in cabin.lamps:good=good and light.visible==(settings["cabin-lights"]=="on")
 good=good and (cabin.find_children("*","OccluderInstance3D",true,false).size()>0)==(settings["cabin-occluder"]=="on")
 for prop in cabin.props:
  var expected: bool=settings["cabin-props"]!="off"
  if settings["cabin-props"]=="lite" and prop.name in ["wooden_candlestick","treasure_chest","CandleFlame"]:expected=false
  if prop.name=="CandleFlame" and settings["cabin-lights"]=="off":expected=false
  good=good and prop.visible==expected
 for point in cabin.beam_vertices:
  if point.y-cabin.FLOOR<1.85:printerr("LOW BEAM: ",point)
  good=good and point.y-cabin.FLOOR>=1.85
 var budgets: Array=JSON.parse_string(FileAccess.get_file_as_string("res://exploration/generated/prop_budgets.json"))
 for row in budgets:
  good=good and row.base_triangles<=row.budget
 for prop in cabin.props:
  var triangles:=0
  var meshes: Array=prop.find_children("*","MeshInstance3D",true,false)
  if prop is MeshInstance3D:meshes.append(prop)
  good=good and not meshes.is_empty()
  for mesh in meshes:
   triangles+=mesh.mesh.get_faces().size()/3
   if settings["cabin-shadows"]=="off":good=good and mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
   for s in range(mesh.mesh.get_surface_count()):
    var mat: Material=mesh.get_active_material(s)
    if mat is BaseMaterial3D:
     good=good and not mat.refraction_enabled
     if prop.name=="wine_bottles_01":
      if mat.transparency not in [BaseMaterial3D.TRANSPARENCY_DISABLED,BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR]:printerr("WINE TRANSPARENCY: ",mat.transparency)
      good=good and mat.transparency in [BaseMaterial3D.TRANSPARENCY_DISABLED,BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR]
  var size: Vector3=prop.get_meta("fitted_size",Vector3.ONE)
  var triangle_limit:=15000 if maxf(size.x,maxf(size.y,size.z))<0.5 else 30000
  good=good and triangles<=triangle_limit
 print("CABIN budget / hidden exterior / light mask / opaque-cutout props: ","PASS" if good else "FAIL")
 world.free()
 quit(0 if good else 1)
