/*{
  "NAME": "Long Exposure",
  "CATEGORIES": ["Time"],
  "DESCRIPTION": "Light painting: bright things leave lasting streaks (lighten-blend accumulation). Restart to clear.",
  "INPUTS": [ { "NAME": "decay", "LABEL": "Fade", "TYPE": "float", "DEFAULT": 0.995, "MIN": 0.9, "MAX": 1 },
              { "NAME": "threshold", "LABEL": "Brightness Threshold", "TYPE": "float", "DEFAULT": 0.6, "MIN": 0, "MAX": 1 },
              { "NAME": "clear", "LABEL": "Clear", "TYPE": "event" } ],
  "PASSES": [ { "TARGET": "acc", "PERSISTENT": true, "FLOAT": true }, {} ]
}*/
float4 effect(Twz t) {
    float3 now = t.sample(t.uv).rgb;
    if (t.pass == 0) {
        if (t.frame == 0 || t.p.clear) return float4(0, 0, 0, 1);
        float3 prev = t.sample(t.acc, t.uv).rgb * t.p.decay;
        float3 bright = now * smoothstep(t.p.threshold - 0.05, t.p.threshold + 0.05, luma(now));
        return float4(max(prev, bright), 1);
    }
    return float4(max(now, t.sample(t.acc, t.uv).rgb), 1.0);
}
