/*{
  "NAME": "Silhouette",
  "CATEGORIES": ["Background", "Stylize"],
  "DESCRIPTION": "You become a solid shadow against the scene (or a cut-out against a color).",
  "MASK": true,
  "INPUTS": [ { "NAME": "color", "LABEL": "Person Color", "TYPE": "color", "DEFAULT": [0.02, 0.02, 0.03, 1] },
              { "NAME": "invert", "LABEL": "Invert (keep person, color background)", "TYPE": "bool", "DEFAULT": false },
              { "NAME": "outline", "LABEL": "Outline", "TYPE": "color", "DEFAULT": [1, 0.8, 0.2, 0] } ]
}*/
float4 effect(Twz t) {
    float3 c = t.sample(t.uv).rgb;
    float m = smoothstep(0.4, 0.6, t.maskAt(t.uv));
    float e = abs(t.maskAt(t.uv + float2(0.003, 0)) - t.maskAt(t.uv - float2(0.003, 0))) + abs(t.maskAt(t.uv + float2(0, 0.005)) - t.maskAt(t.uv - float2(0, 0.005)));
    float3 out = t.p.invert ? mix(t.p.color.rgb, c, m) : mix(c, t.p.color.rgb, m);
    out = mix(out, t.p.outline.rgb, smoothstep(0.2, 0.8, e) * t.p.outline.a);
    return float4(out, 1.0);
}
