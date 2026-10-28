# ADR-0006: Metal Shading Language is translated to HLSL at the source level

Status: accepted. Date: 2026-10-28. Extends ADR-0004.

## Decision

`Sources/Metal/MSLTranslator.swift` is a pure-Swift source-to-source translator from the
practical MSL subset to HLSL. `MTLDevice.makeLibrary(source:options:)` on every device
detects the dialect (`MTLCompileOptions.shaderLanguage`, else `MSLTranslator.detectLanguage`:
`metal_stdlib`, `using namespace metal`, `[[...]]` or `vertex`/`fragment`/`kernel`
qualifiers mean MSL; semantics, `cbuffer` and `register(` mean HLSL), translates MSL and
compiles the HLSL as before. Function names stay the MSL names, so
`makeFunction(name:)` and pipeline descriptors are unchanged; the library exposes the
translated text (`hlslSource`) and the `MSLTranslation` for diagnostics. The reference
device goes through the same path, so the macOS/Linux test run rejects what the D3D12
device would reject. HLSL sources keep the HLSL-first behaviour of ADR-0004.

The target is HLSL that dxc compiles at shader model 6.0 and d3dcompiler at 5.1; shader
model 6 constructs are only emitted for MSL features that have no 5.1 equivalent
(`simd_*` → `Wave*`, `int64_t`, `SV_Barycentrics`).

## Conventions

Binding model (mirrors the D3D12 shim's root signature: root CBVs b0..b7 per stage, an
SRV table t0..t7 and a sampler table s0..s7 per stage):

| MSL argument | HLSL |
| --- | --- |
| `constant T& x [[buffer(n)]]` (struct `T`) | `ConstantBuffer<T> x : register(bn)` |
| `constant float4& x [[buffer(n)]]` (non-struct) | `cbuffer __cb_x : register(bn) { float4 x; }` |
| `constant T* x` / `const device T* x [[buffer(n)]]` | `StructuredBuffer<T> x : register(tn, space1)` |
| `device T* x` / `device T& x [[buffer(n)]]` | `RWStructuredBuffer<T> x : register(un, space1)` (`x->m`, `x.m` → `x[0].m`) |
| `texture2d<float> t [[texture(n)]]` | `Texture2D<float4> t : register(tn)` (1d/2d/3d/cube/array/ms, `depth2d` → `Texture2D<float>`) |
| `texture2d<float, access::write> t [[texture(n)]]` | `RWTexture2D<float4> t : register(un)` |
| `sampler s [[sampler(n)]]` | `SamplerState s : register(sn)` (`SamplerComparisonState` when used by `sample_compare`) |
| `constexpr sampler s(...)` | `SamplerState s : register(sN)`, N = lowest slot no `[[sampler(n)]]` uses; the device binds the parsed descriptor when the pipeline is set |
| `threadgroup T x[N];` inside a kernel | `groupshared T x[N];` at file scope |

Resource globals are emitted once when every entry point declares them identically,
otherwise mangled as `name__function`. `space1` is the translator's convention for
pointer-style buffers; the shim does not bind it yet (see Consequences), and the D3D12
device rejects such pipelines with a clear message.

Stages and semantics: `vertex`/`fragment`/`kernel` become plain HLSL functions (the MSL
name, with a trailing `_` when it is an HLSL keyword; `MSLTranslation.Function.entryPoint`
carries it). `[[position]]` → `SV_Position`, `[[color(n)]]` → `SV_Target n`, `[[depth]]`
→ `SV_Depth`, `[[vertex_id]]` → `SV_VertexID`, `[[instance_id]]` → `SV_InstanceID`,
`[[front_facing]]` → `SV_IsFrontFace`, `[[sample_id]]` → `SV_SampleIndex`,
`[[primitive_id]]` → `SV_PrimitiveID`, `[[point_size]]` → `PSIZE` (ignored by D3D12),
`[[clip_distance]]` → `SV_ClipDistance`, `[[thread_position_in_grid]]` →
`SV_DispatchThreadID`, `[[thread_position_in_threadgroup]]` → `SV_GroupThreadID`,
`[[threadgroup_position_in_grid]]` → `SV_GroupID`, `[[thread_index_in_threadgroup]]` →
`SV_GroupIndex`, `[[threads_per_threadgroup]]` → a local from `[numthreads]`. Struct
members are given semantics by role: `[[attribute(n)]]` → `ATTRIBUTEn` in vertex input
structs (the shim declares vertex attributes under both `ATTRIBUTEn` and `TEXCOORDn`),
unattributed members of varying structs → `TEXCOORDk` by position (`[[user(name)]]` is
accepted; linkage is positional, so use the same struct for both stages or keep the
order), unattributed members of fragment output structs → `SV_Targetk`. Integer varyings
get `nointerpolation`; `[[flat]]`, `[[center_no_perspective]]`, `[[centroid_*]]` and
`[[sample_*]]` map to the HLSL modifiers. `[[early_fragment_tests]]` →
`[earlydepthstencil]`.

Kernels get `[numthreads(x, y, z)]` from the translator extension
`[[threads_per_threadgroup(x, y, z)]]` on the function, or a default by the dimension of
the `thread_position_in_grid` argument (64×1×1, 8×8×1, 4×4×4; `MSLTranslator.Options`).
`threadgroup_barrier(mem_flags::mem_threadgroup)` → `GroupMemoryBarrierWithGroupSync()`,
`mem_device` → `DeviceMemoryBarrierWithGroupSync()`, anything else → `AllMemoryBarrierWithGroupSync()`.

