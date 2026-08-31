#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: validate-ffmpeg-provider-aar.sh PROVIDER_AAR" >&2
    exit 2
fi

provider_aar="$1"
[[ -f "$provider_aar" ]] || {
    echo "Provider AAR not found: $provider_aar" >&2
    exit 1
}
command -v unzip >/dev/null || {
    echo "unzip is required to validate the provider AAR." >&2
    exit 1
}

entries="$(unzip -Z1 "$provider_aar")"
require_entry() {
    local entry="$1"
    grep -Fxq "$entry" <<<"$entries" || {
        echo "Missing provider entry: $entry" >&2
        exit 1
    }
}

metadata_entry=META-INF/mpv-ffmpeg-android.properties
require_entry "$metadata_entry"
metadata="$(unzip -p "$provider_aar" "$metadata_entry")"
for expected in \
    'group=io.github.abdallahmehiz' \
    'artifact=mpv-ffmpeg-android' \
    'ndk_version=29.0.14206865' \
    'abis=armeabi-v7a,arm64-v8a,x86,x86_64' \
    'optimization=O3,thin-lto,armv7-neon,armv7-thumb,arm64-neon'
do
    grep -Fxq "$expected" <<<"$metadata" || {
        echo "Provider metadata is missing: $expected" >&2
        exit 1
    }
done
provider_version="$(sed -n 's/^version=//p' <<<"$metadata")"
ffmpeg_version="$(sed -n 's/^ffmpeg_version=//p' <<<"$metadata")"
ffmpeg_commit="$(sed -n 's/^ffmpeg_commit=//p' <<<"$metadata")"
[[ "$ffmpeg_version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || {
    echo "Provider FFmpeg version is invalid: $ffmpeg_version" >&2
    exit 1
}
[[ "$ffmpeg_commit" =~ ^[0-9a-f]{40}$ ]] || {
    echo "Provider FFmpeg commit is invalid: $ffmpeg_commit" >&2
    exit 1
}
[[ "$provider_version" == "${ffmpeg_version}-thor.${ffmpeg_commit:0:12}" ]] || {
    echo "Provider version does not match FFmpeg $ffmpeg_version at $ffmpeg_commit: $provider_version" >&2
    exit 1
}

libraries=(avcodec avdevice avfilter avformat avutil swresample swscale)
for abi in armeabi-v7a arm64-v8a x86 x86_64; do
    for library in "${libraries[@]}"; do
        require_entry "jni/$abi/lib$library.so"
    done
done
require_entry prefab/prefab.json
require_entry prefab/modules/avcodec/include/libavcodec/version_major.h
require_entry prefab/modules/avutil/include/libavutil/avconfig.h
require_entry prefab/modules/avutil/libs/android.x86/include/libavutil/avconfig.h
require_entry prefab/modules/avutil_headers/include/libavutil/avutil.h
require_entry prefab/modules/avutil_headers/module.json
for library in "${libraries[@]}"; do
    require_entry "prefab/modules/$library/module.json"
done
if grep -Eq '^headers/|^prefab/modules/[^/]+/libs/android\.(armeabi-v7a|arm64-v8a|x86_64)/include/' <<<"$entries"; then
    echo "Provider AAR contains redundant FFmpeg headers." >&2
    exit 1
fi

decoder_manifest="$(sed -n 's/^decoders=//p' <<<"$metadata")"
for decoder in \
    aac mp3 mp1 mp2 ac3 eac3 truehd dca vorbis opus \
    amrnb amrwb flac alac pcm_mulaw pcm_alaw gsm_ms \
    h264 hevc av1 vp8 vp9 flv mpeg1video mpeg2video \
    mpeg4 msmpeg4v2 msmpeg4v3 h263 vc1 wmv1 wmv2 wmv3
do
    case ",$decoder_manifest," in
        *",$decoder,"*) ;;
        *)
            echo "Provider decoder manifest is missing: $decoder" >&2
            exit 1
            ;;
    esac
done

echo "Validated FFmpeg provider AAR: $provider_aar"
