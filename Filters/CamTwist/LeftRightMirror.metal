/*{
  "NAME": "Left/Right Mirror",
  "CATEGORIES": ["CamTwist", "Geometry"],
  "DESCRIPTION": "Reflect one half of the picture onto the other — instant symmetrical face.",
  "INPUTS": [ { "NAME": "mode", "LABEL": "Keep", "TYPE": "long", "DEFAULT": 0, "VALUES": [0, 1, 2, 3], "LABELS": ["Left", "Right", "Top", "Bottom"] },
              { "NAME": "split", "LABEL": "Split Position", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0.2, "MAX": 0.8 } ]
}*/
float4 effect(Twz t) {
    float2 uv = t.uv;
    float s = t.p.split;
    if (t.p.mode == 0 && uv.x > s) uv.x = 2.0 * s - uv.x;
    if (t.p.mode == 1 && uv.x < s) uv.x = 2.0 * s - uv.x;
    if (t.p.mode == 2 && uv.y > s) uv.y = 2.0 * s - uv.y;
    if (t.p.mode == 3 && uv.y < s) uv.y = 2.0 * s - uv.y;
    return t.sample(uv);
}
