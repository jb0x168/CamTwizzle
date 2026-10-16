/*{
  "NAME": "Face Swirl",
  "CATEGORIES": ["Face", "Distortion"],
  "DESCRIPTION": "Twists your face around its center.",
  "FACE": true,
  "INPUTS": [ { "NAME": "angle", "LABEL": "Twist", "TYPE": "float", "DEFAULT": 3, "MIN": -10, "MAX": 10 },
              { "NAME": "animate", "LABEL": "Animate", "TYPE": "bool", "DEFAULT": false } ]
}*/
float4 effect(Twz t) {
    if (t.faceCount == 0) return t.sample(t.uv);
    float2 c = t.centered(float2(t.face.x + t.face.z * 0.5, t.face.y + t.face.w * 0.5));
    float R = max(t.face.z * t.aspect, t.face.w) * 0.7;
    float2 d = t.centered() - c;
    float r = length(d);
    if (r >= R) return t.sample(t.uv);
    float k = 1.0 - r / R;
    float a = t.p.angle * k * k * (t.p.animate ? sin(t.time * 1.5) : 1.0);
    return t.sample((c + rotate2d(d, a)) / float2(t.aspect, 1.0) + 0.5);
}
