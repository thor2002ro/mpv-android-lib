#!/usr/bin/env bash
set -euo pipefail

object_file="${1:?usage: extract-build-date.sh OBJECT_FILE}"
[[ -f "$object_file" ]] || {
	echo "Compiled MPV version object not found: $object_file" >&2
	exit 1
}

if ! build_date="$({ LC_ALL=C strings "$object_file" || true; } | awk '
	/^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) [ 0-9][0-9] [0-9][0-9][0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]$/ && found == "" { found = $0 }
	END { if (found != "") print found; else exit 1 }
')"; then
	echo "Couldn't read the MPV build date from $object_file" >&2
	exit 1
fi

printf '%s\n' "$build_date"
