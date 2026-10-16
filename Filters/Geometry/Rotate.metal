/*{
  "NAME": "Rotate",
  "CATEGORIES": ["Geometry"],
  "DESCRIPTION": "Rotate the picture by any angle (90° steps for sideways cameras), optionally spinning.",
  "INPUTS": [ { "NAME": "angle", "LABEL": "Angle", "TYPE": "float", "DEFAULT": 90, "MIN": -180, "MAX": 180 },
              { "NAME": "spin", "LABEL": "Spin (°/s)", "TYPE": "float", "DEFAULT": 0, "MIN": -180, "MAX": 180 },
              { "NAME": "fill", "LABEL": "Zoom to Fill", "TYPE": "bool", "DEFAULT": true } ]
}*/
float4 effect(Twz t) {
    float a = (t.p.angle + t.time * t.p.spin) * PI / 180.0;
    float2 d = t.centered();
    float s = 1.0;
    if (t.p.fill) {
        // scale so the rotated picture covers the frame
        float ca = abs(cos(a)), sa = abs(sin(a));
        s = max((t.aspect * ca + sa) / t.aspect, (t.aspect * sa + ca));
    }
    float2 q = rotate2d(d, -a) / s;
    float2 uv = q / float2(t.aspect, 1.0) + 0.5;
    if (any(uv < 0.0) || any(uv > 1.0)) return float4(0, 0, 0, 1);
    return t.sample(uv);
}
