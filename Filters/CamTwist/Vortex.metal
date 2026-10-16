/*{
  "NAME": "Vortex",
  "CATEGORIES": ["CamTwist", "Time", "Distortion"],
  "DESCRIPTION": "Video feedback spiral: each frame is spun and zoomed into the next (after CamTwist's qVortex).",
  "INPUTS": [
    { "NAME": "spin", "LABEL": "Spin", "TYPE": "float", "DEFAULT": 0.5, "MIN": -2, "MAX": 2 },
    { "NAME": "zoom", "LABEL": "Zoom", "TYPE": "float", "DEFAULT": -0.2, "MIN": -1, "MAX": 1 },
    { "NAME": "feedback", "LABEL": "Feedback", "TYPE": "float", "DEFAULT": 0.85, "MIN": 0, "MAX": 0.98 },
    { "NAME": "hueShift", "LABEL": "Hue Drift", "TYPE": "float", "DEFAULT": 0.02, "MIN": 0, "MAX": 0.2 }
  ],
  "PASSES": [ { "TARGET": "acc", "PERSISTENT": true } ]
}*/
float4 effect(Twz t) {
    float4 now = t.sample(t.uv);
    if (t.frame == 0) return now;
    float2 d = (t.uv - 0.5) * float2(t.aspect, 1.0);
    d = rotate2d(d, t.p.spin * 0.05);
    d *= 1.0 + t.p.zoom * 0.05;
    float2 q = d / float2(t.aspect, 1.0) + 0.5;
    float3 prev = t.sample(t.acc, q).rgb;
    float3 hsv = rgb2hsv(prev);
    hsv.x = fract(hsv.x + t.p.hueShift);
    prev = hsv2rgb(hsv);
    float k = t.p.feedback * (any(q < 0.0) || any(q > 1.0) ? 0.0 : 1.0);
    float3 c = mix(now.rgb, max(now.rgb, prev), k);
    return float4(c, 1.0);
}
