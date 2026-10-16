/*{
  "NAME": "Tilt Shift",
  "CATEGORIES": ["Blur", "Photo"],
  "DESCRIPTION": "Miniature-model look: a sharp band with strongly blurred top and bottom, plus a saturation boost.",
  "INPUTS": [ { "NAME": "center", "LABEL": "Focus Line", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0, "MAX": 1 },
              { "NAME": "band", "LABEL": "Focus Band", "TYPE": "float", "DEFAULT": 0.18, "MIN": 0.02, "MAX": 0.6 },
              { "NAME": "blur", "LABEL": "Blur", "TYPE": "float", "DEFAULT": 10, "MIN": 0, "MAX": 30 },
              { "NAME": "saturation", "LABEL": "Saturation", "TYPE": "float", "DEFAULT": 1.35, "MIN": 0, "MAX": 2 } ]
}*/
float4 effect(Twz t) {
    float d = abs(t.uv.y - t.p.center);
    float k = smoothstep(t.p.band * 0.5, t.p.band * 0.5 + 0.25, d);
    float r = k * t.p.blur * t.inputSize.y / 720.0;
    float3 c = r > 0.5 ? (t.blur(r).rgb * 0.6 + t.blur(r * 0.5).rgb * 0.4) : t.sample(t.uv).rgb;
    float l = luma(c);
    c = mix(float3(l), c, t.p.saturation);
    return float4(clamp(c, 0.0, 1.0), 1.0);
}
