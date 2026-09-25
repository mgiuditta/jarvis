#include <metal_stdlib>
using namespace metal;

struct OrbUniforms {
    float  time;
    float  energy;     // 0…1 overall activity (state + audio)
    float  speed;      // noise animation speed
    float  swirl;      // thinking: stronger inner bands
    float4 levels;     // x overall, y low, z mid, w high (FFT)
    float4 color;      // rgb
    float2 size;       // drawable px
};

struct VOut { float4 pos [[position]]; float2 uv; };

vertex VOut fullscreen(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);          // big triangle covering the viewport
    VOut o; o.pos = float4(p * 2 - 1, 0, 1); o.uv = float2(p.x, 1 - p.y); return o;
}

// --- 3D simplex noise (Ashima Arts / Stefan Gustavson, MIT) ---
static float3 mod289(float3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
static float4 mod289(float4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
static float4 permute(float4 x) { return mod289(((x * 34.0) + 1.0) * x); }
static float4 taylorInvSqrt(float4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

static float snoise(float3 v) {
    const float2 C = float2(1.0 / 6.0, 1.0 / 3.0);
    const float4 D = float4(0.0, 0.5, 1.0, 2.0);
    float3 i = floor(v + dot(v, C.yyy));
    float3 x0 = v - i + dot(i, C.xxx);
    float3 g = step(x0.yzx, x0.xyz);
    float3 l = 1.0 - g;
    float3 i1 = min(g.xyz, l.zxy);
    float3 i2 = max(g.xyz, l.zxy);
    float3 x1 = x0 - i1 + C.xxx;
    float3 x2 = x0 - i2 + C.yyy;
    float3 x3 = x0 - D.yyy;
    i = mod289(i);
    float4 p = permute(permute(permute(i.z + float4(0.0, i1.z, i2.z, 1.0)) + i.y + float4(0.0, i1.y, i2.y, 1.0)) + i.x + float4(0.0, i1.x, i2.x, 1.0));
    float n_ = 0.142857142857;
    float3 ns = n_ * D.wyz - D.xzx;
    float4 j = p - 49.0 * floor(p * ns.z * ns.z);
    float4 x_ = floor(j * ns.z);
    float4 y_ = floor(j - 7.0 * x_);
    float4 x = x_ * ns.x + ns.yyyy;
    float4 y = y_ * ns.x + ns.yyyy;
    float4 h = 1.0 - abs(x) - abs(y);
    float4 b0 = float4(x.xy, y.xy);
    float4 b1 = float4(x.zw, y.zw);
    float4 s0 = floor(b0) * 2.0 + 1.0;
    float4 s1 = floor(b1) * 2.0 + 1.0;
    float4 sh = -step(h, float4(0.0));
    float4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    float4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
    float3 p0 = float3(a0.xy, h.x);
    float3 p1 = float3(a0.zw, h.y);
    float3 p2 = float3(a1.xy, h.z);
    float3 p3 = float3(a1.zw, h.w);
    float4 norm = taylorInvSqrt(float4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
    p0 *= norm.x; p1 *= norm.y; p2 *= norm.z; p3 *= norm.w;
    float4 m = max(0.6 - float4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
    m = m * m;
    return 42.0 * dot(m * m, float4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

// Holographic sphere: noise-displaced silhouette, fresnel rim, inner bands, scanlines. Premultiplied alpha.
fragment float4 orbScene(VOut in [[stage_in]], constant OrbUniforms& u [[buffer(0)]]) {
    float2 p = in.uv * 2 - 1;
    p.x *= u.size.x / u.size.y;
    float t = u.time * u.speed;
    float len = length(p);
    float2 dir = len > 0 ? p / len : float2(0, 1);

    float amp = 0.035 + 0.16 * u.energy + 0.10 * u.levels.y;
    float edgeNoise = snoise(float3(dir * 1.6, t * 0.5)) + 0.5 * snoise(float3(dir * 3.5, t * 0.9 + 7.0)) * (0.4 + u.levels.w);
    float radius = 0.56 * (1.0 + amp * edgeNoise) * (1.0 + 0.06 * u.levels.x);
    float3 col = u.color.rgb;

    // Soft halo outside the sphere (the bloom pass adds the wide glow).
    float halo = exp(-max(len - radius, 0.0) * 9.0) * (0.25 + 0.5 * u.energy);
    float inside = smoothstep(radius + 0.01, radius - 0.01, len);
    if (inside <= 0.0) return float4(col * halo, halo) * 0.8;

    float r = min(len / radius, 1.0);
    float3 n = float3(p / radius, sqrt(1.0 - r * r));
    float fresnel = pow(1.0 - n.z, 2.2);
    float bands = snoise(n * (2.2 + 2.0 * u.swirl) + float3(0, 0, t * 0.6));
    bands = 0.5 + 0.5 * sin(bands * (6.0 + 8.0 * u.swirl) + t * 1.5);
    float scan = 0.92 + 0.08 * sin(in.uv.y * u.size.y * 0.9 + u.time * 6.0);
    float core = exp(-r * r * 3.0) * (0.25 + 0.9 * u.levels.z + 0.4 * u.energy);

    float3 rgb = col * (0.12 + 0.45 * bands * (0.4 + u.energy)) * scan
               + col * fresnel * (1.4 + 1.5 * u.levels.x)
               + mix(col, float3(1), 0.6) * core;
    float a = clamp(0.35 + 0.65 * fresnel + 0.3 * bands + core, 0.0, 1.0) * inside;
    return float4(rgb * inside, a) + float4(col * halo, halo) * (1.0 - inside) * 0.8;
}

// Separable 9-tap gaussian; writes into a half-res target, so the first pass also downsamples.
fragment float4 blur(VOut in [[stage_in]], texture2d<float> src [[texture(0)]], constant float2& dir [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    const float w[5] = { 0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216 };
    float2 texel = dir / float2(src.get_width(), src.get_height());
    float4 c = src.sample(s, in.uv) * w[0];
    for (int i = 1; i < 5; i++) {
        c += src.sample(s, in.uv + texel * float(i) * 1.5) * w[i];
        c += src.sample(s, in.uv - texel * float(i) * 1.5) * w[i];
    }
    return c;
}

fragment float4 composite(VOut in [[stage_in]], texture2d<float> scene [[texture(0)]], texture2d<float> glow [[texture(1)]],
                          constant float& strength [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 c = scene.sample(s, in.uv) + glow.sample(s, in.uv) * strength;
    return float4(min(c.rgb, float3(c.a + 0.2)), min(c.a, 1.0));   // keep premultiplied-ish, no blowout
}
