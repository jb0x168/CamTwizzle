/*{
  "NAME": "Comic Book",
  "CATEGORIES": ["CamTwist", "Stylize"],
  "DESCRIPTION": "Flat inked colors, bold outlines and halftone dots — the CamTwist ComicBook look.",
  "INPUTS": [
    { "NAME": "levels", "LABEL": "Color Levels", "TYPE": "float", "DEFAULT": 4, "MIN": 2, "MAX": 10 },
    { "NAME": "ink", "LABEL": "Ink Lines", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0, "MAX": 3 },
    { "NAME": "dots", "LABEL": "Halftone Size", "TYPE": "float", "DEFAULT": 7, "MIN": 3, "MAX": 20 },
    { "NAME": "saturation", "LABEL": "Saturation", "TYPE": "float", "DEFAULT": 1.4, "MIN": 0, "MAX": 2.5 }
  ]
}*/
float4 effect(Twz t) {
    float3 c = t.blur(1.5).rgb;
    float3 hsv = rgb2hsv(c);
    hsv.y = clamp(hsv.y * t.p.saturation, 0.0, 1.0);
    hsv.z = floor(hsv.z * t.p.levels + 0.5) / t.p.levels;
    float3 flat = hsv2rgb(hsv);
    // halftone shading on darker tones
    float2 gp = rotate2d(t.pos, 0.785) / t.p.dots;
    float2 cell = fract(gp) - 0.5;
    float tone = 1.0 - luma(c);
    float dot_ = smoothstep(tone * 0.6 + 0.02, tone * 0.6 - 0.04, length(cell));
    flat *= 1.0 - dot_ * 0.35;
    float e = smoothstep(0.15, 0.45, t.edge(1.5) * t.p.ink);
    return float4(mix(flat, float3(0.03), e), 1.0);
}
