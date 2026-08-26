#!/bin/bash -e

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mpv_root="$(cd "$script_dir/../.." && pwd)"

case "${android_abi:-${prefix_dir##*/}}" in
	armeabi-v7a|armv7l) android_abi=armeabi-v7a ;;
	arm64-v8a|arm64) android_abi=arm64-v8a ;;
	x86) android_abi=x86 ;;
	x86_64) android_abi=x86_64 ;;
	*)
		echo "Cannot map native prefix to an Android ABI: ${prefix_dir:-unset}" >&2
		exit 1
		;;
esac

sdk_root="${LIBDOVI_ANDROID_SDK:-$mpv_root/../libdovi-android/OUTPUT/sdk}"
sdk_abi="$sdk_root/$android_abi"
header="$sdk_abi/include/dovi.h"
library="$sdk_abi/lib/libjellyfin_dovi.so"
pkg_config="$sdk_abi/lib/pkgconfig/jellyfin-dovi.pc"

for input in "$header" "$library" "$pkg_config"; do
	if [ ! -f "$input" ]; then
		echo "Missing standalone libdovi Android SDK input: $input" >&2
		exit 1
	fi
done

package_version="$(sed -n 's/^Version:[[:space:]]*//p' "$pkg_config" | head -n 1)"
if [ -z "$package_version" ]; then
	echo "Missing pkg-config Version: $pkg_config" >&2
	exit 1
fi

mkdir -p "$prefix_dir/include" "$prefix_dir/lib/pkgconfig"
cp "$header" "$prefix_dir/include/dovi.h"
cp "$library" "$prefix_dir/lib/libjellyfin_dovi.so"
cat >"$prefix_dir/lib/pkgconfig/jellyfin-dovi.pc" <<EOF
prefix=/usr/local
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: jellyfin-dovi
Description: Jellyfin Dolby Vision RPU conversion bridge
Version: $package_version
Libs: -L\${libdir} -ljellyfin_dovi
Cflags: -I\${includedir}
EOF
