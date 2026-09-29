#[compute]
#version 450
// Initial Fourier amplitudes h0(k) for every FFT cascade, drawn from the same
// directional spectrum as sea_state.gd: fetch-limited JONSWAP wind sea with
// Donelan-Banner spreading plus a Gaussian-spread swell. Each cascade keeps
// only its band [k_low, k_high) so the cascades and the explicit long-wave
// components never double count energy.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict writeonly buffer Initial { vec4 h0[]; };
layout(set = 0, binding = 1, std430) restrict readonly buffer Cascades { vec4 cascades[]; }; // size, k_low, k_high, foam_decay

layout(push_constant, std430) uniform Params {
	float wind_alpha;
	float wind_peak;
	float wind_gamma;
	float wind_heading;
	float swell_alpha;
	float swell_peak;
	float swell_gamma;
	float swell_heading;
	float swell_spread;
	float split_k;
	float choppiness;
	float seed;
	uint n;
	uint cascade_count;
	float repeat_omega;
	float pad;
} params;

const float G = 9.81;
const float PI = 3.14159265358979;

float jonswap(float w, float peak, float alpha, float gamma) {
	if (w <= 0.0 || peak <= 0.0 || alpha <= 0.0) return 0.0;
	float sigma = w <= peak ? 0.07 : 0.09;
	float shape = exp(-(w - peak) * (w - peak) / (2.0 * sigma * sigma * peak * peak));
	float r = peak / w;
	float r4 = r * r * r * r;
	return alpha * G * G / (w * w * w * w * w) * exp(-1.25 * r4) * pow(gamma, shape);
}

float donelan_banner(float theta, float ratio) {
	float beta;
	if (ratio < 0.95) beta = 2.61 * pow(max(ratio, 0.56), 1.3);
	else if (ratio < 1.6) beta = 2.28 * pow(ratio, -1.3);
	else beta = pow(10.0, -0.4 + 0.8393 * exp(-0.567 * log(ratio * ratio)));
	float s = 1.0 / cosh(beta * theta);
	return beta / (2.0 * tanh(beta * PI)) * s * s;
}

float wrap_angle(float a) {
	return a - 2.0 * PI * floor((a + PI) / (2.0 * PI));
}

uint pcg(uint v) {
	uint state = v * 747796405u + 2891336453u;
	uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
	return (word >> 22u) ^ word;
}

// Complex standard normal pair from an integer mode address (Box-Muller).
vec2 gaussian(uvec3 id) {
	uint h = pcg(id.x + pcg(id.y + pcg(id.z + pcg(uint(params.seed)))));
	uint h2 = pcg(h ^ 0x9e3779b9u);
	float u1 = (float(h >> 8u) + 1.0) / 16777217.0;
	float u2 = float(h2 >> 8u) / 16777216.0;
	float r = sqrt(-2.0 * log(u1));
	return r * vec2(cos(2.0 * PI * u2), sin(2.0 * PI * u2));
}

// sqrt(E(k) dk^2): standard deviation of the mode's complex amplitude.
float mode_amplitude(ivec2 index, uint cascade) {
	vec4 c = cascades[cascade];
	float dk = 2.0 * PI / c.x;
	vec2 k = vec2(index) * dk;
	float kl = length(k);
	if (kl < c.y || kl >= c.z || kl <= 0.0) return 0.0;
	float w = sqrt(G * kl);
	float dw_dk = G / (2.0 * w);
	float theta = atan(k.y, k.x);
	float wind = jonswap(w, params.wind_peak, params.wind_alpha, params.wind_gamma) * donelan_banner(wrap_angle(theta - params.wind_heading), w / params.wind_peak);
	float swell_theta = wrap_angle(theta - params.swell_heading);
	float spread = max(params.swell_spread, 0.01);
	float swell = jonswap(w, params.swell_peak, params.swell_alpha, params.swell_gamma) * exp(-swell_theta * swell_theta / (2.0 * spread * spread)) / (sqrt(2.0 * PI) * spread);
	float density = (wind + swell) * dw_dk / kl;
	return sqrt(density) * dk;
}

ivec2 signed_index(uvec2 id) {
	int half_n = int(params.n / 2u);
	return ivec2(id) - ivec2(greaterThanEqual(ivec2(id), ivec2(half_n))) * int(params.n);
}

void main() {
	uvec3 id = gl_GlobalInvocationID;
	if (id.x >= params.n || id.y >= params.n || id.z >= params.cascade_count) return;
	uvec2 mirror = (uvec2(params.n) - id.xy) % params.n;
	ivec2 index = signed_index(id.xy);
	ivec2 mirrored = signed_index(mirror);
	// Variance of the synthesised field is sum 2|h0|^2 = sum E dk^2, hence 1/2.
	vec2 a = 0.5 * gaussian(id) * mode_amplitude(index, id.z);
	vec2 b = 0.5 * gaussian(uvec3(mirror, id.z)) * mode_amplitude(mirrored, id.z);
	h0[(id.z * params.n + id.y) * params.n + id.x] = vec4(a, b.x, -b.y);
}
