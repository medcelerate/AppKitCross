// Metal Shading Language → HLSL source translation (ADR-0006).
//
// `MSLTranslator.translate` turns the practical MSL subset (structs with stage
// attributes, `vertex`/`fragment`/`kernel` entry points, buffer/texture/sampler
// arguments, the metal_stdlib math library) into HLSL that dxc compiles at shader model
// 6 and d3dcompiler at 5.1. The binding model mirrors the D3D12 shim's root signature:
// `[[buffer(n)]]` references → `register(bn)`, `[[texture(n)]]` → `register(tn)`,
// `[[sampler(n)]]` → `register(sn)`; pointer-style buffers go to `space1`, which the shim
// does not bind yet (see the ADR). Matrices keep Metal's column-major storage
// (`#pragma pack_matrix(column_major)`), `a * b` with a matrix operand becomes
// `mul(a, b)`, and matrix constructors/subscripts are transposed so column semantics
// survive. Anything outside the subset throws `MSLTranslationError` with the line.
//
// Pure Swift, no platform imports: the macOS host build tests it.

import Foundation

/// A construct the translator does not handle, with the 1-based source line.
public struct MSLTranslationError: Error, CustomStringConvertible, Sendable {
    public let line: Int
    public let message: String
    public init(line: Int, message: String) { self.line = line; self.message = message }
    public var description: String { "MSL line \(line): \(message)" }
}

/// The result of translating one MSL source: HLSL text plus what the device needs to
/// compile and bind its entry points.
public struct MSLTranslation: Sendable {
    /// A `constexpr sampler` declared in the source; the device binds it at `slot`
    /// (`register(s<slot>)`) when a pipeline using the function is set.
    public struct ConstexprSampler: Sendable, Equatable {
        public var name: String
        public var slot: Int
        public var minFilter: MTLSamplerMinMagFilter = .nearest
        public var magFilter: MTLSamplerMinMagFilter = .nearest
        public var mipFilter: MTLSamplerMipFilter = .notMipmapped
        public var sAddressMode: MTLSamplerAddressMode = .clampToEdge
        public var tAddressMode: MTLSamplerAddressMode = .clampToEdge
        public var rAddressMode: MTLSamplerAddressMode = .clampToEdge
        public var compareFunction: MTLCompareFunction = .never
    }
    public struct Function: Sendable {
        /// The MSL function name (what `MTLLibrary.makeFunction(name:)` takes).
        public var name: String
        /// The HLSL entry point (differs from `name` only when it collides with an HLSL keyword).
        public var entryPoint: String
        public var type: MTLFunctionType
        /// `[numthreads]` of a kernel.
        public var threadgroupSize: (Int, Int, Int)?
        /// `constexpr sampler`s the function samples with.
        public var constexprSamplers: [ConstexprSampler]
        /// True when the function reads or writes pointer-style buffers (`space1` tables).
        public var usesBufferTables: Bool
    }
    public let hlsl: String
    public let functions: [Function]
    public var functionNames: [String] { functions.map(\.name) }
    public func function(named name: String) -> Function? { functions.first { $0.name == name } }
}

public enum MSLTranslator {
    public struct Options: Sendable {
        public enum HalfType: Sendable { case float, min16float }
        /// What `half` maps to. `float` by default; `min16float` keeps the reduced
        /// precision hint (dxc only).
        public var halfType: HalfType = .float
        /// `[numthreads]` for kernels without a `[[threads_per_threadgroup(x, y, z)]]`
        /// attribute (a translator extension), chosen by the dimension of the
        /// `thread_position_in_grid` argument.
        public var threadgroupSize1D: (Int, Int, Int) = (64, 1, 1)
        public var threadgroupSize2D: (Int, Int, Int) = (8, 8, 1)
        public var threadgroupSize3D: (Int, Int, Int) = (4, 4, 4)
        public init() {}
    }

    /// Guesses the dialect of a shader source: MSL when it includes metal_stdlib, uses the
    /// `metal` namespace, has `[[...]]` attributes or `vertex`/`fragment`/`kernel`
    /// qualifiers; HLSL when it has semantics, `cbuffer`s or `register` bindings; MSL
    /// otherwise (Apple's default).
    public static func detectLanguage(_ source: String) -> MTLShaderLanguage {
        if source.contains("metal_stdlib") || source.contains("namespace metal") || source.contains("[[") { return .metal }
        let hlslMarkers = ["SV_", "cbuffer ", "register(", "SamplerState", "Texture2D", "numthreads", "StructuredBuffer"]
        if hlslMarkers.contains(where: { source.contains($0) }) { return .hlsl }
        let scalars = source.replacingOccurrences(of: "(", with: " ").split(whereSeparator: { $0.isWhitespace })
        for (i, t) in scalars.enumerated() where t == "vertex" || t == "fragment" || t == "kernel" {
            if i + 2 < scalars.count { return .metal }
        }
        if source.contains(" : ") && source.contains("float4") { return .hlsl }
        return .metal
    }

    public static func translate(_ source: String, options: Options = Options()) throws -> MSLTranslation {
        var t = Translator(options: options)
        return try t.run(source)
    }
}

// MARK: - Lexer

struct MSLToken: Equatable {
    enum Kind { case ident, number, punct, string, directive }
    var kind: Kind
    var text: String
    var line: Int
    init(_ kind: Kind, _ text: String, _ line: Int) { self.kind = kind; self.text = text; self.line = line }
    var isIdent: Bool { kind == .ident }
    func `is`(_ s: String) -> Bool { kind != .string && text == s }
}

