#!/usr/bin/env bash
set -euo pipefail

# Build the exact reviewed QtBase source into a redistributable Linux prefix.
# ICU is disabled because Qt's public Linux binary package has an external ICU
# dependency that is not part of Bezel's public redistribution boundary. Other
# dynamically resolved Linux libraries remain host prerequisites: the Bezel
# packager records them but does not copy them into the public runtime. If Qt
# chooses one of its bundled third-party copies internally, that code comes from
# the exact QtBase source archive whose licenses/attributions ship with Bezel.

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

# Deliberately small release configuration:
# - shared: preserves the LGPL replacement/relinking model;
# - no ICU: removes the incompatible external ICU dependency from QtCore;
# - OpenSSL runtime loading: no link-time OpenSSL dependency is introduced;
# - host Linux/X11/font/graphics libraries remain external prerequisites;
# - Qt may use bundled third-party copies from the exact verified QtBase source
#   when its own feature detection selects them. Their notices/source are
#   already covered by the exact-source compliance bundle.
#
# Do not add undocumented umbrella flags here. The accepted Qt 6.8 options are
# intentionally traceable to Qt's configure help/source and CI exercises this
# exact command on Ubuntu 22.04.
cd "$BUILD_DIR"
"$SRC_DIR/configure" \
  -prefix "$PREFIX" \
  -release \
  -shared \
  -no-icu \
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

# ICU is the one explicitly prohibited dependency in this profile. Other
# non-Qt shared libraries are intentionally host prerequisites and are recorded
# later by package-native-linux.sh rather than redistributed.
if ldd "$PREFIX/lib/libQt6Core.so.6" "$PREFIX/lib/libQt6Gui.so.6" 2>/dev/null | grep -E 'libicu[^ ]*\.so' >/dev/null; then
  echo "pinned Linux Qt unexpectedly depends on ICU" >&2
  ldd "$PREFIX/lib/libQt6Core.so.6" >&2
  exit 1
fi

cat > "$PREFIX/BEZEL-QT-BUILD.txt" <<EOF
Qt version: $QT_VERSION
Source archive: $QT_ARCHIVE
Source SHA-256: $QT_SOURCE_SHA256
Build profile: linux-x86_64-source-shared-no-icu-host-deps-external
Linkage: shared
ICU: disabled
Host dependency policy: dynamically linked non-Qt Linux libraries are prerequisites and are not redistributed by Bezel
Bundled dependency policy: any Qt-selected bundled third-party code comes from the exact verified QtBase source archive
EOF

echo "Pinned Linux QtBase ready: $PREFIX"
