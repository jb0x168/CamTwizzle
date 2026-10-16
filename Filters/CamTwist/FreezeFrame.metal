/*{
  "NAME": "Freeze Frame",
  "CATEGORIES": ["CamTwist", "Time"],
  "DESCRIPTION": "Hold the current picture while Freeze is on — step away from your desk unnoticed.",
  "INPUTS": [ { "NAME": "freeze", "LABEL": "Freeze", "TYPE": "bool", "DEFAULT": false } ],
  "PASSES": [ { "TARGET": "held", "PERSISTENT": true } ]
}*/
float4 effect(Twz t) {
    if (!t.p.freeze || t.frame == 0) return t.sample(t.uv);
    return t.sample(t.held, t.uv);
}