enum MSLLexer {
    static func tokenize(_ source: String) throws -> [MSLToken] {
        let s = Array(source.unicodeScalars)
        var out: [MSLToken] = []
        var i = 0, line = 1
        var atLineStart = true
        func isIdentStart(_ c: Unicode.Scalar) -> Bool { c == "_" || (c.value < 128 && (Character(c).isLetter)) }
        func isIdentChar(_ c: Unicode.Scalar) -> Bool { isIdentStart(c) || (c.value < 128 && Character(c).isNumber) }
        let three: Set<String> = ["<<=", ">>=", "..."]
        let two: Set<String> = ["->", "::", "<<", ">>", "<=", ">=", "==", "!=", "&&", "||", "++", "--", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^="]
        while i < s.count {
            let c = s[i]
            if c == "\n" { line += 1; i += 1; atLineStart = true; continue }
            if c == " " || c == "\t" || c == "\r" { i += 1; continue }
            if c == "/" && i + 1 < s.count && s[i + 1] == "/" {
                while i < s.count && s[i] != "\n" { i += 1 }
                continue
            }
            if c == "/" && i + 1 < s.count && s[i + 1] == "*" {
                i += 2
                while i + 1 < s.count && !(s[i] == "*" && s[i + 1] == "/") { if s[i] == "\n" { line += 1 }; i += 1 }
                i += 2
                continue
            }
            if c == "#" && atLineStart {
                var text = ""
                let startLine = line
                while i < s.count {
                    if s[i] == "\\" && i + 1 < s.count && s[i + 1] == "\n" { i += 2; line += 1; text.append(" "); continue }
                    if s[i] == "\n" { break }
                    text.unicodeScalars.append(s[i]); i += 1
                }
                out.append(MSLToken(.directive, text, startLine))
                continue
            }
            atLineStart = false
            if c == "\"" {
                var text = "\""
                i += 1
                while i < s.count && s[i] != "\"" { if s[i] == "\\" && i + 1 < s.count { text.unicodeScalars.append(s[i]); i += 1 }; text.unicodeScalars.append(s[i]); i += 1 }
                text.append("\""); i += 1
                out.append(MSLToken(.string, text, line))
                continue
            }
            if isIdentStart(c) {
                var text = ""
                while i < s.count && isIdentChar(s[i]) { text.unicodeScalars.append(s[i]); i += 1 }
                out.append(MSLToken(.ident, text, line))
                continue
            }
            if Character(c).isNumber || (c == "." && i + 1 < s.count && Character(s[i + 1]).isNumber) {
                var text = ""
                let hex = c == "0" && i + 1 < s.count && (s[i + 1] == "x" || s[i + 1] == "X")
                if hex { text = "0x"; i += 2 }
                while i < s.count {
                    let d = s[i]
                    let digit = Character(d).isNumber || (hex && Character(d).isHexDigit) || d == "."
                    let exponent = !hex && (d == "e" || d == "E") && i + 1 < s.count && (Character(s[i + 1]).isNumber || ((s[i + 1] == "+" || s[i + 1] == "-") && i + 2 < s.count && Character(s[i + 2]).isNumber))
                    if digit { text.unicodeScalars.append(d); i += 1 }
                    else if exponent { text.unicodeScalars.append(d); text.unicodeScalars.append(s[i + 1]); i += 2 }
                    else { break }
                }
                // Suffixes: u, l, f keep their HLSL meaning; h (half) is dropped.
                while i < s.count, let ch = Optional(s[i]), ch == "u" || ch == "U" || ch == "l" || ch == "L" || ch == "f" || ch == "F" || ch == "h" || ch == "H" {
                    if ch == "h" || ch == "H" { i += 1; continue }
                    if ch == "l" || ch == "L" { i += 1; continue }
                    text.unicodeScalars.append(ch); i += 1
                }
                out.append(MSLToken(.number, text, line))
                continue
            }
            if i + 2 < s.count, three.contains(String(String.UnicodeScalarView(s[i...i + 2]))) {
                out.append(MSLToken(.punct, String(String.UnicodeScalarView(s[i...i + 2])), line)); i += 3; continue
            }
            if i + 1 < s.count, two.contains(String(String.UnicodeScalarView(s[i...i + 1]))) {
                out.append(MSLToken(.punct, String(String.UnicodeScalarView(s[i...i + 1])), line)); i += 2; continue
            }
            out.append(MSLToken(.punct, String(c), line))
            i += 1
        }
        return out
    }
}

// MARK: - Tables

enum MSLTables {
    /// HLSL reserved words that are legal MSL identifiers; renamed with a trailing `_`.
    static let hlslKeywords: Set<String> = [
        "in", "out", "inout", "sample", "linear", "centroid", "matrix", "vector", "texture", "pass", "technique", "string",
        "shared", "groupshared", "precise", "line", "point", "triangle", "lineadj", "triangleadj", "uniform", "extern",
        "register", "packoffset", "row_major", "column_major", "snorm", "unorm", "dword", "cbuffer", "tbuffer", "stateblock",
        "compile", "asm", "fxgroup", "pixelfragment", "vertexfragment", "nointerpolation", "noperspective", "export",
        "interface", "Buffer", "min16float", "min16int", "min16uint", "min10float", "min12int", "mul", "lerp", "frac", "ddx", "ddy", "mad",
        "SamplerState", "Texture2D", "RWTexture2D", "ConstantBuffer", "StructuredBuffer", "RWStructuredBuffer", "numthreads", "discard",
    ]
    static let scalars: [String: String] = [
        "float": "float", "int": "int", "uint": "uint", "bool": "bool", "short": "int", "ushort": "uint", "char": "int", "uchar": "uint",
        "long": "int64_t", "ulong": "uint64_t", "size_t": "uint", "ptrdiff_t": "int", "double": "double", "void": "void",
        "int8_t": "int", "uint8_t": "uint", "int16_t": "int", "uint16_t": "uint", "int32_t": "int", "uint32_t": "uint", "int64_t": "int64_t", "uint64_t": "uint64_t",
    ]
    static let textures: [String: (hlsl: String, dims: Int, array: Bool, cube: Bool, ms: Bool, depth: Bool)] = [
        "texture1d": ("Texture1D", 1, false, false, false, false), "texture1d_array": ("Texture1DArray", 1, true, false, false, false),
        "texture2d": ("Texture2D", 2, false, false, false, false), "texture2d_array": ("Texture2DArray", 2, true, false, false, false),
        "texture3d": ("Texture3D", 3, false, false, false, false), "texturecube": ("TextureCube", 2, false, true, false, false),
        "texturecube_array": ("TextureCubeArray", 2, true, true, false, false), "texture2d_ms": ("Texture2DMS", 2, false, false, true, false),
        "depth2d": ("Texture2D", 2, false, false, false, true), "depth2d_array": ("Texture2DArray", 2, true, false, false, true),
        "depthcube": ("TextureCube", 2, false, true, false, true), "depth2d_ms": ("Texture2DMS", 2, false, false, true, true),
    ]
    static let intrinsics: [String: String] = [
        "fract": "frac", "mix": "lerp", "dfdx": "ddx", "dfdy": "ddy", "fma": "mad", "rint": "round", "popcount": "countbits", "ctz": "firstbitlow",
        "fmin": "min", "fmax": "max", "fabs": "abs", "powr": "pow", "isordered": "isfinite", "simd_sum": "WaveActiveSum", "simd_min": "WaveActiveMin",
        "simd_max": "WaveActiveMax", "simd_product": "WaveActiveProduct", "simd_broadcast_first": "WaveReadLaneFirst", "simd_is_first": "WaveIsFirstLane",
        "simd_prefix_exclusive_sum": "WavePrefixSum", "simd_ballot": "WaveActiveBallot", "simd_any": "WaveActiveAnyTrue", "simd_all": "WaveActiveAllTrue",
        "rsqrt": "rsqrt", "atan2": "atan2", "fmod": "fmod", "saturate": "saturate",
    ]
    /// Intrinsics whose result has the type of their first argument (for matrix detection).
    static let sameTypeIntrinsics: Set<String> = ["abs", "normalize", "saturate", "clamp", "min", "max", "lerp", "floor", "ceil", "round", "frac", "sqrt", "rsqrt", "exp", "exp2", "log", "log2", "pow", "sin", "cos", "tan", "sign", "trunc", "mad", "step", "smoothstep", "reflect", "fmod", "ddx", "ddy", "fwidth"]
    static let constants: [String: String] = [
        "M_PI_F": "3.14159265358979323846f", "M_PI_H": "3.14159265358979323846f", "M_PI_2_F": "1.57079632679489661923f", "M_PI_4_F": "0.785398163397448309616f",
        "M_1_PI_F": "0.318309886183790671538f", "M_2_PI_F": "0.636619772367581343076f", "M_E_F": "2.71828182845904523536f", "M_SQRT2_F": "1.41421356237309504880f",
        "M_SQRT1_2_F": "0.707106781186547524401f", "M_LN2_F": "0.693147180559945309417f", "M_LN10_F": "2.30258509299404568402f", "M_LOG2E_F": "1.44269504088896340736f",
        "FLT_MAX": "3.402823466e+38f", "FLT_MIN": "1.175494351e-38f", "FLT_EPSILON": "1.192092896e-07f", "HALF_MAX": "65504.0f", "UINT_MAX": "0xffffffffu",
        "INT_MAX": "2147483647", "INT_MIN": "(-2147483647 - 1)", "INFINITY": "asfloat(0x7f800000u)", "NAN": "asfloat(0x7fc00000u)", "MAXFLOAT": "3.402823466e+38f",
    ]
    /// Stage builtins usable as entry-point parameters or I/O struct members.
    static let builtinSemantics: [String: String] = [
        "position": "SV_Position", "vertex_id": "SV_VertexID", "instance_id": "SV_InstanceID", "front_facing": "SV_IsFrontFace",
        "sample_id": "SV_SampleIndex", "sample_mask": "SV_Coverage", "primitive_id": "SV_PrimitiveID", "point_size": "PSIZE",
        "clip_distance": "SV_ClipDistance", "render_target_array_index": "SV_RenderTargetArrayIndex", "viewport_array_index": "SV_ViewportArrayIndex",
        "thread_position_in_grid": "SV_DispatchThreadID", "thread_position_in_threadgroup": "SV_GroupThreadID",
        "threadgroup_position_in_grid": "SV_GroupID", "thread_index_in_threadgroup": "SV_GroupIndex", "barycentric_coord": "SV_Barycentrics",
        "stencil": "SV_StencilRef",
    ]
    static let unsupportedAttributes: [String: String] = [
        "function_constant": "function constants are not translated (specialise the source before compiling)",
        "base_vertex": "[[base_vertex]] needs shader model 6.8", "base_instance": "[[base_instance]] needs shader model 6.8",
        "point_coord": "[[point_coord]] has no HLSL equivalent", "threads_per_grid": "[[threads_per_grid]] has no HLSL equivalent (pass it in a buffer)",
        "threadgroups_per_grid": "[[threadgroups_per_grid]] has no HLSL equivalent (pass it in a buffer)",
        "simdgroup_index_in_threadgroup": "[[simdgroup_index_in_threadgroup]] has no HLSL equivalent",
        "raster_order_group": "raster order groups are not translated", "imageblock_data": "imageblocks are not translated",
        "payload": "mesh/object shaders are not translated", "amplification_count": "mesh/object shaders are not translated",
        "amplification_id": "mesh/object shaders are not translated", "threadgroup": "threadgroup pointer arguments are not translated (declare `threadgroup` arrays inside the kernel)",
    ]
    static let interpolation: [String: String] = [
        "flat": "nointerpolation", "center_no_perspective": "noperspective", "centroid_perspective": "centroid", "centroid_no_perspective": "centroid noperspective",
        "sample_perspective": "sample", "sample_no_perspective": "sample noperspective", "center_perspective": "",
    ]
    static let statementKeywords: Set<String> = ["if", "else", "for", "while", "do", "switch", "case", "default", "return", "break", "continue", "discard"]
}

// MARK: - Model

struct MSLAttribute { var name: String; var args: [MSLToken]; var line: Int }

struct MSLType {
    var qualifiers: Set<String> = []       // const constant device threadgroup thread constexpr static
    var base: String = ""                  // MSL base name
    var templateArgs: [[MSLToken]] = []
    var isPointer = false
    var isReference = false
    var line = 0
}

/// What an identifier denotes while translating a body (HLSL-side types).
struct MSLSymbol {
    enum Kind { case value, texture, sampler, constantBuffer, structuredBuffer, rwReference }
    var kind: Kind
    /// Value type: the HLSL type (struct name, `float4x4`, ...). Buffers: the element type. Textures: the element type.
    var type: String
    var arrayDims: [String] = []
    var texture: (hlsl: String, dims: Int, array: Bool, cube: Bool, ms: Bool, depth: Bool, rw: Bool)? = nil
    var rename: String? = nil
}

struct MSLStructMember { var type: String; var name: String; var arrayDims: [String]; var attrs: [MSLAttribute]; var line: Int; var isStructType = false }
final class MSLStruct {
    var name: String
    var members: [MSLStructMember]
    var line: Int
    enum Role { case vertexInput, varying, fragmentOutput }
    var roles: Set<Role> = []
    init(name: String, members: [MSLStructMember], line: Int) { self.name = name; self.members = members; self.line = line }
}

struct MSLResource {
    var mslName: String
    var hlslName: String
    /// Declaration without the name, e.g. `ConstantBuffer<Frame>` and the register suffix.
    var typeText: String
    var registerText: String
    var symbol: MSLSymbol
    var cbufferWrapped: Bool       // non-struct constant reference: `cbuffer __cb_x : register(b0) { float4 x; }`
    var line: Int
}

struct MSLParam {
    var type: MSLType
    var name: String
    var arrayDims: [String]
    var attrs: [MSLAttribute]
    var line: Int
}

final class MSLFunction {
    var name: String
    var hlslName: String
    var kind: MTLFunctionType?   // nil = helper
    var returnType: MSLType
    var returnAttrs: [MSLAttribute]
    var funcAttrs: [MSLAttribute]
    var params: [MSLParam]
    var body: [MSLToken]?        // nil for a forward declaration
    var line: Int
    // Translation output
    var resources: [MSLResource] = []
    var hlslParams: [String] = []
    var prologue: [MSLToken] = []
    var symbols: [String: MSLSymbol] = [:]
    var threadgroupSize: (Int, Int, Int)? = nil
    var constexprSamplers: [String] = []
    var usesBufferTables = false
    var bodyText = ""
    var returnSemantic: String? = nil
    var hlslReturnType = ""
    var hlslAttributes: [String] = []
    init(name: String, kind: MTLFunctionType?, returnType: MSLType, returnAttrs: [MSLAttribute], funcAttrs: [MSLAttribute], params: [MSLParam], body: [MSLToken]?, line: Int) {
        self.name = name; hlslName = name; self.kind = kind; self.returnType = returnType; self.returnAttrs = returnAttrs; self.funcAttrs = funcAttrs; self.params = params; self.body = body; self.line = line
    }
}

enum MSLDecl {
    case raw(String)
    case structDecl(MSLStruct)
    case global(String)
    case function(MSLFunction)
}

// MARK: - Translator

struct Translator {
    let options: MSLTranslator.Options
    var tokens: [MSLToken] = []
    var pos = 0
    var decls: [MSLDecl] = []
    var structs: [String: MSLStruct] = [:]
    var typedefs: [String: String] = [:]
    var globals: [String: MSLSymbol] = [:]
    var constexprSamplers: [String: MSLTranslation.ConstexprSampler] = [:]
    var usedSamplerSlots: Set<Int> = []
    var comparisonSamplers: Set<String> = []
    var helpers: [String: String] = [:]      // name → HLSL definition
    var groupshared: [String] = []
    var functions: [MSLFunction] = []

    init(options: MSLTranslator.Options) { self.options = options }

    // MARK: Token access

    var atEnd: Bool { pos >= tokens.count }
    var current: MSLToken? { pos < tokens.count ? tokens[pos] : nil }
    var currentLine: Int { current?.line ?? tokens.last?.line ?? 1 }
    func peek(_ n: Int = 0) -> MSLToken? { pos + n < tokens.count ? tokens[pos + n] : nil }
    mutating func advance() -> MSLToken { let t = tokens[pos]; pos += 1; return t }
    func check(_ s: String) -> Bool { current?.is(s) ?? false }
    mutating func match(_ s: String) -> Bool { if check(s) { pos += 1; return true }; return false }
    mutating func expect(_ s: String) throws -> MSLToken {
        guard check(s) else { throw MSLTranslationError(line: currentLine, message: "expected '\(s)'" + (current.map { ", found '\($0.text)'" } ?? " at end of source")) }
        return advance()
    }
    mutating func expectIdent() throws -> MSLToken {
        guard let t = current, t.isIdent else { throw MSLTranslationError(line: currentLine, message: "expected an identifier" + (current.map { ", found '\($0.text)'" } ?? "")) }
        return advance()
    }
    func fail(_ message: String, line: Int? = nil) -> MSLTranslationError { MSLTranslationError(line: line ?? currentLine, message: message) }

    // MARK: Driver

    mutating func run(_ source: String) throws -> MSLTranslation {
        tokens = try MSLLexer.tokenize(source)
        try parseTopLevel()
        try assignStructRoles()
        try planResources()
        assignConstexprSamplerSlots()
        for f in functions { try translateBody(f) }
        let hlsl = assemble()
        let fns = functions.compactMap { f -> MSLTranslation.Function? in
            guard let kind = f.kind else { return nil }
            return MSLTranslation.Function(name: f.name, entryPoint: f.hlslName, type: kind, threadgroupSize: f.threadgroupSize,
                                           constexprSamplers: f.constexprSamplers.compactMap { constexprSamplers[$0] }, usesBufferTables: f.usesBufferTables)
        }
        return MSLTranslation(hlsl: hlsl, functions: fns)
    }

    // MARK: Top level

    mutating func parseTopLevel() throws {
        while let t = current {
            switch t.kind {
            case .directive:
                pos += 1
                try handleDirective(t)
            case .ident:
                switch t.text {
                case "using":
                    pos += 1
                    if match("namespace") {
                        let ns = try expectIdent()
                        guard ns.text == "metal" else { throw fail("only `using namespace metal` is supported", line: ns.line) }
                        _ = try expect(";")
                    } else {
                        let alias = try expectIdent()
                        _ = try expect("=")
                        let type = try parseType()
                        _ = try expect(";")
                        let hlsl = try hlslTypeName(type)
                        typedefs[alias.text] = hlsl
                        decls.append(.raw("typedef \(hlsl) \(identifier(alias.text));"))
                    }
                case "typedef":
                    pos += 1
                    let type = try parseType()
                    let alias = try expectIdent()
                    _ = try expect(";")
                    let hlsl = try hlslTypeName(type)
                    typedefs[alias.text] = hlsl
                    decls.append(.raw("typedef \(hlsl) \(identifier(alias.text));"))
                case "struct":
                    try parseStruct()
                case "template", "class", "namespace", "operator", "virtual", "union":
                    throw fail("`\(t.text)` is not supported by the MSL translator")
                case "enum":
                    throw fail("enums are not translated (use `constant` integer constants)")
                case "constexpr" where peek(1)?.is("sampler") == true:
                    try parseConstexprSampler()
                case "vertex", "fragment", "kernel", "visible", "intersection", "mesh", "object":
                    try parseFunctionOrGlobal(leadingAttrs: [])
                case ";":
                    pos += 1
                default:
                    try parseFunctionOrGlobal(leadingAttrs: [])
                }
            case .punct where t.text == "[" && peek(1)?.is("[") == true:
                let attrs = try parseAttributes()
                try parseFunctionOrGlobal(leadingAttrs: attrs)
            case .punct where t.text == ";":
                pos += 1
            default:
                throw fail("unexpected '\(t.text)' at file scope")
            }
        }
    }

    mutating func handleDirective(_ t: MSLToken) throws {
        let text = t.text.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#include") {
            let target = text.dropFirst("#include".count).trimmingCharacters(in: .whitespaces)
            if target.hasPrefix("<metal") || target == "<simd/simd.h>" || target.hasPrefix("<simd") { return }
            throw fail("#include \(target) cannot be resolved; inline the file", line: t.line)
        }
        if text.hasPrefix("#pragma") { return }
        decls.append(.raw(text))
    }

