/*{
  "NAME": "Tiny Face",
  "CATEGORIES": ["Face", "Distortion"],
  "DESCRIPTION": "Shrinks your features into the middle of your face — oddly hilarious.",
  "FACE": true,
  "INPUTS": [ { "NAME": "amount", "LABEL": "Shrink", "TYPE": "float", "DEFAULT": 0.6, "MIN": 0, "MAX": 1 } ]
}*/
float4 effect(Twz t) {
    if (t.faceCount == 0) return t.sample(t.uv);
    float2 c = (t.leftEye + t.rightEye + t.mouth) / 3.0;
    float R = max(t.face.z * t.aspect, t.face.w) * 0.55;
    float2 d = (t.uv - c) * float2(t.aspect, 1.0);
    float r = length(d);
    if (r >= R) return t.sample(t.uv);
    float k = r / R;
    float s = 1.0 + t.p.amount * (1.0 - k) * (1.0 - k) * 1.6;
    return t.sample(c + d * s / float2(t.aspect, 1.0));
}
