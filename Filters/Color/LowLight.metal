/*{
  "NAME": "Low Light Boost",
  "CATEGORIES": ["Color"],
  "DESCRIPTION": "Brightens a dim room: lifts shadows with a tone curve while denoising the dark areas.",
  "INPUTS": [ { "NAME": "boost", "LABEL": "Boost", "TYPE": "float", "DEFAULT": 0.6, "MIN": 0, "MAX": 1 },
              { "NAME": "denoise", "LABEL": "Denoise", "TYPE": "float", "DEFAULT": 0.6, "MIN": 0, "MAX": 1 } ]
}*/
float4 effect(Twz t) {
    float3 c0 = t.sample(t.uv).rgb;
    float3 b = t.blur(2.0 * t.inputSize.y / 720.0).rgb;
    float l0 = luma(c0);
    float3 c = mix(c0, b, t.p.denoise * smoothstep(0.4, 0.05, l0));
    float k = 1.0 + 3.0 * t.p.boost;
    float3 lifted = 1.0 - pow(1.0 - clamp(c, 0.0, 1.0), float3(k));     // gentle shoulder
    return float4(lifted, 1.0);
}
