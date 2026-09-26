shader_type spatial;
render_mode skip_vertex_transform, cull_back, shadows_disabled, specular_schlick_ggx;
#include "res://ocean/surface.gdshaderinc"
#include "res://ocean/hull.gdshaderinc"
uniform sampler2D detail0 : filter_linear_mipmap, repeat_enable;
uniform sampler2D detail1 : filter_linear_mipmap, repeat_enable;
uniform vec3 sun_direction;
void fragment() {
 // QUEUE
 vec3 local=(world_to_ship*vec4(world_position,1)).xyz;
 // HULL_CLIP
 float distance_to_eye=length(VERTEX);
 vec2 uv=world_position.xz;
 vec3 swell=(VIEW_MATRIX*vec4(swell_normal(wave_coordinate,distance_to_eye),0)).xyz;
 vec2 slopes=texture(detail0,uv*0.34+sim_time*vec2(0.012,0.008)).rg*2.0-1.0;
 slopes+=texture(detail1,uv*0.035+sim_time*vec2(-0.009,0.015)).rg*2.0-1.0;
 float footprint=max(length(dFdx(uv)),length(dFdy(uv)));
 // Reuse the second normal lookup at a coarser scale in the far field.
 float far_mix=smoothstep(30.0,180.0,distance_to_eye);
 float detail_filter=mix(1.0,0.46,far_mix)/(1.0+footprint*0.04);
 vec3 n=normalize(swell+(VIEW_MATRIX*vec4(slopes.x,0,slopes.y,0)).xyz*0.13*detail_filter);
 NORMAL=n;
 // Widen from texture footprint, never derivatives of triangle normals.
 ROUGHNESS=min(0.5,mix(0.10,0.45,smoothstep(10.0,180.0,distance_to_eye))+footprint*0.12);
 METALLIC=0.0;
 SPECULAR=0.25; // F0 ~ 0.02; engine sky radiance supplies Fresnel reflection.
 float crest=smoothstep(0.035,0.085,compression)*(1.0-smoothstep(100.0,300.0,distance_to_eye));
 crest*=smoothstep(0.45,0.75,slopes.x*0.25+0.5+crest*0.5);
 float occlusion=1.0;
 float contact=0.0;
 if(abs(local.x-3.5)<19.5 && abs(local.z)<6.0) {
  float edge=hull_edge(local);
  contact=smoothstep(0.04,0.16,edge)*(1.0-smoothstep(0.4,1.3,edge))*smoothstep(0.3,0.7,slopes.y*0.25+0.5)*0.4;
  occlusion=1.0-0.25*(1.0-smoothstep(0.0,2.0,edge));
 }
 float wake=(1.0-smoothstep(0.0,1.8,abs(local.z)))*smoothstep(-35.0,-14.0,local.x)*(1.0-smoothstep(-14.0,-12.0,local.x))*0.08;
 float foam=clamp(crest*0.30+contact,0.0,0.65);
 ROUGHNESS*=1.0-wake*2.0;
 vec3 shadow_point=(world_to_ship*vec4(world_position+sun_direction*5.0,1)).xyz;
 shadow_point.y=0.6;
 if(inside_hull(shadow_point)) occlusion*=0.4;
 ALBEDO=mix(vec3(0.004,0.014,0.030),vec3(0.30,0.32,0.32),foam);
 vec3 world_normal=normalize((INV_VIEW_MATRIX*vec4(n,0)).xyz);
 float glow=max(dot(world_normal,sun_direction),0.0)*smoothstep(0.15,0.65,world_position.y);
 vec3 view_world=normalize(CAMERA_POSITION_WORLD-world_position);
 glow*=pow(max(dot(-view_world,sun_direction),0.0),4.0);
 EMISSION=vec3(0.02,0.07,0.07)*glow*occlusion;
 ALBEDO*=occlusion;
 AO=occlusion;
 AO_LIGHT_AFFECT=1.0;
}
