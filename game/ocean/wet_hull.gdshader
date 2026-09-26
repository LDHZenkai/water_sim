shader_type spatial;
render_mode cull_back, fog_disabled;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_texture : filter_linear_mipmap_anisotropic;
uniform vec4 albedo_factor : source_color = vec4(1.0);
varying float hull_height;
void vertex() { hull_height=VERTEX.y; }
void fragment() {
 vec3 orm=texture(orm_texture,UV).rgb;
 vec3 wood=texture(albedo_texture,UV).rgb*albedo_factor.rgb;
 float ragged=dot(wood,vec3(0.333))*0.35;
 float wet=1.0-smoothstep(1.0,2.0,hull_height+ragged);
 ALBEDO=wood*mix(1.0,0.66,wet);
 NORMAL_MAP=texture(normal_texture,UV).rgb;
 // Preserve the source material: no new AO multiplication.
 ROUGHNESS=mix(orm.g,0.15,wet);
 METALLIC=orm.b;
}
