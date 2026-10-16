/*{
  "NAME": "Take On Me",
  "CATEGORIES": ["CamTwist", "Stylize"],
  "DESCRIPTION": "Pencil-sketch rotoscope look from a-ha's 'Take On Me': boiling hand-drawn lines on white paper.",
  "INPUTS": [
    { "NAME": "lines", "LABEL": "Line Strength", "TYPE": "float", "DEFAULT": 1.2, "MIN": 0, "MAX": 3 },
    { "NAME": "hatching", "LABEL": "Hatching", "TYPE": "float", "DEFAULT": 0.35, "MIN": 0, "MAX": 1 },
    { "NAME": "boil", "LABEL": "Line Boil", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0, "MAX": 3 },
    { "NAME": "color", "LABEL": "Keep Color", "TYPE": "float", "DEFAULT": 0.0, "MIN": 0, "MAX": 1 }
  ]
}*/
float4 effect(Twz t) {
    float step_ = floor(t.time * 8.0);                    // hand-drawn at 8 drawings/sec
    float2 jit = (float2(vnoise(t.uv * 9.0 + step_ * 3.1), vnoise(t.uv * 9.0 - step_ * 1.7)) - 0.5) * 3.0 * t.p.boil;
    Twz u = t; u.uv = t.uv + jit * t.texel;
    float e = u.edge(1.5) * 0.7 + u.edge(3.0) * 0.5;
    float l = luma(u.blur(2.0).rgb);
    float pencil = smoothstep(0.12, 0.5, e * t.p.lines);
    // cross hatching in dark areas
    float h1 = smoothstep(0.65, 0.95, sin((t.pos.x + t.pos.y) * 0.9 + vnoise(t.pos * 0.05 + step_) * 4.0));
    float h2 = smoothstep(0.65, 0.95, sin((t.pos.x - t.pos.y) * 0.9 + vnoise(t.pos * 0.05 - step_) * 4.0));
    float hatch = h1 * smoothstep(0.4, 0.15, l) + h2 * smoothstep(0.25, 0.05, l);
    float ink = clamp(pencil + hatch * t.p.hatching * 0.7, 0.0, 1.0);
    float3 paper = float3(0.96, 0.95, 0.92) * (0.95 + 0.05 * vnoise(t.pos * 0.3));
    float3 tinted = mix(paper, t.sample(t.uv).rgb * 1.1, t.p.color * 0.6);
    return float4(mix(tinted, float3(0.12, 0.12, 0.15), ink), 1.0);
}
