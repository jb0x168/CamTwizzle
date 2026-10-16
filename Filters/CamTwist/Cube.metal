/*{
  "NAME": "Cube",
  "CATEGORIES": ["CamTwist", "Geometry"],
  "DESCRIPTION": "Your picture on every face of a spinning 3D cube.",
  "INPUTS": [
    { "NAME": "period", "LABEL": "Seconds per Turn", "TYPE": "float", "DEFAULT": 10, "MIN": 1, "MAX": 60 },
    { "NAME": "size", "LABEL": "Size", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0.3, "MAX": 2 },
    { "NAME": "background", "LABEL": "Background", "TYPE": "long", "DEFAULT": 0, "VALUES": [0, 1, 2], "LABELS": ["Blurred Picture", "Gradient", "Black"] }
  ]
}*/

bool boxHit(float3 ro, float3 rd, thread float &tHit, thread float3 &n) {
    float3 m = 1.0 / rd;
    float3 k = abs(m);
    float3 t1 = -m * ro - k, t2 = -m * ro + k;
    float tN = max(max(t1.x, t1.y), t1.z), tF = min(min(t2.x, t2.y), t2.z);
    if (tN > tF || tF < 0.0) return false;
    tHit = tN;
    n = -sign(rd) * step(t1.yzx, t1.xyz) * step(t1.zxy, t1.xyz);
    return true;
}

float3x3 rotXY(float a, float b) {
    float ca = cos(a), sa = sin(a), cb = cos(b), sb = sin(b);
    float3x3 rx = float3x3(float3(1, 0, 0), float3(0, ca, -sa), float3(0, sa, ca));
    float3x3 ry = float3x3(float3(cb, 0, sb), float3(0, 1, 0), float3(-sb, 0, cb));
    return ry * rx;
}

float4 effect(Twz t) {
    float2 p = t.centered() * float2(1.0, -1.0);
    float3 ro = float3(0, 0, -4.2 / t.p.size);
    float3 rd = normalize(float3(p, 1.6));
    float a = t.time * TAU / max(t.p.period, 0.1);
    float3x3 R = rotXY(a * 0.7 + 0.5, a);
    float3x3 Ri = transpose(R);
    float3 lro = Ri * ro, lrd = Ri * rd;
    float th; float3 n;
    float3 bg;
    if (t.p.background == 0) bg = t.blur(18.0).rgb * 0.45;
    else if (t.p.background == 1) bg = mix(float3(0.12, 0.05, 0.25), float3(0.02, 0.02, 0.05), t.uv.y);
    else bg = float3(0);
    if (!boxHit(lro, lrd, th, n)) return float4(bg, 1.0);
    float3 hp = lro + lrd * th;
    float2 fuv;
    if (abs(n.x) > 0.5) fuv = float2(hp.z * sign(n.x), -hp.y);
    else if (abs(n.y) > 0.5) fuv = float2(hp.x, hp.z * sign(n.y));
    else fuv = float2(-hp.x * sign(n.z), -hp.y);
    fuv = fuv * 0.5 + 0.5;
    // Keep the picture's aspect on square faces: crop to a centered square.
    float2 suv = float2(0.5 + (fuv.x - 0.5) / t.aspect, fuv.y);
    float3 col = t.sample(suv).rgb;
    float3 wn = R * n;
    float diff = clamp(dot(wn, normalize(float3(0.4, 0.6, -0.7))), 0.0, 1.0);
    col *= 0.45 + 0.65 * diff;
    float edge = max(max(abs(hp.x) * abs(hp.y), abs(hp.y) * abs(hp.z)), abs(hp.x) * abs(hp.z));
    col *= 1.0 - 0.35 * smoothstep(0.92, 1.0, edge);
    return float4(col, 1.0);
}
