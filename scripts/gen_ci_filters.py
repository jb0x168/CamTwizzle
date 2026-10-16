#!/usr/bin/env python3
"""Generate CamTwizzle graph plugins wrapping classic Core Image filters.

Each entry becomes Filters/<Category>/<ID>.json. Edit the table and re-run;
hand-written graphs live elsewhere and are not touched.
"""
import json
import os

ROOT = os.path.join(os.path.dirname(__file__), "..", "Filters")


def f(name, minv, maxv, default, label=None):
    return {"NAME": name, "LABEL": label or name.capitalize(), "TYPE": "float", "DEFAULT": default, "MIN": minv, "MAX": maxv}


def pt(name, default=(0.5, 0.5), label=None):
    return {"NAME": name, "LABEL": label or name.capitalize(), "TYPE": "point2D", "DEFAULT": list(default)}


def col(name, default, label=None):
    return {"NAME": name, "LABEL": label or name.capitalize(), "TYPE": "color", "DEFAULT": list(default)}


CENTER = pt("center", label="Center")
# (id, name, category, description, filter, inputs, params, clamp_input, post)
FILTERS = [
    # ---- Stylize
    ("Pixellate", "Pixellate", "Stylize", "Big square pixels (CIPixellate).", "CIPixellate",
     {"inputCenter": "%center", "inputScale": "=scale * HEIGHT / 100"}, [f("scale", 0.5, 15, 3, "Pixel Size %"), CENTER], False),
    ("HexPixellate", "Hexagonal Pixellate", "Stylize", "Hexagonal tiles (CIHexagonalPixellate).", "CIHexagonalPixellate",
     {"inputCenter": "%center", "inputScale": "=scale * HEIGHT / 100"}, [f("scale", 0.5, 15, 3, "Cell Size %"), CENTER], False),
    ("Crystallize", "Crystallize", "Stylize", "Polygonal crystal cells (CICrystallize).", "CICrystallize",
     {"inputCenter": "%center", "inputRadius": "=radius * HEIGHT / 100"}, [f("radius", 0.5, 10, 2.5, "Cell Size %"), CENTER], False),
    ("Pointillize", "Pointillize", "Stylize", "Seurat-style dots (CIPointillize).", "CIPointillize",
     {"inputCenter": "%center", "inputRadius": "=radius * HEIGHT / 100"}, [f("radius", 0.3, 5, 1.2, "Dot Size %"), CENTER], False),
    ("ComicEffect", "Comic", "Stylize", "Core Image's comic book effect (CIComicEffect).", "CIComicEffect", {}, [], False),
    ("Bloom", "Bloom", "Stylize", "Dreamy glow around bright areas (CIBloom).", "CIBloom",
     {"inputRadius": "=radius * HEIGHT / 100", "inputIntensity": "=intensity"}, [f("radius", 0, 10, 2), f("intensity", 0, 2, 0.8)], True),
    ("Gloom", "Gloom", "Stylize", "Moody, dulled highlights (CIGloom).", "CIGloom",
     {"inputRadius": "=radius * HEIGHT / 100", "inputIntensity": "=intensity"}, [f("radius", 0, 10, 2), f("intensity", 0, 2, 0.8)], True),
    ("Posterize", "Posterize", "Color", "Reduce the number of color levels (CIColorPosterize).", "CIColorPosterize",
     {"inputLevels": "=levels"}, [f("levels", 2, 16, 5, "Levels")], False),
    ("Kaleidoscope", "Kaleidoscope", "Geometry", "Classic mirror kaleidoscope (CIKaleidoscope).", "CIKaleidoscope",
     {"inputCenter": "%center", "inputCount": "=count", "inputAngle": "=angle * PI / 180 + TIME * spin"},
     [f("count", 2, 16, 6, "Segments"), f("angle", 0, 360, 0, "Angle"), f("spin", -1, 1, 0.1, "Spin"), CENTER], True),
    ("TriangleKaleidoscope", "Triangle Kaleidoscope", "Geometry", "Triangular mirror tiles (CITriangleKaleidoscope).", "CITriangleKaleidoscope",
     {"inputPoint": "%center", "inputSize": "=size * HEIGHT / 100", "inputRotation": "=rotation * PI / 180 + TIME * spin", "inputDecay": "=decay"},
     [f("size", 5, 100, 40, "Size %"), f("rotation", 0, 360, 0), f("spin", -1, 1, 0.2), f("decay", 0, 1, 0.85), CENTER], True),
    ("Vignette", "Vignette", "Color", "Darkened corners (CIVignetteEffect).", "CIVignetteEffect",
     {"inputCenter": "%center", "inputRadius": "=radius * HEIGHT", "inputIntensity": "=intensity", "inputFalloff": "=falloff"},
     [CENTER, f("radius", 0.2, 1.5, 0.7), f("intensity", 0, 1, 0.9), f("falloff", 0, 1, 0.5)], False),
    ("Sharpen", "Sharpen", "Blur", "Crisper details (CISharpenLuminance).", "CISharpenLuminance",
     {"inputSharpness": "=sharpness", "inputRadius": "=radius"}, [f("sharpness", 0, 2, 0.6), f("radius", 0, 10, 1.7)], True),
    ("UnsharpMask", "Unsharp Mask", "Blur", "Classic unsharp-mask sharpening (CIUnsharpMask).", "CIUnsharpMask",
     {"inputRadius": "=radius", "inputIntensity": "=intensity"}, [f("radius", 0, 20, 2.5), f("intensity", 0, 2, 0.5)], True),
    ("HighlightShadow", "Highlights & Shadows", "Color", "Recover shadows and tame highlights (CIHighlightShadowAdjust).", "CIHighlightShadowAdjust",
     {"inputShadowAmount": "=shadows", "inputHighlightAmount": "=highlights", "inputRadius": "=radius"},
     [f("shadows", -1, 1, 0.4, "Shadows"), f("highlights", 0, 1, 0.8, "Highlights"), f("radius", 0, 10, 2)], True),
    ("Dither", "Dither", "Retro", "Adds dither noise (CIDither).", "CIDither", {"inputIntensity": "=intensity"}, [f("intensity", 0, 5, 1)], False),
    # ---- Halftone
    ("DotScreen", "Dot Screen", "Halftone", "Newspaper dot halftone (CIDotScreen).", "CIDotScreen",
     {"inputCenter": "%center", "inputAngle": "=angle * PI / 180", "inputWidth": "=width * HEIGHT / 100", "inputSharpness": "=sharpness"},
     [CENTER, f("angle", 0, 180, 45), f("width", 0.3, 5, 1.0, "Width %"), f("sharpness", 0, 1, 0.7)], False),
    ("LineScreen", "Line Screen", "Halftone", "Engraved line halftone (CILineScreen).", "CILineScreen",
     {"inputCenter": "%center", "inputAngle": "=angle * PI / 180", "inputWidth": "=width * HEIGHT / 100", "inputSharpness": "=sharpness"},
     [CENTER, f("angle", 0, 180, 30), f("width", 0.3, 5, 0.8, "Width %"), f("sharpness", 0, 1, 0.7)], False),
    ("HatchedScreen", "Hatched Screen", "Halftone", "Cross-hatched halftone (CIHatchedScreen).", "CIHatchedScreen",
     {"inputCenter": "%center", "inputAngle": "=angle * PI / 180", "inputWidth": "=width * HEIGHT / 100", "inputSharpness": "=sharpness"},
     [CENTER, f("angle", 0, 180, 0), f("width", 0.3, 5, 0.8, "Width %"), f("sharpness", 0, 1, 0.7)], False),
    ("CircularScreen", "Circular Screen", "Halftone", "Concentric-ring halftone (CICircularScreen).", "CICircularScreen",
     {"inputCenter": "%center", "inputWidth": "=width * HEIGHT / 100", "inputSharpness": "=sharpness"},
     [CENTER, f("width", 0.3, 5, 0.8, "Width %"), f("sharpness", 0, 1, 0.7)], False),
    ("CMYKHalftone", "CMYK Halftone", "Halftone", "Four-color print halftone (CICMYKHalftone).", "CICMYKHalftone",
     {"inputCenter": "%center", "inputAngle": "=angle * PI / 180", "inputWidth": "=width * HEIGHT / 100", "inputSharpness": "=sharpness",
      "inputGCR": "=gcr", "inputUCR": "=ucr"},
     [CENTER, f("angle", 0, 180, 0), f("width", 0.3, 5, 0.9, "Dot Width %"), f("sharpness", 0, 1, 0.7), f("gcr", 0, 1, 1, "Gray Removal"), f("ucr", 0, 1, 0.5, "Under-color Removal")], False),
    # ---- Distortion
    ("Twirl", "Twirl", "Distortion", "Swirl the picture around a point (CITwirlDistortion).", "CITwirlDistortion",
     {"inputCenter": "%center", "inputRadius": "=radius * HEIGHT", "inputAngle": "=angle * PI / 180 + sin(TIME * wobble) * 2"},
     [CENTER, f("radius", 0.05, 1.5, 0.45), f("angle", -720, 720, 200), f("wobble", 0, 3, 0, "Wobble Speed")], True),
    ("VortexDistortion", "Whirlpool", "Distortion", "Deep rotational vortex (CIVortexDistortion).", "CIVortexDistortion",
     {"inputCenter": "%center", "inputRadius": "=radius * HEIGHT", "inputAngle": "=angle"},
     [CENTER, f("radius", 0.05, 1.5, 0.5), f("angle", -2000, 2000, 560)], True),
    ("Pinch", "Pinch", "Distortion", "Pinch towards a point (CIPinchDistortion).", "CIPinchDistortion",
     {"inputCenter": "%center", "inputRadius": "=radius * HEIGHT", "inputScale": "=scale"},
     [CENTER, f("radius", 0.05, 1.5, 0.5), f("scale", 0, 2, 0.6)], True),
    ("Hole", "Hole", "Distortion", "Punch a hole that pushes the picture outward (CIHoleDistortion).", "CIHoleDistortion",
     {"inputCenter": "%center", "inputRadius": "=radius * HEIGHT"}, [CENTER, f("radius", 0.01, 0.5, 0.12)], True),
    ("CircleSplash", "Circle Splash", "Distortion", "Streaks radiating out of a circle (CICircleSplashDistortion).", "CICircleSplashDistortion",
     {"inputCenter": "%center", "inputRadius": "=radius * HEIGHT"}, [CENTER, f("radius", 0.05, 1, 0.3)], True),
    ("GlassLozenge", "Glass Lozenge", "Distortion", "A lozenge of thick glass (CIGlassLozenge).", "CIGlassLozenge",
     {"inputPoint0": "%point0", "inputPoint1": "%point1", "inputRadius": "=radius * HEIGHT", "inputRefraction": "=refraction"},
     [pt("point0", (0.35, 0.5), "Start"), pt("point1", (0.65, 0.5), "End"), f("radius", 0.05, 0.6, 0.18), f("refraction", 0, 5, 1.7)], True),
    ("TorusLens", "Torus Lens", "Distortion", "A ring-shaped lens (CITorusLensDistortion).", "CITorusLensDistortion",
     {"inputCenter": "%center", "inputRadius": "=radius * HEIGHT", "inputWidth": "=width * HEIGHT", "inputRefraction": "=refraction"},
     [CENTER, f("radius", 0.05, 1, 0.3), f("width", 0.01, 0.5, 0.12), f("refraction", 0, 5, 1.7)], True),
    ("LightTunnel", "Light Tunnel", "Distortion", "Spiralling light tunnel (CILightTunnel).", "CILightTunnel",
     {"inputCenter": "%center", "inputRotation": "=rotation + TIME * spin", "inputRadius": "=radius * HEIGHT"},
     [CENTER, f("rotation", -6.28, 6.28, 0), f("radius", 0.01, 1, 0.2), f("spin", -2, 2, 0.5)], True),
    ("Droste", "Droste", "Distortion", "Escher-style recursive spiral (CIDroste).", "CIDroste",
     {"inputInsetPoint0": "%inset0", "inputInsetPoint1": "%inset1", "inputStrands": "=strands", "inputPeriodicity": "=periodicity",
      "inputRotation": "=rotation", "inputZoom": "=zoom * exp(fract(TIME * speed) * 2)"},
     [pt("inset0", (0.25, 0.75), "Inset Bottom-Left"), pt("inset1", (0.75, 0.25), "Inset Top-Right"), f("strands", -3, 3, 1),
      f("periodicity", 1, 5, 1), f("rotation", 0, 6.28, 0), f("zoom", 0.1, 4, 1), f("speed", 0, 1, 0.15, "Zoom Speed")], False),
    # ---- Color
    ("Sepia", "Sepia", "Color", "Old-photo brown tone (CISepiaTone).", "CISepiaTone", {"inputIntensity": "=intensity"}, [f("intensity", 0, 1, 1)], False),
    ("Invert", "Invert", "Color", "Negative image (CIColorInvert).", "CIColorInvert", {}, [], False),
    ("FalseColor", "False Color", "Color", "Map dark/bright to two colors (CIFalseColor).", "CIFalseColor",
     {"inputColor0": "%dark", "inputColor1": "%bright"}, [col("dark", (0.1, 0.0, 0.35, 1), "Dark Color"), col("bright", (1.0, 0.8, 0.2, 1), "Bright Color")], False),
    ("Thermal", "Thermal", "Color", "Heat-camera palette (CIThermal).", "CIThermal", {}, [], False),
    ("XRay", "X-Ray", "Color", "X-ray look (CIXRay).", "CIXRay", {}, [], False),
    ("Chrome", "Chrome", "Photo", "Photo effect: Chrome.", "CIPhotoEffectChrome", {}, [], False),
    ("Fade", "Fade", "Photo", "Photo effect: Fade.", "CIPhotoEffectFade", {}, [], False),
    ("Instant", "Instant", "Photo", "Photo effect: Instant (Polaroid-ish).", "CIPhotoEffectInstant", {}, [], False),
    ("Mono", "Mono", "Photo", "Photo effect: Mono.", "CIPhotoEffectMono", {}, [], False),
    ("Noir", "Noir", "Photo", "Photo effect: Noir.", "CIPhotoEffectNoir", {}, [], False),
    ("Process", "Process", "Photo", "Photo effect: Process.", "CIPhotoEffectProcess", {}, [], False),
    ("Tonal", "Tonal", "Photo", "Photo effect: Tonal.", "CIPhotoEffectTonal", {}, [], False),
    ("Transfer", "Transfer", "Photo", "Photo effect: Transfer.", "CIPhotoEffectTransfer", {}, [], False),
    ("Vibrance", "Vibrance", "Color", "Boost muted colors without overdoing skin tones (CIVibrance).", "CIVibrance",
     {"inputAmount": "=amount"}, [f("amount", -1, 1, 0.6)], False),
    ("HueAdjust", "Hue Shift", "Color", "Rotate all hues (CIHueAdjust); optional cycling.", "CIHueAdjust",
     {"inputAngle": "=angle * PI / 180 + TIME * cycle"}, [f("angle", -180, 180, 90), f("cycle", 0, 3, 0, "Cycle Speed")], False),
    ("Exposure", "Exposure", "Color", "Exposure compensation in EV (CIExposureAdjust).", "CIExposureAdjust", {"inputEV": "=ev"}, [f("ev", -3, 3, 0.7, "EV")], False),
    ("Gamma", "Gamma", "Color", "Gamma curve (CIGammaAdjust).", "CIGammaAdjust", {"inputPower": "=power"}, [f("power", 0.25, 3, 0.75)], False),
    ("WhiteBalance", "White Balance", "Color", "Warm up or cool down the picture (CITemperatureAndTint).", "CITemperatureAndTint",
     {"inputNeutral": [6500, 0], "inputTargetNeutral": ["=temperature", "=tint"]}, [f("temperature", 2500, 12000, 5500, "Temperature K"), f("tint", -100, 100, 0)], False),
    # ---- Blur
    ("GaussianBlur", "Gaussian Blur", "Blur", "Soft blur (CIGaussianBlur).", "CIGaussianBlur", {"inputRadius": "=radius * HEIGHT / 100"}, [f("radius", 0, 10, 1.5, "Radius %")], True),
    ("BoxBlur", "Box Blur", "Blur", "Box blur (CIBoxBlur).", "CIBoxBlur", {"inputRadius": "=radius * HEIGHT / 100"}, [f("radius", 0, 10, 1.5, "Radius %")], True),
    ("DiscBlur", "Disc Blur", "Blur", "Lens-like disc blur (CIDiscBlur).", "CIDiscBlur", {"inputRadius": "=radius * HEIGHT / 100"}, [f("radius", 0, 10, 1.5, "Radius %")], True),
    ("MotionBlur", "Motion Blur", "Blur", "Directional smear (CIMotionBlur).", "CIMotionBlur",
     {"inputRadius": "=radius * HEIGHT / 100", "inputAngle": "=angle * PI / 180"}, [f("radius", 0, 15, 3, "Length %"), f("angle", 0, 180, 0)], True),
    ("ZoomBlur", "Zoom Blur", "Blur", "Rushing-forward radial blur (CIZoomBlur).", "CIZoomBlur",
     {"inputCenter": "%center", "inputAmount": "=amount * HEIGHT / 100"}, [CENTER, f("amount", 0, 20, 4, "Amount %")], True),
    ("Median", "Median", "Blur", "Removes speckles while keeping edges (CIMedianFilter).", "CIMedianFilter", {}, [], True),
    ("Bokeh", "Bokeh", "Blur", "Out-of-focus highlights become rings (CIBokehBlur).", "CIBokehBlur",
     {"inputRadius": "=radius * HEIGHT / 100", "inputRingAmount": "=ring", "inputRingSize": "=ringSize", "inputSoftness": "=softness"},
     [f("radius", 0, 6, 2, "Radius %"), f("ring", 0, 1, 0.3, "Ring Amount"), f("ringSize", 0, 0.2, 0.1, "Ring Size"), f("softness", 0, 10, 1)], True),
    # ---- Tiles
    ("OpTile", "Op Art Tile", "Tiles", "Op-art segmentation and tiling (CIOpTile).", "CIOpTile",
     {"inputCenter": "%center", "inputScale": "=scale", "inputAngle": "=angle * PI / 180", "inputWidth": "=width * HEIGHT / 100"},
     [CENTER, f("scale", 0.1, 10, 2.8), f("angle", 0, 360, 0), f("width", 2, 50, 12, "Width %")], False),
    ("EightfoldTile", "Eightfold Tile", "Tiles", "Eight-way reflected tiling (CIEightfoldReflectedTile).", "CIEightfoldReflectedTile",
     {"inputCenter": "%center", "inputAngle": "=angle * PI / 180 + TIME * spin", "inputWidth": "=width * HEIGHT / 100"},
     [CENTER, f("angle", 0, 360, 0), f("width", 5, 100, 30, "Tile Size %"), f("spin", -1, 1, 0.0)], False),
    ("SixfoldTile", "Sixfold Rotated Tile", "Tiles", "Six-way rotated tiling (CISixfoldRotatedTile).", "CISixfoldRotatedTile",
     {"inputCenter": "%center", "inputAngle": "=angle * PI / 180 + TIME * spin", "inputWidth": "=width * HEIGHT / 100"},
     [CENTER, f("angle", 0, 360, 0), f("width", 5, 100, 30, "Tile Size %"), f("spin", -1, 1, 0.0)], False),
    ("TriangleTile", "Triangle Tile", "Tiles", "Triangular tiling (CITriangleTile).", "CITriangleTile",
     {"inputCenter": "%center", "inputAngle": "=angle * PI / 180 + TIME * spin", "inputWidth": "=width * HEIGHT / 100"},
     [CENTER, f("angle", 0, 360, 0), f("width", 5, 100, 30, "Tile Size %"), f("spin", -1, 1, 0.0)], False),
    ("GlideTile", "Glide Reflected Tile", "Tiles", "Glide-reflection tiling (CIGlideReflectedTile).", "CIGlideReflectedTile",
     {"inputCenter": "%center", "inputAngle": "=angle * PI / 180", "inputWidth": "=width * HEIGHT / 100"},
     [CENTER, f("angle", 0, 360, 0), f("width", 5, 100, 30, "Tile Size %")], False),
]


def main():
    count = 0
    for (fid, name, cat, desc, filt, inputs, params, clamp) in FILTERS:
        graph = []
        src = "$input"
        if clamp:
            graph.append({"ID": "clamped", "FILTER": "CIAffineClamp", "INPUTS": {"inputImage": "$input", "inputTransform": {"TRANSFORM": {}}}})
            src = "@clamped"
        node_inputs = {"inputImage": src}
        node_inputs.update(inputs)
        graph.append({"ID": "fx", "FILTER": filt, "INPUTS": node_inputs})
        doc = {
            "NAME": name,
            "CATEGORIES": [cat, "Core Image"],
            "DESCRIPTION": desc,
            "INPUTS": params,
            "GRAPH": graph,
            "OUTPUT": "@fx",
        }
        d = os.path.join(ROOT, cat)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, fid + ".json"), "w") as fh:
            json.dump(doc, fh, indent=2, ensure_ascii=False)
            fh.write("\n")
        count += 1
    print(f"wrote {count} Core Image graph plugins")


if __name__ == "__main__":
    main()
