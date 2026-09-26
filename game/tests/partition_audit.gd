extends SceneTree
func _initialize() -> void:
 var scene=load("res://assets/polyhaven/models/dutch_ship_large_01/dutch_ship_large_01_2k.gltf").instantiate()
 var hull=scene.find_child("*hull*",true,false)
 var source: Mesh=hull.get_meta("source_mesh")
 var fresh=preload("res://exploration/hull_split.gd").build(source)
 for key in ["hull","patch","knees"]:
  var old: Mesh=hull.get_meta("m2_partition")[key]
  print(key," cached=",old.get_faces().size()/3," current=",fresh[key].get_faces().size()/3," identical=",old.get_faces()==fresh[key].get_faces())
 scene.free()
 quit()
