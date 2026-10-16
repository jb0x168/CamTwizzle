/*{
  "NAME": "Scrolling Text",
  "CATEGORIES": ["CamTwist", "Overlay", "Text"],
  "DESCRIPTION": "A news-ticker style crawl along the bottom of the picture.",
  "INPUTS": [
    { "NAME": "text", "LABEL": "Text", "TYPE": "text", "DEFAULT": "Hello World!  ✦  CamTwizzle is live  ✦  {time:HH:mm}  ✦  ", "FONT": "HelveticaNeue-Bold", "FONTSIZE": 90 },
    { "NAME": "y", "LABEL": "Vertical Position", "TYPE": "float", "DEFAULT": 0.93, "MIN": 0, "MAX": 1 },
    { "NAME": "size", "LABEL": "Size", "TYPE": "float", "DEFAULT": 0.07, "MIN": 0.02, "MAX": 0.3 },
    { "NAME": "speed", "LABEL": "Speed", "TYPE": "float", "DEFAULT": 0.15, "MIN": -1, "MAX": 1 },
    { "NAME": "color", "LABEL": "Text Color", "TYPE": "color", "DEFAULT": [1, 1, 1, 1] },
    { "NAME": "bar", "LABEL": "Bar Color", "TYPE": "color", "DEFAULT": [0.75, 0.05, 0.1, 0.85] }
  ]
}*/

float4 effect(Twz t) {
    float4 c = t.sample(t.uv);
    float h = t.p.size;
    float inBar = step(abs(t.uv.y - t.p.y), h * 0.6);
    c.rgb = mix(c.rgb, t.p.bar.rgb, inBar * t.p.bar.a);
    float w = t.placedWidth(t.text, h);
    // Repeat the text along x, scrolling with time.
    float x = mod(t.uv.x + t.time * t.p.speed, w);
    float2 q = float2(x, t.uv.y);
    float a = t.placeAt(t.text, q, float2(w * 0.5, t.p.y), h).a * t.p.color.a;
    return float4(mix(c.rgb, t.p.color.rgb, a), 1.0);
}
