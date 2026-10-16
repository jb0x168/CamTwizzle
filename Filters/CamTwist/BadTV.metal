/*{
  "NAME": "Bad TV",
  "CATEGORIES": ["CamTwist", "Retro", "Glitch"],
  "DESCRIPTION": "Analog TV with bad reception: line distortion, rolling picture, scan lines and static. After CamTwist's Msa_badtv.",
  "CREDIT": "after Msa (Memo Akten) badtv for CamTwist",
  "INPUTS": [
    { "NAME": "distortion", "LABEL": "Distortion", "TYPE": "float", "DEFAULT": 0.125, "MIN": 0, "MAX": 1 },
    { "NAME": "lineSync", "LABEL": "Line Sync", "TYPE": "float", "DEFAULT": 0.2, "MIN": 0, "MAX": 1 },
    { "NAME": "verticalSync", "LABEL": "Vertical Roll", "TYPE": "float", "DEFAULT": 0.125, "MIN": 0, "MAX": 1 },
    { "NAME": "bars", "LABEL": "Rolling Bars", "TYPE": "float", "DEFAULT": 0.44, "MIN": 0, "MAX": 1 },
    { "NAME": "scanLines", "LABEL": "Scan Lines", "TYPE": "float", "DEFAULT": 0.7, "MIN": 0, "MAX": 1 },
    { "NAME": "noise", "LABEL": "Static", "TYPE": "float", "DEFAULT": 0.25, "MIN": 0, "MAX": 1 }
  ]
}*/
float4 effect(Twz t) {
    float2 uv = t.uv;
    float time = t.time;
    // Vertical roll: occasional slipping of the vertical hold.
    float roll = t.p.verticalSync * (time * 0.4 + 0.3 * vnoise(float2(time * 0.7, 2.0)));
    uv.y = fract(uv.y + roll * step(0.5, vnoise(float2(time * 0.3, 9.0))));
    // Line distortion: wobbly horizontal offsets.
    float line = vnoise(float2(uv.y * 8.0, time * 3.0)) - 0.5;
    float fine = vnoise(float2(uv.y * 240.0, time * 40.0)) - 0.5;
    uv.x += line * t.p.distortion * 0.2 + fine * t.p.lineSync * 0.02;
    // Sudden sync tears.
    float tear = step(0.985 - t.p.lineSync * 0.05, hash12(float2(floor(uv.y * 60.0), floor(time * 12.0))));
    uv.x += tear * (hash11(floor(time * 12.0)) - 0.5) * 0.15 * t.p.lineSync;
    float3 c;
    c.r = t.sample(uv + float2(0.003 * t.p.distortion, 0)).r;
    c.g = t.sample(uv).g;
    c.b = t.sample(uv - float2(0.003 * t.p.distortion, 0)).b;
    // Rolling dark bars
    float bar = 0.5 + 0.5 * sin((uv.y - time * 0.18) * TAU * 1.5);
    c *= 1.0 - t.p.bars * 0.45 * smoothstep(0.6, 1.0, bar);
    // Scan lines
    float sl = 0.5 + 0.5 * cos(t.pos.y * PI);
    c *= 1.0 - t.p.scanLines * 0.35 * sl;
    // Static
    float n = hash12(t.pos + fract(time * 37.0) * 917.0);
    c = mix(c, float3(n), t.p.noise * 0.35);
    return float4(c, 1.0);
}
