// Long-wave band: explicit components shared with sea_state.gd (CPU).
// (kx, kz, amplitude, horizontal amplitude); phases are wrapped on the CPU.
uniform vec4 long_waves[96];
uniform float long_phases[96];
uniform int long_count = 32;
uniform float sim_time;
uniform bool fog_enabled = true;
uniform sampler2D hull_bounds : filter_linear, repeat_disable;
uniform mat4 world_to_ship;
// Short-wave band: GPU FFT cascades (fft_ocean.gd).
uniform bool fft_enabled = false;
uniform sampler2DArray fft_displacement : filter_linear_mipmap, repeat_enable;
uniform sampler2DArray fft_slopes : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float cascade_scale0 = 0.005977;
uniform float cascade_scale1 = 0.033670;
uniform float cascade_scale2 = 0.189753;
uniform vec2 cascade_offset0;
uniform vec2 cascade_offset1;
uniform vec2 cascade_offset2;
uniform float fft_texels = 256.0;
// Reactive band: local wave simulation around the ship (wake_sim.gd).
uniform bool wake_enabled = false;
uniform sampler2DArray wake_map : filter_linear_mipmap, repeat_disable;
uniform vec4 wake_rect; // world XZ of the domain's corner, 1/size, edge fade (uv)
varying vec3 world_position;
varying float ocean_fog;
varying vec2 wave_coordinate;
varying vec2 grid_coordinate;
// Long-band slopes of the displaced surface and its Jacobian (1 = unstretched).
varying vec3 long_surface;
// Slope variance of long waves the mesh could not carry here (far field).
varying float long_hidden;
uniform float grid_half = 60.0;

float wake_fade(vec2 uv) {
	vec2 edge = min(uv, 1.0 - uv);
	return smoothstep(0.0, wake_rect.w, min(edge.x, edge.y));
}

void vertex() {
	grid_coordinate = VERTEX.xz;
	vec3 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 q = p.xz;
	wave_coordinate = q;
	float distance_to_eye = length(q - CAMERA_POSITION_WORLD.xz);
	// A single coordinate-based LOD for the welded lattice. Finish displacement
	// before the 400 -> 800 m skirt cell, whose span cannot resolve any wave.
	float cell = 400.0 * 1.6 / grid_half * pow(clamp(max(abs(VERTEX.x), abs(VERTEX.z)) / 400.0, 0.0, 1.0), 0.375);
	float envelope = 1.0 - smoothstep(200.0, 400.0, max(abs(VERTEX.x), abs(VERTEX.z)));
	vec3 d = vec3(0.0);
	vec2 slope = vec2(0.0);
	float jxx = 1.0, jzz = 1.0, jxz = 0.0;
	long_hidden = 0.0;
	for (int i = 0; i < 96; i++) {
		if (i >= long_count) break;
		vec4 w = long_waves[i];
		float k = length(w.xy);
		float wavelength = TAU / k;
		// A wave the local vertex spacing cannot carry is faded, never aliased.
		float resolved = envelope * (1.0 - smoothstep(wavelength * 0.25, wavelength * 0.5, cell));
		long_hidden += (1.0 - resolved) * 0.5 * w.z * w.z * k * k;
		float phase = dot(w.xy, q) + long_phases[i];
		float s = sin(phase), c = cos(phase);
		vec2 unit = w.xy / k;
		float a = w.z * resolved;
		float h = w.w * resolved;
		d += vec3(h * unit.x * c, a * s, h * unit.y * c);
		slope += a * c * w.xy;
		jxx -= h * s * unit.x * w.x;
		jzz -= h * s * unit.y * w.y;
		jxz -= h * s * unit.x * w.y;
	}
	float jacobian = jxx * jzz - jxz * jxz;
	long_surface = vec3(vec2(jzz * slope.x - jxz * slope.y, jxx * slope.y - jxz * slope.x) / max(jacobian, 0.1), jacobian);
	if (fft_enabled) {
		// Mip matched to the vertex spacing: unresolvable chop is filtered out
		// of the mesh (it still reaches every pixel through the normals).
		float lod0 = log2(max(cell * cascade_scale0 * fft_texels, 1.0));
		float lod1 = log2(max(cell * cascade_scale1 * fft_texels, 1.0));
		d += textureLod(fft_displacement, vec3((q - cascade_offset0) * cascade_scale0, 0.0), lod0).xyz * envelope;
		d += textureLod(fft_displacement, vec3((q - cascade_offset1) * cascade_scale1, 1.0), lod1).xyz * envelope;
	}
	if (wake_enabled) {
		vec2 uv = (q - wake_rect.xy) * wake_rect.z;
		if (uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0) {
			// Filtered to the vertex spacing, like the FFT cascades.
			float lod = log2(max(cell * wake_rect.z * float(textureSize(wake_map, 0).x), 1.0));
			d.y += textureLod(wake_map, vec3(uv, 0.0), lod).x * wake_fade(uv);
		}
	}
	p += d;
	ocean_fog = fog_enabled ? pow(clamp((length(p - CAMERA_POSITION_WORLD) - 250.0) / 2750.0, 0.0, 1.0), 1.5) : 0.0;
	world_position = p;
	VERTEX = (VIEW_MATRIX * vec4(p, 1)).xyz;
	NORMAL = (VIEW_MATRIX * vec4(0, 1, 0, 0)).xyz;
	POSITION = PROJECTION_MATRIX * vec4(VERTEX, 1);
}
