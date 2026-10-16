/*{
  "NAME": "Bubbles",
  "CATEGORIES": ["CamTwist", "Overlay"],
  "DESCRIPTION": "Soap bubbles drift up across the picture, refracting what's behind them.",
  "INPUTS": [
    { "NAME": "amount", "LABEL": "Amount", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0, "MAX": 1 },
    { "NAME": "size", "LABEL": "Size", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0.3, "MAX": 3 },
    { "NAME": "speed", "LABEL": "Speed", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0, "MAX": 3 }
  ]
}*/

float4 effect(Twz t) {
    float2 p = t.centered();                        // x in [-aspect/2, aspect/2], y in [-0.5, 0.5]
    float4 c = t.sample(t.uv);
    float3 col = c.rgb;
    for (int layer = 0; layer < 3; layer++) {
        float scale = (4.0 + float(layer) * 3.0) / t.p.size;
        float2 q = p * scale;
        q.y += t.time * t.p.speed * (0.6 + 0.25 * float(layer));      // rise (y down is +)
        float2 cell = floor(q);
        float2 f = fract(q) - 0.5;
        float h = hash12(cell + float(layer) * 17.0);
        if (h > t.p.amount) continue;
        float r = 0.18 + 0.22 * hash12(cell * 1.7 + 3.0);
        float2 wob = float2(sin(t.time * 1.3 + h * 40.0), cos(t.time * 1.1 + h * 23.0)) * 0.12;
        float2 d = f - wob;
        float dist = length(d);
        if (dist < r) {
            float k = dist / r;
            // Refract background through the bubble.
            float2 refr = t.uv - d / scale * (1.0 - k * k) * 0.6 * float2(1.0 / t.aspect, 1.0);
            float3 bg = t.sample(refr).rgb;
            float rim = smoothstep(0.75, 1.0, k);
            float3 irid = hsv2rgb(float3(fract(k * 0.8 + h + t.time * 0.05), 0.5, 1.0));
            float spec = smoothstep(0.12, 0.0, length(d - float2(-0.35, -0.35) * r)) ;
            float3 bubble = mix(bg, irid, rim * 0.55) + spec * 0.9 + rim * 0.15;
            col = mix(col, bubble, smoothstep(r, r * 0.96, dist));
        }
    }
    return float4(col, 1.0);
}
