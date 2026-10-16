/*{
  "NAME": "Bullet Time",
  "CATEGORIES": ["CamTwist", "Time"],
  "DESCRIPTION": "Ghostly time echoes: the current frame blended with several delayed copies, like CamTwist's BulletTime.",
  "INPUTS": [
    { "NAME": "interval", "LABEL": "Echo Spacing (frames)", "TYPE": "float", "DEFAULT": 4, "MIN": 1, "MAX": 20 },
    { "NAME": "strength", "LABEL": "Echo Strength", "TYPE": "float", "DEFAULT": 0.6, "MIN": 0, "MAX": 1 },
    { "NAME": "tint", "LABEL": "Colored Echoes", "TYPE": "bool", "DEFAULT": true }
  ],
  "PASSES": [
    { "TARGET": "e3", "PERSISTENT": true },
    { "TARGET": "e2", "PERSISTENT": true },
    { "TARGET": "e1", "PERSISTENT": true },
    {}
  ]
}*/

float4 effect(Twz t) {
    bool shift = (t.frame % max(1, int(t.p.interval))) == 0 || t.frame < 2;
    if (t.pass == 0) return shift ? t.sample(t.e2, t.uv) : t.sample(t.e3, t.uv);
    if (t.pass == 1) return shift ? t.sample(t.e1, t.uv) : t.sample(t.e2, t.uv);
    if (t.pass == 2) return shift ? t.sample(t.uv) : t.sample(t.e1, t.uv);
    float3 now = t.sample(t.uv).rgb;
    float3 a = t.sample(t.e1, t.uv).rgb, b = t.sample(t.e2, t.uv).rgb, c = t.sample(t.e3, t.uv).rgb;
    if (t.p.tint) { a *= float3(1.0, 0.6, 0.6); b *= float3(0.6, 1.0, 0.6); c *= float3(0.6, 0.6, 1.0); }
    float s = t.p.strength;
    float3 echo = (a * 0.45 + b * 0.33 + c * 0.22);
    return float4(mix(now, max(now, echo * 1.1), s), 1.0);
}
