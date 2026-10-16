/*{
  "NAME": "LetterBox",
  "CATEGORIES": ["CamTwist", "Overlay"],
  "DESCRIPTION": "Cinematic bars at the top and bottom.",
  "INPUTS": [
    { "NAME": "percent", "LABEL": "Bar Height %", "TYPE": "float", "DEFAULT": 12, "MIN": 0, "MAX": 45 },
    { "NAME": "color", "LABEL": "Color", "TYPE": "color", "DEFAULT": [0, 0, 0, 1] },
    { "NAME": "pillar", "LABEL": "Pillarbox (sides)", "TYPE": "bool", "DEFAULT": false }
  ]
}*/

float4 effect(Twz t) {
    float4 c = t.sample(t.uv);
    float b = t.p.percent / 100.0;
    float coord = t.p.pillar ? t.uv.x : t.uv.y;
    float bar = step(coord, b) + step(1.0 - b, coord);
    return float4(mix(c.rgb, t.p.color.rgb, clamp(bar, 0.0, 1.0) * t.p.color.a), 1.0);
}
