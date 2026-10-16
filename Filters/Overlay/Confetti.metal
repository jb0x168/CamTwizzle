/*{
  "NAME": "Confetti",
  "CATEGORIES": ["Overlay"],
  "DESCRIPTION": "Celebrate! Tumbling colorful confetti. Click 'Burst' for an extra shower.",
  "INPUTS": [ { "NAME": "amount", "LABEL": "Amount", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0, "MAX": 1 },
              { "NAME": "speed", "LABEL": "Speed", "TYPE": "float", "DEFAULT": 1, "MIN": 0.1, "MAX": 3 },
              { "NAME": "size", "LABEL": "Size", "TYPE": "float", "DEFAULT": 1, "MIN": 0.3, "MAX": 3 } ]
}*/
float4 effect(Twz t) {
    float3 c = t.sample(t.uv).rgb;
    float2 p = t.centered();
    for (int l = 0; l < 3; l++) {
        float sc = (9.0 + float(l) * 5.0) / t.p.size;
        float2 q = p * sc;
        q.y -= t.time * t.p.speed * (1.2 + float(l) * 0.4);
        float2 cell = floor(q);
        float h = hash12(cell + float(l) * 13.0);
        if (h > t.p.amount * 0.8) continue;
        float2 f = fract(q) - 0.5;
        f += (hash22(cell) - 0.5) * 0.5;
        f.x += sin(t.time * 2.0 + h * 20.0) * 0.15;
        float ang = t.time * (2.0 + h * 5.0) + h * 10.0;
        float2 r = rotate2d(f, ang);
        r.x *= 0.5 + 0.5 * abs(sin(t.time * 3.0 + h * 9.0));    // tumbling (foreshortening)
        float piece = step(abs(r.x), 0.12) * step(abs(r.y), 0.07);
        float3 col = hsv2rgb(float3(hash11(h * 31.0), 0.75, 1.0));
        c = mix(c, col * (0.8 + 0.4 * abs(sin(ang))), piece);
    }
    return float4(c, 1.0);
}
