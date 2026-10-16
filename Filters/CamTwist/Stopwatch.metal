/*{
  "NAME": "Count Up",
  "CATEGORIES": ["CamTwist", "Overlay", "Text"],
  "DESCRIPTION": "Elapsed time since the effect started (Restart resets it), like CamTwist's Count up.",
  "INPUTS": [
    { "NAME": "text", "LABEL": "Text", "TYPE": "text", "DEFAULT": "On air {elapsed}", "FONT": "Menlo-Bold", "FONTSIZE": 96 },
    { "NAME": "position", "LABEL": "Position", "TYPE": "point2D", "DEFAULT": [0.15, 0.08] },
    { "NAME": "size", "LABEL": "Size", "TYPE": "float", "DEFAULT": 0.05, "MIN": 0.02, "MAX": 0.3 },
    { "NAME": "color", "LABEL": "Color", "TYPE": "color", "DEFAULT": [1, 0.25, 0.2, 1] },
    { "NAME": "shadow", "LABEL": "Shadow", "TYPE": "color", "DEFAULT": [0, 0, 0, 0.8] }
  ]
}*/

float4 effect(Twz t) {
    return t.drawText(t.sample(t.uv), t.text, t.p.position, t.p.size, t.p.color, t.p.shadow);
}
