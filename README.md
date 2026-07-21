# mediainfo-builds

Builds [MediaInfo](https://github.com/MediaArea/MediaInfo) (the `mediainfo` CLI, plus a
`MediaInfo.app` wxWidgets GUI on macOS) with **MediaInfoLib taken directly from the MMT/TLV PR
branch** ([`saindriches/MediaInfoLib` @ `mmt-tlv`](https://github.com/MediaArea/MediaInfoLib/pull/2647),
MediaArea/MediaInfoLib PR #2647). That branch adds an MMT/TLV container parser (ARIB STD-B60/B61),
so `mediainfo` reports assets, codecs, EIT program info, service name, audio metadata, and scramble
state from Japanese ISDB-S3 4K/8K **`.mmts`** files. On scrambled streams the clear signaling still
yields the metadata. (This repo previously carried the feature as local patches; it now compiles the
PR branch directly.)

Same idea as the sibling [iina-builds](https://github.com/saindriches/iina-builds) and
[mpv-builds](https://github.com/saindriches/mpv-builds): a standalone repo (not a fork) that keeps
the build recipe and CI in one clean place.

## The three source repos

MediaInfo builds from three sibling checkouts, the way the official
`Project/GNU/CLI/CLI_Compile.sh` and CI expect:

- **ZenLib** (`MediaArea/ZenLib`): base utility library.
- **MediaInfoLib** (`saindriches/MediaInfoLib` @ `mmt-tlv`): the parsing library, taken from the
  MMT/TLV PR branch, which carries the `File_MmtTlv` parser in-tree.
- **MediaInfo** (`MediaArea/MediaInfo`): the CLI (`Project/GNU/CLI`) and the wx GUI
  (`Project/GNU/GUI`).

CI checks out all three at the versions pinned in [`manifest.env`](manifest.env), builds ZenLib +
MediaInfoLib static into a prefix, then builds the CLI and GUI against it. No patch step — the
MMT/TLV feature is already in the MediaInfoLib branch.

## What it produces

| platform | runner | output |
|---|---|---|
| macOS universal2 | `macos-14` | `mediainfo` CLI + `MediaInfo.app` (wx GUI), both arm64 + x86_64 in one binary |
| Linux x86_64 | `ubuntu-latest` | `mediainfo` CLI + `MediaInfo-gui` **AppImage** (portable, wxGTK3) |
| Windows x64 | `windows-latest` | `mediainfo.exe` CLI (CMake) + `MediaInfo-GUI.exe` (MSVC solution, wx) |

macOS is built once on Apple Silicon as a **universal2** binary (arm64 + x86_64 via `lipo`), so a
single `mediainfo` and one `MediaInfo.app` run on both architectures. This sidesteps the
now-unreliable macos-13 Intel runners.

`MediaInfo.app` is the wxWidgets `mediainfo-gui` wrapped into a bundle, mirroring the GUI path of
the official `Project/Mac/Make_MI_dmg.sh` (Info.plist + icon from `Project/Mac/`). wxWidgets is
built static and universal from source, so the app carries no wx dylib. macOS binaries are ad-hoc
signed (not notarized), fine for personal use.

Windows builds the **CLI** via the official CMake path (`Project/CMake/CLI/`): CMake FetchContent
pulls `MediaArea/ZenLib` and `MediaArea/zlib`, and the mmt-tlv MediaInfoLib is compiled in from the
sibling checkout, producing a static, self-contained `mediainfo.exe`. The **GUI** has no CMake path,
so it builds from the MSVC solution (`Project/MSVC2022`): the GUI `.vcxproj` references wxWidgets'
own `wx_base`/`wx_core`/`wx_html`/`wx_wxpng` projects plus `ZenLib` and `MediaInfoLib`, so one
`msbuild` of the `MediaInfo-GUI` target builds wxWidgets (from the sibling wxWidgets source) and both
libraries and links a self-contained `MediaInfo-GUI.exe`. The `.vcxproj` hardcodes wx 3.1 lib names,
so we check out wxWidgets `WX_WIN_VERSION` (3.1.x) as the sibling to match — no upstream edits.

Linux ships the GUI as an **AppImage**: wxWidgets (GTK3) is built static from source, `mediainfo-gui`
links it, and `linuxdeploy` bundles the remaining GTK/glib runtime so the single `.AppImage` runs on
any recent glibc distro with nothing to install.

## Use

Download the artifact for your platform (or a published Release), then:

```sh
# macOS (CLI + app)
tar xf mediainfo-cli-macos-universal.tar.xz
./mediainfo somefile.mmts
tar xf MediaInfo-gui-macos-universal.tar.xz
xattr -dr com.apple.quarantine MediaInfo.app   # clear Gatekeeper
open MediaInfo.app

# Linux GUI (portable, no install)
chmod +x MediaInfo-gui-linux-x86_64.AppImage
./MediaInfo-gui-linux-x86_64.AppImage

# Windows: unzip and run mediainfo.exe (CLI) or MediaInfo-GUI.exe (GUI)
```

## Caching (fast iteration)

Three layers, so re-runs are cheap:

1. **Built deps**: ZenLib + MediaInfoLib built in place are cached, keyed on the pinned refs
   (including the `mmt-tlv` commit). They rebuild only when a ref changes; a CLI/GUI-only iteration
   restores them in seconds. `build-deps.sh` is idempotent, so a cache hit is free.
2. **wxWidgets prefix** (macOS universal + Linux GTK3): the static wx build, keyed on `WX_VERSION`.
   (On Windows wx is built as an msbuild project dependency, not separately cached.)
3. **ccache**: accelerates recompiles, keyed per platform with a rolling `restore-keys`.

Force a full deps rebuild with the `force_rebuild_deps` dispatch input, or bump `CACHE_EPOCH`.

## Release

On a run where every build job succeeds, the `release` job collects the artifacts and publishes a
GitHub Release tagged `build-<run number>`.

## Pinned inputs

See [`manifest.env`](manifest.env): `ZENLIB_REF`, `MEDIAINFOLIB_REPO` + `MEDIAINFOLIB_REF` (the
MMT/TLV PR fork and its `mmt-tlv` head commit), `MEDIAINFO_REF`, `MEDIAINFO_VERSION`, `WX_VERSION`
(macOS/Linux GUI), `WX_WIN_VERSION` (Windows GUI, wx 3.1.x to match the vcxproj), `MACOS_ARCHS`,
`CACHE_EPOCH`.

## Updating the MMT/TLV branch

The MMT/TLV parser lives in the PR branch, not here. To pick up new work on the PR, bump
`MEDIAINFOLIB_REF` in [`manifest.env`](manifest.env) and the workflow `env:` to the new `mmt-tlv`
head commit and push; the deps cache busts on the changed ref and rebuilds. (To point at a different
fork/branch entirely, change `MEDIAINFOLIB_REPO` too.)

## Status

All three OS build **CLI + GUI** in CI: macOS (universal CLI + `MediaInfo.app`), Linux (CLI + GUI
AppImage), Windows (CLI + `MediaInfo-GUI.exe`). MediaInfoLib comes from the `mmt-tlv` PR branch.
First CI runs may need fixups; GitHub Actions cannot be validated locally. The Windows GUI (MSVC
solution + wxWidgets built as an msbuild dependency) is the most likely to need iteration.
