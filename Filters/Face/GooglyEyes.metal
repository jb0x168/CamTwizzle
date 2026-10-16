/*{
  "NAME": "Googly Eyes",
  "CATEGORIES": ["Face", "Overlay"],
  "DESCRIPTION": "Big wobbly googly eyes stuck over your eyes.",
  "FACE": true,
  "INPUTS": [ { "NAME": "size", "LABEL": "Size", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0.4, "MAX": 2.5 },
              { "NAME": "wobble", "LABEL": "Wobble", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0, "MAX": 3 } ]
}*/
float3 googly(float3 bg, float2 p, float2 c, float r, float phase, float wob) {
    float2 d = p - c;
    float dist = length(d);
    if (dist > r * 1.08) return bg;
    float3 col = mix(float3(0.05), bg, smoothstep(r * 1.0, r * 1.08, dist));           // rim shadow
    col = mix(col, float3(0.97), smoothstep(r, r * 0.97, dist));                     // white
    float2 pupil = float2(sin(phase) * 0.35, 0.3 + 0.1 * cos(phase * 1.3)) * r * wob;
    pupil = normalize(pupil + 1e-5) * min(length(pupil), r * 0.45);
    float pd = length(d - pupil);
    col = mix(col, float3(0.02), smoothstep(r * 0.52, r * 0.49, pd));
    col += smoothstep(r * 0.25, 0.0, length(d - float2(-0.35, -0.35) * r)) * 0.6;     // shine
    return col;
}
float4 effect(Twz t) {
    float4 c = t.sample(t.uv);
    if (t.faceCount == 0) return c;
    float2 p = t.centered();
    float eyeDist = length((t.rightEye - t.leftEye) * float2(t.aspect, 1.0));
    float r = eyeDist * 0.42 * t.p.size;
    float3 col = c.rgb;
    col = googly(col, p, t.centered(t.leftEye), r, t.time * 7.0 + sin(t.time * 3.1) * 2.0, t.p.wobble);
    col = googly(col, p, t.centered(t.rightEye), r, t.time * 6.3 + 1.7 + sin(t.time * 2.7) * 2.0, t.p.wobble);
    return float4(col, 1.0);
}
