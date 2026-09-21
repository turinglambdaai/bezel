#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${1:-bezel-shim/build}"
DIST_DIR="${2:-dist}"
COMPLIANCE_DIR="${3:-dist/compliance/runtime-licenses}"
ARCH="$(uname -m)"
case "$ARCH" in
  amd64) ARCH=x86_64 ;;
  arm64) ARCH=aarch64 ;;
esac
ASSET="bezel-native-linux-${ARCH}"
ROOT="${DIST_DIR}/${ASSET}"
ARCHIVE="${DIST_DIR}/${ASSET}.tar.gz"

rm -rf "$ROOT" "$ARCHIVE"
mkdir -p "$ROOT/platforms" "$ROOT/imageformats"

[[ -d "$COMPLIANCE_DIR" ]] || {
  echo "license compliance material is missing: $COMPLIANCE_DIR" >&2
  exit 1
}

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
cp -R "$COMPLIANCE_DIR" "$ROOT/LICENSES"

if ! command -v patchelf >/dev/null 2>&1; then
  echo "patchelf is required to create a relocatable Linux runtime" >&2
  exit 1
fi

QT_PLUGIN_DIR=""
QT_PREFIX=""
if command -v qmake6 >/dev/null 2>&1; then
  QT_PLUGIN_DIR="$(qmake6 -query QT_INSTALL_PLUGINS 2>/dev/null || true)"
  QT_PREFIX="$(qmake6 -query QT_INSTALL_PREFIX 2>/dev/null || true)"
fi
if [[ -z "$QT_PLUGIN_DIR" ]] && command -v qmake >/dev/null 2>&1; then
  QT_PLUGIN_DIR="$(qmake -query QT_INSTALL_PLUGINS 2>/dev/null || true)"
  QT_PREFIX="$(qmake -query QT_INSTALL_PREFIX 2>/dev/null || true)"
fi
if [[ -z "$QT_PLUGIN_DIR" ]] && command -v qtpaths6 >/dev/null 2>&1; then
  QT_PLUGIN_DIR="$(qtpaths6 --plugin-dir 2>/dev/null || true)"
fi
if [[ -z "$QT_PREFIX" ]] && command -v qtpaths6 >/dev/null 2>&1; then
  QT_PREFIX="$(qtpaths6 --install-prefix 2>/dev/null || true)"
fi
if [[ -z "$QT_PLUGIN_DIR" || ! -d "$QT_PLUGIN_DIR" ]]; then
  echo "Qt 6 plugin directory could not be discovered" >&2
  exit 1
fi
if [[ -z "$QT_PREFIX" || ! -d "$QT_PREFIX" ]]; then
  # Plugins are normally <prefix>/plugins. This fallback is still constrained
  # to that exact Qt installation instead of accepting arbitrary host libraries.
  QT_PREFIX="$(cd "$QT_PLUGIN_DIR/.." && pwd -P)"
fi
QT_PREFIX="$(cd "$QT_PREFIX" && pwd -P)"
echo "Qt prefix: $QT_PREFIX"
echo "Qt plugin directory: $QT_PLUGIN_DIR"

for plugin in libqxcb.so libqoffscreen.so; do
  [[ -e "$QT_PLUGIN_DIR/platforms/$plugin" ]] || {
    echo "required Qt platform plugin missing: $plugin" >&2
    exit 1
  }
  cp -L "$QT_PLUGIN_DIR/platforms/$plugin" "$ROOT/platforms/"
done
for plugin in libqgif.so libqico.so libqjpeg.so; do
  if [[ -e "$QT_PLUGIN_DIR/imageformats/$plugin" ]]; then
    cp -L "$QT_PLUGIN_DIR/imageformats/$plugin" "$ROOT/imageformats/"
  fi
done

# Public Bezel archives redistribute Bezel + Qt only. Do not recursively copy
# arbitrary host/system libraries: doing that silently expands the license set
# of the product. Instead copy a dependency only when its resolved path belongs
# to the exact Qt installation selected above. All other libraries remain OS
# prerequisites and are recorded for diagnostics.
SYSTEM_DEPS="$ROOT/SYSTEM-DEPENDENCIES.txt"
: > "$SYSTEM_DEPS"

