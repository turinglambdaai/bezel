#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${1:-bezel-shim/build}"
DIST_DIR="${2:-dist}"
COMPLIANCE_DIR="${3:-dist/compliance/runtime-licenses}"
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

[[ -d "$COMPLIANCE_DIR" ]] || {
  echo "license compliance material is missing: $COMPLIANCE_DIR" >&2
  exit 1
}

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
if [[ -z "$MACDEPLOYQT" ]]; then
  echo "macdeployqt was not found" >&2
  exit 1
fi
"$MACDEPLOYQT" "$APP" -always-overwrite -no-strip

FRAMEWORKS="$APP/Contents/Frameworks"
PLUGINS="$APP/Contents/PlugIns"
MACOS_DIR="$APP/Contents/MacOS"
mkdir -p "$FRAMEWORKS" "$PLUGINS/platforms"
cp -R "$COMPLIANCE_DIR" "$ROOT/LICENSES"

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
if [[ ! -e "$FRAMEWORKS/libbezel.0.dylib" ]]; then
  cp -L "$SHIM" "$FRAMEWORKS/libbezel.0.dylib"
fi

QT_PLUGIN_DIR=""
if command -v qtpaths6 >/dev/null 2>&1; then
  QT_PLUGIN_DIR="$(qtpaths6 --plugin-dir 2>/dev/null || true)"
elif command -v qtpaths >/dev/null 2>&1; then
  QT_PLUGIN_DIR="$(qtpaths --plugin-dir 2>/dev/null || true)"
elif command -v qmake6 >/dev/null 2>&1; then
  QT_PLUGIN_DIR="$(qmake6 -query QT_INSTALL_PLUGINS 2>/dev/null || true)"
fi
if [[ -n "$QT_PLUGIN_DIR" && -e "$QT_PLUGIN_DIR/platforms/libqoffscreen.dylib" ]]; then
  cp -L "$QT_PLUGIN_DIR/platforms/libqoffscreen.dylib" "$PLUGINS/platforms/"
fi

[[ -e "$PLUGINS/platforms/libqcocoa.dylib" ]] || { echo "Cocoa desktop platform plugin missing" >&2; exit 1; }
[[ -e "$PLUGINS/platforms/libqoffscreen.dylib" ]] || { echo "offscreen platform plugin missing" >&2; exit 1; }
[[ -e "$FRAMEWORKS/libbezel.0.dylib" ]] || { echo "libbezel missing" >&2; exit 1; }
[[ -e "$ROOT/LICENSES/NOTICE.md" ]] || { echo "runtime license notice missing" >&2; exit 1; }

# Public release bundles are intentionally limited to Bezel + Qt. Reject an
# unrelated framework/dylib silently introduced by deployment tooling.
while IFS= read -r entry; do
  base="$(basename "$entry")"
  case "$base" in
    Qt*.framework|libbezel*.dylib) ;;
    *)
      echo "unexpected non-Qt framework/runtime in public bundle: $base" >&2
      exit 1 ;;
  esac
done < <(find "$FRAMEWORKS" -mindepth 1 -maxdepth 1 \( -type d -name '*.framework' -o -type f -name '*.dylib' \) -print)

if ! otool -L "$FRAMEWORKS/libbezel.0.dylib" | grep -q 'QtWidgets.framework'; then
  echo "libbezel is not dynamically linked to QtWidgets as required by LGPL release policy" >&2
  exit 1
fi

add_rpath_if_missing() {
  local binary="$1"
  local rpath="$2"
  if ! otool -l "$binary" | grep -Fq "path ${rpath} ("; then
    install_name_tool -add_rpath "$rpath" "$binary"
  fi
}

normalize_install_id() {
  local binary="$1"
  local desired="$2"
  local current=""
  current="$(otool -D "$binary" 2>/dev/null | tail -n +2 | head -n 1 || true)"
  if [[ -n "$current" && "$current" != "$desired" ]]; then
    install_name_tool -id "$desired" "$binary"
  fi
}

rewrite_macho() {
  local binary="$1"
  local runtime_rpath="$2"
  if ! file "$binary" | grep -q 'Mach-O'; then return 0; fi
  while IFS= read -r dep; do
    case "$dep" in
      @executable_path/../Frameworks/*)
        install_name_tool -change "$dep" "@rpath/${dep#@executable_path/../Frameworks/}" "$binary" ;;
    esac
  done < <(otool -L "$binary" | tail -n +2 | sed 's/^[[:space:]]*//' | awk '{print $1}')
  add_rpath_if_missing "$binary" "$runtime_rpath"
}

while IFS= read -r -d '' binary; do
  if [[ "$binary" == "$FRAMEWORKS"/*.framework/Versions/*/* ]]; then
    rewrite_macho "$binary" '@loader_path/../../..'
    normalize_install_id "$binary" "@rpath/${binary#${FRAMEWORKS}/}"
  else
    rewrite_macho "$binary" '@loader_path'
    normalize_install_id "$binary" "@rpath/$(basename "$binary")"
  fi
done < <(find "$FRAMEWORKS" -type f -print0)

while IFS= read -r -d '' binary; do
  rewrite_macho "$binary" '@loader_path/../../Frameworks'
done < <(find "$PLUGINS" -type f -print0)
while IFS= read -r -d '' binary; do
  rewrite_macho "$binary" '@loader_path/../Frameworks'
done < <(find "$MACOS_DIR" -type f -print0)

while IFS= read -r -d '' binary; do
  if file "$binary" | grep -q 'Mach-O'; then
    if otool -L "$binary" | tail -n +2 | sed 's/^[[:space:]]*//' | awk '{print $1}' | grep -q '^@executable_path/../Frameworks/'; then
      echo "non-relocatable @executable_path dependency remains in $binary" >&2
      otool -L "$binary" >&2
      exit 1
    fi
  fi
done < <(find "$FRAMEWORKS" "$PLUGINS" "$MACOS_DIR" -type f -print0)

# install_name_tool invalidates signatures. Ad-hoc sign the SDK bundle so local
# modified/relinked Qt builds remain loadable. Final applications still apply
# their own Developer ID/notarization policy subject to LGPL user rights.
codesign --force --deep --sign - --timestamp=none "$APP"

mkdir -p "$DIST_DIR"
tar -C "$DIST_DIR" -czf "$ARCHIVE" "$ASSET"
echo "$ARCHIVE"
