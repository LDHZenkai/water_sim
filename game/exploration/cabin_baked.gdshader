shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic;
uniform bool has_normal = false;
uniform float normal_strength = 1.0;
varying mat3 local_to_view;
varying vec3 dominant_direction;
varying float geometric_response;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool triplanar = false;
uniform bool candle_on = true;
uniform float light_scale = 1.0;
uniform float sun_scale = 1.0;
uniform vec3 candle_local = vec3(0.0);
uniform float specular_amount = 0.0;
uniform float specular_power = 32.0;
varying vec3 candle_vector;
varying vec3 local_position;
varying vec3 local_normal;
void vertex() {
 local_to_view = MODELVIEW_NORMAL_MATRIX;
 dominant_direction = normalize((MODELVIEW_MATRIX * vec4(CUSTOM0.xyz, 0.0)).xyz);
 geometric_response = CUSTOM0.w;
 candle_vector = (MODELVIEW_MATRIX * vec4(candle_local - VERTEX, 0.0)).xyz;
 local_position = VERTEX;
 local_normal = NORMAL;
}
void fragment() {
 vec3 albedo = texture(albedo_map, UV).rgb;
 if (triplanar) {
  vec3 w = pow(abs(local_normal), vec3(4.0));
  w /= max(w.x+w.y+w.z, 0.001);
  albedo = texture(albedo_map, local_position.zy).rgb*w.x + texture(albedo_map, local_position.xz).rgb*w.y + texture(albedo_map, local_position.xy).rgb*w.z;
 }
 vec3 detail_normal = normalize(NORMAL);
 if (has_normal) {
  vec3 mapped = texture(normal_map, UV).xyz * 2.0 - 1.0;
  mapped.xy *= normal_strength;
  mapped.z = sqrt(max(0.0, 1.0-dot(mapped.xy,mapped.xy)));
  detail_normal = normalize(TANGENT*mapped.x + BINORMAL*mapped.y + NORMAL*mapped.z);
  if (triplanar) {
   vec3 w = pow(abs(local_normal), vec3(4.0));
   w /= max(w.x+w.y+w.z, 0.001);
   vec2 nx = (texture(normal_map, local_position.zy).xy*2.0-1.0)*normal_strength;
   vec2 ny = (texture(normal_map, local_position.xz).xy*2.0-1.0)*normal_strength;
   vec2 nz = (texture(normal_map, local_position.xy).xy*2.0-1.0)*normal_strength;
   vec3 perturb = vec3(0.0,nx.y,nx.x)*w.x + vec3(ny.x,0.0,ny.y)*w.y + vec3(nz.x,nz.y,0.0)*w.z;
   detail_normal = normalize(local_to_view * normalize(local_normal + perturb));
  }
 }
 // One directional-lightmap response, normalized to preserve baked irradiance.
 float response = clamp(max(dot(detail_normal, normalize(dominant_direction)), 0.0) / max(geometric_response,0.25), 0.0, 2.0);
 // Vertex channels hold independent, ray-occluded irradiance contributions.
 vec3 illumination = vec3(0.16,0.17,0.19);
 // Broad window bounce preserves readable walls away from the direct apertures.
 illumination += vec3(0.16,0.115,0.064) * sun_scale;
 illumination += response * COLOR.b * vec3(1.0,0.72,0.40) * sun_scale;
 illumination += response * COLOR.r * vec3(1.0,0.72,0.40) * sun_scale;
 if (candle_on) illumination += response * COLOR.g * vec3(1.0,0.57,0.25);
 ALBEDO = albedo * tint.rgb * illumination * light_scale;
 // A single broad, view-dependent candle highlight retains the polished table
 // and metal furniture accents without running the PBR light loop.
 if (candle_on && specular_amount > 0.0) {
  vec3 h = normalize(normalize(candle_vector) + VIEW);
  float highlight = pow(max(dot(detail_normal, h), 0.0), specular_power);
  ALBEDO += vec3(1.0,0.57,0.25) * COLOR.g * highlight * specular_amount * light_scale;
 }
}
