/*{
  "NAME": "Fisheye",
  "CATEGORIES": ["Distortion"],
  "DESCRIPTION": "Barrel (fisheye) or pincushion lens distortion. Great for the classic 'peephole' / skate-video look.",
  "INPUTS": [ { "NAME": "amount", "LABEL": "Amount", "TYPE": "float", "DEFAULT": 0.6, "MIN": -1, "MAX": 1.5 },
              { "NAME": "zoom", "LABEL": "Zoom", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0.5, "MAX": 2 },
              { "NAME": "circle", "LABEL": "Circular Frame", "TYPE": "bool", "DEFAULT": false } ]
}*/
float4 effect(Twz t) {
    float2 p = t.centered() * 2.0;
    float r = length(p);
    float k = t.p.amount;
    float2 q = p * (1.0 - k * 0.25 * r * r) / (1.0 - k * 0.25) / t.p.zoom;
    if (k > 0.0) q = p * (1.0 + k * 0.35 * r * r) / (1.0 + k * 0.35) / t.p.zoom * (1.0 - k * 0.2);
    float2 uv = q * 0.5 / float2(t.aspect, 1.0) + 0.5;
    if (t.p.circle && r > 1.0) return float4(0, 0, 0, 1);
    if (any(uv < 0.0) || any(uv > 1.0)) return float4(0, 0, 0, 1);
    return t.sample(uv);
}
