#[compute]
#version 450
// Reactive wave simulation, step 3 of 3 (spatial): shader outputs and foam.
// Layer 0: (height, dh/dx, dh/dz, foam)   layer 1: (u, w, P, phi)
// Height is eta + P: the hull's own static depression is hidden inside the
// hull, so only the waves it makes reach the rendered surface.
// Foam is carried by the surface flow (current + grad phi) semi-Lagrangian,
// decays, and is born only where the water is really churned: flow piling
// onto the bow, flow separating behind the stern, the hull slamming
// (fast change of its head at the waterline), and over-steep radiated crests.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict readonly buffer State { vec2 state[]; };
layout(set = 0, binding = 1, std430) restrict readonly buffer Pressure { vec2 pressure[]; };
layout(r32f, set = 0, binding = 2) uniform restrict readonly image2D foam_in;
layout(r32f, set = 0, binding = 3) uniform restrict writeonly image2D foam_out;
layout(rgba16f, set = 0, binding = 4) uniform restrict writeonly image2D surface;
layout(rgba16f, set = 0, binding = 5) uniform restrict writeonly image2D flow;

layout(push_constant, std430) uniform Params {
	uint n;
	float texel;
	float dt;
	float foam_decay;
	vec2 current;
	ivec2 shift;
} params;

float head_at(ivec2 p) {
	p = clamp(p, ivec2(0), ivec2(params.n - 1u));
	return pressure[uint(p.y) * params.n + uint(p.x)].x;
}

vec2 at(ivec2 p) {
	p = clamp(p, ivec2(0), ivec2(params.n - 1u));
	uint i = uint(p.y) * params.n + uint(p.x);
	// Displayed height relative to the hull's static depression.
	return state[i] + vec2(pressure[i].x, 0.0);
}

float foam_at(vec2 p) {
	vec2 f = p - 0.5;
	ivec2 i = ivec2(floor(f));
	vec2 t = f - vec2(i);
	ivec2 top = ivec2(params.n - 1u);
	float a = imageLoad(foam_in, clamp(i, ivec2(0), top)).r;
	float b = imageLoad(foam_in, clamp(i + ivec2(1, 0), ivec2(0), top)).r;
	float c = imageLoad(foam_in, clamp(i + ivec2(0, 1), ivec2(0), top)).r;
	float d = imageLoad(foam_in, clamp(i + ivec2(1, 1), ivec2(0), top)).r;
	return mix(mix(a, b, t.x), mix(c, d, t.x), t.y);
}

void main() {
	ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	if (id.x >= int(params.n) || id.y >= int(params.n)) return;
	vec2 z = at(id);
	vec2 px = at(id + ivec2(1, 0)), nx = at(id - ivec2(1, 0));
	vec2 pz = at(id + ivec2(0, 1)), nz = at(id - ivec2(0, 1));
	float inv = 0.5 / params.texel;
	vec2 gradient = vec2(px.x - nx.x, pz.x - nz.x) * inv;
	vec2 velocity = vec2(px.y - nx.y, pz.y - nz.y) * inv + params.current;
	uint index = uint(id.y) * params.n + uint(id.x);
	vec2 p = pressure[index];
	// Advect along the flow; the domain shift (whole texels) is folded in.
	vec2 departure = vec2(id) + 0.5 + vec2(params.shift) - velocity * params.dt / params.texel;
	float foam = foam_at(departure) * exp(-params.dt / params.foam_decay);
	// Thin band where the hull meets the water.
	float band = p.x > 0.0 ? 1.0 - smoothstep(0.05, 0.4, p.x) : 0.0;
	vec2 head_gradient = vec2(head_at(id + ivec2(1, 0)) - head_at(id - ivec2(1, 0)), head_at(id + ivec2(0, 1)) - head_at(id - ivec2(0, 1))) * inv;
	// Water meeting a rising hull (bow) or leaving a falling one (stern), m/s.
	float along = dot(params.current, head_gradient);
	float impact = clamp((along - 0.15) * 1.5, 0.0, 0.9);
	// Separation only at the trailing edge: water about to leave the hull.
	vec2 downstream = length(params.current) > 0.01 ? normalize(params.current) : vec2(0.0);
	float leaving = head_at(id + ivec2(round(downstream * 2.0))) <= 0.0 ? 1.0 : 0.0;
	float separation = leaving * clamp((-along - 0.15) * 0.8, 0.0, 0.7);
	float slam = 0.8 * smoothstep(0.25, 0.8, abs(p.y));
	float churn = band * max(max(impact, separation), slam);
	float steep = clamp((length(gradient) - 0.5) * 2.0, 0.0, 0.7);
	foam = clamp(max(foam, max(churn, steep)), 0.0, 1.0);
	imageStore(foam_out, id, vec4(foam));
	imageStore(surface, id, vec4(z.x, gradient, foam));
	imageStore(flow, id, vec4(velocity, p.x, z.y));
}
