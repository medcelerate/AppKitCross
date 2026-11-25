// Liquid Glass lens, HLSL (ADR-0052 stage 2): the pixel shader of the Direct2D custom effect
// in Sources/CD2D/cd2d_glass.cpp, run on the window's own D2D device. The lens stage of
// glass.metal with the same arithmetic; the backdrop arrives already blurred and saturated
// (the backdrop stage runs on the CPU on Windows while the frame beneath the glass is a CPU
// bitmap, ADR-0052) and its luminance is in the constants. The input is the backdrop at the
// sample scale, laid in the effect's space at (0, 0); the output covers (0, 0, W, H) in
// output pixels. D2D hands the input's texture coordinate of this pixel's scene position
// (uv0.xy) and the size of one scene pixel in it (uv0.zw), so any point of the backdrop is
// uv0.xy + (q - posScene.xy) * uv0.zw.

Texture2D InputTexture : register(t0);
SamplerState InputSampler : register(s0);

// Twelve float4 rows, see glass.metal's GlassConstants.
cbuffer GlassConstants : register(b0) { float4 k[12]; };

float3 glass_field(float2 p) {
    float radius = k[3].x;
    float2 c = (k[2].xy + k[2].zw) * 0.5;
    float2 h = (k[2].zw - k[2].xy) * 0.5 - float2(radius, radius);
    float2 dd = p - c;
    float2 q = abs(dd) - h;
    float2 o = max(q, float2(0, 0));
    float outside = sqrt(o.x * o.x + o.y * o.y);
    float d = outside + min(max(q.x, q.y), 0.0) - radius;
    float2 n;
    if (outside > 1e-5) n = float2(o.x / outside * (dd.x < 0 ? -1.0 : 1.0), o.y / outside * (dd.y < 0 ? -1.0 : 1.0));
    else if (q.x > q.y) n = float2(dd.x < 0 ? -1.0 : 1.0, 0);
    else n = float2(0, dd.y < 0 ? -1.0 : 1.0);
    return float3(d, n);
}

float4 main(float4 pos : SV_POSITION, float4 posScene : SCENE_POSITION, float4 uv0 : TEXCOORD0) : SV_Target {
    float2 p = posScene.xy;
    float3 f = glass_field(p);
    float d = f.x; float2 n = f.yz;
    if (d >= 0.5) return float4(0, 0, 0, 0);
    float luminance = k[9].z;
    bool dark = k[9].x == 1 || (k[9].x == 2 && (luminance < 0 ? 1.0 : luminance) < k[9].y);
    float4 veil = dark ? k[7] : k[6];
    float rimA = dark ? k[8].z : k[8].x, spec = dark ? k[8].w : k[8].y;
    float edge = k[3].y, refraction = k[3].z, rimW = k[3].w;
    bool bevelled = k[4].w > 0;
    float cover = min(1.0, 0.5 - d);
    float t = bevelled ? min(1.0, max(0.0, 1 + d / edge)) : 0;
    float bend = refraction * t * t;
    float2 bent = p + n * bend;
    float facing = n.x * k[4].x + n.y * k[4].y;
    // The backdrop point in sample pixels, clamped to the border pixels' centres as the
    // software look-up clamps its indices; the sampler is bilinear.
    float2 q = (bent - k[1].xy) * k[1].zw;
    q = clamp(q, float2(0.5, 0.5), k[0].zw - float2(0.5, 0.5));
    float4 c = InputTexture.SampleLevel(InputSampler, uv0.xy + (q - posScene.xy) * uv0.zw, 0);
    float a = c.a;
    float3 rgb = c.rgb;
    if (a > 0.001) rgb *= 1 / a;
    rgb += (veil.rgb - rgb) * veil.a; a += (1 - a) * veil.a;
    if (k[5].w > 0) { rgb += (k[5].rgb - rgb) * k[5].w; a += (1 - a) * k[5].w; }
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
    float lift = k[4].z;
    if (lift > 0) rgb += (1 - rgb) * lift;
    float outA = min(1.0, a) * cover;
    return float4(saturate(rgb) * outA, outA);
}
