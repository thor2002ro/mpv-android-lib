#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d -t mpv-native-optimization-tests.XXXXXXXX)"

cleanup() {
    rm -rf -- "$test_root"
}
trap cleanup EXIT INT TERM

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

fake_bin="$test_root/bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/pkg-config" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$fake_bin/make" <<'EOF'
#!/usr/bin/env bash
if [[ -n "${MAKE_ARGS_FILE:-}" ]]; then
    printf '%s\n' "$@" > "$MAKE_ARGS_FILE"
    touch liblua.a
fi
exit 0
EOF
chmod +x "$fake_bin/pkg-config" "$fake_bin/make"

write_crossfile() {
    local arch="$1"
    local fixture="$test_root/buildall-$arch"
    mkdir -p "$fixture/include"
    cp "$repository_root/buildscripts/buildall.sh" "$fixture/buildall.sh"
    cp "$repository_root/buildscripts/include/depinfo.sh" "$fixture/include/depinfo.sh"
    (
        cd "$fixture"
        PATH="$fake_bin:$PATH" bash ./buildall.sh --arch "$arch" --only-deps libressl >/dev/null
    )
    printf '%s\n' "$fixture/prefix/$arch/crossfile.txt"
}

armv7_crossfile="$(write_crossfile armv7l)"
grep -Fq "optimization = '3'" "$armv7_crossfile" ||
    fail "ARMv7 Meson configuration does not explicitly select optimization level 3"
grep -Fq "b_lto = true" "$armv7_crossfile" ||
    fail "ARMv7 Meson configuration does not enable LTO"
if grep -Fq "build.b_lto" "$armv7_crossfile"; then
    fail "Meson configuration uses unsupported per-machine LTO syntax"
fi
grep -Fq "debug = false" "$armv7_crossfile" ||
    fail "ARMv7 Meson configuration does not disable debug mode"
if grep -Fq "buildtype = 'release'" "$armv7_crossfile"; then
    fail "Meson configuration redundantly combines buildtype with explicit optimization"
fi
grep -Fq "c_args = ['-mfpu=neon', '-mthumb']" "$armv7_crossfile" ||
    fail "ARMv7 C compilation does not require NEON Thumb-2"
grep -Fq "cpp_args = ['-mfpu=neon', '-mthumb']" "$armv7_crossfile" ||
    fail "ARMv7 C++ compilation does not require NEON Thumb-2"

arm64_crossfile="$(write_crossfile arm64)"
grep -Fq "optimization = '3'" "$arm64_crossfile" ||
    fail "ARM64 Meson configuration does not explicitly select optimization level 3"
grep -Fq "b_lto = true" "$arm64_crossfile" ||
    fail "ARM64 Meson configuration does not enable LTO"
if grep -Fq -- '-mfpu=neon' "$arm64_crossfile"; then
    fail "ARM64 configuration uses the ARMv7-only -mfpu flag"
fi

native_linker_fixture="$test_root/native-linker"
mkdir -p "$native_linker_fixture/include" \
    "$native_linker_fixture/deps/probe" \
    "$native_linker_fixture/scripts"
cp "$repository_root/buildscripts/buildall.sh" "$native_linker_fixture/buildall.sh"
cp "$repository_root/buildscripts/include/depinfo.sh" "$native_linker_fixture/include/depinfo.sh"
cat > "$native_linker_fixture/scripts/probe.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' \
    "${CC_FOR_BUILD-}" \
    "${CXX_FOR_BUILD-}" \
    "${CFLAGS-}" \
    "${CXXFLAGS-}" \
    "${LDFLAGS-}" > "$NATIVE_COMPILERS_FILE"
EOF
native_compilers_file="$test_root/native-compilers.txt"
(
    cd "$native_linker_fixture"
    PATH="$fake_bin:$PATH" \
        NATIVE_COMPILERS_FILE="$native_compilers_file" \
        bash ./buildall.sh --arch armv7l -n probe >/dev/null
)
[[ "$(sed -n '1p' "$native_compilers_file")" == clang ]] ||
    fail "Meson build-machine C helpers do not use Clang"
[[ "$(sed -n '2p' "$native_compilers_file")" == clang++ ]] ||
    fail "Meson build-machine C++ helpers do not use Clang"
armv7_cflags="$(sed -n '3p' "$native_compilers_file")"
armv7_cxxflags="$(sed -n '4p' "$native_compilers_file")"
armv7_ldflags="$(sed -n '5p' "$native_compilers_file")"
for flag in -O3 -flto=thin -mfpu=neon -mthumb; do
    [[ " $armv7_cflags " == *" $flag "* ]] ||
        fail "ARMv7 C environment is missing $flag"
    [[ " $armv7_cxxflags " == *" $flag "* ]] ||
        fail "ARMv7 C++ environment is missing $flag"
done
[[ " $armv7_ldflags " == *" -flto=thin "* ]] ||
    fail "ARMv7 linker environment does not enable thin LTO"

lua_fixture="$test_root/lua"
mkdir -p "$lua_fixture/buildscripts/scripts" "$lua_fixture/buildscripts/include" \
    "$lua_fixture/buildscripts/deps/lua"
touch "$lua_fixture/buildscripts/deps/lua/lua.h" \
    "$lua_fixture/buildscripts/deps/lua/luaconf.h" \
    "$lua_fixture/buildscripts/deps/lua/lauxlib.h" \
    "$lua_fixture/buildscripts/deps/lua/lualib.h"
cp "$repository_root/buildscripts/scripts/lua.sh" \
    "$lua_fixture/buildscripts/scripts/lua.sh"
