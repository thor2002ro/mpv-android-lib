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

mapfile -t mpv_aars < <(find "$work_dir/lib/build/outputs/aar" -maxdepth 1 -name '*-release.aar' -type f)
(( ${#mpv_aars[@]} == 1 )) || {
	echo "Expected one MPV release AAR, found ${#mpv_aars[@]}." >&2
	exit 1
}
mapfile -t provider_aars < <(find "$work_dir/ffmpeg/build/outputs/aar" -maxdepth 1 -name '*-release.aar' -type f)
(( ${#provider_aars[@]} == 1 )) || {
	echo "Expected one FFmpeg provider release AAR, found ${#provider_aars[@]}." >&2
	exit 1
}
mpv_aar="${mpv_aars[0]}"
provider_aar="${provider_aars[0]}"

cd "$work_dir"
./gradlew --no-daemon \
	:lib:generatePomFileForMavenPublication \
	:ffmpeg:generatePomFileForMavenPublication
mpv_pom="$work_dir/lib/build/publications/maven/pom-default.xml"
provider_pom="$work_dir/ffmpeg/build/publications/maven/pom-default.xml"
mpv_version=$(sed -n 's|.*<version>\([^<]*\)</version>.*|\1|p' "$mpv_pom" | head -n 1)
provider_version=$(sed -n 's|.*<version>\([^<]*\)</version>.*|\1|p' "$provider_pom" | head -n 1)
[[ -n "$mpv_version" ]] || {
	echo "Couldn't read the MPV library version from $mpv_pom." >&2
	exit 1
}
[[ "$provider_version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?-thor\.[0-9a-f]{12}$ ]] || {
	echo "Couldn't read a commit-pinned provider version from $provider_pom." >&2
	exit 1
}

jar --update --file "$provider_aar" \
	-C "$work_dir/ffmpeg/src/main/generated" META-INF \
	-C "$work_dir/ffmpeg/src/main/generated" prefab
"$repo_dir/buildscripts/scripts/validate-ffmpeg-provider-aar.sh" "$provider_aar"
"$repo_dir/buildscripts/scripts/validate-dovi-aar.sh" "$mpv_aar"
grep -Fq '<artifactId>mpv-ffmpeg-android</artifactId>' "$mpv_pom" || {
	echo "MPV POM does not depend on the FFmpeg provider." >&2
	exit 1
}
grep -Fq "<version>$provider_version</version>" "$mpv_pom" || {
	echo "MPV POM does not pin FFmpeg provider $provider_version." >&2
	exit 1
}

maven_root="$repo_dir/OUTPUT/maven"
mpv_staging_dir="$work_dir/maven-stage/io/github/abdallahmehiz/mpv-android-lib/$mpv_version"
provider_staging_dir="$work_dir/maven-stage/io/github/abdallahmehiz/mpv-ffmpeg-android/$provider_version"
mkdir -p "$mpv_staging_dir" "$provider_staging_dir"
cp "$mpv_aar" "$mpv_staging_dir/mpv-android-lib-$mpv_version.aar"
cp "$mpv_pom" "$mpv_staging_dir/mpv-android-lib-$mpv_version.pom"
cp "$provider_aar" "$provider_staging_dir/mpv-ffmpeg-android-$provider_version.aar"
cp "$provider_pom" "$provider_staging_dir/mpv-ffmpeg-android-$provider_version.pom"

pending_root="$repo_dir/OUTPUT/maven.pending"
rm -rf "$pending_root"
mkdir -p "$pending_root"
cp -R "$work_dir/maven-stage/." "$pending_root/"
"$repo_dir/buildscripts/scripts/publish-maven-tree.sh" \
	"$pending_root" \
	"$maven_root" \
	"io/github/abdallahmehiz/mpv-android-lib/$mpv_version/mpv-android-lib-$mpv_version.aar" \
	"$repo_dir/buildscripts/scripts/validate-dovi-aar.sh"
echo "Created $maven_root/io/github/abdallahmehiz/mpv-android-lib/$mpv_version"
echo "Created $maven_root/io/github/abdallahmehiz/mpv-ffmpeg-android/$provider_version"
