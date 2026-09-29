extends RefCounted
## Makes the model's sails respond to the wind. The joined sails mesh is split
## into its sails (connected islands); every vertex learns where it sits in
## its own sail, and sails.gdshader fills, backs, shivers or furls the cloth
## from the apparent wind the ship's motion model reports each frame.
var mesh_instance: MeshInstance3D
var material := ShaderMaterial.new()
var sail_count := 0
var fill := 1.0
var luff := 0.0
var _clock := 0.0

func build(sails: MeshInstance3D, original: BaseMaterial3D) -> void:
	mesh_instance = sails
	var source := sails.mesh
	var arrays: Array = source.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var island := _islands(vertices, indices)
	var roots := {}
	for i in range(vertices.size()):
		var r: int = island[i]
		if not roots.has(r): roots[r] = {"min": vertices[i], "max": vertices[i], "index": roots.size()}
		roots[r].min = roots[r].min.min(vertices[i])
		roots[r].max = roots[r].max.max(vertices[i])
	sail_count = roots.size()
	# The yard line: mean x of the top 4% of each sail.
	for r in roots:
		var top: float = roots[r].max.y - (roots[r].max.y - roots[r].min.y) * 0.04
		var total := 0.0
		var count := 0
		for i in range(vertices.size()):
			if island[i] == r and vertices[i].y >= top:
				total += vertices[i].x
				count += 1
		roots[r].plane = total / maxf(count, 1)
	var custom0 := PackedFloat32Array()
	var custom1 := PackedFloat32Array()
	for i in range(vertices.size()):
		var sail: Dictionary = roots[island[i]]
		var low: Vector3 = sail.min
		var high: Vector3 = sail.max
		custom0.append_array([
			(vertices[i].z - low.z) / maxf(high.z - low.z, 0.01),
			(high.y - vertices[i].y) / maxf(high.y - low.y, 0.01),
			vertices[i].x - float(sail.plane),
			high.y])
		custom1.append_array([float(sail.plane), high.x - low.x, float(sail.index), 0.0])
	arrays[Mesh.ARRAY_CUSTOM0] = custom0
	arrays[Mesh.ARRAY_CUSTOM1] = custom1
	var format := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	var rigged := ArrayMesh.new()
	rigged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, format)
	# Sails swing well clear of their rest pose when backed or furled.
	rigged.custom_aabb = source.get_aabb().grow(3.0)
	sails.mesh = rigged
	material.shader = preload("res://exploration/sails.gdshader")
	material.set_shader_parameter("albedo_texture", original.albedo_texture)
	material.set_shader_parameter("normal_texture", original.normal_texture)
	material.set_shader_parameter("arm_texture", original.roughness_texture)
	sails.material_override = material

## Connected islands, welding vertices that share a position (UV seams).
static func _islands(vertices: PackedVector3Array, indices: PackedInt32Array) -> PackedInt32Array:
	var parent := PackedInt32Array()
	parent.resize(vertices.size())
	for i in range(vertices.size()): parent[i] = i
	var find := func(x: int) -> int:
		while parent[x] != x:
			parent[x] = parent[parent[x]]
			x = parent[x]
		return x
	for t in range(0, indices.size(), 3):
		var a: int = find.call(indices[t])
		parent[find.call(indices[t + 1])] = a
		parent[find.call(indices[t + 2])] = a
	var seen := {}
	for i in range(vertices.size()):
		var key := Vector3i(roundi(vertices[i].x * 1000.0), roundi(vertices[i].y * 1000.0), roundi(vertices[i].z * 1000.0))
		if seen.has(key): parent[find.call(i)] = find.call(seen[key])
		else: seen[key] = i
	var result := PackedInt32Array()
	result.resize(vertices.size())
	for i in range(vertices.size()): result[i] = find.call(i)
	return result

## Per-frame wind on the cloth from the ship's motion model.
func update(motion: RefCounted, delta: float) -> void:
	_clock += delta
	var direction: Vector2 = motion.forward()
	var apparent: Vector2 = motion.wind() - direction * float(motion.speed)
	var strength := apparent.length()
	var angle: float = motion.apparent_wind_angle(direction, float(motion.speed))
	# Pressure relative to a fresh 9 m/s breeze on the quarter.
	var pressure := strength * strength / 80.0
	var target: float
	var shiver := 0.0
	if strength < 1.5:
		target = 0.12
	elif angle < deg_to_rad(38.0):
		# Wind from ahead: taken aback, pressed against the mast.
		target = -minf(0.35 + pressure * 0.4, 0.9)
		shiver = 0.4
	elif angle < deg_to_rad(58.0):
		# Too close to the wind to fill: the cloth luffs and slats.
		target = 0.18
		shiver = 1.0
	else:
		target = clampf(0.25 + 0.75 * minf(pressure, 1.0) + 0.15 * maxf(pressure - 1.0, 0.0), 0.2, 1.3)
		# Hard driven cloth still shivers along the leech.
		shiver = clampf((strength - 14.0) / 20.0, 0.0, 0.35)
	fill = lerpf(fill, target, 1.0 - exp(-delta / 0.6))
	luff = lerpf(luff, shiver, 1.0 - exp(-delta / 0.4))
	material.set_shader_parameter("fill", fill)
	material.set_shader_parameter("luff", luff)
	material.set_shader_parameter("canvas", float(motion.canvas))
	material.set_shader_parameter("wind_time", _clock * clampf(strength / 10.0, 0.3, 2.5))
