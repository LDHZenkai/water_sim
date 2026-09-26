shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, blend_add, depth_draw_never;
void fragment() {
 vec2 p=UV*2.0-1.0;
 float width=mix(0.6,0.08,1.0-UV.y);
 float glow=(1.0-smoothstep(0.25,1.0,abs(p.x)/width))*(1.0-smoothstep(0.45,1.0,abs(p.y)));
 ALBEDO=vec3(1.0,0.55,0.12)*1.5;
 ALPHA=glow;
}
