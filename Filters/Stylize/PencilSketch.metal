/*{
  "NAME": "Pencil Sketch",
  "CATEGORIES": ["Stylize"],
  "DESCRIPTION": "Graphite drawing via the classic color-dodge sketch technique, optionally tinted with the original colors.",
  "INPUTS": [
    { "NAME": "softness", "LABEL": "Softness", "TYPE": "float", "DEFAULT": 6, "MIN": 1, "MAX": 20 },
    { "NAME": "darkness", "LABEL": "Darkness", "TYPE": "float", "DEFAULT": 1.4, "MIN": 0.5, "MAX": 4 },
    { "NAME": "color", "LABEL": "Color Pencil", "TYPE": "float", "DEFAULT": 0, "MIN": 0, "MAX": 1 }
  ]
}*/
float4 effect(Twz t) {
    float g = luma(t.sample(t.uv).rgb);
    float b = luma(t.blur(t.p.softness * t.inputSize.y / 720.0).rgb);
    float sketch = clamp(g / max(b, 0.02), 0.0, 1.0);          // color dodge of inverted blur
    sketch = pow(sketch, t.p.darkness * 2.0);
    float paper = 0.96 + 0.04 * vnoise(t.pos * 0.4);
    float3 c = float3(sketch * paper);
    float3 tint = mix(float3(1.0), t.sample(t.uv).rgb * 1.3, t.p.color);
    return float4(clamp(c * tint, 0.0, 1.0), 1.0);
}
