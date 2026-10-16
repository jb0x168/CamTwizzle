/*{
  "NAME": "Flame",
  "CATEGORIES": ["CamTwist", "Time"],
  "DESCRIPTION": "Moving things catch fire: motion seeds flames that rise and flicker over the picture. A take on CamTwist's Flame (EffecTV FireTV).",
  "CREDIT": "Idea from EffecTV FireTV / CamTwist Flame.bundle",
  "INPUTS": [
    { "NAME": "sensitivity", "LABEL": "Motion Sensitivity", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0, "MAX": 1 },
    { "NAME": "height", "LABEL": "Flame Height", "TYPE": "float", "DEFAULT": 0.6, "MIN": 0.1, "MAX": 1 },
    { "NAME": "seed", "LABEL": "Fuel", "TYPE": "long", "DEFAULT": 0, "VALUES": [0, 1, 2], "LABELS": ["Motion", "Edges", "Bright Areas"] },
    { "NAME": "darken", "LABEL": "Darken Picture", "TYPE": "float", "DEFAULT": 0.3, "MIN": 0, "MAX": 1 }
  ],
  "PASSES": [
    { "TARGET": "fire", "PERSISTENT": true, "FLOAT": true, "SCALE": 0.5 },
    { "TARGET": "prevIn", "PERSISTENT": true, "SCALE": 0.5 },
    {}
  ]
}*/

float3 firePalette(float f) {
    f = clamp(f, 0.0, 1.0);
    return float3(smoothstep(0.0, 0.45, f), smoothstep(0.3, 0.8, f), smoothstep(0.7, 1.0, f) * 0.9);
}

float4 effect(Twz t) {
    if (t.pass == 0) {
        float2 px = 1.0 / t.size;
        // Propagate upward: average of the pixels below, with sideways turbulence.
        float n = vnoise(float2(t.uv.x * 40.0, t.uv.y * 25.0 + t.time * 6.0)) - 0.5;
        float2 below = t.uv + float2(n * 2.5 * px.x, 2.0 * px.y);
        float f = (t.sample(t.fire, below).r * 2.0 + t.sample(t.fire, below + float2(px.x, 0)).r + t.sample(t.fire, below - float2(px.x, 0)).r) / 4.0;
        f -= (1.1 - t.p.height) * 0.06 * (0.5 + hash12(t.pos + t.time * 60.0));
        // Fuel
        float fuel = 0;
        float4 now = t.sample(t.uv);
        if (t.p.seed == 0) {
            float4 before = t.sample(t.prevIn, t.uv);
            fuel = length(now.rgb - before.rgb) * 4.0;
            fuel = smoothstep(0.6 - t.p.sensitivity * 0.5, 0.9 - t.p.sensitivity * 0.5, fuel);
        } else if (t.p.seed == 1) {
            fuel = smoothstep(0.5 - t.p.sensitivity * 0.4, 0.9 - t.p.sensitivity * 0.4, t.edge(2.0));
        } else {
            fuel = smoothstep(0.95 - t.p.sensitivity * 0.4, 1.0 - t.p.sensitivity * 0.3, luma(now.rgb));
        }
        if (t.frame < 3) { fuel = 0; f = 0; }     // no previous frame yet
        f = max(f, fuel * (0.75 + 0.25 * hash12(t.pos * 1.3 + t.time)));
        return float4(max(f, 0.0), 0, 0, 1);
    }
    if (t.pass == 1) return t.sample(t.uv);
    float f = t.sample(t.fire, t.uv).r;
    float3 base = t.sample(t.uv).rgb * (1.0 - t.p.darken);
    float3 fire = firePalette(f * 1.2);
    return float4(blendScreen(base, fire), 1.0);
}
