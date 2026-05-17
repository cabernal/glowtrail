const builtin = @import("builtin");
const math = @import("math.zig");
const sokol = @import("sokol");
const sg = sokol.gfx;

pub const MaxSparks: usize = 768;
pub const SparkVerticesPerParticle: usize = 6;
pub const MaxSparkVertices: usize = MaxSparks * SparkVerticesPerParticle;

pub const SparkParticle = struct {
    active: bool = false,
    pos: math.Vec2 = .{},
    vel: math.Vec2 = .{},
    life: f32 = 0.0,
    max_life: f32 = 1.0,
    radius: f32 = 4.0,
    color: [4]f32 = .{ 1.0, 0.72, 0.20, 1.0 },
};

pub const SparkVertex = extern struct {
    position: [2]f32,
    uv: [2]f32,
    color: [4]f32,
    life: f32,
};

pub fn sparkShaderDesc() sg.ShaderDesc {
    var desc: sg.ShaderDesc = .{};
    desc.vertex_func.source = sparkVertexShaderSource();
    desc.fragment_func.source = sparkFragmentShaderSource();
    if (usesMetalBackend()) {
        desc.vertex_func.entry = "vs_main";
        desc.fragment_func.entry = "fs_main";
    }
    desc.attrs[0] = .{ .base_type = .FLOAT, .glsl_name = "position", .hlsl_sem_name = "POSITION" };
    desc.attrs[1] = .{ .base_type = .FLOAT, .glsl_name = "uv0", .hlsl_sem_name = "TEXCOORD", .hlsl_sem_index = 0 };
    desc.attrs[2] = .{ .base_type = .FLOAT, .glsl_name = "color0", .hlsl_sem_name = "COLOR" };
    desc.attrs[3] = .{ .base_type = .FLOAT, .glsl_name = "life0", .hlsl_sem_name = "TEXCOORD", .hlsl_sem_index = 1 };
    desc.label = "grind-spark-shader";
    return desc;
}

fn sparkVertexShaderSource() [*c]const u8 {
    return if (usesMetalBackend())
        MetalSparkVs.ptr
    else if (builtin.target.os.tag == .emscripten)
        GlesSparkVs.ptr
    else
        GlCoreSparkVs.ptr;
}

fn sparkFragmentShaderSource() [*c]const u8 {
    return if (usesMetalBackend())
        MetalSparkFs.ptr
    else if (builtin.target.os.tag == .emscripten)
        GlesSparkFs.ptr
    else
        GlCoreSparkFs.ptr;
}

fn usesMetalBackend() bool {
    return builtin.target.os.tag.isDarwin();
}

const MetalSparkVs =
    \\#include <metal_stdlib>
    \\using namespace metal;
    \\
    \\struct VsIn {
    \\    float2 position [[attribute(0)]];
    \\    float2 uv0 [[attribute(1)]];
    \\    float4 color0 [[attribute(2)]];
    \\    float life0 [[attribute(3)]];
    \\};
    \\
    \\struct VsOut {
    \\    float4 position [[position]];
    \\    float2 uv0;
    \\    float4 color0;
    \\    float life0;
    \\};
    \\
    \\vertex VsOut vs_main(VsIn in [[stage_in]]) {
    \\    VsOut out;
    \\    out.position = float4(in.position, 0.0, 1.0);
    \\    out.uv0 = in.uv0;
    \\    out.color0 = in.color0;
    \\    out.life0 = in.life0;
    \\    return out;
    \\}
;

