/*{
  "NAME": "Zoom",
  "CATEGORIES": ["CamTwist", "Geometry"],
  "DESCRIPTION": "Digital zoom towards a point. Drag on the preview to choose where.",
  "INPUTS": [ { "NAME": "scale", "LABEL": "Zoom", "TYPE": "float", "DEFAULT": 2.0, "MIN": 1, "MAX": 8 },
              { "NAME": "center", "LABEL": "Center", "TYPE": "point2D", "DEFAULT": [0.5, 0.5] } ]
}*/
float4 effect(Twz t) {
    float s = max(t.p.scale, 1.0);
    float2 half_ = 0.5 / s;
    float2 c = clamp(t.p.center, half_, 1.0 - half_);
    return t.sample(c + (t.uv - 0.5) / s);
}
