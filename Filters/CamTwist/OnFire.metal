/*{
  "NAME": "On Fire",
  "CATEGORIES": ["CamTwist", "Background"],
  "DESCRIPTION": "Flames lick up from your silhouette. Uses person segmentation when available (falls back to image edges). Inspired by CamTwist's qOnFire.",
  "MASK": true,
  "INPUTS": [
    { "NAME": "length", "LABEL": "Flame Length", "TYPE": "float", "DEFAULT": 0.7, "MIN": 0.1, "MAX": 1 },
    { "NAME": "power", "LABEL": "Power", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0, "MAX": 2 },
    { "NAME": "flicker", "LABEL": "Flicker", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0, "MAX": 3 }
  ],
  "PASSES": [ { "TARGET": "fire", "PERSISTENT": true, "FLOAT": true, "SCALE": 0.5 }, {} ]
}*/

float4 effect(Twz t) {
    if (t.pass == 0) {
        float2 px = 1.0 / t.size;
        float n = vnoise(float2(t.uv.x * 30.0, t.uv.y * 20.0 + t.time * 5.0 * t.p.flicker)) - 0.5;
        float2 below = t.uv + float2(n * 3.0 * px.x, 1.2 * px.y);
        float f = (t.sample(t.fire, below).r * 2.0 + t.sample(t.fire, below + float2(px.x, 0)).r + t.sample(t.fire, below - float2(px.x, 0)).r) / 4.0;
        f -= (1.05 - t.p.length) * 0.03 * (0.4 + hash12(t.pos + floor(t.time * 30.0)));
        // Outline of the person (mask gradient), else image edges
        float m = t.maskAt(t.uv);
        float mg = abs(t.maskAt(t.uv + float2(4.0, 0) * t.texel) - t.maskAt(t.uv - float2(4.0, 0) * t.texel))
                 + abs(t.maskAt(t.uv + float2(0, 4.0) * t.texel) - t.maskAt(t.uv - float2(0, 4.0) * t.texel));
        float hasMask = step(0.001, 1.0 - t.maskAt(float2(0.02, 0.02)));   // a white mask means "no segmentation"
        float fuel = hasMask > 0.5 ? smoothstep(0.15, 0.6, mg) : smoothstep(0.35, 0.8, t.edge(2.0)) * 0.8;
        fuel *= 0.7 + 0.6 * vnoise(t.uv * 60.0 + t.time * 3.0);
        f = max(f, fuel * t.p.power);
        return float4(max(f, 0.0), m, 0, 1);
    }
    float f = t.sample(t.fire, t.uv).r * t.p.power;
    float3 base = t.sample(t.uv).rgb;
    float3 fire = float3(smoothstep(0.0, 0.4, f), smoothstep(0.25, 0.75, f) * 0.85, smoothstep(0.65, 1.0, f) * 0.6);
    return float4(blendScreen(base, fire), 1.0);
}
