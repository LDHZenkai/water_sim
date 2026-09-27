#[compute]
#version 450
// One radix-2 Stockham FFT line per workgroup, entirely in shared memory.
// Rows then columns (two dispatches) give the 2D transform in place.
// direction = +1: inverse (synthesis, unnormalised); -1: forward.
layout(local_size_x = 128, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict buffer Planes { vec2 planes[]; };

layout(push_constant, std430) uniform Params {
	uint n;
	uint columns;
	float direction;
	uint pad;
} params;

const float PI = 3.14159265358979;
const uint MAX_N = 512u;

shared vec2 lines[2][MAX_N];

vec2 cmul(vec2 a, vec2 b) {
	return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

void main() {
	uint n = params.n;
	uint half_n = n / 2u;
	uint line = gl_WorkGroupID.x;
	uint base = gl_WorkGroupID.y * n * n;
	uint stride = params.columns == 1u ? n : 1u;
	uint start = base + (params.columns == 1u ? line : line * n);
	uint lane = gl_LocalInvocationID.x;
	for (uint i = lane; i < n; i += 128u) {
		lines[0][i] = planes[start + i * stride];
	}
	memoryBarrierShared();
	barrier();
	uint source = 0u;
	for (uint p = 1u; p < n; p <<= 1u) {
		for (uint i = lane; i < half_n; i += 128u) {
			uint k = i & (p - 1u);
			float angle = params.direction * PI * float(k) / float(p);
			vec2 u0 = lines[source][i];
			vec2 u1 = cmul(lines[source][i + half_n], vec2(cos(angle), sin(angle)));
			uint j = (i << 1u) - k;
			lines[1u - source][j] = u0 + u1;
			lines[1u - source][j + p] = u0 - u1;
		}
		memoryBarrierShared();
		barrier();
		source = 1u - source;
	}
	for (uint i = lane; i < n; i += 128u) {
		planes[start + i * stride] = lines[source][i];
	}
}
