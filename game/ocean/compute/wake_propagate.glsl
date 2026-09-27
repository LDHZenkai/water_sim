#[compute]
#version 450
// Reactive wave simulation, step 2 of 3 (spectral): exact linear deep-water
// propagation (Tessendorf's eWave). The complex field z = eta + i phi is
// split into the Hermitian spectra of eta and phi, and each mode rotates at
// w = sqrt(g k): d(eta)/dt = k phi, d(phi)/dt = -g eta. Any time step is
// stable and every wavelength travels at its true (dispersive) speed, so a
// moving hull draws a correct Kelvin wake. A current advects the whole field
// by a phase shift.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict readonly buffer Source { vec2 source[]; };
layout(set = 0, binding = 1, std430) restrict writeonly buffer Target { vec2 target[]; };

layout(push_constant, std430) uniform Params {
	uint n;
	float size;
	float dt;
	float viscosity;
	vec2 current;
	vec2 pad;
} params;

const float G = 9.81;
const float PI = 3.14159265358979;

vec2 cmul(vec2 a, vec2 b) {
	return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

vec2 conj(vec2 a) {
	return vec2(a.x, -a.y);
}

void main() {
	uvec2 id = gl_GlobalInvocationID.xy;
	uint n = params.n;
	if (id.x >= n || id.y >= n) return;
	uvec2 mirror = (uvec2(n) - id) % n;
	vec2 z = source[id.y * n + id.x];
	vec2 zm = conj(source[mirror.y * n + mirror.x]);
	vec2 eta = 0.5 * (z + zm);
	vec2 difference = 0.5 * (z - zm);
	vec2 phi = vec2(difference.y, -difference.x); // (z - conj z(-k)) / 2i
	int half_n = int(n / 2u);
	ivec2 index = ivec2(id) - ivec2(greaterThanEqual(ivec2(id), ivec2(half_n))) * int(n);
	vec2 k = vec2(index) * (2.0 * PI / params.size);
	float kl = length(k);
	vec2 result = vec2(0.0);
	if (kl > 0.0) {
		float w = sqrt(G * kl);
		float c = cos(w * params.dt);
		float s = sin(w * params.dt);
		vec2 eta_next = eta * c + phi * (w / G * s);
		vec2 phi_next = phi * c - eta * (G / w * s);
		float angle = -dot(k, params.current) * params.dt;
		vec2 shift = vec2(cos(angle), sin(angle)) * exp(-params.viscosity * kl * kl * params.dt);
		eta_next = cmul(eta_next, shift);
		phi_next = cmul(phi_next, shift);
		result = eta_next + vec2(-phi_next.y, phi_next.x);
	}
	target[id.y * n + id.x] = result / float(n * n);
}
