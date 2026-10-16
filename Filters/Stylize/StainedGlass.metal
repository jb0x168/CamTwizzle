/*{
  "NAME": "Stained Glass",
  "CATEGORIES": ["Stylize"],
  "DESCRIPTION": "Voronoi cells of glowing colored glass held together by dark lead lines.",
  "INPUTS": [ { "NAME": "cells", "LABEL": "Cell Count", "TYPE": "float", "DEFAULT": 40, "MIN": 8, "MAX": 150 },
              { "NAME": "lead", "LABEL": "Lead Width", "TYPE": "float", "DEFAULT": 0.06, "MIN": 0, "MAX": 0.2 },
              { "NAME": "saturation", "LABEL": "Saturation", "TYPE": "float", "DEFAULT": 1.5, "MIN": 0, "MAX": 3 } ]
}*/
float4 effect(Twz t) {
    float2 p = t.uv * float2(t.aspect, 1.0) * (t.p.cells / 4.0);
    float2 ip = floor(p);
    float d1 = 1e9, d2 = 1e9; float2 best = 0;
    for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
        float2 g = ip + float2(i, j);
        float2 o = g + 0.15 + 0.7 * hash22(g);
        float d = length(p - o);
        if (d < d1) { d2 = d1; d1 = d; best = o; } else if (d < d2) d2 = d;
    }
    float2 cuv = best / (t.p.cells / 4.0) / float2(t.aspect, 1.0);
    float3 c = t.blurAt(clamp(cuv, 0.0, 1.0), 6.0).rgb;
    float3 hsv = rgb2hsv(c);
    hsv.y = clamp(hsv.y * t.p.saturation, 0.0, 1.0);
    hsv.z = clamp(hsv.z * 1.15, 0.0, 1.0);
    c = hsv2rgb(hsv);
    c *= 0.85 + 0.3 * (1.0 - d1);                        // brighter at cell centers
    float lead = smoothstep(t.p.lead, t.p.lead * 0.6, d2 - d1);
    return float4(mix(c, float3(0.05, 0.04, 0.03), lead), 1.0);
}
