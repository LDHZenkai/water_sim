#[compute]
#version 450
// Reactive wave simulation, step 1 of 3 (spatial): hull and splash forcing.
// State z = (eta, phi): surface height and velocity potential of the
// disturbance. The hull is a Havelock pressure patch: its hydrostatic head P
// is the draft below the incident waves, entering Bernoulli as
// d(phi)/dt = -g (eta + P). The kick uses the mean of the previous and new
// head, i.e. Strang splitting (half kick after one propagation, half before
// the next), so a resting hull sits in its own still depression while heave,
// pitch, roll, chop along the hull and any current past it radiate real waves
// (with a current: a Kelvin wake).
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict readonly buffer State { vec2 state[]; };
layout(set = 0, binding = 1, std430) restrict writeonly buffer Forced { vec2 forced[]; };
layout(set = 0, binding = 2, std430) restrict buffer Pressure { vec2 pressure[]; }; // (P, dP/dt)
layout(set = 0, binding = 3, std430) restrict readonly buffer Step {
	mat4 world_to_ship;
	mat4 ship_to_world;
	vec4 domain;    // corner x, corner z, texel size, n
	vec4 flow;      // current x, current z, dt, 2 = first step
	ivec4 counts;   // shift x, shift z, impulses, long waves
	vec4 chop;      // cascade 0 scale, offset x, offset z, fft enabled
	vec4 chop1;     // cascade 1 scale, offset x, offset z, unused
	vec4 impulses[16];   // world x, world z, radius, depth
	vec4 long_waves[96]; // kx, kz, amplitude, horizontal amplitude
	vec4 long_phases[24];
} params;
layout(set = 0, binding = 4) uniform sampler2D keel;
layout(set = 0, binding = 5) uniform sampler2DArray chop_map;

const float SPONGE = 0.12;
const float G = 9.81;
// Head per metre of draft. A full hydrostatic patch over-predicts wave making
// (thin-ship theory drives waves by the hull's slopes, not its whole draft)
// and lets the covered surface ring freely, which a rigid hull cannot; so the
// head is scaled and the potential under the hull is damped. Calibrated so a
// ~30 m hull at Froude 0.18 makes stern waves of a few tens of centimetres.
const float COUPLING = 0.3;
const float HULL_DAMPING = 2.5;

float incident_height(vec2 q) {
	float height = 0.0;
	for (int i = 0; i < params.counts.w; i++) {
		vec4 w = params.long_waves[i];
		height += w.z * sin(dot(w.xy, q) + params.long_phases[i / 4][i % 4]);
	}
	if (params.chop.w > 0.5) {
		height += textureLod(chop_map, vec3((q - params.chop.yz) * params.chop.x, 0.0), 2.0).y;
		height += textureLod(chop_map, vec3((q - params.chop1.yz) * params.chop1.x, 1.0), 1.0).y;
	}
	return height;
}

void main() {
	uvec2 id = gl_GlobalInvocationID.xy;
	uint n = uint(params.domain.w);
	if (id.x >= n || id.y >= n) return;
	uint index = id.y * n + id.x;
	// The domain follows the ship in whole texels; carry the field with it.
	ivec2 source = ivec2(id) + params.counts.xy;
	bool inside = all(greaterThanEqual(source, ivec2(0))) && all(lessThan(source, ivec2(n)));
	uint from = uint(source.y) * n + uint(source.x);
	vec2 z = inside ? state[from] : vec2(0.0);
	float previous = inside ? pressure[from].x : 0.0;
	vec2 world = params.domain.xy + (vec2(id) + 0.5) * params.domain.z;
	float draft = 0.0;
	vec3 local = (params.world_to_ship * vec4(world.x, 0.0, world.y, 1.0)).xyz;
	if (local.x > -16.0 && local.x < 23.0 && abs(local.z) < 6.0) {
		float ambient = incident_height(world);
		local = (params.world_to_ship * vec4(world.x, ambient, world.y, 1.0)).xyz;
		float bottom = textureLod(keel, vec2((local.x + 16.0) / 39.0, (local.z + 6.0) / 12.0), 0.0).r;
		if (bottom < 50.0) {
			float bottom_world = (params.ship_to_world * vec4(local.x, bottom, local.z, 1.0)).y;
			draft = max(ambient - bottom_world, 0.0);
		}
	}
	float head = COUPLING * draft;
	if (params.flow.w > 1.5) {
		// First step: start exactly on the discrete equilibrium of
		// kick-then-propagate, (eta, phi) = (-P, g P dt / 2): no startup ring.
		z = vec2(-head, 0.5 * G * head * params.flow.z);
		previous = head;
	}
	for (int i = 0; i < params.counts.z; i++) {
		vec4 impulse = params.impulses[i];
		vec2 offset = world - impulse.xy;
		z.x -= impulse.w * exp(-dot(offset, offset) / (impulse.z * impulse.z));
	}
	z.y -= 0.5 * G * (head + previous) * params.flow.z;
	// Covered surface cannot slosh: bleed the potential under the hull toward
	// its equilibrium value (never toward zero, which would itself radiate).
	float rest = -0.5 * G * head * params.flow.z;
	float covered = smoothstep(0.02, 0.3, head);
	z.y = rest + (z.y - rest) * exp(-HULL_DAMPING * covered * params.flow.z);
	// Sponge: the domain's edge absorbs outgoing waves instead of wrapping.
	vec2 uv = (vec2(id) + 0.5) / float(n);
	float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float absorb = 1.0 - smoothstep(0.0, SPONGE, edge);
	z *= exp(-4.0 * absorb * absorb * params.flow.z);
	forced[index] = z;
	pressure[index] = vec2(head, (head - previous) / max(params.flow.z, 1e-4));
}
