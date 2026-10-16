/*{
  "NAME": "Comic Noir",
  "CATEGORIES": ["CamTwist", "Stylize"],
  "DESCRIPTION": "High-contrast black & white with blobby shadows and ink edges, Sin City style (after CamTwist's qComicNoir).",
  "INPUTS": [
    { "NAME": "blobbiness", "LABEL": "Blobbiness", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0, "MAX": 3 },
    { "NAME": "threshold", "LABEL": "Threshold", "TYPE": "float", "DEFAULT": 0.42, "MIN": 0.1, "MAX": 0.9 },
    { "NAME": "accent", "LABEL": "Red Accent", "TYPE": "bool", "DEFAULT": true }
  ]
}*/
float4 effect(Twz t) {
    float4 src = t.blur(1.0 + t.p.blobbiness * 3.0);
    float l = luma(src.rgb);
    float v = smoothstep(t.p.threshold - 0.04, t.p.threshold + 0.04, l);
    float e = smoothstep(0.2, 0.5, t.edge(2.0));
    float3 c = float3(v * (1.0 - e));
    if (t.p.accent) {
        float3 hsv = rgb2hsv(t.sample(t.uv).rgb);
        float red = smoothstep(0.35, 0.6, hsv.y) * (1.0 - smoothstep(0.04, 0.1, min(hsv.x, 1.0 - hsv.x)));
        c = mix(c, float3(0.85, 0.05, 0.08) * (0.5 + 0.5 * v), red);
    }
    return float4(c, 1.0);
}
