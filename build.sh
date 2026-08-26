#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sdk_root="${LIBDOVI_ANDROID_SDK:-$repo_dir/../libdovi-android/OUTPUT/sdk}"
if [[ "$sdk_root" != /* ]]; then
	sdk_root="$PWD/$sdk_root"
fi
requested_sdk_root="$sdk_root"
if ! sdk_root="$(cd "$sdk_root" 2>/dev/null && pwd -P)"; then
	echo "Standalone libdovi Android SDK directory not found: $requested_sdk_root" >&2
	exit 1
fi
for abi in armeabi-v7a arm64-v8a x86 x86_64; do
	for input in \
		"$sdk_root/$abi/include/dovi.h" \
		"$sdk_root/$abi/lib/libjellyfin_dovi.so" \
		"$sdk_root/$abi/lib/pkgconfig/jellyfin-dovi.pc"
	do
		[[ -f "$input" ]] || {
			echo "Missing standalone libdovi Android SDK input: $input" >&2
			exit 1
		}
	done
done
export LIBDOVI_ANDROID_SDK="$sdk_root"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/mpv-android-lib.XXXXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
export GRADLE_USER_HOME="$work_dir/.gradle-user-home"

tar \
	--exclude=.git \
	--exclude=.gradle \
	--exclude=OUTPUT \
	--exclude='*/build' \
	-C "$repo_dir" -cf - . | tar -C "$work_dir" -xf -

rm -f "$work_dir/lib/src/main/assets/subfont.ttf"
find "$work_dir" -type f \( -name '*.sh' -o -name '*.patch' \) -exec sed -i 's/\r$//' {} +
sed -i 's/\r$//' "$work_dir/gradlew"
rm -f "$work_dir/lib/src/main/jniLibs"
ln -s libs "$work_dir/lib/src/main/jniLibs"

cd "$work_dir/buildscripts"
IN_CI=1 ./download.sh
for arch in armv7l arm64 x86 x86_64; do
	./buildall.sh --arch "$arch" mpv
done
./buildall.sh -n mpv-android

mapfile -t aars < <(find "$work_dir/lib/build/outputs/aar" -maxdepth 1 -name '*-release.aar' -type f)
(( ${#aars[@]} == 1 )) || {
	echo "Expected one release AAR, found ${#aars[@]}." >&2
	exit 1
}

cd "$work_dir"
./gradlew --no-daemon :lib:generatePomFileForMavenPublication
pom="$work_dir/lib/build/publications/maven/pom-default.xml"
version=$(sed -n 's|.*<version>\([^<]*\)</version>.*|\1|p' "$pom" | head -n 1)
[[ -n "$version" ]] || {
	echo "Couldn't read the library version from $pom." >&2
	exit 1
}

maven_root="$repo_dir/OUTPUT/maven"
module_root="$maven_root/io/github/abdallahmehiz/mpv-android-lib"
maven_dir="$module_root/$version"
staging_dir="$work_dir/maven-stage/$version"
mkdir -p "$staging_dir"
cp "${aars[0]}" "$staging_dir/mpv-android-lib-$version.aar"
cp "$pom" "$staging_dir/mpv-android-lib-$version.pom"
"$repo_dir/buildscripts/scripts/validate-dovi-aar.sh" "$staging_dir/mpv-android-lib-$version.aar"

pending_root="$repo_dir/OUTPUT/maven.pending"
rm -rf "$pending_root"
mkdir -p "$pending_root/io/github/abdallahmehiz/mpv-android-lib"
cp -R "$staging_dir" "$pending_root/io/github/abdallahmehiz/mpv-android-lib/$version"
"$repo_dir/buildscripts/scripts/publish-maven-tree.sh" \
	"$pending_root" \
	"$maven_root" \
	"io/github/abdallahmehiz/mpv-android-lib/$version/mpv-android-lib-$version.aar" \
	"$repo_dir/buildscripts/scripts/validate-dovi-aar.sh"
echo "Created $maven_dir" || true
