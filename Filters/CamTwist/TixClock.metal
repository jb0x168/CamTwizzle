/*{
  "NAME": "TIX Clock",
  "CATEGORIES": ["CamTwist", "Overlay"],
  "DESCRIPTION": "The quirky TIX LED clock: count the lit squares in each group to read the time (HH:MM). Squares reshuffle every few seconds.",
  "INPUTS": [
    { "NAME": "position", "LABEL": "Position", "TYPE": "point2D", "DEFAULT": [0.82, 0.1] },
    { "NAME": "size", "LABEL": "Size", "TYPE": "float", "DEFAULT": 0.09, "MIN": 0.03, "MAX": 0.4 },
    { "NAME": "delay", "LABEL": "Shuffle Every (s)", "TYPE": "float", "DEFAULT": 3, "MIN": 1, "MAX": 60 },
    { "NAME": "military", "LABEL": "24 Hour", "TYPE": "bool", "DEFAULT": true },
    { "NAME": "c1", "LABEL": "Group 1", "TYPE": "color", "DEFAULT": [1, 0.1, 0.1, 1] },
    { "NAME": "c2", "LABEL": "Group 2", "TYPE": "color", "DEFAULT": [0.1, 1, 0.2, 1] },
    { "NAME": "c3", "LABEL": "Group 3", "TYPE": "color", "DEFAULT": [0.2, 0.4, 1, 1] },
    { "NAME": "c4", "LABEL": "Group 4", "TYPE": "color", "DEFAULT": [1, 0.15, 0.15, 1] }
  ]
}*/
// Is square `i` of a group with `n` squares lit when `count` must be on?
bool lit(int i, int n, int count, float seed) {
    // rank squares by a random key; the lowest `count` keys are lit
    float k = hash11(float(i) * 7.13 + seed);
    int rank = 0;
    for (int j = 0; j < 9; j++) { if (j >= n) break; float kj = hash11(float(j) * 7.13 + seed); if (kj < k) rank++; }
    return rank < count;
}
float4 effect(Twz t) {
    float4 c = t.sample(t.uv);
    float secs = t.date.w;
    int hours = int(secs / 3600.0);
    int mins = int(fmod(secs / 60.0, 60.0));
    if (!t.p.military) { hours = hours % 12; if (hours == 0) hours = 12; }
    int digits[4] = { hours / 10, hours % 10, mins / 10, mins % 10 };
    int cols[4] = { 1, 3, 2, 3 };
    float4 colors[4] = { t.p.c1, t.p.c2, t.p.c3, t.p.c4 };
    // layout: 9 columns + 3 gaps, 3 rows
    float cell = t.p.size / 3.0;
    float2 origin = t.p.position - float2((9.0 + 3.0 * 0.6) * cell / t.aspect * 0.5, t.p.size * 0.5);
    float2 local = (t.uv - origin) * float2(t.aspect, 1.0) / cell;
    if (local.y < -0.3 || local.y > 3.3 || local.x < -0.3 || local.x > 11.1) return c;
    // panel background
    c.rgb *= 0.35;
    float x = local.x;
    float seed = floor(t.time / t.p.delay);
    for (int g = 0; g < 4; g++) {
        float gx = x;
        if (gx >= 0.0 && gx < float(cols[g])) {
            float2 sq = floor(float2(gx, local.y));
            float2 f = fract(float2(gx, local.y)) - 0.5;
            int idx = int(sq.y) * cols[g] + int(sq.x);
            if (sq.y >= 0.0 && sq.y < 3.0) {
                bool on = lit(idx, cols[g] * 3, digits[g], seed + float(g) * 13.0);
                float box = smoothstep(0.42, 0.36, max(abs(f.x), abs(f.y)));
                float3 col = on ? colors[g].rgb : float3(0.12);
                c.rgb = mix(c.rgb, col, box * (on ? 1.0 : 0.8));
            }
            break;
        }
        x -= float(cols[g]) + 0.6;
    }
    return c;
}
