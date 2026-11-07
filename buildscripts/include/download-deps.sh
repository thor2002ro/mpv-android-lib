#!/bin/bash -e

. ./include/depinfo.sh

[ -z "$IN_CI" ] && IN_CI=0
[ -z "$WGET" ] && WGET=wget

mkdir -p deps && cd deps

# libressl
if [ ! -d libressl ]; then
	archive="libressl-$v_libressl.tar.gz"
	$WGET "https://cdn.openbsd.org/pub/OpenBSD/LibreSSL/$archive"
	$WGET https://cdn.openbsd.org/pub/OpenBSD/LibreSSL/SHA256 -O SHA256.libressl
	expected=$(sed -n "s/^SHA256 ($archive) = //p" SHA256.libressl)
	[[ "$expected" =~ ^[0-9a-f]{64}$ ]] || { echo "Missing published checksum for $archive" >&2; exit 1; }
	echo "$expected  $archive" | sha256sum --check --strict -
	mkdir libressl
	tar -xzf "$archive" -C libressl --strip-components=1
	rm "$archive" SHA256.libressl
fi

# libxml2
if [ ! -d libxml2 ]; then
	git clone --branch "v$v_libxml2" --depth 1 https://gitlab.gnome.org/GNOME/libxml2.git libxml2
fi

# dav1d
[ ! -d dav1d ] && git clone --depth 1 https://github.com/videolan/dav1d

# LLVM's assembler runs on the Android target, independently of the NDK compiler.
if [ ! -d llvm ]; then
	git clone --branch "llvmorg-$v_llvm" --depth 1 https://github.com/llvm/llvm-project.git llvm
fi

# ffmpeg
if [ ! -d ffmpeg ]; then
    git clone --branch "$v_ffmpeg" --depth 1 https://github.com/FFmpeg/FFmpeg ffmpeg
else
    git -C ffmpeg fetch --depth 1 origin "$v_ffmpeg"
    git -C ffmpeg reset --hard FETCH_HEAD
    git -C ffmpeg clean -fdx
fi
for patch_file in "$(realpath ../patches/ffmpeg)"/*.patch; do
	if git -C ffmpeg apply --check "$patch_file"; then
		git -C ffmpeg apply "$patch_file"
	elif ! git -C ffmpeg apply --reverse --check "$patch_file"; then
		echo >&2 "Unable to apply FFmpeg patch: $patch_file"
		exit 1
	fi
done
# freetype2
[ ! -d freetype2 ] && git clone --depth 1 --recurse-submodules https://gitlab.freedesktop.org/freetype/freetype.git freetype2 -b VER-${v_freetype//./-}

# fontconfig
if [ ! -d fontconfig ]; then
	git clone --branch "$v_fontconfig" --depth 1 https://gitlab.freedesktop.org/fontconfig/fontconfig.git fontconfig
fi

# fribidi
if [ ! -d fribidi ]; then
	git clone --branch "v$v_fribidi" --depth 1 https://github.com/fribidi/fribidi.git fribidi
fi

# harfbuzz
if [ ! -d harfbuzz ]; then
	git clone --branch "$v_harfbuzz" --depth 1 https://github.com/harfbuzz/harfbuzz.git harfbuzz
fi

# unibreak
if [ ! -d unibreak ]; then
	git clone --branch "libunibreak_${v_unibreak//./_}" --depth 1 https://github.com/adah1972/libunibreak.git unibreak
fi

# libass is built from source unless a shared provider AAR was selected.
if [[ -z "${LIBASS_ANDROID_PROVIDER_AAR:-}" && ! -d libass ]]; then
	git clone --depth 1 https://github.com/libass/libass
fi

# lua
[ ! -d lua ] && git clone --depth 1 --branch v5-2 https://github.com/lua/lua

# libplacebo
if [ ! -d libplacebo ]; then
	git clone --branch "$v_libplacebo" --depth 1 --recursive https://github.com/haasn/libplacebo
else
	git -C libplacebo fetch --depth 1 origin "$v_libplacebo"
	git -C libplacebo reset --hard FETCH_HEAD
	git -C libplacebo submodule sync --recursive
	git -C libplacebo submodule update --init --recursive --depth 1
fi

# mpv
if [ ! -d mpv ]; then
	git clone --depth 1 https://github.com/mpv-player/mpv
else
	git -C mpv fetch --depth 1 origin master
	git -C mpv reset --hard FETCH_HEAD
    git -C mpv clean -fdx
fi
for patch_file in "$(realpath ../patches/mpv)"/*.patch; do
	if git -C mpv apply --check "$patch_file"; then
		git -C mpv apply "$patch_file"
	elif ! git -C mpv apply --reverse --check "$patch_file"; then
		echo >&2 "Unable to apply mpv patch: $patch_file"
		exit 1
	fi
done

cd ..
