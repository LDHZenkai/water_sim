shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, fog_disabled;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform float strand_radius = 0.012;
varying float coverage;
void vertex() {
 float depth = max(0.01, -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z);
 float pixel = 2.0 * depth / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
 float radius = max(strand_radius, pixel * 0.5);
 VERTEX += NORMAL * (radius - strand_radius);
 coverage = strand_radius / radius;
}
void fragment() {
 ALBEDO = texture(albedo_texture, UV).rgb;
 ROUGHNESS = 0.9;
 ALPHA = coverage;
}
