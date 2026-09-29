shader_type spatial;
render_mode cull_disabled, fog_disabled;
// Square sails driven by the wind (sails.gd). Each vertex carries its place
// in its own sail: CUSTOM0 = (across 0..1, down 0..1, rest belly m, yard y),
// CUSTOM1 = (yard plane x, sail depth m, sail index, 0), all ship-local.
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D arm_texture : filter_linear_mipmap_anisotropic;
// Belly: 1 = the modelled full sail, 0 = slack, negative = taken aback.
uniform float fill = 1.0;
// Luffing: the leech shivers and waves run across the cloth.
uniform float luff = 0.0;
// Canvas set: 1 = full, 0 = furled up to the yard.
uniform float canvas = 1.0;
uniform float wind_time = 0.0;
uniform vec3 backlight_color = vec3(0.34, 0.31, 0.25);

void vertex() {
	float across = CUSTOM0.x;
	float down = CUSTOM0.y;
	float belly = CUSTOM0.z;
	float yard = CUSTOM0.w;
	float plane = CUSTOM1.x;
	float index = CUSTOM1.z;
	// Furling hauls the foot up to the yard; a thin bundle stays.
	float keep = max(canvas, 0.05);
	VERTEX.y = yard - (yard - VERTEX.y) * keep;
	// Cloth is held at the yard and the clews; the middle takes the wind.
	float free = sin(across * PI) * smoothstep(0.0, 0.35, down);
	float shiver = luff * (0.22 * sin(wind_time * 11.0 - down * 9.0 + across * 6.0 + index * 1.7) + 0.08 * sin(wind_time * 23.0 + across * 17.0 + index)) * free;
	float shape = belly * fill * mix(0.35, 1.0, keep);
	VERTEX.x = plane + shape + shiver * (0.4 + 0.6 * keep);
	// A backed sail bellies aft: turn its shading normal with it.
	NORMAL.x *= sign(fill + 0.001);
}

void fragment() {
	vec4 arm = texture(arm_texture, UV);
	ALBEDO = texture(albedo_texture, UV).rgb;
	NORMAL_MAP = texture(normal_texture, UV).rgb;
	ROUGHNESS = arm.g;
	METALLIC = 0.0;
	BACKLIGHT = backlight_color;
}
