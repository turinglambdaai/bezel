#!/usr/bin/env bash
set -euo pipefail

# Build the public macOS runtime from the same verified QtBase source and
# official security patches as the other release targets. OpenGL is disabled:
# Bezel's Qt Widgets surface does not require it, and this avoids inheriting the
# removed AGL framework from old prebuilt Qt SDK metadata on newer macOS images.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
POLICY="$REPO_ROOT/release/qt-runtime-policy.json"
PREFIX="${1:-$REPO_ROOT/.qt-macos/6.8.4}"
WORK_DIR="${2:-$REPO_ROOT/.qt-macos-build}"
SOURCE_ARCHIVE="${3:-$REPO_ROOT/dist/compliance/source/qtbase-everywhere-opensource-src-6.8.4.tar.xz}"
PATCH_DIR="${4:-$REPO_ROOT/dist/compliance/source/patches}"

read_policy() {
  python3 - "$POLICY" "$1" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    print(json.load(f)[sys.argv[2]])
PY
}

QT_VERSION="$(read_policy qt_version)"
[[ "$QT_VERSION" == "6.8.4" ]] || {
  echo "unexpected Qt version in policy: $QT_VERSION" >&2
  exit 1
}

if [[ -x "$PREFIX/bin/qmake6" || -x "$PREFIX/bin/qmake" ]]; then
  echo "Using existing pinned Qt prefix: $PREFIX"
  exit 0
fi

SOURCE_STAGE="$WORK_DIR/source"
BUILD_DIR="$WORK_DIR/build"
rm -rf "$SOURCE_STAGE" "$BUILD_DIR" "$PREFIX"
mkdir -p "$BUILD_DIR" "$PREFIX"
SRC_DIR="$(python3 "$REPO_ROOT/scripts/prepare-pinned-qt-source.py" \
  "$SOURCE_ARCHIVE" "$PATCH_DIR" "$SOURCE_STAGE")"

cd "$BUILD_DIR"
"$SRC_DIR/configure" \
  -prefix "$PREFIX" \
  -release \
  -shared \
  -no-icu \
  -no-opengl \
  -qt-zlib \
  -qt-libpng \
  -qt-libjpeg \
  -qt-pcre \
  -nomake examples \
  -nomake tests \
  -- \
  -DQT_BUILD_EXAMPLES_BY_DEFAULT=OFF \
  -DQT_BUILD_TESTS_BY_DEFAULT=OFF

cmake --build . --parallel "${BEZEL_QT_BUILD_JOBS:-2}"
cmake --install .

QMAKE="$PREFIX/bin/qmake6"
[[ -x "$QMAKE" ]] || QMAKE="$PREFIX/bin/qmake"
[[ -x "$QMAKE" ]] || { echo "qmake missing from pinned Qt install" >&2; exit 1; }
QT_PLUGIN_DIR="$($QMAKE -query QT_INSTALL_PLUGINS)"

for required in \
  "$PREFIX/lib/QtCore.framework" \
  "$PREFIX/lib/QtGui.framework" \
  "$PREFIX/lib/QtWidgets.framework" \
  "$QT_PLUGIN_DIR/platforms/libqcocoa.dylib" \
  "$QT_PLUGIN_DIR/platforms/libqoffscreen.dylib"; do
  [[ -e "$required" ]] || { echo "pinned Qt build missing: $required" >&2; exit 1; }
done

cat > "$PREFIX/BEZEL-QT-BUILD.txt" <<EOF
Qt version: $QT_VERSION
Source archive: $(read_policy source_archive)
Source SHA-256: $(read_policy source_sha256)
Security review date: $(read_policy security_reviewed_through)
Build profile: macosx-aarch64-source-shared-no-icu-no-opengl-official-security-patches
Linkage: shared frameworks
ICU: disabled
OpenGL/AGL: disabled
EOF

echo "Pinned macOS QtBase ready: $PREFIX"
