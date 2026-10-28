// MSL → HLSL translation (ADR-0006): pure Swift, so the macOS host build covers it.

import XCTest
@testable import AppKit
@testable import Metal

/// HelloWindow's hand-written HLSL triangle (`MetalDemoViewController.shaderSource`; keep in sync).
enum MetalDemoShaders {
    static let hlsl = """
    cbuffer Frame { float2 scale; float angle; float padding; };
    struct VSIn { float2 position : ATTRIBUTE0; float4 color : ATTRIBUTE1; };
    struct VSOut { float4 position : SV_Position; float4 color : COLOR0; };
    VSOut triangleVertex(VSIn v) {
        float s = sin(angle), c = cos(angle);
        float2 p = float2(v.position.x * c - v.position.y * s, v.position.x * s + v.position.y * c) * scale;
        VSOut o;
        o.position = float4(p, 0, 1);
        o.color = v.color;
        return o;
    }
    float4 triangleFragment(VSOut i) : SV_Target { return i.color; }
    """
}

/// Drops all whitespace so comparisons ignore layout.
private func squash(_ s: String) -> String { s.filter { !$0.isWhitespace } }

private func translate(_ msl: String, file: StaticString = #filePath, line: UInt = #line) throws -> MSLTranslation {
    do { return try MSLTranslator.translate(msl) } catch let e as MSLTranslationError { XCTFail("translation failed: \(e)", file: file, line: line); throw e }
}

final class MSLTranslatorTests: XCTestCase, @unchecked Sendable {
    /// HelloWindow's triangle in MSL (the HLSL original is `MetalDemoViewController.shaderSource`).
    static let triangleMSL = """
    #include <metal_stdlib>
    using namespace metal;

    struct Frame { float2 scale; float angle; float padding; };
    struct VertexIn { float2 position [[attribute(0)]]; float4 color [[attribute(1)]]; };
    struct VertexOut { float4 position [[position]]; float4 color; };

    vertex VertexOut triangleVertex(VertexIn v [[stage_in]], constant Frame& frame [[buffer(0)]]) {
        float s = sin(frame.angle), c = cos(frame.angle);
        float2 p = float2(v.position.x * c - v.position.y * s, v.position.x * s + v.position.y * c) * frame.scale;
        VertexOut o;
        o.position = float4(p, 0, 1);
        o.color = v.color;
        return o;
    }

    fragment float4 triangleFragment(VertexOut i [[stage_in]]) { return i.color; }
    """

    func testTriangleMatchesHelloWindowHLSL() throws {
        let t = try translate(Self.triangleMSL)
        let expected = """
        #pragma pack_matrix(column_major)
        struct Frame { float2 scale; float angle; float padding; };
        struct VertexIn { float2 position : ATTRIBUTE0; float4 color : ATTRIBUTE1; };
        struct VertexOut { float4 position : SV_Position; float4 color : TEXCOORD0; };
        ConstantBuffer<Frame> frame : register(b0);
        VertexOut triangleVertex(VertexIn v) {
            float s = sin(frame.angle), c = cos(frame.angle);
            float2 p = float2(v.position.x * c - v.position.y * s, v.position.x * s + v.position.y * c) * frame.scale;
            VertexOut o;
            o.position = float4(p, 0, 1);
            o.color = v.color;
            return o;
        }
        float4 triangleFragment(VertexOut i) : SV_Target0 { return i.color; }
        """
        let body = t.hlsl.split(separator: "\n").filter { !$0.hasPrefix("//") }.joined(separator: "\n")
        XCTAssertEqual(squash(body), squash(expected), "\n\(t.hlsl)")
        XCTAssertEqual(t.functionNames, ["triangleVertex", "triangleFragment"])
        XCTAssertEqual(t.function(named: "triangleVertex")?.type, .vertex)
        XCTAssertEqual(t.function(named: "triangleFragment")?.type, .fragment)
        XCTAssertEqual(t.function(named: "triangleFragment")?.entryPoint, "triangleFragment")
        // Structurally the same as the hand-written HLSL: same semantics and bindings.
        let original = MetalDemoShaders.hlsl
        for marker in ["ATTRIBUTE0", "ATTRIBUTE1", "SV_Position", "SV_Target", "float2(v.position.x * c - v.position.y * s, v.position.x * s + v.position.y * c)"] {
            XCTAssertTrue(original.contains(marker) && t.hlsl.contains(marker), marker)
        }
    }

