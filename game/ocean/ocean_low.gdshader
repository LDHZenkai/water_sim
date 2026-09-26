shader_type spatial;
render_mode skip_vertex_transform, cull_back, unshaded, fog_disabled;
#include "res://ocean/surface.gdshaderinc"
#include "res://ocean/hull.gdshaderinc"
#include "res://ocean/horizon.gdshaderinc"
uniform sampler2D detail0 : filter_linear_mipmap, repeat_enable;
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
  vec2 uv=world_position.xz*mix(0.55,0.10,smoothstep(30.0,150.0,distance_to_eye))+sim_time*vec2(0.012,0.008);
  vec2 gx=dFdx(uv), gy=dFdy(uv);
  float footprint=max(length(gx),length(gy));
  float detail_filter=mix(1.0,0.375,smoothstep(30.0,150.0,distance_to_eye))/(1.0+footprint*0.5);
  vec2 detail=textureGrad(detail0,uv,gx,gy).rg;
  float slick=(1.0-smoothstep(0.0,1.8,abs(local.z)))*smoothstep(-35.0,-14.0,local.x)*(1.0-smoothstep(-14.0,-12.0,local.x));
  detail_filter*=1.0-slick*0.5;
  vec3 n=normalize((VIEW_MATRIX*vec4(swell_normal(wave_coordinate,distance_to_eye),0)).xyz+(VIEW_MATRIX*vec4((detail.x*2.0-1.0)*0.16,0,(detail.y*2.0-1.0)*0.16,0)).xyz*detail_filter);
  vec3 v=normalize(-VERTEX);
  float ndv=max(dot(n,v),0.02);
  float f=1.0-max(ndv,0.08*smoothstep(30.0,180.0,distance_to_eye)); float fresnel=(0.02+0.98*f*f*f*f*f)*mix(1.0,0.7,smoothstep(30.0,180.0,distance_to_eye));
  float roughness=mix(0.10,0.45,smoothstep(10.0,180.0,distance_to_eye));
  roughness=min(0.5,roughness+footprint*0.12);
  vec3 reflected=(INV_VIEW_MATRIX*vec4(reflect(-v,n),0)).xyz;
  float c=cos(sky_yaw), s=sin(sky_yaw);
  vec3 d=vec3(c*reflected.x-s*reflected.z,max(reflected.y,0.0),s*reflected.x+c*reflected.z);
  vec2 sky_uv=vec2(atan(d.x,-d.z)/TAU,acos(clamp(d.y,-1.0,1.0))/PI);
  vec3 sky=textureLod(sky_map,sky_uv,roughness*7.0).rgb;
  sky=sky/(vec3(1.0)+sky/4.0);
  vec3 l=(VIEW_MATRIX*vec4(sun_direction,0)).xyz;
  vec3 h=normalize(v+l);
  float ndh=max(dot(n,h),0.0);
  float glitter_roughness=min(0.30,mix(0.12,0.26,smoothstep(10.0,180.0,distance_to_eye))+footprint*0.04);
  float a2=pow(glitter_roughness,4.0);
  float denom=ndh*ndh*(a2-1.0)+1.0;
  float glitter=a2/(PI*denom*denom)*0.018*(sun_energy/3.5)*max(dot(n,l),0.0)/max(4.0*ndv,0.08);
  float crest=smoothstep(0.035,0.085,compression)*(1.0-smoothstep(100.0,300.0,distance_to_eye));
  float foam=crest*smoothstep(0.45,0.75,detail.x+crest*0.5)*0.30;
  float occlusion=1.0;
  if(abs(local.x-3.5)<19.5 && abs(local.z)<6.0) {
   float edge=hull_edge(local);
   float contact=smoothstep(0.04,0.16,edge)*(1.0-smoothstep(0.4,1.3,edge));
   foam+=contact*smoothstep(0.30,0.7,detail.y)*0.4;
   occlusion=1.0-0.25*(1.0-smoothstep(0.0,2.0,edge));
  }
  // Three graded taps along the 14 m freeboard shadow; no cut-out edge.
  for(int tap=0;tap<3;tap++) {
   float reach=4.0+5.0*float(tap);
   vec3 shadow_point=(world_to_ship*vec4(world_position+sun_direction*reach,1)).xyz;
   float shade=1.0-smoothstep(0.0,2.5,hull_edge(shadow_point));
   occlusion-=shade*(0.20-0.05*float(tap));
  }
  occlusion=max(occlusion,0.30);
  color=mix(vec3(0.004,0.014,0.030),sky,fresnel)*occlusion;
  vec3 n_world=normalize((INV_VIEW_MATRIX*vec4(n,0)).xyz);
  color*=0.75+0.4*clamp(dot(n_world,sun_direction)*0.5+0.5,0.0,1.0);
  color*=mix(0.8,1.05,smoothstep(-1.2,1.2,world_position.y));
  vec3 view_world=normalize(CAMERA_POSITION_WORLD-world_position);
  float backlight=max(dot(-view_world,sun_direction),0.0);
  color+=vec3(0.02,0.07,0.07)*backlight*backlight*backlight*backlight*smoothstep(0.5,1.3,world_position.y)*occlusion;
  vec3 horizon_view=vec3(c*view_world.x-s*view_world.z,0,s*view_world.x+c*view_world.z);
  // View direction FROM eye to water, matching sky panorama azimuth.
  float azimuth=atan(-horizon_view.x,horizon_view.z)/TAU;
  vec3 horizon=horizon_radiance(textureLod(sky_map,vec2(azimuth,0.5),6.0).rgb);
  vec3 foam_color=max(color*1.1,max(horizon*1.1,vec3(0.8,0.78,0.74))*(0.5+0.5*max(dot(n,l),0.0))*occlusion);
  color=mix(color,foam_color,min(foam,0.6));
  color=mix(color,horizon,ocean_fog);
  color+=vec3(1.0,0.80,0.55)*glitter*occlusion*(1.0-0.6*ocean_fog);
 }
 ALBEDO=color;
}
