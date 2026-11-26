// Liquid Glass program, Metal (ADR-0052 stage 2). Runs on the macOS host through the
// CGlassMetal shim. The same stages, with the same arithmetic, as the software pass in
// Platform/Material.swift and the GLSL (glass_*.comp) and HLSL (glass_lens.hlsl) programs.
// Pixels are premultiplied BGRA packed little-endian in a uint (b in the low byte).
// Compile with fast math off so the float steps match the software pass.

#include <metal_stdlib>
using namespace metal;

// Twelve float4 rows; PlatformGlassRequest.constants packs them.
struct GlassConstants {
    float4 size;      // output width, height; sample width, height
    float4 backdrop;  // backdrop origin x, y in output px; sample px per output px x, y
    float4 rect;      // shape rect minX, minY, maxX, maxY (output px)
    float4 shape;     // corner radius, bevel width, refraction, rim width
    float4 light;     // light direction x, y (unit); lift; bevelled (0/1)
    float4 tint;      // tint rgb, effective tint alpha (0: none)
    float4 veilLight; // light veil rgb, alpha
    float4 veilDark;  // dark veil rgb, alpha
    float4 lit;       // rim alpha, specular (light); rim alpha, specular (dark)
    float4 variant;   // 0 light, 1 dark, 2 adaptive; threshold; luminance (< 0: probed); saturation
    float4 blur;      // box radius per pass
    float4 reserved;
};

// One box pass: width, height, stride (in pixels), radius, horizontal.
struct GlassPass { uint width, height, stride, radius, horizontal, pad0, pad1, pad2; };

static inline uint4 glass_unpack(uint p) { return uint4(p & 0xffu, (p >> 8) & 0xffu, (p >> 16) & 0xffu, p >> 24); }
static inline uint glass_pack(uint4 c) { return c.x | (c.y << 8) | (c.z << 16) | (c.w << 24); }

