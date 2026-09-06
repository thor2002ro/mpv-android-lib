#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
importer="$repository_root/buildscripts/scripts/import-libass-provider.sh"
test_root="$(mktemp -d -t mpv-libass-import-tests.XXXXXXXX)"

cleanup() {
	rm -rf -- "$test_root"
}
trap cleanup EXIT INT TERM

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

write_provider() {
	local provider_aar="$1"
	local artifact="${2:-libass-android-provider}"
	local commit="${3:-b2fe9d8770671234567890abcdef1234567890ab}"
	local include_armv7="${4:-yes}"
	local ndk_version="${5:-29.0.14206865}"
	local fixture="$test_root/fixture"
	rm -rf -- "$fixture"
	mkdir -p "$fixture/META-INF" "$fixture/prefab/modules/ass/include/ass"
	printf 'test ass header\n' > "$fixture/prefab/modules/ass/include/ass/ass.h"
	printf 'test ass types header\n' > "$fixture/prefab/modules/ass/include/ass/ass_types.h"
	cat > "$fixture/META-INF/libass-android-provider.properties" <<EOF
group=io.github.peerless2012
artifact=$artifact
version=0.5.1-thor.b2fe9d877067
libass_version=0.17.5
libass_version_hex=0x01705010
libass_commit=$commit
patch_tree=0123456789abcdef0123456789abcdef01234567
ndk_version=$ndk_version
abis=armeabi-v7a,arm64-v8a,x86,x86_64
optimization=O3,thin-lto,armv7-neon,armv7-thumb,arm64-neon
EOF
	for abi in armeabi-v7a arm64-v8a x86 x86_64; do
		[[ "$abi" == armeabi-v7a && "$include_armv7" == no ]] && continue
		mkdir -p "$fixture/jni/$abi"
		printf 'libass fixture for %s\n' "$abi" > "$fixture/jni/$abi/libass.so"
		printf 'libc++ fixture for %s\n' "$abi" > "$fixture/jni/$abi/libc++_shared.so"
	done
	jar --create --file "$provider_aar" -C "$fixture" .
}

run_import() {
	local provider_aar="$1"
	local prefix="$2"
	LIBASS_ANDROID_PROVIDER_AAR="$provider_aar" \
		prefix_dir="$prefix" \
		bash "$importer"
}

missing_aar="$test_root/missing.aar"
if missing_output="$(run_import "$missing_aar" "$test_root/missing-prefix" 2>&1)"; then
	fail "import accepted a missing provider AAR"
fi
[[ "$missing_output" == *"Provider AAR not found"* ]] || \
	fail "missing AAR failure was not actionable: $missing_output"

missing_armv7="$test_root/missing-armv7.aar"
write_provider "$missing_armv7" libass-android-provider b2fe9d8770671234567890abcdef1234567890ab no
missing_armv7_prefix="$test_root/missing-armv7-prefix/armv7l"
if missing_armv7_output="$(run_import "$missing_armv7" "$missing_armv7_prefix" 2>&1)"; then
	fail "import accepted a provider without ARMv7"
fi
[[ "$missing_armv7_output" == *"Missing provider entry: jni/armeabi-v7a/libass.so"* ]] || \
	fail "missing ARMv7 failure was not actionable: $missing_armv7_output"
[[ ! -e "$missing_armv7_prefix" ]] || fail "failed import changed the prefix"

wrong_artifact="$test_root/wrong-artifact.aar"
write_provider "$wrong_artifact" another-provider
wrong_artifact_prefix="$test_root/wrong-artifact-prefix/armv7l"
if wrong_artifact_output="$(run_import "$wrong_artifact" "$wrong_artifact_prefix" 2>&1)"; then
	fail "import accepted the wrong provider identity"
fi
[[ "$wrong_artifact_output" == *"Provider metadata is missing: artifact=libass-android-provider"* ]] || \
	fail "wrong artifact failure was not actionable: $wrong_artifact_output"
[[ ! -e "$wrong_artifact_prefix" ]] || fail "failed import changed the prefix"

invalid_commit="$test_root/invalid-commit.aar"
write_provider "$invalid_commit" libass-android-provider invalid
invalid_commit_prefix="$test_root/invalid-commit-prefix/armv7l"
if invalid_commit_output="$(run_import "$invalid_commit" "$invalid_commit_prefix" 2>&1)"; then
	fail "import accepted an invalid libass commit"
fi
[[ "$invalid_commit_output" == *"Provider libass commit is invalid"* ]] || \
	fail "invalid commit failure was not actionable: $invalid_commit_output"
[[ ! -e "$invalid_commit_prefix" ]] || fail "failed import changed the prefix"

configured_importer_root="$test_root/configured-importer"
mkdir -p "$configured_importer_root/buildscripts/scripts" "$configured_importer_root/buildscripts/include"
cp "$importer" "$configured_importer_root/buildscripts/scripts/"
printf 'v_ndk_n=99.1.2\n' > "$configured_importer_root/buildscripts/include/depinfo.sh"
configured_provider="$test_root/configured-ndk.aar"
write_provider "$configured_provider" libass-android-provider b2fe9d8770671234567890abcdef1234567890ab yes 99.1.2
LIBASS_ANDROID_PROVIDER_AAR="$configured_provider" \
	prefix_dir="$test_root/configured-prefix/arm64" \
	bash "$configured_importer_root/buildscripts/scripts/import-libass-provider.sh"

valid_provider="$test_root/valid-provider.aar"
write_provider "$valid_provider"
while read -r prefix_name android_abi; do
	prefix="$test_root/prefix/$prefix_name"
	run_import "$valid_provider" "$prefix"
	[[ -f "$prefix/include/ass/ass.h" ]] || fail "missing ass.h for $prefix_name"
	[[ -f "$prefix/include/ass/ass_types.h" ]] || fail "missing ass_types.h for $prefix_name"
	fixture_library="$test_root/fixture/jni/$android_abi/libass.so"
	cmp "$fixture_library" "$prefix/lib/libass.so" || fail "wrong library imported for $prefix_name"
	grep -Fxq 'Libs: -L${libdir} -lass' "$prefix/lib/pkgconfig/libass.pc" || \
		fail "pkg-config does not request dynamic libass for $prefix_name"
	grep -Fxq 'Version: 0.17.5' "$prefix/lib/pkgconfig/libass.pc" || \
		fail "pkg-config lost the libass version for $prefix_name"
done <<'EOF'
armv7l armeabi-v7a
arm64 arm64-v8a
x86 x86
x86_64 x86_64
EOF

echo "MPV shared libass provider import contracts passed"
