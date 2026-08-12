#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source_project="$(cd -- "$script_dir/.." && pwd -P)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/daily-build-test.XXXXXX")"

cleanup() {
    rm -R -- "$test_root"
}
trap cleanup EXIT

workspace="$test_root/Project With Spaces"
external="$test_root/external"
fake_bin="$test_root/fake-bin"
mkdir -p -- "$workspace/scripts" "$workspace/Sources/DailyApp/Resources" "$external" "$fake_bin"
cp -- "$source_project/scripts/build-app.sh" "$workspace/scripts/build-app.sh"
cp -- "$source_project/Sources/DailyApp/Resources/Info.plist" "$workspace/Sources/DailyApp/Resources/Info.plist"
printf 'sentinel\n' > "$external/sentinel"
ln -s -- "$external" "$workspace/build"

printf '%s\n' \
    '#!/usr/bin/env bash' \
    'if [[ "${*: -1}" == "--show-bin-path" ]]; then' \
    '    printf '\''%s\n'\'' "${FAKE_BINARY_DIR:?}"' \
    'fi' > "$fake_bin/swift"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/codesign"
chmod +x "$fake_bin/swift" "$fake_bin/codesign"

set +e
PATH="$fake_bin:$PATH" FAKE_BINARY_DIR="$test_root/binary" \
    bash "$workspace/scripts/build-app.sh" > "$test_root/stdout" 2> "$test_root/stderr"
status=$?
set -e

if [[ $status -eq 0 ]]; then
    echo "expected symlinked build directory to be rejected" >&2
    exit 1
fi
if [[ ! -f "$external/sentinel" ]]; then
    echo "external sentinel was removed" >&2
    exit 1
fi
if [[ -e "$external/Daily.app" || -e "$external/.Daily.app.staging" ]]; then
    echo "script wrote through build symlink" >&2
    exit 1
fi

echo "SYMLINK_ESCAPE_REJECTED"