    func testUniformBufferTexturesAndSamplers() throws {
        let msl = """
        #include <metal_stdlib>
        using namespace metal;
        struct Uniforms { float4x4 mvp; float4 tint; };
        struct VIn { float3 position [[attribute(0)]]; float2 uv [[attribute(1)]]; };
        struct VOut { float4 position [[position]]; float2 uv [[user(texcoord)]]; float pointSize [[point_size]]; };
        vertex VOut vmain(VIn in [[stage_in]], constant Uniforms& u [[buffer(1)]], uint vid [[vertex_id]], uint iid [[instance_id]]) {
            VOut out;
            out.position = u.mvp * float4(in.position, 1.0);
            out.uv = in.uv;
            out.pointSize = 1.0;
            return out;
        }
        fragment half4 fmain(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]], sampler smp [[sampler(2)]], constant float4& tint [[buffer(3)]]) {
            float4 c = tex.sample(smp, in.uv) * tint;
            if (c.a < 0.5h) discard_fragment();
            return half4(c);
        }
        """
        let t = try translate(msl)
        let h = t.hlsl
        XCTAssertTrue(h.contains("struct VIn {\n    float3 position : ATTRIBUTE0;\n    float2 uv : ATTRIBUTE1;\n};"), h)
        XCTAssertTrue(h.contains("float2 uv : TEXCOORD0;"), h)
        XCTAssertTrue(h.contains("float pointSize : PSIZE;"), h)
        XCTAssertTrue(h.contains("ConstantBuffer<Uniforms> u : register(b1);"), h)
        XCTAssertTrue(h.contains("cbuffer __cb_tint : register(b3) { float4 tint; };"), h)
        XCTAssertTrue(h.contains("Texture2D<float4> tex : register(t0);"), h)
        XCTAssertTrue(h.contains("SamplerState smp : register(s2);"), h)
        XCTAssertTrue(h.contains("VOut vmain(VIn in_, uint vid : SV_VertexID, uint iid : SV_InstanceID)"), h)
        XCTAssertTrue(squash(h).contains(squash("out_.position = mul(u.mvp, float4(in_.position, 1.0));")), h)
        XCTAssertTrue(h.contains("float4 fmain(VOut in_) : SV_Target0"), h)
        XCTAssertTrue(squash(h).contains(squash("float4 c = tex.Sample(smp, in_.uv) * tint;")), h)
        XCTAssertTrue(squash(h).contains(squash("if (c.a < 0.5) discard;")), h)
        XCTAssertTrue(squash(h).contains(squash("return ((float4)(c));")), h)
        XCTAssertEqual(t.function(named: "fmain")?.usesBufferTables, false)
    }

    func testComputeKernel() throws {
        let msl = """
        #include <metal_stdlib>
        using namespace metal;
        struct Params { uint count; float scale; };
        kernel void scaleValues(device float* values [[buffer(0)]], constant Params& p [[buffer(1)]], const device float* weights [[buffer(2)]],
                                uint id [[thread_position_in_grid]], uint lid [[thread_index_in_threadgroup]]) {
            threadgroup float cache[64];
            if (id >= p.count) return;
            cache[lid] = weights[id];
            threadgroup_barrier(mem_flags::mem_threadgroup);
            values[id] = values[id] * p.scale + cache[lid];
        }
        [[threads_per_threadgroup(8, 8, 1)]] kernel void fill(texture2d<float, access::write> out [[texture(0)]], texture2d<float> in [[texture(1)]], uint2 gid [[thread_position_in_grid]]) {
            if (gid.x >= out.get_width() || gid.y >= out.get_height()) return;
            float4 c = in.read(gid);
            out.write(c * 2.0, gid);
        }
        """
        let t = try translate(msl)
        let h = t.hlsl
        XCTAssertTrue(h.contains("RWStructuredBuffer<float> values : register(u0, space1);"), h)
        XCTAssertTrue(h.contains("ConstantBuffer<Params> p : register(b1);"), h)
        XCTAssertTrue(h.contains("StructuredBuffer<float> weights : register(t2, space1);"), h)
        XCTAssertTrue(h.contains("groupshared float cache[64];"), h)
        XCTAssertTrue(h.contains("[numthreads(64, 1, 1)]\nvoid scaleValues(uint id : SV_DispatchThreadID, uint lid : SV_GroupIndex)"), h)
        XCTAssertTrue(h.contains("GroupMemoryBarrierWithGroupSync();"), h)
        XCTAssertTrue(h.contains("[numthreads(8, 8, 1)]\nvoid fill(uint2 gid : SV_DispatchThreadID)"), h)
        XCTAssertTrue(h.contains("RWTexture2D<float4> out_ : register(u0);"), h)
        XCTAssertTrue(h.contains("Texture2D<float4> in_ : register(t1);"), h)
        XCTAssertTrue(squash(h).contains(squash("__msl_get_width_RWTexture2D_float4(out_)")), h)
        XCTAssertTrue(squash(h).contains(squash("float4 c = in_.Load(int3(gid, 0));")), h)
        XCTAssertTrue(squash(h).contains(squash("out_[gid] = c * 2.0;")), h)
        XCTAssertEqual(t.function(named: "scaleValues")?.threadgroupSize.map { [$0.0, $0.1, $0.2] }, [64, 1, 1])
        XCTAssertEqual(t.function(named: "fill")?.threadgroupSize.map { [$0.0, $0.1, $0.2] }, [8, 8, 1])
        XCTAssertEqual(t.function(named: "scaleValues")?.usesBufferTables, true)
        XCTAssertEqual(t.function(named: "fill")?.usesBufferTables, false)
    }

