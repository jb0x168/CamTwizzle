/*{
  "NAME": "Sparkle Trail",
  "CATEGORIES": ["CamTwist", "Time", "Overlay"],
  "DESCRIPTION": "Moving things leave a trail of twinkling stars (after CamTwist's SparkleTrail).",
  "INPUTS": [
    { "NAME": "sensitivity", "LABEL": "Sensitivity", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0, "MAX": 1 },
    { "NAME": "density", "LABEL": "Density", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0, "MAX": 1 },
    { "NAME": "trail", "LABEL": "Trail Length", "TYPE": "float", "DEFAULT": 0.88, "MIN": 0.5, "MAX": 0.98 },
    { "NAME": "color", "LABEL": "Color", "TYPE": "color", "DEFAULT": [1, 0.9, 0.6, 1] }
  ],
  "PASSES": [ { "TARGET": "spark", "PERSISTENT": true, "FLOAT": true }, { "TARGET": "prevIn", "PERSISTENT": true, "SCALE": 0.25 }, {} ]
}*/
float star(float2 d, float s) {
    float r = length(d);
    float cross_ = max(smoothstep(s * 0.12, 0.0, abs(d.x)) * smoothstep(s, 0.0, abs(d.y)),
                       smoothstep(s * 0.12, 0.0, abs(d.y)) * smoothstep(s, 0.0, abs(d.x)));
    return max(cross_, smoothstep(s * 0.35, 0.0, r));
}
float4 effect(Twz t) {
    if (t.pass == 0) {
        float prev = t.sample(t.spark, t.uv).r * t.p.trail;
        float cellPx = 22.0;
        float2 cell = floor(t.pos / cellPx);
        float2 cc = (cell + 0.5) * cellPx;
        float2 cuv = cc / t.size;
        float motion = length(t.blurAt(cuv, 3.0).rgb - t.sample(t.prevIn, cuv).rgb);
        float lit = step(0.25 - t.p.sensitivity * 0.2, motion) * step(1.0 - t.p.density, hash12(cell + floor(t.time * 15.0)));
        if (t.frame < 3) lit = 0;
        float2 jitter = (hash22(cell + floor(t.time * 15.0)) - 0.5) * cellPx * 0.6;
        float s = star(t.pos - cc - jitter, cellPx * (0.4 + 0.5 * hash12(cell * 1.3)));
        return float4(max(prev, s * lit), 0, 0, 1);
    }
    if (t.pass == 1) return t.blur(3.0);
    float s = t.sample(t.spark, t.uv).r;
    float tw = 0.7 + 0.3 * sin(t.time * 20.0 + hash12(floor(t.pos / 22.0)) * 50.0);
    float3 c = t.sample(t.uv).rgb + t.p.color.rgb * s * tw * 1.4;
    return float4(c, 1.0);
}
