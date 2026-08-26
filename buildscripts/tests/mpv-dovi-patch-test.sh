#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
patch_file="$repository_root/buildscripts/patches/mpv/0003-convert-dovi-profile7-to-profile81.patch"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

grep -Fq '+#include <libavcodec/codec_par.h>' "$patch_file" ||
    fail "Dolby Vision conversion source does not include the AVCodecParameters definition"

grep -Fq '+    dovi_record_mpv_transform_v3(generation,' "$patch_file" ||
    fail "Dolby Vision conversion source does not record successful MPV transforms"

source_line_count="$(git apply --numstat "$patch_file" |
    awk '$3 == "demux/dovi_profile_convert.c" { print $1 }')"
[[ "$source_line_count" == 320 ]] ||
    fail "Dolby Vision conversion patch has inconsistent source hunk metadata"

echo "MPV Dolby Vision patch contracts passed"
