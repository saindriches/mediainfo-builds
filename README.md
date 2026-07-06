# mediainfo-build

Builds [MediaInfo](https://github.com/MediaArea/MediaInfo) (the `mediainfo` CLI, plus a
`MediaInfo.app` wxWidgets GUI on macOS) from its three official source repos with the **File_MmtTlv
MMT/TLV patches** under [`patches/mediainfolib/`](patches/mediainfolib/) applied. Those patches add
an MMT/TLV container parser (ARIB STD-B60/B61), so `mediainfo` reports assets, codecs, EIT program
info, service name, audio metadata, and scramble state from Japanese ISDB-S3 4K/8K **`.mmts`**
files. On scrambled streams the clear signaling still yields the metadata. The patch set is
MediaArea/MediaInfoLib PR #2647.

Same idea as the sibling [iina-builds](https://github.com/saindriches/iina-builds) and
[mpv-builds](https://github.com/saindriches/mpv-builds): a standalone repo (not a fork) that keeps
the patches and CI in one clean place.

## The three source repos

MediaInfo builds from three sibling checkouts, the way the official
`Project/GNU/CLI/CLI_Compile.sh` and CI expect:

- **ZenLib** (`MediaArea/ZenLib`): base utility library.
- **MediaInfoLib** (`MediaArea/MediaInfoLib`): the parsing library. Our patches apply here.
- **MediaInfo** (`MediaArea/MediaInfo`): the CLI (`Project/GNU/CLI`) and the wx GUI
  (`Project/GNU/GUI`).

CI checks out all three at the versions pinned in [`manifest.env`](manifest.env), applies the
patches to MediaInfoLib, builds ZenLib + MediaInfoLib static into a prefix, then builds the CLI and
GUI against it.

## What it produces

| platform | runner | output |
|---|---|---|
| macOS arm64 | `macos-14` | `mediainfo` CLI + `MediaInfo.app` (wx GUI) |
| macOS x86_64 | `macos-13` | `mediainfo` CLI + `MediaInfo.app` (wx GUI) |
| Linux x86_64 | `ubuntu-latest` | `mediainfo` CLI |
| Windows x86_64 | `windows-latest` | scaffold (MSVC solution wiring pending) |

`MediaInfo.app` is the wxWidgets `mediainfo-gui` wrapped into a bundle, mirroring the GUI path of
the official `Project/Mac/Make_MI_dmg.sh` (Info.plist + icon from `Project/Mac/`). macOS binaries
are ad-hoc signed (not notarized), fine for personal use.

## Use

Download the artifact for your platform (or a published Release), then:

```sh
tar xf mediainfo-cli-macos-arm64.tar.xz
./mediainfo somefile.mmts

tar xf MediaInfo-gui-macos-arm64.tar.xz
xattr -dr com.apple.quarantine MediaInfo.app   # clear Gatekeeper
open MediaInfo.app
```

## Caching (fast iteration)

Two layers, so re-runs are cheap:

1. **Deps prefix**: the built ZenLib + patched MediaInfoLib (`deps-prefix/`) is cached, keyed on the
   pinned refs and a hash of `patches/mediainfolib/*.patch`. It rebuilds only when a patch or a ref
   changes; a CLI/GUI-only iteration restores it in seconds. `build-deps.sh` is idempotent, so a
   cache hit is free.
2. **ccache**: accelerates recompiles, keyed per platform with a rolling `restore-keys`.

Force a full deps rebuild with the `force_rebuild_deps` dispatch input, or bump `CACHE_EPOCH`.

## Release

On a run where every build job succeeds, the `release` job collects the artifacts and publishes a
GitHub Release tagged `build-<run number>`.

## Pinned inputs

See [`manifest.env`](manifest.env): `ZENLIB_REF`, `MEDIAINFOLIB_REF` (the base our patches target),
`MEDIAINFO_REF`, `MEDIAINFO_VERSION`, `CACHE_EPOCH`.

## Adding a patch

Drop a `-p1` diff into `patches/mediainfolib/` named `NNNN-description.patch` and push; it applies
to the MediaInfoLib source in order before it builds.

## Status

macOS (CLI + GUI) and Linux (CLI) are the intended paths. Windows is a scaffold. First CI runs may
need fixups; GitHub Actions cannot be validated locally.
