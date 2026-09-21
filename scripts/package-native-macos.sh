#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${1:-bezel-shim/build}"
DIST_DIR="${2:-dist}"
ARCH="$(uname -m)"
case "$ARCH" in
  arm64) ARCH=aarch64 ;;
  amd64) ARCH=x86_64 ;;
esac
ASSET="bezel-native-macosx-${ARCH}"
ROOT="${DIST_DIR}/${ASSET}"
APP="${ROOT}/BezelRuntime.app"
ARCHIVE="${DIST_DIR}/${ASSET}.tar.gz"

rm -rf "$ROOT" "$ARCHIVE"
mkdir -p "$ROOT"

PROBE_APP="${BUILD_DIR}/bezel-deploy-probe.app"
if [[ ! -d "$PROBE_APP" ]]; then
  PROBE_APP="$(find "$BUILD_DIR" -maxdepth 3 -type d -name 'bezel-deploy-probe.app' -print -quit)"
fi
if [[ -z "$PROBE_APP" || ! -d "$PROBE_APP" ]]; then
  echo "bezel-deploy-probe.app was not found in $BUILD_DIR" >&2
  exit 1
fi

ditto "$PROBE_APP" "$APP"

MACDEPLOYQT="$(command -v macdeployqt || true)"
if [[ -z "$MACDEPLOYQT" ]] && command -v brew >/dev/null 2>&1; then
  CANDIDATE="$(brew --prefix qt)/bin/macdeployqt"
  [[ -x "$CANDIDATE" ]] && MACDEPLOYQT="$CANDIDATE"
fi
if [[ -z "$MACDEPLOYQT" ]]; then
  echo "macdeployqt was not found" >&2
  exit 1
fi

"$MACDEPLOYQT" "$APP" -always-overwrite -no-strip

FRAMEWORKS="$APP/Contents/Frameworks"
PLUGINS="$APP/Contents/PlugIns"
MACOS_DIR="$APP/Contents/MacOS"
mkdir -p "$FRAMEWORKS" "$PLUGINS/platforms"

SHIM="$(find "$FRAMEWORKS" -maxdepth 1 -type f -name 'libbezel*.dylib' -print -quit)"
if [[ -z "$SHIM" ]]; then
  BUILD_SHIM="$(find "$BUILD_DIR" -maxdepth 2 -type f -name 'libbezel*.dylib' -print -quit)"
  if [[ -z "$BUILD_SHIM" ]]; then
    echo "libbezel dylib was not found after macdeployqt" >&2
    exit 1
  fi
  cp -L "$BUILD_SHIM" "$FRAMEWORKS/libbezel.0.dylib"
  SHIM="$FRAMEWORKS/libbezel.0.dylib"
fi

# Give the Racket loader a stable ABI-major filename even if the deploy tool
# retained CMake's full VERSION filename.
if [[ ! -e "$FRAMEWORKS/libbezel.0.dylib" ]]; then
  cp -L "$SHIM" "$FRAMEWORKS/libbezel.0.dylib"
fi

# macdeployqt deploys the normal Cocoa backend. Keep the offscreen QPA backend
# too so packaged Bezel also works in CI, render farms, and screenshot tools.
QT_PLUGIN_DIR=""
if command -v qtpaths6 >/dev/null 2>&1; then
  QT_PLUGIN_DIR="$(qtpaths6 --plugin-dir)"
elif command -v qtpaths >/dev/null 2>&1; then
  QT_PLUGIN_DIR="$(qtpaths --plugin-dir)"
elif command -v brew >/dev/null 2>&1; then
  QT_PLUGIN_DIR="$(brew --prefix qt)/share/qt/plugins"
fi
if [[ -n "$QT_PLUGIN_DIR" && -e "$QT_PLUGIN_DIR/platforms/libqoffscreen.dylib" ]]; then
  cp -L "$QT_PLUGIN_DIR/platforms/libqoffscreen.dylib" "$PLUGINS/platforms/"
