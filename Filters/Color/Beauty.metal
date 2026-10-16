/*{
  "NAME": "Beauty",
  "CATEGORIES": ["Color", "Face"],
  "DESCRIPTION": "Video-call touch-up: smooths skin while keeping eyes and edges sharp, with a subtle warm glow.",
  "INPUTS": [ { "NAME": "smooth", "LABEL": "Smoothing", "TYPE": "float", "DEFAULT": 0.6, "MIN": 0, "MAX": 1 },
              { "NAME": "glow", "LABEL": "Glow", "TYPE": "float", "DEFAULT": 0.3, "MIN": 0, "MAX": 1 },
              { "NAME": "warmth", "LABEL": "Warmth", "TYPE": "float", "DEFAULT": 0.2, "MIN": -1, "MAX": 1 } ]
}*/
float4 effect(Twz t) {
    float3 c0 = t.sample(t.uv).rgb;
    float3 acc = c0; float wsum = 1;
    float r = 2.5 * t.inputSize.y / 720.0;
    for (int j = -3; j <= 3; j++) for (int i = -3; i <= 3; i++) {
        if (i == 0 && j == 0) continue;
        float3 s = t.offset(float2(i, j) * r).rgb;
        float w = exp(-dot(s - c0, s - c0) * 60.0) * exp(-float(i * i + j * j) / 8.0);
        acc += s * w; wsum += w;
    }
    float3 sm = acc / wsum;
    float3 hsv = rgb2hsv(c0);
    float skin = smoothstep(0.13, 0.04, abs(hsv.x - 0.06)) * smoothstep(0.1, 0.3, hsv.y) * smoothstep(0.15, 0.35, hsv.z);
    float3 c = mix(c0, sm, t.p.smooth * (0.35 + 0.65 * skin));
    float3 g = t.blur(10.0 * t.inputSize.y / 720.0).rgb;
    c = blendScreen(c, g * 0.35 * t.p.glow);
    c *= float3(1.0 + 0.06 * t.p.warmth, 1.0, 1.0 - 0.06 * t.p.warmth);
    return float4(clamp(c, 0.0, 1.0), 1.0);
}