    func testIntrinsicRenames() throws {
        let msl = """
        #include <metal_stdlib>
        using namespace metal;
        fragment float4 f(float4 p [[position]]) {
            float a = fract(p.x) + mix(0.0, 1.0, p.y) + dfdx(p.x) + dfdy(p.y) + fma(p.x, p.y, 1.0) + rsqrt(p.x) + fmod(p.x, 2.0) + atan2(p.y, p.x);
            float b = select(1.0, 2.0, p.x > 0.5) + fast::sin(p.x) + metal::abs(p.y) + M_PI_F;
            float3 c = float3(a) + float3(b, 1, 2);
            uint bits = as_type<uint>(a) + popcount(7u);
            return float4(c, b + float(bits));
        }
        """
        let t = try translate(msl)
        let h = squash(t.hlsl)
        XCTAssertTrue(h.contains(squash("float a = frac(p.x) + lerp(0.0, 1.0, p.y) + ddx(p.x) + ddy(p.y) + mad(p.x, p.y, 1.0) + rsqrt(p.x) + fmod(p.x, 2.0) + atan2(p.y, p.x);")), t.hlsl)
        XCTAssertTrue(h.contains(squash("float b = ((p.x > 0.5) ? (2.0) : (1.0)) + sin(p.x) + abs(p.y) + 3.14159265358979323846f;")), t.hlsl)
        XCTAssertTrue(h.contains(squash("float3 c = ((float3)(a)) + float3(b, 1, 2);")), t.hlsl)
        XCTAssertTrue(h.contains(squash("uint bits = asuint(a) + countbits(7u);")), t.hlsl)
        XCTAssertTrue(t.hlsl.contains("float4 f(float4 p : SV_Position) : SV_Target0"), t.hlsl)
    }

