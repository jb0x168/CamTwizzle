/*{
  "NAME": "3D Rotate",
  "CATEGORIES": ["CamTwist", "Geometry"],
  "DESCRIPTION": "Tilt and spin the picture as a flat card in 3D space (CamTwist's Rotation Translation).",
  "INPUTS": [
    { "NAME": "rotX", "LABEL": "Tilt (X)", "TYPE": "float", "DEFAULT": 20, "MIN": -89, "MAX": 89 },
    { "NAME": "rotY", "LABEL": "Turn (Y)", "TYPE": "float", "DEFAULT": -25, "MIN": -89, "MAX": 89 },
    { "NAME": "rotZ", "LABEL": "Roll (Z)", "TYPE": "float", "DEFAULT": 0, "MIN": -180, "MAX": 180 },
    { "NAME": "distance", "LABEL": "Distance", "TYPE": "float", "DEFAULT": 1.3, "MIN": 0.8, "MAX": 4 },
    { "NAME": "spin", "LABEL": "Auto Spin", "TYPE": "float", "DEFAULT": 0, "MIN": -1, "MAX": 1 },
    { "NAME": "background", "LABEL": "Background", "TYPE": "color", "DEFAULT": [0.05, 0.05, 0.08, 1] }
  ]
}*/
float4 effect(Twz t) {
    float ax = t.p.rotX * PI / 180.0, ay = (t.p.rotY + t.time * t.p.spin * 90.0) * PI / 180.0, az = t.p.rotZ * PI / 180.0;
    float3x3 rx = float3x3(float3(1, 0, 0), float3(0, cos(ax), -sin(ax)), float3(0, sin(ax), cos(ax)));
    float3x3 ry = float3x3(float3(cos(ay), 0, sin(ay)), float3(0, 1, 0), float3(-sin(ay), 0, cos(ay)));
    float3x3 rz = float3x3(float3(cos(az), -sin(az), 0), float3(sin(az), cos(az), 0), float3(0, 0, 1));
    float3x3 R = rz * ry * rx;
    float2 p = t.centered();
    float3 ro = float3(0, 0, -t.p.distance);
    float3 rd = normalize(float3(p, 1.0));
    // plane through origin with normal R*(0,0,1)
    float3 n = R * float3(0, 0, 1);
    float denom = dot(rd, n);
    if (abs(denom) < 1e-4) return t.p.background;
    float th = -dot(ro, n) / denom;
    if (th < 0.0) return t.p.background;
    float3 hp = transpose(R) * (ro + rd * th);
    float2 q = hp.xy / float2(t.aspect, 1.0) + 0.5;
    if (any(q < 0.0) || any(q > 1.0)) return t.p.background;
    float4 c = t.sample(q);
    c.rgb *= denom < 0.0 ? 0.6 : 1.0;      // back side a bit darker
    return float4(c.rgb, 1.0);
}
