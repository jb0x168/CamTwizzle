/*{
  "NAME": "Heat Haze",
  "CATEGORIES": ["Distortion"],
  "DESCRIPTION": "Shimmering hot air rising from the bottom of the picture.",
  "INPUTS": [ { "NAME": "strength", "LABEL": "Strength", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0, "MAX": 2 },
              { "NAME": "height", "LABEL": "Height", "TYPE": "float", "DEFAULT": 0.6, "MIN": 0.1, "MAX": 1 } ]
}*/
float4 effect(Twz t) {
    float h = smoothstep(1.0 - t.p.height, 1.0, t.uv.y);
    float2 n = float2(vnoise(float2(t.uv.x * 40.0, t.uv.y * 20.0 + t.time * 4.0)), vnoise(float2(t.uv.x * 30.0 + 7.0, t.uv.y * 25.0 + t.time * 5.0))) - 0.5;
    return t.sample(t.uv + n * 0.012 * t.p.strength * h);
}