    /// `[[name(args)]], ...]]` (the opening `[` `[` is current).
    mutating func parseAttributes() throws -> [MSLAttribute] {
        var attrs: [MSLAttribute] = []
        while check("[") && peek(1)?.is("[") == true {
            pos += 2
            repeat {
                let name = try expectIdent()
                var args: [MSLToken] = []
                if match("(") {
                    var depth = 1
                    while let c = current {
                        pos += 1
                        if c.is("(") { depth += 1 } else if c.is(")") { depth -= 1; if depth == 0 { break } }
                        args.append(c)
                    }
                }
                attrs.append(MSLAttribute(name: name.text, args: args, line: name.line))
            } while match(",")
            _ = try expect("]")
            _ = try expect("]")
        }
        return attrs
    }

    mutating func parseType() throws -> MSLType {
        var type = MSLType()
        type.line = currentLine
        let qualifiers: Set<String> = ["const", "constant", "device", "threadgroup", "thread", "constexpr", "static", "inline", "volatile", "ray_data", "threadgroup_imageblock"]
        while let t = current, t.isIdent, qualifiers.contains(t.text) {
            if t.text == "ray_data" || t.text == "threadgroup_imageblock" { throw fail("`\(t.text)` address space is not supported", line: t.line) }
            type.qualifiers.insert(t.text); pos += 1
        }
        if check("metal") && peek(1)?.is("::") == true { pos += 2 }
        let base = try expectIdent()
        if base.text == "unsigned" || base.text == "signed" {
            // unsigned int → uint
            let next = try expectIdent()
            type.base = (base.text == "unsigned" ? "u" : "") + next.text
        } else {
            type.base = base.text
        }
        if base.text == "atomic_uint" || base.text == "atomic_int" || base.text == "atomic_bool" || base.text == "atomic" || base.text == "array" || base.text == "texture_buffer" || base.text == "visible_function_table" || base.text == "intersection_function_table" || base.text == "acceleration_structure" {
            throw fail("`\(base.text)` is not supported by the MSL translator", line: base.line)
        }
        if check("<") {
            pos += 1
            var arg: [MSLToken] = []
            var depth = 1
            while let c = current {
                pos += 1
                if c.is("<") { depth += 1 } else if c.is(">") { depth -= 1; if depth == 0 { if !arg.isEmpty { type.templateArgs.append(arg) }; break } }
                else if c.is(">>") && depth >= 2 { depth -= 2; if depth == 0 { if !arg.isEmpty { type.templateArgs.append(arg) }; break } }
                if c.is(",") && depth == 1 { type.templateArgs.append(arg); arg = []; continue }
                arg.append(c)
            }
        }
        while let t = current, t.isIdent, qualifiers.contains(t.text) { type.qualifiers.insert(t.text); pos += 1 }
        while true {
            if match("*") { if type.isPointer { throw fail("pointer to pointer is not supported") }; type.isPointer = true }
            else if match("&") { type.isReference = true }
            else if check("&&") { throw fail("rvalue references are not supported") }
            else if let t = current, t.isIdent, t.text == "const" { pos += 1; type.qualifiers.insert("const") }
            else { break }
        }
        return type
    }

    mutating func parseArrayDims() throws -> [String] {
        var dims: [String] = []
        while check("[") && peek(1)?.is("[") != true {
            pos += 1
            var text = ""
            while let c = current, !c.is("]") { text += (text.isEmpty ? "" : " ") + c.text; pos += 1 }
            _ = try expect("]")
            dims.append(text)
        }
        return dims
    }

    /// Collects tokens up to a `,` or `;` at depth 0 (initialisers).
    mutating func collectUntilSeparator() -> [MSLToken] {
        var out: [MSLToken] = []
        var depth = 0
        while let c = current {
            if depth == 0 && (c.is(",") || c.is(";")) { break }
            if c.is("(") || c.is("[") || c.is("{") { depth += 1 }
            if c.is(")") || c.is("]") || c.is("}") { depth -= 1 }
            out.append(c); pos += 1
        }
        return out
    }

    mutating func parseStruct() throws {
        let kw = advance()
        let name = try expectIdent()
        if match(";") { decls.append(.raw("struct \(identifier(name.text));")); return }  // forward declaration
        _ = try expect("{")
        var members: [MSLStructMember] = []
        while !check("}") {
            guard !atEnd else { throw fail("unterminated struct '\(name.text)'", line: kw.line) }
            let type = try parseType()
            if type.isPointer || type.isReference { throw fail("pointer or reference struct members are not supported", line: type.line) }
            repeat {
                let member = try expectIdent()
                let dims = try parseArrayDims()
                let attrs = try parseAttributes()
                if check("=") { throw fail("default member initialisers are not supported", line: member.line) }
                let hlsl = try hlslTypeName(type)
                members.append(MSLStructMember(type: hlsl, name: identifier(member.text), arrayDims: dims, attrs: attrs, line: member.line, isStructType: structs[type.base] != nil))
            } while match(",")
            _ = try expect(";")
        }
        _ = try expect("}")
        _ = try expect(";")
        let s = MSLStruct(name: identifier(name.text), members: members, line: kw.line)
        structs[name.text] = s
        decls.append(.structDecl(s))
    }

    mutating func parseConstexprSampler() throws {
        let kw = advance()  // constexpr
        _ = advance()       // sampler
        let name = try expectIdent()
        var sampler = MSLTranslation.ConstexprSampler(name: identifier(name.text), slot: -1)
        if match("(") {
            while !check(")") {
                guard !atEnd else { throw fail("unterminated constexpr sampler", line: kw.line) }
                let key = try expectIdent()
                _ = try expect("::")
                let value = try expectIdent()
                func address(_ v: String) throws -> MTLSamplerAddressMode {
                    switch v {
                    case "clamp_to_edge": return .clampToEdge
                    case "clamp_to_zero": return .clampToZero
                    case "clamp_to_border": return .clampToBorderColor
                    case "repeat": return .repeat
                    case "mirrored_repeat": return .mirrorRepeat
                    default: throw fail("unknown sampler address mode '\(v)'", line: value.line)
                    }
                }
                switch key.text {
                case "filter":
                    let f: MTLSamplerMinMagFilter = value.text == "linear" ? .linear : .nearest
                    sampler.minFilter = f; sampler.magFilter = f
                case "min_filter": sampler.minFilter = value.text == "linear" ? .linear : .nearest
                case "mag_filter": sampler.magFilter = value.text == "linear" ? .linear : .nearest
                case "mip_filter": sampler.mipFilter = value.text == "linear" ? .linear : value.text == "nearest" ? .nearest : .notMipmapped
                case "address": let a = try address(value.text); sampler.sAddressMode = a; sampler.tAddressMode = a; sampler.rAddressMode = a
                case "s_address": sampler.sAddressMode = try address(value.text)
                case "t_address": sampler.tAddressMode = try address(value.text)
                case "r_address": sampler.rAddressMode = try address(value.text)
                case "compare_func":
                    let map: [String: MTLCompareFunction] = ["never": .never, "less": .less, "less_equal": .lessEqual, "greater": .greater, "greater_equal": .greaterEqual, "equal": .equal, "not_equal": .notEqual, "always": .always, "none": .never]
                    guard let c = map[value.text] else { throw fail("unknown compare function '\(value.text)'", line: value.line) }
                    sampler.compareFunction = c
                case "coord", "max_anisotropy", "lod_clamp", "border_color", "reduction":
                    // Accepted and ignored; the shim's sampler model has no equivalent.
                    if match("(") { var d = 1; while let c = current { pos += 1; if c.is("(") { d += 1 } else if c.is(")") { d -= 1; if d == 0 { break } } } }
                default: throw fail("unknown constexpr sampler property '\(key.text)'", line: key.line)
                }
                if !match(",") { break }
            }
            _ = try expect(")")
        }
        _ = try expect(";")
        constexprSamplers[name.text] = sampler
        globals[name.text] = MSLSymbol(kind: .sampler, type: "SamplerState", rename: identifier(name.text))
    }

    mutating func parseFunctionOrGlobal(leadingAttrs: [MSLAttribute]) throws {
        let startLine = currentLine
        var kind: MTLFunctionType? = nil
        var attrs = leadingAttrs
        if let t = current, t.isIdent {
            switch t.text {
            case "vertex": kind = .vertex; pos += 1
            case "fragment": kind = .fragment; pos += 1
            case "kernel": kind = .kernel; pos += 1
            case "visible", "intersection", "mesh", "object": throw fail("`\(t.text)` functions are not supported by the MSL translator")
            default: break
            }
        }
        attrs += try parseAttributes()
        let type = try parseType()
        let name = try expectIdent()
        if check("(") {
            pos += 1
            var params: [MSLParam] = []
            while !check(")") {
                guard !atEnd else { throw fail("unterminated parameter list of '\(name.text)'", line: name.line) }
                if check("void") && peek(1)?.is(")") == true { pos += 1; break }
                let ptype = try parseType()
                var pname = ""
                if let t = current, t.isIdent { pname = advance().text }
                let dims = try parseArrayDims()
                let pattrs = try parseAttributes()
                if check("=") { throw fail("default arguments are not supported", line: ptype.line) }
                params.append(MSLParam(type: ptype, name: pname, arrayDims: dims, attrs: pattrs, line: ptype.line))
                if !match(",") { break }
            }
            _ = try expect(")")
            let returnAttrs = try parseAttributes()
            var body: [MSLToken]? = nil
            if match(";") {
                body = nil
            } else {
                _ = try expect("{")
                var depth = 1
                var b: [MSLToken] = []
                while let c = current {
                    pos += 1
                    if c.is("{") { depth += 1 } else if c.is("}") { depth -= 1; if depth == 0 { break } }
                    b.append(c)
                }
                if depth != 0 { throw fail("unterminated body of '\(name.text)'", line: name.line) }
                body = b
            }
            let f = MSLFunction(name: name.text, kind: kind, returnType: type, returnAttrs: returnAttrs + attrs.filter { $0.name == "color" || $0.name == "position" }, funcAttrs: attrs, params: params, body: body, line: startLine)
            if MSLTables.hlslKeywords.contains(name.text) { f.hlslName = identifier(name.text) }
            if kind != nil, functions.contains(where: { $0.name == name.text && $0.kind != nil }) { throw fail("entry point '\(name.text)' is declared twice", line: name.line) }
            functions.append(f)
            decls.append(.function(f))
        } else {
            // Global variable: `constant float3 k = ...;` → `static const float3 k = ...;`
            if kind != nil { throw fail("expected '(' after '\(name.text)'", line: name.line) }
            guard type.qualifiers.contains("constant") || type.qualifiers.contains("static") || type.qualifiers.contains("constexpr") || type.qualifiers.contains("const") else {
                throw fail("global variables must be `constant` (or `static const`)", line: name.line)
            }
            if type.isPointer || type.isReference { throw fail("global pointers are not supported", line: name.line) }
            let hlsl = try hlslTypeName(type)
            var text = "static const \(hlsl) \(identifier(name.text))"
            let dims = try parseArrayDims()
            for d in dims { text += "[\(d)]" }
            globals[name.text] = MSLSymbol(kind: .value, type: hlsl, arrayDims: dims, rename: identifier(name.text))
            if match("=") {
                let initTokens = collectUntilSeparator()
                var ctx = BodyContext(function: nil, translator: self)
                let rewritten = try ctx.rewrite(initTokens)
                self = ctx.translator
                text += " = " + MSLFormatter.join(rewritten)
            }
            if check(",") { throw fail("one global per declaration, please", line: name.line) }
            _ = try expect(";")
            decls.append(.global(text + ";"))
        }
    }

    // MARK: Types

    /// Renames identifiers that are HLSL keywords.
    func identifier(_ name: String) -> String { MSLTables.hlslKeywords.contains(name) ? name + "_" : name }

    func halfName() -> String { options.halfType == .float ? "float" : "min16float" }

    /// Maps an MSL base type name to HLSL, or nil when it is not a builtin.
    func builtinTypeName(_ base: String) -> String? {
        if let s = MSLTables.scalars[base] { return s }
        if base == "half" { return halfName() }
        var name = base
        if name.hasPrefix("packed_") { name = String(name.dropFirst(7)) }
        // Vectors: prefixN
        if let last = name.last, let n = Int(String(last)), (2...4).contains(n), !name.dropLast().contains("x") {
            let prefix = String(name.dropLast())
            if prefix == "half" { return halfName() + "\(n)" }
            if let s = MSLTables.scalars[prefix], s != "void" { return s + "\(n)" }
        }
        // Matrices: prefixCxR (C columns, R rows) → HLSL prefixRxC (R rows, C columns): same storage, column-major.
        if let x = name.firstIndex(of: "x"), name.distance(from: x, to: name.endIndex) == 2, name.distance(from: name.startIndex, to: x) >= 2 {
            let prefix = String(name[..<name.index(before: x)])
            let c = name[name.index(before: x)], r = name[name.index(after: x)]
            if let ci = Int(String(c)), let ri = Int(String(r)), (2...4).contains(ci), (2...4).contains(ri) {
                if prefix == "half" { return halfName() + "\(ri)x\(ci)" }
                if prefix == "float" || prefix == "double" { return prefix + "\(ri)x\(ci)" }
            }
        }
        if name == "sampler" { return "SamplerState" }
        return nil
    }

