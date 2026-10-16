/*{
  "NAME": "Disappear",
  "CATEGORIES": ["Time", "Background"],
  "DESCRIPTION": "Step out of the picture, click 'Learn Background', step back in — then fade yourself out. Uses person segmentation when available to keep learning the background around you.",
  "MASK": true,
  "INPUTS": [ { "NAME": "learn", "LABEL": "Learn Background", "TYPE": "event" },
              { "NAME": "visibility", "LABEL": "Your Visibility", "TYPE": "float", "DEFAULT": 0.15, "MIN": 0, "MAX": 1 },
              { "NAME": "shimmer", "LABEL": "Predator Shimmer", "TYPE": "float", "DEFAULT": 0.4, "MIN": 0, "MAX": 1 } ],
  "PASSES": [ { "TARGET": "bg", "PERSISTENT": true }, {} ]
}*/
float4 effect(Twz t) {
    float4 now = t.sample(t.uv);
    float hasMask = 1.0 - step(0.999, t.maskAt(float2(0.01, 0.01)) * t.maskAt(float2(0.99, 0.99)) * t.maskAt(float2(0.5, 0.02)));
    float m = hasMask > 0.5 ? smoothstep(0.3, 0.7, t.maskAt(t.uv)) : 0.0;
    if (t.pass == 0) {
        if (t.frame == 0 || t.p.learn) return now;
        // keep updating wherever no person is detected
        float4 bg = t.sample(t.bg, t.uv);
        return hasMask > 0.5 ? mix(now, bg, max(m, 0.9)) : bg;
    }
    float4 bg = t.sample(t.bg, t.uv);
    // person region: compare against the learned background if there's no mask
    float diff = smoothstep(0.08, 0.2, length(now.rgb - bg.rgb));
    float person = hasMask > 0.5 ? m : diff;
    float2 n = (float2(vnoise(t.uv * 60.0 + t.time), vnoise(t.uv * 60.0 - t.time)) - 0.5) * 0.02 * t.p.shimmer;
    float3 cloak = t.sample(t.bg, t.uv + n * person).rgb;
    float edge = abs(t.maskAt(t.uv + float2(0.004, 0)) - t.maskAt(t.uv - float2(0.004, 0))) + abs(t.maskAt(t.uv + float2(0, 0.004)) - t.maskAt(t.uv - float2(0, 0.004)));
    cloak += edge * t.p.shimmer * 0.3;
    return float4(mix(now.rgb, mix(cloak, now.rgb, t.p.visibility), person), 1.0);
}
