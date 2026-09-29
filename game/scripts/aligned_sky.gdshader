shader_type sky;
#include "res://ocean/horizon.gdshaderinc"
uniform sampler2D horizon_map : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 sun_direction;
// Explicit inverse yaw makes panorama/light alignment independent of editor conventions.
uniform sampler2D panorama : source_color, filter_linear, repeat_enable;
uniform float yaw = 0.6108652382;
// Weather (atmosphere.gd): cloud deck cover 0..1, its drift with the wind
// (km, world XZ), storm darkness 0..1 and a lightning flash 0..1.
uniform float cloud_cover = 0.25;
uniform vec2 cloud_offset = vec2(0.0);
uniform float storm = 0.0;
uniform float flash = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 19.19);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Overcast deck radiance; atmosphere.gd matches the fog to it so the
// horizon dissolves in rain.
vec3 overcast_color(float darkness) {
	return vec3(0.30, 0.32, 0.35) * mix(0.85, 0.28, darkness);
}

float clouds(vec2 p) {
	float total = 0.0;
	float amplitude = 0.55;
	for (int i = 0; i < 5; i++) {
		total += amplitude * value_noise(p);
		p = p * 2.03 + vec2(17.3, 9.1);
		amplitude *= 0.5;
	}
	return total;
}

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
	// Cloud deck ~2 km up: FBM on a plane, drifting with the wind. Cover
	// thresholds the noise. Fair weather: sunlit cumulus with grey bases.
	// Overcast: an unbroken deck (no sun, no blue) with darker scud beneath
	// it; storm darkens the whole deck.
	float overcast = smoothstep(0.55, 1.0, cloud_cover);
	vec3 deck = overcast_color(storm);
	float up = max(EYEDIR.y, 0.0);
	COLOR = mix(COLOR, deck * (0.9 + 0.25 * up), overcast);
	if (EYEDIR.y > 0.0) {
		vec2 p = EYEDIR.xz / (EYEDIR.y + 0.06) * 1.6 + cloud_offset;
		float n = clouds(p);
		float threshold = mix(0.78, 0.25, cloud_cover);
		// Distant cloud merges into a uniform layer toward the horizon.
		float amount = smoothstep(threshold, threshold + 0.25, n) * smoothstep(0.0, 0.12, EYEDIR.y);
		float thick = smoothstep(threshold, threshold + 0.55, n);
		float sunward = pow(max(dot(d, sun_direction), 0.0), 6.0);
		vec3 fair = mix(mix(vec3(0.92, 0.9, 0.86), vec3(1.0, 0.92, 0.8), sunward), vec3(0.45, 0.47, 0.5), thick * 0.7);
		vec3 scud = deck * (0.9 + 0.25 * up) * mix(1.12, 0.6, thick);
		COLOR = mix(COLOR, mix(fair, scud, overcast), amount);
	}
	vec3 horizon_color=horizon_radiance(textureLod(horizon_map,vec2(uv.x,0.5),6.0).rgb);
	horizon_color=mix(horizon_color, deck * 0.9, overcast);
	COLOR=mix(COLOR,horizon_color,1.0-smoothstep(0.0,0.006,abs(EYEDIR.y)));
	// Lightning lights the cloud base from below.
	COLOR += vec3(0.75, 0.8, 1.0) * flash * (0.4 + 0.6 * max(EYEDIR.y, 0.0)) * (0.3 + cloud_cover);
}
