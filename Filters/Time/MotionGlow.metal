/*{
  "NAME": "Motion Glow",
  "CATEGORIES": ["Time"],
  "DESCRIPTION": "Only movement lights up, in glowing color, over a darkened picture — motion detector vision.",
  "INPUTS": [ { "NAME": "sensitivity", "LABEL": "Sensitivity", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0, "MAX": 1 },
              { "NAME": "decay", "LABEL": "Glow Decay", "TYPE": "float", "DEFAULT": 0.85, "MIN": 0, "MAX": 0.98 },
              { "NAME": "background", "LABEL": "Background", "TYPE": "float", "DEFAULT": 0.25, "MIN": 0, "MAX": 1 },
              { "NAME": "color", "LABEL": "Color", "TYPE": "color", "DEFAULT": [0.2, 1, 0.9, 1] } ],
  "PASSES": [ { "TARGET": "glow", "PERSISTENT": true, "FLOAT": true }, { "TARGET": "prevIn", "PERSISTENT": true, "SCALE": 0.5 }, {} ]
}*/
float4 effect(Twz t) {
    if (t.pass == 0) {
        float m = length(t.blur(2.0).rgb - t.sample(t.prevIn, t.uv).rgb);
        m = t.frame < 2 ? 0.0 : smoothstep(0.25 - t.p.sensitivity * 0.2, 0.5 - t.p.sensitivity * 0.3, m);
        return float4(max(t.sample(t.glow, t.uv).r * t.p.decay, m), 0, 0, 1);
    }
    if (t.pass == 1) return t.blur(2.0);
    float g = t.sample(t.glow, t.uv).r;
    float3 c = t.sample(t.uv).rgb * t.p.background + t.p.color.rgb * g * 1.3;
    return float4(c, 1.0);
}
