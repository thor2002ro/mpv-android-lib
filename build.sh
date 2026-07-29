#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work_dir="${XDG_CACHE_HOME:-$HOME/.cache}/mpv-android-lib"
mkdir -p "$work_dir"

# source overlays preserve expensive native caches; remove work_dir for a pristine build.
tar \
	--exclude=.git \
	--exclude=.gradle \
	--exclude=OUTPUT \
	--exclude='*/build' \
	-C "$repo_dir" -cf - . | tar -C "$work_dir" -xf -

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

mkdir -p "$repo_dir/OUTPUT"
rm -f "$repo_dir"/OUTPUT/*.aar
cp "${aars[0]}" "$repo_dir/OUTPUT/mpv-android-lib-release.aar"
echo "Created $repo_dir/OUTPUT/mpv-android-lib-release.aar"