    func testMatrixConvention() throws {
        let msl = """
        #include <metal_stdlib>
        using namespace metal;
        struct U { float4x4 model; float4x4 view; float3x3 normalMatrix; float2x3 oddShape; };
        vertex float4 v(constant U& u [[buffer(0)]], uint vid [[vertex_id]]) {
            float4 pos = float4(float(vid), 0, 0, 1);
            float4 world = u.model * pos;
            float4 clip = u.view * u.model * pos;
            float4 rowVec = pos * u.model;
            float3 n = u.normalMatrix * pos.xyz;
            float3x3 upper = float3x3(u.model);
            float4x4 identity = float4x4(1.0);
            float2x2 rot = float2x2(float2(0, 1), float2(-1, 0));
            float4 column0 = u.model[0];
            float2 scaled = rot * pos.xy * 2.0;
            return world + clip + rowVec + float4(n, 0) + float4(upper[0], 0) + identity[1] + float4(scaled, 0, 0) + column0;
        }
        """
        let t = try translate(msl)
        let h = squash(t.hlsl)
        XCTAssertTrue(t.hlsl.contains("#pragma pack_matrix(column_major)"))
        XCTAssertTrue(t.hlsl.contains("float3x2 oddShape;"), t.hlsl)
        XCTAssertTrue(h.contains(squash("float4 world = mul(u.model, pos);")), t.hlsl)
        XCTAssertTrue(h.contains(squash("float4 clip = mul(mul(u.view, u.model), pos);")), t.hlsl)
        XCTAssertTrue(h.contains(squash("float4 rowVec = mul(pos, u.model);")), t.hlsl)
        XCTAssertTrue(h.contains(squash("float3 n = mul(u.normalMatrix, pos.xyz);")), t.hlsl)
        XCTAssertTrue(h.contains(squash("float3x3 upper = ((float3x3)(u.model));")), t.hlsl)
        XCTAssertTrue(h.contains(squash("float4x4 identity = __msl_diag_float4x4(1.0);")), t.hlsl)
        XCTAssertTrue(h.contains(squash("float2x2 rot = transpose(float2x2(float2(0, 1), float2(-1, 0)));")), t.hlsl)
        XCTAssertTrue(h.contains(squash("float4 column0 = transpose(u.model)[0];")), t.hlsl)
        XCTAssertTrue(h.contains(squash("float2 scaled = mul(rot, pos.xy) * 2.0;")), t.hlsl)
        XCTAssertTrue(h.contains(squash("float4(transpose(upper)[0], 0) + transpose(identity)[1]")), t.hlsl)
        XCTAssertTrue(t.hlsl.contains("float4x4 __msl_diag_float4x4(float s) { return float4x4(s, 0, 0, 0, 0, s, 0, 0, 0, 0, s, 0, 0, 0, 0, s); }"), t.hlsl)
    }

    func testUnsupportedConstructsReportTheLine() {
        func line(of msl: String) -> Int? {
            do { _ = try MSLTranslator.translate(msl); XCTFail("accepted: \(msl)"); return nil }
            catch let e as MSLTranslationError { return e.line }
            catch { XCTFail("\(error)"); return nil }
        }
        XCTAssertEqual(line(of: "#include <metal_stdlib>\nusing namespace metal;\n\nkernel void k(device atomic_uint* counter [[buffer(0)]]) {}"), 4)
        XCTAssertEqual(line(of: "#include <metal_stdlib>\nusing namespace metal;\ntemplate <typename T> T twice(T x) { return x * 2; }"), 3)
        XCTAssertEqual(line(of: "#include <metal_stdlib>\nusing namespace metal;\nconstant bool flag [[function_constant(0)]];\nvertex float4 v() { return float4(0); }"), 3)
        XCTAssertEqual(line(of: "#include <metal_stdlib>\nusing namespace metal;\nvertex float4 v(float4 x) { return x; }"), 3)
        XCTAssertEqual(line(of: "#include <metal_stdlib>\nusing namespace metal;\nvertex float4 v(uint id [[vertex_id]]) {\n    float x = 1;\n    thread float* p = &x;\n    return float4(*p);\n}"), 5)
        XCTAssertEqual(line(of: "#include <foo.h>\nvertex float4 v() { return float4(0); }"), 1)
        XCTAssertEqual(line(of: "#include <metal_stdlib>\nusing namespace metal;\nfragment float4 f(float2 uv [[point_coord]]) { return float4(uv, 0, 1); }"), 3)
        let err = XCTAssertThrowsErrorOfType("#include <metal_stdlib>\nusing namespace metal;\nvertex float4 v(uint id [[vertex_id]]) {\n  float4x4 m = float4x4(unknownValue(id));\n  return m[0];\n}")
        XCTAssertEqual(err?.line, 4)
        XCTAssertTrue(err?.message.contains("matrix constructor") ?? false)
    }

    private func XCTAssertThrowsErrorOfType(_ msl: String) -> MSLTranslationError? {
        do { _ = try MSLTranslator.translate(msl); XCTFail("accepted"); return nil } catch { return error as? MSLTranslationError }
    }

