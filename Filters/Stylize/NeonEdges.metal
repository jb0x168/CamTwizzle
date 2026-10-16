/*{
  "NAME": "Neon Edges",
  "CATEGORIES": ["Stylize"],
  "DESCRIPTION": "Glowing neon outlines in cycling rainbow colors on a dark background.",
  "INPUTS": [
    { "NAME": "glow", "LABEL": "Glow", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0, "MAX": 3 },
    { "NAME": "cycle", "LABEL": "Color Cycle", "TYPE": "float", "DEFAULT": 0.2, "MIN": 0, "MAX": 2 },
    { "NAME": "background", "LABEL": "Background", "TYPE": "float", "DEFAULT": 0.12, "MIN": 0, "MAX": 1 }
  ]
}*/
float4 effect(Twz t) {
    float s = t.inputSize.y / 720.0;
    float e = smoothstep(0.1, 0.5, t.edge(1.5 * s));
    float halo = 0;
    for (int i = 1; i <= 4; i++) {
        Twz u = t;
        float r = float(i) * 3.0 * s;
        halo += (smoothstep(0.1, 0.5, u.edge(r)) ) / float(i);
    }
    float hue = fract(t.uv.x * 0.6 + t.uv.y * 0.3 + t.time * t.p.cycle);
    float3 neon = hsv2rgb(float3(hue, 0.85, 1.0));
    float3 base = t.sample(t.uv).rgb * t.p.background;
    float3 c = base + neon * (e * 1.2 + halo * 0.25 * t.p.glow) + float3(1.0) * e * 0.3;
    return float4(c, 1.0);
}
