/*{
  "NAME": "Virtual Background",
  "CATEGORIES": ["Background"],
  "DESCRIPTION": "Replaces the background with an image, another live source (screen share = weather-presenter mode) or a color. Uses person segmentation.",
  "MASK": true,
  "INPUTS": [ { "NAME": "image", "LABEL": "Background Image", "TYPE": "image" },
              { "NAME": "source", "LABEL": "Background Source", "TYPE": "source" },
              { "NAME": "color", "LABEL": "Background Color", "TYPE": "color", "DEFAULT": [0.0, 0.7, 0.25, 1] },
              { "NAME": "feather", "LABEL": "Edge Feather", "TYPE": "float", "DEFAULT": 0.12, "MIN": 0.01, "MAX": 0.5 },
              { "NAME": "lightWrap", "LABEL": "Light Wrap", "TYPE": "float", "DEFAULT": 0.3, "MIN": 0, "MAX": 1 } ]
}*/
float4 effect(Twz t) {
    float3 bg = t.p.color.rgb;
    if (t.p.source_size.x > 0.0) bg = t.sample(t.source, t.uv).rgb;
    else if (t.p.image_size.x > 0.0) {
        // aspect-fill the image
        float ia = t.p.image_size.x / t.p.image_size.y;
        float2 uv = t.uv;
        if (ia > t.aspect) uv.x = 0.5 + (uv.x - 0.5) * t.aspect / ia; else uv.y = 0.5 + (uv.y - 0.5) * ia / t.aspect;
        bg = t.sample(t.image, uv).rgb;
    }
    float m = smoothstep(0.5 - t.p.feather, 0.5 + t.p.feather, t.maskAt(t.uv));
    float3 fg = t.sample(t.uv).rgb;
    // light wrap: let the background bleed onto the person's edge
    float edge = m * (1.0 - smoothstep(0.6, 1.0, t.mask.sample(twz_linear, t.uv, level(0)).r));
    fg = mix(fg, blendScreen(fg, bg), edge * t.p.lightWrap);
    return float4(mix(bg, fg, m), 1.0);
}
