#!/usr/bin/env bash
# Build ZenLib and the patched MediaInfoLib in place, the way the official MediaInfo build expects:
# ZenLib/, MediaInfoLib/, MediaInfo/ as siblings, each built with autotools (autoreconf + configure
# + make) but NOT installed. The CLI and GUI configure scripts find these built libraries through
# the relative sibling paths (../../../../ZenLib/..., ../../../../MediaInfoLib/...) and link the
# static .la, so there is no install prefix; the built source trees ARE the artifact.
#
# patches/mediainfolib/* are applied to MediaInfoLib before it configures; the MMT/TLV parser
# (File_MmtTlv) lives there. This is the slow, cacheable half of the build: the two built trees are
# cached (see the workflow). Idempotent: if MediaInfoLib's libmediainfo.la already exists (restored
# from cache) it does nothing, so a cache hit is free.
set -euxo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${SRC:-$ROOT}"   # where ZenLib/ and MediaInfoLib/ are checked out (workspace by default)

if [ -f "$SRC/MediaInfoLib/Project/GNU/Library/libmediainfo.la" ]; then
  echo "mediainfo-build: deps already built (cache hit), skipping"
  exit 0
fi

jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"

# ZenLib: the base library. --disable-shared so only libzen.a is produced; otherwise the linker
# picks up the dylib and the CLI/GUI end up with a build-tree-relative libzen dynamic dep that will
# not resolve on another machine. Static-only makes the final binaries self-contained.
pushd "$SRC/ZenLib/Project/GNU/Library"
  autoreconf -if
  ./configure --enable-static --disable-shared
  make -j"$jobs"
  test -f libzen.la || { echo "::error::ZenLib libzen.la not produced"; exit 1; }
popd

# MediaInfoLib: apply our MMT/TLV patches, then build static in place. Its configure finds ZenLib
# via the sibling ../../../../ZenLib path.
pushd "$SRC/MediaInfoLib"
  shopt -s nullglob
  for p in "$ROOT"/patches/mediainfolib/*.patch; do
    echo "mediainfo-build: applying $(basename "$p")"
    patch -p1 -F3 < "$p"
  done
  cd Project/GNU/Library
  autoreconf -if
  ./configure --enable-static --disable-shared
  make -j"$jobs"
  test -f libmediainfo.la || { echo "::error::MediaInfoLib libmediainfo.la not produced"; exit 1; }
popd

echo "mediainfo-build: ZenLib + patched MediaInfoLib built in place"
