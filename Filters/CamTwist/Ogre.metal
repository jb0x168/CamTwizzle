/*{
  "NAME": "Ogre",
  "CATEGORIES": ["CamTwist", "Distortion", "Face"],
  "DESCRIPTION": "Lumpy, swollen monster face: the picture is pushed around by a blurred height map of its own edges, with warty shading. Inspired by CamTwist's qOgre.",
  "INPUTS": [
    { "NAME": "amount", "LABEL": "Amount", "TYPE": "float", "DEFAULT": 0.35, "MIN": 0, "MAX": 1.5 },
    { "NAME": "lumpiness", "LABEL": "Lump Size", "TYPE": "float", "DEFAULT": 14, "MIN": 3, "MAX": 40 },
    { "NAME": "shading", "LABEL": "Warty Shading", "TYPE": "float", "DEFAULT": 0.35, "MIN": 0, "MAX": 1.5 },
    { "NAME": "skin", "LABEL": "Ogre Green", "TYPE": "float", "DEFAULT": 0.0, "MIN": 0, "MAX": 1 }
  ],
  "PASSES": [
    { "TARGET": "height", "SCALE": 0.5, "FLOAT": true },
    { "TARGET": "blurH", "SCALE": 0.5, "FLOAT": true },
    { "TARGET": "blurV", "SCALE": 0.5, "FLOAT": true },
    {}
  ]
}*/

float4 blur1d(Twz t, texture2d<float> src, float2 dir) {
    // 25 taps spaced ~lumpiness/8 px: smooth, no aliasing lattice.
    float2 step = dir * (t.p.lumpiness / 8.0) / float2(src.get_width(), src.get_height());
    float4 acc = 0; float wsum = 0;
    for (int i = -12; i <= 12; i++) {
        float w = gauss(float(i), 5.0);
        acc += t.sample(src, t.uv + step * float(i)) * w;
        wsum += w;
    }
    return acc / wsum;
}

float4 effect(Twz t) {
    if (t.pass == 0) {
        // Height map: smoothed luma plus strong edges (features become bumps)
        float e = t.edge(2.0) * 0.5 + t.edge(4.0) * 0.5;
        float l = luma(t.blur(3.0).rgb);
        float h = clamp(e * 2.5 + l * 0.35, 0.0, 1.5);
        return float4(h, h, h, 1);
    }
    if (t.pass == 1) return blur1d(t, t.height, float2(1, 0));
    if (t.pass == 2) return blur1d(t, t.blurH, float2(0, 1));

    float2 px = (t.p.lumpiness * 0.5) / float2(t.blurV.get_width(), t.blurV.get_height());
    float hl = t.sample(t.blurV, t.uv - float2(px.x, 0)).r, hr = t.sample(t.blurV, t.uv + float2(px.x, 0)).r;
    float hu = t.sample(t.blurV, t.uv - float2(0, px.y)).r, hd = t.sample(t.blurV, t.uv + float2(0, px.y)).r;
    float2 g = float2(hr - hl, hd - hu);
    // Bulge outward from ridges: move the lookup towards lower height.
    float2 uv = t.uv - g * t.p.amount * 0.5;
    float4 c = t.sample(uv);
    float3 n = normalize(float3(-g * 12.0, 1.0));
    float light = dot(n, normalize(float3(-0.5, -0.6, 0.65)));
    c.rgb *= mix(1.0, 0.55 + 0.75 * light, t.p.shading);
    float l = luma(c.rgb);
    float3 green = float3(0.45, 0.62, 0.2) * (0.35 + 1.1 * l);
    c.rgb = mix(c.rgb, green, t.p.skin * 0.85);
    return float4(c.rgb, 1.0);
}