    static func isMatrixType(_ t: String) -> Bool {
        guard t.count >= 5, let x = t.lastIndex(of: "x"), x != t.startIndex, t.distance(from: x, to: t.endIndex) == 2 else { return false }
        let c = t[t.index(before: x)], r = t[t.index(after: x)]
        return "234".contains(c) && "234".contains(r) && t[..<t.index(before: x)].allSatisfy { $0.isLetter || $0 == "1" || $0 == "6" }
    }
    static func transposedMatrixName(_ t: String) -> String {
        guard isMatrixType(t), let x = t.lastIndex(of: "x") else { return t }
        let c = t[t.index(before: x)], r = t[t.index(after: x)]
        return String(t[..<t.index(before: x)]) + String(r) + "x" + String(c)
    }
    static func isVectorType(_ t: String) -> Bool {
        guard let last = t.last, "234".contains(last), !isMatrixType(t) else { return false }
        return ["float", "half", "int", "uint", "bool", "min16float", "double"].contains(String(t.dropLast()))
    }

    func textureInfo(_ type: MSLType) throws -> (hlsl: String, dims: Int, array: Bool, cube: Bool, ms: Bool, depth: Bool, rw: Bool, element: String)? {
        guard let t = MSLTables.textures[type.base] else { return nil }
        var element = "float"
        var rw = false
        for arg in type.templateArgs {
            let text = arg.map(\.text).joined()
            if text.hasPrefix("access::") {
                switch text.dropFirst(8) {
                case "write", "read_write": rw = true
                case "read", "sample": break
                default: throw fail("unknown texture access '\(text)'", line: type.line)
                }
            } else if let s = builtinTypeName(text), ["float", "int", "uint", "min16float"].contains(s) {
                element = s == "min16float" ? "float" : s
            } else {
                throw fail("unsupported texture element type '\(text)'", line: type.line)
            }
        }
        if rw && t.depth { throw fail("depth textures cannot be written", line: type.line) }
        if rw && (t.cube || t.ms) { throw fail("\(type.base) cannot be written", line: type.line) }
        let elem = t.depth ? element : element + "4"
        return ((rw ? "RW" : "") + t.hlsl + "<\(elem)>", t.dims, t.array, t.cube, t.ms, t.depth, rw, elem)
    }

    /// The HLSL spelling of a value type (no address-space or resource handling).
    func hlslTypeName(_ type: MSLType) throws -> String {
        if let b = builtinTypeName(type.base) {
            if !type.templateArgs.isEmpty && type.base != "sampler" { throw fail("unexpected template arguments on '\(type.base)'", line: type.line) }
            return b
        }
        if type.base == "vec" || type.base == "matrix" {
            guard type.templateArgs.count == 2 || type.templateArgs.count == 3, let scalar = builtinTypeName(type.templateArgs[0].map(\.text).joined()) else { throw fail("unsupported `\(type.base)<...>` type", line: type.line) }
            if type.base == "vec" { return scalar + type.templateArgs[1].map(\.text).joined() }
            return scalar + type.templateArgs[2].map(\.text).joined() + "x" + type.templateArgs[1].map(\.text).joined()
        }
        if let tex = try textureInfo(type) { return tex.hlsl }
        if let s = structs[type.base] { return s.name }
        if let t = typedefs[type.base] { return t }
        if !type.templateArgs.isEmpty { throw fail("templated type '\(type.base)' is not supported", line: type.line) }
        return identifier(type.base)
    }

    // MARK: Struct roles

    mutating func assignStructRoles() throws {
        for f in functions {
            guard let kind = f.kind else { continue }
            for p in f.params where p.attrs.contains(where: { $0.name == "stage_in" }) {
                guard let s = structs[p.type.base] else { throw fail("[[stage_in]] argument must be a struct", line: p.line) }
                s.roles.insert(kind == .vertex ? .vertexInput : .varying)
            }
            if let s = structs[f.returnType.base] {
                s.roles.insert(kind == .fragment ? .fragmentOutput : .varying)
            }
        }
        for s in structs.values where !s.roles.isEmpty {
            if s.roles.contains(.vertexInput) && s.roles.count > 1 { throw fail("struct '\(s.name)' is used both as vertex input and as a stage output", line: s.line) }
            if s.roles.contains(.fragmentOutput) && s.roles.count > 1 { throw fail("struct '\(s.name)' is used both as fragment output and as a varying", line: s.line) }
            for m in s.members where m.isStructType { throw fail("nested structs in stage I/O are not supported ('\(m.name)')", line: m.line) }
        }
    }

    /// Semantic and interpolation prefix for a member of a stage I/O struct.
    func memberSemantic(_ m: MSLStructMember, role: MSLStruct.Role, counter: inout Int) throws -> (prefix: String, semantic: String) {
        var prefix = ""
        var semantic: String? = nil
        var slots = 1
        for d in m.arrayDims { slots *= Int(d) ?? 1 }
        for a in m.attrs {
            switch a.name {
            case "attribute":
                guard role == .vertexInput else { throw fail("[[attribute]] only applies to vertex input structs", line: a.line) }
                semantic = "ATTRIBUTE" + a.args.map(\.text).joined()
            case "color":
                semantic = (role == .vertexInput ? "COLOR" : "SV_Target") + a.args.map(\.text).joined()
            case "depth": semantic = "SV_Depth"
            case "user": break   // name only; linkage is by position below
            case "stage_in": break
            default:
                if let i = MSLTables.interpolation[a.name] { prefix += i.isEmpty ? "" : i + " " }
                else if let s = MSLTables.builtinSemantics[a.name] { semantic = s }
                else if let why = MSLTables.unsupportedAttributes[a.name] { throw fail(why, line: a.line) }
                else { throw fail("unknown attribute [[\(a.name)]]", line: a.line) }
            }
        }
        if semantic == nil {
            switch role {
            case .vertexInput: semantic = "ATTRIBUTE\(counter)"
            case .varying: semantic = "TEXCOORD\(counter)"
            case .fragmentOutput: semantic = "SV_Target\(counter)"
            }
            counter += slots
        }
        if role == .varying, !prefix.contains("nointerpolation"), m.type.hasPrefix("int") || m.type.hasPrefix("uint") || m.type.hasPrefix("bool") { prefix = "nointerpolation " + prefix }
        return (prefix, semantic!)
    }

    // MARK: Resources

    /// Turns entry-point arguments into HLSL parameters, globals and prologue locals.
    mutating func planResources() throws {
        for f in functions { try planFunction(f) }
        // Resource globals shared by name: identical declarations are emitted once, differing ones are mangled per function.
        var byName: [String: [(MSLFunction, Int)]] = [:]
        for f in functions { for (i, r) in f.resources.enumerated() { byName[r.mslName, default: []].append((f, i)) } }
        for (_, uses) in byName {
            let first = uses[0].0.resources[uses[0].1]
            let identical = uses.allSatisfy { $0.0.resources[$0.1].typeText == first.typeText && $0.0.resources[$0.1].registerText == first.registerText }
            if identical { continue }
            for (f, i) in uses {
                f.resources[i].hlslName = f.resources[i].hlslName + "__" + f.hlslName
                f.resources[i].symbol.rename = f.resources[i].hlslName
                f.symbols[f.resources[i].mslName] = f.resources[i].symbol
            }
        }
    }

    mutating func planFunction(_ f: MSLFunction) throws {
        for p in f.params { if p.name.isEmpty && f.body != nil { throw fail("unnamed parameters are not supported", line: p.line) } }
        f.hlslReturnType = try hlslTypeName(f.returnType)
        if f.returnType.isPointer || f.returnType.isReference { throw fail("functions cannot return pointers or references", line: f.line) }
        if let kind = f.kind {
            for a in f.funcAttrs {
                switch a.name {
                case "early_fragment_tests": f.hlslAttributes.append("[earlydepthstencil]")
                case "threads_per_threadgroup":
                    let n = a.args.filter { $0.kind == .number }.compactMap { Int($0.text) }
                    guard n.count == 3 else { throw fail("[[threads_per_threadgroup(x, y, z)]] takes three integers", line: a.line) }
                    f.threadgroupSize = (n[0], n[1], n[2])
                case "max_total_threads_per_threadgroup", "color", "position": break
                default: throw fail("unknown function attribute [[\(a.name)]]", line: a.line)
                }
            }
            switch kind {
            case .vertex:
                if f.hlslReturnType == "void" { throw fail("vertex functions must return a position or a struct", line: f.line) }
                if structs[f.returnType.base] == nil { f.returnSemantic = "SV_Position" }
            case .fragment:
                if structs[f.returnType.base] == nil && f.hlslReturnType != "void" {
                    let index = f.returnAttrs.first { $0.name == "color" }?.args.map(\.text).joined() ?? "0"
                    f.returnSemantic = f.returnAttrs.contains { $0.name == "depth" } ? "SV_Depth" : "SV_Target" + index
                }
            case .kernel:
                if f.hlslReturnType != "void" { throw fail("kernels must return void", line: f.line) }
            default: break
            }
        }
        var gridDims = 1
        var userVaryings = 0
        for p in f.params {
            let sym: MSLSymbol
            let hlslType: String
            if let tex = try textureInfo(p.type) {
                hlslType = tex.hlsl
                sym = MSLSymbol(kind: .texture, type: tex.element, texture: (tex.hlsl, tex.dims, tex.array, tex.cube, tex.ms, tex.depth, tex.rw), rename: identifier(p.name))
            } else {
                hlslType = try hlslTypeName(p.type)
                sym = MSLSymbol(kind: p.type.base == "sampler" ? .sampler : .value, type: hlslType, arrayDims: p.arrayDims, rename: identifier(p.name))
            }
            let attr = p.attrs.first
            if f.kind == nil {
                // Helper function: references become in/inout, resources pass straight through.
                if let a = attr { throw fail("attributes on helper function parameters are not supported ([[\(a.name)]])", line: a.line) }
                if p.type.isPointer {
                    if p.type.qualifiers.contains("constant") || p.type.qualifiers.contains("device") {
                        let rw = p.type.qualifiers.contains("device") && !p.type.qualifiers.contains("const")
                        f.hlslParams.append("\(rw ? "RW" : "")StructuredBuffer<\(hlslType)> \(identifier(p.name))")
                        f.symbols[p.name] = MSLSymbol(kind: .structuredBuffer, type: hlslType, rename: identifier(p.name))
                        continue
                    }
                    throw fail("pointer parameters are only supported for `constant`/`device` buffers", line: p.line)
                }
                var text = ""
                if p.type.isReference {
                    if p.type.qualifiers.contains("constant") || p.type.qualifiers.contains("const") { text = "in " } else { text = "inout " }
                }
                text += hlslType + " " + identifier(p.name) + p.arrayDims.map { "[\($0)]" }.joined()
                f.hlslParams.append(text)
                f.symbols[p.name] = sym
                continue
            }
            guard let a = attr else { throw fail("entry point argument '\(p.name)' needs an attribute such as [[stage_in]] or [[buffer(n)]]", line: p.line) }
            if p.attrs.count > 1 { throw fail("one attribute per entry point argument", line: p.attrs[1].line) }
            let index = a.args.first.flatMap { Int($0.text) }
            switch a.name {
            case "stage_in":
                guard let s = structs[p.type.base] else { throw fail("[[stage_in]] argument must be a struct", line: p.line) }
                f.hlslParams.append("\(s.name) \(identifier(p.name))")
                f.symbols[p.name] = MSLSymbol(kind: .value, type: s.name, rename: identifier(p.name))
            case "buffer":
                guard let index else { throw fail("[[buffer(n)]] needs an index", line: a.line) }
                let isConstant = p.type.qualifiers.contains("constant") || (p.type.qualifiers.contains("device") && p.type.qualifiers.contains("const"))
                guard isConstant || p.type.qualifiers.contains("device") else { throw fail("[[buffer]] arguments must be in the `constant` or `device` address space", line: p.line) }
                if p.type.isReference && isConstant {
                    // Root CBV at b<n>.
                    let isStruct = structs[p.type.base] != nil
                    let r = MSLResource(mslName: p.name, hlslName: identifier(p.name), typeText: isStruct ? "ConstantBuffer<\(hlslType)>" : hlslType, registerText: "register(b\(index))",
                                        symbol: MSLSymbol(kind: isStruct ? .constantBuffer : .value, type: hlslType, rename: identifier(p.name)), cbufferWrapped: !isStruct, line: p.line)
                    f.resources.append(r)
                    f.symbols[p.name] = r.symbol
                } else if p.type.isPointer || p.type.isReference {
                    let rw = !isConstant
                    let kind: MSLSymbol.Kind = p.type.isReference ? .rwReference : .structuredBuffer
                    let r = MSLResource(mslName: p.name, hlslName: identifier(p.name), typeText: "\(rw ? "RW" : "")StructuredBuffer<\(hlslType)>", registerText: "register(\(rw ? "u" : "t")\(index), space1)",
                                        symbol: MSLSymbol(kind: kind, type: hlslType, rename: identifier(p.name)), cbufferWrapped: false, line: p.line)
                    f.resources.append(r)
                    f.symbols[p.name] = r.symbol
                    f.usesBufferTables = true
                } else {
                    throw fail("[[buffer(n)]] arguments must be references or pointers", line: p.line)
                }
            case "texture":
                guard let index else { throw fail("[[texture(n)]] needs an index", line: a.line) }
                guard let tex = sym.texture else { throw fail("[[texture(n)]] argument must be a texture type", line: p.line) }
                let r = MSLResource(mslName: p.name, hlslName: identifier(p.name), typeText: hlslType, registerText: "register(\(tex.rw ? "u" : "t")\(index))", symbol: sym, cbufferWrapped: false, line: p.line)
                f.resources.append(r)
                f.symbols[p.name] = sym
            case "sampler":
                guard let index else { throw fail("[[sampler(n)]] needs an index", line: a.line) }
                guard p.type.base == "sampler" else { throw fail("[[sampler(n)]] argument must be a sampler", line: p.line) }
                usedSamplerSlots.insert(index)
                let r = MSLResource(mslName: p.name, hlslName: identifier(p.name), typeText: "SamplerState", registerText: "register(s\(index))", symbol: sym, cbufferWrapped: false, line: p.line)
                f.resources.append(r)
                f.symbols[p.name] = sym
            case "threads_per_threadgroup":
                // Compile-time constant from [numthreads].
                f.prologue += MSLFormatter.tokens("\(hlslType) \(identifier(p.name)) = __MSL_THREADGROUP_SIZE;", line: p.line)
                f.symbols[p.name] = sym
            case "thread_execution_width":
                f.prologue += MSLFormatter.tokens("\(hlslType) \(identifier(p.name)) = WaveGetLaneCount();", line: p.line)
                f.symbols[p.name] = sym
            case "thread_index_in_simdgroup":
                f.prologue += MSLFormatter.tokens("\(hlslType) \(identifier(p.name)) = WaveGetLaneIndex();", line: p.line)
                f.symbols[p.name] = sym
            default:
                if a.name == "user" {
                    // Bare varyings on a fragment function: TEXCOORDn by position (same order as the vertex output struct).
                    guard f.kind == .fragment else { throw fail("[[user(name)]] arguments are only supported on fragment functions", line: a.line) }
                    f.hlslParams.append("\(hlslType) \(identifier(p.name)) : TEXCOORD\(userVaryings)")
                    userVaryings += 1
                    f.symbols[p.name] = sym
                } else if let semantic = MSLTables.builtinSemantics[a.name] {
                    if a.name == "thread_position_in_grid" { gridDims = Int(String(hlslType.last ?? "1")) ?? 1 }
                    f.hlslParams.append("\(hlslType) \(identifier(p.name)) : \(semantic)")
                    f.symbols[p.name] = sym
                } else if let why = MSLTables.unsupportedAttributes[a.name] {
                    throw fail(why, line: a.line)
                } else {
                    throw fail("unknown argument attribute [[\(a.name)]]", line: a.line)
                }
            }
        }
        if f.kind == .kernel && f.threadgroupSize == nil {
            f.threadgroupSize = gridDims == 3 ? options.threadgroupSize3D : gridDims == 2 ? options.threadgroupSize2D : options.threadgroupSize1D
        }
        if let s = f.threadgroupSize {
            let text = "uint3(\(s.0), \(s.1), \(s.2))"
            f.prologue = f.prologue.map { $0.text == "__MSL_THREADGROUP_SIZE" ? MSLToken(.ident, text, $0.line) : $0 }
        }
    }

