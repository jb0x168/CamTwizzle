/*{
  "NAME": "ASCII Art",
  "CATEGORIES": ["Stylize", "Retro"],
  "DESCRIPTION": "Renders the image as text characters chosen by brightness.",
  "INPUTS": [
    { "NAME": "cell", "LABEL": "Cell Size", "TYPE": "float", "DEFAULT": 12, "MIN": 4, "MAX": 48 },
    { "NAME": "mode", "LABEL": "Color", "TYPE": "long", "DEFAULT": 0, "VALUES": [0, 1, 2], "LABELS": ["Green Terminal", "Source Colors", "White on Black"] },
    { "NAME": "contrast", "LABEL": "Contrast", "TYPE": "float", "DEFAULT": 1.2, "MIN": 0.5, "MAX": 3 },
    { "NAME": "invert", "LABEL": "Invert", "TYPE": "bool", "DEFAULT": false }
  ],
  "GLYPHS": [ { "NAME": "ramp", "CHARS": " .`:-=+*cox%#&@", "FONT": "Menlo-Bold", "SIZE": 48 } ]
}*/

float4 effect(Twz t) {
    float2 cellPx = float2(t.p.cell * 0.6, t.p.cell);        // monospace aspect
    float2 cellIdx = floor(t.pos / cellPx);
    float2 cellUV = fract(t.pos / cellPx);
    float2 center = (cellIdx + 0.5) * cellPx / t.size;
    float4 c = t.sample(center);
    float l = clamp((luma(c.rgb) - 0.5) * t.p.contrast + 0.5, 0.0, 1.0);
    if (t.p.invert) l = 1.0 - l;
    int idx = int(l * float(ramp_COUNT - 1) + 0.5);
    float g = glyphAt(t.ramp, ramp_COUNT, idx, cellUV);
    float3 ink;
    if (t.p.mode == 0) ink = float3(0.2, 1.0, 0.35);
    else if (t.p.mode == 1) ink = c.rgb / max(max(c.r, max(c.g, c.b)), 0.15);
    else ink = float3(1.0);
    return float4(ink * g, 1.0);
}
