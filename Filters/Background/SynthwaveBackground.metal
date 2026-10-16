/*{
  "NAME": "Synthwave Background",
  "CATEGORIES": ["Background", "Generator"],
  "DESCRIPTION": "Put yourself in front of an 80s neon sunset with a scrolling grid.",
  "MASK": true,
  "INPUTS": [ { "NAME": "speed", "LABEL": "Grid Speed", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0, "MAX": 3 },
              { "NAME": "outline", "LABEL": "Neon Outline", "TYPE": "float", "DEFAULT": 0.6, "MIN": 0, "MAX": 2 } ]
}*/
float3 synth(float2 uv, float time, float aspect) {
    float horizon = 0.62;
    float3 sky = mix(float3(0.05, 0.0, 0.15), float3(0.85, 0.15, 0.55), smoothstep(0.0, horizon, uv.y));
    // sun with stripes
    float2 sp = (uv - float2(0.5, horizon - 0.18)) * float2(aspect, 1.0);
    float sr = length(sp);
    float stripes = step(0.5, fract((uv.y - horizon) * 40.0)) + step(uv.y, horizon - 0.25);
    float sun = smoothstep(0.2, 0.195, sr) * clamp(stripes, 0.0, 1.0);
    sky = mix(sky, mix(float3(1.0, 0.9, 0.2), float3(1.0, 0.2, 0.5), smoothstep(-0.2, 0.2, sp.y)), sun);
    sky += float3(1.0, 0.3, 0.6) * exp(-sr * 4.0) * 0.4;
    if (uv.y < horizon) return sky;
    // perspective grid
    float d = (uv.y - horizon);
    float z = 0.08 / max(d, 1e-3);
    float x = (uv.x - 0.5) * aspect * z * 6.0;
    float gz = fract(z * 2.0 - time);
    float gx = fract(x);
    float line = max(smoothstep(0.06, 0.0, abs(gx - 0.5) * 2.0 - 0.9) , smoothstep(0.1 * z, 0.0, abs(gz - 0.5) * 2.0 - 0.9));
    float3 ground = float3(0.05, 0.0, 0.1) + float3(1.0, 0.1, 0.8) * line * smoothstep(0.0, 0.1, d);
    return ground + float3(0.6, 0.1, 0.5) * exp(-d * 20.0) * 0.5;
}
float4 effect(Twz t) {
    float3 c = t.sample(t.uv).rgb;
    float m = smoothstep(0.35, 0.65, t.maskAt(t.uv));
    float e = abs(t.maskAt(t.uv + float2(0.004, 0)) - t.maskAt(t.uv - float2(0.004, 0))) + abs(t.maskAt(t.uv + float2(0, 0.006)) - t.maskAt(t.uv - float2(0, 0.006)));
    float3 bg = synth(t.uv, t.time * t.p.speed, t.aspect);
    float3 out = mix(bg, c * float3(1.05, 0.95, 1.1), m);
    out += float3(1.0, 0.2, 0.8) * smoothstep(0.1, 0.6, e) * t.p.outline;
    return float4(out, 1.0);
}