    /// `constexpr sampler`s take the lowest sampler slots no `[[sampler(n)]]` argument uses.
    mutating func assignConstexprSamplerSlots() {
        var next = 0
        for name in constexprSamplers.keys.sorted(by: { constexprSamplers[$0]!.name < constexprSamplers[$1]!.name }) {
            while usedSamplerSlots.contains(next) { next += 1 }
            constexprSamplers[name]!.slot = next
            usedSamplerSlots.insert(next)
        }
    }

    // MARK: Bodies

    mutating func translateBody(_ f: MSLFunction) throws {
        guard let body = f.body else { return }
        var ctx = BodyContext(function: f, translator: self)
        var out = f.prologue
        out += try ctx.rewrite(body)
        self = ctx.translator
        f.bodyText = MSLFormatter.format(out, indent: 1)
    }

    // MARK: Assembly

    func assemble() -> String {
        var lines: [String] = []
        lines.append("// Translated from Metal Shading Language by AppKitCross's MSLTranslator (ADR-0006).")
        lines.append("#pragma pack_matrix(column_major)")
        for (_, def) in helpers.sorted(by: { $0.key < $1.key }) { lines.append(def) }
        var emittedResources: Set<String> = []
        for d in decls {
            switch d {
            case .raw(let text): lines.append(text)
            case .global(let text): lines.append(text)
            case .structDecl(let s):
                lines.append("struct \(s.name) {")
                var counter = 0
                let role = s.roles.first
                for m in s.members {
                    var text = "    "
                    if let role, let sem = try? memberSemantic(m, role: role, counter: &counter) {
                        text += sem.prefix + m.type + " " + m.name + m.arrayDims.map { "[\($0)]" }.joined() + " : " + sem.semantic + ";"
                    } else {
                        text += m.type + " " + m.name + m.arrayDims.map { "[\($0)]" }.joined() + ";"
                    }
                    lines.append(text)
                }
                lines.append("};")
            case .function(let f):
                for r in f.resources where !emittedResources.contains(r.hlslName) {
                    emittedResources.insert(r.hlslName)
                    if r.cbufferWrapped {
                        lines.append("cbuffer __cb_\(r.hlslName) : \(r.registerText) { \(r.typeText) \(r.hlslName); };")
                    } else if r.symbol.kind == .sampler, comparisonSamplers.contains(r.mslName) {
                        lines.append("SamplerComparisonState \(r.hlslName) : \(r.registerText);")
                    } else {
                        lines.append("\(r.typeText) \(r.hlslName) : \(r.registerText);")
                    }
                }
                for name in f.constexprSamplers where !emittedResources.contains("sampler:" + name) {
                    emittedResources.insert("sampler:" + name)
                    guard let s = constexprSamplers[name] else { continue }
                    lines.append("\(comparisonSamplers.contains(name) ? "SamplerComparisonState" : "SamplerState") \(s.name) : register(s\(s.slot));")
                }
                var head = ""
                if let s = f.threadgroupSize, f.kind == .kernel { head += "[numthreads(\(s.0), \(s.1), \(s.2))]\n" }
                for a in f.hlslAttributes { head += a + "\n" }
                head += "\(f.hlslReturnType) \(f.hlslName)(\(f.hlslParams.joined(separator: ", ")))"
                if let sem = f.returnSemantic { head += " : \(sem)" }
                if f.body == nil { lines.append(head + ";") } else { lines.append(head + " {"); if !f.bodyText.isEmpty { lines.append(f.bodyText) }; lines.append("}") }
            }
        }
        for g in groupshared { lines.insert(g, at: 2) }
        return lines.joined(separator: "\n") + "\n"
    }
}

// MARK: - Body rewriting

struct BodyContext {
    let function: MSLFunction?
    var translator: Translator
    var locals: [String: MSLSymbol] = [:]
    var toks: [MSLToken] = []
    var i = 0
    var out: [MSLToken] = []

    init(function: MSLFunction?, translator: Translator) { self.function = function; self.translator = translator }

    func symbol(_ name: String) -> MSLSymbol? { locals[name] ?? function?.symbols[name] ?? translator.globals[name] }
    func fail(_ message: String, _ line: Int) -> MSLTranslationError { MSLTranslationError(line: line, message: message) }
    var line: Int { i < toks.count ? toks[i].line : (toks.last?.line ?? function?.line ?? 1) }
    func peek(_ n: Int = 0) -> MSLToken? { i + n < toks.count ? toks[i + n] : nil }
    func prev(_ n: Int = 1) -> MSLToken? { out.count >= n ? out[out.count - n] : nil }

    mutating func emit(_ text: String, _ line: Int, kind: MSLToken.Kind = .punct) { out.append(MSLToken(kind, text, line)) }
    mutating func emit(_ t: MSLToken) { out.append(t) }

    /// Rewrites a token stream: types, identifiers, intrinsics, texture methods, then matrices.
    mutating func rewrite(_ tokens: [MSLToken]) throws -> [MSLToken] {
        toks = tokens; i = 0; out = []
        try pass1()
        var result = out
        var pass = MatrixPass(context: self)
        try pass.run(&result)
        translator.helpers.merge(pass.newHelpers) { a, _ in a }
        return result
    }

    /// Reads a type at `i` if one starts there (and the following token is an identifier → declaration).
    func declarationAhead() -> Bool {
        var j = i
        let quals: Set<String> = ["const", "constant", "thread", "threadgroup", "static", "constexpr", "device"]
        while let t = peek(j - i), t.isIdent, quals.contains(t.text) { j += 1 }
        guard let t = peek(j - i), t.isIdent else { return false }
        if t.text == "metal", peek(j - i + 1)?.is("::") == true { j += 2 }
        guard let base = peek(j - i), base.isIdent else { return false }
        let known = translator.builtinTypeName(base.text) != nil || translator.structs[base.text] != nil || translator.typedefs[base.text] != nil || MSLTables.textures[base.text] != nil
        guard known else { return false }
        j += 1
        if peek(j - i)?.is("<") == true {
            var depth = 0
            while let c = peek(j - i) { j += 1; if c.is("<") { depth += 1 } else if c.is(">") { depth -= 1; if depth == 0 { break } } }
        }
        while let c = peek(j - i), c.is("*") || c.is("&") || c.is("const") { j += 1 }
        guard let name = peek(j - i), name.isIdent, !MSLTables.statementKeywords.contains(name.text) else { return false }
        return true
    }

    mutating func parseTypeHere() throws -> MSLType {
        // Reuse the translator's parser on this token slice.
        var sub = translator
        sub.tokens = toks; sub.pos = i
        let type = try sub.parseType()
        i = sub.pos
        return type
    }

    mutating func pass1() throws {
        while i < toks.count {
            let t = toks[i]
            if t.kind == .directive { throw fail("preprocessor directives inside function bodies are not supported", t.line) }
            if t.kind == .string || t.kind == .number { emit(t); i += 1; continue }
            if t.kind == .punct {
                switch t.text {
                case "&":
                    // Unary address-of
                    if let p = prev(), !(p.kind == .ident || p.kind == .number || p.is(")") || p.is("]")) { throw fail("address-of (`&`) is not supported", t.line) }
                    emit(t); i += 1
                case "->":
                    emit("[", t.line); emit("0", t.line, kind: .number); emit("]", t.line); emit(".", t.line); i += 1
                case "::":
                    throw fail("unexpected '::'", t.line)
                case "[" where peek(1)?.is("[") == true:
                    throw fail("attributes are not allowed here", t.line)
                default:
                    emit(t); i += 1
                }
                continue
            }
            // Identifiers
            if t.text == "metal" || t.text == "fast" || t.text == "precise" || t.text == "simd", peek(1)?.is("::") == true { i += 2; continue }
            if t.text == "threadgroup", function?.kind == .kernel, declarationAhead() {
                try hoistGroupshared(); continue
            }
            if declarationAhead() { try rewriteDeclaration(); continue }
            if prev()?.is(".") == true { try rewriteMember(t); continue }
            if peek(1)?.is("::") == true {
                // enum-like scopes: access::, component::, mem_flags:: etc.
                throw fail("'\(t.text)::' scopes are only supported inside texture and barrier calls", t.line)
            }
            try rewriteIdentifier(t)
        }
    }