Types: `half` → `float` (`Options.halfType = .min16float` keeps the hint; `1.0h` literals
drop the suffix), `short`/`ushort`/`char`/`uchar` → `int`/`uint`, `long`/`ulong` →
`int64_t`/`uint64_t`, `packed_floatN` → `floatN`, `size_t` → `uint`. Single-argument
vector constructors become casts (`float3(x)` → `((float3)(x))`) so scalar splats and
truncations compile on d3dcompiler too.

Matrices keep Metal's column-major storage: the output starts with
`#pragma pack_matrix(column_major)`, so a `float4x4` in a constant buffer has the same
bytes on both APIs. The translator infers operand types from declared locals, arguments,
struct members and constructors, and:

- `a * b` with a matrix operand → `mul(a, b)` (operand order preserved: `m * v`, `v * m`
  and `m1 * m2` all keep Metal's meaning);
- MSL `floatCxR` (C columns of R rows) → HLSL `floatRxC` (same storage);
- `m[i]` on a matrix (a column in MSL, a row in HLSL) → `transpose(m)[i]`;
- `floatNxM(c0, c1, ...)` and scalar-list constructors (column-major in MSL, row-major in
  HLSL) → `transpose(floatMxN(...))`;
- `float4x4(s)` with a scalar → a generated `__msl_diag_float4x4(s)` helper;
  `float3x3(m)` with a matrix → `((float3x3)(m))`.

When neither operand's type can be inferred the `*` is left alone (an unknown type is
never a matrix in the supported subset).

Intrinsics: `fract` → `frac`, `mix` → `lerp`, `dfdx`/`dfdy` → `ddx`/`ddy`, `fma` → `mad`,
`rint` → `round`, `popcount` → `countbits`, `ctz` → `firstbitlow`, `fmin`/`fmax`/`fabs`
→ `min`/`max`/`abs`, `select(a, b, c)` → `((c) ? (b) : (a))`, `discard_fragment()` →
`discard`, `as_type<T>(x)` → `asfloat`/`asuint`/`asint`, `metal::`/`fast::`/`precise::`
prefixes are dropped, `M_PI_F`-style constants and `FLT_MAX`/`INFINITY`/`NAN` become
literals, `pack_float_to_unorm4x8`/`unpack_unorm4x8_to_float` (and the snorm pair) become
generated helpers, `simd_sum`/`simd_min`/`simd_max`/`simd_broadcast_first`/`simd_is_first`
become `Wave*` (shader model 6). Texture methods: `.sample(s, uv)` → `.Sample(s, uv)`,
`level(l)`/`bias(b)`/`gradient2d(dx, dy)` modifiers → `SampleLevel`/`SampleBias`/
`SampleGrad`, an offset argument is passed through, array textures fold the slice into
the coordinate, `.sample_compare` → `SampleCmp`, `.gather` → `Gather`/`GatherRed`…,
`.read(c [, lod])` → `.Load(int3(c, lod))` (RW textures: `t[c]`), `.write(v, c)` →
`t[c] = v`, `get_width()` and friends → generated `GetDimensions` helpers.

Identifiers that are HLSL keywords (`in`, `out`, `sample`, `linear`, `texture`,
`matrix`, …) are renamed with a trailing underscore everywhere, entry points included.

## Rejected constructs

The translator throws `MSLTranslationError` with the 1-based line rather than emitting
HLSL it cannot vouch for: templates, classes, namespaces (other than `using namespace
metal`), enums, `#include` of anything but `metal_stdlib`/`simd`, preprocessor
directives inside bodies, `atomic_*` types and functions, `array<>`,
`texture_buffer`, ray tracing and function tables, `visible`/`mesh`/`object` functions,
function constants, `[[base_vertex]]`/`[[base_instance]]` (shader model 6.8),
`[[point_coord]]`, `[[threads_per_grid]]`/`[[threadgroups_per_grid]]`, threadgroup
pointer arguments, address-of and local pointers, entry-point arguments without an
attribute, structs used both as vertex input and stage output, nested structs in stage
I/O, texture methods on values of unknown type, ambiguous single-argument matrix
constructors, and `T x(...)` constructor-style locals (use `T x = T(...)`).

## Consequences

- Metal apps can ship MSL only: HelloWindow's `--metal-msl` draws the triangle from MSL
  and `--metal-selftest` renders an MSL pipeline offscreen next to the HLSL one.
- The D3D12 shim needs two additions to run the rest of the subset: a buffer SRV/UAV
  table in `register space1` (for pointer-style `[[buffer(n)]]` arguments) and a compute
  pipeline/dispatch path (`cm_pipeline_create_compute`, `cm_commandlist_dispatch`,
  `cm_commandlist_set_compute_*`). Until then `makeRenderPipelineState` rejects
  functions that use `space1` and `makeComputePipelineState` stays unsupported.
- `constexpr sampler`s are bound by the Swift side from the parsed descriptor through
  the existing `cm_commandlist_set_sampler` when `setRenderPipelineState` runs, so they
  need no shim change; an app binding its own sampler at the same slot afterwards wins.
- Translation is textual and single-pass per body: it does not type-check, so HLSL
  compile errors can still come back from dxc for code the translator passed through
  (line numbers in those refer to the translated text, available as `hlslSource`).
