/*{
  "NAME": "Trails",
  "CATEGORIES": ["Time"],
  "DESCRIPTION": "Motion trails: blends each frame into a slowly fading accumulation buffer.",
  "INPUTS": [
    { "NAME": "persistence", "LABEL": "Persistence", "TYPE": "float", "DEFAULT": 0.85, "MIN": 0.0, "MAX": 0.99 },
    { "NAME": "tint", "LABEL": "Trail Tint", "TYPE": "color", "DEFAULT": [1, 1, 1, 1] }
  ],
  "PASSES": [ { "TARGET": "acc", "PERSISTENT": true, "FLOAT": true } ]
}*/

float4 effect(Twz t) {
    float4 now = t.sample(t.uv);
    float4 old = t.sample(t.acc, t.uv);
    if (t.frame == 0) return now;
    float3 trail = old.rgb * t.p.tint.rgb;
    return float4(max(now.rgb, mix(now.rgb, trail, t.p.persistence)), 1.0);
}
