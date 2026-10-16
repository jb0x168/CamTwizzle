/*{
  "NAME": "Color Pop",
  "CATEGORIES": ["Color"],
  "DESCRIPTION": "Everything black & white except one hue (red by default).",
  "INPUTS": [ { "NAME": "hue", "LABEL": "Keep Hue", "TYPE": "float", "DEFAULT": 0, "MIN": 0, "MAX": 360 },
              { "NAME": "range", "LABEL": "Hue Range", "TYPE": "float", "DEFAULT": 25, "MIN": 5, "MAX": 90 } ]
}*/
float4 effect(Twz t) {
    float3 c = t.sample(t.uv).rgb;
    float3 hsv = rgb2hsv(c);
    float dh = abs(fract(hsv.x - t.p.hue / 360.0 + 0.5) - 0.5) * 360.0;
    float keep = smoothstep(t.p.range, t.p.range * 0.6, dh) * smoothstep(0.1, 0.3, hsv.y);
    return float4(mix(float3(luma(c)), c, keep), 1.0);
}
