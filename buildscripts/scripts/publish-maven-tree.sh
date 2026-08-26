#!/usr/bin/env bash
set -euo pipefail

remove_exact_tree() {
	local path="$1"
	local parent="$2"
	case "$path" in
		"$parent/maven"|"$parent/maven.pending"|"$parent/maven.backup"|"$parent/maven.rollback") ;;
		*) echo "Refusing to remove unexpected publication path: $path" >&2; return 1 ;;
	esac
	if [[ "${MPV_PUBLICATION_TEST_CLEANUP_FAILURE:-0}" == 1 &&
		( "$path" == "$parent/maven.backup" || "$path" == "$parent/maven.rollback" ) ]]
	then
		return 1
	fi
	rm -rf -- "$path"
}

publish_maven_tree() {
	local pending_root="$1"
	local maven_root="$2"
	local final_aar_relative="$3"
	local validator="$4"
	local output_root
	output_root="$(cd "$(dirname "$maven_root")" && pwd -P)"
	maven_root="$output_root/$(basename "$maven_root")"
	pending_root="$output_root/$(basename "$pending_root")"
	[[ "$maven_root" == "$output_root/maven" && "$pending_root" == "$output_root/maven.pending" ]] || {
		echo "Publication paths must be exact siblings below $output_root" >&2
		return 1
	}

	local recovery_root="$output_root/maven.backup"
	local rollback_root="$output_root/maven.rollback"
	local transaction_backup="$recovery_root"
	local promotion_started=0
	local publication_committed=0

	if [[ ! -d "$maven_root" && -d "$recovery_root" ]]; then
		mv "$recovery_root" "$maven_root"
	fi
	[[ -d "$pending_root" ]] || {
		echo "Pending Maven tree not found: $pending_root" >&2
		return 1
	}

	if [[ -d "$recovery_root" ]]; then
		transaction_backup="$rollback_root"
		remove_exact_tree "$rollback_root" "$output_root"
	fi

	rollback_publication() {
		local status="$1"
		if (( status != 0 && promotion_started != 0 && publication_committed == 0 )); then
			remove_exact_tree "$maven_root" "$output_root" || true
			if [[ -d "$transaction_backup" ]] && ! mv "$transaction_backup" "$maven_root"; then
				echo "Failed to restore Maven backup: $transaction_backup" >&2
			fi
		fi
		remove_exact_tree "$pending_root" "$output_root" || true
		return "$status"
	}
	trap 'rollback_publication $?' EXIT

	if [[ -d "$maven_root" ]] && ! mv "$maven_root" "$transaction_backup"; then
		trap - EXIT
		rollback_publication 1
		return 1
	fi
	promotion_started=1
	if ! mv "$pending_root" "$maven_root"; then
		trap - EXIT
		rollback_publication 1
		return 1
	fi
	if ! "$validator" "$maven_root/$final_aar_relative"; then
		trap - EXIT
		rollback_publication 1
		return 1
	fi
	publication_committed=1
	trap - EXIT

	if ! remove_exact_tree "$transaction_backup" "$output_root"; then
		echo "Warning: validated Maven tree committed; backup cleanup deferred" >&2
	fi
	if [[ "$transaction_backup" != "$recovery_root" ]]; then
		if ! remove_exact_tree "$recovery_root" "$output_root"; then
			echo "Warning: validated Maven tree committed; stale recovery cleanup deferred" >&2
		fi
	fi
}

self_test_validator() {
	[[ -f "$1" && "$(<"$1")" == new ]]
}

self_test() {
	local root
	root="$(mktemp -d "${TMPDIR:-/tmp}/mpv-maven-publish.XXXXXXXX")"
	trap 'rm -rf "$root"' RETURN

	mkdir -p "$root/a/maven"
	echo old >"$root/a/maven/state"
	! publish_maven_tree "$root/a/maven.pending" "$root/a/maven" version/artifact self_test_validator
	[[ "$(<"$root/a/maven/state")" == old ]]

	mkdir -p "$root/b/maven" "$root/b/maven.pending/version"
	echo old >"$root/b/maven/state"
	echo invalid >"$root/b/maven.pending/version/artifact"
	! publish_maven_tree "$root/b/maven.pending" "$root/b/maven" version/artifact self_test_validator
	[[ "$(<"$root/b/maven/state")" == old ]]

	mkdir -p "$root/c/maven" "$root/c/maven.pending/version"
	echo old >"$root/c/maven/state"
	echo new >"$root/c/maven.pending/version/artifact"
	MPV_PUBLICATION_TEST_CLEANUP_FAILURE=1 \
		publish_maven_tree "$root/c/maven.pending" "$root/c/maven" version/artifact self_test_validator
	[[ "$(<"$root/c/maven/version/artifact")" == new ]]

	mkdir -p "$root/d/maven.backup"
	echo old >"$root/d/maven.backup/state"
	! publish_maven_tree "$root/d/maven.pending" "$root/d/maven" version/artifact self_test_validator
	[[ "$(<"$root/d/maven/state")" == old && ! -e "$root/d/maven.backup" ]]

	echo "Maven publication transaction self-test passed"
}

if [[ "${1:-}" == "--self-test" ]]; then
	self_test
	exit 0
fi

[[ $# == 4 ]] || {
	echo "usage: publish-maven-tree.sh PENDING_ROOT MAVEN_ROOT FINAL_AAR_RELATIVE VALIDATOR" >&2
	exit 1
}
publish_maven_tree "$@"
