/*{
  "NAME": "VHS",
  "CATEGORIES": ["Retro"],
  "DESCRIPTION": "Worn VHS tape: chroma bleed, tracking noise, wobble and an on-screen display.",
  "INPUTS": [
    { "NAME": "wear", "LABEL": "Tape Wear", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0, "MAX": 1 },
    { "NAME": "tracking", "LABEL": "Tracking Noise", "TYPE": "float", "DEFAULT": 0.4, "MIN": 0, "MAX": 1 },
    { "NAME": "osd", "LABEL": "On-Screen Text", "TYPE": "text", "DEFAULT": "PLAY ▶\n{date:MMM. dd yyyy}", "FONT": "Menlo-Bold", "FONTSIZE": 80 },
    { "NAME": "showOSD", "LABEL": "Show OSD", "TYPE": "bool", "DEFAULT": true }
  ]
}*/
float3 rgb2yiq(float3 c) { return float3(dot(c, float3(0.299, 0.587, 0.114)), dot(c, float3(0.596, -0.274, -0.322)), dot(c, float3(0.211, -0.523, 0.312))); }
float3 yiq2rgb(float3 y) { return float3(y.x + 0.956 * y.y + 0.621 * y.z, y.x - 0.272 * y.y - 0.647 * y.z, y.x - 1.106 * y.y + 1.703 * y.z); }

float4 effect(Twz t) {
    float2 uv = t.uv;
    float w = t.p.wear;
    // horizontal wobble per line + slow warp
    uv.x += (vnoise(float2(uv.y * 120.0, t.time * 8.0)) - 0.5) * 0.004 * w;
    uv.x += sin(uv.y * 6.0 + t.time * 1.3) * 0.002 * w;
    // tracking band rolling down
    float band = fract(t.time * 0.11);
    float inBand = smoothstep(0.05, 0.0, abs(uv.y - band)) * t.p.tracking;
    uv.x += inBand * (hash11(floor(uv.y * 200.0) + t.time) - 0.5) * 0.06;
    // luma sharp, chroma blurred horizontally (and shifted)
    float3 yiq = rgb2yiq(t.sample(uv).rgb);
    float3 chroma = 0;
    for (int i = -4; i <= 4; i++) chroma += rgb2yiq(t.sample(uv + float2((float(i) * 3.0 + 6.0 * w) * t.texel.x * (t.inputSize.y / 720.0), 0)).rgb);
    yiq.yz = chroma.yz / 9.0 * (1.0 - 0.25 * w);
    float3 c = yiq2rgb(yiq);
    // tape noise speckles and lines
    float line = step(1.0 - 0.004 * t.p.tracking, hash12(float2(floor(uv.y * t.inputSize.y), floor(t.time * 30.0))));
    float spk = step(0.985, hash12(t.pos * 0.5 + t.time)) * inBand;
    c = mix(c, float3(0.9), clamp(line * 0.6 + spk + inBand * 0.25 * hash12(t.pos + t.time), 0.0, 1.0));
    c *= 0.94 + 0.06 * sin(t.pos.y * PI);                     // faint scanlines
    c = mix(c, c * float3(1.05, 0.98, 1.08), w);              // slight color cast
    float vig = smoothstep(1.1, 0.4, length((t.uv - 0.5) * float2(t.aspect, 1.0)));
    c *= mix(1.0, vig, 0.5);
    float4 out = float4(clamp(c, 0.0, 1.0), 1.0);
    if (t.p.showOSD) out = t.drawText(out, t.osd, float2(0.05 + t.placedWidth(t.osd, 0.12) * 0.5, 0.12), 0.12, float4(1, 1, 1, 0.92), float4(0, 0, 0, 0.5));
    return out;
}
