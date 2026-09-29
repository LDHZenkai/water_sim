shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;
// One raindrop's blur over ~1/60 s: a thin quad along the particle's own
// velocity (align_y puts it on the particle's Y axis), turned about that axis
// to face the eye. Godot's Y-billboard would use the world's up instead, so
// wind-driven rain would still fall straight down. Far streaks are widened
// to a pixel and faded by the same factor, so they thin out, not shimmer.
uniform vec4 color : source_color = vec4(0.82, 0.85, 0.9, 0.45);
// Angular width of one pixel at the reference resolution, radians.
uniform float pixel_angle = 0.0012;
varying float fade;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 axis = MODEL_MATRIX[1].xyz;
	float length_scale = length(axis);
	axis /= max(length_scale, 0.0001);
	vec3 to_eye = CAMERA_POSITION_WORLD - origin;
	float distance = max(length(to_eye), 0.05);
	vec3 side = normalize(cross(axis, to_eye / distance));
	float width = abs(VERTEX.x) * 2.0;
	float drawn = max(width, distance * pixel_angle);
	// A drop grazing the lens is a blur, not a bright bar.
	fade = width / drawn * smoothstep(0.6, 2.5, distance);
	vec3 world = origin + axis * VERTEX.y * length_scale + side * sign(VERTEX.x) * drawn * 0.5;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = (VIEW_MATRIX * vec4(cross(side, axis), 0.0)).xyz;
}

void fragment() {
	ALBEDO = color.rgb;
	// Soft across the streak, tapered at both ends.
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	ALPHA = color.a * fade * across * sin(UV.y * PI);
}
