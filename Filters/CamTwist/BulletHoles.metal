/*{
  "NAME": "Bullet Holes",
  "CATEGORIES": ["CamTwist", "Overlay"],
  "DESCRIPTION": "Shatter the screen: click Shoot to put another bullet hole in the glass. Restart clears them.",
  "INPUTS": [
    { "NAME": "shoot", "LABEL": "Shoot!", "TYPE": "event" },
    { "NAME": "initial", "LABEL": "Starting Holes", "TYPE": "long", "DEFAULT": 3, "MIN": 0, "MAX": 8 },
    { "NAME": "size", "LABEL": "Size", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0.3, "MAX": 3 }
  ],
  "PASSES": [ { "TARGET": "glass", "PERSISTENT": true, "FLOAT": true }, {} ]
}*/

// Crack pattern of one hole at `c` (aspect-corrected space). Returns (hole, crack).
float2 holeAt(float2 p, float2 c, float s, float seed) {
    float2 d = p - c;
    float r = length(d);
    float a = atan2(d.y, d.x + 1e-6);
    float hole = smoothstep(0.022 * s, 0.017 * s, r);
    float crack = 0;
    for (int k = 0; k < 11; k++) {
        float ang = (float(k) + (hash11(seed + float(k)) - 0.5) * 0.8) * TAU / 11.0;
        float len = (0.12 + 0.25 * hash11(seed * 3.1 + float(k))) * s;
        // wobble the crack line a little
        float wob = (vnoise(float2(r * 40.0, seed + float(k))) - 0.5) * 0.25;
        float da = abs(fmod(a - ang - wob + PI * 3.0, TAU) - PI);
        float dist = da * r;                       // ~ perpendicular distance to the crack
        float w = 0.0022 * s * (1.0 - r / len) + 0.0006;
        crack = max(crack, smoothstep(w, w * 0.3, dist) * step(r, len));
    }
    for (int k = 0; k < 2; k++) {                  // concentric rings
        float rr = (0.045 + 0.04 * float(k)) * s * (0.85 + 0.3 * hash11(seed + 7.0 * float(k)));
        float ring = smoothstep(0.0025 * s, 0.0, abs(r - rr)) * step(0.4, vnoise(float2(a * 3.0, seed + float(k))));
        crack = max(crack, ring * 0.8);
    }
    float bruise = smoothstep(0.05 * s, 0.0, r);
    return float2(max(hole, bruise * 0.35), crack);
}

float4 effect(Twz t) {
    float2 p = t.centered();
    if (t.pass == 0) {
        float4 g = t.sample(t.glass, t.uv);
        float s = t.p.size;
        if (t.frame == 0) {
            g = float4(0);
            for (int i = 0; i < 8; i++) {
                if (i >= t.p.initial) break;
                float2 c = (hash22(float2(i, 3.7)) - 0.5) * float2(t.aspect * 0.8, 0.8);
                float2 h = holeAt(p, c, s, float(i) * 11.0);
                g.r = max(g.r, h.x); g.g = max(g.g, h.y);
            }
        }
        if (t.p.shoot) {
            float2 c = (t.random.xy - 0.5) * float2(t.aspect * 0.85, 0.85);
            float2 h = holeAt(p, c, s, t.random.z * 100.0);
            g.r = max(g.r, h.x); g.g = max(g.g, h.y);
        }
        return g;
    }
    float4 g = t.sample(t.glass, t.uv);
    float2 refr = t.uv + float2(g.g * 0.004);
    float3 c = t.sample(refr).rgb;
    c = mix(c, c * 0.4 + 0.65, g.g * 0.9);     // white cracks
    c = mix(c, float3(0.02), g.r);              // dark hole
    return float4(c, 1.0);
}
