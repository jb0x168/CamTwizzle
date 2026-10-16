/*{
  "NAME": "Auto Frame",
  "CATEGORIES": ["Face", "Geometry"],
  "DESCRIPTION": "Center-Stage style: zooms in and keeps your face nicely framed as you move.",
  "FACE": true,
  "INPUTS": [ { "NAME": "zoom", "LABEL": "Max Zoom", "TYPE": "float", "DEFAULT": 1.8, "MIN": 1, "MAX": 4 },
              { "NAME": "headroom", "LABEL": "Face Height in Frame", "TYPE": "float", "DEFAULT": 0.38, "MIN": 0.15, "MAX": 0.8 },
              { "NAME": "smoothing", "LABEL": "Smoothness", "TYPE": "float", "DEFAULT": 0.9, "MIN": 0, "MAX": 0.99 } ],
  "PASSES": [ { "TARGET": "cam", "PERSISTENT": true, "FLOAT32": true, "WIDTH": "1", "HEIGHT": "1" }, {} ]
}*/
float4 effect(Twz t) {
    if (t.pass == 0) {
        float4 prev = t.sample(t.cam, float2(0.5));        // xy = center, z = zoom
        float3 target = float3(0.5, 0.5, 1.0);
        if (t.faceCount > 0) {
            float z = clamp(t.p.headroom / max(t.face.w, 0.01), 1.0, t.p.zoom);
            float2 fc = float2(t.face.x + t.face.z * 0.5, t.face.y + t.face.w * 0.5);
            target = float3(fc.x, fc.y + 0.08 / z, z);
        }
        if (t.frame == 0 || prev.z < 0.5) return float4(target, 1);
        float k = 1.0 - t.p.smoothing;
        return float4(mix(prev.xyz, target, k), 1);
    }
    float4 cam = t.sample(t.cam, float2(0.5));
    float z = max(cam.z, 1.0);
    float2 half_ = 0.5 / z;
    float2 c = clamp(cam.xy, half_, 1.0 - half_);
    return t.sample(c + (t.uv - 0.5) / z);
}
