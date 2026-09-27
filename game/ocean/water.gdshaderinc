// Per-pixel sea surface shared by the lit and unshaded ocean shaders.
// Slopes: long band (per vertex) + every FFT cascade (per pixel, mip filtered).
// Variance: slope variance hidden inside a pixel (LEAN: E[s^2] - E[s]^2 from
// the mips) plus the capillary ripples below the finest cascade (Cox-Munk
// total minus the resolved spectrum, computed on the CPU). This is what
// widens the sun glitter with distance, from physics rather than a fudge.
uniform sampler2DArray fft_moments : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail0 : filter_linear_mipmap, repeat_enable;
uniform sampler2D detail1 : filter_linear_mipmap, repeat_enable;
uniform float unresolved_variance = 0.006;
// Inherent optical properties of the water column, 1/m (red, green, blue).
uniform vec3 absorption = vec3(0.40, 0.06, 0.025);
uniform vec3 backscatter = vec3(0.003, 0.0045, 0.006);
uniform vec3 water_albedo = vec3(0.0012, 0.0115, 0.032);
// Whitecaps start where the combined surface is compressed this much
// (Jacobian of every band's horizontal map, long x cascade 0 x cascade 1).
uniform float breaking_jacobian = 0.5;
// Gale foam streaks blown down the wind (0 below force 7), ocean.gd.
uniform float foam_streaks = 0.0;
uniform vec2 wind_direction = vec2(1.0, 0.0);

struct Water {
	vec2 slope;
	float variance;
	float foam;
	float fine;
};

Water sample_water(vec2 q, float distance_to_eye) {
	Water water;
	water.slope = long_surface.xy;
	water.variance = unresolved_variance + long_hidden;
	water.foam = 0.0;
	water.fine = 0.5;
	if (fft_enabled) {
		vec3 uv0 = vec3((q - cascade_offset0) * cascade_scale0, 0.0);
		vec3 uv1 = vec3((q - cascade_offset1) * cascade_scale1, 1.0);
		vec3 uv2 = vec3((q - cascade_offset2) * cascade_scale2, 2.0);
		vec4 s0 = texture(fft_slopes, uv0);
		vec4 s1 = texture(fft_slopes, uv1);
		vec4 s2 = texture(fft_slopes, uv2);
		water.slope += s0.xy + s1.xy + s2.xy;
		water.variance += max(texture(fft_moments, uv0).w - dot(s0.xy, s0.xy), 0.0);
		water.variance += max(texture(fft_moments, uv1).w - dot(s1.xy, s1.xy), 0.0);
		water.variance += max(texture(fft_moments, uv2).w - dot(s2.xy, s2.xy), 0.0);
		// Persistent foam from the cascades, plus active breaking wherever the
		// whole surface (long band included) is compressed past the threshold.
		float compressed = long_surface.z * s0.w * s1.w;
		float breaking = smoothstep(breaking_jacobian + 0.2, breaking_jacobian - 0.1, compressed);
		water.foam = max(max(s0.z, s1.z * 0.8), breaking);
		// Metre and decimetre ripples break foam into lace and bubbles.
		water.fine = clamp(0.5 + 1.2 * (s1.x + s1.y) + 2.0 * (s2.x - s2.y), 0.0, 1.0);
		if (foam_streaks > 0.0) {
			// From force 8 the wind tears foam off the crests and lays it in
			// long bands down the wind; they ride on the water (q frame).
			vec2 across = vec2(-wind_direction.y, wind_direction.x);
			vec2 sp = vec2(dot(q, across) * 0.08, dot(q, wind_direction) * 0.005);
			float streak = texture(detail1, sp).r * 0.65 + texture(detail0, sp * vec2(3.1, 2.3) + 0.37).r * 0.35;
			water.foam = max(water.foam, smoothstep(0.6, 0.8, streak) * foam_streaks * 0.5);
		}
	} else {
		// No RenderingDevice (headless, Compatibility): legacy detail maps.
		vec2 uv = q;
		vec2 detail = texture(detail0, uv * 0.34 + sim_time * vec2(0.012, 0.008)).rg * 2.0 - 1.0;
		detail += texture(detail1, uv * 0.035 + sim_time * vec2(-0.009, 0.015)).rg * 2.0 - 1.0;
		water.slope += detail * 0.13 * mix(1.0, 0.46, smoothstep(30.0, 180.0, distance_to_eye));
		water.variance += 0.004 + 0.02 * smoothstep(10.0, 180.0, distance_to_eye);
		water.fine = detail.x * 0.25 + 0.5;
	}
	if (wake_enabled) {
		vec2 uv = (q - wake_rect.xy) * wake_rect.z;
		if (uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0) {
			vec4 wake = texture(wake_map, vec3(uv, 0.0));
			float fade = wake_fade(uv);
			water.slope += wake.yz * fade;
			water.foam = max(water.foam, wake.w * fade);
		}
	}
	return water;
}

vec3 water_normal(Water water) {
	return normalize(vec3(-water.slope.x, 1.0, -water.slope.y));
}

// Foam coverage: the amount sets how much of the ripple pattern turns white,
// so thin foam is lace and bubbles and only thick foam is solid.
float foam_coverage(float amount, float fine) {
	float threshold = 1.0 - amount;
	// Where the lace is finer than a pixel, blend to its mean coverage
	// instead of aliasing into speckle.
	float soft = 1.5 * fwidth(fine);
	return smoothstep(threshold - 0.08 - soft, threshold + 0.12 + soft, fine) * smoothstep(0.02, 0.2, amount);
}

// GGX roughness from total slope variance: Beckmann m^2 = variance, alpha ~ m,
// and Godot's roughness is sqrt(alpha).
float water_roughness(float variance) {
	return clamp(pow(variance, 0.25), 0.04, 0.75);
}

// Sunlight refracted into the back of a wave, scattered forward through the
// crest (Henyey-Greenstein) and attenuated by the water's absorption: the
// thin-crest glow, coloured by physics rather than picked.
vec3 crest_transmission(vec3 normal, vec3 view_world, vec3 sun, float height) {
	float path = 3.0;
	vec3 transmit = exp(-absorption * path);
	vec3 scatter = backscatter / (absorption + backscatter);
	float g = 0.55;
	float mu = dot(-sun, -view_world);
	float phase = (1.0 - g * g) / (4.0 * PI * pow(1.0 + g * g - 2.0 * g * mu, 1.5));
	float thin = smoothstep(-0.3, 1.2, height);
	float into_view = clamp(dot(normal, view_world), 0.0, 1.0);
	float refracted = 1.0 - pow(1.0 - into_view, 5.0);
	float lit_back = clamp(0.5 - 0.5 * dot(normal, sun), 0.0, 1.0);
	return transmit * scatter * phase * thin * refracted * (0.35 + lit_back);
}
