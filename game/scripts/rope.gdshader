shader_type spatial;
// Opaque sheets: retain reverse faces on the source ratlines; no alpha pass.
// Preserve the source silhouette and UVs, including the broad top timbers.
render_mode cull_disabled, fog_disabled;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
void vertex() {
 // A bounded subpixel expansion reduces broken distant strands at MSAA 0.
 // No alpha, discard, distance cull or visibility switch; near ropes stay put.
 float depth = max(0.0,-(MODELVIEW_MATRIX * vec4(VERTEX,1.0)).z);
 float pixel = 2.0 * depth / max(1.0,abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
 VERTEX += NORMAL * clamp(pixel * 0.4 - 0.004,0.0,0.012);
}
void fragment() {
 ALBEDO = texture(albedo_texture, UV).rgb;
 ROUGHNESS = 0.9;
}
