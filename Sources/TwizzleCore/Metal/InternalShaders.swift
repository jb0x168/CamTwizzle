import Foundation

/// Shaders the engine itself uses (source fitting, layer compositing, output
/// conversion, built-in generators). Compiled at runtime like plugins.
enum InternalShaders {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct TwzVOut { float4 position [[position]]; float2 uv; };

    vertex TwzVOut twz_fullscreen_vertex(uint vid [[vertex_id]]) {
        float2 p = float2((vid << 1) & 2, vid & 2);
        TwzVOut o;
        o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        o.uv = float2(p.x, 1.0 - p.y);
        return o;
    }

    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);

    // Map canvas uv -> source uv with an affine (scale, offset). Outside -> background.
    // u0 = scale.xy, offset.xy ; u1 = mirror, bg alpha, 0, 0 ; u2 = bg rgb
    fragment float4 twz_fit(TwzVOut in [[stage_in]], texture2d<float> src [[texture(0)]], constant float4* u [[buffer(0)]]) {
        float2 uv = in.uv;
        if (u[1].x > 0.5) uv.x = 1.0 - uv.x;
        float2 s = uv * u[0].xy + u[0].zw;
        if (any(s < 0.0) || any(s > 1.0)) return float4(u[2].rgb, u[1].y);
        float4 c = src.sample(linearClamp, s);
        return c;
    }

    // Same mapping for a single-channel mask; outside -> 0.
    fragment float4 twz_fit_mask(TwzVOut in [[stage_in]], texture2d<float> src [[texture(0)]], constant float4* u [[buffer(0)]]) {
        float2 uv = in.uv;
        if (u[1].x > 0.5) uv.x = 1.0 - uv.x;
        float2 s = uv * u[0].xy + u[0].zw;
        if (any(s < 0.0) || any(s > 1.0)) return float4(0, 0, 0, 1);
        float m = src.sample(linearClamp, s).r;
        return float4(m, m, m, 1.0);
    }

    float3 twz_blend(float3 b, float3 l, int mode) {
        switch (mode) {
            case 1: return min(b + l, 1.0);                       // add
            case 2: return 1.0 - (1.0 - b) * (1.0 - l);           // screen
            case 3: return b * l;                                 // multiply
            case 4: return abs(b - l);                            // difference
            case 5: return max(b, l);                             // lighten
            case 6: return min(b, l);                             // darken
            case 7: return mix(2.0 * b * l, 1.0 - 2.0 * (1.0 - b) * (1.0 - l), step(0.5, b)); // overlay
            default: return l;                                    // normal
        }
    }

    // Composite a layer (canvas-sized content) over the base canvas.
    // u0 = center.xy, scale, angle ; u1 = canvas w, h, opacity, blend mode ; u2 = crop l,t,r,b (layer uv)
    fragment float4 twz_composite(TwzVOut in [[stage_in]], texture2d<float> base [[texture(0)]],
                                  texture2d<float> layer [[texture(1)]], constant float4* u [[buffer(0)]]) {
        float4 b = base.sample(linearClamp, in.uv);
        float2 size = u[1].xy;
        float2 p = (in.uv - u[0].xy) * size;
        float a = -u[0].w;
        float2 r = float2(p.x * cos(a) - p.y * sin(a), p.x * sin(a) + p.y * cos(a));
        float2 luv = r / (size * max(u[0].z, 1e-4)) + 0.5;
        float4 crop = u[2];
        // anti-aliased edge (~1 px in layer space)
        float2 px = 1.0 / (size * max(u[0].z, 1e-4));
        float2 lo = smoothstep(crop.xy - px, crop.xy + px, luv);
        float2 hi = 1.0 - smoothstep(1.0 - crop.zw - px, 1.0 - crop.zw + px, luv);
        float inside = lo.x * lo.y * hi.x * hi.y;
        if (inside <= 0.0) return b;
        float4 l = layer.sample(linearClamp, clamp(luv, 0.0, 1.0));
        float alpha = l.a * u[1].z * inside;
        float3 blended = twz_blend(b.rgb, l.rgb, int(u[1].w));
        return float4(mix(b.rgb, blended, alpha), max(b.a, alpha));
    }

    // Copy, optionally forcing alpha to 1. u0.x = opaque
    fragment float4 twz_copy(TwzVOut in [[stage_in]], texture2d<float> src [[texture(0)]], constant float4* u [[buffer(0)]]) {
        float4 c = src.sample(linearClamp, in.uv);
        if (u[0].x > 0.5) c.a = 1.0;
        return c;
    }

    // Premultiplied overlay (rendered by OpenGL, so bottom-up) over the base.
    fragment float4 twz_over_flipped(TwzVOut in [[stage_in]], texture2d<float> base [[texture(0)]], texture2d<float> top [[texture(1)]]) {
        float4 b = base.sample(linearClamp, in.uv);
        float4 t = top.sample(linearClamp, float2(in.uv.x, 1.0 - in.uv.y));
        return float4(t.rgb + b.rgb * (1.0 - t.a), 1.0);
    }

    float twz_hash(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }

    // Built-in generators. u0 = time, kind, w, h ; u1 = color A ; u2 = color B
    fragment float4 twz_pattern(TwzVOut in [[stage_in]], constant float4* u [[buffer(0)]]) {
        float t = u[0].x;
        int kind = int(u[0].y);
        float2 size = u[0].zw;
        float2 uv = in.uv;
        float2 px = uv * size;
        if (kind == 0) return u[1];                              // solid color
        if (kind == 1) {                                         // SMPTE-ish bars + moving ball
            const float3 bars[7] = { float3(0.75,0.75,0.75), float3(0.75,0.75,0), float3(0,0.75,0.75), float3(0,0.75,0),
                                     float3(0.75,0,0.75), float3(0.75,0,0), float3(0,0,0.75) };
            float3 c;
            if (uv.y < 0.67) c = bars[min(int(uv.x * 7.0), 6)];
            else if (uv.y < 0.75) {
                const float3 rev[7] = { float3(0,0,0.75), float3(0.07), float3(0.75,0,0.75), float3(0.07), float3(0,0.75,0.75), float3(0.07), float3(0.75) };
                c = rev[min(int(uv.x * 7.0), 6)];
            } else {
                c = float3(uv.x);                                // gray ramp
                if (uv.x < 0.2) c = float3(0.0, 0.13, 0.3);
            }
            float2 ball = float2(0.5 + 0.38 * sin(t * 0.9), 0.4 + 0.25 * sin(t * 1.7));
            float d = length((uv - ball) * float2(size.x / size.y, 1.0));
            c = mix(c, float3(1.0), 1.0 - smoothstep(0.075, 0.08, d));
            c = mix(c, float3(0.05), 1.0 - smoothstep(0.03, 0.035, d));
            // ticking seconds bar
            float sec = fract(t);
            if (uv.y > 0.95 && uv.x < sec) c = float3(1.0, 0.3, 0.1);
            return float4(c, 1.0);
        }
        if (kind == 2) {                                         // plasma
            float2 p = uv * 6.0;
            float v = sin(p.x + t) + sin(p.y * 1.3 + t * 1.1) + sin((p.x + p.y) * 0.7 + t * 0.7) + sin(length(p - 3.0) * 1.5 - t * 1.3);
            float3 c = 0.5 + 0.5 * cos(v * 1.4 + float3(0.0, 2.1, 4.2));
            return float4(c, 1.0);
        }
        if (kind == 3) {                                         // checkerboard
            float2 cell = floor(px / 64.0);
            float k = fmod(cell.x + cell.y, 2.0);
            return mix(u[1], u[2], k);
        }
        if (kind == 4) {                                         // gradient
            return mix(u[1], u[2], uv.y);
        }
        if (kind == 5) {                                         // noise / static
            float n = twz_hash(px + fract(t * 61.0) * 1000.0);
            return float4(float3(n), 1.0);
        }
        return float4(0, 0, 0, 1);
    }
    """
}
