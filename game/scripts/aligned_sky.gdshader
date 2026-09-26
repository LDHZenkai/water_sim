shader_type sky;
#include "res://ocean/horizon.gdshaderinc"
uniform sampler2D horizon_map : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 sun_direction;
// Explicit inverse yaw makes panorama/light alignment independent of editor conventions.
uniform sampler2D panorama : source_color, filter_linear, repeat_enable;
uniform float yaw = 0.6108652382;
void sky() {
	float c = cos(yaw);
	float s = sin(yaw);
	vec3 d = vec3(c * EYEDIR.x - s * EYEDIR.z, EYEDIR.y, s * EYEDIR.x + c * EYEDIR.z);
	vec2 uv = vec2(mod(atan(d.x, -d.z) / TAU + 1.0, 1.0), acos(clamp(d.y, -1.0, 1.0)) / PI);
	COLOR = texture(panorama, uv).rgb;
	// A shared shoulder keeps visible sky and radiance consistent.
	float sun_distance = acos(clamp(dot(d,sun_direction), -1.0,1.0));
	float shoulder=mix(3.0,6.0,smoothstep(0.01,0.14,sun_distance))+5.0*(1.0-smoothstep(0.002,0.008,sun_distance));
	COLOR=COLOR/(vec3(1.0)+COLOR/shoulder);
	float horizon=1.0-smoothstep(0.0,0.22,abs(d.y));
	COLOR*=mix(vec3(1.0),vec3(1.0,0.86,0.68),horizon*0.5);
	vec3 horizon_color=horizon_radiance(textureLod(horizon_map,vec2(uv.x,0.5),6.0).rgb);
	COLOR=mix(COLOR,horizon_color,1.0-smoothstep(0.0,0.006,abs(EYEDIR.y)));
}