    mutating func rewriteMember(_ t: MSLToken) throws {
        // `.name` after a texture-typed chain and followed by `(` is a method call.
        guard peek(1)?.is("(") == true else {
            emit(MSLToken(.ident, translator.identifier(t.text), t.line)); i += 1; return
        }
        let dotIndex = out.count - 1
        let chainStart = MatrixPass.operandStart(in: out, before: dotIndex)
        let chain = Array(out[chainStart..<dotIndex])
        let type = MatrixPass(context: self).infer(chain)
        guard let sym = type?.texture else {
            // Not a texture: struct member function call, which MSL has no equivalent for in the subset.
            if ["sample", "read", "write", "gather", "sample_compare", "get_width", "get_height"].contains(t.text) {
                throw fail("'.\(t.text)' on a value of unknown type; only texture arguments can be sampled", t.line)
            }
            emit(MSLToken(.ident, translator.identifier(t.text), t.line)); i += 1; return
        }
        i += 2   // name (
        let args = try collectArguments()
        switch t.text {
        case "sample", "sample_compare":
            guard args.count >= 2 else { throw fail("'.\(t.text)' needs a sampler and coordinates", t.line) }
            let samplerName = args[0].first?.text ?? ""
            var method = t.text == "sample" ? "Sample" : "SampleCmp"
            if t.text == "sample_compare" { translator.comparisonSamplers.insert(samplerName) }
            if function != nil, translator.constexprSamplers[samplerName] != nil, let f = function, !f.constexprSamplers.contains(samplerName) { f.constexprSamplers.append(samplerName) }
            var coord = args[1]
            var rest = Array(args.dropFirst(2))
            var compare: [MSLToken]? = nil
            if t.text == "sample_compare" { guard !rest.isEmpty else { throw fail("sample_compare needs a compare value", t.line) }; compare = rest.removeFirst() }
            if sym.array {
                guard !rest.isEmpty else { throw fail("array texture sampling needs a slice", t.line) }
                let slice = rest.removeFirst()
                let n = sym.cube ? 4 : sym.dims + 1
                coord = MSLFormatter.tokens("float\(n)(", line: t.line) + coord + [MSLToken(.punct, ",", t.line)] + slice + [MSLToken(.punct, ")", t.line)]
            }
            var extra: [[MSLToken]] = []
            var offset: [MSLToken]? = nil
            for r in rest {
                let head = r.first?.text ?? ""
                if r.count >= 3, r[1].is("("), ["level", "bias", "gradient2d", "gradient3d", "gradientcube", "min_lod_clamp"].contains(head) {
                    let inner = Array(r[2..<(r.count - 1)])
                    switch head {
                    case "level": method = t.text == "sample" ? "SampleLevel" : "SampleCmpLevelZero"; if t.text == "sample" { extra.append(inner) }
                    case "bias": method = "SampleBias"; extra.append(inner)
                    case "gradient2d", "gradient3d", "gradientcube":
                        method = "SampleGrad"
                        extra += MSLFormatter.splitArguments(inner)
                    default: break   // min_lod_clamp dropped
                    }
                } else {
                    offset = r
                }
            }
            if method == "SampleCmpLevelZero" && t.text == "sample_compare" {}
            if let compare { extra.insert(compare, at: 0) }
            if let offset { extra.append(offset) }
            emit(MSLToken(.ident, method, t.line)); emit("(", t.line)
            out += MSLFormatter.tokens(translator.identifier(samplerName), line: t.line)
            emit(",", t.line); out += coord
            for e in extra { emit(",", t.line); out += e }
            emit(")", t.line)
        case "read":
            guard args.count >= 1 else { throw fail("'.read' needs coordinates", t.line) }
            if sym.rw {
                // RW textures index directly.
                out.removeSubrange(dotIndex..<out.count)
                emit("[", t.line); out += args[0]; emit("]", t.line)
                return
            }
            if sym.ms {
                emit(MSLToken(.ident, "Load", t.line)); emit("(", t.line)
                out += MSLFormatter.tokens("int\(sym.dims)(", line: t.line) + args[0] + [MSLToken(.punct, ")", t.line)]
                emit(",", t.line); out += args.count > 1 ? args[1] : [MSLToken(.number, "0", t.line)]
                emit(")", t.line)
                return
            }
            let n = sym.dims + (sym.array ? 1 : 0) + 1
            emit(MSLToken(.ident, "Load", t.line)); emit("(", t.line)
            out += MSLFormatter.tokens("int\(n)(", line: t.line)
            out += args[0]
            var rest = Array(args.dropFirst())
            if sym.array { emit(",", t.line); out += rest.isEmpty ? [MSLToken(.number, "0", t.line)] : rest.removeFirst() }
            emit(",", t.line); out += rest.first ?? [MSLToken(.number, "0", t.line)]
            emit(")", t.line); emit(")", t.line)
        case "write":
            guard sym.rw else { throw fail("'.write' on a texture without access::write", t.line) }
            guard args.count >= 2 else { throw fail("'.write' needs a value and coordinates", t.line) }
            out.removeSubrange(dotIndex..<out.count)
            emit("[", t.line)
            if sym.array && args.count >= 3 {
                out += MSLFormatter.tokens("uint\(sym.dims + 1)(", line: t.line) + args[1] + [MSLToken(.punct, ",", t.line)] + args[2] + [MSLToken(.punct, ")", t.line)]
            } else {
                out += args[1]
            }
            emit("]", t.line); emit("=", t.line)
            out += args[0]
        case "gather":
            guard args.count >= 2 else { throw fail("'.gather' needs a sampler and coordinates", t.line) }
            var method = "Gather"
            for r in args.dropFirst(2) where r.count == 3 && r[0].is("component") {
                method = ["x": "GatherRed", "y": "GatherGreen", "z": "GatherBlue", "w": "GatherAlpha"][r[2].text] ?? "Gather"
            }
            emit(MSLToken(.ident, method, t.line)); emit("(", t.line)
            out += MSLFormatter.tokens(translator.identifier(args[0].first?.text ?? ""), line: t.line); emit(",", t.line); out += args[1]; emit(")", t.line)
        case "get_width", "get_height", "get_depth", "get_num_mip_levels", "get_array_size", "get_num_samples":
            let helper = try dimensionHelper(t.text, texture: sym, line: t.line)
            out.removeSubrange(dotIndex..<out.count)
            let chainTokens = Array(out[chainStart..<out.count])
            out.removeSubrange(chainStart..<out.count)
            emit(MSLToken(.ident, helper, t.line)); emit("(", t.line); out += chainTokens; emit(")", t.line)
        default:
            throw fail("texture method '.\(t.text)' is not supported", t.line)
        }
    }

    /// Emits a `uint __msl_width_Texture2D_float4(Texture2D<float4> t)` style helper once.
    mutating func dimensionHelper(_ method: String, texture: (hlsl: String, dims: Int, array: Bool, cube: Bool, ms: Bool, depth: Bool, rw: Bool), line: Int) throws -> String {
        let safe = texture.hlsl.replacingOccurrences(of: "<", with: "_").replacingOccurrences(of: ">", with: "")
        let name = "__msl_\(method)_\(safe)"
        if translator.helpers[name] != nil { return name }
        var vars = ["w"]
        if texture.dims >= 2 { vars.append("h") }
        if texture.dims == 3 { vars.append("d") }
        if texture.array { vars.append("elements") }
        if texture.ms { vars.append("samples") } else if !texture.rw { vars.append("levels") }
        let which: String
        switch method {
        case "get_width": which = "w"
        case "get_height": guard texture.dims >= 2 else { throw fail("1D textures have no height", line) }; which = "h"
        case "get_depth": guard texture.dims == 3 else { throw fail("only 3D textures have depth", line) }; which = "d"
        case "get_array_size": guard texture.array else { throw fail("not an array texture", line) }; which = "elements"
        case "get_num_samples": guard texture.ms else { throw fail("not a multisampled texture", line) }; which = "samples"
        default: guard vars.contains("levels") else { throw fail("mip levels are not available on this texture", line) }; which = "levels"
        }
        let decl = vars.map { "uint \($0)" }.joined(separator: "; ") + ";"
        let call = (texture.rw || texture.ms ? "" : "0, ") + vars.joined(separator: ", ")
        translator.helpers[name] = "uint \(name)(\(texture.hlsl) t) { \(decl) t.GetDimensions(\(call)); return \(which); }"
        return name
    }

    /// Collects call arguments after the opening `(` (already consumed) up to the matching `)`.
    mutating func collectArguments() throws -> [[MSLToken]] {
        var args: [[MSLToken]] = []
        var cur: [MSLToken] = []
        var depth = 0
        let start = line
        while i < toks.count {
            let c = toks[i]; i += 1
            if c.is("(") || c.is("[") || c.is("{") { depth += 1 }
            if c.is(")") || c.is("]") || c.is("}") {
                if depth == 0 { if !cur.isEmpty { args.append(cur) }; return try args.map { try rewriteNested($0) } }
                depth -= 1
            }
            if c.is(",") && depth == 0 { args.append(cur); cur = []; continue }
            cur.append(c)
        }
        throw fail("unterminated argument list", start)
    }

    /// Rewrites an argument expression with the same context (locals shared).
    mutating func rewriteNested(_ tokens: [MSLToken]) throws -> [MSLToken] {
        var sub = BodyContext(function: function, translator: translator)
        sub.locals = locals
        sub.toks = tokens
        try sub.pass1()
        translator = sub.translator
        locals = sub.locals
        return sub.out
    }

    mutating func hoistGroupshared() throws {
        let start = line
        i += 1 // threadgroup
        let type = try parseTypeHere()
        let hlsl = try translator.hlslTypeName(type)
        var decl = "groupshared \(hlsl)"
        guard let name = peek(), name.isIdent else { throw fail("expected a name after `threadgroup`", start) }
        i += 1
        decl += " " + translator.identifier(name.text)
        var dims: [String] = []
        while peek()?.is("[") == true {
            i += 1
            var text = ""
            while let c = peek(), !c.is("]") { text += c.text; i += 1 }
            i += 1
            dims.append(text)
            decl += "[\(text)]"
        }
        guard peek()?.is(";") == true else { throw fail("`threadgroup` variables cannot have initialisers", start) }
        i += 1
        translator.groupshared.append(decl + ";")
        locals[name.text] = MSLSymbol(kind: .value, type: hlsl, arrayDims: dims, rename: translator.identifier(name.text))
    }

    mutating func rewriteDeclaration() throws {
        let start = line
        let type = try parseTypeHere()
        if type.isPointer { throw fail("local pointers are not supported", start) }
        if type.isReference { throw fail("local references are not supported", start) }
        if type.qualifiers.contains("threadgroup") { throw fail("`threadgroup` variables are only supported in kernels", start) }
        let hlsl: String
        var texInfo: (hlsl: String, dims: Int, array: Bool, cube: Bool, ms: Bool, depth: Bool, rw: Bool, element: String)? = nil
        if let tex = try translator.textureInfo(type) { hlsl = tex.hlsl; texInfo = tex } else { hlsl = try translator.hlslTypeName(type) }
        if type.qualifiers.contains("constexpr") || type.qualifiers.contains("constant") { out += MSLFormatter.tokens("static const", line: start) }
        else if type.qualifiers.contains("static") { out += MSLFormatter.tokens("static", line: start) }
        else if type.qualifiers.contains("const") { out += MSLFormatter.tokens("const", line: start) }
        emit(MSLToken(.ident, hlsl, start))
        repeat {
            guard let name = peek(), name.isIdent else { throw fail("expected a variable name", line) }
            i += 1
            emit(MSLToken(.ident, translator.identifier(name.text), name.line))
            var dims: [String] = []
            while peek()?.is("[") == true, peek(1)?.is("[") != true {
                emit("[", name.line); i += 1
                var text = ""
                while let c = peek(), !c.is("]") { text += c.text; emit(c); i += 1 }
                emit("]", name.line); i += 1
                dims.append(text)
            }
            if let tex = texInfo {
                locals[name.text] = MSLSymbol(kind: .texture, type: tex.element, texture: (tex.hlsl, tex.dims, tex.array, tex.cube, tex.ms, tex.depth, tex.rw), rename: translator.identifier(name.text))
            } else {
                locals[name.text] = MSLSymbol(kind: type.base == "sampler" ? .sampler : .value, type: hlsl, arrayDims: dims, rename: translator.identifier(name.text))
            }
            if peek()?.is("=") == true {
                emit("=", name.line); i += 1
                if peek()?.is("{") == true, peek(1)?.is("}") == true { i += 2; out += MSLFormatter.tokens("(\(hlsl))0", line: name.line); continue }
                // Initialiser up to , or ; at depth 0, rewritten in place.
                var depth = 0
                var initTokens: [MSLToken] = []
                while let c = peek() {
                    if depth == 0 && (c.is(",") || c.is(";")) { break }
                    if c.is("(") || c.is("[") || c.is("{") { depth += 1 }
                    if c.is(")") || c.is("]") || c.is("}") { depth -= 1 }
                    initTokens.append(c); i += 1
                }
                out += try rewriteNested(initTokens)
            } else if peek()?.is("(") == true {
                throw fail("constructor-style initialisation of locals (`T x(...)`) is not supported; use `T x = T(...)`", name.line)
            }
            if peek()?.is(",") == true { emit(",", name.line); i += 1; continue }
            break
        } while true
    }

