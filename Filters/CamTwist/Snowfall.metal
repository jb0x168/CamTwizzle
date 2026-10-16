/*{
  "NAME": "Snowfall",
  "CATEGORIES": ["CamTwist", "Overlay"],
  "DESCRIPTION": "Soft snowflakes drifting down in several depth layers.",
  "INPUTS": [
    { "NAME": "amount", "LABEL": "Number of Flakes", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0, "MAX": 1 },
    { "NAME": "speed", "LABEL": "Speed", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0, "MAX": 3 },
    { "NAME": "size", "LABEL": "Size", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0.3, "MAX": 3 },
    { "NAME": "wind", "LABEL": "Wind", "TYPE": "float", "DEFAULT": 0.2, "MIN": -1, "MAX": 1 }
  ]
}*/
float4 effect(Twz t) {
    float3 c = t.sample(t.uv).rgb;
    float2 p = t.centered();
    float snow = 0;
    for (int l = 0; l < 5; l++) {
        float depth = 1.0 + float(l) * 0.7;
        float scale = 6.0 * depth / t.p.size;
        float2 q = p * scale;
        q.y -= t.time * t.p.speed * 1.2 / depth * scale * 0.12;
        q.x -= t.time * t.p.wind * 0.6 + sin(t.time * 0.7 + float(l)) * 0.3;
        float2 cell = floor(q);
        float2 f = fract(q) - 0.5;
        float h = hash12(cell + float(l) * 31.0);
        if (h > t.p.amount) continue;
        float2 off = (hash22(cell + float(l)) - 0.5) * 0.6;
        off.x += sin(t.time * (1.0 + h * 2.0) + h * 30.0) * 0.15;
        float r = (0.05 + 0.08 * hash11(h * 13.0)) ;
        float d = length(f - off);
        snow += smoothstep(r, r * 0.3, d) * (1.1 - float(l) * 0.15);
    }
    return float4(mix(c, float3(1.0), clamp(snow, 0.0, 1.0)), 1.0);
}
