/*{
  "NAME": "Rain",
  "CATEGORIES": ["Overlay"],
  "DESCRIPTION": "Rain streaks plus droplets trickling down the lens.",
  "INPUTS": [ { "NAME": "amount", "LABEL": "Rain", "TYPE": "float", "DEFAULT": 0.6, "MIN": 0, "MAX": 1 },
              { "NAME": "drops", "LABEL": "Lens Drops", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0, "MAX": 1 },
              { "NAME": "gloom", "LABEL": "Gloom", "TYPE": "float", "DEFAULT": 0.3, "MIN": 0, "MAX": 1 } ]
}*/
float4 effect(Twz t) {
    float2 p = t.centered();
    float2 off = 0;
    // lens droplets: cells with a drop sliding down
    float2 dp = p * float2(14.0, 6.0);
    dp.y += t.time * 0.3;
    float2 cell = floor(dp);
    float2 f = fract(dp) - 0.5;
    float h = hash12(cell);
    if (h < t.p.drops * 0.6) {
        float2 dc = float2((hash11(h * 7.0) - 0.5) * 0.6, fract(-t.time * (0.2 + h) + h) - 0.5);
        float2 d = (f - dc) * float2(1.0, 2.3);
        float r = 0.12 + 0.08 * h;
        float drop = smoothstep(r, r * 0.6, length(d));
        off += d * drop * 0.08;
        // trail
        off += float2(0, 0.01) * smoothstep(0.04, 0.0, abs(f.x - dc.x)) * step(dc.y, f.y) * step(f.y, dc.y + 0.4) * 0.5;
    }
    float3 c = t.sample(t.uv + off).rgb;
    c = mix(c, c * float3(0.75, 0.82, 0.95), t.p.gloom);
    // streaks
    float streaks = 0;
    for (int l = 0; l < 3; l++) {
        float2 q = rotate2d(p, 0.15) * float2(60.0 + float(l) * 40.0, 1.5 + float(l));
        q.y += t.time * (5.0 + float(l) * 2.0);
        float2 c2 = floor(q);
        float2 f2 = fract(q);
        float r = hash12(c2 + float(l) * 9.0);
        streaks += step(1.0 - t.p.amount * 0.35, r) * smoothstep(0.08, 0.0, abs(f2.x - 0.5)) * smoothstep(0.0, 0.3, f2.y) * smoothstep(1.0, 0.6, f2.y);
    }
    c += streaks * 0.25;
    return float4(c, 1.0);
}
