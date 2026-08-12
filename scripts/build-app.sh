#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_dir="$(cd -- "$script_dir/.." && pwd -P)"
build_dir="$project_dir/build"
app_dir="$build_dir/Daily.app"
staging_dir="$build_dir/.Daily.app.staging"
plist_path="$project_dir/Sources/DailyApp/Resources/Info.plist"

case "$staging_dir" in
    "$project_dir"/build/.Daily.app.staging) ;;
    *) echo "Refusing unsafe staging path: $staging_dir" >&2; exit 1 ;;
esac

cd -- "$project_dir"
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"

mkdir -p -- "$build_dir"
if [[ -e "$staging_dir" ]]; then
    rm -R -- "$staging_dir"
fi
mkdir -p -- "$staging_dir/Contents/MacOS" "$staging_dir/Contents/Resources"
install -m 755 -- "$binary_dir/Daily" "$staging_dir/Contents/MacOS/Daily"
install -m 644 -- "$plist_path" "$staging_dir/Contents/Info.plist"

codesign --force --deep --sign - "$staging_dir"
codesign --verify --deep --strict "$staging_dir"

if [[ -e "$app_dir" ]]; then
    case "$app_dir" in
        "$project_dir"/build/Daily.app) rm -R -- "$app_dir" ;;
        *) echo "Refusing unsafe app path: $app_dir" >&2; exit 1 ;;
    esac
fi
mv -- "$staging_dir" "$app_dir"
codesign --verify --deep --strict "$app_dir"
printf '%s\n' "$app_dir"
