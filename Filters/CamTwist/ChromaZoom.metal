/*{
  "NAME": "Chroma Zoom",
  "CATEGORIES": ["CamTwist", "Distortion"],
  "DESCRIPTION": "Zooms the red, green and blue channels by different amounts (toneburst's tb_chromaZoom, based on Vidvox's VVZoom).",
  "CREDIT": "toneburst 2007, after Vidvox VVZoom",
  "INPUTS": [
    { "NAME": "master", "LABEL": "Master Zoom", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0.5, "MAX": 2 },
    { "NAME": "zoomR", "LABEL": "Red", "TYPE": "float", "DEFAULT": 1.114, "MIN": 0.8, "MAX": 1.5 },
    { "NAME": "zoomG", "LABEL": "Green", "TYPE": "float", "DEFAULT": 1.018, "MIN": 0.8, "MAX": 1.5 },
    { "NAME": "zoomB", "LABEL": "Blue", "TYPE": "float", "DEFAULT": 1.055, "MIN": 0.8, "MAX": 1.5 },
    { "NAME": "center", "LABEL": "Center", "TYPE": "point2D", "DEFAULT": [0.5, 0.5] }
  ]
}*/
float4 effect(Twz t) {
    float2 d = t.uv - t.p.center;
    float r = t.sample(t.p.center + d / (t.p.zoomR * t.p.master)).r;
    float g = t.sample(t.p.center + d / (t.p.zoomG * t.p.master)).g;
    float b = t.sample(t.p.center + d / (t.p.zoomB * t.p.master)).b;
    return float4(r, g, b, 1.0);
}
