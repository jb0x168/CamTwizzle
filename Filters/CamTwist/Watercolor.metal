/*{
  "NAME": "Watercolor",
  "CATEGORIES": ["CamTwist", "Stylize"],
  "DESCRIPTION": "Soft washes of color with darkened edges and paper texture.",
  "INPUTS": [
    { "NAME": "radius", "LABEL": "Brush Size", "TYPE": "float", "DEFAULT": 4, "MIN": 1, "MAX": 12 },
    { "NAME": "edges", "LABEL": "Edge Darkening", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0, "MAX": 2 },
    { "NAME": "bleed", "LABEL": "Color Bleed", "TYPE": "float", "DEFAULT": 0.6, "MIN": 0, "MAX": 2 },
    { "NAME": "saturation", "LABEL": "Saturation", "TYPE": "float", "DEFAULT": 1.2, "MIN": 0, "MAX": 2 }
  ]
}*/
// Kuwahara-style 4-quadrant smoothing: picks the quadrant with the lowest variance.
float3 kuwahara(Twz t, float2 q, float r) {
    float3 bestMean = 0; float bestVar = 1e9;
    const float2 dirs[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    for (int k = 0; k < 4; k++) {
        float3 m = 0, m2 = 0;
        for (int j = 0; j < 3; j++) for (int i = 0; i < 3; i++) {
            float3 s = t.sample(q + dirs[k] * float2(i, j) * r * 0.5 * t.texel).rgb;
            m += s; m2 += s * s;
        }
        m /= 9.0; m2 /= 9.0;
        float v = dot(m2 - m * m, float3(1));
        if (v < bestVar) { bestVar = v; bestMean = m; }
    }
    return bestMean;
}
float4 effect(Twz t) {
    float2 n = (float2(fbm(t.pos * 0.02, 3), fbm(t.pos * 0.02 + 17.0, 3)) - 0.5) * t.p.bleed * 16.0 * t.texel;
    float3 c = kuwahara(t, t.uv + n, t.p.radius);
    float3 hsv = rgb2hsv(c);
    hsv.y = clamp(hsv.y * t.p.saturation, 0.0, 1.0);
    c = hsv2rgb(hsv);
    Twz u = t; u.uv = t.uv + n;
    float e = smoothstep(0.08, 0.4, u.edge(2.0));
    c *= 1.0 - e * 0.3 * t.p.edges;
    float paper = fbm(t.pos * 0.25, 4);
    c = mix(c, float3(1.0), 0.18) * (0.95 + 0.1 * paper);
    return float4(c, 1.0);
}
