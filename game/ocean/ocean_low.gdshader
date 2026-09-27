shader_type spatial;
render_mode skip_vertex_transform, cull_back, unshaded, fog_disabled;
#include "res://ocean/surface.gdshaderinc"
#include "res://ocean/hull.gdshaderinc"
#include "res://ocean/horizon.gdshaderinc"
#include "res://ocean/water.gdshaderinc"
uniform sampler2D sky_map : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 sun_direction;
uniform float sun_energy = 3.5;
uniform float sky_yaw;
void fragment() {
 // QUEUE
 vec3 local=(world_to_ship*vec4(world_position,1)).xyz;
 // HULL_CLIP
 vec3 color;
 {
  float distance_to_eye=length(VERTEX);
  Water water=sample_water(wave_coordinate,distance_to_eye);
  vec3 n_world=water_normal(water);
  vec3 n=normalize((VIEW_MATRIX*vec4(n_world,0)).xyz);
  vec3 v=normalize(-VERTEX);
  float ndv=max(dot(n,v),0.02);
  float f=1.0-ndv;
  float fresnel=0.02+0.98*f*f*f*f*f;
  float roughness=water_roughness(water.variance);
  vec3 reflected=(INV_VIEW_MATRIX*vec4(reflect(-v,n),0)).xyz;
  float c=cos(sky_yaw), s=sin(sky_yaw);
  vec3 d=vec3(c*reflected.x-s*reflected.z,max(reflected.y,0.0),s*reflected.x+c*reflected.z);
  vec2 sky_uv=vec2(atan(d.x,-d.z)/TAU,acos(clamp(d.y,-1.0,1.0))/PI);
  vec3 sky=textureLod(sky_map,sky_uv,roughness*7.0).rgb;
  sky=sky/(vec3(1.0)+sky/4.0);
  vec3 l=(VIEW_MATRIX*vec4(sun_direction,0)).xyz;
  vec3 h=normalize(v+l);
  float ndh=max(dot(n,h),0.0);
  float a2=pow(roughness,4.0);
  float denom=ndh*ndh*(a2-1.0)+1.0;
  float glitter=a2/(PI*denom*denom)*0.02*(sun_energy/3.5)*max(dot(n,l),0.0)/max(4.0*ndv,0.08);
  float occlusion=1.0;
  float contact=0.0;
  if(abs(local.x-3.5)<19.5 && abs(local.z)<6.0) {
   float edge=hull_edge(local);
   contact=smoothstep(0.04,0.16,edge)*(1.0-smoothstep(0.4,1.3,edge))*(wake_enabled?0.3:0.6);
   occlusion=1.0-0.25*(1.0-smoothstep(0.0,2.0,edge));
  }
  float foam=foam_coverage(max(water.foam,contact),water.fine)*(1.0-smoothstep(150.0,600.0,distance_to_eye)*0.6);
  // Three graded taps along the 14 m freeboard shadow; no cut-out edge.
  for(int tap=0;tap<3;tap++) {
   float reach=4.0+5.0*float(tap);
   vec3 shadow_point=(world_to_ship*vec4(world_position+sun_direction*reach,1)).xyz;
   float shade=1.0-smoothstep(0.0,2.5,hull_edge(shadow_point));
   occlusion-=shade*(0.20-0.05*float(tap));
  }
  occlusion=max(occlusion,0.30);
  vec3 body=water_albedo*(0.35+0.65*clamp(dot(n_world,sun_direction),0.0,1.0))*sun_energy*0.6;
  color=mix(body,sky,fresnel)*occlusion;
  vec3 view_world=normalize(CAMERA_POSITION_WORLD-world_position);
  color+=crest_transmission(n_world,view_world,sun_direction,world_position.y)*sun_energy*occlusion*(1.0-foam);
  vec3 horizon_view=vec3(c*view_world.x-s*view_world.z,0,s*view_world.x+c*view_world.z);
  // View direction FROM eye to water, matching sky panorama azimuth.
  float azimuth=atan(-horizon_view.x,horizon_view.z)/TAU;
  vec3 horizon=horizon_radiance(textureLod(sky_map,vec2(azimuth,0.5),6.0).rgb);
  vec3 foam_color=max(horizon*1.1,vec3(0.8,0.78,0.74))*(0.5+0.5*max(dot(n,l),0.0))*occlusion;
  color=mix(color,foam_color,foam);
  color=mix(color,horizon,ocean_fog);
  color+=vec3(1.0,0.80,0.55)*glitter*occlusion*(1.0-foam)*(1.0-0.6*ocean_fog);
 }
 ALBEDO=color;
}
