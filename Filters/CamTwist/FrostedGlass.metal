/*{
  "NAME": "Frosted Glass",
  "CATEGORIES": ["CamTwist", "Distortion"],
  "DESCRIPTION": "Looking through a frosted / bathroom window (after CamTwist's Msa_FrostedGlass).",
  "INPUTS": [
    { "NAME": "amount", "LABEL": "Amount", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0, "MAX": 1 },
    { "NAME": "scale", "LABEL": "Pattern Scale", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0.2, "MAX": 5 },
    { "NAME": "fine", "LABEL": "Fine Grain", "TYPE": "bool", "DEFAULT": false }
  ]
}*/
float4 effect(Twz t) {
    float2 q = t.uv * float2(t.aspect, 1.0) * (t.p.fine ? 400.0 : 120.0 / t.p.scale);
    float2 n = t.p.fine ? hash22(floor(q)) - 0.5 : float2(vnoise(q), vnoise(q + 31.7)) - 0.5;
    float2 n2 = hash22(t.pos) - 0.5;
    float2 off = (n * 2.0 + n2 * 0.6) * t.p.amount * 0.012 * float2(1.0 / t.aspect, 1.0);
    float4 c = (t.sample(t.uv + off) + t.sample(t.uv + off * 0.6 + n2.yx * 0.004)) * 0.5;
    c.rgb = mix(c.rgb, c.rgb * 0.92 + 0.08, t.p.amount);
    return float4(c.rgb, 1.0);
}
