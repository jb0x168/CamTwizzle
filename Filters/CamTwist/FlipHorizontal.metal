/*{ "NAME": "LR Flip", "CATEGORIES": ["CamTwist", "Geometry"], "DESCRIPTION": "Mirror the picture left-to-right.", "INPUTS": [] }*/
float4 effect(Twz t) { return t.sample(float2(1.0 - t.uv.x, t.uv.y)); }
