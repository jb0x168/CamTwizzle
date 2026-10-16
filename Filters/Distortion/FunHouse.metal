/*{
  "NAME": "Fun House Mirror",
  "CATEGORIES": ["Distortion"],
  "DESCRIPTION": "Carnival mirrors: tall-and-thin, short-and-wide, or wavy.",
  "INPUTS": [ { "NAME": "mode", "LABEL": "Mirror", "TYPE": "long", "DEFAULT": 0, "VALUES": [0, 1, 2, 3], "LABELS": ["Skinny Middle", "Wide Middle", "Wavy", "Hourglass"] },
              { "NAME": "amount", "LABEL": "Amount", "TYPE": "float", "DEFAULT": 0.6, "MIN": 0, "MAX": 1 },
              { "NAME": "animate", "LABEL": "Breathe", "TYPE": "bool", "DEFAULT": false } ]
}*/
float4 effect(Twz t) {
    float a = t.p.amount * (t.p.animate ? 0.6 + 0.4 * sin(t.time * 1.5) : 1.0);
    float2 uv = t.uv;
    float x = uv.x - 0.5;
    if (t.p.mode == 0) uv.x = 0.5 + x / (1.0 - a * 0.6 * exp(-x * x * 18.0)) ;
    else if (t.p.mode == 1) uv.x = 0.5 + x * (1.0 - a * 0.5 * exp(-x * x * 10.0));
    else if (t.p.mode == 2) uv.x += sin(uv.y * 12.0 + t.time) * 0.04 * a, uv.y += sin(uv.x * 9.0) * 0.03 * a;
    else uv.x = 0.5 + x * (1.0 + a * 0.8 * (0.25 - pow(uv.y - 0.5, 2.0)) * 2.0);
    if (uv.x < 0.0 || uv.x > 1.0) return float4(0.05, 0.02, 0.08, 1);
    return t.sample(uv);
}
