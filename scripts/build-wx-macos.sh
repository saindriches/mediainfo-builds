#!/usr/bin/env bash
# Build wxWidgets static and universal (arm64 + x86_64) from source, installed to $WX_PREFIX. The
# macOS GUI links wx statically (mirroring the official Make_MI_dmg --with-wx-static path), so the
# resulting MediaInfo.app carries no wx dylib and is a universal2 binary. Homebrew's wx is
# arm64-only, so we cannot use it for a universal build; hence source.
#
# We use wx's own --enable-universal_binary so the fat libs keep their normal names (a per-arch +
# lipo merge does not work: a cross --host build renames the libs with the host triple, so they
# never line up for lipo). The catch is wx 3.2.6's bundled libpng, whose Intel-SSE path fails to
# compile for the x86_64 slice (pngpriv.h pulls the classic 'fp.h'); since the MediaInfo GUI uses no
# images (no wxImage/wxBitmap/PNG in Source/GUI/WxWidgets), we drop libpng/libjpeg/libtiff and svg.
#
# Cached by the workflow, keyed on WX_VERSION. Idempotent: a present wx-config means a cache hit.
set -euxo pipefail
: "${WX_PREFIX:?set WX_PREFIX}" "${WX_VERSION:?set WX_VERSION}"

if [ -x "$WX_PREFIX/bin/wx-config" ]; then
  echo "mediainfo-builds: wxWidgets already built at $WX_PREFIX (cache hit), skipping"
  exit 0
fi

jobs="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
work="$(mktemp -d)"; cd "$work"
url="https://github.com/wxWidgets/wxWidgets/releases/download/v${WX_VERSION}/wxWidgets-${WX_VERSION}.tar.bz2"
curl -fsSL "$url" -o wx.tar.bz2
tar xf wx.tar.bz2
cd "wxWidgets-${WX_VERSION}"

# Static (--disable-shared; wx has no --enable-static), universal via --enable-universal_binary.
# Image libs and svg off (see header): avoids the bundled-libpng SSE compile failure and keeps the
# static libs lean. The GUI needs none of them.
./configure \
  --prefix="$WX_PREFIX" \
  --disable-shared \
  --enable-unicode \
  --enable-universal_binary=arm64,x86_64 \
  --with-macosx-version-min=11.0 \
  --without-libpng --without-libjpeg --without-libtiff \
  --disable-svg \
  --disable-sound --disable-mediactrl --disable-webview

make -j"$jobs"
make install
test -x "$WX_PREFIX/bin/wx-config" || { echo "::error::wx-config not produced"; exit 1; }
"$WX_PREFIX/bin/wx-config" --version
lipo -info "$(find "$WX_PREFIX" -name 'libwx_baseu-*.a' | head -1)" || true
echo "mediainfo-builds: wxWidgets ${WX_VERSION} (static, universal) installed to $WX_PREFIX"
