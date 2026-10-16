/*{
  "NAME": "N-Square",
  "CATEGORIES": ["CamTwist", "Geometry"],
  "DESCRIPTION": "Tiles the picture in an N×N grid.",
  "INPUTS": [ { "NAME": "squares", "LABEL": "Squares", "TYPE": "float", "DEFAULT": 4, "MIN": 1, "MAX": 16 },
              { "NAME": "alternate", "LABEL": "Mirror Alternate Tiles", "TYPE": "bool", "DEFAULT": false } ]
}*/
float4 effect(Twz t) {
    float n = max(1.0, floor(t.p.squares + 0.5));
    float2 q = t.uv * n;
    float2 uv = fract(q);
    if (t.p.alternate) {
        float2 cell = floor(q);
        if (mod(cell.x, 2.0) > 0.5) uv.x = 1.0 - uv.x;
        if (mod(cell.y, 2.0) > 0.5) uv.y = 1.0 - uv.y;
    }
    return t.sample(uv);
}
