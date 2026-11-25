// Liquid Glass backdrop stage, HLSL (ADR-0052 stage 2, round 3): the box passes with the
// saturation, and the luminance probe, as Direct2D custom effects (Sources/CD2D/cd2d_glass.cpp)
// over the frame beneath the glass rendered on the window's own device. The same arithmetic
// as glass.metal's glass_box, glass_saturate and glass_luminance: every pass reads and
// writes whole bytes (point sampling; Direct2D's intermediates are 8-bit), so the box's
// truncating division is the software running sum's.
//
// The input lies in the frame's pixel space; the crop is (k[0].x, k[0].y) to
// (k[0].x + k[0].z, k[0].y + k[0].w). D2D hands the input's texture coordinate of this
// pixel's scene position (uv0.xy) and the size of one scene pixel in it (uv0.zw).

Texture2D InputTexture : register(t0);
SamplerState InputSampler : register(s0);

// k[0]: crop x, y, width, height (frame pixels); k[1]: box radius, horizontal (0/1),
// saturate after this pass (0/1), saturation.
cbuffer GlassBackdropConstants : register(b0) { float4 k[12]; };

float4 glass_texel(float2 index, float2 posScene, float4 uv0) {
    return round(InputTexture.SampleLevel(InputSampler, uv0.xy + (index + 0.5 - posScene) * uv0.zw, 0) * 255);
}

// One box pass (and the saturation when it is the last): bytes in, bytes out.
float4 box(float4 pos : SV_POSITION, float4 posScene : SCENE_POSITION, float4 uv0 : TEXCOORD0) : SV_Target {
    int r = (int)k[1].x;
    bool across = k[1].y > 0.5;
    float2 p = floor(posScene.xy);
    float lo = across ? k[0].x : k[0].y;
    float hi = lo + (across ? k[0].z : k[0].w) - 1;
    float4 sum = float4(0, 0, 0, 0);
    [loop] for (int i = -r; i <= r; i++) {
        float2 q = p;
        if (across) q.x = clamp(p.x + i, lo, hi); else q.y = clamp(p.y + i, lo, hi);
        sum += glass_texel(q, posScene.xy, uv0);
    }
    float4 c = floor(sum / (2 * r + 1));
    if (k[1].z > 0.5) {
        // rgba here: the software's b, g, r weights on blue, green, red.
        float l = 0.0722 * c.b + 0.7152 * c.g + 0.2126 * c.r;
        c.rgb = clamp(floor(float3(l, l, l) + (c.rgb - float3(l, l, l)) * k[1].w + 0.5), float3(0, 0, 0), float3(c.a, c.a, c.a));
    }
    return c / 255;
}

// The alpha-weighted mean luminance of the crop, as one pixel at the scene origin, alpha 1;
// transparent when nothing in the crop is covered. Direct2D's intermediates are 8-bit, and
// one byte (1/255) is enough to flip the variant of a backdrop near the threshold, so the mean
// is stored in two: red the whole steps of 1/255, green the fraction of a step (16 bits in all).
float4 luminance(float4 pos : SV_POSITION, float4 posScene : SCENE_POSITION, float4 uv0 : TEXCOORD0) : SV_Target {
    float sum = 0, weight = 0;
    int w = (int)k[0].z, h = (int)k[0].w;
    [loop] for (int y = 0; y < h; y++) {
        [loop] for (int x = 0; x < w; x++) {
            float4 c = glass_texel(float2(k[0].x + x, k[0].y + y), posScene.xy, uv0);
            if (c.a > 0) { sum += 0.0722 * c.b + 0.7152 * c.g + 0.2126 * c.r; weight += c.a; }
        }
    }
    if (weight <= 0) return float4(0, 0, 0, 0);
    float v = sum / weight * 255;
    float whole = floor(v);
    return float4(whole / 255, v - whole, 0, 1);
}
