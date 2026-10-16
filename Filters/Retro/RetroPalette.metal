/*{
  "NAME": "Retro Palette",
  "CATEGORIES": ["Retro", "Color"],
  "DESCRIPTION": "8-bit computer looks: CGA, EGA, C64, PICO-8, ZX Spectrum — chunky pixels quantized to a vintage palette with optional dithering.",
  "INPUTS": [
    { "NAME": "palette", "LABEL": "Palette", "TYPE": "long", "DEFAULT": 3, "VALUES": [0, 1, 2, 3, 4], "LABELS": ["CGA (cyan/magenta)", "EGA 16", "Commodore 64", "PICO-8", "ZX Spectrum"] },
    { "NAME": "pixels", "LABEL": "Vertical Pixels", "TYPE": "float", "DEFAULT": 200, "MIN": 60, "MAX": 720 },
    { "NAME": "dither", "LABEL": "Dithering", "TYPE": "float", "DEFAULT": 0.6, "MIN": 0, "MAX": 1 }
  ]
}*/
constant float bayer8[64] = { 0,32,8,40,2,34,10,42, 48,16,56,24,50,18,58,26, 12,44,4,36,14,46,6,38, 60,28,52,20,62,30,54,22,
                              3,35,11,43,1,33,9,41, 51,19,59,27,49,17,57,25, 15,47,7,39,13,45,5,37, 63,31,55,23,61,29,53,21 };
constant float3 CGA[4] = { float3(0), float3(0.33, 1, 1), float3(1, 0.33, 1), float3(1) };
constant float3 EGA[16] = { float3(0), float3(0,0,0.67), float3(0,0.67,0), float3(0,0.67,0.67), float3(0.67,0,0), float3(0.67,0,0.67), float3(0.67,0.33,0), float3(0.67),
                            float3(0.33), float3(0.33,0.33,1), float3(0.33,1,0.33), float3(0.33,1,1), float3(1,0.33,0.33), float3(1,0.33,1), float3(1,1,0.33), float3(1) };
constant float3 C64[16] = { float3(0), float3(1), float3(0.53,0.2,0.22), float3(0.4,0.75,0.78), float3(0.55,0.24,0.59), float3(0.33,0.63,0.29), float3(0.25,0.19,0.55), float3(0.75,0.81,0.45),
                            float3(0.55,0.33,0.16), float3(0.34,0.26,0), float3(0.72,0.41,0.38), float3(0.31), float3(0.47), float3(0.58,0.88,0.54), float3(0.47,0.41,0.75), float3(0.62) };
constant float3 PICO[16] = { float3(0), float3(0.11,0.17,0.33), float3(0.49,0.15,0.33), float3(0,0.53,0.32), float3(0.67,0.32,0.21), float3(0.37,0.34,0.31), float3(0.76,0.76,0.78), float3(1,0.95,0.91),
                             float3(1,0,0.3), float3(1,0.64,0), float3(1,0.93,0.15), float3(0,0.89,0.21), float3(0.16,0.68,1), float3(0.51,0.46,0.61), float3(1,0.47,0.66), float3(1,0.8,0.67) };
constant float3 ZX[15] = { float3(0), float3(0,0,0.84), float3(0.84,0,0), float3(0.84,0,0.84), float3(0,0.84,0), float3(0,0.84,0.84), float3(0.84,0.84,0), float3(0.84),
                           float3(0,0,1), float3(1,0,0), float3(1,0,1), float3(0,1,0), float3(0,1,1), float3(1,1,0), float3(1) };
float3 nearest(float3 c, int pal) {
    int n = pal == 0 ? 4 : (pal == 4 ? 15 : 16);
    float best = 1e9; float3 bc = c;
    for (int i = 0; i < 16; i++) {
        if (i >= n) break;
        float3 p = pal == 0 ? CGA[i] : (pal == 1 ? EGA[i] : (pal == 2 ? C64[i] : (pal == 3 ? PICO[i] : ZX[i])));
        float3 d = (c - p) * float3(0.3, 0.59, 0.11);
        float dd = dot(d, d) + dot(c - p, c - p) * 0.2;
        if (dd < best) { best = dd; bc = p; }
    }
    return bc;
}
float4 effect(Twz t) {
    float2 res = float2(floor(t.p.pixels * t.aspect), t.p.pixels);
    float2 cell = floor(t.uv * res);
    float3 c = t.blurAt((cell + 0.5) / res, 0.4 * t.inputSize.y / t.p.pixels).rgb;
    int bi = int(fmod(cell.x, 8.0)) + int(fmod(cell.y, 8.0)) * 8;
    c += (bayer8[bi] / 64.0 - 0.5) * 0.35 * t.p.dither;
    return float4(nearest(clamp(c, 0.0, 1.0), t.p.palette), 1.0);
}
