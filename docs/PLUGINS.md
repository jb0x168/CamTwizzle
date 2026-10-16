# Writing CamTwizzle effects

CamTwizzle loads effects ("plugins") from two places:

| Folder | What's there |
|---|---|
| `CamTwizzle.app/Contents/Resources/Filters` | the built-in library |
| `~/Library/Application Support/CamTwizzle/Effects` | **your** effects (Effects › Open My Effects Folder) |

Files in your folder override built-ins with the same file name, and **changes reload live** —
save in your editor and the effect updates in the preview immediately (compile errors show up
in red in the inspector). `Effects › New Effect from Template` gives you a starting point, and
`Customize…` in the inspector copies any built-in effect into your folder for editing.

There are three kinds of plugin:

| Extension | Kind | Best for |
|---|---|---|
| `.metal` | **Shader** — Metal Shading Language with a JSON header | anything pixel-level; multipass, feedback, text, glyphs, face/mask aware |
| `.json` / `.twzgraph` | **Graph** — a node graph of Core Image filters (and shaders) | quickly combining Apple's 200+ built-in CIFilters, Quartz-Composer style |
| `.qtz` | **Quartz Composer** composition (legacy) | running old CamTwist / QC effects as-is |

Effects are stacked: each one receives the output of the one before it.

---

## 1. Shader effects (`.metal`)

A shader effect is a Metal file that **starts with a JSON header in a block comment** (the same
idea as ISF, so the keys will feel familiar) followed by a function:

```metal
/*{
  "NAME": "Tint",
  "CATEGORIES": ["Color"],
  "DESCRIPTION": "Multiplies the picture by a color.",
  "INPUTS": [
    { "NAME": "color",  "LABEL": "Color",  "TYPE": "color", "DEFAULT": [1, 0.5, 0.2, 1] },
    { "NAME": "amount", "LABEL": "Amount", "TYPE": "float", "DEFAULT": 1, "MIN": 0, "MAX": 1 }
  ]
}*/

float4 effect(Twz t) {
    float4 c = t.sample(t.uv);
    return float4(mix(c.rgb, c.rgb * t.p.color.rgb, t.p.amount), 1.0);
}
```

`effect` runs once per output pixel. `t` (a `Twz` context) gives you everything:

| Member | Meaning |
|---|---|
| `t.uv` | position of this pixel, 0…1, **(0,0) = top-left** |
| `t.pos` | pixel coordinates in the current pass target |
| `t.size` | size of the current pass target in pixels |
| `t.inputSize`, `t.texel` | input image size and `1/inputSize` |
| `t.aspect` | width / height |
| `t.time`, `t.dt`, `t.frame` | seconds since this effect started, frame delta, frame counter |
| `t.pass` | index of the current pass (multipass effects) |
| `t.date` | year, month, day, seconds since midnight |
| `t.random` | four fresh random numbers per frame |
| `t.p.<name>` | your parameters (float / int / bool / float4 color / float2 point) |
| `t.input` | the input image texture |
| `t.<name>` | textures you declared: pass targets, glyph atlases, images, text, sources |

Sampling helpers:

```metal
t.sample(uv)                 // input, bilinear, clamped
t.sample(tex, uv)            // any texture
t.sampleNearest(tex, uv)  t.sampleRepeat(tex, uv)  t.sampleMirror(tex, uv)
t.load(px)                   // input at pixel coordinates
t.offset(float2(dx, dy))     // input at the current uv shifted by N input pixels
t.blur(radiusPx)  t.blurAt(uv, radiusPx)   // quick 13-tap blur of the input
t.edge(px)                   // Sobel edge magnitude of the input luma
t.grad(px)                   // luma gradient
t.centered()                 // (uv - 0.5) * (aspect, 1): circles stay round
t.place(tex, center, height)           // draw a texture (e.g. text) at a spot
t.drawText(base, tex, center, height, color, shadowColor)
```

Free helper functions: `luma`, `rgb2hsv`, `hsv2rgb`, `hash11/12/22/32`, `vnoise`, `fbm`,
`rotate2d`, `over`, `blendScreen/Overlay/SoftLight`, `posterize`, `gauss`, `sdCircle`, `sdBox`,
`sdRoundBox`, `palette`, `glyphAt`, `glyphColorAt`, GLSL-style `mod()` and `atan(y, x)`,
and the constants `PI`, `TAU`.

### Parameters (`INPUTS`)

| TYPE | Control | In the shader |
|---|---|---|
| `float` | slider (`MIN`/`MAX`) | `float t.p.name` |
| `long` | menu/segments (`VALUES` + `LABELS`) or stepper | `int t.p.name` |
| `bool` | checkbox | `bool t.p.name` |
| `event` | button (true for exactly one frame) | `bool t.p.name` |
| `color` | color well, RGBA | `float4 t.p.name` |
| `point2D` | X/Y sliders — or **drag on the preview** | `float2 t.p.name` (0…1, top-left origin) |
| `image` | file picker | texture `t.name`, size in `t.p.name_size` (0 if none) |
| `text` | text field (`FONT`, `FONTSIZE`) | white text rendered to texture `t.name` |
| `source` | pick any camera/screen/pattern | live texture `t.name`, size in `t.p.name_size` |

Text parameters expand live tokens every frame: `{time}`, `{time:HH:mm}`, `{date}`,
`{date:EEEE d MMMM}`, `{elapsed}`, `{countdown:5:00}`, `{until:17:30}`.

### Multipass & feedback (`PASSES`)

