/*{
  "NAME": "Slime",
  "CATEGORIES": ["CamTwist", "Overlay"],
  "DESCRIPTION": "Gooey, glossy slime oozes down from the top and clings to edges (after CamTwist's qSlime).",
  "INPUTS": [
    { "NAME": "color", "LABEL": "Color", "TYPE": "color", "DEFAULT": [0.35, 0.95, 0.15, 1] },
    { "NAME": "amount", "LABEL": "Amount", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0, "MAX": 1 },
    { "NAME": "drip", "LABEL": "Drip Speed", "TYPE": "float", "DEFAULT": 0.3, "MIN": 0, "MAX": 1 }
  ]
}*/
float slimeField(Twz t, float2 uv) {
    float x = uv.x * t.aspect;
    // drips from the top: each column has a drip of varying length that slowly grows
    float col = floor(x * 18.0);
    float len = 0.08 + 0.35 * t.p.amount * hash11(col) + 0.25 * t.p.amount * fract(t.time * t.p.drip * 0.05 * (0.5 + hash11(col + 5.0)) + hash11(col * 2.0));
    float fx = fract(x * 18.0) - 0.5;
    float dripW = 0.18 + 0.2 * hash11(col + 9.0);
    float drip = smoothstep(dripW, dripW * 0.5, abs(fx)) * smoothstep(len, len - 0.06, uv.y);
    float sheet = smoothstep(0.06 + 0.1 * t.p.amount + 0.04 * vnoise(float2(x * 6.0, t.time * 0.2)), 0.0, uv.y);
    float blob = drip + sheet;
    // clinging to edges
    { Twz u = t; u.uv = uv; blob += smoothstep(0.35, 0.8, u.edge(3.0)) * t.p.amount * 0.6; }
    return clamp(blob, 0.0, 1.0);
}
float4 effect(Twz t) {
    float h = slimeField(t, t.uv);
    float2 e = 3.0 * t.texel;
    float hx = slimeField(t, t.uv + float2(e.x, 0)) - slimeField(t, t.uv - float2(e.x, 0));
    float hy = slimeField(t, t.uv + float2(0, e.y)) - slimeField(t, t.uv - float2(0, e.y));
    float3 n = normalize(float3(-hx, -hy, 0.35));
    float3 bg = t.sample(t.uv + float2(hx, hy) * 0.02).rgb;
    float diff = clamp(dot(n, normalize(float3(-0.4, -0.6, 0.7))), 0.0, 1.0);
    float spec = pow(clamp(dot(reflect(normalize(float3(0.4, 0.6, -0.7)), n), float3(0, 0, 1)), 0.0, 1.0), 24.0);
    float3 slime = t.p.color.rgb * (0.35 + 0.75 * diff) + spec * 0.9;
    float a = smoothstep(0.35, 0.55, h);
    return float4(mix(bg, mix(bg * t.p.color.rgb, slime, 0.85), a), 1.0);
}
