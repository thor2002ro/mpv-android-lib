#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/../include/depinfo.sh"
[[ "$v_ndk_n" =~ ^[0-9]+(\.[0-9]+)+$ ]] || {
	echo "Configured MPV NDK version is invalid: $v_ndk_n" >&2
	exit 1
}

provider_aar="${LIBASS_ANDROID_PROVIDER_AAR:-}"
[[ -n "$provider_aar" && -f "$provider_aar" ]] || {
	echo "Provider AAR not found: ${provider_aar:-unset}" >&2
	exit 1
}
[[ -n "${prefix_dir:-}" && "$prefix_dir" != / ]] || {
	echo "A safe MPV prefix directory is required." >&2
	exit 1
}
command -v unzip >/dev/null || {
	echo "unzip is required to import the provider AAR." >&2
	exit 1
}

case "${android_abi:-${prefix_dir##*/}}" in
	armeabi-v7a|armv7l) android_abi=armeabi-v7a ;;
	arm64-v8a|arm64) android_abi=arm64-v8a ;;
	x86) android_abi=x86 ;;
	x86_64) android_abi=x86_64 ;;
	*)
		echo "Cannot map native prefix to an Android ABI: $prefix_dir" >&2
		exit 1
		;;
esac

entries="$(unzip -Z1 "$provider_aar")"
require_entry() {
	local entry="$1"
	grep -Fxq "$entry" <<<"$entries" || {
		echo "Missing provider entry: $entry" >&2
		exit 1
	}
}

metadata_entry=META-INF/libass-android-provider.properties
require_entry "$metadata_entry"
metadata="$(unzip -p "$provider_aar" "$metadata_entry" | tr -d '\r')"
for expected in \
	'group=io.github.peerless2012' \
	'artifact=libass-android-provider' \
	"ndk_version=$v_ndk_n" \
	'abis=armeabi-v7a,arm64-v8a,x86,x86_64' \
	'optimization=O3,thin-lto,armv7-neon,armv7-thumb,arm64-neon'
do
	grep -Fxq "$expected" <<<"$metadata" || {
		echo "Provider metadata is missing: $expected" >&2
		exit 1
	}
done

provider_version="$(sed -n 's/^version=//p' <<<"$metadata")"
libass_version="$(sed -n 's/^libass_version=//p' <<<"$metadata")"
libass_version_hex="$(sed -n 's/^libass_version_hex=//p' <<<"$metadata")"
libass_commit="$(sed -n 's/^libass_commit=//p' <<<"$metadata")"
patch_tree="$(sed -n 's/^patch_tree=//p' <<<"$metadata")"
[[ "$libass_commit" =~ ^[0-9a-f]{40}$ ]] || {
	echo "Provider libass commit is invalid: $libass_commit" >&2
	exit 1
}
[[ "$patch_tree" =~ ^[0-9a-f]{40}$ ]] || {
	echo "Provider patch tree is invalid: $patch_tree" >&2
	exit 1
}
[[ "$libass_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
	echo "Provider libass version is invalid: $libass_version" >&2
	exit 1
}
[[ "$libass_version_hex" =~ ^0x[0-9A-Fa-f]{8}$ ]] || {
	echo "Provider hexadecimal libass version is invalid: $libass_version_hex" >&2
	exit 1
}
[[ "$provider_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+-thor\.[0-9a-f]{12}$ ]] &&
	[[ "$provider_version" == *".${libass_commit:0:12}" ]] || {
	echo "Provider version does not identify libass commit $libass_commit: $provider_version" >&2
	exit 1
}

require_entry prefab/modules/ass/include/ass/ass.h
require_entry prefab/modules/ass/include/ass/ass_types.h
for required_abi in armeabi-v7a arm64-v8a x86 x86_64; do
	require_entry "jni/$required_abi/libass.so"
	require_entry "jni/$required_abi/libc++_shared.so"
done

temporary_dir="$(mktemp -d -t mpv-libass-provider.XXXXXXXX)"
trap 'rm -rf -- "$temporary_dir"' EXIT
unzip -qq "$provider_aar" \
	"prefab/modules/ass/include/ass/ass.h" \
	"prefab/modules/ass/include/ass/ass_types.h" \
	"jni/$android_abi/libass.so" \
	-d "$temporary_dir"

mkdir -p "$prefix_dir/include/ass" "$prefix_dir/lib/pkgconfig"
cp "$temporary_dir/prefab/modules/ass/include/ass/ass.h" "$prefix_dir/include/ass/ass.h.tmp"
cp "$temporary_dir/prefab/modules/ass/include/ass/ass_types.h" "$prefix_dir/include/ass/ass_types.h.tmp"
cp "$temporary_dir/jni/$android_abi/libass.so" "$prefix_dir/lib/libass.so.tmp"
cat > "$prefix_dir/lib/pkgconfig/libass.pc.tmp" <<EOF
prefix=/usr/local
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: libass
Description: Canonical patched Android libass provider
Version: $libass_version
Libs: -L\${libdir} -lass
Cflags: -I\${includedir}
EOF
mv "$prefix_dir/include/ass/ass.h.tmp" "$prefix_dir/include/ass/ass.h"
mv "$prefix_dir/include/ass/ass_types.h.tmp" "$prefix_dir/include/ass/ass_types.h"
mv "$prefix_dir/lib/libass.so.tmp" "$prefix_dir/lib/libass.so"
mv "$prefix_dir/lib/pkgconfig/libass.pc.tmp" "$prefix_dir/lib/pkgconfig/libass.pc"
