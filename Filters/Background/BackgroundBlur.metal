/*{
  "NAME": "Background Blur",
  "CATEGORIES": ["Background"],
  "DESCRIPTION": "Portrait mode: blurs everything except you (person segmentation).",
  "MASK": true,
  "INPUTS": [ { "NAME": "blur", "LABEL": "Blur", "TYPE": "float", "DEFAULT": 12, "MIN": 0, "MAX": 40 },
              { "NAME": "dim", "LABEL": "Dim Background", "TYPE": "float", "DEFAULT": 0.0, "MIN": 0, "MAX": 1 },
              { "NAME": "feather", "LABEL": "Edge Feather", "TYPE": "float", "DEFAULT": 0.15, "MIN": 0.01, "MAX": 0.5 } ],
  "PASSES": [ { "TARGET": "small", "SCALE": 0.25 }, {} ]
}*/
float4 effect(Twz t) {
    float r = t.p.blur * t.inputSize.y / 720.0;
    if (t.pass == 0) return t.blur(r * 0.5);
    float m = smoothstep(0.5 - t.p.feather, 0.5 + t.p.feather, t.maskAt(t.uv));
    // big soft blur from the quarter-res pass, sampled with a disc
    float3 acc = 0;
    for (int i = 0; i < 12; i++) {
        float a = float(i) * TAU / 12.0;
        acc += t.sample(t.small, t.uv + float2(cos(a), sin(a)) * r * 0.5 * t.texel).rgb;
    }
    float3 bg = (acc / 12.0) * (1.0 - t.p.dim);
    return float4(mix(bg, t.sample(t.uv).rgb, m), 1.0);
}
