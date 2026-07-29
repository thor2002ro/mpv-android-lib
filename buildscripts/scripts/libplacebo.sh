#!/bin/bash -e

. ../../include/path.sh

build=_build$ndk_suffix

if [ "$1" == "build" ]; then
	true
elif [ "$1" == "clean" ]; then
	rm -rf $build
	exit 0
else
	exit 255
fi

unset CC CXX

shaderc_build="$prefix_dir/shaderc"
case "$ndk_triple" in
	arm-*) abi=armeabi-v7a ;;
	aarch64-*) abi=arm64-v8a ;;
	i686-*) abi=x86 ;;
	x86_64-*) abi=x86_64 ;;
esac

"$DIR/sdk/android-ndk-${v_ndk}/ndk-build" \
	-C "$DIR/sdk/android-ndk-${v_ndk}/sources/third_party/shaderc" \
	NDK_PROJECT_PATH=. APP_BUILD_SCRIPT=Android.mk \
	APP_ABI="$abi" APP_PLATFORM=android-21 APP_STL=c++_static \
	NDK_OUT="$shaderc_build/obj" NDK_LIBS_OUT="$shaderc_build/libs" \
	libshaderc_combined
mkdir -p "$prefix_dir"/{include/shaderc,lib/pkgconfig}
cp "$shaderc_build/include/shaderc/"* "$prefix_dir/include/shaderc/"
cp "$shaderc_build/libs/c++_static/$abi/libshaderc.a" "$prefix_dir/lib/"
cat > "$prefix_dir/lib/pkgconfig/shaderc.pc" <<EOF
prefix=\${pcfiledir}/../..
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: shaderc
Description: SPIR-V compile
Version: 2025.1
Libs: -L\${libdir} -lshaderc -latomic -lc++
Cflags: -I\${includedir}
EOF
cat > "$prefix_dir/lib/pkgconfig/vulkan.pc" <<EOF
Name: Vulkan
Description: Android NDK Vulkan headers
Version: 1.4.0
EOF

meson setup $build --cross-file "$prefix_dir"/crossfile.txt \
	-Dvulkan=enabled -Dvk-proc-addr=disabled \
	-Dshaderc=enabled -Dglslang=disabled -Ddemos=false

ninja -C $build -j$cores
DESTDIR="$prefix_dir" ninja -C $build install

# add missing library for static linking
# this isn't "-lstdc++" due to a meson bug: https://github.com/mesonbuild/meson/issues/11300
${SED:-sed} '/^Libs:/ s|$| -lc++|' "$prefix_dir/lib/pkgconfig/libplacebo.pc" -i
