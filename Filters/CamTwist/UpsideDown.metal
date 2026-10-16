/*{ "NAME": "Upside Down", "CATEGORIES": ["CamTwist", "Geometry"], "DESCRIPTION": "Flip the picture vertically.", "INPUTS": [] }*/
float4 effect(Twz t) { return t.sample(float2(t.uv.x, 1.0 - t.uv.y)); }
