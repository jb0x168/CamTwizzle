/*{
  "NAME": "Picture in Picture",
  "CATEGORIES": ["CamTwist", "Overlay"],
  "DESCRIPTION": "Inset another live source (camera, screen, test pattern…) with a rounded border and shadow.",
  "INPUTS": [
    { "NAME": "source", "LABEL": "Source", "TYPE": "source", "DEFAULT": "pattern:bars" },
    { "NAME": "center", "LABEL": "Position", "TYPE": "point2D", "DEFAULT": [0.8, 0.78] },
    { "NAME": "size", "LABEL": "Size", "TYPE": "float", "DEFAULT": 0.3, "MIN": 0.05, "MAX": 1 },
    { "NAME": "radius", "LABEL": "Corner Radius", "TYPE": "float", "DEFAULT": 0.02, "MIN": 0, "MAX": 0.2 },
    { "NAME": "border", "LABEL": "Border", "TYPE": "float", "DEFAULT": 0.004, "MIN": 0, "MAX": 0.03 },
    { "NAME": "borderColor", "LABEL": "Border Color", "TYPE": "color", "DEFAULT": [1, 1, 1, 1] },
    { "NAME": "shadow", "LABEL": "Shadow", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0, "MAX": 1 }
  ]
}*/
float4 effect(Twz t) {
    float4 c = t.sample(t.uv);
    float2 p = (t.uv - t.p.center) * float2(t.aspect, 1.0);
    float2 half_ = float2(t.p.size * t.aspect, t.p.size) * 0.5;
    float r = min(t.p.radius, min(half_.x, half_.y));
    float sd = sdRoundBox(p - float2(0.006, 0.01), half_, r);
    c.rgb *= 1.0 - t.p.shadow * 0.6 * smoothstep(0.03, -0.01, sd);
    float d = sdRoundBox(p, half_ + t.p.border, r + t.p.border);
    c.rgb = mix(c.rgb, t.p.borderColor.rgb, smoothstep(0.0015, -0.0015, d) * t.p.borderColor.a);
    float di = sdRoundBox(p, half_, r);
    float2 local = p / (half_ * 2.0) + 0.5;
    float3 src = t.p.source_size.x > 0.0 ? t.sample(t.source, local).rgb : float3(0.1);
    c.rgb = mix(c.rgb, src, smoothstep(0.0015, -0.0015, di));
    return float4(c.rgb, 1.0);
}
