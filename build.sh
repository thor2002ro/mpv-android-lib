#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
find "$work_dir" -type f -name '*.sh' -exec sed -i 's/\r$//' {} +
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

maven_dir="$repo_dir/OUTPUT/maven/io/github/abdallahmehiz/mpv-android-lib/$version"
rm -rf "$repo_dir/OUTPUT/maven"
mkdir -p "$maven_dir"
cp "${aars[0]}" "$maven_dir/mpv-android-lib-$version.aar"
cp "$pom" "$maven_dir/mpv-android-lib-$version.pom"
echo "Created $maven_dir"
