/*{
  "NAME": "Framing Grid",
  "CATEGORIES": ["Overlay"],
  "DESCRIPTION": "Rule-of-thirds, center cross or golden-ratio guides.",
  "INPUTS": [ { "NAME": "mode", "LABEL": "Guide", "TYPE": "long", "DEFAULT": 0, "VALUES": [0, 1, 2], "LABELS": ["Rule of Thirds", "Center Cross", "Golden Ratio"] },
              { "NAME": "color", "LABEL": "Color", "TYPE": "color", "DEFAULT": [1, 1, 1, 0.5] } ]
}*/
float4 effect(Twz t) {
    float4 c = t.sample(t.uv);
    float px = 1.5 / t.size.y;
    float g = 0;
    if (t.p.mode == 0) {
        for (int i = 1; i <= 2; i++) {
            g = max(g, smoothstep(px, 0.0, abs(t.uv.x - float(i) / 3.0) / t.aspect * t.aspect));
            g = max(g, smoothstep(px, 0.0, abs(t.uv.y - float(i) / 3.0)));
        }
    } else if (t.p.mode == 1) {
        g = max(smoothstep(px, 0.0, abs(t.uv.x - 0.5)) * step(abs(t.uv.y - 0.5), 0.05), smoothstep(px, 0.0, abs(t.uv.y - 0.5)) * step(abs(t.uv.x - 0.5), 0.05 / t.aspect));
    } else {
        float a = 0.382;
        g = max(max(smoothstep(px, 0.0, abs(t.uv.x - a)), smoothstep(px, 0.0, abs(t.uv.x - (1.0 - a)))),
                max(smoothstep(px, 0.0, abs(t.uv.y - a)), smoothstep(px, 0.0, abs(t.uv.y - (1.0 - a)))));
    }
    return float4(mix(c.rgb, t.p.color.rgb, g * t.p.color.a), 1.0);
}
