/*{
  "NAME": "Mustache",
  "CATEGORIES": ["Face", "Overlay"],
  "DESCRIPTION": "A dapper handlebar mustache that sticks to your upper lip.",
  "FACE": true,
  "INPUTS": [ { "NAME": "size", "LABEL": "Size", "TYPE": "float", "DEFAULT": 1, "MIN": 0.4, "MAX": 2.5 },
              { "NAME": "curl", "LABEL": "Curl", "TYPE": "float", "DEFAULT": 1, "MIN": 0, "MAX": 2 },
              { "NAME": "color", "LABEL": "Color", "TYPE": "color", "DEFAULT": [0.12, 0.07, 0.04, 1] } ]
}*/
float4 effect(Twz t) {
    float4 c = t.sample(t.uv);
    if (t.faceCount == 0) return c;
    float ed = length((t.rightEye - t.leftEye) * float2(t.aspect, 1.0));
    float2 anchor = t.centered(mix(t.nose, t.mouth, 0.55));
    float2 d = rotate2d(t.centered() - anchor, -t.faceRoll) / (ed * t.p.size);
    float x = abs(d.x);
    // body: thick in the middle, thinning outwards, curling up at the ends
    float y0 = -0.05 - 0.25 * t.p.curl * smoothstep(0.35, 0.75, x) * (x - 0.35) * 2.0;
    float th = 0.11 * (1.0 - smoothstep(0.0, 0.8, x)) + 0.015;
    float body = smoothstep(th, th * 0.8, abs(d.y - y0 - 0.04 * x)) * step(x, 0.8);
    float tip = smoothstep(0.05, 0.035, length(float2(x, d.y) - float2(0.78, y0 - 0.02 * t.p.curl)));
    float m = max(body, tip) * smoothstep(0.02, 0.06, x + 0.1);
    float hair = 0.85 + 0.15 * sin(d.x * 120.0 + d.y * 40.0);
    return float4(mix(c.rgb, t.p.color.rgb * hair, m), 1.0);
}
