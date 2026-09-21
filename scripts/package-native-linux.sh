#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${1:-bezel-shim/build}"
DIST_DIR="${2:-dist}"
ARCH="$(uname -m)"
case "$ARCH" in
  amd64) ARCH=x86_64 ;;
  arm64) ARCH=aarch64 ;;
esac
ASSET="bezel-native-linux-${ARCH}"
ROOT="${DIST_DIR}/${ASSET}"
ARCHIVE="${DIST_DIR}/${ASSET}.tar.gz"

rm -rf "$ROOT" "$ARCHIVE"
mkdir -p "$ROOT"

SHIM=""
for candidate in "$BUILD_DIR/libbezel.so.0" "$BUILD_DIR/libbezel.so"; do
  if [[ -e "$candidate" ]]; then SHIM="$candidate"; break; fi
done
if [[ -z "$SHIM" ]]; then
  echo "libbezel was not found in $BUILD_DIR" >&2
  exit 1
fi

cp -L "$SHIM" "$ROOT/libbezel.so.0"
cp -L "$SHIM" "$ROOT/libbezel.so"

if ! command -v patchelf >/dev/null 2>&1; then
  echo "patchelf is required to create a relocatable Linux runtime" >&2
  exit 1
fi

QT_PLUGIN_DIR=""
if command -v qtpaths6 >/dev/null 2>&1; then
  QT_PLUGIN_DIR="$(qtpaths6 --plugin-dir)"
elif command -v qtpaths >/dev/null 2>&1; then
  QT_PLUGIN_DIR="$(qtpaths --plugin-dir)"
fi
if [[ -z "$QT_PLUGIN_DIR" || ! -d "$QT_PLUGIN_DIR" ]]; then
  echo "Qt plugin directory could not be discovered" >&2
  exit 1
fi

for plugin_group in platforms imageformats iconengines platformthemes styles xcbglintegrations; do
  if [[ -d "$QT_PLUGIN_DIR/$plugin_group" ]]; then
    mkdir -p "$ROOT/$plugin_group"
    find "$QT_PLUGIN_DIR/$plugin_group" -maxdepth 1 -type f -name '*.so' -exec cp -L {} "$ROOT/$plugin_group/" \;
  fi
done

copy_qt_deps() {
  local file="$1"
  while IFS= read -r dep; do
    [[ -n "$dep" ]] || continue
    local base
    base="$(basename "$dep")"
    if [[ "$base" == libQt6*.so* && ! -e "$ROOT/$base" ]]; then
      cp -L "$dep" "$ROOT/$base"
    fi
  done < <(ldd "$file" 2>/dev/null | awk '$2 == "=>" && $3 ~ /^\// { print $3 }')
}

# Resolve the Qt dependency closure. A few passes are enough because the Qt
# module graph is shallow, and stopping is harmless once no new files appear.
copy_qt_deps "$ROOT/libbezel.so.0"
for _ in 1 2 3 4; do
  while IFS= read -r file; do copy_qt_deps "$file"; done < <(find "$ROOT" -type f -name '*.so*')
done

# The shim and Qt modules live together at the runtime root. Plugins are one
# directory deeper and therefore use $ORIGIN/.. to resolve those modules.
while IFS= read -r file; do
  patchelf --set-rpath '$ORIGIN' "$file"
done < <(find "$ROOT" -maxdepth 1 -type f -name '*.so*')
while IFS= read -r file; do
  patchelf --set-rpath '$ORIGIN/..' "$file"
done < <(find "$ROOT" -mindepth 2 -type f -name '*.so*')

[[ -e "$ROOT/libQt6Core.so.6" ]] || { echo "Qt6Core missing from runtime" >&2; exit 1; }
[[ -e "$ROOT/libQt6Gui.so.6" ]] || { echo "Qt6Gui missing from runtime" >&2; exit 1; }
[[ -e "$ROOT/libQt6Widgets.so.6" ]] || { echo "Qt6Widgets missing from runtime" >&2; exit 1; }
[[ -e "$ROOT/platforms/libqoffscreen.so" ]] || { echo "offscreen platform plugin missing" >&2; exit 1; }

mkdir -p "$DIST_DIR"
tar -C "$DIST_DIR" -czf "$ARCHIVE" "$ASSET"
echo "$ARCHIVE"
