/*{
  "NAME": "Color LUT",
  "CATEGORIES": ["Color", "Photo"],
  "DESCRIPTION": "Apply a 3D color lookup table stored as a PNG (the common 512×512 8×8-tile layout, or a 64×4096/4096×64 strip). Great for film emulation packs.",
  "INPUTS": [ { "NAME": "lut", "LABEL": "LUT Image", "TYPE": "image" },
              { "NAME": "amount", "LABEL": "Amount", "TYPE": "float", "DEFAULT": 1, "MIN": 0, "MAX": 1 } ]
}*/
float2 lutUV(float b, float2 rg, float2 sz) {
    // 512x512 with 8x8 tiles of 64x64, or a horizontal 64-tile strip
    bool strip = sz.x > sz.y * 4.0;
    float n = strip ? sz.y : 64.0;
    float slice = clamp(b * (n - 1.0), 0.0, n - 1.0);
    float2 tile = strip ? float2(slice, 0.0) : float2(fmod(slice, 8.0), floor(slice / 8.0));
    float2 inner = (rg * (n - 1.0) + 0.5) / n;
    float2 grid = strip ? float2(n, 1.0) : float2(8.0, 8.0);
    return (tile + inner) / grid;
}
float4 effect(Twz t) {
    float3 c = t.sample(t.uv).rgb;
    if (t.p.lut_size.x < 2.0) return float4(c, 1.0);
    bool strip = t.p.lut_size.x > t.p.lut_size.y * 4.0;
    float n = strip ? t.p.lut_size.y : 64.0;
    float s = c.b * (n - 1.0);
    float b0 = floor(s) / (n - 1.0), b1 = min(floor(s) + 1.0, n - 1.0) / (n - 1.0);
    float3 l0 = t.sampleNearest(t.lut, lutUV(b0, c.rg, t.p.lut_size)).rgb;
    float3 l1 = t.sampleNearest(t.lut, lutUV(b1, c.rg, t.p.lut_size)).rgb;
    float3 l = mix(l0, l1, fract(s));
    return float4(mix(c, l, t.p.amount), 1.0);
}
