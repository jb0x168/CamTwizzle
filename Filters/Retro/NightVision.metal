/*{
  "NAME": "Night Vision",
  "CATEGORIES": ["Retro", "Color"],
  "DESCRIPTION": "Green phosphor image intensifier with noise, glow and an optional binocular mask.",
  "INPUTS": [
    { "NAME": "gain", "LABEL": "Gain", "TYPE": "float", "DEFAULT": 1.8, "MIN": 0.5, "MAX": 5 },
    { "NAME": "noise", "LABEL": "Noise", "TYPE": "float", "DEFAULT": 0.3, "MIN": 0, "MAX": 1 },
    { "NAME": "binocular", "LABEL": "Binocular Mask", "TYPE": "bool", "DEFAULT": true }
  ]
}*/
float4 effect(Twz t) {
    float l = luma(t.sample(t.uv).rgb);
    float g = luma(t.blur(5.0 * t.inputSize.y / 720.0).rgb);
    l = l * t.p.gain + g * g * 0.6;
    l += (hash12(t.pos + fract(t.time * 23.0) * 400.0) - 0.5) * t.p.noise * 0.5;
    l *= 0.95 + 0.05 * sin(t.pos.y * 1.5 + t.time * 30.0);
    float3 c = float3(0.1, 1.0, 0.25) * clamp(l, 0.0, 1.4);
    c += float3(0.6, 1.0, 0.6) * smoothstep(1.0, 1.4, l) * 0.4;
    if (t.p.binocular) {
        float2 p = t.centered();
        float r = 0.42;
        float d = min(length(p - float2(-0.3, 0)), length(p - float2(0.3, 0)));
        c *= smoothstep(r, r - 0.04, d);
    } else {
        c *= smoothstep(1.0, 0.3, length(t.centered()));
    }
    return float4(c, 1.0);
}
