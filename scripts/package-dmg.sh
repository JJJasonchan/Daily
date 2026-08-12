#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_dir="$(cd -- "$script_dir/.." && pwd -P)"
app_path="$project_dir/build/Daily.app"
dmg_path="$project_dir/build/Daily.dmg"
tmp_dmg="/tmp/Daily_temp.dmg"

# Ensure .app exists
if [[ ! -d "$app_path" ]]; then
    echo "App not found at $app_path. Run build-app.sh first." >&2
    exit 1
fi

# Clean up any leftover mount
hdiutil detach /Volumes/Daily -force 2>/dev/null || true
rm -f "$tmp_dmg"

# Create sparse image
echo "Creating DMG..."
hdiutil create -size 30m -fs HFS+ -volname "Daily" -attach "$tmp_dmg" >/dev/null 2>&1
sleep 1

# Copy app and Applications symlink
cp -R "$app_path" /Volumes/Daily/
ln -s /Applications /Volumes/Daily/Applications

# Set icon layout
osascript << 'OSA' 2>/dev/null || true
tell application "Finder"
    tell disk "Daily"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {400, 200, 940, 520}
        set icon size of container window to 80
        set position of item "Daily.app" of container window to {160, 130}
        set position of item "Applications" of container window to {380, 130}
        close
    end tell
end tell
OSA

# Unmount
hdiutil detach /Volumes/Daily -force >/dev/null 2>&1
sleep 1

# Convert to compressed DMG
mkdir -p "$project_dir/build"
hdiutil convert "$tmp_dmg" -format UDZO -imagekey zlib-level=9 -o "$dmg_path" >/dev/null 2>&1
rm -f "$tmp_dmg"

echo "Done: $dmg_path"
ls -lh "$dmg_path"