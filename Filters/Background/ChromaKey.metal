/*{
  "NAME": "Chroma Key",
  "CATEGORIES": ["Background"],
  "DESCRIPTION": "Classic green/blue screen keying: replace a color with an image, another live source or a solid color.",
  "INPUTS": [
    { "NAME": "key", "LABEL": "Key Color", "TYPE": "color", "DEFAULT": [0.1, 0.8, 0.2, 1] },
    { "NAME": "tolerance", "LABEL": "Tolerance", "TYPE": "float", "DEFAULT": 0.18, "MIN": 0, "MAX": 0.6 },
    { "NAME": "softness", "LABEL": "Softness", "TYPE": "float", "DEFAULT": 0.08, "MIN": 0, "MAX": 0.3 },
    { "NAME": "spill", "LABEL": "Spill Suppression", "TYPE": "float", "DEFAULT": 0.6, "MIN": 0, "MAX": 1 },
    { "NAME": "image", "LABEL": "Background Image", "TYPE": "image" },
    { "NAME": "source", "LABEL": "Background Source", "TYPE": "source" },
    { "NAME": "color", "LABEL": "Background Color", "TYPE": "color", "DEFAULT": [0.1, 0.1, 0.15, 1] }
  ]
}*/
float2 chromaUV(float3 c) { return float2(dot(c, float3(-0.169, -0.331, 0.5)), dot(c, float3(0.5, -0.419, -0.081))); }
float4 effect(Twz t) {
    float3 c = t.sample(t.uv).rgb;
    float d = length(chromaUV(c) - chromaUV(t.p.key.rgb));
    float a = smoothstep(t.p.tolerance, t.p.tolerance + t.p.softness, d);   // 1 = keep
    // spill suppression: limit the key's dominant channel
    float3 kc = t.p.key.rgb;
    if (kc.g >= kc.r && kc.g >= kc.b) c.g = mix(c.g, min(c.g, max(c.r, c.b)), t.p.spill);
    else if (kc.b >= kc.r) c.b = mix(c.b, min(c.b, max(c.r, c.g)), t.p.spill);
    float3 bg = t.p.color.rgb;
    if (t.p.source_size.x > 0.0) bg = t.sample(t.source, t.uv).rgb;
    else if (t.p.image_size.x > 0.0) bg = t.sample(t.image, t.uv).rgb;
    return float4(mix(bg, c, a), 1.0);
}
