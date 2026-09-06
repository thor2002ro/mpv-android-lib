#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
libass_provider_aar="${LIBASS_ANDROID_PROVIDER_AAR:-$repo_dir/../libass-android/OUTPUT/lib_ass-release.aar}"
if [[ "$libass_provider_aar" != /* ]]; then
	libass_provider_aar="$PWD/$libass_provider_aar"
fi
requested_provider_aar="$libass_provider_aar"
if ! libass_provider_dir="$(cd "$(dirname "$libass_provider_aar")" 2>/dev/null && pwd -P)"; then
	echo "Provider AAR not found: $requested_provider_aar" >&2
	exit 1
fi
libass_provider_aar="$libass_provider_dir/$(basename "$libass_provider_aar")"
[[ -f "$libass_provider_aar" ]] || {
	echo "Provider AAR not found: $requested_provider_aar" >&2
	exit 1
}
export LIBASS_ANDROID_PROVIDER_AAR="$libass_provider_aar"
libass_metadata="$(unzip -p "$libass_provider_aar" META-INF/libass-android-provider.properties | tr -d '\r')"
libass_group="$(sed -n 's/^group=//p' <<<"$libass_metadata")"
libass_artifact="$(sed -n 's/^artifact=//p' <<<"$libass_metadata")"
libass_version="$(sed -n 's/^version=//p' <<<"$libass_metadata")"
[[ "$libass_group" == io.github.peerless2012 && "$libass_artifact" == libass-android-provider ]] || {
	echo "Invalid shared libass provider identity." >&2
	exit 1
}
[[ "$libass_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+-thor\.[0-9a-f]{12}$ ]] || {
	echo "Invalid shared libass provider version: $libass_version" >&2
	exit 1
}
libass_maven_relative="${libass_group//.//}/$libass_artifact/$libass_version"
libass_provider_pom="$libass_provider_dir/maven/$libass_maven_relative/$libass_artifact-$libass_version.pom"
if [[ ! -f "$libass_provider_pom" ]]; then
	libass_provider_pom="${libass_provider_aar%.aar}.pom"
fi
[[ -f "$libass_provider_pom" ]] || {
	echo "Provider POM not found for $libass_provider_aar" >&2
	exit 1
}
grep -Fq "<groupId>$libass_group</groupId>" "$libass_provider_pom" &&
	grep -Fq "<artifactId>$libass_artifact</artifactId>" "$libass_provider_pom" &&
	grep -Fq "<version>$libass_version</version>" "$libass_provider_pom" || {
	echo "Provider POM does not match $libass_group:$libass_artifact:$libass_version" >&2
	exit 1
}
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

libass_build_repository="$work_dir/libass-maven"
libass_build_version_dir="$libass_build_repository/$libass_maven_relative"
mkdir -p "$libass_build_version_dir"
cp "$libass_provider_aar" "$libass_build_version_dir/$libass_artifact-$libass_version.aar"
cp "$libass_provider_pom" "$libass_build_version_dir/$libass_artifact-$libass_version.pom"
libass_build_properties="$work_dir/libass-provider.properties"
printf '%s\n' "$libass_metadata" > "$libass_build_properties"
export ORG_GRADLE_PROJECT_libassProviderRepository="$libass_build_repository"
export ORG_GRADLE_PROJECT_libassProviderProperties="$libass_build_properties"

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
mapfile -t ffmpeg_provider_aars < <(find "$work_dir/ffmpeg/build/outputs/aar" -maxdepth 1 -name '*-release.aar' -type f)
(( ${#ffmpeg_provider_aars[@]} == 1 )) || {
	echo "Expected one FFmpeg provider release AAR, found ${#ffmpeg_provider_aars[@]}." >&2
	exit 1
}
mpv_aar="${mpv_aars[0]}"
ffmpeg_provider_aar="${ffmpeg_provider_aars[0]}"
if unzip -Z1 "$mpv_aar" | grep -Eq '^jni/[^/]+/libc\+\+_shared\.so$'; then
	echo "MPV AAR must use libc++_shared.so from the shared libass provider." >&2
	exit 1
fi

cd "$work_dir"
./gradlew --no-daemon \
	:lib:generatePomFileForMavenPublication \
	:ffmpeg:generatePomFileForMavenPublication
mpv_pom="$work_dir/lib/build/publications/maven/pom-default.xml"
ffmpeg_provider_pom="$work_dir/ffmpeg/build/publications/maven/pom-default.xml"
mpv_version=$(sed -n 's|.*<version>\([^<]*\)</version>.*|\1|p' "$mpv_pom" | head -n 1)
ffmpeg_provider_version=$(sed -n 's|.*<version>\([^<]*\)</version>.*|\1|p' "$ffmpeg_provider_pom" | head -n 1)
[[ -n "$mpv_version" ]] || {
	echo "Couldn't read the MPV library version from $mpv_pom." >&2
	exit 1
}
[[ "$ffmpeg_provider_version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?-thor\.[0-9a-f]{12}$ ]] || {
	echo "Couldn't read a commit-pinned provider version from $ffmpeg_provider_pom." >&2
	exit 1
}

jar --update --file "$ffmpeg_provider_aar" \
	-C "$work_dir/ffmpeg/src/main/generated" META-INF \
	-C "$work_dir/ffmpeg/src/main/generated" prefab
"$repo_dir/buildscripts/scripts/validate-ffmpeg-provider-aar.sh" "$ffmpeg_provider_aar"
"$repo_dir/buildscripts/scripts/validate-dovi-aar.sh" "$mpv_aar"
grep -Fq '<artifactId>mpv-ffmpeg-android</artifactId>' "$mpv_pom" || {
	echo "MPV POM does not depend on the FFmpeg provider." >&2
	exit 1
}
grep -Fq "<version>$ffmpeg_provider_version</version>" "$mpv_pom" || {
	echo "MPV POM does not pin FFmpeg provider $ffmpeg_provider_version." >&2
	exit 1
}
[[ "$(grep -c "<artifactId>$libass_artifact</artifactId>" "$mpv_pom")" -eq 1 ]] || {
	echo "MPV POM does not contain exactly one shared libass dependency." >&2
	exit 1
}
grep -Fq "<version>$libass_version</version>" "$mpv_pom" || {
	echo "MPV POM does not pin shared libass $libass_version." >&2
	exit 1
}

maven_root="$repo_dir/OUTPUT/maven"
mpv_staging_dir="$work_dir/maven-stage/io/github/abdallahmehiz/mpv-android-lib/$mpv_version"
ffmpeg_provider_staging_dir="$work_dir/maven-stage/io/github/abdallahmehiz/mpv-ffmpeg-android/$ffmpeg_provider_version"
mkdir -p "$mpv_staging_dir" "$ffmpeg_provider_staging_dir"
cp "$mpv_aar" "$mpv_staging_dir/mpv-android-lib-$mpv_version.aar"
cp "$mpv_pom" "$mpv_staging_dir/mpv-android-lib-$mpv_version.pom"
cp "$ffmpeg_provider_aar" "$ffmpeg_provider_staging_dir/mpv-ffmpeg-android-$ffmpeg_provider_version.aar"
cp "$ffmpeg_provider_pom" "$ffmpeg_provider_staging_dir/mpv-ffmpeg-android-$ffmpeg_provider_version.pom"

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
echo "Created $maven_root/io/github/abdallahmehiz/mpv-ffmpeg-android/$ffmpeg_provider_version"
