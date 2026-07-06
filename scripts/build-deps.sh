#!/usr/bin/env bash
# Build ZenLib and the patched MediaInfoLib in place, the way the official MediaInfo build expects:
# ZenLib/, MediaInfoLib/, MediaInfo/ as siblings, each built with autotools (autoreconf + configure
# + make) but NOT installed. The CLI and GUI configure scripts find these built libraries through
# the relative sibling paths (../../../../ZenLib/..., ../../../../MediaInfoLib/...) and link the
# static .la, so there is no install prefix; the built source trees ARE the artifact.
#
# patches/mediainfolib/* are applied to MediaInfoLib before it configures; the MMT/TLV parser
# (File_MmtTlv) lives there. This is the slow, cacheable half of the build.
#
# macOS universal: set ARCHS="arm64 x86_64" and each dep is built once per arch and lipo'd into a
# fat .libs/*.a in place, so the CLI/GUI (compiled with both -arch flags) link a universal library.
# Leave ARCHS empty on Linux for a plain native build.
#
# Idempotent: if MediaInfoLib's libmediainfo.la already exists (restored from cache) it does
# nothing, so a cache hit is free. --disable-shared throughout so only static .a is produced;
# otherwise the linker picks the dylib and the final binaries get a build-tree-relative dep.
set -euxo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${SRC:-$ROOT}"        # where ZenLib/ and MediaInfoLib/ are checked out (workspace by default)
ARCHS="${ARCHS:-}"         # e.g. "arm64 x86_64" for a universal macOS build; empty = native

if [ -f "$SRC/MediaInfoLib/Project/GNU/Library/libmediainfo.la" ]; then
  echo "mediainfo-builds: deps already built (cache hit), skipping"
  exit 0
fi

jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"

# Apply our MMT/TLV patches to MediaInfoLib once, before any configure.
pushd "$SRC/MediaInfoLib"
  shopt -s nullglob
  for p in "$ROOT"/patches/mediainfolib/*.patch; do
    echo "mediainfo-builds: applying $(basename "$p")"
    patch -p1 -F3 < "$p"
  done
popd

# build_lib <dir-under-SRC/Project/GNU/Library> <lib basename, e.g. libzen>
# Configures + builds static. With ARCHS set, builds each arch into a temp copy of the .a and lipos
# them into the final .libs/<lib>.a so the archive is universal.
build_lib() {
  local dir="$1" lib="$2"
  pushd "$SRC/$dir/Project/GNU/Library"
    autoreconf -if
    if [ -z "$ARCHS" ]; then
      ./configure --enable-static --disable-shared
      make -j"$jobs"
    else
      local slices=()
      for a in $ARCHS; do
        make clean >/dev/null 2>&1 || true
        ./configure --enable-static --disable-shared --host="${a}-apple-darwin" \
          CFLAGS="-arch $a" CXXFLAGS="-arch $a" LDFLAGS="-arch $a"
        make -j"$jobs"
        cp ".libs/${lib}.a" ".libs/${lib}-${a}.a"
        slices+=(".libs/${lib}-${a}.a")
      done
      lipo -create "${slices[@]}" -output ".libs/${lib}.a"
      rm -f "${slices[@]}"
      lipo -info ".libs/${lib}.a"
    fi
    test -f "${lib}.la" || { echo "::error::$lib .la not produced"; exit 1; }
  popd
}

# ZenLib first (MediaInfoLib finds it via the sibling ../../../../ZenLib path), then MediaInfoLib.
build_lib ZenLib libzen
build_lib MediaInfoLib libmediainfo

echo "mediainfo-builds: ZenLib + patched MediaInfoLib built in place (archs: ${ARCHS:-native})"
