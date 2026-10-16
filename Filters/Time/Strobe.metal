/*{
  "NAME": "Strobe",
  "CATEGORIES": ["Time"],
  "DESCRIPTION": "Choppy low frame rate, optionally with flashes — like a nightclub strobe or a stop-motion film.",
  "INPUTS": [ { "NAME": "fps", "LABEL": "Frames per Second", "TYPE": "float", "DEFAULT": 6, "MIN": 1, "MAX": 30 },
              { "NAME": "flash", "LABEL": "Flash", "TYPE": "float", "DEFAULT": 0.0, "MIN": 0, "MAX": 1 } ],
  "PASSES": [ { "TARGET": "held", "PERSISTENT": true }, {} ]
}*/
float4 effect(Twz t) {
    float slot = floor(t.time * t.p.fps);
    float prevSlot = floor((t.time - t.dt) * t.p.fps);
    bool grab = slot != prevSlot || t.frame == 0;
    if (t.pass == 0) return grab ? t.sample(t.uv) : t.sample(t.held, t.uv);
    float3 c = t.sample(t.held, t.uv).rgb;
    float ph = fract(t.time * t.p.fps);
    c += t.p.flash * smoothstep(0.3, 0.0, ph);
    return float4(c, 1.0);
}
