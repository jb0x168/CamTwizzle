/*{
  "NAME": "1-Bit Dither",
  "CATEGORIES": ["Retro", "Stylize"],
  "DESCRIPTION": "Classic Mac / Obra Dinn style: just two colors and an ordered or noise dither.",
  "INPUTS": [
    { "NAME": "pixel", "LABEL": "Pixel Size", "TYPE": "float", "DEFAULT": 2, "MIN": 1, "MAX": 8 },
    { "NAME": "method", "LABEL": "Dither", "TYPE": "long", "DEFAULT": 0, "VALUES": [0, 1, 2], "LABELS": ["Bayer", "Blue-ish Noise", "Threshold"] },
    { "NAME": "bias", "LABEL": "Brightness", "TYPE": "float", "DEFAULT": 0.0, "MIN": -0.5, "MAX": 0.5 },
    { "NAME": "dark", "LABEL": "Ink", "TYPE": "color", "DEFAULT": [0.05, 0.05, 0.08, 1] },
    { "NAME": "light", "LABEL": "Paper", "TYPE": "color", "DEFAULT": [0.93, 0.92, 0.85, 1] }
  ]
}*/
constant float bayer8b[64] = { 0,32,8,40,2,34,10,42, 48,16,56,24,50,18,58,26, 12,44,4,36,14,46,6,38, 60,28,52,20,62,30,54,22,
                               3,35,11,43,1,33,9,41, 51,19,59,27,49,17,57,25, 15,47,7,39,13,45,5,37, 63,31,55,23,61,29,53,21 };
float4 effect(Twz t) {
    float ps = max(1.0, floor(t.p.pixel * t.inputSize.y / 720.0 + 0.5));
    float2 cell = floor(t.pos / ps);
    float l = luma(t.sample((cell + 0.5) * ps / t.size).rgb) + t.p.bias;
    float th = 0.5;
    if (t.p.method == 0) th = (bayer8b[int(fmod(cell.x, 8.0)) + int(fmod(cell.y, 8.0)) * 8] + 0.5) / 64.0;
    else if (t.p.method == 1) th = fract(hash12(cell) * 0.5 + hash12(cell * 0.37 + 11.0) * 0.5 + 0.6180339 * fmod(cell.x + cell.y * 3.0, 7.0));
    return float4(l > th ? t.p.light.rgb : t.p.dark.rgb, 1.0);
}
