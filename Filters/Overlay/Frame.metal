/*{
  "NAME": "Frame",
  "CATEGORIES": ["Overlay"],
  "DESCRIPTION": "A border around the picture: solid, rounded, glowing or a Polaroid card.",
  "INPUTS": [ { "NAME": "style", "LABEL": "Style", "TYPE": "long", "DEFAULT": 0, "VALUES": [0, 1, 2, 3], "LABELS": ["Solid", "Rounded Card", "Neon Glow", "Polaroid"] },
              { "NAME": "width", "LABEL": "Width", "TYPE": "float", "DEFAULT": 0.03, "MIN": 0.005, "MAX": 0.2 },
              { "NAME": "color", "LABEL": "Color", "TYPE": "color", "DEFAULT": [1, 1, 1, 1] },
              { "NAME": "radius", "LABEL": "Corner Radius", "TYPE": "float", "DEFAULT": 0.05, "MIN": 0, "MAX": 0.3 } ]
}*/
float4 effect(Twz t) {
    float4 c = t.sample(t.uv);
    float2 p = (t.uv - 0.5) * float2(t.aspect, 1.0);
    float2 half_ = float2(t.aspect, 1.0) * 0.5;
    float w = t.p.width;
    if (t.p.style == 0) {
        float d = sdBox(p, half_ - w);
        return float4(mix(c.rgb, t.p.color.rgb, step(0.0, d) * t.p.color.a), 1.0);
    }
    if (t.p.style == 1) {
        float d = sdRoundBox(p, half_ - w, t.p.radius);
        float3 bg = t.p.color.rgb * (1.0 - 0.3 * smoothstep(0.0, 0.05, -sdRoundBox(p + float2(-0.01, -0.015), half_ - w, t.p.radius)));
        return float4(mix(c.rgb, t.p.color.rgb, smoothstep(-0.002, 0.002, d)), 1.0);
    }
    if (t.p.style == 2) {
        float d = abs(sdRoundBox(p, half_ - w * 1.5, t.p.radius));
        float glow = exp(-d * 60.0 / max(w * 30.0, 0.1)) * (0.8 + 0.2 * sin(t.time * 4.0));
        return float4(c.rgb + t.p.color.rgb * glow * 1.2 * float3(1.0, 0.4, 1.0), 1.0);
    }
    // Polaroid: wider bottom border
    float2 inner = half_ - float2(w, w);
    float2 off = float2(0, -w * 1.8);
    float d = sdBox(p - off * 0.5, inner - float2(0, w * 0.9));
    return float4(mix(c.rgb, float3(0.96, 0.95, 0.92), step(0.0, d)), 1.0);
}
