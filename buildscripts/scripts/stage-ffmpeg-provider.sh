#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: stage-ffmpeg-provider.sh REPOSITORY_ROOT NDK_VERSION" >&2
    exit 2
fi

repository_root="$(cd "$1" && pwd -P)"
ndk_version="$2"
ffmpeg_repository="$repository_root/buildscripts/deps/ffmpeg"
provider_main="$repository_root/ffmpeg/src/main"
wrapper_libraries="$repository_root/lib/src/main/libs"

[[ -d "$ffmpeg_repository/.git" ]] || {
    echo "FFmpeg repository is missing: $ffmpeg_repository" >&2
    exit 1
}
[[ -d "$wrapper_libraries" ]] || {
    echo "MPV JNI library staging directory is missing: $wrapper_libraries" >&2
    exit 1
}
[[ "$provider_main" == "$repository_root/ffmpeg/src/main" ]] || {
    echo "Refusing unexpected provider staging directory: $provider_main" >&2
    exit 1
}

ffmpeg_libraries=(
    libavcodec.so libavdevice.so libavfilter.so libavformat.so
    libavutil.so libswresample.so libswscale.so
)
media3_decoders=(
    aac mp3 mp1 mp2 ac3 eac3 truehd dca vorbis opus
    amrnb amrwb flac alac pcm_mulaw pcm_alaw gsm_ms
    h264 hevc av1 vp8 vp9 flv mpeg1video mpeg2video
    mpeg4 msmpeg4v2 msmpeg4v3 h263 vc1 wmv1 wmv2 wmv3
)

