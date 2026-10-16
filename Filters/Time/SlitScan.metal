/*{
  "NAME": "Slit Scan",
  "CATEGORIES": ["Time", "Distortion"],
  "DESCRIPTION": "Each band of the picture comes from a different moment in the past — movement turns into rubbery stretches.",
  "INPUTS": [ { "NAME": "direction", "LABEL": "Direction", "TYPE": "long", "DEFAULT": 0, "VALUES": [0, 1, 2], "LABELS": ["Top is oldest", "Left is oldest", "Center is newest"] },
              { "NAME": "frameStep", "LABEL": "Frames Between Slices", "TYPE": "float", "DEFAULT": 2, "MIN": 1, "MAX": 8 } ],
  "PASSES": [ { "TARGET": "atlas", "PERSISTENT": true, "WIDTH": "$WIDTH", "HEIGHT": "$HEIGHT" }, {} ]
}*/
// The atlas holds 16 quarter-size frames in a 4×4 grid; slot = (frame / step) % 16.
float4 effect(Twz t) {
    int step_ = max(1, int(t.p.frameStep));
    int slot = (t.frame / step_) % 16;
    if (t.pass == 0) {
        float2 cell = floor(t.uv * 4.0);
        int idx = int(cell.y) * 4 + int(cell.x);
        if (idx == slot && t.frame % step_ == 0) return t.sample(fract(t.uv * 4.0));
        if (t.frame == 0) return t.sample(fract(t.uv * 4.0));
        return t.sample(t.atlas, t.uv);
    }
    float age;
    if (t.p.direction == 0) age = 1.0 - t.uv.y;
    else if (t.p.direction == 1) age = 1.0 - t.uv.x;
    else age = clamp(length(t.centered()) * 1.6, 0.0, 1.0);
    int back = int(age * 15.0);
    int s = (slot - back + 16) % 16;
    float2 tile = float2(s % 4, s / 4);
    return t.sample(t.atlas, (tile + clamp(t.uv, 0.002, 0.998)) / 4.0);
}
