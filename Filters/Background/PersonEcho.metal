/*{
  "NAME": "Clone Trail",
  "CATEGORIES": ["Background", "Time"],
  "DESCRIPTION": "Fading copies of you trail behind as you move; the background stays clean.",
  "MASK": true,
  "INPUTS": [ { "NAME": "persistence", "LABEL": "Persistence", "TYPE": "float", "DEFAULT": 0.9, "MIN": 0.5, "MAX": 0.99 },
              { "NAME": "tint", "LABEL": "Tint Clones", "TYPE": "bool", "DEFAULT": true } ],
  "PASSES": [ { "TARGET": "echo", "PERSISTENT": true }, {} ]
}*/
float4 effect(Twz t) {
    float3 c = t.sample(t.uv).rgb;
    float m = smoothstep(0.4, 0.6, t.maskAt(t.uv));
    if (t.pass == 0) {
        float4 prev = t.sample(t.echo, t.uv);
        float a = prev.a * t.p.persistence;
        float3 pc = prev.rgb;
        if (t.frame == 0) a = 0;
        // new person pixels replace; elsewhere keep fading clone
        return m > 0.5 ? float4(c, 1.0) : float4(pc, a);
    }
    float4 e = t.sample(t.echo, t.uv);
    float3 clone = e.rgb;
    if (t.p.tint) clone = mix(clone, hsv2rgb(float3(fract(e.a * 2.0 + t.time * 0.1), 0.7, 1.0)) * luma(clone) * 1.6, 0.5);
    float3 out = mix(c, clone, e.a * (1.0 - m) * 0.8);
    return float4(out, 1.0);
}
