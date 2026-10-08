#!/bin/bash -e
set -e

. ../../include/path.sh

if [ "$1" == clean ]; then
	rm -rf "_build$ndk_suffix"
	exit 0
elif [ "$1" != build ]; then
	exit 255
fi
case "$ndk_triple" in
    aarch64*) llvm_target=AArch64; llvm_abi=arm64-v8a; llvm_triple=aarch64-linux-android ;;
    *) exit 0 ;;
esac

common_args=(
	-G Ninja -DCMAKE_BUILD_TYPE=Release
	-DLLVM_TARGETS_TO_BUILD="$llvm_target" -DLLVM_ENABLE_PROJECTS=
	-DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF
	-DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_BUILD_TOOLS=OFF
	-DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF
	-DLLVM_ENABLE_LIBXML2=OFF -DLLVM_ENABLE_CURL=OFF
	-DLLVM_ENABLE_LIBEDIT=OFF -DLLVM_ENABLE_TERMINFO=OFF
	-DLLVM_ENABLE_RTTI=OFF -DLLVM_ENABLE_EH=OFF
	-DLLVM_BUILD_LLVM_DYLIB=OFF -DBUILD_SHARED_LIBS=OFF
)
# TableGen and llvm-config must run on the build host, not Android.
env -u CC -u CXX -u CFLAGS -u CXXFLAGS -u LDFLAGS \
	cmake -S llvm -B _build-host "${common_args[@]}" \
	-DCMAKE_C_COMPILER="${CC_FOR_BUILD:-cc}" -DCMAKE_CXX_COMPILER="${CXX_FOR_BUILD:-c++}"
cmake --build _build-host --parallel "$cores" --target llvm-tblgen llvm-config

cmake -S llvm -B "_build$ndk_suffix" "${common_args[@]}" \
	-DCMAKE_TOOLCHAIN_FILE="$DIR/sdk/android-ndk-$v_ndk/build/cmake/android.toolchain.cmake" \
	-DANDROID_ABI="$llvm_abi" -DANDROID_PLATFORM=android-24 -DANDROID_STL=c++_shared \
	-DCMAKE_INSTALL_PREFIX="$prefix_dir" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
	-DLLVM_HOST_TRIPLE="$llvm_triple" -DLLVM_DEFAULT_TARGET_TRIPLE="$llvm_triple" \
	-DLLVM_TABLEGEN="$PWD/_build-host/bin/llvm-tblgen" \
	-DLLVM_NATIVE_TOOL_DIR="$PWD/_build-host/bin"
cmake --build "_build$ndk_suffix" --parallel "$cores" \
	--target "LLVM${llvm_target}AsmParser" "LLVM${llvm_target}Desc" "LLVM${llvm_target}Info" LLVMMC LLVMMCParser LLVMObject
cmake --build "_build$ndk_suffix" --target install-llvm-headers
mkdir -p "$prefix_dir/lib" "$prefix_dir/bin"
cp "_build$ndk_suffix"/lib/libLLVM*.a "$prefix_dir/lib/"
cp _build-host/bin/llvm-config "$prefix_dir/bin/llvm-config-host"
printf '%s\n' "$llvm_triple" > "$prefix_dir/lib/llvm-target.txt"

# Relocated host llvm-config reads the installed target archives; flags must describe Android.
cat > "$prefix_dir/bin/llvm-config" <<'CONFIG'
#!/bin/bash -e
prefix="$(cd "$(dirname "$0")/.." && pwd)"
args=()
system_libs=0
for arg in "$@"; do
	case "$arg" in
		--cxxflags) echo "-I$prefix/include -std=c++17 -fno-exceptions -fno-rtti -DNDEBUG -D_GNU_SOURCE" ;;
		--cflags|--cppflags) echo "-I$prefix/include -DNDEBUG -D_GNU_SOURCE" ;;
		--ldflags) echo "-L$prefix/lib" ;;
		--host-target) cat "$prefix/lib/llvm-target.txt" ;;
		--system-libs) system_libs=1 ;;
		*) args+=("$arg") ;;
	esac
done
if [[ ${#args[@]} -gt 0 ]]; then
	"$prefix/bin/llvm-config-host" "${args[@]}"
fi
if [[ $system_libs -eq 1 ]]; then
	echo '-lm -ldl -latomic'
fi
CONFIG
chmod +x "$prefix_dir/bin/llvm-config"
"$prefix_dir/bin/llvm-config" --link-static --libs "${llvm_target}AsmParser" "${llvm_target}Desc" "${llvm_target}Info" MC MCParser Object
