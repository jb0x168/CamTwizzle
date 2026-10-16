/*{
  "NAME": "Gradient Map",
  "CATEGORIES": ["Color"],
  "DESCRIPTION": "Recolor brightness through a palette: sunset, ocean, fire, viridis, synthwave, gold.",
  "INPUTS": [
    { "NAME": "palette", "LABEL": "Palette", "TYPE": "long", "DEFAULT": 0, "VALUES": [0, 1, 2, 3, 4, 5], "LABELS": ["Sunset", "Ocean", "Fire", "Viridis", "Synthwave", "Gold"] },
    { "NAME": "amount", "LABEL": "Amount", "TYPE": "float", "DEFAULT": 1, "MIN": 0, "MAX": 1 },
    { "NAME": "shift", "LABEL": "Cycle", "TYPE": "float", "DEFAULT": 0, "MIN": 0, "MAX": 1 }
  ]
}*/
float3 gmap(int p, float x) {
    if (p == 0) return palette(x, float3(0.5, 0.3, 0.35), float3(0.5, 0.35, 0.3), float3(1.0, 0.8, 0.5), float3(0.0, 0.1, 0.25));
    if (p == 1) return palette(x, float3(0.2, 0.45, 0.6), float3(0.2, 0.35, 0.4), float3(1.0, 1.0, 1.0), float3(0.0, 0.15, 0.2));
    if (p == 2) return clamp(float3(x * 2.2, x * x * 1.6, pow(x, 4.0) * 1.2), 0.0, 1.0);
    if (p == 3) return clamp(float3(0.27 + x * (0.0 + x * 0.73), 0.0 + x * 0.9, 0.33 + x * (0.4 - x * 0.6)), 0.0, 1.0);
    if (p == 4) return mix(mix(float3(0.08, 0.0, 0.2), float3(0.9, 0.1, 0.6), smoothstep(0.0, 0.5, x)), float3(1.0, 0.85, 0.3), smoothstep(0.5, 1.0, x));
    return mix(float3(0.1, 0.05, 0.0), float3(1.0, 0.85, 0.45), x) + smoothstep(0.85, 1.0, x) * 0.2;
}
float4 effect(Twz t) {
    float3 c = t.sample(t.uv).rgb;
    float l = fract(luma(c) * 0.999 + t.p.shift * t.time * 0.2 * step(0.001, t.p.shift));
    if (t.p.shift <= 0.0) l = luma(c);
    return float4(mix(c, gmap(t.p.palette, l), t.p.amount), 1.0);
}
