/*{
  "NAME": "Warp Speed",
  "CATEGORIES": ["Overlay", "Generator"],
  "DESCRIPTION": "Stars streak past in hyperspace — over the picture, or behind you with segmentation enabled.",
  "MASK": true,
  "INPUTS": [ { "NAME": "speed", "LABEL": "Speed", "TYPE": "float", "DEFAULT": 1, "MIN": 0, "MAX": 5 },
              { "NAME": "behind", "LABEL": "Only Behind Me", "TYPE": "bool", "DEFAULT": true },
              { "NAME": "dim", "LABEL": "Dim Background", "TYPE": "float", "DEFAULT": 0.6, "MIN": 0, "MAX": 1 } ]
}*/
float4 effect(Twz t) {
    float3 c = t.sample(t.uv).rgb;
    float2 p = t.centered();
    float a = atan2(p.y, p.x + 1e-6);
    float r = length(p);
    float stars = 0;
    for (int l = 0; l < 3; l++) {
        float seg = floor((a / TAU + 0.5) * (180.0 + float(l) * 90.0));
        float h = hash11(seg + float(l) * 100.0);
        float z = fract(h * 7.0 - t.time * t.p.speed * (0.2 + 0.1 * float(l)));
        float sr = mix(1.2, 0.02, z);
        float len = 0.02 + 0.3 * (1.0 - z) * t.p.speed * 0.3;
        float s = smoothstep(len, 0.0, abs(r - sr)) * step(0.8, h) * (1.0 - z);
        stars += s;
    }
    float m = t.p.behind ? smoothstep(0.35, 0.65, t.maskAt(t.uv)) : 0.0;
    float3 bg = c * (1.0 - t.p.dim) + float3(0.7, 0.85, 1.0) * stars;
    return float4(mix(bg, c, m), 1.0);
}
