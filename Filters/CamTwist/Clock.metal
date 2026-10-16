/*{
  "NAME": "Clock",
  "CATEGORIES": ["CamTwist", "Overlay", "Text"],
  "DESCRIPTION": "Shows the time and/or date. Edit the text to change the format, e.g. {time:h:mm a} or {date:EEEE}.",
  "INPUTS": [
    { "NAME": "text", "LABEL": "Format", "TYPE": "text", "DEFAULT": "{date:EEE d MMM}  {time:HH:mm:ss}", "FONT": "Menlo-Bold", "FONTSIZE": 96 },
    { "NAME": "position", "LABEL": "Position", "TYPE": "point2D", "DEFAULT": [0.78, 0.92] },
    { "NAME": "size", "LABEL": "Size", "TYPE": "float", "DEFAULT": 0.06, "MIN": 0.02, "MAX": 0.3 },
    { "NAME": "color", "LABEL": "Color", "TYPE": "color", "DEFAULT": [1, 0.95, 0.2, 1] },
    { "NAME": "shadow", "LABEL": "Shadow", "TYPE": "color", "DEFAULT": [0, 0, 0, 0.8] },
    { "NAME": "box", "LABEL": "Background Box", "TYPE": "color", "DEFAULT": [0, 0, 0, 0.0] }
  ]
}*/

float4 effect(Twz t) {
    float4 c = t.sample(t.uv);
    float w = t.placedWidth(t.text, t.p.size);
    float2 d = abs(t.uv - t.p.position) - float2(w * 0.5, t.p.size * 0.5);
    float inBox = step(max(d.x, d.y), 0.0);
    c.rgb = mix(c.rgb, t.p.box.rgb, inBox * t.p.box.a);
    return t.drawText(c, t.text, t.p.position, t.p.size, t.p.color, t.p.shadow);
}
