/*{
  "NAME": "Face Censor",
  "CATEGORIES": ["Face"],
  "DESCRIPTION": "Hides the face with pixelation, blur or a black bar — 'witness protection'.",
  "FACE": true,
  "INPUTS": [ { "NAME": "mode", "LABEL": "Style", "TYPE": "long", "DEFAULT": 0, "VALUES": [0, 1, 2], "LABELS": ["Pixelate", "Blur", "Eye Bar"] },
              { "NAME": "blocks", "LABEL": "Pixel Blocks", "TYPE": "float", "DEFAULT": 10, "MIN": 3, "MAX": 40 },
              { "NAME": "margin", "LABEL": "Margin", "TYPE": "float", "DEFAULT": 1.2, "MIN": 0.8, "MAX": 2 } ]
}*/
float4 effect(Twz t) {
    float4 c = t.sample(t.uv);
    if (t.faceCount == 0) return c;
    float2 fc = float2(t.face.x + t.face.z * 0.5, t.face.y + t.face.w * 0.5);
    float2 half_ = float2(t.face.z, t.face.w) * 0.5 * t.p.margin;
    if (t.p.mode == 2) {
        float2 ec = (t.leftEye + t.rightEye) * 0.5;
        float2 d = rotate2d((t.uv - ec) * float2(t.aspect, 1.0), -t.faceRoll);
        float w = length((t.rightEye - t.leftEye) * float2(t.aspect, 1.0));
        return (abs(d.x) < w * 1.05 && abs(d.y) < w * 0.22) ? float4(0, 0, 0, 1) : c;
    }
    float2 d = (t.uv - fc) / half_;
    if (length(d) > 1.0) return c;
    if (t.p.mode == 0) {
        float bs = t.face.w * t.p.margin / t.p.blocks;
        float2 cell = floor(t.uv / float2(bs / t.aspect, bs));
        return t.blurAt((cell + 0.5) * float2(bs / t.aspect, bs), bs * t.inputSize.y * 0.3);
    }
    return t.blur(t.face.w * t.inputSize.y * 0.08);
}