    mutating func rewriteIdentifier(_ t: MSLToken) throws {
        let name = t.text
        let callFollows = peek(1)?.is("(") == true
        if let c = MSLTables.constants[name] { out += MSLFormatter.tokens(c, line: t.line); i += 1; return }
        if name.hasPrefix("atomic_") { throw fail("atomic operations are not supported", t.line) }
        if callFollows {
            switch name {
            case "discard_fragment":
                i += 2; guard peek()?.is(")") == true else { throw fail("discard_fragment takes no arguments", t.line) }; i += 1
                emit(MSLToken(.ident, "discard", t.line)); return
            case "select":
                i += 2
                let args = try collectArguments()
                guard args.count == 3 else { throw fail("select takes (a, b, condition)", t.line) }
                emit("(", t.line); emit("(", t.line); out += args[2]; emit(")", t.line); emit("?", t.line); emit("(", t.line); out += args[1]; emit(")", t.line); emit(":", t.line); emit("(", t.line); out += args[0]; emit(")", t.line); emit(")", t.line)
                return
            case "threadgroup_barrier", "simdgroup_barrier":
                i += 2
                var flags = ""
                while let c = peek(), !c.is(")") { flags += c.text; i += 1 }
                i += 1
                let barrier = flags.contains("mem_threadgroup") && !flags.contains("mem_device") ? "GroupMemoryBarrierWithGroupSync" : flags.contains("mem_device") && !flags.contains("mem_threadgroup") ? "DeviceMemoryBarrierWithGroupSync" : "AllMemoryBarrierWithGroupSync"
                emit(MSLToken(.ident, barrier, t.line)); emit("(", t.line); emit(")", t.line)
                return
            case "unpack_unorm4x8_to_float", "unpack_unorm4x8_srgb_to_float", "pack_float_to_unorm4x8", "unpack_snorm4x8_to_float", "pack_float_to_snorm4x8":
                translator.helpers["__msl_pack"] = """
                float4 __msl_unpack_unorm4x8_to_float(uint p) { return float4(p & 0xffu, (p >> 8) & 0xffu, (p >> 16) & 0xffu, p >> 24) / 255.0; }
                uint __msl_pack_float_to_unorm4x8(float4 v) { uint4 u = uint4(round(saturate(v) * 255.0)); return u.x | (u.y << 8) | (u.z << 16) | (u.w << 24); }
                float4 __msl_unpack_snorm4x8_to_float(uint p) { int4 s = int4(int(p << 24) >> 24, int(p << 16) >> 24, int(p << 8) >> 24, int(p) >> 24); return max(float4(s) / 127.0, -1.0); }
                uint __msl_pack_float_to_snorm4x8(float4 v) { int4 s = int4(round(clamp(v, -1.0, 1.0) * 127.0)); return (uint(s.x) & 0xffu) | ((uint(s.y) & 0xffu) << 8) | ((uint(s.z) & 0xffu) << 16) | ((uint(s.w) & 0xffu) << 24); }
                """
                if name == "unpack_unorm4x8_srgb_to_float" { throw fail("sRGB unpacking is not supported", t.line) }
                emit(MSLToken(.ident, "__msl_" + name, t.line)); i += 1; return
            default: break
            }
        }
        if name == "as_type" {
            guard peek(1)?.is("<") == true else { throw fail("as_type needs a template argument", t.line) }
            i += 2
            var target = ""
            while let c = peek(), !c.is(">") { target += c.text; i += 1 }
            i += 1
            guard let hlsl = translator.builtinTypeName(target) else { throw fail("as_type<\(target)> is not supported", t.line) }
            let scalar = hlsl.trimmingCharacters(in: CharacterSet(charactersIn: "234"))
            let fn = ["float": "asfloat", "uint": "asuint", "int": "asint", "min16float": "asfloat16"][scalar]
            guard let fn, !Translator.isMatrixType(hlsl) else { throw fail("as_type<\(target)> is not supported", t.line) }
            emit(MSLToken(.ident, fn, t.line)); return
        }
        if let f = translator.functions.first(where: { $0.name == name }) { emit(MSLToken(.ident, f.hlslName, t.line)); i += 1; return }
        if let mapped = MSLTables.intrinsics[name], callFollows, symbol(name) == nil { emit(MSLToken(.ident, mapped, t.line)); i += 1; return }
        if let sym = symbol(name) {
            emit(MSLToken(.ident, sym.rename ?? translator.identifier(name), t.line)); i += 1
            if sym.kind == .rwReference { emit("[", t.line); emit("0", t.line, kind: .number); emit("]", t.line) }
            if sym.kind == .sampler, let f = function, translator.constexprSamplers[name] != nil, !f.constexprSamplers.contains(name) { f.constexprSamplers.append(name) }
            return
        }
        if let b = translator.builtinTypeName(name) {
            // Type used as a constructor or cast: single-argument vector constructors become casts.
            emit(MSLToken(.ident, b, t.line)); i += 1
            if callFollows && !Translator.isMatrixType(b) && name != "sampler" {
                i += 1
                let args = try collectArguments()
                if args.count == 1 {
                    out.removeLast()
                    emit("(", t.line); emit("(", t.line); emit(MSLToken(.ident, b, t.line)); emit(")", t.line); emit("(", t.line); out += args[0]; emit(")", t.line); emit(")", t.line)
                } else {
                    emit("(", t.line)
                    for (k, a) in args.enumerated() { if k > 0 { emit(",", t.line) }; out += a }
                    emit(")", t.line)
                }
            }
            return
        }
        if let s = translator.structs[name] { emit(MSLToken(.ident, s.name, t.line)); i += 1; return }
        if let f = translator.functions.first(where: { $0.name == name }) { emit(MSLToken(.ident, f.hlslName, t.line)); i += 1; return }
        if MSLTables.textures[name] != nil { throw fail("texture locals must be declared from arguments", t.line) }
        if name == "sizeof" { throw fail("sizeof is not supported", t.line) }
        if name == "this" || name == "new" || name == "delete" { throw fail("'\(name)' is not supported", t.line) }
        emit(MSLToken(.ident, translator.identifier(name), t.line)); i += 1
    }
}

// MARK: - Matrix pass

/// Rewrites `a * b` to `mul(a, b)` when an operand is a matrix, matrix subscripts to
/// `transpose(m)[i]` (columns), and matrix constructors to `transpose(T(...))`.
struct MatrixPass {
    let context: BodyContext
    var newHelpers: [String: String] = [:]

    static let operatorEnds: Set<String> = ["(", "[", ",", "=", "+", "-", "*", "/", "%", "<", ">", "<=", ">=", "==", "!=", "&&", "||", "!", "~", "?", ":", "+=", "-=", "*=", "/=", "&", "|", "^", "<<", ">>", ";", "{", "}", "return"]

    /// Index where the primary/postfix (plus prefix unary) operand ending at `end - 1` starts.
    static func operandStart(in toks: [MSLToken], before end: Int) -> Int {
        var k = end
        func matchBack(_ close: String, _ open: String) {
            var depth = 0
            while k > 0 {
                k -= 1
                if toks[k].is(close) { depth += 1 } else if toks[k].is(open) { depth -= 1; if depth == 0 { return } }
            }
        }
        guard k > 0 else { return end }
        // Primary
        if toks[k - 1].is(")") || toks[k - 1].is("]") {
            // nothing: handled by the chain loop below
        } else if toks[k - 1].kind == .ident || toks[k - 1].kind == .number || toks[k - 1].kind == .string {
            k -= 1
        } else { return end }
        // Postfix chain walking backwards
        while k > 0 {
            let t = toks[k - 1]
            if t.is(")") { matchBack(")", "("); if k > 0 && toks[k - 1].kind == .ident { k -= 1 }; continue }
            if t.is("]") { matchBack("]", "["); if k > 0 && toks[k - 1].kind == .ident { k -= 1 }; continue }
            if t.is(".") && k >= 2 { k -= 2; continue }
            break
        }
        // Cast `(type)` before
        if k >= 3, toks[k - 1].is(")"), toks[k - 3].is("("), toks[k - 2].kind == .ident, k - 4 < 0 || !(toks[k - 4].kind == .ident || toks[k - 4].is(")") || toks[k - 4].is("]")) {
            k -= 3
        }
        // Prefix unary
        while k > 0, toks[k - 1].is("-") || toks[k - 1].is("!") || toks[k - 1].is("~") || toks[k - 1].is("+") {
            if k >= 2 { let p = toks[k - 2]; if p.kind == .ident && !operatorEnds.contains(p.text) || p.kind == .number || p.is(")") || p.is("]") { break } }
            k -= 1
        }
        return k
    }

    /// Index one past the operand starting at `start`.
    static func operandEnd(in toks: [MSLToken], from start: Int) -> Int {
        var k = start
        func matchForward(_ open: String, _ close: String) {
            var depth = 0
            while k < toks.count {
                if toks[k].is(open) { depth += 1 } else if toks[k].is(close) { depth -= 1; if depth == 0 { k += 1; return } }
                k += 1
            }
        }
        while k < toks.count, toks[k].is("-") || toks[k].is("!") || toks[k].is("~") || toks[k].is("+") { k += 1 }
        guard k < toks.count else { return k }
        if toks[k].is("(") {
            matchForward("(", ")")
            // cast: (type) followed by operand
            if k - start >= 3, toks[k - 2].kind == .ident, toks[k - 3].is("("), k < toks.count, !(toks[k].kind == .punct && !toks[k].is("(")) {
                return operandEnd(in: toks, from: k)
            }
        } else if toks[k].kind == .ident || toks[k].kind == .number || toks[k].kind == .string {
            k += 1
        } else { return k }
        while k < toks.count {
            if toks[k].is("(") { matchForward("(", ")"); continue }
            if toks[k].is("[") { matchForward("[", "]"); continue }
            if toks[k].is("."), k + 1 < toks.count { k += 2; continue }
            break
        }
        return k
    }

    /// The HLSL type of an operand expression when it can be determined.
    func infer(_ toks: [MSLToken]) -> MSLSymbol? {
        var t = toks
        while let f = t.first, f.is("-") || f.is("!") || f.is("~") || f.is("+") { t.removeFirst() }
        guard !t.isEmpty else { return nil }
        // Cast
        if t.count >= 4, t[0].is("("), t[2].is(")"), t[1].kind == .ident, context.translator.builtinTypeName(t[1].text) != nil || Translator.isMatrixType(t[1].text) || Translator.isVectorType(t[1].text) {
            return MSLSymbol(kind: .value, type: t[1].text)
        }
        // Parenthesised
        if t[0].is("(") {
            var depth = 0, close = -1
            for (k, x) in t.enumerated() { if x.is("(") { depth += 1 } else if x.is(")") { depth -= 1; if depth == 0 { close = k; break } } }
            if close == t.count - 1 { return inferExpression(Array(t[1..<close])) }
            return nil
        }
        if t[0].kind == .number { return MSLSymbol(kind: .value, type: t[0].text.contains(".") || t[0].text.hasSuffix("f") ? "float" : "int") }
        guard t[0].kind == .ident else { return nil }
        var sym: MSLSymbol?
        var k = 1
        let head = t[0].text
        if k < t.count, t[k].is("(") {
            // Call
            var depth = 0, close = k
            for x in k..<t.count { if t[x].is("(") { depth += 1 } else if t[x].is(")") { depth -= 1; if depth == 0 { close = x; break } } }
            let args = MSLFormatter.splitArguments(Array(t[(k + 1)..<close]))
            k = close + 1
            if Translator.isMatrixType(head) || Translator.isVectorType(head) || context.translator.builtinTypeName(head) == head {
                sym = MSLSymbol(kind: .value, type: head)
            } else if let s = context.translator.structs.values.first(where: { $0.name == head }) {
                sym = MSLSymbol(kind: .value, type: s.name)
            } else if head == "mul", args.count == 2, let a = infer(args[0]), let b = infer(args[1]) {
                let am = Translator.isMatrixType(a.type), bm = Translator.isMatrixType(b.type)
                if am && bm { sym = MSLSymbol(kind: .value, type: String(a.type.dropLast(1)) + String(b.type.suffix(1))) }
                else if am { sym = MSLSymbol(kind: .value, type: Translator.rowVector(of: a.type)) }
                else if bm { sym = MSLSymbol(kind: .value, type: Translator.columnVector(of: b.type)) }
                else { sym = a }
            } else if head == "transpose", args.count == 1, let a = infer(args[0]) {
                sym = MSLSymbol(kind: .value, type: Translator.transposedMatrixName(a.type))
            } else if MSLTables.sameTypeIntrinsics.contains(head), let a = args.first, let s = infer(a) {
                sym = s
            } else if let f = context.translator.functions.first(where: { $0.hlslName == head }) {
                sym = MSLSymbol(kind: .value, type: f.hlslReturnType)
            } else {
                return nil
            }
        } else {
            guard let s = context.locals.values.first(where: { $0.rename == head }) ?? context.function?.symbols.values.first(where: { $0.rename == head }) ?? context.translator.globals.values.first(where: { $0.rename == head }) ?? context.symbol(head) else { return nil }
            sym = s
        }
        // Postfix chain
        while k < t.count, var s = sym {
            if t[k].is("[") {
                var depth = 0, close = k
                for x in k..<t.count { if t[x].is("[") { depth += 1 } else if t[x].is("]") { depth -= 1; if depth == 0 { close = x; break } } }
                k = close + 1
                if !s.arrayDims.isEmpty { s.arrayDims.removeFirst(); sym = s; continue }
                switch s.kind {
                case .structuredBuffer, .rwReference: sym = MSLSymbol(kind: .value, type: s.type)
                case .texture: sym = MSLSymbol(kind: .value, type: s.type)
                default:
                    if Translator.isMatrixType(s.type) { sym = MSLSymbol(kind: .value, type: Translator.rowVector(of: s.type)) }
                    else if Translator.isVectorType(s.type) { sym = MSLSymbol(kind: .value, type: String(s.type.dropLast())) }
                    else { return nil }
                }
                continue
            }
            if t[k].is("."), k + 1 < t.count {
                let member = t[k + 1].text
                k += 2
                if k < t.count, t[k].is("(") {
                    // method call result: unknown except textures' Sample → element
                    var depth = 0, close = k
                    for x in k..<t.count { if t[x].is("(") { depth += 1 } else if t[x].is(")") { depth -= 1; if depth == 0 { close = x; break } } }
                    k = close + 1
                    sym = s.kind == .texture ? MSLSymbol(kind: .value, type: s.type) : nil
                    continue
                }
                if s.kind == .constantBuffer || s.kind == .value, let st = context.translator.structs.values.first(where: { $0.name == s.type }), let m = st.members.first(where: { $0.name == member }) {
                    sym = MSLSymbol(kind: .value, type: m.type, arrayDims: m.arrayDims)
                } else if Translator.isVectorType(s.type) || context.translator.builtinTypeName(s.type) != nil {
                    let scalar = s.type.trimmingCharacters(in: CharacterSet(charactersIn: "234"))
                    sym = MSLSymbol(kind: .value, type: member.count == 1 ? scalar : scalar + "\(member.count)")
                } else { return nil }
                continue
            }
            break
        }
        return sym
    }

