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
  install_name_tool -add_rpath '@loader_path' "$SHIM" 2>/dev/null || true
fi

# Give the Racket loader a stable ABI-major filename even if the deploy tool
# retained CMake's full VERSION filename.
if [[ ! -e "$FRAMEWORKS/libbezel.0.dylib" ]]; then
  cp -L "$SHIM" "$FRAMEWORKS/libbezel.0.dylib"
fi

# macdeployqt normally deploys Cocoa only. Keep the offscreen QPA backend too
# so packaged Bezel works in CI, render farms, and screenshot automation.
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
[[ -e "$PLUGINS/platforms/libqoffscreen.dylib" ]] || { echo "offscreen platform plugin missing from app bundle" >&2; exit 1; }
[[ -e "$FRAMEWORKS/libbezel.0.dylib" ]] || { echo "libbezel missing from app bundle" >&2; exit 1; }

mkdir -p "$DIST_DIR"
tar -C "$DIST_DIR" -czf "$ARCHIVE" "$ASSET"
echo "$ARCHIVE"
