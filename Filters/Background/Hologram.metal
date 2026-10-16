/*{
  "NAME": "Hologram",
  "CATEGORIES": ["Background", "Stylize"],
  "DESCRIPTION": "Help me, Obi-Wan: you as a flickering blue hologram with scanlines.",
  "MASK": true,
  "INPUTS": [ { "NAME": "color", "LABEL": "Color", "TYPE": "color", "DEFAULT": [0.3, 0.75, 1.0, 1] },
              { "NAME": "background", "LABEL": "Background Darkness", "TYPE": "float", "DEFAULT": 0.85, "MIN": 0, "MAX": 1 },
              { "NAME": "glitch", "LABEL": "Glitch", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0, "MAX": 1 } ]
}*/
float4 effect(Twz t) {
    float2 uv = t.uv;
    float band = step(0.97 - t.p.glitch * 0.05, hash11(floor(uv.y * 40.0) + floor(t.time * 8.0)));
    uv.x += band * (hash11(floor(t.time * 8.0)) - 0.5) * 0.05 * t.p.glitch;
    float3 src = t.sample(uv).rgb;
    float m = smoothstep(0.35, 0.65, t.maskAt(uv));
    float l = luma(src);
    float scan = 0.65 + 0.35 * sin(t.pos.y * 1.2 - t.time * 12.0);
    float flicker = 0.85 + 0.15 * hash11(floor(t.time * 20.0));
    float e = t.edge(1.5);
    float3 holo = t.p.color.rgb * (l * 1.3 + e * 1.5) * scan * flicker;
    float3 bg = src * (1.0 - t.p.background) * float3(0.6, 0.7, 0.9);
    float3 c = bg + holo * m * 0.95;
    c += t.p.color.rgb * smoothstep(0.0, 1.0, t.blur(10.0).r) * 0.05 * m;
    return float4(c, 1.0);
}
