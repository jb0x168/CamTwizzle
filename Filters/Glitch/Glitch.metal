/*{
  "NAME": "Glitch",
  "CATEGORIES": ["Glitch"],
  "DESCRIPTION": "Digital corruption: RGB split, displaced blocks, line jitter and inverted flashes, in bursts.",
  "INPUTS": [
    { "NAME": "intensity", "LABEL": "Intensity", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0, "MAX": 1 },
    { "NAME": "frequency", "LABEL": "Burst Frequency", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0, "MAX": 1 },
    { "NAME": "blocks", "LABEL": "Block Size", "TYPE": "float", "DEFAULT": 0.06, "MIN": 0.01, "MAX": 0.3 }
  ]
}*/
float4 effect(Twz t) {
    float tt = floor(t.time * 12.0);
    float burst = step(1.0 - t.p.frequency * 0.6, hash11(tt * 1.7)) * t.p.intensity;
    float always = t.p.intensity * 0.15;
    float2 uv = t.uv;
    // block displacement
    float2 bsz = float2(t.p.blocks * 3.0, t.p.blocks);
    float2 blk = floor(uv / bsz);
    float r = hash12(blk + tt);
    if (r < burst * 0.35) uv.x += (hash12(blk * 1.3 + tt) - 0.5) * 0.25 * burst;
    // line jitter
    float ln = floor(uv.y * t.inputSize.y / 3.0);
    if (hash11(ln + tt * 13.0) < burst * 0.15) uv.x += (hash11(ln * 3.1 + tt) - 0.5) * 0.08;
    float sp = (burst * 0.02 + always * 0.02) * (0.5 + hash11(tt));
    float3 c = float3(t.sample(uv + float2(sp, 0)).r, t.sample(uv).g, t.sample(uv - float2(sp, sp * 0.3)).b);
    // color quantize & invert flashes in some blocks
    if (r > 1.0 - burst * 0.12) c = 1.0 - c;
    if (r > 1.0 - burst * 0.25 && r < 1.0 - burst * 0.12) c = posterize(c, 3.0);
    // occasional dropped scanlines
    c *= 1.0 - 0.35 * step(1.0 - burst * 0.1, hash12(float2(ln, tt)));
    return float4(c, 1.0);
}
