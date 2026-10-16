/*{
  "NAME": "Deal With It",
  "CATEGORIES": ["Face", "Overlay"],
  "DESCRIPTION": "Pixel-art sunglasses slide down onto your face. Click 'Drop' to do it again.",
  "FACE": true,
  "INPUTS": [ { "NAME": "drop", "LABEL": "Drop", "TYPE": "event" },
              { "NAME": "size", "LABEL": "Size", "TYPE": "float", "DEFAULT": 1, "MIN": 0.5, "MAX": 2 },
              { "NAME": "duration", "LABEL": "Drop Time", "TYPE": "float", "DEFAULT": 2.0, "MIN": 0.2, "MAX": 6 } ],
  "PASSES": [ { "TARGET": "state", "PERSISTENT": true, "FLOAT32": true, "WIDTH": "1", "HEIGHT": "1" }, {} ]
}*/
// 16x5 pixel sunglasses bitmap (1 = black, 2 = white glint)
constant uchar glasses[80] = {
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    0,1,2,2,1,1,1,0,0,1,2,2,1,1,1,0,
    0,1,2,1,1,1,1,0,0,1,2,1,1,1,1,0,
    0,0,1,1,1,1,0,0,0,0,1,1,1,1,0,0,
    0,0,0,1,1,0,0,0,0,0,0,1,1,0,0,0 };
float4 effect(Twz t) {
    if (t.pass == 0) {
        // state.r = time when the drop started
        float start = t.sample(t.state, float2(0.5)).r;
        if (t.frame == 0 || t.p.drop) start = t.time;
        return float4(start, 0, 0, 1);
    }
    float4 c = t.sample(t.uv);
    if (t.faceCount == 0) return c;
    float start = t.sample(t.state, float2(0.5)).r;
    float k = clamp((t.time - start) / t.p.duration, 0.0, 1.0);
    k = 1.0 - pow(1.0 - k, 3.0);
    float2 ec = (t.leftEye + t.rightEye) * 0.5;
    float ed = length((t.rightEye - t.leftEye) * float2(t.aspect, 1.0));
    float w = ed * 2.3 * t.p.size;
    float2 target = t.centered(ec) + float2(0, ed * 0.05);
    float2 pos = mix(float2(target.x, -0.7), target, k);
    float2 d = rotate2d(t.centered() - pos, -t.faceRoll * k);
    float2 g = d / float2(w, w * 5.0 / 16.0) + 0.5;
    if (any(g < 0.0) || any(g >= 1.0)) return c;
    int2 px = int2(g * float2(16, 5));
    uchar v = glasses[px.y * 16 + px.x];
    if (v == 1) return float4(0.02, 0.02, 0.02, 1);
    if (v == 2) return float4(0.95, 0.95, 0.95, 1);
    return c;
}