const MetalSparkFs =
    \\#include <metal_stdlib>
    \\using namespace metal;
    \\
    \\struct FsIn {
    \\    float4 position [[position]];
    \\    float2 uv0;
    \\    float4 color0;
    \\    float life0;
    \\};
    \\
    \\static float hash21(float2 p) {
    \\    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
    \\}
    \\
    \\fragment float4 fs_main(FsIn in [[stage_in]]) {
    \\    float2 p = in.uv0 * 2.0 - 1.0;
    \\    float d = length(p);
    \\    float core = smoothstep(1.0, 0.06, d);
    \\    float streak = smoothstep(0.22, 0.0, abs(p.y)) * smoothstep(1.05, 0.08, abs(p.x));
    \\    float grain = hash21(floor((in.uv0 + in.life0) * 14.0));
    \\    float burn = max(core, streak * 0.74) * (0.78 + grain * 0.28);
    \\    float flash = 0.74 + sin(in.life0 * 24.0 + grain * 5.0) * 0.18;
    \\    float alpha = burn * in.color0.a * in.life0;
    \\    float3 color = in.color0.rgb * (1.1 + burn * 1.8) + float3(1.0, 0.80, 0.32) * core * flash;
    \\    return float4(color, alpha);
    \\}
;

const GlesSparkVs =
    \\#version 300 es
    \\precision mediump float;
    \\layout(location=0) in vec2 position;
    \\layout(location=1) in vec2 uv0;
    \\layout(location=2) in vec4 color0;
    \\layout(location=3) in float life0;
    \\out vec2 v_uv0;
    \\out vec4 v_color0;
    \\out float v_life0;
    \\void main() {
    \\    gl_Position = vec4(position, 0.0, 1.0);
    \\    v_uv0 = uv0;
    \\    v_color0 = color0;
    \\    v_life0 = life0;
    \\}
;

const GlesSparkFs =
    \\#version 300 es
    \\precision mediump float;
    \\in vec2 v_uv0;
    \\in vec4 v_color0;
    \\in float v_life0;
    \\out vec4 frag_color;
    \\float hash21(vec2 p) {
    \\    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
    \\}
    \\void main() {
    \\    vec2 p = v_uv0 * 2.0 - 1.0;
    \\    float d = length(p);
    \\    float core = smoothstep(1.0, 0.06, d);
    \\    float streak = smoothstep(0.22, 0.0, abs(p.y)) * smoothstep(1.05, 0.08, abs(p.x));
    \\    float grain = hash21(floor((v_uv0 + v_life0) * 14.0));
    \\    float burn = max(core, streak * 0.74) * (0.78 + grain * 0.28);
    \\    float flash = 0.74 + sin(v_life0 * 24.0 + grain * 5.0) * 0.18;
    \\    float alpha = burn * v_color0.a * v_life0;
    \\    vec3 color = v_color0.rgb * (1.1 + burn * 1.8) + vec3(1.0, 0.80, 0.32) * core * flash;
    \\    frag_color = vec4(color, alpha);
    \\}
;

const GlCoreSparkVs =
    \\#version 330
    \\layout(location=0) in vec2 position;
    \\layout(location=1) in vec2 uv0;
    \\layout(location=2) in vec4 color0;
    \\layout(location=3) in float life0;
    \\out vec2 v_uv0;
    \\out vec4 v_color0;
    \\out float v_life0;
    \\void main() {
    \\    gl_Position = vec4(position, 0.0, 1.0);
    \\    v_uv0 = uv0;
    \\    v_color0 = color0;
    \\    v_life0 = life0;
    \\}
;

const GlCoreSparkFs =
    \\#version 330
    \\in vec2 v_uv0;
    \\in vec4 v_color0;
    \\in float v_life0;
    \\out vec4 frag_color;
    \\float hash21(vec2 p) {
    \\    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
    \\}
    \\void main() {
    \\    vec2 p = v_uv0 * 2.0 - 1.0;
    \\    float d = length(p);
    \\    float core = smoothstep(1.0, 0.06, d);
    \\    float streak = smoothstep(0.22, 0.0, abs(p.y)) * smoothstep(1.05, 0.08, abs(p.x));
    \\    float grain = hash21(floor((v_uv0 + v_life0) * 14.0));
    \\    float burn = max(core, streak * 0.74) * (0.78 + grain * 0.28);
    \\    float flash = 0.74 + sin(v_life0 * 24.0 + grain * 5.0) * 0.18;
    \\    float alpha = burn * v_color0.a * v_life0;
    \\    vec3 color = v_color0.rgb * (1.1 + burn * 1.8) + vec3(1.0, 0.80, 0.32) * core * flash;
    \\    frag_color = vec4(color, alpha);
    \\}
;
