/*{
  "NAME": "Aura",
  "CATEGORIES": ["Background", "Overlay"],
  "DESCRIPTION": "A glowing, shifting rainbow aura around you.",
  "MASK": true,
  "INPUTS": [ { "NAME": "size", "LABEL": "Size", "TYPE": "float", "DEFAULT": 0.06, "MIN": 0.01, "MAX": 0.2 },
              { "NAME": "intensity", "LABEL": "Intensity", "TYPE": "float", "DEFAULT": 1, "MIN": 0, "MAX": 3 },
              { "NAME": "rainbow", "LABEL": "Rainbow", "TYPE": "bool", "DEFAULT": true },
              { "NAME": "color", "LABEL": "Color (if not rainbow)", "TYPE": "color", "DEFAULT": [0.5, 0.3, 1, 1] } ]
}*/
float4 effect(Twz t) {
    float3 c = t.sample(t.uv).rgb;
    float m = t.maskAt(t.uv);
    // dilated mask: max over a ring of samples
    float halo = 0;
    for (int i = 0; i < 16; i++) {
        float a = float(i) * TAU / 16.0 + t.time * 0.5;
        for (int k = 1; k <= 3; k++) {
            float2 o = float2(cos(a), sin(a)) * t.p.size * float(k) / 3.0 * float2(1.0 / t.aspect, 1.0);
            halo = max(halo, t.maskAt(t.uv + o) * (1.0 - float(k - 1) / 3.0));
        }
    }
    float aura = clamp(halo - m, 0.0, 1.0);
    float wav = 0.7 + 0.3 * sin(t.uv.y * 30.0 - t.time * 4.0 + vnoise(t.uv * 8.0 + t.time) * 6.0);
    float3 col = t.p.rainbow ? hsv2rgb(float3(fract(t.uv.y * 0.8 + t.time * 0.15), 0.8, 1.0)) : t.p.color.rgb;
    return float4(c + col * aura * wav * t.p.intensity, 1.0);
}
