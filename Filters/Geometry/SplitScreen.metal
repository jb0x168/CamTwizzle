/*{
  "NAME": "Split Screen",
  "CATEGORIES": ["Geometry", "Overlay"],
  "DESCRIPTION": "Side-by-side (or top/bottom) with another live source.",
  "INPUTS": [ { "NAME": "source", "LABEL": "Other Source", "TYPE": "source", "DEFAULT": "pattern:plasma" },
              { "NAME": "layout", "LABEL": "Layout", "TYPE": "long", "DEFAULT": 0, "VALUES": [0, 1], "LABELS": ["Side by Side", "Top / Bottom"] },
              { "NAME": "split", "LABEL": "Split", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0.1, "MAX": 0.9 },
              { "NAME": "gap", "LABEL": "Divider", "TYPE": "float", "DEFAULT": 0.004, "MIN": 0, "MAX": 0.03 } ]
}*/
float4 effect(Twz t) {
    bool side = t.p.layout == 0;
    float coord = side ? t.uv.x : t.uv.y;
    float s = t.p.split;
    if (abs(coord - s) < t.p.gap) return float4(0.05, 0.05, 0.05, 1);
    if (coord < s) {
        // own picture, centered crop of the left part
        float2 uv = side ? float2(0.5 + (t.uv.x / s - 0.5) * s, t.uv.y) : float2(t.uv.x, 0.5 + (t.uv.y / s - 0.5) * s);
        return t.sample(uv);
    }
    float2 uv = side ? float2(0.5 + ((t.uv.x - s) / (1.0 - s) - 0.5) * (1.0 - s), t.uv.y) : float2(t.uv.x, 0.5 + ((t.uv.y - s) / (1.0 - s) - 0.5) * (1.0 - s));
    return t.p.source_size.x > 0.0 ? t.sample(t.source, uv) : float4(0.1, 0.1, 0.12, 1);
}
