/*{
  "NAME": "Image Overlay",
  "CATEGORIES": ["CamTwist", "Overlay"],
  "DESCRIPTION": "Places an image (PNG with transparency works great) over the picture, with border and crop.",
  "INPUTS": [
    { "NAME": "image", "LABEL": "Image", "TYPE": "image" },
    { "NAME": "center", "LABEL": "Position", "TYPE": "point2D", "DEFAULT": [0.85, 0.15] },
    { "NAME": "scale", "LABEL": "Height", "TYPE": "float", "DEFAULT": 0.25, "MIN": 0.02, "MAX": 1.5 },
    { "NAME": "rotation", "LABEL": "Rotation", "TYPE": "float", "DEFAULT": 0, "MIN": -180, "MAX": 180 },
    { "NAME": "opacity", "LABEL": "Opacity", "TYPE": "float", "DEFAULT": 1, "MIN": 0, "MAX": 1 },
    { "NAME": "border", "LABEL": "Border Width", "TYPE": "float", "DEFAULT": 0, "MIN": 0, "MAX": 0.05 },
    { "NAME": "borderColor", "LABEL": "Border Color", "TYPE": "color", "DEFAULT": [1, 1, 1, 1] }
  ]
}*/
float4 effect(Twz t) {
    float4 c = t.sample(t.uv);
    if (t.p.image_size.x < 1.0) return c;
    float2 d = (t.uv - t.p.center) * float2(t.aspect, 1.0);
    d = rotate2d(d, -t.p.rotation * PI / 180.0);
    float h = t.p.scale;
    float w = h * t.p.image_size.x / t.p.image_size.y;
    float2 local = d / float2(w, h) + 0.5;
    float2 b = abs(d) - float2(w, h) * 0.5;
    float inBorder = step(max(b.x, b.y), t.p.border) * step(0.0001, t.p.border);
    c.rgb = mix(c.rgb, t.p.borderColor.rgb, inBorder * t.p.borderColor.a * t.p.opacity);
    if (all(local >= 0.0) && all(local <= 1.0)) {
        float4 img = t.sample(t.image, local);
        c.rgb = mix(c.rgb, img.rgb, img.a * t.p.opacity);
    }
    return float4(c.rgb, 1.0);
}
