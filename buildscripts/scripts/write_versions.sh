#!/usr/bin/env bash
set -euo pipefail

# Credit goes to jmir1
ndk_suffix="${1:-}"
# get versions from source code
MPV_VERSION=$(cat "buildscripts/deps/mpv/_build${ndk_suffix}/common/version.h" | grep "#define VERSION" | cut -d '"' -f 2)
LIBPLACEBO_VERSION=$(cat "buildscripts/deps/libplacebo/_build${ndk_suffix}/src/version.h" | grep "#define BUILD_VERSION" | cut -d '"' -f 2)
FFMPEG_VERSION=$(sed -n 's/^#define FFMPEG_VERSION "\(.*\)"/\1/p' "buildscripts/deps/ffmpeg/_build${ndk_suffix}/libavutil/ffversion.h")
[[ -n "$FFMPEG_VERSION" ]]
# Read the compiler date from the final library. With LTO enabled the
# intermediate version object does not reliably expose its string data.
DATE=$(buildscripts/scripts/extract-build-date.sh "buildscripts/deps/mpv/_build${ndk_suffix}/libmpv.so")
[[ -n "$DATE" ]]
# write versions to Utils.kt
sed -i "s/%MPV_VERSION%/$MPV_VERSION/g" lib/src/main/java/is/xyz/mpv/Utils.kt
sed -i "s/%LIBPLACEBO_VERSION%/$LIBPLACEBO_VERSION/g" lib/src/main/java/is/xyz/mpv/Utils.kt
sed -i "s/%FFMPEG_VERSION%/$FFMPEG_VERSION/g" lib/src/main/java/is/xyz/mpv/Utils.kt
sed -i "s/%DATE%/$DATE/g" lib/src/main/java/is/xyz/mpv/Utils.kt
