/*{
  "NAME": "Clown Nose",
  "CATEGORIES": ["Face", "Overlay"],
  "DESCRIPTION": "A shiny red clown nose (honk!).",
  "FACE": true,
  "INPUTS": [ { "NAME": "size", "LABEL": "Size", "TYPE": "float", "DEFAULT": 1, "MIN": 0.4, "MAX": 3 },
              { "NAME": "color", "LABEL": "Color", "TYPE": "color", "DEFAULT": [0.9, 0.05, 0.05, 1] } ]
}*/
float4 effect(Twz t) {
    float4 c = t.sample(t.uv);
    if (t.faceCount == 0) return c;
    float ed = length((t.rightEye - t.leftEye) * float2(t.aspect, 1.0));
    float r = ed * 0.33 * t.p.size;
    float2 n = t.centered(t.nose);
    float2 d = t.centered() - n;
    float dist = length(d);
    float3 col = c.rgb * (1.0 - 0.35 * smoothstep(r * 1.25, r, length(d - float2(0.0, r * 0.15))));  // shadow
    if (dist < r) {
        float3 nrm = normalize(float3(d / r, sqrt(max(0.0, 1.0 - dot(d, d) / (r * r)))));
        float diff = clamp(dot(nrm, normalize(float3(-0.4, -0.5, 0.75))), 0.0, 1.0);
        float spec = pow(clamp(dot(reflect(normalize(float3(0.4, 0.5, -0.75)), nrm), float3(0, 0, 1)), 0.0, 1.0), 30.0);
        float3 ball = t.p.color.rgb * (0.3 + 0.8 * diff) + spec;
        col = mix(col, ball, smoothstep(r, r * 0.95, dist));
    }
    return float4(col, 1.0);
}
