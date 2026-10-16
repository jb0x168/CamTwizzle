/*{
  "NAME": "Text",
  "CATEGORIES": ["CamTwist", "Overlay", "Text"],
  "DESCRIPTION": "A line of text over the picture, with shadow, rotation and an optional box.",
  "INPUTS": [
    { "NAME": "text", "LABEL": "Text", "TYPE": "text", "DEFAULT": "Hello World!", "FONT": "HelveticaNeue-Bold", "FONTSIZE": 110 },
    { "NAME": "position", "LABEL": "Position", "TYPE": "point2D", "DEFAULT": [0.5, 0.85] },
    { "NAME": "size", "LABEL": "Size", "TYPE": "float", "DEFAULT": 0.1, "MIN": 0.02, "MAX": 0.5 },
    { "NAME": "rotation", "LABEL": "Rotation", "TYPE": "float", "DEFAULT": 0, "MIN": -180, "MAX": 180 },
    { "NAME": "color", "LABEL": "Color", "TYPE": "color", "DEFAULT": [1, 1, 1, 1] },
    { "NAME": "shadow", "LABEL": "Shadow", "TYPE": "color", "DEFAULT": [0, 0, 0, 0.8] },
    { "NAME": "box", "LABEL": "Background", "TYPE": "color", "DEFAULT": [0, 0, 0, 0] }
  ]
}*/

float4 effect(Twz t) {
    float4 c = t.sample(t.uv);
    // Rotate the lookup point around the text center (aspect-correct).
    float2 d = (t.uv - t.p.position) * float2(t.aspect, 1.0);
    d = rotate2d(d, -t.p.rotation * PI / 180.0);
    float2 q = t.p.position + d / float2(t.aspect, 1.0);
    float w = t.placedWidth(t.text, t.p.size);
    float2 bd = abs(q - t.p.position) - float2(w * 0.5, t.p.size * 0.5);
    c.rgb = mix(c.rgb, t.p.box.rgb, step(max(bd.x, bd.y), 0.0) * t.p.box.a);
    float2 so = float2(0.05 * t.p.size / t.aspect, 0.05 * t.p.size);
    float sa = t.placeAt(t.text, q - so, t.p.position, t.p.size).a * t.p.shadow.a;
    c.rgb = mix(c.rgb, t.p.shadow.rgb, sa);
    float a = t.placeAt(t.text, q, t.p.position, t.p.size).a * t.p.color.a;
    return float4(mix(c.rgb, t.p.color.rgb, a), 1.0);
}
