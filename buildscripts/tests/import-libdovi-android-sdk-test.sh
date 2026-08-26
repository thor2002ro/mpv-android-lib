#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d -t mpv-libdovi-import-tests.XXXXXXXX)"

cleanup() {
    rm -rf -- "$test_root"
}
trap cleanup EXIT INT TERM

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

write_sdk() {
    local sdk_root="$1"
    local version="${2:-}"
    local abi_root="$sdk_root/armeabi-v7a"
    mkdir -p "$abi_root/include" "$abi_root/lib/pkgconfig"
    touch "$abi_root/include/dovi.h" "$abi_root/lib/libjellyfin_dovi.so"
    printf '%s\n' \
        'prefix=/source-sdk' \
        'libdir=${prefix}/lib' \
        'includedir=${prefix}/include' \
        '' \
        'Name: jellyfin-dovi' \
        'Description: test package' \
        > "$abi_root/lib/pkgconfig/jellyfin-dovi.pc"
    [[ -n "$version" ]] && printf 'Version: %s\n' "$version" >> "$abi_root/lib/pkgconfig/jellyfin-dovi.pc"
    printf '%s\n' \
        'Libs: -L${libdir} -ljellyfin_dovi' \
        'Cflags: -I${includedir}' \
        >> "$abi_root/lib/pkgconfig/jellyfin-dovi.pc"
}

run_import() {
    local sdk_root="$1"
    local prefix_root="$2"
    LIBDOVI_ANDROID_SDK="$sdk_root" \
        android_abi=armeabi-v7a \
        prefix_dir="$prefix_root" \
        bash "$repository_root/buildscripts/scripts/import-libdovi-android-sdk.sh"
}

missing_sdk="$test_root/missing-version-sdk"
write_sdk "$missing_sdk"
if missing_output="$(run_import "$missing_sdk" "$test_root/missing-prefix" 2>&1)"; then
    fail "import accepted pkg-config metadata without a version"
fi
[[ "$missing_output" == *"Missing pkg-config Version"* ]] || \
    fail "missing version failure was not actionable: $missing_output"

valid_sdk="$test_root/valid-sdk"
valid_prefix="$test_root/valid-prefix"
write_sdk "$valid_sdk" '0.1.0-SNAPSHOT'
run_import "$valid_sdk" "$valid_prefix"
imported_pc="$valid_prefix/lib/pkgconfig/jellyfin-dovi.pc"
[[ -f "$imported_pc" ]] || fail "import did not create jellyfin-dovi.pc"
[[ "$(sed -n 's/^Version:[[:space:]]*//p' "$imported_pc")" == '0.1.0-SNAPSHOT' ]] || \
    fail "import did not preserve the SDK package version"
[[ "$(sed -n 's/^prefix=//p' "$imported_pc")" == '/usr/local' ]] || \
    fail "import did not relocate the package prefix"

echo "MPV libdovi SDK import contracts passed"
