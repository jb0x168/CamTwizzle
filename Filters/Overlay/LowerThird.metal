/*{
  "NAME": "Lower Third",
  "CATEGORIES": ["Overlay", "Text"],
  "DESCRIPTION": "TV-style name and title banner that slides in. Click 'Replay' to animate again.",
  "INPUTS": [
    { "NAME": "name", "LABEL": "Name", "TYPE": "text", "DEFAULT": "Your Name", "FONT": "HelveticaNeue-Bold", "FONTSIZE": 96 },
    { "NAME": "title", "LABEL": "Title", "TYPE": "text", "DEFAULT": "Chief Twizzler · CamTwizzle Inc.", "FONT": "HelveticaNeue", "FONTSIZE": 80 },
    { "NAME": "accent", "LABEL": "Accent", "TYPE": "color", "DEFAULT": [0.95, 0.3, 0.2, 1] },
    { "NAME": "panel", "LABEL": "Panel", "TYPE": "color", "DEFAULT": [0.06, 0.06, 0.1, 0.85] },
    { "NAME": "y", "LABEL": "Vertical Position", "TYPE": "float", "DEFAULT": 0.8, "MIN": 0.1, "MAX": 0.95 },
    { "NAME": "size", "LABEL": "Size", "TYPE": "float", "DEFAULT": 1, "MIN": 0.5, "MAX": 2 },
    { "NAME": "replay", "LABEL": "Replay", "TYPE": "event" }
  ],
  "PASSES": [ { "TARGET": "state", "PERSISTENT": true, "FLOAT32": true, "WIDTH": "1", "HEIGHT": "1" }, {} ]
}*/
float4 effect(Twz t) {
    if (t.pass == 0) {
        float start = t.sample(t.state, float2(0.5)).r;
        if (t.frame == 0 || t.p.replay) start = t.time;
        return float4(start, 0, 0, 1);
    }
    float4 c = t.sample(t.uv);
    float k = clamp((t.time - t.sample(t.state, float2(0.5)).r) / 0.6, 0.0, 1.0);
    k = 1.0 - pow(1.0 - k, 3.0);
    float s = t.p.size;
    float nameH = 0.065 * s, titleH = 0.04 * s;
    float x0 = 0.06;
    float w = max(t.placedWidth(t.name, nameH), t.placedWidth(t.title, titleH)) + 0.04;
    float slide = (1.0 - k) * (w + 0.1);
    float2 q = t.uv + float2(slide, 0);
    float top = t.p.y - nameH * 0.75, bot = t.p.y + titleH * 1.6;
    // panel + accent bar
    if (q.x > x0 && q.x < x0 + w && t.uv.y > top && t.uv.y < bot) c.rgb = mix(c.rgb, t.p.panel.rgb, t.p.panel.a);
    if (q.x > x0 - 0.008 && q.x < x0 && t.uv.y > top && t.uv.y < bot) c.rgb = t.p.accent.rgb;
    float na = t.placeAt(t.name, q, float2(x0 + 0.02 + t.placedWidth(t.name, nameH) * 0.5, t.p.y), nameH).a;
    float ta = t.placeAt(t.title, q, float2(x0 + 0.02 + t.placedWidth(t.title, titleH) * 0.5, t.p.y + nameH * 0.55 + titleH * 0.35), titleH).a;
    c.rgb = mix(c.rgb, float3(1.0), na);
    c.rgb = mix(c.rgb, mix(float3(0.85), t.p.accent.rgb, 0.35), ta);
    return float4(c.rgb, 1.0);
}
