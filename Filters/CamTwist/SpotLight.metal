/*{
  "NAME": "Spotlight",
  "CATEGORIES": ["CamTwist", "Overlay", "Face"],
  "DESCRIPTION": "Darkens everything except a circle of light — fixed, wandering like a searchlight, or following your face.",
  "FACE": true,
  "INPUTS": [
    { "NAME": "mode", "LABEL": "Mode", "TYPE": "long", "DEFAULT": 2, "VALUES": [0, 1, 2], "LABELS": ["Fixed", "Wander", "Follow Face"] },
    { "NAME": "center", "LABEL": "Center", "TYPE": "point2D", "DEFAULT": [0.5, 0.45] },
    { "NAME": "radius", "LABEL": "Radius", "TYPE": "float", "DEFAULT": 0.28, "MIN": 0.05, "MAX": 0.8 },
    { "NAME": "softness", "LABEL": "Softness", "TYPE": "float", "DEFAULT": 0.12, "MIN": 0.0, "MAX": 0.5 },
    { "NAME": "darkness", "LABEL": "Darkness", "TYPE": "float", "DEFAULT": 0.85, "MIN": 0, "MAX": 1 },
    { "NAME": "tint", "LABEL": "Light Tint", "TYPE": "color", "DEFAULT": [1, 0.97, 0.85, 1] }
  ]
}*/
float4 effect(Twz t) {
    float2 c = t.p.center;
    float r = t.p.radius;
    if (t.p.mode == 1) c = float2(0.5 + 0.32 * sin(t.time * 0.53), 0.5 + 0.25 * sin(t.time * 0.81 + 1.0));
    if (t.p.mode == 2 && t.faceCount > 0) {
        c = float2(t.face.x + t.face.z * 0.5, t.face.y + t.face.w * 0.5);
        r = max(t.face.z * t.aspect, t.face.w) * 0.85 * (t.p.radius / 0.28);
    }
    float d = length((t.uv - c) * float2(t.aspect, 1.0));
    float light = smoothstep(r + t.p.softness, r - t.p.softness * 0.2, d);
    float3 col = t.sample(t.uv).rgb;
    col = col * mix(1.0 - t.p.darkness, 1.0, light) * mix(float3(1.0), t.p.tint.rgb, light);
    return float4(col, 1.0);
}
