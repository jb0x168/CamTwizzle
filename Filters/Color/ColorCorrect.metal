/*{
  "NAME": "Color Correct",
  "CATEGORIES": ["Color"],
  "DESCRIPTION": "All-in-one adjustments: exposure, contrast, saturation, temperature, tint, hue, gamma, shadows lift.",
  "INPUTS": [
    { "NAME": "exposure", "LABEL": "Exposure", "TYPE": "float", "DEFAULT": 0, "MIN": -2, "MAX": 2 },
    { "NAME": "contrast", "LABEL": "Contrast", "TYPE": "float", "DEFAULT": 1, "MIN": 0, "MAX": 2.5 },
    { "NAME": "saturation", "LABEL": "Saturation", "TYPE": "float", "DEFAULT": 1, "MIN": 0, "MAX": 2.5 },
    { "NAME": "temperature", "LABEL": "Temperature", "TYPE": "float", "DEFAULT": 0, "MIN": -1, "MAX": 1 },
    { "NAME": "tint", "LABEL": "Tint", "TYPE": "float", "DEFAULT": 0, "MIN": -1, "MAX": 1 },
    { "NAME": "hue", "LABEL": "Hue", "TYPE": "float", "DEFAULT": 0, "MIN": -180, "MAX": 180 },
    { "NAME": "gamma", "LABEL": "Gamma", "TYPE": "float", "DEFAULT": 1, "MIN": 0.3, "MAX": 3 },
    { "NAME": "lift", "LABEL": "Shadow Lift", "TYPE": "float", "DEFAULT": 0, "MIN": 0, "MAX": 0.4 }
  ]
}*/
float4 effect(Twz t) {
    float3 c = t.sample(t.uv).rgb * exp2(t.p.exposure);
    c *= float3(1.0 + 0.2 * t.p.temperature, 1.0 + 0.1 * t.p.tint * -1.0, 1.0 - 0.2 * t.p.temperature);
    c = (c - 0.5) * t.p.contrast + 0.5;
    c = c + t.p.lift * (1.0 - c);
    float3 hsv = rgb2hsv(clamp(c, 0.0, 1.0));
    hsv.x = fract(hsv.x + t.p.hue / 360.0);
    hsv.y = clamp(hsv.y * t.p.saturation, 0.0, 1.0);
    c = hsv2rgb(hsv);
    c = pow(clamp(c, 0.0, 1.0), float3(1.0 / t.p.gamma));
    return float4(c, 1.0);
}
