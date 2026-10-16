/*{
  "NAME": "Infinite Tunnel",
  "CATEGORIES": ["Distortion"],
  "DESCRIPTION": "Fly down an endless tunnel lined with the picture.",
  "INPUTS": [ { "NAME": "speed", "LABEL": "Speed", "TYPE": "float", "DEFAULT": 0.4, "MIN": -2, "MAX": 2 },
              { "NAME": "twist", "LABEL": "Twist", "TYPE": "float", "DEFAULT": 0.1, "MIN": -1, "MAX": 1 },
              { "NAME": "tiles", "LABEL": "Tiles Around", "TYPE": "float", "DEFAULT": 3, "MIN": 1, "MAX": 8 },
              { "NAME": "fog", "LABEL": "Depth Fade", "TYPE": "float", "DEFAULT": 0.8, "MIN": 0, "MAX": 1 } ]
}*/
float4 effect(Twz t) {
    float2 p = t.centered();
    float r = length(p) + 1e-4;
    float a = atan2(p.y, p.x);
    float depth = 0.25 / r;
    float2 uv = float2(a / TAU * floor(t.p.tiles) + depth * t.p.twist + t.time * t.p.twist * 0.2, depth + t.time * t.p.speed);
    float3 c = t.sampleRepeat(t.input, fract(uv)).rgb;
    c *= mix(1.0, smoothstep(0.0, 0.35, r), t.p.fog);
    return float4(c, 1.0);
}
