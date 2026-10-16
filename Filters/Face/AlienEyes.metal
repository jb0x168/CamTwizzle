/*{
  "NAME": "Big Eyes",
  "CATEGORIES": ["Face", "Distortion"],
  "DESCRIPTION": "Anime/alien eyes: magnifies each eye.",
  "FACE": true,
  "INPUTS": [ { "NAME": "amount", "LABEL": "Amount", "TYPE": "float", "DEFAULT": 0.6, "MIN": 0, "MAX": 1 },
              { "NAME": "size", "LABEL": "Area", "TYPE": "float", "DEFAULT": 1, "MIN": 0.4, "MAX": 2 } ]
}*/
float2 bulge(float2 p, float2 c, float R, float amt) {
    float2 d = p - c;
    float r = length(d);
    if (r >= R) return p;
    float k = r / R;
    return c + d * (1.0 - amt * (1.0 - k * k) * 0.6);
}
float4 effect(Twz t) {
    if (t.faceCount == 0) return t.sample(t.uv);
    float ed = length((t.rightEye - t.leftEye) * float2(t.aspect, 1.0));
    float R = ed * 0.45 * t.p.size;
    float2 p = t.centered();
    p = bulge(p, t.centered(t.leftEye), R, t.p.amount);
    p = bulge(p, t.centered(t.rightEye), R, t.p.amount);
    return t.sample(p / float2(t.aspect, 1.0) + 0.5);
}
