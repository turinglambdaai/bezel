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
mkdir -p "$ROOT/platforms" "$ROOT/imageformats"

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

# Qt tool naming differs between distributions. Ubuntu 22.04 ships a generic
# `qtpaths` through qtchooser, which exits with an error unless a Qt selection
# is configured. `qmake6 -query` is the most reliable Qt 6 source there; keep
# several fallbacks for newer distros and non-Debian systems.
QT_PLUGIN_DIR=""
if command -v qmake6 >/dev/null 2>&1; then
  QT_PLUGIN_DIR="$(qmake6 -query QT_INSTALL_PLUGINS 2>/dev/null || true)"
fi
if [[ -z "$QT_PLUGIN_DIR" ]] && command -v qtpaths6 >/dev/null 2>&1; then
  QT_PLUGIN_DIR="$(qtpaths6 --plugin-dir 2>/dev/null || true)"
fi
if [[ -z "$QT_PLUGIN_DIR" ]] && command -v qtpaths >/dev/null 2>&1; then
  QT_PLUGIN_DIR="$(qtpaths --qt-version 6 --plugin-dir 2>/dev/null || true)"
fi
if [[ -z "$QT_PLUGIN_DIR" ]] && command -v dpkg-architecture >/dev/null 2>&1; then
  multiarch="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || true)"
  for candidate in \
    "/usr/lib/${multiarch}/qt6/plugins" \
    "/usr/lib/qt6/plugins" \
    "/usr/lib64/qt6/plugins"; do
    if [[ -n "$multiarch" && -d "$candidate" ]] || [[ -d "$candidate" ]]; then
      QT_PLUGIN_DIR="$candidate"
      break
    fi
  done
fi
if [[ -z "$QT_PLUGIN_DIR" || ! -d "$QT_PLUGIN_DIR" ]]; then
  echo "Qt 6 plugin directory could not be discovered" >&2
  echo "Tried qmake6, qtpaths6, qtpaths --qt-version 6, and standard distro paths." >&2
  exit 1
fi

echo "Qt plugin directory: $QT_PLUGIN_DIR"

# Keep the SDK runtime intentionally small and predictable. Bezel needs a real
# desktop backend plus the offscreen backend used by tests/rendering. Common
# image codecs are useful to applications without dragging in unrelated QPA
# backends (Wayland/EGLFS/VNC/etc.) and their extra system dependencies.
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

# glibc and the C/C++ runtime are part of the supported Linux baseline rather
# than the Bezel bundle. Everything else reachable from libbezel, Qt, and the
# selected plugins is copied recursively. This is the important difference
# between a build-tree package and a runtime that works on a machine where Qt
# development/runtime packages were never installed.
is_baseline_system_lib() {
  case "$1" in
    ld-linux*.so*|libc.so.*|libm.so.*|libpthread.so.*|libdl.so.*|librt.so.*|\
    libresolv.so.*|libutil.so.*|libnss_*.so.*|libstdc++.so.*|libgcc_s.so.*)
      return 0 ;;
    *) return 1 ;;
  esac
}

copy_direct_deps() {
  local file="$1"
  while IFS= read -r dep; do
    [[ -n "$dep" && -e "$dep" ]] || continue
    local base
    base="$(basename "$dep")"
    is_baseline_system_lib "$base" && continue
    if [[ ! -e "$ROOT/$base" ]]; then
      cp -L "$dep" "$ROOT/$base"
    fi
  done < <(ldd "$file" 2>/dev/null | awk '$2 == "=>" && $3 ~ /^\// { print $3 }')
}

# Iterate until no new dependency was discovered. Dependencies copied to ROOT
# can themselves depend on ICU, xcb, fontconfig, JPEG, etc.
for _ in 1 2 3 4 5 6 7 8; do
  before="$(find "$ROOT" -maxdepth 1 -type f | wc -l)"
  while IFS= read -r file; do
    copy_direct_deps "$file"
  done < <(find "$ROOT" -type f -name '*.so*' -print)
  after="$(find "$ROOT" -maxdepth 1 -type f | wc -l)"
  [[ "$before" == "$after" ]] && break
done

# The shim, Qt libraries and copied dependency closure live at the runtime
# root. Plugins are one directory deeper and therefore resolve root libraries
# through $ORIGIN/..
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

# Do not publish a bundle with a dependency hole that only the build runner's
# installed Qt packages happen to satisfy.
missing=0
while IFS= read -r file; do
  unresolved="$(LD_LIBRARY_PATH="$ROOT${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ldd "$file" 2>/dev/null | awk '/not found/ { print }')"
  if [[ -n "$unresolved" ]]; then
    echo "unresolved runtime dependencies for $file:" >&2
    echo "$unresolved" >&2
    missing=1
  fi
done < <(find "$ROOT" -type f -name '*.so*' -print)
[[ "$missing" -eq 0 ]] || exit 1

mkdir -p "$DIST_DIR"
tar -C "$DIST_DIR" -czf "$ARCHIVE" "$ASSET"
echo "$ARCHIVE"
