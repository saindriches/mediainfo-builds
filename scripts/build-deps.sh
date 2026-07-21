#!/usr/bin/env bash
# Build ZenLib and the MMT/TLV MediaInfoLib in place, the way the official MediaInfo build expects:
# ZenLib/, MediaInfoLib/, MediaInfo/ as siblings, each built with autotools (autoreconf + configure
# + make) but NOT installed. The CLI and GUI configure scripts find these built libraries through
# the relative sibling paths (../../../../ZenLib/..., ../../../../MediaInfoLib/...) and link the
# static .la, so there is no install prefix; the built source trees ARE the artifact.
#
# MediaInfoLib is checked out from the MMT/TLV PR branch (saindriches/MediaInfoLib @ mmt-tlv), so
# the File_MmtTlv parser is already in-tree — no patching step. This is the slow, cacheable half.
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

# build_lib <dir-under-SRC/Project/GNU/Library> <lib basename, e.g. libzen>
# Configures + builds static. With ARCHS set, builds each arch, stashes its .a OUTSIDE the build
# tree (make clean between arches would wipe anything left in .libs/), then lipos the slices back
# into .libs/<lib>.a so the archive is universal. --host only for the cross arch (a --host on the
# native build pushes autotools into cross mode with an outdated config.sub that rejects arm64).
NATIVE_ARCH="$(uname -m)"   # arm64 on Apple Silicon runners
build_lib() {
  local dir="$1" lib="$2"
  pushd "$SRC/$dir/Project/GNU/Library"
    autoreconf -if
    if [ -z "$ARCHS" ]; then
      ./configure --enable-static --disable-shared
      make -j"$jobs"
    else
      local stash slices=()
      stash="$(mktemp -d)"
      for a in $ARCHS; do
        make clean >/dev/null 2>&1 || true
        local host_opt=""
        [ "$a" != "$NATIVE_ARCH" ] && host_opt="--host=${a}-apple-darwin"
        ./configure --enable-static --disable-shared $host_opt \
          CFLAGS="-arch $a" CXXFLAGS="-arch $a" LDFLAGS="-arch $a"
        make -j"$jobs"
        cp ".libs/${lib}.a" "$stash/${lib}-${a}.a"
        slices+=("$stash/${lib}-${a}.a")
      done
      # Rebuild the native arch last so .la and .libs match the machine, then overwrite the .a fat.
      lipo -create "${slices[@]}" -output ".libs/${lib}.a"
      lipo -info ".libs/${lib}.a"
      rm -rf "$stash"
    fi
    test -f "${lib}.la" || { echo "::error::$lib .la not produced"; exit 1; }
  popd
}

# ZenLib first (MediaInfoLib finds it via the sibling ../../../../ZenLib path), then MediaInfoLib.
build_lib ZenLib libzen
build_lib MediaInfoLib libmediainfo

echo "mediainfo-builds: ZenLib + MediaInfoLib (mmt-tlv) built in place (archs: ${ARCHS:-native})"
