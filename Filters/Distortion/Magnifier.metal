/*{
  "NAME": "Magnifying Glass",
  "CATEGORIES": ["Distortion", "Face"],
  "DESCRIPTION": "A round lens that magnifies — place it with the mouse, or let it follow your face.",
  "FACE": true,
  "INPUTS": [ { "NAME": "center", "LABEL": "Position", "TYPE": "point2D", "DEFAULT": [0.5, 0.45] },
              { "NAME": "follow", "LABEL": "Follow Face", "TYPE": "bool", "DEFAULT": false },
              { "NAME": "radius", "LABEL": "Radius", "TYPE": "float", "DEFAULT": 0.18, "MIN": 0.05, "MAX": 0.5 },
              { "NAME": "zoom", "LABEL": "Magnification", "TYPE": "float", "DEFAULT": 2, "MIN": 1, "MAX": 6 } ]
}*/
float4 effect(Twz t) {
    float2 c = t.p.center;
    if (t.p.follow && t.faceCount > 0) c = float2(t.face.x + t.face.z * 0.5, t.face.y + t.face.w * 0.5);
    float2 d = (t.uv - c) * float2(t.aspect, 1.0);
    float r = length(d);
    float4 col = t.sample(t.uv);
    if (r > t.p.radius + 0.012) return col;
    if (r > t.p.radius) return float4(mix(col.rgb, float3(0.15, 0.12, 0.1), 0.9), 1.0);   // rim
    float k = r / t.p.radius;
    float2 q = c + d / float2(t.aspect, 1.0) / t.p.zoom * (1.0 + 0.3 * k * k);
    float3 m = t.sample(q).rgb;
    m += smoothstep(0.5, 0.0, length(d / t.p.radius - float2(-0.4, -0.4))) * 0.25;   // glare
    return float4(m, 1.0);
}
