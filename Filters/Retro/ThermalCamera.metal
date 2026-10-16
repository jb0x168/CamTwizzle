/*{
  "NAME": "Thermal Camera",
  "CATEGORIES": ["Retro", "Color"],
  "DESCRIPTION": "FLIR-style heat palettes with a crosshair and fake temperature readout. (Brightness stands in for heat.)",
  "INPUTS": [
    { "NAME": "palette", "LABEL": "Palette", "TYPE": "long", "DEFAULT": 0, "VALUES": [0, 1, 2], "LABELS": ["Iron", "Rainbow", "White Hot"] },
    { "NAME": "skinBoost", "LABEL": "Warm Skin", "TYPE": "float", "DEFAULT": 0.6, "MIN": 0, "MAX": 1 },
    { "NAME": "hud", "LABEL": "Crosshair", "TYPE": "bool", "DEFAULT": true }
  ]
}*/
float3 iron(float x) {
    return clamp(float3(1.5 * x - 0.1, 1.6 * x * x - 0.2, 0.6 * sin(x * PI * 1.1) + max(0.0, x - 0.85) * 3.0), 0.0, 1.0);
}
float4 effect(Twz t) {
    float3 s = t.blur(2.0).rgb;
    float h = luma(s);
    // skin-ish hues read as warmer
    float3 hsv = rgb2hsv(s);
    float skin = smoothstep(0.12, 0.02, abs(hsv.x - 0.06)) * smoothstep(0.15, 0.4, hsv.y);
    h = clamp(h * 0.75 + skin * t.p.skinBoost * 0.45, 0.0, 1.0);
    float3 c;
    if (t.p.palette == 0) c = iron(h);
    else if (t.p.palette == 1) c = hsv2rgb(float3(0.7 * (1.0 - h), 1.0, 0.35 + 0.65 * h));
    else c = float3(h);
    if (t.p.hud) {
        float2 p = (t.uv - 0.5) * float2(t.aspect, 1.0);
        float ch = (step(abs(p.x), 0.0015) * step(abs(p.y), 0.04) + step(abs(p.y), 0.0015) * step(abs(p.x), 0.04)) * step(0.012, length(p));
        c = mix(c, float3(1), ch);
    }
    return float4(c, 1.0);
}