// The software box pass exactly: the sum of 2r + 1 border-clamped bytes per channel,
// divided with truncation.
kernel void glass_box(device const uint *src [[buffer(0)]], device uint *dst [[buffer(1)]],
                      constant GlassPass &pass [[buffer(3)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= pass.width || gid.y >= pass.height) return;
    int r = int(pass.radius);
    int last = int(pass.horizontal != 0 ? pass.width : pass.height) - 1;
    int at = int(pass.horizontal != 0 ? gid.x : gid.y);
    uint4 sum = uint4(0);
    for (int k = -r; k <= r; k++) {
        int i = clamp(at + k, 0, last);
        uint idx = pass.horizontal != 0 ? gid.y * pass.stride + uint(i) : uint(i) * pass.stride + gid.x;
        sum += glass_unpack(src[idx]);
    }
    dst[gid.y * pass.stride + gid.x] = glass_pack(sum / uint(2 * r + 1));
}

// Saturation in place: every channel pulled from (above 1) the pixel's luminance.
kernel void glass_saturate(device uint *px [[buffer(1)]], constant GlassConstants &k [[buffer(2)]],
                           constant GlassPass &pass [[buffer(3)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= pass.width || gid.y >= pass.height) return;
    uint o = gid.y * pass.stride + gid.x;
    float4 c = float4(glass_unpack(px[o]));   // b, g, r, a
    float s = k.variant.w;
    float l = 0.0722 * c.x + 0.7152 * c.y + 0.2126 * c.z;
    float3 v = clamp(round(float3(l) + (c.xyz - float3(l)) * s), float3(0), float3(c.w));
    px[o] = glass_pack(uint4(uint3(v), uint(c.w)));
}

// The alpha-weighted mean luminance of the blurred sample, one threadgroup of 256.
kernel void glass_luminance(device const uint *px [[buffer(1)]], device float *out [[buffer(4)]],
                            constant GlassPass &pass [[buffer(3)]], uint tid [[thread_index_in_threadgroup]]) {
    threadgroup float sums[256];
    threadgroup float weights[256];
    float sum = 0, weight = 0;
    uint n = pass.width * pass.height;
    for (uint i = tid; i < n; i += 256) {
        uint4 c = glass_unpack(px[(i / pass.width) * pass.stride + (i % pass.width)]);
        if (c.w > 0) { sum += 0.0722 * float(c.x) + 0.7152 * float(c.y) + 0.2126 * float(c.z); weight += float(c.w); }
    }
    sums[tid] = sum; weights[tid] = weight;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint s = 128; s > 0; s >>= 1) {
        if (tid < s) { sums[tid] += sums[tid + s]; weights[tid] += weights[tid + s]; }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (tid == 0) out[0] = weights[0] > 0 ? sums[0] / weights[0] : -1.0;
}

// The rounded rectangle's signed distance (negative inside) and outward normal at p.
static inline float3 glass_field(float2 p, constant GlassConstants &k) {
    float radius = k.shape.x;
    float2 c = (k.rect.xy + k.rect.zw) * 0.5;
    float2 h = (k.rect.zw - k.rect.xy) * 0.5 - float2(radius);
    float2 dd = p - c;
    float2 q = abs(dd) - h;
    float2 o = max(q, float2(0));
    float outside = sqrt(o.x * o.x + o.y * o.y);
    float d = outside + min(max(q.x, q.y), 0.0) - radius;
    float2 n;
    if (outside > 1e-5) n = float2(o.x / outside * (dd.x < 0 ? -1.0 : 1.0), o.y / outside * (dd.y < 0 ? -1.0 : 1.0));
    else if (q.x > q.y) n = float2(dd.x < 0 ? -1.0 : 1.0, 0);
    else n = float2(0, dd.y < 0 ? -1.0 : 1.0);
    return float3(d, n);
}

// The software bilinear look-up: premultiplied b, g, r, a in 0...1, the border clamped.
static inline float4 glass_bilinear(device const uint *s, uint w, uint h, uint stride, float x, float y) {
    float cx = min(float(w - 1), max(0.0, x)), cy = min(float(h - 1), max(0.0, y));
    uint x0 = uint(cx), y0 = uint(cy);
    uint x1 = min(w - 1, x0 + 1), y1 = min(h - 1, y0 + 1);
    float fx = cx - float(x0), fy = cy - float(y0);
    float4 c00 = float4(glass_unpack(s[y0 * stride + x0])), c10 = float4(glass_unpack(s[y0 * stride + x1]));
    float4 c01 = float4(glass_unpack(s[y1 * stride + x0])), c11 = float4(glass_unpack(s[y1 * stride + x1]));
    return (c00 * ((1 - fx) * (1 - fy)) + c10 * (fx * (1 - fy)) + c01 * ((1 - fx) * fy) + c11 * (fx * fy)) * (1.0 / 255.0);
}

static inline uint glass_byte(float v) { return uint(min(255.0, max(0.0, round(v * 255.0)))); }

// The lens over the blurred backdrop: one thread per output pixel.
kernel void glass_lens(device const uint *src [[buffer(0)]], device uint *dst [[buffer(1)]],
                       constant GlassConstants &k [[buffer(2)]], constant GlassPass &pass [[buffer(3)]],
                       device const float *probe [[buffer(4)]], uint2 gid [[thread_position_in_grid]]) {
    uint W = uint(k.size.x), H = uint(k.size.y);
    if (gid.x >= W || gid.y >= H) return;
    float2 p = float2(gid) + 0.5;
    float3 f = glass_field(p, k);
    float d = f.x; float2 n = f.yz;
    if (d >= 0.5) { dst[gid.y * W + gid.x] = 0; return; }
    // The variant: the probed (or given) luminance against the threshold.
    float luminance = k.variant.z >= 0 ? k.variant.z : probe[0];
    bool dark = k.variant.x == 1 || (k.variant.x == 2 && (luminance < 0 ? 1.0 : luminance) < k.variant.y);
    float4 veil = dark ? k.veilDark : k.veilLight;
    float rimA = dark ? k.lit.z : k.lit.x, spec = dark ? k.lit.w : k.lit.y;
    float edge = k.shape.y, refraction = k.shape.z, rimW = k.shape.w;
    bool bevelled = k.light.w > 0;
    float cover = min(1.0, 0.5 - d);
    float t = bevelled ? min(1.0, max(0.0, 1 + d / edge)) : 0;
    float bend = refraction * t * t;
    p += n * bend;
    float facing = n.x * k.light.x + n.y * k.light.y;
    float4 c = glass_bilinear(src, pass.width, pass.height, pass.stride,
                              (p.x - k.backdrop.x) * k.backdrop.z - 0.5, (p.y - k.backdrop.y) * k.backdrop.w - 0.5);
    float a = c.w;
    float3 bgr = c.xyz;
    if (a > 0.001) bgr *= 1 / a;
    float3 rgb = bgr.zyx;
    rgb += (veil.rgb - rgb) * veil.a; a += (1 - a) * veil.a;
    if (k.tint.w > 0) { rgb += (k.tint.rgb - rgb) * k.tint.w; a += (1 - a) * k.tint.w; }
    if (rimA > 0) {
        float rim = min(1.0, max(0.0, 1 + d / rimW)) * rimA;
        if (facing > 0) rgb += (1 - rgb) * (rim * facing);
        else rgb *= 1 - rim * -facing * 0.45;
        a += (1 - a) * rim;
    }
    if (spec > 0 && facing > 0 && bevelled) {
        float reach = min(1.0, max(0.0, 1 + d / (2 * edge)));
        rgb += (1 - rgb) * (facing * facing * reach * reach * spec);
    }
    float lift = k.light.z;
    if (lift > 0) rgb += (1 - rgb) * lift;
    float outA = min(1.0, a) * cover;
    dst[gid.y * W + gid.x] = glass_pack(uint4(glass_byte(rgb.b * outA), glass_byte(rgb.g * outA), glass_byte(rgb.r * outA), glass_byte(outA)));
}
