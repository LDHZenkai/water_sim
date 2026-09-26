uniform vec4 waves[8];
uniform float wave_phases[8];
uniform int wave_count = 5;
uniform float sim_time;
uniform bool fog_enabled = true;
uniform sampler2D hull_bounds : filter_linear, repeat_disable;
uniform mat4 world_to_ship;
varying vec3 world_position;
varying float compression;
varying float ocean_fog;
varying vec2 wave_coordinate;
varying vec2 grid_coordinate;
uniform float grid_half = 60.0;
void vertex() {
 grid_coordinate = VERTEX.xz;
 vec3 p = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 vec2 q = p.xz;
 wave_coordinate=q;
 float distance_to_eye = length(q-CAMERA_POSITION_WORLD.xz);
 // A single coordinate-based LOD for the welded lattice. Finish displacement
 // before the 400 -> 800 m skirt cell, whose span cannot resolve any wave.
 float cell=400.0*1.6/grid_half*pow(clamp(max(abs(VERTEX.x),abs(VERTEX.z))/400.0,0.0,1.0),0.375);
 float envelope=1.0-smoothstep(200.0,400.0,max(abs(VERTEX.x),abs(VERTEX.z)));
 compression=0.0;
 for(int i=0;i<8;i++) {
  if(i>=wave_count) break;
  vec4 w=waves[i]; vec2 d=vec2(cos(w.x),sin(w.x));
  float k=TAU/w.z, phase=k*dot(d,q)-wave_phases[i];
  float s=sin(phase), c=cos(phase), h=w.y*w.w;
  float resolved=envelope*(1.0-smoothstep(w.z*0.25,w.z*0.5,cell));
  p+=resolved*vec3(h*d.x*c,w.y*s,h*d.y*c);
  compression+=resolved*h*k*s;
 }
 ocean_fog=fog_enabled ? pow(clamp((length(p-CAMERA_POSITION_WORLD)-250.0)/2750.0,0.0,1.0),1.5) : 0.0;
 world_position=p;
 VERTEX=(VIEW_MATRIX*vec4(p,1)).xyz;
 NORMAL=(VIEW_MATRIX*vec4(0,1,0,0)).xyz;
 POSITION=PROJECTION_MATRIX*vec4(VERTEX,1);
}

// Resolve the two dominant swells per pixel, independently of mesh density.
// The remaining wind waves use the mip-filtered detail normal textures.
vec3 swell_normal(vec2 q, float distance_to_eye) {
 vec3 dx=vec3(1,0,0), dz=vec3(0,0,1);
 float envelope=1.0-smoothstep(400.0,1500.0,distance_to_eye);
 for(int i=0;i<2;i++) {
  vec4 w=waves[i]; vec2 d=vec2(cos(w.x),sin(w.x));
  float k=TAU/w.z, phase=k*dot(d,q)-wave_phases[i];
  float s=sin(phase), c=cos(phase), h=w.y*w.w;
  dx+=envelope*vec3(-h*k*d.x*d.x*s,w.y*k*d.x*c,-h*k*d.x*d.y*s);
  dz+=envelope*vec3(-h*k*d.x*d.y*s,w.y*k*d.y*c,-h*k*d.y*d.y*s);
 }
 return normalize(cross(dz,dx));
}
