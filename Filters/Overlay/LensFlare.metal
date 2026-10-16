/*{
  "NAME": "Lens Flare",
  "CATEGORIES": ["Overlay", "Photo"],
  "DESCRIPTION": "J.J. Abrams would approve: streak, glow and ghost rings from a light source (drag to move).",
  "INPUTS": [ { "NAME": "light", "LABEL": "Light Position", "TYPE": "point2D", "DEFAULT": [0.2, 0.2] },
              { "NAME": "intensity", "LABEL": "Intensity", "TYPE": "float", "DEFAULT": 1, "MIN": 0, "MAX": 3 },
              { "NAME": "tint", "LABEL": "Tint", "TYPE": "color", "DEFAULT": [1.0, 0.85, 0.6, 1] },
              { "NAME": "streak", "LABEL": "Anamorphic Streak", "TYPE": "bool", "DEFAULT": true } ]
}*/
float4 effect(Twz t) {
    float3 c = t.sample(t.uv).rgb;
    float2 p = t.centered();
    float2 l = t.centered(t.p.light);
    float2 d = p - l;
    float glow = exp(-length(d) * 6.0) * 0.8 + exp(-length(d) * 30.0);
    float3 add = t.p.tint.rgb * glow;
    if (t.p.streak) add += float3(0.5, 0.7, 1.0) * exp(-abs(d.y) * 120.0) * exp(-abs(d.x) * 1.5) * 0.6;
    // ghosts along the line through the center
    for (int i = 1; i <= 5; i++) {
        float k = -0.4 * float(i) + 0.3;
        float2 gc = l * k;
        float r = 0.02 + 0.03 * float(i % 3);
        float ring = smoothstep(r, r * 0.7, length(p - gc)) * 0.12;
        add += hsv2rgb(float3(fract(0.1 * float(i) + 0.5), 0.6, 1.0)) * ring;
    }
    return float4(c + add * t.p.intensity, 1.0);
}
