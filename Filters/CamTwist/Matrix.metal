/*{
  "NAME": "Matrix",
  "CATEGORIES": ["CamTwist", "Stylize", "Retro"],
  "DESCRIPTION": "Digital rain: the picture is rebuilt from glowing green katakana, with code streams falling through it. In the spirit of CamTwist's Matrix (EffecTV matrixTV).",
  "CREDIT": "Idea from EffecTV matrixTV / CamTwist Matrix.bundle",
  "INPUTS": [
    { "NAME": "cell", "LABEL": "Glyph Size", "TYPE": "float", "DEFAULT": 16, "MIN": 6, "MAX": 48 },
    { "NAME": "image", "LABEL": "Image Visibility", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0, "MAX": 2 },
    { "NAME": "edges", "LABEL": "Edge Emphasis", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0, "MAX": 3 },
    { "NAME": "rain", "LABEL": "Rain", "TYPE": "float", "DEFAULT": 0.8, "MIN": 0, "MAX": 1 },
    { "NAME": "speed", "LABEL": "Rain Speed", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0.1, "MAX": 4 },
    { "NAME": "color", "LABEL": "Color", "TYPE": "color", "DEFAULT": [0.25, 1.0, 0.45, 1] }
  ],
  "GLYPHS": [ { "NAME": "kana", "CHARS": "ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789Z:.=*+-<>", "FONT": "HiraginoSans-W6", "SIZE": 48 } ]
}*/

float4 effect(Twz t) {
    float2 cellPx = float2(t.p.cell * 0.75, t.p.cell);
    float2 cell = floor(t.pos / cellPx);
    float2 cuv = fract(t.pos / cellPx);
    float2 rows = floor(t.size / cellPx);
    float2 center = (cell + 0.5) * cellPx / t.size;

    // Image term: brightness + edges of the cell.
    float4 src = t.blurAt(center, t.p.cell * 0.35);
    float e = 0;
    { Twz u = t; u.uv = center; e = u.edge(t.p.cell * 0.3); }
    float l = luma(src.rgb);
    float img = clamp(smoothstep(0.1, 0.85, l) * 0.8 + e * t.p.edges * 1.6, 0.0, 1.3) * t.p.image;

    // Rain term: one stream per column.
    float col = cell.x;
    float speed = mix(0.4, 1.4, hash11(col * 1.37)) * t.p.speed;
    float len = rows.y * mix(0.15, 0.45, hash11(col * 7.11));
    float period = rows.y * mix(1.3, 2.4, hash11(col * 3.3)) + len;
    float head = mod(t.time * speed * 9.0 + hash11(col) * period, period);
    float d = head - cell.y;
    float rain = (d >= 0.0 && d < len) ? pow(1.0 - d / len, 1.5) : 0.0;
    float isHead = (d >= 0.0 && d < 1.0) ? 1.0 : 0.0;
    rain *= t.p.rain * 0.75;

    // The picture is always readable; streams brighten it as they pass and glow faintly in the dark.
    float rainN = rain / max(t.p.rain * 0.75, 0.01);
    float b = img * (0.7 + 0.3 * rainN) + rain * 0.22 + isHead * t.p.rain * 0.6;
    // Glyphs flicker/change over time, faster near the head.
    float change = floor(t.time * (2.0 + 10.0 * isHead) + hash12(cell) * 10.0);
    int idx = int(hash12(cell + change * 0.731) * float(kana_COUNT));
    float g = glyphAt(t.kana, kana_COUNT, idx, float2(1.0 - cuv.x, cuv.y));   // mirrored, like the film
    float3 c = t.p.color.rgb * b * 1.25;
    c = mix(c, float3(0.85, 1.0, 0.9), isHead * t.p.rain * 0.8 + smoothstep(0.9, 1.2, b) * 0.5);
    return float4(c * g + t.p.color.rgb * 0.04 * b, 1.0);
}
