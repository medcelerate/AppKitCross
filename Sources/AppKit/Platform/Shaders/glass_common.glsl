// Shared declarations of the Liquid Glass Vulkan compute shaders (ADR-0052 stage 2), the
// GLSL twin of glass.metal. Bindings follow the Metal-on-Vulkan binding model (ADR-0012):
// kernel-stage storage buffer slot N is set 1, binding N.

layout(std430, set = 1, binding = 0) readonly buffer Source { uint src[]; };
layout(std430, set = 1, binding = 1) buffer Destination { uint dst[]; };
// Twelve vec4 rows, see glass.metal's GlassConstants.
layout(std430, set = 1, binding = 2) readonly buffer Constants { vec4 k[12]; };
layout(std430, set = 1, binding = 3) readonly buffer Pass { uint width, height, stride, radius, horizontal, pad0, pad1, pad2; } pass;
layout(std430, set = 1, binding = 4) buffer Probe { float luminance[]; };

uvec4 glass_unpack(uint p) { return uvec4(p & 0xffu, (p >> 8) & 0xffu, (p >> 16) & 0xffu, p >> 24); }
uint glass_pack(uvec4 c) { return c.x | (c.y << 8) | (c.z << 16) | (c.w << 24); }
