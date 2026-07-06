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

# Static, universal, no shared. Disable the pieces the MediaInfo GUI never uses to keep it lean and
# avoid pulling extra system frameworks. --disable-sys-libs would rebuild image libs; we keep system
# ones (the app bundles nothing here since wx is static).
./configure \
  --prefix="$WX_PREFIX" \
  --enable-unicode \
  --disable-shared --enable-static \
  --enable-universal_binary=arm64,x86_64 \
  --with-macosx-version-min=11.0 \
  --without-subdirs \
  --disable-sound --disable-mediactrl \
  --disable-webview --disable-webviewwebkit

make -j"$jobs"
make install
test -x "$WX_PREFIX/bin/wx-config" || { echo "::error::wx-config not produced"; exit 1; }
"$WX_PREFIX/bin/wx-config" --version
echo "mediainfo-builds: wxWidgets ${WX_VERSION} (static, universal) installed to $WX_PREFIX"
