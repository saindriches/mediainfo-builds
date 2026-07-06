#!/usr/bin/env bash
# Wrap the wxWidgets mediainfo-gui binary into MediaInfo.app, mirroring the GUI path of the
# official Project/Mac/Make_MI_dmg.sh (Info.plist + MediaInfo.icns from Project/Mac/, VERSION
# substituted, PkgInfo written). We ad-hoc sign instead of the Developer ID cert Make_MI_dmg uses,
# so the app runs on a personal machine (clear the quarantine xattr; see README).
#
# Args: <mediainfo-gui path> <MediaInfo source dir> <version> <output MediaInfo.app path>
set -euxo pipefail
GUI_BIN="${1:?mediainfo-gui path}"
MI_SRC="${2:?MediaInfo source dir}"
VERSION="${3:?version}"
APP="${4:?output MediaInfo.app path}"

MAC="$MI_SRC/Project/Mac"
test -x "$GUI_BIN"       || { echo "::error::mediainfo-gui not found or not executable: $GUI_BIN"; exit 1; }
test -f "$MAC/Info.plist" || { echo "::error::$MAC/Info.plist missing"; exit 1; }
# Must be the real Mach-O, not a libtool wrapper script (which happens if the deps cache still had
# shared libs); bundling a wrapper would ship a broken app.
file "$GUI_BIN" | grep -q 'Mach-O' || { echo "::error::mediainfo-gui is a libtool wrapper, not a binary: $GUI_BIN"; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# The wx binary is fully self-contained (static libs), so the executable is all we ship.
cp "$GUI_BIN" "$APP/Contents/MacOS/MediaInfo"
strip -u -r "$APP/Contents/MacOS/MediaInfo" || true

cp "$MAC/Info.plist" "$APP/Contents/Info.plist"
sed -i '' -e "s/VERSION/${VERSION}/g" "$APP/Contents/Info.plist"
printf '%s' 'APPL????' > "$APP/Contents/PkgInfo"
cp "$MAC/MediaInfo.icns" "$APP/Contents/Resources/MediaInfo.icns"

# List non-system dylib deps. otool -L on a universal binary prints a header line per arch
# ("... (architecture arm64):") plus the binary path line; real deps are the tab-indented lines
# with a path. Keep only tab-indented lines, then drop system + already-bundled paths.
nonsystem_deps() {
  otool -L "$1" | grep $'^\t' | awk '{print $1}' | grep -vE '^(/usr/lib|/System)/|^@executable_path/' || true
}

# With wx built static (build-wx-macos.sh) the binary should carry no non-system dylib. If any
# slipped in (e.g. a Homebrew wx), bundle it into Contents/libs/ and rewrite the load path to
# @executable_path/../libs, so the app stays self-contained either way.
if [ -n "$(nonsystem_deps "$APP/Contents/MacOS/MediaInfo")" ]; then
  dylibbundler --overwrite-dir --bundle-deps --create-dir \
    --fix-file "$APP/Contents/MacOS/MediaInfo" \
    --dest-dir "$APP/Contents/libs" \
    --install-path "@executable_path/../libs/"
fi

# Fail if any non-system dylib dep still remains unresolved.
if [ -n "$(nonsystem_deps "$APP/Contents/MacOS/MediaInfo")" ]; then
  echo "::error::MediaInfo.app still has an unbundled dylib dep"; otool -L "$APP/Contents/MacOS/MediaInfo"; exit 1
fi

# Ad-hoc sign (no Developer ID). Fine for personal use, not notarized. Sign any bundled libs first.
find "$APP/Contents/libs" -name '*.dylib' -exec codesign -f -s - {} \; 2>/dev/null || true
codesign -f -s - "$APP/Contents/MacOS/MediaInfo"
codesign -f -s - --deep "$APP"
codesign --verify --verbose "$APP"
echo "mediainfo-builds: app binary arch: $(lipo -info "$APP/Contents/MacOS/MediaInfo" 2>/dev/null || echo unknown)"

echo "mediainfo-builds: built $APP (version $VERSION, ad-hoc signed)"
