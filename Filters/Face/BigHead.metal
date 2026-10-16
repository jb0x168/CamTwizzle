/*{
  "NAME": "Big Head",
  "CATEGORIES": ["Face", "Distortion"],
  "DESCRIPTION": "Bobblehead mode: inflates your head (face tracked).",
  "FACE": true,
  "INPUTS": [ { "NAME": "amount", "LABEL": "Inflation", "TYPE": "float", "DEFAULT": 0.6, "MIN": -0.9, "MAX": 1 },
              { "NAME": "size", "LABEL": "Area", "TYPE": "float", "DEFAULT": 1.3, "MIN": 0.5, "MAX": 3 } ]
}*/
float4 effect(Twz t) {
    if (t.faceCount == 0) return t.sample(t.uv);
    float2 c = float2(t.face.x + t.face.z * 0.5, t.face.y + t.face.w * 0.45);
    float R = max(t.face.z * t.aspect, t.face.w) * 0.75 * t.p.size;
    float2 d = (t.uv - c) * float2(t.aspect, 1.0);
    float r = length(d);
    if (r >= R) return t.sample(t.uv);
    float k = r / R;
    float s = 1.0 - t.p.amount * (1.0 - k * k) * 0.55;    // >0 amount = magnify
    return t.sample(c + d * s / float2(t.aspect, 1.0));
}
