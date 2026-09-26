shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic;
uniform bool mark_north = false;
varying float local_z;
void vertex() { local_z = VERTEX.z; }
void fragment() {
 // Stable broad key and fill retain the atlas detail on the moving prop.
 float key = 0.65 + 0.45 * max(dot(normalize(NORMAL),normalize(vec3(-0.3,0.6,1.0))),0.0);
 ALBEDO = texture(albedo_map,UV).rgb * key;
 if (mark_north && local_z < -0.003) ALBEDO = vec3(0.55,0.025,0.012) * key;
}
