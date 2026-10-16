/*{
  "NAME": "Earthquake",
  "CATEGORIES": ["CamTwist", "Geometry", "Time"],
  "DESCRIPTION": "Shakes the picture as if the ground were moving.",
  "INPUTS": [
    { "NAME": "strength", "LABEL": "Strength", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0, "MAX": 1 },
    { "NAME": "speed", "LABEL": "Speed", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0.05, "MAX": 2 },
    { "NAME": "blur", "LABEL": "Motion Blur", "TYPE": "bool", "DEFAULT": true }
  ]
}*/
float2 shake(float time, float s, float sp) {
    float k = time * sp * 18.0;
    return (float2(vnoise(float2(k, 1.3)), vnoise(float2(k, 7.9))) - 0.5) * 0.12 * s;
}
float4 effect(Twz t) {
    float s = t.p.strength;
    float2 o = shake(t.time, s, t.p.speed);
    float rot = (vnoise(float2(t.time * t.p.speed * 14.0, 3.3)) - 0.5) * 0.12 * s;
    float zoom = 1.0 + 0.14 * s;
    float2 d = (t.uv - 0.5) * float2(t.aspect, 1.0);
    d = rotate2d(d, rot) / zoom;
    float2 uv = d / float2(t.aspect, 1.0) + 0.5 + o;
    if (!t.p.blur) return t.sample(uv);
    float2 v = o - shake(t.time - 0.03, s, t.p.speed);
    float4 acc = 0;
    for (int i = 0; i < 5; i++) acc += t.sample(uv - v * (float(i) / 4.0));
    return acc / 5.0;
}
