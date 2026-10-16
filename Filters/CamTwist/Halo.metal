/*{
  "NAME": "Halo",
  "CATEGORIES": ["CamTwist", "Face", "Overlay"],
  "DESCRIPTION": "A glowing angel halo that floats above your head (face tracked).",
  "FACE": true,
  "INPUTS": [
    { "NAME": "color", "LABEL": "Color", "TYPE": "color", "DEFAULT": [1.0, 0.85, 0.35, 1] },
    { "NAME": "size", "LABEL": "Size", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0.4, "MAX": 2 },
    { "NAME": "height", "LABEL": "Height Above Head", "TYPE": "float", "DEFAULT": 0.25, "MIN": 0, "MAX": 1 },
    { "NAME": "glow", "LABEL": "Glow", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0, "MAX": 3 }
  ]
}*/
float4 effect(Twz t) {
    float4 c = t.sample(t.uv);
    if (t.faceCount == 0) return c;
    float2 fc = float2(t.face.x + t.face.z * 0.5, t.face.y);                 // top of the face box
    float fw = t.face.z * t.aspect;                                         // face width in centered units
    float bob = sin(t.time * 2.0) * 0.012;
    float2 center = float2(fc.x, fc.y - t.face.w * t.p.height + bob);
    float2 d = (t.uv - center) * float2(t.aspect, 1.0);
    d = rotate2d(d, -t.faceRoll);
    float rx = fw * 0.42 * t.p.size, ry = fw * 0.09 * t.p.size;
    float e = length(d / float2(rx, ry));                                   // 1.0 on the ring
    float ring = smoothstep(0.16, 0.0, abs(e - 1.0));
    float glow = exp(-abs(e - 1.0) * 5.0) * 0.6 * t.p.glow;
    float3 col = c.rgb + t.p.color.rgb * glow;
    col = mix(col, mix(t.p.color.rgb, float3(1.0), 0.55), ring);
    return float4(col, 1.0);
}
