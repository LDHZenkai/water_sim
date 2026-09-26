extends SceneTree
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 var world=load("res://scenes/main.tscn").instantiate()
 root.add_child(world)
 var quality=root.get_node("Quality")
 var settings: Dictionary=quality.effective
 var good:=true
 var expected_aniso:int={1:Viewport.ANISOTROPY_DISABLED,2:Viewport.ANISOTROPY_2X,4:Viewport.ANISOTROPY_4X,16:Viewport.ANISOTROPY_16X}[int(settings.aniso)]
 good=good and root.anisotropic_filtering_level==expected_aniso
 good=good and world.get_node("Sun").shadow_enabled==(settings.shadows=="on")
 good=good and world.get_node("Atmosphere").environment.fog_enabled==(settings.fog=="on")
 good=good and world.get_node("Atmosphere").environment.fog_aerial_perspective==0.0
 good=good and world.ocean.material.get_shader_parameter("fog_enabled")== (settings.fog=="on")
 for mesh in world.ship_body.get_node("Model").find_children("*","MeshInstance3D"):
  if "rigging" in mesh.name:
   good=good and mesh.visible==(settings.rigging=="on")
   var code: String=mesh.material_override.shader.code
   var legacy: bool=settings["rigging-material"]=="legacy"
   good=good and ("ALPHA = coverage" in code)==legacy
   good=good and "cull_disabled" in code
   good=good and mesh.visibility_range_end==0.0
   good=good and mesh.material_override.get_shader_parameter("albedo_texture")!=null
   good=good and mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  if "hull" in mesh.name:
   good=good and ("cull_back" if settings["hull-cull"]=="back" else "cull_disabled") in mesh.material_override.shader.code
   good=good and "fog_disabled" in mesh.material_override.shader.code
   good=good and preload("res://tests/hull_partition.gd").matches(world.hull_source_mesh, world.hull_partition.source_parts)
   good=good and preload("res://tests/hull_partition.gd").matches(world.hull_source_mesh, [preload("res://ocean/generated/hull_back.res"), preload("res://ocean/generated/hull_two_sided.res")])
   if settings["hull-cull"]=="back":
    good=good and mesh.mesh.get_faces().size()>0
    good=good and mesh.get_node("ThinHullPatch").mesh.get_faces().size()/3==6
 var ocean=world.ocean
 good=good and ocean.wave_count==int(settings["ocean-waves"])
 good=good and ocean.grid==int(settings["ocean-grid"])
 good=good and ocean.visible==(settings["ocean"]!="off")
 good=good and (ocean.bilge!=null)==(settings["ocean-clip"]=="occluder")
 good=good and ("if (inside_hull(local)) discard;" in ocean.material.shader.code)==(settings["ocean-clip"]=="discard")
 good=good and ("ALPHA = 1.0;" in ocean.material.shader.code)==(settings["ocean-order"]=="after")
 good=good and ("unshaded" in ocean.material.shader.code)==(settings["ocean-shader"]=="low" or settings["ocean-debug"]=="rings")
 print("PASS: render switches applied to scene, shader and viewport" if good else "FAIL: render switches applied to scene, shader and viewport")
 world.free()
 quit(0 if good else 1)
