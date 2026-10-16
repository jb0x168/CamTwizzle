/*{
  "NAME": "Laser Eyes",
  "CATEGORIES": ["Face", "Overlay"],
  "DESCRIPTION": "Red-hot laser beams blast out of your eyes.",
  "FACE": true,
  "INPUTS": [ { "NAME": "color", "LABEL": "Color", "TYPE": "color", "DEFAULT": [1, 0.1, 0.05, 1] },
              { "NAME": "angle", "LABEL": "Beam Angle", "TYPE": "float", "DEFAULT": -35, "MIN": -180, "MAX": 180 },
              { "NAME": "width", "LABEL": "Beam Width", "TYPE": "float", "DEFAULT": 1, "MIN": 0.3, "MAX": 3 },
              { "NAME": "flare", "LABEL": "Eye Flare", "TYPE": "float", "DEFAULT": 1, "MIN": 0, "MAX": 3 } ]
}*/
float beam(float2 p, float2 o, float2 dir, float w) {
    float2 d = p - o;
    float along = dot(d, dir);
    if (along < 0.0) return 0.0;
    float perp = abs(d.x * dir.y - d.y * dir.x);
    float ww = w * (1.0 + along * 0.6);
    return exp(-perp * perp / (ww * ww)) * (0.85 + 0.15 * sin(along * 80.0));
}
float4 effect(Twz t) {
    float4 c = t.sample(t.uv);
    if (t.faceCount == 0) return c;
    float2 p = t.centered();
    float ed = length((t.rightEye - t.leftEye) * float2(t.aspect, 1.0));
    float a = (t.p.angle + 90.0) * PI / 180.0 + t.faceRoll;
    float2 dir = float2(cos(a), sin(a));
    float w = ed * 0.06 * t.p.width;
    float b = beam(p, t.centered(t.leftEye), dir, w) + beam(p, t.centered(t.rightEye), dir, w);
    float flare = 0;
    for (int i = 0; i < 2; i++) {
        float2 e = t.centered(i == 0 ? t.leftEye : t.rightEye);
        float2 d = p - e;
        flare += exp(-dot(d, d) / (ed * ed * 0.02)) + 0.4 * exp(-abs(d.y) / (ed * 0.01)) * exp(-abs(d.x) / (ed * 0.6));
    }
    float flick = 0.85 + 0.15 * hash11(floor(t.time * 30.0));
    float3 col = c.rgb + t.p.color.rgb * (b * 1.6 + flare * t.p.flare) * flick;
    col += float3(1.0) * smoothstep(0.6, 1.4, b + flare) * 0.6;
    return float4(col, 1.0);
}
