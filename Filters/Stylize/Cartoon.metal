/*{
  "NAME": "Cartoon",
  "CATEGORIES": ["Stylize"],
  "DESCRIPTION": "Cel-shaded cartoon: smoothed flat color bands with clean black outlines.",
  "INPUTS": [
    { "NAME": "levels", "LABEL": "Color Bands", "TYPE": "float", "DEFAULT": 6, "MIN": 2, "MAX": 12 },
    { "NAME": "outline", "LABEL": "Outline", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0, "MAX": 3 },
    { "NAME": "smooth", "LABEL": "Smoothing", "TYPE": "float", "DEFAULT": 3, "MIN": 0, "MAX": 8 },
    { "NAME": "saturation", "LABEL": "Saturation", "TYPE": "float", "DEFAULT": 1.3, "MIN": 0, "MAX": 2.5 }
  ]
}*/
float4 effect(Twz t) {
    // edge-preserving smoothing: weight neighbours by color similarity (cheap bilateral)
    float3 c0 = t.sample(t.uv).rgb;
    float3 acc = c0; float wsum = 1;
    float r = t.p.smooth * t.inputSize.y / 720.0;
    for (int j = -2; j <= 2; j++) for (int i = -2; i <= 2; i++) {
        if (i == 0 && j == 0) continue;
        float3 s = t.offset(float2(i, j) * r * 0.6).rgb;
        float w = exp(-dot(s - c0, s - c0) * 18.0);
        acc += s * w; wsum += w;
    }
    float3 c = acc / wsum;
    float3 hsv = rgb2hsv(c);
    hsv.y = clamp(hsv.y * t.p.saturation, 0.0, 1.0);
    hsv.z = floor(hsv.z * t.p.levels + 0.5) / t.p.levels;
    c = hsv2rgb(hsv);
    float e = smoothstep(0.2, 0.45, t.edge(1.5 * t.inputSize.y / 720.0) * t.p.outline);
    return float4(c * (1.0 - e), 1.0);
}
