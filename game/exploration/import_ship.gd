@tool
extends EditorScenePostImport
func _post_import(scene: Node) -> Object:
 for hull in scene.find_children("*","MeshInstance3D"):
  if "hull" not in hull.name:continue
  var source: Mesh=hull.mesh
  var parts:=preload("res://exploration/hull_split.gd").build(source)
  # Keep the complete source for water masking and independent partition audit.
  hull.set_meta("source_mesh",source)
  hull.set_meta("m2_partition",parts)
  var material: Material=hull.get_active_material(0)
  hull.mesh=parts.hull
  hull.mesh.surface_set_material(0,material)
 return scene
