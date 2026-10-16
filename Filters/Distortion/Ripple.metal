/*{
  "NAME": "Ripple",
  "CATEGORIES": ["Distortion"],
  "DESCRIPTION": "Water ripples spreading from a point — or raindrops landing all over.",
  "INPUTS": [ { "NAME": "mode", "LABEL": "Mode", "TYPE": "long", "DEFAULT": 0, "VALUES": [0, 1], "LABELS": ["Pond", "Raindrops"] },
              { "NAME": "center", "LABEL": "Center", "TYPE": "point2D", "DEFAULT": [0.5, 0.5] },
              { "NAME": "amplitude", "LABEL": "Amplitude", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0, "MAX": 2 },
              { "NAME": "wavelength", "LABEL": "Wavelength", "TYPE": "float", "DEFAULT": 0.05, "MIN": 0.01, "MAX": 0.3 },
              { "NAME": "speed", "LABEL": "Speed", "TYPE": "float", "DEFAULT": 1, "MIN": 0, "MAX": 4 } ]
}*/
float4 effect(Twz t) {
    float2 p = t.centered();
    float2 off = 0;
    if (t.p.mode == 0) {
        float2 d = p - t.centered(t.p.center);
        float r = length(d);
        float w = sin(r / t.p.wavelength * TAU - t.time * t.p.speed * 6.0) * exp(-r * 2.0);
        off = d / max(r, 1e-4) * w * 0.01 * t.p.amplitude;
    } else {
        for (int i = 0; i < 12; i++) {
            float period = 1.6 + hash11(float(i));
            float lt = fmod(t.time * t.p.speed + hash11(float(i) * 3.3) * period, period);
            float k = floor((t.time * t.p.speed + hash11(float(i) * 3.3) * period) / period);
            float2 c = (hash22(float2(i, k)) - 0.5) * float2(t.aspect, 1.0);
            float2 d = p - c;
            float r = length(d);
            float front = lt * 0.25;
            float w = sin((r - front) / t.p.wavelength * TAU) * smoothstep(0.06, 0.0, abs(r - front)) * (1.0 - lt / period);
            off += d / max(r, 1e-4) * w * 0.006 * t.p.amplitude;
        }
    }
    return t.sample(t.uv + off / float2(t.aspect, 1.0));
}
