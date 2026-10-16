/*{
  "NAME": "Light Leaks",
  "CATEGORIES": ["Overlay", "Photo", "Retro"],
  "DESCRIPTION": "Warm, drifting film light leaks along the edges.",
  "INPUTS": [ { "NAME": "intensity", "LABEL": "Intensity", "TYPE": "float", "DEFAULT": 0.6, "MIN": 0, "MAX": 1.5 },
              { "NAME": "speed", "LABEL": "Drift Speed", "TYPE": "float", "DEFAULT": 0.15, "MIN": 0, "MAX": 1 } ]
}*/
float4 effect(Twz t) {
    float3 c = t.sample(t.uv).rgb;
    float tt = t.time * t.p.speed;
    float2 p = t.uv;
    float leak = 0;
    float3 col = 0;
    for (int i = 0; i < 3; i++) {
        float2 ctr = float2(fract(0.15 + float(i) * 0.37 + tt * (0.3 + 0.1 * float(i))) * 1.4 - 0.2, float(i % 2));
        float n = fbm(p * 2.0 + float(i) * 5.0 + tt, 3);
        float d = length((p - ctr) * float2(1.0, 1.6)) - n * 0.25;
        float k = smoothstep(0.55, 0.0, d);
        col += k * mix(float3(1.0, 0.35, 0.1), float3(1.0, 0.75, 0.25), float(i) * 0.5);
        leak += k;
    }
    return float4(blendScreen(c, col * t.p.intensity * 0.7), 1.0);
}
