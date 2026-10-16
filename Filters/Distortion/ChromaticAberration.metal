/*{
  "NAME": "Chromatic Aberration",
  "CATEGORIES": ["Distortion", "Photo"],
  "DESCRIPTION": "Cheap-lens color fringing that grows towards the edges.",
  "INPUTS": [ { "NAME": "amount", "LABEL": "Amount", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0, "MAX": 2 },
              { "NAME": "center", "LABEL": "Center", "TYPE": "point2D", "DEFAULT": [0.5, 0.5] } ]
}*/
float4 effect(Twz t) {
    float2 d = t.uv - t.p.center;
    float k = dot(d * float2(t.aspect, 1.0), d * float2(t.aspect, 1.0)) * 0.04 * t.p.amount;
    float r = t.sample(t.uv + d * k).r;
    float g = t.sample(t.uv).g;
    float b = t.sample(t.uv - d * k).b;
    return float4(r, g, b, 1.0);
}
