/*{
  "NAME": "Datamosh",
  "CATEGORIES": ["Glitch", "Time"],
  "DESCRIPTION": "Compression-glitch smear: blocks keep old pixels and drift along with motion until they get refreshed.",
  "INPUTS": [
    { "NAME": "refresh", "LABEL": "Refresh Rate", "TYPE": "float", "DEFAULT": 0.08, "MIN": 0, "MAX": 1 },
    { "NAME": "drift", "LABEL": "Drift", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0, "MAX": 2 },
    { "NAME": "block", "LABEL": "Block Size (px @720p)", "TYPE": "float", "DEFAULT": 16, "MIN": 4, "MAX": 64 },
    { "NAME": "keyframe", "LABEL": "Insert Keyframe", "TYPE": "event" }
  ],
  "PASSES": [ { "TARGET": "mosh", "PERSISTENT": true }, { "TARGET": "prevIn", "PERSISTENT": true, "SCALE": 0.25 }, {} ]
}*/
float4 effect(Twz t) {
    if (t.pass == 0) {
        float bs = t.p.block * t.inputSize.y / 720.0;
        float2 blk = floor(t.pos / bs);
        float tt = floor(t.time * 10.0);
        float2 cuv = (blk + 0.5) * bs / t.size;
        float3 now = t.sample(cuv).rgb, before = t.sample(t.prevIn, cuv).rgb;
        float motion = length(now - before);
        // crude motion vector from luma gradients (optical-flow-ish)
        Twz u = t; u.uv = cuv;
        float2 g = u.grad(3.0);
        float dt = luma(now) - luma(before);
        float2 v = -dt * g / max(dot(g, g), 0.002) * 0.02 * t.p.drift;
        bool refresh = t.frame < 2 || t.p.keyframe || hash12(blk + tt) < t.p.refresh * 0.25 || motion < 0.02;
        if (refresh) return t.sample(t.uv);
        return t.sample(t.mosh, t.uv - v + (hash22(blk + tt) - 0.5) * 0.002 * t.p.drift);
    }
    if (t.pass == 1) return t.sample(t.uv);
    return t.sample(t.mosh, t.uv);
}
