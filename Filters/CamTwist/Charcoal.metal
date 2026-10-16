/*{
  "NAME": "Charcoal",
  "CATEGORIES": ["CamTwist", "Stylize"],
  "DESCRIPTION": "A smudgy charcoal sketch on rough paper (after CamTwist's qCharcoal).",
  "INPUTS": [
    { "NAME": "radius", "LABEL": "Stroke Width", "TYPE": "float", "DEFAULT": 2.5, "MIN": 1, "MAX": 8 },
    { "NAME": "darkness", "LABEL": "Darkness", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0, "MAX": 3 },
    { "NAME": "smudge", "LABEL": "Smudge", "TYPE": "float", "DEFAULT": 0.6, "MIN": 0, "MAX": 1 },
    { "NAME": "paper", "LABEL": "Paper Color", "TYPE": "color", "DEFAULT": [0.95, 0.93, 0.88, 1] }
  ]
}*/
float4 effect(Twz t) {
    float e = t.edge(t.p.radius) * 0.6 + t.edge(t.p.radius * 2.5) * 0.4;
    float l = luma(t.blur(t.p.radius * 3.0).rgb);
    // directional strokes: noise stretched along a diagonal
    float2 sp = rotate2d(t.pos, 0.6);
    float strokes = vnoise(sp * float2(0.04, 0.7)) * 0.6 + vnoise(sp * float2(0.08, 1.4)) * 0.4;
    float shade = smoothstep(0.55, 0.05, l) * t.p.smudge * (0.4 + 0.6 * strokes);
    float ink = clamp(smoothstep(0.08, 0.6, e) * t.p.darkness + shade * 0.55, 0.0, 1.0);
    float grain = fbm(t.pos * 0.15, 3);
    ink *= 0.75 + 0.5 * grain;
    float3 paper = t.p.paper.rgb * (0.92 + 0.08 * grain);
    return float4(mix(paper, float3(0.08, 0.08, 0.09), clamp(ink, 0.0, 1.0)), 1.0);
}
