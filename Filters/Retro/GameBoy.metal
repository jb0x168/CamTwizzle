/*{
  "NAME": "Game Boy",
  "CATEGORIES": ["Retro"],
  "DESCRIPTION": "160×144-ish pixels, four shades of pea-soup green and ordered dithering.",
  "INPUTS": [
    { "NAME": "pixels", "LABEL": "Vertical Pixels", "TYPE": "float", "DEFAULT": 144, "MIN": 48, "MAX": 360 },
    { "NAME": "contrast", "LABEL": "Contrast", "TYPE": "float", "DEFAULT": 1.2, "MIN": 0.5, "MAX": 2.5 },
    { "NAME": "palette", "LABEL": "Palette", "TYPE": "long", "DEFAULT": 0, "VALUES": [0, 1, 2], "LABELS": ["DMG Green", "Pocket Gray", "Virtual Boy"] },
    { "NAME": "grid", "LABEL": "Pixel Grid", "TYPE": "bool", "DEFAULT": true }
  ]
}*/
constant float bayer4[16] = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 };
float4 effect(Twz t) {
    float ph = t.p.pixels;
    float2 res = float2(floor(ph * t.aspect), ph);
    float2 cell = floor(t.uv * res);
    float2 cuv = (cell + 0.5) / res;
    float l = luma(t.blurAt(cuv, 0.5 * t.inputSize.y / ph).rgb);
    l = clamp((l - 0.5) * t.p.contrast + 0.5, 0.0, 1.0);
    int bi = int(fmod(cell.x, 4.0)) + int(fmod(cell.y, 4.0)) * 4;
    float d = (bayer4[bi] / 16.0 - 0.5) / 3.0;
    int level = int(clamp(floor((l + d) * 4.0), 0.0, 3.0));
    float3 pal[4];
    if (t.p.palette == 0) { pal[0] = float3(0.06, 0.22, 0.06); pal[1] = float3(0.19, 0.38, 0.19); pal[2] = float3(0.55, 0.67, 0.06); pal[3] = float3(0.61, 0.74, 0.06); }
    else if (t.p.palette == 1) { pal[0] = float3(0.1); pal[1] = float3(0.33); pal[2] = float3(0.62); pal[3] = float3(0.86, 0.87, 0.82); }
    else { pal[0] = float3(0.0); pal[1] = float3(0.33, 0, 0); pal[2] = float3(0.66, 0, 0); pal[3] = float3(1.0, 0.05, 0.05); }
    float3 c = pal[level];
    if (t.p.grid) {
        float2 f = fract(t.uv * res);
        float gl = step(0.92, max(f.x, f.y));
        c *= 1.0 - gl * 0.18;
    }
    return float4(c, 1.0);
}
