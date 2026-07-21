#!/usr/bin/env bash
# Build wxWidgets (GTK3) static from source, installed to $WX_PREFIX, for the Linux MediaInfo GUI.
# Static wx (--disable-shared) means mediainfo-gui embeds wx and only dynamically links the system
# GTK3/glib stack, which the AppImage step bundles. Unlike the macOS build we KEEP libpng: the GUI
# uses PNG icons (Source/Resource/Image/MediaInfo.png), and wx's bundled/system libpng compiles
# cleanly for native x86_64 here (the macOS drop was only to dodge an Intel-slice SSE compile break).
#
# Cached by the workflow, keyed on WX_VERSION + this script's hash. Idempotent: a present wx-config
# is treated as a cache hit.
set -euxo pipefail
: "${WX_PREFIX:?set WX_PREFIX}" "${WX_VERSION:?set WX_VERSION}"

if [ -x "$WX_PREFIX/bin/wx-config" ]; then
  echo "mediainfo-builds: wxWidgets already built at $WX_PREFIX (cache hit), skipping"
  exit 0
fi

jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
work="$(mktemp -d)"; cd "$work"
url="https://github.com/wxWidgets/wxWidgets/releases/download/v${WX_VERSION}/wxWidgets-${WX_VERSION}.tar.bz2"
curl -fsSL "$url" -o wx.tar.bz2
tar xf wx.tar.bz2
cd "wxWidgets-${WX_VERSION}"

# GTK3, Unicode, static. No sound/mediactrl/webview (the GUI uses none, and they drag in extra
# runtime libs the AppImage would then have to bundle). PNG stays on for the app icon.
./configure \
  --prefix="$WX_PREFIX" \
  --disable-shared \
  --enable-unicode \
  --with-gtk=3 \
  --disable-sound --disable-mediactrl --disable-webview

make -j"$jobs"
make install
test -x "$WX_PREFIX/bin/wx-config" || { echo "::error::wx-config not produced"; exit 1; }
"$WX_PREFIX/bin/wx-config" --version
echo "mediainfo-builds: wxWidgets ${WX_VERSION} (GTK3, static) installed to $WX_PREFIX"
