/*{
  "NAME": "Thought Bubble",
  "CATEGORIES": ["CamTwist", "Overlay", "Face", "Text"],
  "DESCRIPTION": "A cartoon thought bubble that follows your head.",
  "FACE": true,
  "INPUTS": [
    { "NAME": "text", "LABEL": "Thought", "TYPE": "text", "DEFAULT": "Hmmmm…", "FONT": "ChalkboardSE-Bold", "FONTSIZE": 96 },
    { "NAME": "size", "LABEL": "Bubble Size", "TYPE": "float", "DEFAULT": 0.9, "MIN": 0.3, "MAX": 2 },
    { "NAME": "side", "LABEL": "Side", "TYPE": "long", "DEFAULT": 1, "VALUES": [0, 1], "LABELS": ["Left", "Right"] }
  ]
}*/
float4 effect(Twz t) {
    float4 c = t.sample(t.uv);
    float2 head = t.faceCount > 0 ? float2(t.face.x + t.face.z * 0.5, t.face.y) : float2(0.5, 0.3);
    float fw = t.faceCount > 0 ? t.face.z : 0.2;
    float dir = t.p.side == 1 ? 1.0 : -1.0;
    float2 bc = head + float2(dir * fw * 1.15, -0.12 * t.p.size);
    bc = clamp(bc, float2(0.15, 0.12), float2(0.85, 0.9));
    float2 p = (t.uv - bc) * float2(t.aspect, 1.0);
    float rw = 0.24 * t.p.size, rh = 0.11 * t.p.size;
    // cloudy outline: ellipse with bumps
    float a = atan2(p.y, p.x + 1e-6);
    float bump = 1.0 + 0.07 * sin(a * 9.0);
    float e = length(p / float2(rw, rh)) / bump;
    float bubble = smoothstep(1.0, 0.97, e);
    float outline = smoothstep(0.035, 0.0, abs(e - 1.0)) ;
    // little trailing circles toward the head
    float2 hp = (head - bc) * float2(t.aspect, 1.0);
    float dots = 0, dotsO = 0;
    for (int i = 1; i <= 3; i++) {
        float k = 0.45 + 0.17 * float(i);
        float2 cp = hp * k;
        float r = 0.028 * t.p.size * (1.15 - 0.25 * float(i));
        float d = length(p - cp);
        dots = max(dots, smoothstep(r, r * 0.9, d));
        dotsO = max(dotsO, smoothstep(r * 0.15, 0.0, abs(d - r)));
    }
    float fill = max(bubble, dots);
    c.rgb = mix(c.rgb, float3(1.0), fill);
    c.rgb = mix(c.rgb, float3(0.1), max(outline, dotsO));
    float th = rh * 0.8;
    float ta = t.place(t.text, bc, min(th, rw * 1.6 * float(t.text.get_height()) / float(t.text.get_width()) * t.aspect)).a;
    c.rgb = mix(c.rgb, float3(0.1, 0.1, 0.15), ta * bubble);
    return float4(c.rgb, 1.0);
}
