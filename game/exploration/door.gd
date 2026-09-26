extends Node3D
var opened := false
var angle := 0.0
var open_angle := 105.0
var body: AnimatableBody3D
func build(mesh: Mesh, material: Material, hinge: Vector3, side: float) -> void:
 position=hinge
 open_angle=105.0*side
 body=AnimatableBody3D.new()
 body.name="Leaf"
 body.collision_layer=1
 body.collision_mask=2
 body.sync_to_physics=false # Parent ship supplies the physics pose.
 add_child(body)
 var visual:=MeshInstance3D.new()
 visual.mesh=mesh
 visual.material_override=material
 visual.position=-hinge
 body.add_child(visual)
 var collision:=CollisionShape3D.new()
 collision.shape=mesh.create_trimesh_shape()
 collision.position=-hinge
 body.add_child(collision)
func interact() -> void:
 set_open(not opened)
func set_open(value: bool, instant: bool=false) -> void:
 if opened!=value:get_node("/root/PerfEvents").mark("door_open" if value else "door_close", {"door":str(name)})
 opened=value
 if instant:
  angle=deg_to_rad(open_angle) if opened else 0.0
  body.rotation.y=angle
func _physics_process(delta: float) -> void:
 var target:=deg_to_rad(open_angle) if opened else 0.0
 angle=move_toward(angle,target,delta*1.5)
 body.rotation.y=angle
func interaction_point() -> Vector3:
 return global_position+global_basis*Vector3(0,0.8,-0.3 if open_angle>0 else 0.3)
