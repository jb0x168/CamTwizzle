/*{
  "NAME": "Floating Hearts",
  "CATEGORIES": ["Overlay"],
  "DESCRIPTION": "Hearts drift up from the bottom of the picture, Instagram-live style.",
  "INPUTS": [ { "NAME": "amount", "LABEL": "Amount", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0, "MAX": 1 },
              { "NAME": "size", "LABEL": "Size", "TYPE": "float", "DEFAULT": 1, "MIN": 0.3, "MAX": 3 },
              { "NAME": "side", "LABEL": "Only Right Side", "TYPE": "bool", "DEFAULT": true } ]
}*/
float heartSDF(float2 p) {
    p.y = -p.y + 0.3;
    p.x = abs(p.x);
    float a = atan2(p.x, p.y + 1e-6) / PI;
    float r = length(p);
    float h = abs(a);
    float d = (13.0 * h - 22.0 * h * h + 10.0 * h * h * h) / (6.0 - 5.0 * h);
    return r - d * 0.5;
}
float4 effect(Twz t) {
    float3 c = t.sample(t.uv).rgb;
    float2 p = t.centered();
    for (int i = 0; i < 14; i++) {
        if (float(i) >= t.p.amount * 14.0) break;
        float period = 3.0 + hash11(float(i)) * 2.0;
        float ph = fract(t.time / period + hash11(float(i) * 3.7));
        float x0 = t.p.side ? t.aspect * (0.3 + 0.15 * hash11(float(i) * 1.3)) : (hash11(float(i) * 1.3) - 0.5) * t.aspect;
        float2 hc = float2(x0 + sin(ph * 9.0 + float(i)) * 0.04, 0.55 - ph * 1.2);
        float s = 0.05 * t.p.size * (0.7 + 0.6 * hash11(float(i) * 5.1)) * smoothstep(0.0, 0.15, ph);
        float d = heartSDF((p - hc) / s);
        float alpha = smoothstep(0.05, -0.05, d) * (1.0 - smoothstep(0.7, 1.0, ph));
        float3 col = hsv2rgb(float3(0.95 + 0.1 * hash11(float(i) * 2.0), 0.75, 1.0));
        c = mix(c, col, alpha);
    }
    return float4(c, 1.0);
}
