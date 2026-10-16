/*{
  "NAME": "Wave",
  "CATEGORIES": ["Distortion"],
  "DESCRIPTION": "Sine-wave wobble, horizontally, vertically or both — the 'dream sequence' effect.",
  "INPUTS": [ { "NAME": "amplitude", "LABEL": "Amplitude", "TYPE": "float", "DEFAULT": 0.02, "MIN": 0, "MAX": 0.15 },
              { "NAME": "frequency", "LABEL": "Frequency", "TYPE": "float", "DEFAULT": 6, "MIN": 0.5, "MAX": 40 },
              { "NAME": "speed", "LABEL": "Speed", "TYPE": "float", "DEFAULT": 2, "MIN": 0, "MAX": 10 },
              { "NAME": "direction", "LABEL": "Direction", "TYPE": "long", "DEFAULT": 0, "VALUES": [0, 1, 2], "LABELS": ["Horizontal", "Vertical", "Both"] } ]
}*/
float4 effect(Twz t) {
    float2 uv = t.uv;
    float a = t.p.amplitude, f = t.p.frequency * TAU, s = t.time * t.p.speed;
    if (t.p.direction != 1) uv.x += sin(t.uv.y * f + s) * a;
    if (t.p.direction != 0) uv.y += sin(t.uv.x * f * 0.7 + s * 1.3) * a;
    return t.sampleMirror(t.input, uv);
}
