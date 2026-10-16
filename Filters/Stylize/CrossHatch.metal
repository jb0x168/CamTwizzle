/*{
  "NAME": "Cross Hatch",
  "CATEGORIES": ["Stylize"],
  "DESCRIPTION": "Ink cross-hatching: more layers of lines in darker areas.",
  "INPUTS": [ { "NAME": "spacing", "LABEL": "Line Spacing", "TYPE": "float", "DEFAULT": 8, "MIN": 3, "MAX": 24 },
              { "NAME": "ink", "LABEL": "Ink", "TYPE": "color", "DEFAULT": [0.1, 0.1, 0.25, 1] },
              { "NAME": "paper", "LABEL": "Paper", "TYPE": "color", "DEFAULT": [0.98, 0.96, 0.9, 1] } ]
}*/
float lines(float2 p, float a, float sp) { float2 q = rotate2d(p, a); return smoothstep(0.25, 0.0, abs(fract(q.x / sp) - 0.5) - 0.25); }
float4 effect(Twz t) {
    float sp = t.p.spacing * t.inputSize.y / 720.0;
    float l = luma(t.blur(1.5).rgb);
    float ink = 0;
    if (l < 0.85) ink = max(ink, lines(t.pos, 0.785, sp));
    if (l < 0.6) ink = max(ink, lines(t.pos, -0.785, sp));
    if (l < 0.4) ink = max(ink, lines(t.pos + sp * 0.5, 0.0, sp));
    if (l < 0.2) ink = max(ink, lines(t.pos + sp * 0.25, 1.571, sp * 0.7));
    ink = max(ink, smoothstep(0.25, 0.6, t.edge(1.5)));
    return float4(mix(t.p.paper.rgb, t.p.ink.rgb, ink), 1.0);
}
