#!/bin/bash -e

. ../../include/path.sh

if [ "$1" == "build" ]; then
	true
elif [ "$1" == "clean" ]; then
	rm -f -- *.o liblua.a lua luac
	exit 0
else
	exit 255
fi

# Building separately from source tree is not supported, this means we are forced to always clean
$0 clean

mycflags=(
	# ensures correct linking into libmpv.so
	-fPIC
	# bionic is missing decimal_point in localeconv [src/llex.c]
	-Dgetlocaledecpoint\\\(\\\)=\\\(46\\\)
	# force fallback as ftello/fseeko are not defined [src/liolib.c]
	-Dlua_fseek
)

# The v5-2 GitHub branch uses a developer makefile. Override its test object
# list with the production 5.2.4 library objects and install only mpv's inputs.
core_objects=(
	lapi.o lcode.o lctype.o ldebug.o ldo.o ldump.o lfunc.o lgc.o llex.o
	lmem.o lobject.o lopcodes.o lparser.o lstate.o lstring.o ltable.o ltm.o
	lundump.o lvm.o lzio.o
)
library_objects=(
	lbaselib.o lbitlib.o lcorolib.o ldblib.o liolib.o lmathlib.o loslib.o
	ltablib.o lstrlib.o loadlib.o linit.o
)
make CC="$CC" AR="$AR rc" RANLIB="$RANLIB" \
	CFLAGS="$CFLAGS ${mycflags[*]}" \
	CORE_O="${core_objects[*]}" LIB_O="${library_objects[*]}" a -j$cores

lua_install_dir="$prefix_dir/usr/local"
mkdir -p "$lua_install_dir/lib/pkgconfig" "$lua_install_dir/include"
${INSTALL:-install} -m 644 liblua.a "$lua_install_dir/lib/liblua.a"
${INSTALL:-install} -m 644 lua.h luaconf.h lauxlib.h lualib.h \
	"$lua_install_dir/include/"

cat >"$lua_install_dir/lib/pkgconfig/lua.pc" <<EOF
prefix=/usr/local
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: Lua
Description:
Version: $v_lua
Libs: -L\${libdir} -llua -lm
Cflags: -I\${includedir}
EOF
