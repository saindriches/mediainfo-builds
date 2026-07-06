#!/usr/bin/env bash
# Build wxWidgets static and universal (arm64 + x86_64) from source, installed to $WX_PREFIX. The
# macOS GUI links wx statically (mirroring the official Make_MI_dmg --with-wx-static path), so the
# resulting MediaInfo.app carries no wx dylib and is a universal2 binary. Homebrew's wx is
# arm64-only, so we cannot use it for a universal build; hence source.
#
# Cached by the workflow, keyed on WX_VERSION, so it builds once. Idempotent: a present wx-config
# means a cache hit and we skip.
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

# Static (wx uses --disable-shared for that; there is no --enable-static), universal. Disable the
# pieces the MediaInfo GUI never uses to keep it lean. --enable-universal_binary builds a fat lib.
./configure \
  --prefix="$WX_PREFIX" \
  --disable-shared \
  --enable-unicode \
  --enable-universal_binary=arm64,x86_64 \
  --with-macosx-version-min=11.0 \
  --disable-sound --disable-mediactrl \
  --disable-webview

make -j"$jobs"
make install
test -x "$WX_PREFIX/bin/wx-config" || { echo "::error::wx-config not produced"; exit 1; }
"$WX_PREFIX/bin/wx-config" --version
echo "mediainfo-builds: wxWidgets ${WX_VERSION} (static, universal) installed to $WX_PREFIX"
