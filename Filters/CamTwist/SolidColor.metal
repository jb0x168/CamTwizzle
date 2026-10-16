/*{
  "NAME": "Solid Color",
  "CATEGORIES": ["CamTwist", "Overlay"],
  "DESCRIPTION": "A colored rectangle — handy for covering things up or as a lower-third bar.",
  "INPUTS": [
    { "NAME": "color", "LABEL": "Color", "TYPE": "color", "DEFAULT": [0.1, 0.3, 0.8, 0.8] },
    { "NAME": "center", "LABEL": "Center", "TYPE": "point2D", "DEFAULT": [0.5, 0.88] },
    { "NAME": "width", "LABEL": "Width", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0, "MAX": 1 },
    { "NAME": "height", "LABEL": "Height", "TYPE": "float", "DEFAULT": 0.25, "MIN": 0, "MAX": 1 },
    { "NAME": "radius", "LABEL": "Corner Radius", "TYPE": "float", "DEFAULT": 0, "MIN": 0, "MAX": 0.2 }
  ]
}*/
float4 effect(Twz t) {
    float4 c = t.sample(t.uv);
    float2 p = (t.uv - t.p.center) * float2(t.aspect, 1.0);
    float2 b = float2(t.p.width * t.aspect, t.p.height) * 0.5;
    float d = sdRoundBox(p, b, min(t.p.radius, min(b.x, b.y)));
    float a = smoothstep(0.0015, -0.0015, d) * t.p.color.a;
    return float4(mix(c.rgb, t.p.color.rgb, a), 1.0);
}
