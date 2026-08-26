#!/usr/bin/env bash
set -euo pipefail

legacy_prefix="j""f_""dovi"
legacy_upper="J""F_""DOVI"

is_legacy_symbol() {
	case "$1" in
		"$legacy_prefix"*|"$legacy_upper"*) return 0 ;;
		*) return 1 ;;
	esac
}

if [[ "${1:-}" == "--self-test" ]]; then
	is_legacy_symbol "${legacy_prefix}_set_mpv_request"
	is_legacy_symbol "${legacy_upper}_STATUS"
	! is_legacy_symbol dovi_get_mpv_request_v3
	echo "Dolby Vision import guard self-test passed"
	exit 0
fi

aar="${1:?usage: validate-dovi-aar.sh MPV_AAR}"
[[ -f "$aar" ]] || { echo "MPV AAR not found: $aar" >&2; exit 1; }

expected_entries=(
	jni/armeabi-v7a/libmpv.so
	jni/arm64-v8a/libmpv.so
	jni/x86/libmpv.so
	jni/x86_64/libmpv.so
)
mapfile -t archive_entries < <(unzip -Z1 "$aar" | grep -E '^jni/[^/]+/libmpv\.so$' | sort)
mapfile -t expected_sorted < <(printf '%s\n' "${expected_entries[@]}" | sort)
[[ "$(printf '%s\n' "${archive_entries[@]}")" == "$(printf '%s\n' "${expected_sorted[@]}")" ]] || {
	echo "MPV AAR must contain exactly the four supported ABI libmpv.so entries" >&2
	printf 'found: %s\n' "${archive_entries[@]}" >&2
	exit 1
}

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/mpv-dovi-aar.XXXXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
unzip -q "$aar" "${expected_entries[@]}" -d "$work_dir"
libraries=()
for entry in "${expected_entries[@]}"; do
	libraries+=("$work_dir/$entry")
done

readelf_candidates=("${LLVM_READELF:-}")
ndk_root="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
if [[ -n "$ndk_root" ]]; then
	for candidate in "$ndk_root"/toolchains/llvm/prebuilt/*/bin/llvm-readelf; do
		readelf_candidates+=("$candidate")
	done
fi
readelf_candidates+=(
	"$(command -v llvm-readelf 2>/dev/null || true)"
	"$(command -v readelf 2>/dev/null || true)"
)
readelf_tool=""
for candidate in "${readelf_candidates[@]}"; do
	if [[ -n "$candidate" && -x "$candidate" ]]; then
		readelf_tool="$candidate"
		break
	fi
done
[[ -n "$readelf_tool" ]] || {
	echo "No llvm-readelf/readelf found; set LLVM_READELF or ANDROID_NDK_HOME" >&2
	exit 1
}

required_symbols=(
	dovi_get_mpv_request_v3
	dovi_owned_buffer_free
	dovi_record_mpv_error_v3
	dovi_transform_sample_alloc
)

for library in "${libraries[@]}"; do
	dynamic_symbols="$($readelf_tool --wide --dyn-syms "$library")"
	undefined_symbols="$(awk '$7 == "UND" { print $8 }' <<<"$dynamic_symbols")"
	while IFS= read -r symbol; do
		if is_legacy_symbol "$symbol"; then
			echo "Forbidden pre-rename Dolby Vision symbol in $library" >&2
			exit 1
		fi
	done <<<"$undefined_symbols"
	for symbol in "${required_symbols[@]}"; do
		grep -Fxq "$symbol" <<<"$undefined_symbols" || {
			echo "Missing required $symbol import in $library" >&2
			exit 1
		}
	done
done

echo "Validated generation-owned Dolby Vision imports in $aar"
