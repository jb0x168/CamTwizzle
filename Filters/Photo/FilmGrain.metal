/*{
  "NAME": "Film Grain",
  "CATEGORIES": ["Photo", "Retro"],
  "DESCRIPTION": "Organic, luminance-dependent film grain.",
  "INPUTS": [ { "NAME": "amount", "LABEL": "Amount", "TYPE": "float", "DEFAULT": 0.3, "MIN": 0, "MAX": 1 },
              { "NAME": "size", "LABEL": "Grain Size", "TYPE": "float", "DEFAULT": 1.5, "MIN": 1, "MAX": 4 },
              { "NAME": "color", "LABEL": "Color Grain", "TYPE": "bool", "DEFAULT": false } ]
}*/
float4 effect(Twz t) {
    float3 c = t.sample(t.uv).rgb;
    float2 p = t.pos / (t.p.size * t.inputSize.y / 1080.0);
    float f = floor(t.time * 24.0);
    float3 n = t.p.color ? hash32(floor(p) + f * 17.0) - 0.5 : float3(hash12(floor(p) + f * 17.0) - 0.5);
    float l = luma(c);
    float w = 4.0 * l * (1.0 - l);                // strongest in midtones
    return float4(clamp(c + n * t.p.amount * 0.5 * (0.35 + w), 0.0, 1.0), 1.0);
}
