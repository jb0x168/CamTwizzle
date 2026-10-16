/*{
  "NAME": "Brick Builder",
  "CATEGORIES": ["Stylize"],
  "DESCRIPTION": "Rebuilds the picture out of plastic toy bricks with shiny studs.",
  "INPUTS": [ { "NAME": "bricks", "LABEL": "Bricks Across Height", "TYPE": "float", "DEFAULT": 36, "MIN": 8, "MAX": 120 },
              { "NAME": "quantize", "LABEL": "Limited Colors", "TYPE": "bool", "DEFAULT": true } ]
}*/
float4 effect(Twz t) {
    float n = t.p.bricks;
    float2 p = t.uv * float2(t.aspect, 1.0) * n;
    float2 cell = floor(p);
    float2 f = fract(p) - 0.5;
    float2 cuv = (cell + 0.5) / n / float2(t.aspect, 1.0);
    float3 c = t.blurAt(cuv, 0.35 * t.inputSize.y / n).rgb;
    if (t.p.quantize) c = posterize(c, 4.0);
    c = clamp(c * 1.1, 0.0, 1.0);
    // brick bevel
    float edge = max(abs(f.x), abs(f.y));
    float shade = 1.0 + (-f.x - f.y) * 0.25;
    c *= shade;
    c *= 1.0 - smoothstep(0.44, 0.5, edge) * 0.45;
    // stud: circle with highlight and shadow
    float r = length(f);
    float stud = smoothstep(0.31, 0.29, r);
    float rim = smoothstep(0.31, 0.27, length(f + float2(0.03, 0.03))) - stud;
    float hl = smoothstep(0.2, 0.0, length(f + float2(0.1, 0.1))) * stud;
    c *= 1.0 - max(rim, 0.0) * 0.5;
    c = mix(c, c * 1.15, stud) + hl * 0.25;
    return float4(c, 1.0);
}
