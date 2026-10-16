/*{
  "NAME": "Sobel",
  "CATEGORIES": ["CamTwist", "Stylize"],
  "DESCRIPTION": "Sobel edge detection, tinted. A port of CamTwist's Sobel.qtz kernel.",
  "CREDIT": "CamTwist (Steve Green) / CamTwizzle port",
  "INPUTS": [
    { "NAME": "color", "LABEL": "Color", "TYPE": "color", "DEFAULT": [1, 1, 1, 1] },
    { "NAME": "gain", "LABEL": "Gain", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0.0, "MAX": 8.0 },
    { "NAME": "thickness", "LABEL": "Thickness", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0.5, "MAX": 4.0 },
    { "NAME": "overlay", "LABEL": "Overlay on image", "TYPE": "bool", "DEFAULT": false }
  ]
}*/

// The original kernel samples the red channel of each neighbour; we use luma,
// which looks the same on grey input and better on colour.
float sobelLuma(Twz t, float2 d) { return luma(t.offset(d * t.p.thickness).rgb); }

float4 effect(Twz t) {
    float tl = sobelLuma(t, float2(-1, -1)), tc = sobelLuma(t, float2(0, -1)), tr = sobelLuma(t, float2(1, -1));
    float ml = sobelLuma(t, float2(-1,  0)),                                     mr = sobelLuma(t, float2(1,  0));
    float bl = sobelLuma(t, float2(-1,  1)), bc = sobelLuma(t, float2(0,  1)), br = sobelLuma(t, float2(1,  1));
    float gx = -tl - 2.0 * ml - bl + tr + 2.0 * mr + br;
    float gy = -tl - 2.0 * tc - tr + bl + 2.0 * bc + br;
    float v = sqrt(gx * gx + gy * gy) * t.p.gain;
    float4 edge = float4(float3(v), 1.0) * t.p.color;
    if (t.p.overlay) {
        float4 src = t.sample(t.uv);
        return float4(mix(src.rgb, t.p.color.rgb, clamp(v, 0.0, 1.0) * t.p.color.a), 1.0);
    }
    return float4(edge.rgb, 1.0);
}
