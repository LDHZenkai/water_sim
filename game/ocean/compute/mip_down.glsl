#[compute]
#version 450
// 2x2 box reduction of one mip level into the next. Averaging slopes and
// slope^2 separately is what lets the shader recover the variance hidden by
// filtering (LEAN mapping) and widen the sun glitter correctly with distance.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D source_a;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D target_a;
layout(rgba16f, set = 0, binding = 2) uniform restrict readonly image2D source_b;
layout(rgba16f, set = 0, binding = 3) uniform restrict writeonly image2D target_b;

void main() {
	ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(id, imageSize(target_a)))) return;
	ivec2 s = id * 2;
	imageStore(target_a, id, 0.25 * (imageLoad(source_a, s) + imageLoad(source_a, s + ivec2(1, 0)) + imageLoad(source_a, s + ivec2(0, 1)) + imageLoad(source_a, s + ivec2(1, 1))));
	imageStore(target_b, id, 0.25 * (imageLoad(source_b, s) + imageLoad(source_b, s + ivec2(1, 0)) + imageLoad(source_b, s + ivec2(0, 1)) + imageLoad(source_b, s + ivec2(1, 1))));
}
