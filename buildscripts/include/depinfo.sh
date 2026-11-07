#!/bin/bash -e

## Dependency versions
# Make sure to keep v_ndk and v_ndk_n in sync, both are listed on the NDK download page

v_sdk=16111833_latest
v_ndk=r30
v_ndk_n=30.0.16248370
v_sdk_platform=37.0
v_sdk_build_tools=37.0.0
v_meson=1.12.1

v_lua=5.2.4
v_unibreak=8.0
v_harfbuzz=15.1.0
v_fribidi=1.0.18
v_freetype=2.15.0
v_libressl=4.4.0
v_libxml2=2.15.4
v_fontconfig=2.18.3
v_ffmpeg=master
v_libplacebo=master
v_llvm=21.1.8
## Dependency tree
# I would've used a dict but putting arrays in a dict is not a thing

dep_libressl=()
dep_libxml2=()
dep_dav1d=()
dep_llvm=()
dep_ffmpeg=(libressl dav1d libxml2 llvm)
dep_freetype2=()
dep_fontconfig=(libxml2 freetype2)
dep_fribidi=()
dep_harfbuzz=()
dep_unibreak=()
dep_libass=(freetype2 fontconfig fribidi harfbuzz unibreak)
dep_lua=()
dep_libplacebo=()
if [[ -n "${LIBASS_ANDROID_PROVIDER_AAR:-}" ]]; then
	dep_mpv=(ffmpeg lua libplacebo)
else
	dep_mpv=(ffmpeg libass lua libplacebo)
fi
dep_mpv_android=(mpv)
