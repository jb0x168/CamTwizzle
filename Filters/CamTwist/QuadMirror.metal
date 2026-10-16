/*{ "NAME": "Mirror", "CATEGORIES": ["CamTwist", "Geometry"], "DESCRIPTION": "Four mirrored copies of the picture (CamTwist's Mirror).", "INPUTS": [] }*/
float4 effect(Twz t) {
    float2 uv = fract(t.uv * 2.0);
    if (t.uv.x >= 0.5) uv.x = 1.0 - uv.x;
    if (t.uv.y >= 0.5) uv.y = 1.0 - uv.y;
    return t.sample(uv);
}
