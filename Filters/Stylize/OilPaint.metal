/*{
  "NAME": "Oil Paint",
  "CATEGORIES": ["Stylize"],
  "DESCRIPTION": "Kuwahara-filter oil painting with visible brush texture.",
  "INPUTS": [
    { "NAME": "radius", "LABEL": "Brush Size", "TYPE": "float", "DEFAULT": 5, "MIN": 1, "MAX": 14 },
    { "NAME": "texture", "LABEL": "Canvas Texture", "TYPE": "float", "DEFAULT": 0.4, "MIN": 0, "MAX": 1 }
  ]
}*/
float4 effect(Twz t) {
    float r = t.p.radius * t.inputSize.y / 720.0;
    float3 bestMean = 0; float bestVar = 1e9;
    for (int k = 0; k < 4; k++) {
        float2 dir = float2((k & 1) ? 1.0 : -1.0, (k & 2) ? 1.0 : -1.0);
        float3 m = 0, m2 = 0;
        for (int j = 0; j < 4; j++) for (int i = 0; i < 4; i++) {
            float3 s = t.offset(dir * float2(i, j) * r / 3.0).rgb;
            m += s; m2 += s * s;
        }
        m /= 16.0; m2 /= 16.0;
        float v = dot(m2 - m * m, float3(1));
        if (v < bestVar) { bestVar = v; bestMean = m; }
    }
    float3 c = bestMean;
    // brush strokes follow the image gradient
    float2 g = t.grad(2.0);
    float2 sp = rotate2d(t.pos, atan2(g.y, g.x + 1e-6));
    float stroke = vnoise(sp * float2(0.6, 0.06)) - 0.5;
    float canvas = vnoise(t.pos * 0.8) * vnoise(t.pos.yx * 0.8) - 0.25;
    c *= 1.0 + (stroke * 0.25 + canvas * 0.3) * t.p.texture;
    return float4(c, 1.0);
}
