/*{
  "NAME": "Background Black & White",
  "CATEGORIES": ["Background", "Color"],
  "DESCRIPTION": "You stay in color, the world goes monochrome (or darker).",
  "MASK": true,
  "INPUTS": [ { "NAME": "desaturate", "LABEL": "Desaturate", "TYPE": "float", "DEFAULT": 1, "MIN": 0, "MAX": 1 },
              { "NAME": "dim", "LABEL": "Dim", "TYPE": "float", "DEFAULT": 0.2, "MIN": 0, "MAX": 1 } ]
}*/
float4 effect(Twz t) {
    float3 c = t.sample(t.uv).rgb;
    float m = smoothstep(0.35, 0.65, t.maskAt(t.uv));
    float3 bg = mix(c, float3(luma(c)), t.p.desaturate) * (1.0 - t.p.dim);
    return float4(mix(bg, c, m), 1.0);
}
