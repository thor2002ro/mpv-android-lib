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

grep -Fq '+    AVBufferRef *buffer = av_buffer_create(' "$patch_file" ||
    fail "MPV does not adopt libdovi output storage"

grep -Fq '+        output.data, output_size,' "$patch_file" ||
    fail "MPV exposes decoder padding as transformed sample data"

if grep -Fq 'output_size + DOVI_OUTPUT_PADDING_SIZE' "$patch_file"; then
    fail "MPV includes decoder padding in the adopted packet size"
fi

grep -Fq '+    output.data = NULL;' "$patch_file" ||
    fail "adopted libdovi output remains owned by libdovi"

grep -Fq '+    converted = new_demux_packet_from_buf(' "$patch_file" ||
    fail "adopted libdovi output does not become the final MPV packet"

if grep -Fq '+    memcpy(converted->buffer, output.data, output.size);' "$patch_file"; then
    fail "MPV still copies the complete transformed sample"
fi

if grep -Fq '+    demux_packet_shorten(converted, output_size);' "$patch_file"; then
    fail "MPV relies on a demux length that packet copies do not preserve"
fi

source_line_count="$(git apply --numstat "$patch_file" |
    awk '$3 == "demux/dovi_profile_convert.c" { print $1 }')"
[[ "$source_line_count" == 339 ]] ||
    fail "Dolby Vision conversion patch has inconsistent source hunk metadata"

echo "MPV Dolby Vision patch contracts passed"
