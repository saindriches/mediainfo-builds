#!/usr/bin/env bash
# Build wxWidgets static and universal (arm64 + x86_64) from source, installed to $WX_PREFIX. The
# macOS GUI links wx statically (mirroring the official Make_MI_dmg --with-wx-static path), so the
# resulting MediaInfo.app carries no wx dylib and is a universal2 binary. Homebrew's wx is
# arm64-only, so we cannot use it for a universal build; hence source.
#
# We build each arch in its own prefix (native for arm64, cross with -arch x86_64), then merge: the
# arm64 prefix becomes $WX_PREFIX and every static lib in it is lipo'd with its x86_64 counterpart
# into a fat archive. This sidesteps wx's --enable-universal_binary, whose bundled libpng compiles
# an Intel-SSE path that fails to build for the x86_64 slice on an arm64 host.
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
mv "wxWidgets-${WX_VERSION}" src

# build_arch <arch> <prefix>: configure + build + install a static wx for one arch. Pass --host
# only when cross-compiling (arch != the build machine); a --host on the native build pushes wx's
# bundled pcre into cross mode with an outdated config.sub that rejects arm64-apple-darwin.
NATIVE_ARCH="$(uname -m)"   # arm64 on Apple Silicon runners
build_arch() {
  local arch="$1" prefix="$2"
  # --host only when cross-compiling (empty string is dropped by configure).
  local host_opt=""
  if [ "$arch" != "$NATIVE_ARCH" ]; then
    host_opt="--host=${arch}-apple-darwin"   # config.sub understands x86_64-apple-darwin
  fi
  rm -rf "$work/b-$arch"; cp -R "$work/src" "$work/b-$arch"
  pushd "$work/b-$arch"
    # The MediaInfo GUI is a plain info window (no wxImage/wxBitmap/PNG in Source/GUI/WxWidgets), so
    # drop the bundled image libs. wx 3.2.6's bundled libpng fails to compile on recent macOS SDKs
    # (pngpriv.h pulls the classic-Mac 'fp.h'); --without-libpng avoids it. SVG needs libpng, so
    # disable it too. This also keeps the static libs lean.
    ./configure \
      --prefix="$prefix" \
      $host_opt \
      --disable-shared \
      --enable-unicode \
      --with-macosx-version-min=11.0 \
      --without-libpng --without-libjpeg --without-libtiff \
      --disable-svg \
      --disable-sound --disable-mediactrl --disable-webview \
      CFLAGS="-arch $arch" CXXFLAGS="-arch $arch" \
      OBJCFLAGS="-arch $arch" OBJCXXFLAGS="-arch $arch" LDFLAGS="-arch $arch"
    make -j"$jobs"
    make install
  popd
}

build_arch arm64  "$WX_PREFIX"
build_arch x86_64 "$work/wx-x86_64"

# Fatten every static lib in the arm64 prefix with its x86_64 twin. wx-config and headers from the
# arm64 prefix stay as-is (arch-independent), so the final $WX_PREFIX is a working universal wx.
while IFS= read -r lib; do
  rel="${lib#$WX_PREFIX/}"
  x86="$work/wx-x86_64/$rel"
  if [ -f "$x86" ]; then
    lipo -create "$lib" "$x86" -output "$lib"
  fi
done < <(find "$WX_PREFIX" -name '*.a')

test -x "$WX_PREFIX/bin/wx-config" || { echo "::error::wx-config not produced"; exit 1; }
"$WX_PREFIX/bin/wx-config" --version
lipo -info "$(find "$WX_PREFIX" -name 'libwx_baseu-*.a' | head -1)" || true
echo "mediainfo-builds: wxWidgets ${WX_VERSION} (static, universal via per-arch lipo) at $WX_PREFIX"
