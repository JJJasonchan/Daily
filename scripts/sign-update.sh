#!/usr/bin/env bash
set -euo pipefail

# Usage: bash scripts/sign-update.sh
# Requires: EdDSA keys in macOS keychain (run scripts/generate_keys first)
#           Sparkle tools in scripts/ (generate_appcast installed)

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_dir="$(cd -- "$script_dir/.." && pwd -P)"
dmg_path="$project_dir/build/Daily.dmg"
appcast_dir="$project_dir/build/appcast"

if [[ ! -f "$dmg_path" ]]; then
    echo "DMG not found: $dmg_path" >&2
    echo "Run scripts/build-app.sh and scripts/package-dmg.sh first." >&2
    exit 1
fi

# generate_appcast reads the private EdDSA key from keychain automatically
gen_appcast="$script_dir/generate_appcast"
if [[ ! -x "$gen_appcast" ]]; then
    echo "generate_appcast not found at $gen_appcast" >&2
    echo "Download from: https://github.com/sparkle-project/Sparkle/releases" >&2
    echo "Extract bin/generate_appcast to scripts/" >&2
    exit 1
fi

echo "Generating appcast for $dmg_path ..."
mkdir -p "$appcast_dir"

# Clean previous DMG in appcast dir (generate_appcast needs only the current DMG)
rm -f "$appcast_dir"/*.dmg
cp "$dmg_path" "$appcast_dir/"

# Generate appcast with EdDSA signature (key from keychain)
"$gen_appcast" --ed-key-from-keychain "$appcast_dir"

appcast_file="$appcast_dir/appcast.xml"
if [[ -f "$appcast_file" ]]; then
    echo ""
    echo "Appcast generated: $appcast_file"
    echo ""
    echo "Upload to GitHub Releases:"
    echo "  1. Create release and upload $dmg_path"
    echo "  2. Upload $appcast_file as a release asset"
    echo "  3. Or serve it from your own CDN"
else
    echo "Error: appcast.xml not generated" >&2
    exit 1
fi