after_prefix() {
  local path="$1"
  [[ "$path" == "$QT_PREFIX"/* ]]
}

scan_and_copy_qt_deps() {
  local file="$1"
  while IFS= read -r dep; do
    [[ -n "$dep" && -e "$dep" ]] || continue
    local resolved base
    resolved="$(readlink -f "$dep")"
    base="$(basename "$dep")"
    if after_prefix "$resolved"; then
      if [[ ! -e "$ROOT/$base" ]]; then
        cp -L "$dep" "$ROOT/$base"
      fi
    else
      printf '%s\t%s\n' "$base" "$resolved" >> "$SYSTEM_DEPS"
    fi
  done < <(ldd "$file" 2>/dev/null | awk '$2 == "=>" && $3 ~ /^\// { print $3 }')
}

for _ in 1 2 3 4 5 6 7 8; do
  before="$(find "$ROOT" -maxdepth 1 -type f -name '*.so*' | wc -l)"
  while IFS= read -r file; do
    scan_and_copy_qt_deps "$file"
  done < <(find "$ROOT" -type f -name '*.so*' -print)
  after="$(find "$ROOT" -maxdepth 1 -type f -name '*.so*' | wc -l)"
  [[ "$before" == "$after" ]] && break
done
sort -u -o "$SYSTEM_DEPS" "$SYSTEM_DEPS"

# Refuse accidental redistribution of a non-Qt shared object at the bundle
# root. The only exception is Bezel itself.
while IFS= read -r file; do
  base="$(basename "$file")"
  case "$base" in
    libbezel.so|libbezel.so.0|libQt6*.so*) ;;
    *)
      echo "unexpected non-Qt shared library in public bundle: $base" >&2
      exit 1 ;;
  esac
done < <(find "$ROOT" -maxdepth 1 -type f -name '*.so*' -print)

while IFS= read -r file; do
  patchelf --set-rpath '$ORIGIN' "$file"
done < <(find "$ROOT" -maxdepth 1 -type f -name '*.so*' -print)
while IFS= read -r file; do
  patchelf --set-rpath '$ORIGIN/..' "$file"
done < <(find "$ROOT" -mindepth 2 -type f -name '*.so*' -print)

[[ -e "$ROOT/libQt6Core.so.6" ]] || { echo "Qt6Core missing from runtime" >&2; exit 1; }
[[ -e "$ROOT/libQt6Gui.so.6" ]] || { echo "Qt6Gui missing from runtime" >&2; exit 1; }
[[ -e "$ROOT/libQt6Widgets.so.6" ]] || { echo "Qt6Widgets missing from runtime" >&2; exit 1; }
[[ -e "$ROOT/platforms/libqoffscreen.so" ]] || { echo "offscreen platform plugin missing" >&2; exit 1; }
[[ -e "$ROOT/platforms/libqxcb.so" ]] || { echo "X11/xcb desktop platform plugin missing" >&2; exit 1; }
[[ -e "$ROOT/LICENSES/NOTICE.md" ]] || { echo "runtime license notice missing" >&2; exit 1; }

if ! readelf -d "$ROOT/libbezel.so.0" | grep -q 'Shared library: \[libQt6Widgets.so.6\]'; then
  echo "libbezel is not dynamically linked to Qt6Widgets as required by LGPL release policy" >&2
  exit 1
fi

# Catch Qt dependency holes while allowing the explicitly external OS baseline.
# Any unresolved library whose name starts with libQt6 is a packaging bug.
while IFS= read -r file; do
  unresolved="$(LD_LIBRARY_PATH="$ROOT${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ldd "$file" 2>/dev/null | awk '/not found/ { print $1 }')"
  if grep -q '^libQt6' <<<"$unresolved"; then
    echo "unresolved Qt dependency for $file:" >&2
    echo "$unresolved" >&2
    exit 1
  fi
done < <(find "$ROOT" -type f -name '*.so*' -print)

mkdir -p "$DIST_DIR"
tar -C "$DIST_DIR" -czf "$ARCHIVE" "$ASSET"
echo "$ARCHIVE"
