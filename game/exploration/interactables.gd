extends Node3D
var cabin: Node3D
var deck_props: Node3D
var player: CharacterBody3D
var cabin_flame: MeshInstance3D
var cabin_lantern: Node3D
var candle_on:=true
var chest: Node3D
var lid: Node3D
var compass: Node3D
var held: Node3D
var needle: Node3D
var opened:=false
var raised:=false
var raise_amount:=0.0
var lantern_on:=true
var enabled:=true
var selected:=""
var prompt: Label
var lamps: Array=[]
func build(room: Node3D,dressing: Node3D,actor: CharacterBody3D) -> void:
 cabin=room
 deck_props=dressing
 player=actor
 enabled=cabin.settings["interactables"]=="on"
 for prop in cabin.props:
  if prop.name=="wooden_lantern_01":cabin_lantern=prop
  if prop.name=="treasure_chest":chest=prop
  if prop.name=="seadogs_compass":compass=prop
 candle_on=cabin.settings["cabin-lights"]=="on"
 lid=chest.find_child("*lid*",true,false)
 assert(lid!=null,"Chest import must preserve hinge and lid")
 held=compass.duplicate()
 held.name="HeldCompass"
 for mesh in held.find_children("*","MeshInstance3D",true,false):
  mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  for s in range(mesh.mesh.get_surface_count()):
   var source: BaseMaterial3D=mesh.get_active_material(s)
   var material:=ShaderMaterial.new()
   material.shader=preload("res://exploration/held_compass.gdshader")
   material.set_shader_parameter("albedo_map",source.albedo_texture)
   material.set_shader_parameter("mark_north","needle" in str(mesh.name))
   mesh.set_surface_override_material(s,material)
 add_child(held)
 held.visible=false
 # Use the asset's separate needle, preserving its stable parent and mesh.
 needle=held.find_child("*needle*",true,false)
 assert(needle!=null,"Compass import must preserve its needle")
 cabin_flame=deck_props.flame.duplicate()
 cabin_flame.position=Vector3.UP*0.19
 cabin_flame.layers=2
 cabin_flame.visible=candle_on
 cabin_lantern.add_child(cabin_flame)
 var ui:=CanvasLayer.new()
 add_child(ui)
 prompt=Label.new()
 prompt.position=Vector2(30,110)
 prompt.add_theme_font_size_override("font_size",16)
 ui.add_child(prompt)
func target() -> String:
 if not enabled or not player.input_enabled:return ""
 var camera: Camera3D=player.camera
 var best:=0.94
 var found:=""
 for entry in [["cabin_lantern",cabin_lantern,cabin_lantern.global_position+Vector3.UP*0.2],["chest",chest,chest.global_position+Vector3.UP*0.45],["compass",compass,compass.global_position+Vector3.UP*0.04],["lantern",deck_props.lantern,deck_props.lantern.global_position+Vector3.UP*0.22]]:
  if not entry[1].is_visible_in_tree():continue
  var delta: Vector3=entry[2]-camera.global_position
  if delta.length()>2:continue
  var dot:=(-camera.global_basis.z).dot(delta.normalized())
  if dot<best:continue
  var query:=PhysicsRayQueryParameters3D.create(camera.global_position,entry[2],1)
  var hit:=get_world_3d().direct_space_state.intersect_ray(query)
  if not hit.is_empty() and hit.position.distance_to(entry[2])>0.25:continue
  best=dot
  found=entry[0]
 return found
func interact(id: String) -> void:
 if not enabled:return
 if id=="chest":opened=not opened
 if id=="lantern":
  lantern_on=not lantern_on
  deck_props.flame.visible=lantern_on
 if id=="cabin_lantern":
  candle_on=not candle_on
  set_candle(candle_on)
 if id=="compass":raised=true
func set_candle(on: bool) -> void:
 for light in cabin.lamps:
  if light is OmniLight3D:light.visible=on
 for mesh in cabin.find_children("*","MeshInstance3D",true,false):
  for s in range(mesh.mesh.get_surface_count()):
   var mat: Material=mesh.get_active_material(s)
   if mat is ShaderMaterial and "candle_on" in mat.shader.code:mat.set_shader_parameter("candle_on",on)
 for prop in cabin.props:
  if prop.name=="CandleFlame":prop.visible=on and cabin.settings["cabin-props"]=="on"
func _unhandled_input(event: InputEvent) -> void:
 if event.is_action_pressed("interact"):interact(target())
 if event.is_action_released("interact"):raised=false
func _process(delta: float) -> void:
 if lid==null or not enabled:return
 lid.rotation.x=move_toward(lid.rotation.x,deg_to_rad(-105) if opened else 0.0,delta*1.8)
 cabin_flame.visible=candle_on and cabin_lantern.is_visible_in_tree()
 selected=target()
 prompt.text={"":"","cabin_lantern":"E · extinguish cabin lamp" if candle_on else "E · light cabin lamp","chest":"E · close chest" if opened else "E · open chest","compass":"Hold E · read compass","lantern":"E · extinguish lantern" if lantern_on else "E · light lantern"}.get(selected,"")
 raise_amount=move_toward(raise_amount,1.0 if raised and enabled else 0.0,delta*5.0)
 held.visible=raise_amount>0 and enabled and cabin.settings["cabin-props"]!="off"
 compass.visible=raise_amount<=0 and cabin.settings["cabin-props"]!="off"
 if held.visible:
  var camera:=get_viewport().get_camera_3d()
  held.global_transform=camera.global_transform*Transform3D(Basis.from_euler(Vector3(0.85,0,0)),Vector3(0.04,lerpf(-0.65,-0.12,smoothstep(0,1,raise_amount)),-0.28))
  var north: Vector3=needle.get_parent().global_basis.inverse()*Vector3(0,0,-1)
  needle.rotation.y=lerp_angle(needle.rotation.y,atan2(-north.x,-north.z),1-exp(-delta*8))
