#!/usr/bin/env bash
set -euo pipefail

# Build the exact reviewed QtBase source into a redistributable Linux prefix.
# We intentionally disable ICU because Qt's public Linux binary package has an
# external ICU 73 dependency that is not present on Ubuntu 22.04/24.04. Pulling
# that binary dependency into Bezel would expand our redistribution/license
# surface. Qt's configure system supports -no-icu; all bundled third-party
# libraries selected here come from the exact QtBase source archive whose
# license/attribution material is already shipped with the Bezel runtime.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
POLICY="$REPO_ROOT/release/qt-runtime-policy.json"
PREFIX="${1:-$REPO_ROOT/.qt-linux/6.8.3}"
WORK_DIR="${2:-$REPO_ROOT/.qt-linux-build}"
SOURCE_ARCHIVE="${3:-}"

read_policy() {
  python3 - "$POLICY" "$1" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    value = json.load(f)[sys.argv[2]]
print(value)
PY
}

QT_VERSION="$(read_policy qt_version)"
QT_ARCHIVE="$(read_policy source_archive)"
QT_SOURCE_URL="$(read_policy source_url)"
QT_SOURCE_SHA256="$(read_policy source_sha256)"

case "$QT_VERSION" in
  6.8.3) ;;
  *) echo "unexpected Qt version in policy: $QT_VERSION" >&2; exit 1 ;;
esac

if [[ -e "$PREFIX/bin/qmake6" || -e "$PREFIX/bin/qmake" ]]; then
  echo "Using existing pinned Qt prefix: $PREFIX"
  exit 0
fi

mkdir -p "$WORK_DIR" "$(dirname "$PREFIX")"
if [[ -z "$SOURCE_ARCHIVE" ]]; then
  SOURCE_ARCHIVE="$WORK_DIR/$QT_ARCHIVE"
fi

if [[ ! -f "$SOURCE_ARCHIVE" ]]; then
  echo "Downloading $QT_SOURCE_URL"
  curl --fail --location --retry 3 --output "$SOURCE_ARCHIVE" "$QT_SOURCE_URL"
fi

echo "$QT_SOURCE_SHA256  $SOURCE_ARCHIVE" | sha256sum --check -

SRC_DIR="$WORK_DIR/src"
BUILD_DIR="$WORK_DIR/build"
rm -rf "$SRC_DIR" "$BUILD_DIR" "$PREFIX"
mkdir -p "$SRC_DIR" "$BUILD_DIR" "$PREFIX"
tar -xJf "$SOURCE_ARCHIVE" -C "$SRC_DIR" --strip-components=1

# Keep this configuration deliberately small and auditable:
# - shared: required by the public LGPL replacement/relinking model;
# - no ICU: removes the external ICU 73 runtime dependency from QtCore;
# - force bundled libs: zlib/jpeg/png/freetype/harfbuzz/pcre/etc. come from the
#   exact QtBase source archive, so their source + notices travel together;
# - no OpenSSL linkage: QtNetwork is not part of Bezel's runtime contract and
#   must not pull OpenSSL into the package dependency closure;
# - X11/xcb remains a host dependency, as Qt's deployment guidance recommends.
cd "$BUILD_DIR"
"$SRC_DIR/configure" \
  -prefix "$PREFIX" \
  -release \
  -shared \
  -no-icu \
  -force-bundled-libs \
  -openssl-runtime \
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
  "$PREFIX/lib/libQt6Core.so.6" \
  "$PREFIX/lib/libQt6Gui.so.6" \
  "$PREFIX/lib/libQt6Widgets.so.6" \
  "$QT_PLUGIN_DIR/platforms/libqxcb.so" \
  "$QT_PLUGIN_DIR/platforms/libqoffscreen.so"; do
  [[ -e "$required" ]] || { echo "pinned Qt build missing: $required" >&2; exit 1; }
done

if ldd "$PREFIX/lib/libQt6Core.so.6" | grep -E 'libicu[^ ]*\.so' >/dev/null; then
  echo "pinned Linux Qt unexpectedly depends on ICU" >&2
  ldd "$PREFIX/lib/libQt6Core.so.6" >&2
  exit 1
fi

# Fail if a bundled-source selection unexpectedly became a separately linked
# host dependency. The package is allowed to depend on the normal Linux/X11
# platform stack, libc/libstdc++, graphics drivers, and dl/pthread primitives.
for forbidden in libicu libpcre libpng libjpeg libfreetype libharfbuzz libzstd libdouble-conversion; do
  if ldd "$PREFIX/lib/libQt6Core.so.6" "$PREFIX/lib/libQt6Gui.so.6" 2>/dev/null | grep -F "$forbidden" >/dev/null; then
    echo "unexpected external dependency after -force-bundled-libs: $forbidden" >&2
    exit 1
  fi
done

cat > "$PREFIX/BEZEL-QT-BUILD.txt" <<EOF
Qt version: $QT_VERSION
Source archive: $QT_ARCHIVE
Source SHA-256: $QT_SOURCE_SHA256
Build profile: linux-x86_64-shared-no-icu-force-bundled-libs
Linkage: shared
ICU: disabled
Third-party policy: QtBase bundled copies where supported
EOF

echo "Pinned Linux QtBase ready: $PREFIX"