```json
"PASSES": [
  { "TARGET": "blurH", "SCALE": 0.5 },
  { "TARGET": "acc", "PERSISTENT": true, "FLOAT": true },
  {}
]
```

Passes run in order; `t.pass` tells you which one you're in. Each `TARGET` becomes a texture
`t.<name>` that later passes can read. **`PERSISTENT`** targets keep their contents between
frames (trails, feedback, cellular automata, freeze frames…) — reading a target while writing it
gives you the previous contents. Options: `FLOAT` (16-bit float), `FLOAT32`, `SCALE` (relative
size), or `WIDTH`/`HEIGHT` expressions like `"$WIDTH/4"` (parameters can be used in expressions).
The last pass is the effect's output.

### Glyphs, images

```json
"GLYPHS": [ { "NAME": "ramp", "CHARS": " .:-=+*#%@", "FONT": "Menlo-Bold", "SIZE": 48 } ],
"IMAGES": [ { "NAME": "logo", "PATH": "logo.png" } ]
```

Glyph atlases are strips of white characters (emoji keep their color: use `glyphColorAt`);
`ramp_COUNT` holds the number of glyphs. See `Stylize/ASCII.metal` and `CamTwist/Matrix.metal`.

### Face tracking & person segmentation

Add `"FACE": true` and/or `"MASK": true` to the header and CamTwizzle runs Apple's Vision
framework on the source:

| Member | Meaning |
|---|---|
| `t.faceCount` | number of faces (0 = none) |
| `t.face` | primary face rect `x, y, w, h` (normalized, top-left) |
| `t.leftEye`, `t.rightEye`, `t.nose`, `t.mouth` | landmark positions (as seen in the picture) |
| `t.faceRoll`, `t.faceYaw` | head rotation in radians |
| `t.mask`, `t.maskAt(uv)` | person segmentation, 1 = person (white everywhere if unavailable) |

See `Face/*.metal` and `Background/*.metal`.

### Tips

* Errors show up in the inspector with file/line numbers. `twizzle check -e MyEffect` compiles
  from the command line; `twizzle render -i photo.jpg -o out.png -e MyEffect` renders a frame.
* Keep sizes resolution-independent: scale pixel radii by `t.inputSize.y / 720.0`.
* Guard `atan2(y, x)` against `(0, 0)` (`x + 1e-6`) — the math mode is relaxed.

---

## 2. Graph effects (`.json`)

The spiritual successor of a Quartz Composer patch: wire Core Image filters together.

```json
{
  "NAME": "Ogre (Classic)",
  "CATEGORIES": ["Distortion"],
  "INPUTS": [ { "NAME": "amount", "TYPE": "float", "DEFAULT": 20, "MIN": 0, "MAX": 60 } ],
  "GRAPH": [
    { "ID": "smooth", "FILTER": "CIMedianFilter",  "INPUTS": { "inputImage": "$input" } },
    { "ID": "edges",  "FILTER": "CIEdgeWork",      "INPUTS": { "inputImage": "@smooth", "inputRadius": 11 }, "CROP": true },
    { "ID": "blur",   "FILTER": "CIGaussianBlur",  "INPUTS": { "inputImage": "@edges", "inputRadius": 20 } },
    { "ID": "out",    "FILTER": "CIDisplacementDistortion",
      "INPUTS": { "inputImage": "$input", "inputDisplacementImage": "@blur", "inputScale": "=amount * 40" } }
  ],
  "OUTPUT": "@out"
}
```

Values:

| Syntax | Meaning |
|---|---|
| `"$input"`, `"$mask"`, `"$prev"` | effect input, segmentation mask, last output of this effect (feedback) |
| `"@node"` | output image of another node |
| `"=expr"` | arithmetic on params and `WIDTH`, `HEIGHT`, `TIME`, `FRAME`, `DT`, `FACECX`, `FACECY`, `FACERADIUS`… (`sin cos abs min max clamp mix smoothstep pow sqrt floor fract mod …`) |
| `"%param"` | a parameter as Core Image wants it: colors → `CIColor`, points → pixel `CIVector`, images → `CIImage`; also `%center`, `%face`, `%extent` |
| `[a, b, "=expr"]` | `CIVector` |
| `{"COLOR": [r,g,b,a]}` | `CIColor` |
| `{"TRANSFORM": {"rotate": 10, "scale": 1.2, "tx": 0}}` | affine transform (about the center) |

Per node: `"CLAMP": true` clamps the output to the edge (good before blurs), `"CROP": true`
crops it to the frame. A node can also run a **shader plugin**:
`{ "ID": "s", "SHADER": "Sobel", "INPUT": "@blur", "PARAMS": { "gain": 2 } }`.

`scripts/gen_ci_filters.py` generates the built-in single-filter graphs; any filter from
`CIFilter.filterNames(inCategory: nil)` works.

---

## 3. Quartz Composer compositions (`.qtz`, legacy)

Drop a `.qtz` into your effects folder and it appears in the browser as "Name (QC)".
Compositions using the **Image Filter** protocol (`_protocolInput_Image` / `_protocolOutput_Image`)
process the picture; any other composition is drawn as a transparent overlay on top (clocks,
text, particles…). Published input ports become parameters. CamTwizzle also looks in
`/Applications/CamTwist/Effects` and `~/Library/Compositions`.

This uses Apple's deprecated QuartzComposer/OpenGL frameworks, which still ship with macOS 26;
some old compositions use Core Image kernels that today's compiler rejects, or CamTwist-only
patches — those render as a passthrough. Every CamTwist effect also has a native port.
