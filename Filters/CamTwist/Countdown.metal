/*{
  "NAME": "Countdown",
  "CATEGORIES": ["CamTwist", "Overlay", "Text"],
  "DESCRIPTION": "A countdown timer. {countdown:5:00} counts down from five minutes after the effect starts (Restart resets it); {until:17:30} counts to a time of day.",
  "INPUTS": [
    { "NAME": "text", "LABEL": "Text", "TYPE": "text", "DEFAULT": "Starting in {countdown:5:00}", "FONT": "HelveticaNeue-Bold", "FONTSIZE": 96 },
    { "NAME": "position", "LABEL": "Position", "TYPE": "point2D", "DEFAULT": [0.5, 0.5] },
    { "NAME": "size", "LABEL": "Size", "TYPE": "float", "DEFAULT": 0.12, "MIN": 0.02, "MAX": 0.4 },
    { "NAME": "color", "LABEL": "Color", "TYPE": "color", "DEFAULT": [1, 1, 1, 1] },
    { "NAME": "shadow", "LABEL": "Shadow", "TYPE": "color", "DEFAULT": [0, 0, 0, 0.85] },
    { "NAME": "dim", "LABEL": "Dim Picture", "TYPE": "float", "DEFAULT": 0.4, "MIN": 0, "MAX": 1 }
  ]
}*/

float4 effect(Twz t) {
    float4 c = t.sample(t.uv);
    c.rgb *= 1.0 - t.p.dim;
    return t.drawText(c, t.text, t.p.position, t.p.size, t.p.color, t.p.shadow);
}
