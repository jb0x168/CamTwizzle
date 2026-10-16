# CamTwizzle

*CamTwist, re-twizzled* — a modern macOS virtual-camera effects box. Pick your sources
(webcams, a screen, a window, Syphon, images, movies, test patterns), stack effects on them,
and every app that uses a camera (Photo Booth, Zoom, FaceTime, Meet, Teams, OBS…) sees the
result.

> **Twizzle** = *twist* + *swizzle* — the shader trick of shuffling vector components
> (`color.bgra`), which is exactly what CamTwizzle does to your video all day.

* **~190 built-in effects** — every CamTwist classic re-done as a Metal shader (Ogre, Sobel,
  Matrix, Flame, On Fire, Comic Book, Bullet Time, Bad TV, Old Movie, TIX clock, Cube, …),
  Apple's Core Image filters (pixellate, kaleidoscope, halftones, twirl, bloom, …) and a pile of
  modern ones: ASCII art, VHS, CRT, Game Boy, glitch, datamosh, pixel sort, slit-scan,
  face-tracked googly eyes / laser eyes / halo / big head / Deal-With-It shades, portrait-mode
  background blur, virtual backgrounds, hologram, synthwave, emoji rain, lower thirds, clocks…
* **Stackable** — effects per source and on the final picture; each processes the previous one's output.
* **Plugin system** — drop a `.metal` shader with a JSON header (ISF-like), a Core Image node
  graph (`.json`, the Quartz Composer successor), or even a legacy `.qtz` composition into
  `~/Library/Application Support/CamTwizzle/Effects`. Edits reload live. See [docs/PLUGINS.md](docs/PLUGINS.md).
* **Sources** — any camera, a whole screen or one window (ScreenCaptureKit), Syphon servers,
  images, looping movies, generators — composited as layers (picture-in-picture, blend modes).
* **Outputs** — a virtual camera device, a Syphon server, or both. Several virtual cameras at once.
* **Face tracking & segmentation** — via Apple's Vision framework, available to every effect.
* **`twizzle` CLI** — render effects offline, contact sheets, run headless, list devices.

## Getting the virtual camera

macOS only lets *signed system extensions* create cameras. CamTwizzle supports two drivers:

1. **OBS Virtual Camera (works without a developer account).** OBS Studio ships a signed camera
   extension that accepts frames from any app. CamTwizzle drives it directly; OBS doesn't need to
   be running. One-time setup:
   * `brew install --cask obs` (or download it), open OBS, click **Start Virtual Camera**;
   * approve it in **System Settings › General › Login Items & Extensions › Camera Extensions**;
   * quit OBS. In CamTwizzle choose **OBS Virtual Camera** as the output (it's picked automatically).
   In other apps the camera is called "OBS Virtual Camera".
2. **CamTwizzle Camera (needs a paid Apple Developer Program team).** The app embeds its own
   CoreMediaIO Camera Extension (two devices, "CamTwizzle" and "CamTwizzle 2", 1080p/720p).
   macOS refuses to load system extensions without the `system-extension.install` entitlement,
   which is only issued to paid teams. To use it:
   * In the developer portal create App IDs `dev.camtwizzle.CamTwizzle` and
     `dev.camtwizzle.CamTwizzle.Camera` (or your own prefix via `BUNDLE_ID=`), enable
     *System Extension* on the app and *App Groups* (`TEAMID.dev.camtwizzle.CamTwizzle`) on both,
     and create **Developer ID** (or development) provisioning profiles for each.
   * Build: `TEAM_ID=ABCDE12345 SIGN_IDENTITY="Developer ID Application: …" APP_PROFILE=app.provisionprofile EXT_PROFILE=ext.provisionprofile scripts/install.sh`
   * Open **Virtual Camera Setup…** and click **Install Camera Extension**; approve it in System Settings.

Either way, the camera only shows CamTwizzle's picture while the app is running (it lives in
the menu bar when the window is closed); otherwise you get a "CamTwizzle — open the app" card
(own extension) or OBS's placeholder.

## Building

Only the Xcode **Command Line Tools** are needed (SwiftPM's `Package.swift` is included for IDEs).

```sh
scripts/build.sh            # builds everything into build/CamTwizzle.app (signed locally)
scripts/install.sh          # build + copy to /Applications (+ twizzle CLI to /usr/local/bin)
CONFIG=debug scripts/build.sh
```

Local builds are signed with a self-signed "CamTwizzle Local Signing" identity kept in
`build/signing.keychain-db`, so camera / screen-recording permissions survive rebuilds.

## Using it

* **Sidebar** — your virtual cameras. Each has its own sources, effects, resolution and output.
* **Sources** — bottom layer first; extra sources start as picture-in-picture. Select one to set
  fit/crop/mirror/position/opacity/blend, or add effects that apply only to it.
* **Effects** — ⌘K opens the browser. Drag to reorder, toggle, ⌫ to remove. Point parameters can
  be dragged directly on the preview.
* **Inspector** — every effect parameter, plus *Customize…* to fork a built-in effect into your
  folder and edit it in your text editor (it reloads as you save).

## The `twizzle` CLI

```sh
twizzle list                                  # all effects
twizzle check                                 # compile everything
twizzle render -i in.jpg -o out.png -e Matrix -e "Old Movie" -p sepia=0.5
twizzle sheet -i in.jpg -o sheet.png          # contact sheet of every effect
twizzle devices                               # cameras and virtual camera sinks
twizzle run --source camera:<id> -e Ogre --device "OBS Virtual Camera"   # headless
```

## Layout

```
Sources/TwizzleCore     engine: Metal renderer, effect runtimes, sources, Vision, CoreMediaIO sink, Syphon
Sources/CamTwizzle      SwiftUI app
Sources/CamTwizzleCamera   CoreMediaIO Camera Extension
Sources/twizzle         command line tool
Sources/Syphon          vendored Syphon framework (BSD)
Filters/                built-in effects
scripts/                build, sign, install, filter generator
```

Credits: CamTwist (Steve Green / allocinit) for the inspiration and the original effect
designs; EffecTV for Matrix/Fire; toneburst and Memo Akten for QC effects; the Syphon project.
