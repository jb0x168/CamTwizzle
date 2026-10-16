/*{
  "NAME": "Duotone",
  "CATEGORIES": ["Color"],
  "DESCRIPTION": "Two-color poster look: shadows take one color, highlights the other.",
  "INPUTS": [
    { "NAME": "shadows", "LABEL": "Shadows", "TYPE": "color", "DEFAULT": [0.12, 0.05, 0.4, 1] },
    { "NAME": "highlights", "LABEL": "Highlights", "TYPE": "color", "DEFAULT": [1.0, 0.45, 0.55, 1] },
    { "NAME": "contrast", "LABEL": "Contrast", "TYPE": "float", "DEFAULT": 1.3, "MIN": 0.5, "MAX": 3 },
    { "NAME": "amount", "LABEL": "Amount", "TYPE": "float", "DEFAULT": 1, "MIN": 0, "MAX": 1 }
  ]
}*/
float4 effect(Twz t) {
    float3 c = t.sample(t.uv).rgb;
    float l = clamp((luma(c) - 0.5) * t.p.contrast + 0.5, 0.0, 1.0);
    float3 d = mix(t.p.shadows.rgb, t.p.highlights.rgb, smoothstep(0.0, 1.0, l));
    return float4(mix(c, d, t.p.amount), 1.0);
}
