shader_type spatial;
render_mode skip_vertex_transform, cull_back, shadows_disabled, specular_schlick_ggx;
#include "res://ocean/surface.gdshaderinc"
#include "res://ocean/hull.gdshaderinc"
#include "res://ocean/water.gdshaderinc"
uniform vec3 sun_direction;
uniform float sun_energy = 3.5;
uniform vec3 sun_color = vec3(1.0, 0.95, 0.88);
void fragment() {
 // QUEUE
 vec3 local=(world_to_ship*vec4(world_position,1)).xyz;
 // HULL_CLIP
 float distance_to_eye=length(VERTEX);
 Water water=sample_water(wave_coordinate,distance_to_eye);
 vec3 world_normal=water_normal(water);
 NORMAL=normalize((VIEW_MATRIX*vec4(world_normal,0)).xyz);
 float occlusion=1.0;
 float contact=0.0;
 if(abs(local.x-3.5)<19.5 && abs(local.z)<6.0) {
  float edge=hull_edge(local);
  contact=smoothstep(0.04,0.16,edge)*(1.0-smoothstep(0.4,1.3,edge))*(wake_enabled?0.3:0.6);
  occlusion=1.0-0.25*(1.0-smoothstep(0.0,2.0,edge));
 }
 if(!wake_enabled) {
  // Without the reactive simulation, keep the legacy flat stern slick.
  float slick=(1.0-smoothstep(0.0,1.8,abs(local.z)))*smoothstep(-35.0,-14.0,local.x)*(1.0-smoothstep(-14.0,-12.0,local.x))*0.08;
  water.variance*=1.0-slick*2.0;
 }
 float foam=foam_coverage(max(water.foam,contact),water.fine);
 foam*=1.0-smoothstep(150.0,600.0,distance_to_eye)*0.6;
 vec3 shadow_point=(world_to_ship*vec4(world_position+sun_direction*5.0,1)).xyz;
 shadow_point.y=0.6;
 if(inside_hull(shadow_point)) occlusion*=0.4;
 ROUGHNESS=mix(water_roughness(water.variance),0.85,foam);
 METALLIC=0.0;
 SPECULAR=mix(0.25,0.1,foam); // F0 = 0.02 for water; engine sky radiance supplies Fresnel reflection.
 ALBEDO=mix(water_albedo,vec3(0.78,0.80,0.80),foam)*occlusion;
 vec3 view_world=normalize(CAMERA_POSITION_WORLD-world_position);
 vec3 glow=crest_transmission(world_normal,view_world,sun_direction,world_position.y);
 EMISSION=sun_color*sun_energy*glow*(1.0-foam)*occlusion;
 AO=occlusion;
 AO_LIGHT_AFFECT=1.0;
}