    /// The type of a full expression: a single operand, or the first operand of an additive chain.
    func inferExpression(_ toks: [MSLToken]) -> MSLSymbol? {
        let end = MatrixPass.operandEnd(in: toks, from: 0)
        if end >= toks.count { return infer(toks) }
        if toks[end].is("?") { return nil }
        return infer(Array(toks[0..<end]))
    }

    mutating func run(_ toks: inout [MSLToken]) throws {
        // Matrix constructors and subscripts first, innermost first.
        var changed = true
        var guardCount = 0
        while changed {
            changed = false
            guardCount += 1
            if guardCount > 10000 { break }
            // Constructors: T( ... ) with T a matrix type, not already wrapped by transpose or a cast.
            for k in toks.indices where toks[k].kind == .ident && Translator.isMatrixType(toks[k].text) && k + 1 < toks.count && toks[k + 1].is("(") && !(k >= 2 && toks[k - 1].is("(") && toks[k - 2].is("__msl_ctor")) {
                var depth = 0, close = k + 1
                for x in (k + 1)..<toks.count { if toks[x].is("(") { depth += 1 } else if toks[x].is(")") { depth -= 1; if depth == 0 { close = x; break } } }
                let args = MSLFormatter.splitArguments(Array(toks[(k + 2)..<close]))
                let type = toks[k].text
                let line = toks[k].line
                var replacement: [MSLToken]
                if args.count == 1 {
                    let argType = infer(args[0])
                    if let a = argType, Translator.isMatrixType(a.type) {
                        replacement = MSLFormatter.tokens("((\(type))(", line: line) + args[0] + MSLFormatter.tokens("))", line: line)
                    } else if let a = argType, !Translator.isVectorType(a.type), context.translator.builtinTypeName(a.type) != nil || a.type == "float" || a.type == "int" {
                        let helper = diagonalHelper(type)
                        replacement = MSLFormatter.tokens("\(helper)(", line: line) + args[0] + MSLFormatter.tokens(")", line: line)
                    } else {
                        throw MSLTranslationError(line: line, message: "ambiguous single-argument matrix constructor \(type)(...): pass a scalar literal or a matrix")
                    }
                } else {
                    // Column-list or column-major scalar list: build the transposed HLSL matrix then transpose.
                    let inner = Translator.transposedMatrixName(type)
                    replacement = MSLFormatter.tokens("transpose(__msl_ctor(\(inner)(", line: line)
                    for (n, a) in args.enumerated() { if n > 0 { replacement.append(MSLToken(.punct, ",", line)) }; replacement += a }
                    replacement += MSLFormatter.tokens(")))", line: line)
                }
                toks.replaceSubrange(k...close, with: replacement)
                changed = true
                break
            }
        }
        // Remove the __msl_ctor markers (they only stop re-processing).
        var cleaned: [MSLToken] = []
        var skipParen = 0
        var depthStack: [Int] = []
        var depth = 0
        for t in toks {
            if t.is("__msl_ctor") { skipParen += 1; continue }
            if t.is("(") {
                depth += 1
                if skipParen > 0 { skipParen -= 1; depthStack.append(depth); continue }
            } else if t.is(")") {
                if let d = depthStack.last, d == depth { depthStack.removeLast(); depth -= 1; continue }
                depth -= 1
            }
            cleaned.append(t)
        }
        toks = cleaned
        // Subscripts on matrices → transpose(m)[i]
        var k = 0
        while k < toks.count {
            if toks[k].is("["), k > 0 {
                let start = MatrixPass.operandStart(in: toks, before: k)
                let chain = Array(toks[start..<k])
                if let s = infer(chain), Translator.isMatrixType(s.type), s.arrayDims.isEmpty, !(chain.first?.is("transpose") ?? false) {
                    let line = toks[k].line
                    toks.replaceSubrange(start..<k, with: MSLFormatter.tokens("transpose(", line: line) + chain + [MSLToken(.punct, ")", line)])
                    k += 3
                }
            }
            k += 1
        }
        // Multiplication: deepest parentheses first, left to right.
        try rewriteMultiplications(&toks)
    }

    mutating func diagonalHelper(_ type: String) -> String {
        let name = "__msl_diag_\(type)"
        if context.translator.helpers[name] == nil && newHelpers[name] == nil {
            let x = type.lastIndex(of: "x")!
            let r = Int(String(type[type.index(before: x)]))!, c = Int(String(type[type.index(after: x)]))!
            var elems: [String] = []
            for i in 0..<r { for j in 0..<c { elems.append(i == j ? "s" : "0") } }
            newHelpers[name] = "\(type) \(name)(float s) { return \(type)(\(elems.joined(separator: ", "))); }"
        }
        return name
    }

    func rewriteMultiplications(_ toks: inout [MSLToken]) throws {
        var done = false
        var passes = 0
        while !done {
            passes += 1
            if passes > 10000 { break }
            done = true
            // Find the `*` with the greatest paren depth; ties → leftmost.
            var best = -1, bestDepth = -1, depth = 0
            for (k, t) in toks.enumerated() {
                if t.is("(") || t.is("[") { depth += 1 } else if t.is(")") || t.is("]") { depth -= 1 }
                else if t.is("*"), !(k > 0 && MatrixPass.operatorEnds.contains(toks[k - 1].text) && toks[k - 1].kind == .punct), depth > bestDepth, !alreadyMul(toks, k) { best = k; bestDepth = depth }
            }
            guard best >= 0 else { break }
            let k = best
            let ls = MatrixPass.operandStart(in: toks, before: k)
            let re = MatrixPass.operandEnd(in: toks, from: k + 1)
            guard ls < k, re > k + 1 else { markMul(&toks, k); done = false; continue }
            let left = Array(toks[ls..<k]), right = Array(toks[(k + 1)..<re])
            let lt = infer(left), rt = infer(right)
            let leftMatrix = lt.map { Translator.isMatrixType($0.type) && $0.arrayDims.isEmpty } ?? false
            let rightMatrix = rt.map { Translator.isMatrixType($0.type) && $0.arrayDims.isEmpty } ?? false
            if leftMatrix || rightMatrix {
                let line = toks[k].line
                var rep = MSLFormatter.tokens("mul(", line: line)
                rep += left; rep.append(MSLToken(.punct, ",", line)); rep += right; rep.append(MSLToken(.punct, ")", line))
                toks.replaceSubrange(ls..<re, with: rep)
            } else {
                markMul(&toks, k)
            }
            done = false
        }
        // Restore marked `*`
        for k in toks.indices where toks[k].text == "\u{1}*" { toks[k].text = "*" }
    }
    func alreadyMul(_ toks: [MSLToken], _ k: Int) -> Bool { toks[k].text == "\u{1}*" }
    func markMul(_ toks: inout [MSLToken], _ k: Int) { toks[k].text = "\u{1}*" }
}

extension Translator {
    /// `float4x3` (4 rows, 3 columns) × float3 → float4.
    static func rowVector(of matrix: String) -> String {
        guard let x = matrix.lastIndex(of: "x") else { return matrix }
        return String(matrix[..<matrix.index(before: x)]) + String(matrix[matrix.index(before: x)])
    }
    /// float4 × `float4x3` → float3.
    static func columnVector(of matrix: String) -> String {
        guard let x = matrix.lastIndex(of: "x") else { return matrix }
        return String(matrix[..<matrix.index(before: x)]) + String(matrix[matrix.index(after: x)])
    }
}

// MARK: - Formatting

enum MSLFormatter {
    static func tokens(_ text: String, line: Int) -> [MSLToken] {
        (try? MSLLexer.tokenize(text))?.map { MSLToken($0.kind, $0.text, line) } ?? []
    }

    static func splitArguments(_ toks: [MSLToken]) -> [[MSLToken]] {
        var args: [[MSLToken]] = []
        var cur: [MSLToken] = []
        var depth = 0
        for t in toks {
            if t.is("(") || t.is("[") || t.is("{") { depth += 1 }
            if t.is(")") || t.is("]") || t.is("}") { depth -= 1 }
            if t.is(",") && depth == 0 { args.append(cur); cur = []; continue }
            cur.append(t)
        }
        if !cur.isEmpty || !args.isEmpty { args.append(cur) }
        return args
    }

    static func join(_ toks: [MSLToken]) -> String {
        var s = ""
        var prev: MSLToken? = nil
        var prevPrev: MSLToken? = nil
        let noSpaceBefore: Set<String> = [",", ";", ")", "]", ".", "(", "[", "++", "--"]
        let noSpaceAfter: Set<String> = ["(", "[", ".", "!", "~"]
        let unaryContext: Set<String> = ["(", "[", ",", "=", "return", "+", "-", "*", "/", "<", ">", "<=", ">=", "==", "!=", "&&", "||", "?", ":", "+=", "-=", "*=", "/=", "{", ";"]
        for t in toks {
            if let p = prev {
                var space = true
                if noSpaceBefore.contains(t.text) && t.kind == .punct { space = false }
                if t.is("(") && !(p.kind == .ident || p.is(")") || p.is("]")) { space = true }
                if t.is("(") && p.kind == .ident && MSLTables.statementKeywords.contains(p.text) { space = true }
                if t.is("[") && !(p.kind == .ident || p.is(")") || p.is("]")) { space = true }
                if noSpaceAfter.contains(p.text) && p.kind == .punct { space = false }
                // Unary sign: no space after `-`/`+` when nothing operand-like precedes it.
                if p.is("-") || p.is("+") {
                    let unary = prevPrev.map { pp in pp.kind == .punct ? unaryContext.contains(pp.text) : pp.kind == .ident && unaryContext.contains(pp.text) } ?? true
                    if unary { space = false }
                }
                if space { s += " " }
            }
            s += t.text
            prevPrev = prev
            prev = t
        }
        return s
    }

    /// Statements one per line, indented by brace depth.
    static func format(_ toks: [MSLToken], indent: Int) -> String {
        var lines: [String] = []
        var cur: [MSLToken] = []
        var depth = indent
        var paren = 0
        func flush() {
            if cur.isEmpty { return }
            lines.append(String(repeating: "    ", count: depth) + join(cur))
            cur = []
        }
        for t in toks {
            if t.is("(") { paren += 1 } else if t.is(")") { paren -= 1 }
            if t.is("{") { cur.append(t); flush(); depth += 1; continue }
            if t.is("}") { flush(); depth = max(indent, depth - 1); cur.append(t); flush(); continue }
            cur.append(t)
            if t.is(";") && paren == 0 { flush() }
        }
        flush()
        return lines.joined(separator: "\n")
    }
}