fi

[[ -d "$PLUGINS/platforms" ]] || { echo "Qt platform plugins missing from app bundle" >&2; exit 1; }
[[ -e "$PLUGINS/platforms/libqcocoa.dylib" ]] || { echo "Cocoa desktop platform plugin missing from app bundle" >&2; exit 1; }
[[ -e "$PLUGINS/platforms/libqoffscreen.dylib" ]] || { echo "offscreen platform plugin missing from app bundle" >&2; exit 1; }
[[ -e "$FRAMEWORKS/libbezel.0.dylib" ]] || { echo "libbezel missing from app bundle" >&2; exit 1; }

# macdeployqt rewrites dependencies for launching the probe as an application,
# which intentionally uses @executable_path. Bezel is different: Racket dlopen's
# libbezel from inside the package, so @executable_path would resolve relative
# to the Racket executable (/Applications/Racket) instead of this runtime.
# Convert bundled-framework dependencies to @rpath and give each Mach-O class a
# loader-relative Frameworks rpath. This makes the same bundle valid both when
# launched as the probe app and when loaded as an SDK from an arbitrary process.
add_rpath_if_missing() {
  local binary="$1"
  local rpath="$2"
  if ! otool -l "$binary" | grep -Fq "path ${rpath} ("; then
    install_name_tool -add_rpath "$rpath" "$binary"
  fi
}

rewrite_macho() {
  local binary="$1"
  local runtime_rpath="$2"

  if ! file "$binary" | grep -q 'Mach-O'; then
    return 0
  fi

  while IFS= read -r dep; do
    case "$dep" in
      @executable_path/../Frameworks/*)
        install_name_tool -change "$dep" "@rpath/${dep#@executable_path/../Frameworks/}" "$binary"
        ;;
    esac
  done < <(otool -L "$binary" | tail -n +2 | sed 's/^[[:space:]]*//' | awk '{print $1}')

  add_rpath_if_missing "$binary" "$runtime_rpath"
}

while IFS= read -r -d '' binary; do
  if [[ "$binary" == "$FRAMEWORKS"/*.framework/Versions/*/* ]]; then
    rewrite_macho "$binary" '@loader_path/../../..'
  else
    rewrite_macho "$binary" '@loader_path'
  fi
done < <(find "$FRAMEWORKS" -type f -print0)

while IFS= read -r -d '' binary; do
  rewrite_macho "$binary" '@loader_path/../../Frameworks'
done < <(find "$PLUGINS" -type f -print0)

while IFS= read -r -d '' binary; do
  rewrite_macho "$binary" '@loader_path/../Frameworks'
done < <(find "$MACOS_DIR" -type f -print0)

# Fail the package build if any deployed Mach-O still requires the application
# executable to locate bundled frameworks. That path is invalid for dlopen SDK
# use and would only be caught later on a clean machine.
while IFS= read -r -d '' binary; do
  if file "$binary" | grep -q 'Mach-O'; then
    if otool -L "$binary" | tail -n +2 | sed 's/^[[:space:]]*//' | awk '{print $1}' | grep -q '^@executable_path/../Frameworks/'; then
      echo "non-relocatable @executable_path dependency remains in $binary" >&2
      otool -L "$binary" >&2
      exit 1
    fi
  fi
done < <(find "$FRAMEWORKS" "$PLUGINS" "$MACOS_DIR" -type f -print0)

# install_name_tool invalidates existing signatures. Ad-hoc sign the SDK bundle
# so Apple-silicon clean runners can load the modified Mach-O files. Final
# applications are still expected to apply their own Developer ID signing and
# notarization policy when they package Bezel.
codesign --force --deep --sign - --timestamp=none "$APP"

mkdir -p "$DIST_DIR"
tar -C "$DIST_DIR" -czf "$ARCHIVE" "$ASSET"
echo "$ARCHIVE"
