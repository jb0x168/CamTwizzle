/*{
  "NAME": "Emoji Rain",
  "CATEGORIES": ["Overlay"],
  "DESCRIPTION": "It's raining emoji. Edit the set in the effect file (GLYPHS) to change them.",
  "INPUTS": [ { "NAME": "amount", "LABEL": "Amount", "TYPE": "float", "DEFAULT": 0.35, "MIN": 0, "MAX": 1 },
              { "NAME": "size", "LABEL": "Size", "TYPE": "float", "DEFAULT": 1, "MIN": 0.3, "MAX": 3 },
              { "NAME": "speed", "LABEL": "Speed", "TYPE": "float", "DEFAULT": 1, "MIN": 0.1, "MAX": 3 } ],
  "GLYPHS": [ { "NAME": "emoji", "CHARS": ["🎉", "😂", "❤️", "🔥", "👍", "🤖", "⭐️", "🍕", "🦄", "😎"], "FONT": "AppleColorEmoji", "SIZE": 96 } ]
}*/
float4 effect(Twz t) {
    float3 c = t.sample(t.uv).rgb;
    float2 p = t.centered();
    for (int l = 0; l < 2; l++) {
        float sc = (6.0 + float(l) * 3.0) / t.p.size;
        float2 q = p * sc;
        q.y -= t.time * t.p.speed * (0.8 + float(l) * 0.3);
        float2 cell = floor(q);
        float h = hash12(cell + float(l) * 7.0);
        if (h > t.p.amount * 0.7) continue;
        float2 f = fract(q) - 0.5;
        f = rotate2d(f, sin(t.time * 2.0 + h * 30.0) * 0.4);
        float2 g = f / 0.8 + 0.5;
        if (any(g < 0.0) || any(g > 1.0)) continue;
        float4 e = glyphColorAt(t.emoji, emoji_COUNT, int(h / max(t.p.amount * 0.7, 1e-3) * float(emoji_COUNT)), g);
        c = mix(c, e.rgb, e.a);
    }
    return float4(c, 1.0);
}
