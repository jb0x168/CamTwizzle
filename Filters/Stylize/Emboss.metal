/*{
  "NAME": "Emboss",
  "CATEGORIES": ["Stylize"],
  "DESCRIPTION": "Raised metal/paper relief.",
  "INPUTS": [
    { "NAME": "angle", "LABEL": "Light Angle", "TYPE": "float", "DEFAULT": 135, "MIN": 0, "MAX": 360 },
    { "NAME": "depth", "LABEL": "Depth", "TYPE": "float", "DEFAULT": 3, "MIN": 0.5, "MAX": 10 },
    { "NAME": "color", "LABEL": "Keep Color", "TYPE": "float", "DEFAULT": 0, "MIN": 0, "MAX": 1 }
  ]
}*/
float4 effect(Twz t) {
    float a = t.p.angle * PI / 180.0;
    float2 d = float2(cos(a), sin(a)) * t.p.depth * t.inputSize.y / 720.0;
    float v = luma(t.offset(-d).rgb) - luma(t.offset(d).rgb);
    float3 relief = float3(0.5 + v * 1.5);
    float3 c = mix(relief, t.sample(t.uv).rgb * (relief * 2.0), t.p.color);
    return float4(clamp(c, 0.0, 1.0), 1.0);
}
