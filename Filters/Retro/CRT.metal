/*{
  "NAME": "CRT Monitor",
  "CATEGORIES": ["Retro"],
  "DESCRIPTION": "Curved glass, scanlines, an RGB aperture grille, glow and rounded corners.",
  "INPUTS": [
    { "NAME": "curvature", "LABEL": "Curvature", "TYPE": "float", "DEFAULT": 0.12, "MIN": 0, "MAX": 0.4 },
    { "NAME": "scanlines", "LABEL": "Scanlines", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0, "MAX": 1 },
    { "NAME": "lines", "LABEL": "Line Count", "TYPE": "float", "DEFAULT": 360, "MIN": 120, "MAX": 1080 },
    { "NAME": "mask", "LABEL": "Phosphor Mask", "TYPE": "float", "DEFAULT": 0.35, "MIN": 0, "MAX": 1 },
    { "NAME": "glow", "LABEL": "Glow", "TYPE": "float", "DEFAULT": 0.3, "MIN": 0, "MAX": 1 }
  ]
}*/
float4 effect(Twz t) {
    float2 q = t.uv * 2.0 - 1.0;
    float2 off = q.yx * q.yx * t.p.curvature;
    q += q * off;
    float2 uv = q * 0.5 + 0.5;
    if (any(uv < 0.0) || any(uv > 1.0)) return float4(0, 0, 0, 1);
    float3 c = t.sample(uv).rgb;
    float3 g = t.blurAt(uv, 6.0 * t.inputSize.y / 720.0).rgb;
    c += g * g * t.p.glow;
    float sl = 0.5 + 0.5 * cos(uv.y * t.p.lines * TAU);
    c *= 1.0 - t.p.scanlines * 0.6 * (1.0 - sl) * (1.0 - luma(c) * 0.5);
    int m = int(fmod(t.pos.x, 3.0));
    float3 mask = m == 0 ? float3(1, 0.4, 0.4) : (m == 1 ? float3(0.4, 1, 0.4) : float3(0.4, 0.4, 1));
    c *= mix(float3(1.0), mask * 1.35, t.p.mask);
    // vignette + rounded corner fade
    float2 e = smoothstep(float2(0.0), float2(0.02, 0.03), uv) * smoothstep(float2(0.0), float2(0.02, 0.03), 1.0 - uv);
    c *= e.x * e.y;
    c *= 1.0 - 0.35 * dot(q, q) * 0.5;
    return float4(c, 1.0);
}