    func testDetectLanguageAndKeywordRenames() throws {
        XCTAssertEqual(MSLTranslator.detectLanguage(Self.triangleMSL), .metal)
        XCTAssertEqual(MSLTranslator.detectLanguage(MetalDemoShaders.hlsl), .hlsl)
        XCTAssertEqual(MSLTranslator.detectLanguage("float4 PSMain() : SV_Target { return 1; }"), .hlsl)
        XCTAssertEqual(MSLTranslator.detectLanguage("vertex float4 v() { return float4(0); }"), .metal)
        // HLSL keywords used as MSL identifiers get a trailing underscore, entry points included.
        let msl = "#include <metal_stdlib>\nusing namespace metal;\nstruct S { float4 position [[position]]; float sample; };\nvertex S linear(uint vid [[vertex_id]]) { S out; out.position = float4(0); out.sample = 1; return out; }"
        let t = try translate(msl)
        XCTAssertTrue(t.hlsl.contains("S linear_(uint vid : SV_VertexID)"), t.hlsl)
        XCTAssertTrue(squash(t.hlsl).contains(squash("out_.sample_ = 1;")), t.hlsl)
        XCTAssertEqual(t.function(named: "linear")?.entryPoint, "linear_")
    }

    func testConstexprSamplersAndHelpers() throws {
        let msl = """
        #include <metal_stdlib>
        using namespace metal;
        constexpr sampler linearSampler(filter::linear, address::repeat, mip_filter::linear);
        float4 fetch(texture2d<float> t, sampler s, float2 uv) { return t.sample(s, uv, level(0)); }
        fragment float4 f(float2 uv [[user(uv)]], texture2d<float> tex [[texture(0)]], sampler explicitSampler [[sampler(0)]], depth2d<float> shadow [[texture(1)]], sampler cmp [[sampler(1)]]) {
            float d = shadow.sample_compare(cmp, uv, 0.5);
            return fetch(tex, linearSampler, uv) + tex.sample(explicitSampler, uv, bias(1.0)) * d;
        }
        """
        let t = try translate(msl)
        let h = t.hlsl
        XCTAssertTrue(h.contains("SamplerState linearSampler : register(s2);"), h)
        XCTAssertTrue(h.contains("SamplerComparisonState cmp : register(s1);"), h)
        XCTAssertTrue(h.contains("Texture2D<float> shadow : register(t1);"), h)
        XCTAssertTrue(h.contains("float4 fetch(Texture2D<float4> t, SamplerState s, float2 uv)"), h)
        XCTAssertTrue(squash(h).contains(squash("return t.SampleLevel(s, uv, 0);")), h)
        XCTAssertTrue(squash(h).contains(squash("float d = shadow.SampleCmp(cmp, uv, 0.5);")), h)
        XCTAssertTrue(squash(h).contains(squash("tex.SampleBias(explicitSampler, uv, 1.0)")), h)
        XCTAssertTrue(h.contains("float4 f(float2 uv : TEXCOORD0) : SV_Target0"), h)
        let f = try XCTUnwrap(t.function(named: "f"))
        XCTAssertEqual(f.constexprSamplers.count, 1)
        XCTAssertEqual(f.constexprSamplers.first?.slot, 2)
        XCTAssertEqual(f.constexprSamplers.first?.minFilter, .linear)
        XCTAssertEqual(f.constexprSamplers.first?.mipFilter, .linear)
        XCTAssertEqual(f.constexprSamplers.first?.sAddressMode, .repeat)
    }

    func testDevicesAcceptMSL() throws {
        try MainActor.assumeIsolated {
            let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
            let lib = try device.makeLibrary(source: Self.triangleMSL, options: nil)
            XCTAssertEqual(Set(lib.functionNames), ["triangleVertex", "triangleFragment"])
            XCTAssertEqual(lib.makeFunction(name: "triangleVertex")?.functionType, .vertex)
            XCTAssertNotNil((lib as? MTLReferenceLibrary)?.hlslSource)
            // HLSL still works without options (detected) and with the explicit option.
            let hl = try device.makeLibrary(source: MetalDemoShaders.hlsl, options: nil)
            XCTAssertEqual(Set(hl.functionNames), ["triangleVertex", "triangleFragment"])
            XCTAssertNil((hl as? MTLReferenceLibrary)?.hlslSource)
            // Unsupported MSL is a compile failure with the line in the message.
            XCTAssertThrowsError(try device.makeLibrary(source: "#include <metal_stdlib>\nusing namespace metal;\ntemplate <typename T> T f(T x) { return x; }", options: nil)) { error in
                guard let e = error as? MTLLibraryError else { return XCTFail("\(error)") }
                XCTAssertEqual(e.code, .compileFailure)
                XCTAssertTrue(e.message.contains("line 3"), e.message)
            }
        }
    }
}
