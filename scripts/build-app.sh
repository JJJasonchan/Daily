#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_dir="$(cd -- "$script_dir/.." && pwd -P)"
build_dir="$project_dir/build"
app_dir="$build_dir/Daily.app"
staging_dir="$build_dir/.Daily.app.staging"
plist_path="$project_dir/Sources/DailyApp/Resources/Info.plist"

reject_symlink() {
    local path="$1"
    if [[ -L "$path" ]]; then
        echo "Refusing symbolic link: $path" >&2
        exit 1
    fi
}

remove_controlled_directory() {
    local path="$1"
    local expected_name="$2"

    reject_symlink "$path"
    [[ -e "$path" ]] || return 0
    if [[ ! -d "$path" ]]; then
        echo "Refusing non-directory build target: $path" >&2
        exit 1
    fi
    if [[ "$(basename -- "$path")" != "$expected_name" ]] || \
       [[ "$(cd -- "$(dirname -- "$path")" && pwd -P)" != "$build_dir" ]]; then
        echo "Refusing unsafe build target: $path" >&2
        exit 1
    fi
    rm -R -- "$path"
}

reject_symlink "$build_dir"
reject_symlink "$staging_dir"
reject_symlink "$app_dir"

cd -- "$project_dir"
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"

mkdir -p -- "$build_dir"
build_dir="$(cd -- "$build_dir" && pwd -P)"
app_dir="$build_dir/Daily.app"
staging_dir="$build_dir/.Daily.app.staging"
remove_controlled_directory "$staging_dir" ".Daily.app.staging"
mkdir -p -- "$staging_dir/Contents/MacOS" "$staging_dir/Contents/Resources"
install -m 755 -- "$binary_dir/Daily" "$staging_dir/Contents/MacOS/Daily"
install_name_tool -add_rpath @executable_path/../Frameworks "$staging_dir/Contents/MacOS/Daily"
install -m 644 -- "$plist_path" "$staging_dir/Contents/Info.plist"
install -m 644 -- "$project_dir/Sources/DailyApp/Resources/AppIcon.icns" "$staging_dir/Contents/Resources/AppIcon.icns"
mkdir -p "$staging_dir/Contents/Frameworks"
cp -R "$binary_dir/Sparkle.framework" "$staging_dir/Contents/Frameworks/"

codesign --force --deep --sign - "$staging_dir"
codesign --verify --deep --strict "$staging_dir"

remove_controlled_directory "$app_dir" "Daily.app"
mv -- "$staging_dir" "$app_dir"
codesign --verify --deep --strict "$app_dir"
printf '%s\n' "$app_dir"
