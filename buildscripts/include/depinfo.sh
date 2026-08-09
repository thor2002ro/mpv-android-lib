#!/bin/bash -e

## Dependency versions
# Make sure to keep v_ndk and v_ndk_n in sync, both are listed on the NDK download page

v_sdk=11076708_latest
v_ndk=r29
v_ndk_n=29.0.14206865
v_sdk_platform=35
v_sdk_build_tools=35.0.0
v_meson=1.11.2

v_lua=5.2.4
v_unibreak=7.0
v_harfbuzz=14.3.0
v_fribidi=1.0.16
v_freetype=2.14.3
v_libressl=4.3.2
v_libxml2=2.15.3
v_fontconfig=2.18.2
v_ffmpeg=release/8.1
v_libplacebo=master
## Dependency tree
# I would've used a dict but putting arrays in a dict is not a thing

dep_libressl=()
dep_libxml2=()
dep_dav1d=()
dep_ffmpeg=(libressl dav1d libxml2)
dep_freetype2=()
dep_fontconfig=(libxml2 freetype2)
dep_fribidi=()
dep_harfbuzz=()
dep_unibreak=()
dep_libass=(freetype2 fontconfig fribidi harfbuzz unibreak)
dep_lua=()
dep_libplacebo=()
dep_mpv=(ffmpeg libass lua libplacebo)
dep_mpv_android=(mpv)
