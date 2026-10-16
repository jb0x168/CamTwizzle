/*{
  "NAME": "Tiny Planet",
  "CATEGORIES": ["Distortion", "Geometry"],
  "DESCRIPTION": "Wraps the picture around a little planet (stereographic / polar projection).",
  "INPUTS": [ { "NAME": "zoom", "LABEL": "Zoom", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0.3, "MAX": 3 },
              { "NAME": "rotation", "LABEL": "Rotation", "TYPE": "float", "DEFAULT": 0, "MIN": -180, "MAX": 180 },
              { "NAME": "spin", "LABEL": "Spin", "TYPE": "float", "DEFAULT": 0.05, "MIN": -1, "MAX": 1 },
              { "NAME": "inside", "LABEL": "Rabbit Hole (invert)", "TYPE": "bool", "DEFAULT": false } ]
}*/
float4 effect(Twz t) {
    float2 p = t.centered() * 2.2 / t.p.zoom;
    float r = length(p);
    float a = atan2(p.x, p.y + 1e-6) + t.p.rotation * PI / 180.0 + t.time * t.p.spin;
    float u = fract(a / TAU + 0.5);
    float v = 1.0 - clamp(atan(r) / (PI * 0.5) * 1.3, 0.0, 1.0);    // ground at center, sky outside
    if (t.p.inside) v = 1.0 - v;
    return t.sampleRepeat(t.input, float2(u, v));
}
