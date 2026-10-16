/*{
  "NAME": "Heart Eyes",
  "CATEGORIES": ["Face", "Overlay"],
  "DESCRIPTION": "Pulsing cartoon hearts over your eyes. 😍",
  "FACE": true,
  "INPUTS": [ { "NAME": "size", "LABEL": "Size", "TYPE": "float", "DEFAULT": 1, "MIN": 0.4, "MAX": 2.5 },
              { "NAME": "color", "LABEL": "Color", "TYPE": "color", "DEFAULT": [0.95, 0.1, 0.3, 1] } ]
}*/
float heart(float2 p) {   // p in roughly [-1,1]; < 0 inside
    p.y = -p.y + 0.25;
    p.x = abs(p.x);
    if (p.y + p.x > 1.0) return sqrt(dot(p - float2(0.25, 0.75), p - float2(0.25, 0.75))) - sqrt(2.0) / 4.0;
    return sqrt(min(dot(p - float2(0.0, 1.0), p - float2(0.0, 1.0)), dot(p - 0.5 * max(p.x + p.y, 0.0), p - 0.5 * max(p.x + p.y, 0.0)))) * sign(p.x - p.y);
}
float4 effect(Twz t) {
    float4 c = t.sample(t.uv);
    if (t.faceCount == 0) return c;
    float ed = length((t.rightEye - t.leftEye) * float2(t.aspect, 1.0));
    float pulse = 1.0 + 0.12 * sin(t.time * 8.0);
    float r = ed * 0.45 * t.p.size * pulse;
    float3 col = c.rgb;
    for (int i = 0; i < 2; i++) {
        float2 e = t.centered(i == 0 ? t.leftEye : t.rightEye);
        float2 q = rotate2d(t.centered() - e, -t.faceRoll) / r;
        float h = heart(q * 1.15 + float2(0, 0.1));
        col = mix(col, float3(0.4, 0.0, 0.05), smoothstep(0.08, 0.0, h) * 0.9);
        col = mix(col, t.p.color.rgb, smoothstep(0.0, -0.04, h));
        col += smoothstep(0.25, 0.0, length(q - float2(-0.35, -0.3))) * 0.5 * step(h, 0.0);
    }
    return float4(col, 1.0);
}
