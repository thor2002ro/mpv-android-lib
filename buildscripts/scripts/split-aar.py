#!/usr/bin/env python3
"""Store an AAR as Git-friendly parts without changing its contents."""
import hashlib
import pathlib
import sys

chunk_size = 90 * 1024 * 1024


def split_aar(aar):
    if not aar.is_file() or aar.suffix != ".aar" or any(char in aar.name for char in "\r\n"):
        raise SystemExit(f"Not an AAR file: {aar}")
    manifest = aar.with_name(f"{aar.name}.parts")
    if aar.stat().st_size <= 100 * 1024 * 1024 and not manifest.exists():
        return
    if aar.stat().st_size == 0:
        raise SystemExit(f"Cannot split an empty AAR: {aar}")
    digest = hashlib.sha256()
    parts = 0
    with aar.open("rb") as source:
        while chunk := source.read(chunk_size):
            parts += 1
            aar.with_name(f"{aar.name}.part{parts:03d}").write_bytes(chunk)
            digest.update(chunk)
    manifest.write_text(
        f"parts={parts}\nsize={aar.stat().st_size}\nsha256={digest.hexdigest()}\n",
        encoding="ascii",
    )
    prefix = f"{aar.name}.part"
    for part in aar.parent.iterdir():
        if not part.name.startswith(prefix):
            continue
        suffix = part.name.removeprefix(f"{aar.name}.part")
        if suffix.isdigit() and int(suffix) > parts:
            part.unlink()
    ignore = aar.with_name(".gitignore")
    lines = ignore.read_text(encoding="utf-8").splitlines() if ignore.exists() else []
    pattern = "/" + "".join("\\" + char if char in "\\*?[]" else char for char in aar.name)
    updated = "\n".join([line for line in lines if line != pattern] + [pattern]) + "\n"
    if not ignore.exists() or ignore.read_text(encoding="utf-8") != updated:
        ignore.write_text(updated, encoding="utf-8")
    print(f"Split {aar.name} into {parts} parts of at most 90 MiB")


if len(sys.argv) < 2:
    raise SystemExit("Usage: split-aar.py AAR_OR_DIRECTORY [...]")
for argument in sys.argv[1:]:
    target = pathlib.Path(argument)
    if not target.exists():
        raise SystemExit(f"AAR or directory does not exist: {target}")
    for aar in sorted(target.rglob("*.aar")) if target.is_dir() else [target]:
        split_aar(aar)
