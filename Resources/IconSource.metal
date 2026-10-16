/*{ "NAME": "Icon", "INPUTS": [] }*/
float sdSquircle(float2 p, float r, float n) { p = abs(p); return pow(pow(p.x, n) + pow(p.y, n), 1.0 / n) - r; }
float4 effect(Twz t) {
    float2 p = (t.uv - 0.5) * 2.0;              // -1..1
    float d = sdSquircle(p, 0.8, 5.0);
    float a = smoothstep(0.006, -0.006, d);
    if (a <= 0.0) return float4(0);
    // background: deep violet to magenta, with a soft glow
    float3 bg = mix(float3(0.16, 0.05, 0.36), float3(0.85, 0.18, 0.55), smoothstep(-0.9, 0.9, p.x + p.y * 0.6));
    bg += float3(1.0, 0.6, 0.9) * exp(-length(p - float2(-0.35, -0.45)) * 2.5) * 0.25;
    float3 c = bg;
    // camera body
    float2 bp = p - float2(0.0, 0.08);
    float body = sdRoundBox(bp, float2(0.56, 0.36), 0.12);
    float hump = sdRoundBox(bp - float2(-0.22, -0.38), float2(0.16, 0.08), 0.05);
    float cam = min(body, hump);
    float shadow = smoothstep(0.08, -0.02, min(sdRoundBox(bp - float2(0.03, 0.05), float2(0.56, 0.36), 0.12), 1.0));
    c *= 1.0 - 0.35 * shadow * step(0.0, cam);
    float3 bodyCol = mix(float3(0.97, 0.96, 1.0), float3(0.78, 0.76, 0.86), smoothstep(-0.35, 0.4, bp.y));
    c = mix(c, bodyCol, smoothstep(0.006, -0.006, cam));
    // lens ring + twisted rainbow inside
    float2 lp = bp - float2(0.06, 0.04);
    float r = length(lp);
    float ring = smoothstep(0.006, -0.006, r - 0.34);
    c = mix(c, float3(0.12, 0.1, 0.18), ring);
    if (r < 0.28) {
        float ang = atan2(lp.y, lp.x + 1e-6) + (0.28 - r) * 14.0;      // the twizzle
        float3 swirl = hsv2rgb(float3(fract(ang / TAU + 0.15), 0.75, 1.0));
        swirl *= 0.75 + 0.25 * cos(ang * 6.0);
        swirl = mix(swirl, float3(1.0), smoothstep(0.08, 0.0, r) * 0.3);
        c = mix(c, swirl, smoothstep(0.282, 0.276, r));
        c += smoothstep(0.09, 0.0, length(lp - float2(-0.1, -0.11))) * 0.55;   // glint
    }
    // flash dot
    c = mix(c, float3(1.0, 0.75, 0.2), smoothstep(0.006, -0.006, length(bp - float2(0.38, -0.2)) - 0.05));
    return float4(c * a, a);
}
