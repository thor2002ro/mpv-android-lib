#!/bin/bash -e

. ./include/depinfo.sh

[ -z "$IN_CI" ] && IN_CI=0
[ -z "$WGET" ] && WGET=wget

mkdir -p deps && cd deps

# mbedtls
if [ ! -d mbedtls ]; then
	mkdir mbedtls
	$WGET https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-$v_mbedtls/mbedtls-$v_mbedtls.tar.bz2 -O - | \
		tar -xj -C mbedtls --strip-components=1
fi

# libxml2
if [ ! -d libxml2 ]; then
	mkdir libxml2
	$WGET https://gitlab.gnome.org/GNOME/libxml2/-/archive/v$v_libxml2/libxml2-v$v_libxml2.tar.gz -O - | \
		tar -xz -C libxml2 --strip-components=1
fi

# dav1d
[ ! -d dav1d ] && git clone --depth 1 https://github.com/videolan/dav1d

# ffmpeg
if [ ! -d ffmpeg ]; then
    if [ $IN_CI -eq 1 ]; then
        git clone --branch $v_ci_ffmpeg --depth 1 https://github.com/FFmpeg/FFmpeg ffmpeg
    else
        git clone --depth 1 https://github.com/FFmpeg/FFmpeg ffmpeg
    fi
fi

# freetype2
[ ! -d freetype2 ] && git clone --depth 1 --recurse-submodules https://gitlab.freedesktop.org/freetype/freetype.git freetype2 -b VER-${v_freetype//./-}

# fontconfig
if [ ! -d fontconfig ]; then
	mkdir fontconfig
	$WGET https://gitlab.freedesktop.org/fontconfig/fontconfig/-/archive/${v_fontconfig}/fontconfig-${v_fontconfig}.tar.gz -O - | \
		tar -xz -C fontconfig --strip-components=1
fi

# fribidi
if [ ! -d fribidi ]; then
	mkdir fribidi
	$WGET https://github.com/fribidi/fribidi/releases/download/v$v_fribidi/fribidi-$v_fribidi.tar.xz -O - | \
		tar -xJ -C fribidi --strip-components=1
fi

# harfbuzz
if [ ! -d harfbuzz ]; then
	mkdir harfbuzz
	$WGET https://github.com/harfbuzz/harfbuzz/releases/download/$v_harfbuzz/harfbuzz-$v_harfbuzz.tar.xz -O - | \
		tar -xJ -C harfbuzz --strip-components=1
fi

# unibreak
if [ ! -d unibreak ]; then
	mkdir unibreak
	$WGET https://github.com/adah1972/libunibreak/releases/download/libunibreak_${v_unibreak//./_}/libunibreak-${v_unibreak}.tar.gz -O - | \
		tar -xz -C unibreak --strip-components=1
fi

# libass
[ ! -d libass ] && git clone --depth 1 https://github.com/libass/libass

# lua
[ ! -d lua ] && git clone --depth 1 --branch v5-2 https://github.com/lua/lua

# libplacebo
[ ! -d libplacebo ] && git clone --depth 1 --recursive https://github.com/haasn/libplacebo

# mpv
if [ ! -d mpv ]; then
	git clone --depth 1 https://github.com/mpv-player/mpv
else
	git -C mpv fetch --depth 1 origin master
	git -C mpv reset --hard FETCH_HEAD
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
