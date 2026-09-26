uniform sampler2D hull_distance : filter_linear, repeat_disable;
vec2 hull_interval(vec3 p) {
 return texture(hull_bounds,(vec2((p.x+14.0)/35.0,(p.y+2.0)/5.0)*vec2(191,63)+0.5)/vec2(192,64)).rg;
}
bool hull_box(vec3 p) {
 return p.x>-14.0 && p.x<21.0 && p.y>-2.0 && p.y<3.0;
}
bool inside_hull(vec3 p) {
 if (!hull_box(p)) return false;
 vec2 b=hull_interval(p);
 return p.z>b.x && p.z<b.y;
}

float hull_edge(vec3 p) {
 if(p.x < -16.0 || p.x > 23.0 || abs(p.z)>6.0) return 100.0;
 return texture(hull_distance,(vec2((p.x+16.0)/39.0,(p.z+6.0)/12.0)*vec2(191,63)+0.5)/vec2(192,64)).r;
}
