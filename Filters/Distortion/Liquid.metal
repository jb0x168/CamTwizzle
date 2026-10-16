/*{
  "NAME": "Liquid",
  "CATEGORIES": ["Distortion"],
  "DESCRIPTION": "The picture flows like it's under moving water / melting.",
  "INPUTS": [ { "NAME": "amount", "LABEL": "Amount", "TYPE": "float", "DEFAULT": 0.4, "MIN": 0, "MAX": 1.5 },
              { "NAME": "scale", "LABEL": "Scale", "TYPE": "float", "DEFAULT": 3, "MIN": 0.5, "MAX": 12 },
              { "NAME": "speed", "LABEL": "Speed", "TYPE": "float", "DEFAULT": 0.3, "MIN": 0, "MAX": 2 } ]
}*/
float4 effect(Twz t) {
    float2 p = t.centered() * t.p.scale;
    float tt = t.time * t.p.speed;
    float2 q = float2(fbm(p + tt, 4), fbm(p + float2(5.2, 1.3) - tt, 4));
    float2 r = float2(fbm(p + 4.0 * q + float2(1.7, 9.2) + tt * 0.5, 4), fbm(p + 4.0 * q + float2(8.3, 2.8), 4));
    return t.sampleMirror(t.input, t.uv + (r - 0.5) * 0.08 * t.p.amount);
}
