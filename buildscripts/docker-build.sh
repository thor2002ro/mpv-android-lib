#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
sdk_root="${LIBDOVI_ANDROID_SDK:-$PROJECT_DIR/../libdovi-android/OUTPUT/sdk}"
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
        if [ ! -f "$input" ]; then
            echo "Missing standalone libdovi Android SDK input: $input" >&2
            exit 1
        fi
    done
done

echo "building Docker image..."
docker build -t mpv-android-builder "$SCRIPT_DIR"

echo "starting the container..."
# forward all arguments
docker run --rm \
    -v "$PROJECT_DIR:/home/mpvbuilder/mpv-android" \
    -v "$sdk_root:/opt/libdovi-android-sdk:ro" \
    -e LIBDOVI_ANDROID_SDK=/opt/libdovi-android-sdk \
    --env-file <(cat <<EOF
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ANDROID_HOME=/opt/android-sdk
ANDROID_NDK_HOME=/opt/android-sdk/ndk-bundle
EOF
) \
    mpv-android-builder "$@"
