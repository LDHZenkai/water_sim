#[compute]
#version 450
// Unpacks one cascade's synthesised planes into the textures the ocean shader
// samples, and advances persistent whitecap foam.
//   displacement: (Dx, Y, Dz, |slope|^2)   slope^2 keeps LEAN variance for mips
//   slopes:       (sx, sz, foam, J)        slopes of the displaced surface
// The Jacobian J of the horizontal map drops below 1 where the surface
// compresses and below 0 where it folds over: that is where waves break.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict readonly buffer Planes { vec2 planes[]; };
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D displacement;
layout(rgba16f, set = 0, binding = 2) uniform restrict image2D slopes;

layout(push_constant, std430) uniform Params {
	uint n;
	uint cascade;
	float choppiness;
	float dt;
	float foam_decay;      // e-folding time of the whitecap, s
	float foam_threshold;  // J below which the crest breaks
	float foam_gain;
	float pad;
} params;

void main() {
	uvec2 id = gl_GlobalInvocationID.xy;
	if (id.x >= params.n || id.y >= params.n) return;
	uint plane = params.n * params.n;
	uint base = params.cascade * 4u * plane + id.y * params.n + id.x;
	vec2 p0 = planes[base];
	vec2 p1 = planes[base + plane];
	vec2 p2 = planes[base + 2u * plane];
	vec2 p3 = planes[base + 3u * plane];
	float lambda = params.choppiness;
	float jxx = 1.0 + lambda * p1.y;
	float jzz = 1.0 + lambda * p3.x;
	float jxz = lambda * p3.y;
	float jacobian = jxx * jzz - jxz * jxz;
	// Normal of the displaced surface is cross(dP/dz, dP/dx); its horizontal
	// parts over its vertical part give the effective slopes.
	float vertical = max(jacobian, 0.1);
	vec2 slope = vec2(jzz * p2.x - jxz * p2.y, jxx * p2.y - jxz * p2.x) / vertical;
	imageStore(displacement, ivec2(id), vec4(lambda * p0.x, p1.x, lambda * p0.y, dot(slope, slope)));
	float foam = imageLoad(slopes, ivec2(id)).z;
	foam *= params.dt > 0.0 ? exp(-params.dt / params.foam_decay) : 1.0;
	float breaking = clamp((params.foam_threshold - jacobian) * params.foam_gain, 0.0, 1.0);
	foam = clamp(max(foam, breaking), 0.0, 1.0);
	imageStore(slopes, ivec2(id), vec4(slope, foam, jacobian));
}
