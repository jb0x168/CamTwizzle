#!/bin/bash
# Build CamTwizzle with plain swiftc (works with just the Command Line Tools;
# SwiftPM's Package.swift is kept for IDEs/Xcode users).
#
#   scripts/build.sh            build everything (release) and assemble build/CamTwizzle.app
#   scripts/build.sh core cli   build selected parts
#   CONFIG=debug scripts/build.sh
#
# Signing is handled by scripts/sign.sh (called at the end of a full build).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUILD="$ROOT/build"
CONFIG="${CONFIG:-release}"
TARGET="arm64-apple-macos15.0"
mkdir -p "$BUILD"/{modules,lib,bin,tmp}

# Pick an SDK the installed compiler can actually use (the newest SDK may be built
# by a newer compiler than the one in the Command Line Tools).
pick_sdk() {
  if [[ -n "${SDKROOT:-}" ]]; then echo "$SDKROOT"; return; fi
  if [[ -f "$BUILD/.sdk" ]] && [[ -d "$(cat "$BUILD/.sdk")" ]]; then cat "$BUILD/.sdk"; return; fi
  local probe="$BUILD/tmp/probe.swift"
  echo 'import Foundation; print(1)' > "$probe"
  for sdk in $(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.*.sdk /Applications/Xcode*.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX*.sdk 2>/dev/null | sort -rV); do
    if swiftc -sdk "$sdk" -target "$TARGET" -typecheck "$probe" >/dev/null 2>&1; then
      echo "$sdk" > "$BUILD/.sdk"; echo "$sdk"; return
    fi
  done
  xcrun --show-sdk-path
}
SDK="$(pick_sdk)"

if [[ "$CONFIG" == "debug" ]]; then OPT=(-Onone -g -DDEBUG); else OPT=(-O -wmo); fi
COMMON=(-sdk "$SDK" -target "$TARGET" -swift-version 5 "${OPT[@]}")
FRAMEWORKS=(-framework Metal -framework MetalKit -framework CoreImage -framework CoreMediaIO -framework CoreMedia
            -framework CoreVideo -framework AVFoundation -framework ScreenCaptureKit -framework Vision
            -framework IOSurface -framework AppKit -framework SystemExtensions -framework IOKit -framework Quartz -framework OpenGL -framework ServiceManagement)

newer() { # newer OUT FILES... -> true if OUT missing or any file newer
  local out="$1"; shift
  [[ ! -e "$out" ]] && return 0
  for f in "$@"; do [[ "$f" -nt "$out" ]] && return 0; done
  return 1
}

build_core() {
  local srcs=(); while IFS= read -r f; do srcs+=("$f"); done < <(find Sources/TwizzleCore -name '*.swift' | sort)
  local objc=()
  if [[ -d Sources/Syphon ]]; then objc=(-Xcc -fmodules); fi
  if newer "$BUILD/lib/libTwizzleCore.a" "${srcs[@]}" scripts/build.sh; then
    echo "▸ TwizzleCore (${#srcs[@]} files, $CONFIG)"
    swiftc "${COMMON[@]}" -module-name TwizzleCore -parse-as-library \
      -emit-module -emit-module-path "$BUILD/modules/TwizzleCore.swiftmodule" \
      -emit-library -static -o "$BUILD/lib/libTwizzleCore.a" \
      $( [[ -f "$BUILD/lib/libSyphon.a" ]] && echo "-DHAVE_SYPHON -Xcc -I$ROOT/Sources/Syphon/include -Xcc -fmodule-map-file=$BUILD/modules/SyphonModule/module.modulemap" ) \
      "${srcs[@]}"
  fi
}

build_exe() { # name srcdir [extra flags...]
  local name="$1" dir="$2"; shift 2
  local srcs=(); while IFS= read -r f; do srcs+=("$f"); done < <(find "$dir" -name '*.swift' | sort)
  if newer "$BUILD/bin/$name" "${srcs[@]}" "$BUILD/lib/libTwizzleCore.a" scripts/build.sh; then
    echo "▸ $name"
    local syphon=()
    [[ -f "$BUILD/lib/libSyphon.a" ]] && syphon=(-lSyphon -framework OpenGL -framework IOSurface -DHAVE_SYPHON -Xcc -I$ROOT/Sources/Syphon/include -Xcc -fmodule-map-file=$BUILD/modules/SyphonModule/module.modulemap)
    swiftc "${COMMON[@]}" -module-name "$name" -I "$BUILD/modules" -L "$BUILD/lib" ${@+"$@"} \
      "${srcs[@]}" -o "$BUILD/bin/$name" "${FRAMEWORKS[@]}" ${syphon[@]+"${syphon[@]}"}
  fi
}

build_syphon() {
  [[ -d Sources/Syphon ]] || return 0
  local srcs=(); while IFS= read -r f; do srcs+=("$f"); done < <(find Sources/Syphon -maxdepth 1 \( -name '*.m' -o -name '*.c' \) | sort)
  if newer "$BUILD/lib/libSyphon.a" "${srcs[@]}" scripts/build.sh; then
    echo "▸ Syphon (${#srcs[@]} files)"
    rm -rf "$BUILD/tmp/syphon"; mkdir -p "$BUILD/tmp/syphon"
    for f in "${srcs[@]}"; do
      local arc=(); [[ "$f" == *.m ]] && arc=(-fobjc-arc)
      clang -c ${arc[@]+"${arc[@]}"} -O2 -isysroot "$SDK" -target "$TARGET" -include Sources/Syphon/Syphon_Prefix.pch \
        -I Sources/Syphon/include -I Sources/Syphon -DSYPHON_CORE_SHARE -DGL_SILENCE_DEPRECATION -Wno-deprecated-declarations \
        -o "$BUILD/tmp/syphon/$(basename "${f%.*}").o" "$f"
    done
    rm -f "$BUILD/lib/libSyphon.a"
    libtool -static -o "$BUILD/lib/libSyphon.a" "$BUILD"/tmp/syphon/*.o 2>/dev/null
  fi
  mkdir -p "$BUILD/modules/SyphonModule"
  printf 'module Syphon {\n  header "%s/Sources/Syphon/Syphon.h"\n  export *\n}\n' "$ROOT" > "$BUILD/modules/SyphonModule/module.modulemap"
}

parts=("$@")
[[ ${#parts[@]} -eq 0 ]] && parts=(syphon core cli app camera bundle)
for p in "${parts[@]}"; do
  case "$p" in
    syphon) build_syphon ;;
    core) build_core ;;
    cli) build_syphon; build_core; build_exe twizzle Sources/twizzle -lTwizzleCore ;;
    app) build_syphon; build_core; build_exe CamTwizzle Sources/CamTwizzle -lTwizzleCore -parse-as-library ;;
    camera) build_exe CamTwizzleCamera Sources/CamTwizzleCamera ;;
    bundle) "$ROOT/scripts/bundle.sh" ;;
    *) echo "unknown part $p"; exit 1 ;;
  esac
done