ffmpeg_commit="$(git -C "$ffmpeg_repository" rev-parse HEAD)"
[[ "$ffmpeg_commit" =~ ^[0-9a-f]{40}$ ]] || {
    echo "Could not resolve the exact FFmpeg commit." >&2
    exit 1
}
[[ -f "$ffmpeg_repository/RELEASE" ]] || {
    echo "FFmpeg release file is missing: $ffmpeg_repository/RELEASE" >&2
    exit 1
}
ffmpeg_version="$(tr -d '[:space:]' < "$ffmpeg_repository/RELEASE")"
ffmpeg_version="${ffmpeg_version%.git}"
[[ "$ffmpeg_version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || {
    echo "Could not resolve the FFmpeg release version: $ffmpeg_version" >&2
    exit 1
}
provider_version="${ffmpeg_version}-thor.${ffmpeg_commit:0:12}"
prefab_version="$ffmpeg_version"
[[ "$prefab_version" == *.*.* ]] || prefab_version="$prefab_version.0"

rm -rf -- \
    "$provider_main/jniLibs" \
    "$provider_main/headers" \
    "$provider_main/generated"
mkdir -p "$provider_main/jniLibs" "$provider_main/headers" "$provider_main/generated/META-INF"

while read -r prefix_name android_abi build_suffix; do
    prefix="$repository_root/buildscripts/prefix/$prefix_name"
    config_components="$ffmpeg_repository/_build$build_suffix/config_components.h"
    wrapper_abi="$wrapper_libraries/$android_abi"
    provider_abi="$provider_main/jniLibs/$android_abi"
    provider_headers="$provider_main/headers/$android_abi"

    [[ -f "$config_components" ]] || {
        echo "FFmpeg component configuration is missing for $android_abi: $config_components" >&2
        exit 1
    }
    [[ -d "$prefix/include" ]] || {
        echo "Installed FFmpeg headers are missing for $android_abi: $prefix/include" >&2
        exit 1
    }
    mkdir -p "$provider_abi" "$provider_headers"

    for decoder in "${media3_decoders[@]}"; do
        decoder_macro="CONFIG_${decoder^^}_DECODER"
        grep -Eq "^#define[[:space:]]+$decoder_macro[[:space:]]+1$" "$config_components" || {
            echo "Missing required FFmpeg decoder $decoder for $android_abi" >&2
            exit 1
        }
    done

    for library in "${ffmpeg_libraries[@]}"; do
        source_library="$wrapper_abi/$library"
        [[ -f "$source_library" ]] || {
            echo "FFmpeg shared library is missing for $android_abi: $source_library" >&2
            exit 1
        }
        mv -- "$source_library" "$provider_abi/$library"
    done
    cp -R -- "$prefix/include/." "$provider_headers/"
done <<'EOF'
armv7l armeabi-v7a
arm64 arm64-v8a -arm64
x86 x86 -x86
x86_64 x86_64 -x64
EOF

decoders_csv="$(IFS=,; echo "${media3_decoders[*]}")"
metadata="$provider_main/generated/META-INF/mpv-ffmpeg-android.properties"
cat > "$metadata" <<EOF
group=io.github.abdallahmehiz
artifact=mpv-ffmpeg-android
version=$provider_version
ffmpeg_version=$ffmpeg_version
ffmpeg_commit=$ffmpeg_commit
ndk_version=$ndk_version
abis=armeabi-v7a,arm64-v8a,x86,x86_64
optimization=O3,thin-lto,armv7-neon,armv7-thumb,arm64-neon
decoders=$decoders_csv
EOF

cat > "$provider_main/ffmpeg-provider.properties" <<EOF
version=$provider_version
ffmpegVersion=$ffmpeg_version
ffmpegCommit=$ffmpeg_commit
ndkVersion=$ndk_version
EOF

prefab_root="$provider_main/generated/prefab"
mkdir -p "$prefab_root/modules"
cat > "$prefab_root/prefab.json" <<EOF
{
  "schema_version": 2,
  "name": "mpv_ffmpeg_android",
  "version": "$prefab_version",
  "dependencies": []
}
EOF

avutil_common="$prefab_root/modules/avutil_headers"
mkdir -p "$avutil_common/include"
cp -R -- "$provider_main/headers/arm64-v8a/libavutil" \
    "$avutil_common/include/libavutil"
rm -f -- "$avutil_common/include/libavutil/avconfig.h"
printf '{}\n' > "$avutil_common/module.json"

for library in "${ffmpeg_libraries[@]}"; do
    module="${library#lib}"
    module="${module%.so}"
    module_root="$prefab_root/modules/$module"
    mkdir -p "$module_root/libs"

    case "$module" in
        avcodec)
            export_libraries='[":avutil", ":swresample"]'
            ;;
        avdevice)
            export_libraries='[":avfilter", ":avformat", ":avcodec", ":swresample", ":swscale", ":avutil"]'
            ;;
        avfilter)
            export_libraries='[":avformat", ":avcodec", ":swresample", ":swscale", ":avutil"]'
            ;;
        avformat)
            export_libraries='[":avcodec", ":swresample", ":avutil"]'
            ;;
        avutil)
            export_libraries='[":avutil_headers"]'
            ;;
        swresample|swscale)
            export_libraries='[":avutil"]'
            ;;
    esac
    cat > "$module_root/module.json" <<EOF
{
  "export_libraries": $export_libraries
}
EOF

    header_directory="lib$module"
    common_headers="$provider_main/headers/arm64-v8a/$header_directory"
    [[ -d "$common_headers" ]] || {
        echo "FFmpeg headers are missing for Prefab module $module: $common_headers" >&2
        exit 1
    }
    if [[ "$module" == avutil ]]; then
        for android_abi in armeabi-v7a x86 x86_64; do
            candidate_headers="$provider_main/headers/$android_abi/$header_directory"
            diff -qr --exclude=avconfig.h -- "$common_headers" "$candidate_headers" >/dev/null || {
                echo "FFmpeg common avutil headers differ for $android_abi." >&2
                exit 1
            }
        done
        cmp -- "$common_headers/avconfig.h" \
            "$provider_main/headers/armeabi-v7a/$header_directory/avconfig.h"
        cmp -- "$common_headers/avconfig.h" \
            "$provider_main/headers/x86_64/$header_directory/avconfig.h"
        mkdir -p "$module_root/include/$header_directory"
        cp -- "$common_headers/avconfig.h" "$module_root/include/$header_directory/avconfig.h"
    else
        for android_abi in armeabi-v7a x86 x86_64; do
            candidate_headers="$provider_main/headers/$android_abi/$header_directory"
            diff -qr -- "$common_headers" "$candidate_headers" >/dev/null || {
                echo "FFmpeg $module headers differ for $android_abi; use ABI-specific Prefab headers." >&2
                exit 1
            }
        done
        mkdir -p "$module_root/include"
        cp -R -- "$common_headers" "$module_root/include/$header_directory"
    fi

    while read -r android_abi; do
        abi_root="$module_root/libs/android.$android_abi"
        mkdir -p "$abi_root"
        if [[ "$module" == avutil && "$android_abi" == x86 ]]; then
            mkdir -p "$abi_root/include/$header_directory"
            cp -- "$provider_main/headers/$android_abi/$header_directory/avconfig.h" \
                "$abi_root/include/$header_directory/avconfig.h"
        fi
        cp -- "$provider_main/jniLibs/$android_abi/$library" "$abi_root/$library"
        cat > "$abi_root/abi.json" <<EOF
{
  "abi": "$android_abi",
  "api": 24,
  "ndk": 29,
  "stl": "none",
  "static": false
}
EOF
    done <<'EOF'
armeabi-v7a
arm64-v8a
x86
x86_64
EOF
done

echo "Staged FFmpeg provider $provider_version"
