/*{
  "NAME": "Pixel Sort",
  "CATEGORIES": ["Glitch", "Stylize"],
  "DESCRIPTION": "Bright regions melt into streaks, imitating the pixel-sorting glitch-art technique.",
  "INPUTS": [
    { "NAME": "threshold", "LABEL": "Threshold", "TYPE": "float", "DEFAULT": 0.55, "MIN": 0, "MAX": 1 },
    { "NAME": "length", "LABEL": "Streak Length", "TYPE": "float", "DEFAULT": 0.25, "MIN": 0.02, "MAX": 1 },
    { "NAME": "direction", "LABEL": "Direction", "TYPE": "long", "DEFAULT": 0, "VALUES": [0, 1, 2, 3], "LABELS": ["Down", "Up", "Right", "Left"] }
  ]
}*/
float4 effect(Twz t) {
    float2 dir = t.p.direction == 0 ? float2(0, -1) : (t.p.direction == 1 ? float2(0, 1) : (t.p.direction == 2 ? float2(-1, 0) : float2(1, 0)));
    float4 here = t.sample(t.uv);
    if (luma(here.rgb) < t.p.threshold) return here;
    // walk "upstream" while pixels stay above the threshold; streak takes the run's start color
    float stepLen = t.p.length / 48.0;
    float2 q = t.uv;
    float3 acc = here.rgb; float n = 1;
    float3 brightest = here.rgb;
    for (int i = 1; i <= 48; i++) {
        float2 s = t.uv + dir * stepLen * float(i) * float2(1.0 / t.aspect, 1.0) * (0.6 + 0.4 * hash11(floor(t.uv.x * t.inputSize.x) + float(i)));
        float3 c = t.sample(s).rgb;
        if (luma(c) < t.p.threshold || any(s < 0.0) || any(s > 1.0)) break;
        q = s; acc += c; n += 1;
        if (luma(c) > luma(brightest)) brightest = c;
    }
    float k = clamp(n / 48.0, 0.0, 1.0);
    float3 streak = mix(acc / n, brightest, 0.5);
    return float4(mix(here.rgb, streak, 0.85 * smoothstep(0.0, 0.2, k)), 1.0);
}
