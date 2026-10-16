/*{
  "NAME": "Old Movie",
  "CATEGORIES": ["CamTwist", "Retro"],
  "DESCRIPTION": "Sepia, film grain, scratches, dust, flicker and gate weave — like CamTwist's Old movie.",
  "INPUTS": [
    { "NAME": "sepia", "LABEL": "Sepia Intensity", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0, "MAX": 1 },
    { "NAME": "grain", "LABEL": "Grain", "TYPE": "float", "DEFAULT": 0.25, "MIN": 0, "MAX": 1 },
    { "NAME": "lines", "LABEL": "Vertical Scratches", "TYPE": "float", "DEFAULT": 5, "MIN": 0, "MAX": 12 },
    { "NAME": "flicker", "LABEL": "Flicker", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0, "MAX": 1 },
    { "NAME": "dust", "LABEL": "Dust", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0, "MAX": 1 },
    { "NAME": "vignette", "LABEL": "Vignette", "TYPE": "float", "DEFAULT": 0.6, "MIN": 0, "MAX": 1 }
  ]
}*/
float4 effect(Twz t) {
    float frame = floor(t.time * 18.0);                         // film runs at ~18 fps
    float2 weave = (hash22(float2(frame, 3.0)) - 0.5) * float2(0.002, 0.004);
    float2 uv = t.uv + weave;
    float3 c = t.sample(uv).rgb;
    float l = luma(c);
    float3 sep = float3(l * 1.07, l * 0.86, l * 0.62) + float3(0.04, 0.02, 0.0);
    c = mix(c, sep, t.p.sepia);
    c *= 1.0 + (hash11(frame) - 0.5) * 0.35 * t.p.flicker;
    // Grain
    c += (hash12(t.pos * 0.5 + frame * 13.1) - 0.5) * 0.35 * t.p.grain;
    // Scratches
    for (int i = 0; i < 12; i++) {
        if (float(i) >= t.p.lines) break;
        float h = hash11(float(i) * 3.7 + floor(t.time * (0.5 + hash11(float(i)))));
        float x = h + (vnoise(float2(t.time * 2.0, float(i))) - 0.5) * 0.02;
        float w = 0.0008 + 0.0012 * hash11(float(i) + 0.5);
        float vis = step(0.35, hash11(frame + float(i) * 7.0));
        c = mix(c, c * 0.45, smoothstep(w, 0.0, abs(t.uv.x - x)) * vis * 0.8);
    }
    // Dust specks
    float2 cell = floor(t.uv * float2(t.aspect, 1.0) * 30.0);
    float2 f = fract(t.uv * float2(t.aspect, 1.0) * 30.0) - 0.5;
    float r = hash12(cell + frame);
    if (r > 1.0 - t.p.dust * 0.03) c *= 0.3 + 0.7 * smoothstep(0.05, 0.35, length(f + (hash22(cell) - 0.5) * 0.4));
    // Vignette
    float2 d = (t.uv - 0.5) * float2(t.aspect, 1.0);
    c *= 1.0 - t.p.vignette * smoothstep(0.35, 1.0, length(d));
    return float4(clamp(c, 0.0, 1.0), 1.0);
}
