/*{
  "NAME": "Mosaic Tiles",
  "CATEGORIES": ["Stylize"],
  "DESCRIPTION": "Square ceramic tiles with grout lines and a little bevel.",
  "INPUTS": [ { "NAME": "tiles", "LABEL": "Tiles Across Height", "TYPE": "float", "DEFAULT": 40, "MIN": 8, "MAX": 160 },
              { "NAME": "grout", "LABEL": "Grout", "TYPE": "float", "DEFAULT": 0.08, "MIN": 0, "MAX": 0.3 },
              { "NAME": "jitter", "LABEL": "Irregularity", "TYPE": "float", "DEFAULT": 0.3, "MIN": 0, "MAX": 1 } ]
}*/
float4 effect(Twz t) {
    float2 p = t.uv * float2(t.aspect, 1.0) * t.p.tiles;
    float2 cell = floor(p);
    float2 f = fract(p) - 0.5;
    f += (hash22(cell) - 0.5) * 0.12 * t.p.jitter;
    float2 cuv = (cell + 0.5) / t.p.tiles / float2(t.aspect, 1.0);
    float3 c = t.sample(cuv).rgb * (0.9 + 0.2 * hash12(cell) * t.p.jitter);
    float edge = max(abs(f.x), abs(f.y));
    float g = smoothstep(0.5 - t.p.grout, 0.5 - t.p.grout + 0.03, edge);
    float bevel = dot(f, float2(-1, -1)) * 0.25;
    c *= 1.0 + bevel;
    return float4(mix(c, float3(0.75, 0.73, 0.7), g), 1.0);
}
