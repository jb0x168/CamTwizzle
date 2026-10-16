/*{
  "NAME": "Lomo",
  "CATEGORIES": ["Photo", "Color"],
  "DESCRIPTION": "Toy-camera look: punchy cross-processed colors and heavy vignetting.",
  "INPUTS": [ { "NAME": "amount", "LABEL": "Amount", "TYPE": "float", "DEFAULT": 1, "MIN": 0, "MAX": 1 },
              { "NAME": "vignette", "LABEL": "Vignette", "TYPE": "float", "DEFAULT": 0.7, "MIN": 0, "MAX": 1 } ]
}*/
float4 effect(Twz t) {
    float3 c = t.sample(t.uv).rgb;
    float3 x = c;
    x.r = smoothstep(-0.05, 1.0, x.r);
    x.g = smoothstep(0.02, 0.98, x.g);
    x.b = x.b * 0.75 + 0.12;
    x = mix(float3(luma(x)), x, 1.35);
    float d = length((t.uv - 0.5) * float2(t.aspect, 1.0));
    x *= 1.0 - t.p.vignette * smoothstep(0.3, 1.0, d);
    return float4(clamp(mix(c, x, t.p.amount), 0.0, 1.0), 1.0);
}