cat > "$lua_fixture/buildscripts/include/path.sh" <<'EOF'
cores=1
prefix_dir="$LUA_PREFIX_DIR"
EOF
lua_make_args="$test_root/lua-make.args"
(
    cd "$lua_fixture/buildscripts/deps/lua"
    PATH="$fake_bin:$PATH" \
        MAKE_ARGS_FILE="$lua_make_args" \
        LUA_PREFIX_DIR="$lua_fixture/prefix" \
        CC=armv7a-linux-androideabi24-clang \
        AR=llvm-ar \
        RANLIB=llvm-ranlib \
        CFLAGS='-O3 -flto=thin -mfpu=neon -mthumb' \
        bash ../../scripts/lua.sh build
)
lua_cflags="$(sed -n 's/^CFLAGS=//p' "$lua_make_args")"
for flag in -O3 -flto=thin -mfpu=neon -mthumb; do
    [[ " $lua_cflags " == *" $flag "* ]] ||
        fail "Lua compilation is missing $flag"
done

android_makefile="$repository_root/lib/src/main/jni/Android.mk"
grep -Eq '^LOCAL_CFLAGS[[:space:]]*:=[[:space:]].*-O3([[:space:]]|$)' "$android_makefile" ||
    fail "MPV JNI compilation does not explicitly select -O3"
grep -Eq '^LOCAL_CFLAGS[[:space:]]*:=[[:space:]].*-flto=thin([[:space:]]|$)' "$android_makefile" ||
    fail "MPV JNI compilation does not enable thin LTO"
grep -Fq 'ifeq ($(TARGET_ARCH_ABI),armeabi-v7a)' "$android_makefile" &&
    grep -Eq '^LOCAL_CFLAGS[[:space:]]*\+=[[:space:]]*-mfpu=neon([[:space:]]|$)' "$android_makefile" ||
    fail "MPV JNI ARMv7 compilation does not require NEON"
grep -Eq '^LOCAL_ARM_MODE[[:space:]]*:=[[:space:]]*thumb([[:space:]]|$)' "$android_makefile" ||
    fail "MPV JNI ARMv7 compilation does not select Thumb-2"
grep -Eq '^LOCAL_LDFLAGS[[:space:]]*:=[[:space:]].*-flto=thin([[:space:]]|$)' "$android_makefile" ||
    fail "MPV JNI linking does not enable thin LTO"

ffmpeg_fixture="$test_root/ffmpeg"
mkdir -p "$ffmpeg_fixture/buildscripts/scripts" \
    "$ffmpeg_fixture/buildscripts/include" \
    "$ffmpeg_fixture/buildscripts/deps/ffmpeg"
cp "$repository_root/buildscripts/scripts/ffmpeg.sh" \
    "$ffmpeg_fixture/buildscripts/scripts/ffmpeg.sh"
cat > "$ffmpeg_fixture/buildscripts/include/path.sh" <<'EOF'
cores=1
EOF
cat > "$ffmpeg_fixture/buildscripts/deps/ffmpeg/configure" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FFMPEG_ARGS_FILE"
EOF
chmod +x "$ffmpeg_fixture/buildscripts/deps/ffmpeg/configure"

run_ffmpeg_configure() {
    local triple="$1"
    local args_file="$2"
    (
        cd "$ffmpeg_fixture/buildscripts/deps/ffmpeg"
        PATH="$fake_bin:$PATH" \
            FFMPEG_ARGS_FILE="$args_file" \
            ndk_triple="$triple" \
            ndk_suffix= \
            CC="${triple}24-clang" \
            prefix_dir=/tmp/mpv-prefix \
            bash ../../scripts/ffmpeg.sh build
    )
}

armv7_ffmpeg_args="$test_root/ffmpeg-armv7.args"
run_ffmpeg_configure arm-linux-androideabi "$armv7_ffmpeg_args"
grep -Fxq -- '--optflags=-O3' "$armv7_ffmpeg_args" ||
    fail "ARMv7 FFmpeg does not explicitly select -O3"
grep -Fxq -- '--enable-lto' "$armv7_ffmpeg_args" ||
    fail "ARMv7 FFmpeg does not enable LTO"
grep -Fxq -- '--host-cc=clang' "$armv7_ffmpeg_args" ||
    fail "FFmpeg build-machine helpers do not use Clang"
grep -Fxq -- '--enable-neon' "$armv7_ffmpeg_args" ||
    fail "ARMv7 FFmpeg does not explicitly enable NEON"
grep -Fxq -- '--enable-thumb' "$armv7_ffmpeg_args" ||
    fail "ARMv7 FFmpeg does not enable Thumb where supported"

x86_ffmpeg_args="$test_root/ffmpeg-x86.args"
run_ffmpeg_configure i686-linux-android "$x86_ffmpeg_args"
grep -Fxq -- '--optflags=-O3' "$x86_ffmpeg_args" ||
    fail "x86 FFmpeg does not explicitly select -O3"
grep -Fxq -- '--enable-lto' "$x86_ffmpeg_args" ||
    fail "x86 FFmpeg does not enable LTO"
if grep -Fxq -- '--enable-neon' "$x86_ffmpeg_args"; then
    fail "x86 FFmpeg incorrectly enables ARM NEON"
fi
if grep -Fxq -- '--enable-thumb' "$x86_ffmpeg_args"; then
    fail "x86 FFmpeg incorrectly enables ARM Thumb"
fi

echo "MPV native optimization contracts passed"
