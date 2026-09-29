#[compute]
#version 450
// Deep-water dispersion w = sqrt(g k) advances every mode analytically, then
// the spectra of eight real fields are packed pairwise into four complex
// planes (A + iB) so one inverse FFT per plane yields two real fields:
//   0: Dx + i Dz            horizontal (choppy) displacement
//   1: Y + i dDx/dx         height, Jacobian term
//   2: dY/dx + i dY/dz      height slopes
//   3: dDz/dz + i dDx/dz    Jacobian terms
// D = i k/|k| h sharpens crests (points move toward the nearest crest).
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict readonly buffer Initial { vec4 h0[]; };
layout(set = 0, binding = 1, std430) restrict writeonly buffer Planes { vec2 planes[]; };
layout(set = 0, binding = 2, std430) restrict readonly buffer Cascades { vec4 cascades[]; };

layout(push_constant, std430) uniform Params {
	float time;          // wrapped to the repeat period on the CPU
	float repeat_omega;  // 2 pi / repeat period: frequencies are quantised to it
	uint n;
	uint cascade_count;
} params;

const float G = 9.81;
const float PI = 3.14159265358979;

vec2 cmul(vec2 a, vec2 b) {
	return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

vec2 mul_i(vec2 z) {
	return vec2(-z.y, z.x);
}

void main() {
	uvec3 id = gl_GlobalInvocationID;
	if (id.x >= params.n || id.y >= params.n || id.z >= params.cascade_count) return;
	int half_n = int(params.n / 2u);
	ivec2 index = ivec2(id.xy) - ivec2(greaterThanEqual(ivec2(id.xy), ivec2(half_n))) * int(params.n);
	vec2 k = vec2(index) * (2.0 * PI / cascades[id.z].x);
	float kl = length(k);
	vec4 h = h0[(id.z * params.n + id.y) * params.n + id.x];
	// Quantised frequency: the whole field repeats exactly every period, so a
	// wrapped time keeps full float precision however long the game runs.
	float w = floor(sqrt(G * kl) / params.repeat_omega) * params.repeat_omega;
	float phase = w * params.time;
	vec2 e = vec2(cos(phase), sin(phase));
	vec2 ht = cmul(h.xy, vec2(e.x, -e.y)) + cmul(h.zw, e);
	vec2 unit = kl > 0.0 ? k / kl : vec2(0.0);
	vec2 dx = mul_i(ht) * unit.x;
	vec2 dz = mul_i(ht) * unit.y;
	vec2 dxx = -k.x * unit.x * ht;
	vec2 dzz = -k.y * unit.y * ht;
	vec2 dxz = -k.y * unit.x * ht;
	vec2 sx = mul_i(ht) * k.x;
	vec2 sz = mul_i(ht) * k.y;
	uint plane = params.n * params.n;
	uint base = id.z * 4u * plane + id.y * params.n + id.x;
	planes[base] = dx + mul_i(dz);
	planes[base + plane] = ht + mul_i(dxx);
	planes[base + 2u * plane] = sx + mul_i(sz);
	planes[base + 3u * plane] = dzz + mul_i(dxz);
}
