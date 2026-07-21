#!/usr/bin/env bash
# Wrap the wxWidgets mediainfo-gui binary into a portable AppImage. wx is static, but the binary
# still dynamically links the GTK3/glib stack; linuxdeploy copies those .so's into the AppDir so the
# result runs on any reasonably recent glibc distro with no install. Mirrors the intent of the macOS
# MediaInfo.app packaging (self-contained GUI), using the .desktop + PNG icon MediaInfo already ships.
#
# Args: <mediainfo-gui path> <MediaInfo source dir> <version> <output .AppImage path>
set -euxo pipefail
GUI_BIN="${1:?mediainfo-gui path}"
MI_SRC="${2:?MediaInfo source dir}"
VERSION="${3:?version}"
OUT="${4:?output .AppImage path}"

test -x "$GUI_BIN" || { echo "::error::mediainfo-gui not found or not executable: $GUI_BIN"; exit 1; }
# Guard against a libtool wrapper script (happens if the deps cache still had shared libs).
file "$GUI_BIN" | grep -q 'ELF' || { echo "::error::mediainfo-gui is not an ELF binary: $GUI_BIN"; exit 1; }

work="$(mktemp -d)"
APPDIR="$work/AppDir"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/applications" \
         "$APPDIR/usr/share/icons/hicolor/256x256/apps"

install -m755 "$GUI_BIN" "$APPDIR/usr/bin/mediainfo-gui"

# .desktop: prefer the one MediaInfo ships; fall back to a minimal one. Icon key must match the
# icon basename (mediainfo-gui) that we install below.
DESKTOP="$APPDIR/usr/share/applications/mediainfo-gui.desktop"
if [ -f "$MI_SRC/Project/GNU/GUI/mediainfo-gui.desktop" ]; then
  cp "$MI_SRC/Project/GNU/GUI/mediainfo-gui.desktop" "$DESKTOP"
  grep -q '^Icon=' "$DESKTOP" && sed -i 's/^Icon=.*/Icon=mediainfo-gui/' "$DESKTOP" || echo 'Icon=mediainfo-gui' >> "$DESKTOP"
else
  cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=MediaInfo
Exec=mediainfo-gui %F
Icon=mediainfo-gui
Categories=AudioVideo;Utility;
Terminal=false
EOF
fi

# Icon (PNG). MediaInfo ships a few under Source/Resource/Image.
ICON_SRC=""
for c in MediaInfoBig.png MediaInfo.png; do
  [ -f "$MI_SRC/Source/Resource/Image/$c" ] && ICON_SRC="$MI_SRC/Source/Resource/Image/$c" && break
done
if [ -n "$ICON_SRC" ]; then
  ICON_DEST="$APPDIR/usr/share/icons/hicolor/256x256/apps/mediainfo-gui.png"
  # linuxdeploy validates the icon's ACTUAL pixel size against a fixed allow-list (…256, 384, 480,
  # 512) and MediaInfo's PNGs are 1024×1024, which is rejected. Resize to 256×256 so it validates
  # (and matches the hicolor/256x256 dir). ImageMagick is installed in the workflow.
  if command -v convert >/dev/null 2>&1; then
    convert "$ICON_SRC" -resize 256x256 "$ICON_DEST"
  elif command -v magick >/dev/null 2>&1; then
    magick "$ICON_SRC" -resize 256x256 "$ICON_DEST"
  else
    echo "::warning::ImageMagick not found; copying icon unresized (linuxdeploy may reject it)"
    cp "$ICON_SRC" "$ICON_DEST"
  fi
  cp "$ICON_DEST" "$APPDIR/mediainfo-gui.png"   # top-level icon linuxdeploy expects
fi

# Tools as AppImages; --appimage-extract-and-run avoids needing FUSE on the runner.
cd "$work"
curl -fsSL -o linuxdeploy "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage"
# The appimage OUTPUT plugin is what actually turns the AppDir into a .AppImage; `--output appimage`
# is a no-op (AppDir only, "no AppImage produced") unless this plugin is present next to linuxdeploy.
curl -fsSL -o linuxdeploy-plugin-appimage "https://github.com/linuxdeploy/linuxdeploy-plugin-appimage/releases/download/continuous/linuxdeploy-plugin-appimage-x86_64.AppImage"
curl -fsSL -o linuxdeploy-plugin-gtk "https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/master/linuxdeploy-plugin-gtk.sh" || true
chmod +x linuxdeploy linuxdeploy-plugin-appimage linuxdeploy-plugin-gtk 2>/dev/null || true
export PATH="$work:$PATH"    # so linuxdeploy finds the plugins by name
export APPIMAGE_EXTRACT_AND_RUN=1
export OUTPUT="$OUT"

# GTK plugin if available (bundles GTK modules/themes); otherwise plain bundling still pulls the
# direct .so deps, which is enough for this dialog-style app.
plugin_args=()
[ -x linuxdeploy-plugin-gtk ] && plugin_args=(--plugin gtk)
mkdir -p "$(dirname "$OUT")"
./linuxdeploy --appdir "$APPDIR" \
  --desktop-file "$DESKTOP" \
  ${ICON_SRC:+--icon-file "$APPDIR/mediainfo-gui.png"} \
  "${plugin_args[@]}" \
  --output appimage

# The appimage plugin honors $OUTPUT and writes the .AppImage straight to $OUT (an absolute path),
# so there is nothing in $work to move — just verify it landed.
[ -f "$OUT" ] || { echo "::error::no AppImage at $OUT"; ls -la "$work" "$(dirname "$OUT")" || true; exit 1; }
chmod +x "$OUT"
echo "mediainfo-builds: built $OUT (version $VERSION)"
