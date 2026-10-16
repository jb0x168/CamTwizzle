/*{
  "NAME": "Infrared",
  "CATEGORIES": ["Color", "Photo"],
  "DESCRIPTION": "False-color infrared film (Aerochrome-ish): foliage goes pink-red, skies turn dark.",
  "INPUTS": [ { "NAME": "amount", "LABEL": "Amount", "TYPE": "float", "DEFAULT": 1, "MIN": 0, "MAX": 1 },
              { "NAME": "glow", "LABEL": "Glow", "TYPE": "float", "DEFAULT": 0.4, "MIN": 0, "MAX": 1 } ]
}*/
float4 effect(Twz t) {
    float3 c = t.sample(t.uv).rgb;
    float3 ir = float3(c.g * 1.2 + c.r * 0.2, c.r * 0.9, c.b * 0.6 + c.g * 0.1);
    ir.r = max(ir.r, c.g * 1.3);
    float3 g = t.blur(8.0 * t.inputSize.y / 720.0).rgb;
    ir += float3(g.g, g.g * 0.5, g.g * 0.6) * t.p.glow * 0.5;
    return float4(clamp(mix(c, ir, t.p.amount), 0.0, 1.0), 1.0);
}
