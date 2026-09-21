#!/usr/bin/env python3
"""bump_edit.py — apply version-bump edits to manifest, metainfo and README.

Called by bump.sh after it resolves the new values from the network.
All edits live in the EDITS table: name -> (file-key, regex, replacement).

Conventions:
  - replacement templates use {value} placeholders (filled from CLI args)
    and \\g<group> named-group backrefs — never \\1-style numbered groups;
  - a pattern that matches nothing aborts the run, so a drifted file
    never produces a silent no-op;
  - `--dry-run` validates every pattern and prints a unified diff
    without touching any file.
"""

import argparse
import difflib
import re
import sys
from pathlib import Path

FILES = {
    "manifest": "aseprite.yaml",
    "metainfo": "aseprite.metainfo.xml",
    "readme": "README.md",
}

# reusable regexp fragments
V = r"v[0-9.]+"  # aseprite tag, e.g. v1.3.18.1
VER = r"[0-9.]+"  # bare version, e.g. 1.3.18.1
SHA1 = r"[0-9a-f]{40}"  # git commit
SHA256 = r"[0-9a-f]{64}"  # archive hash
DATE = r"[0-9]{4}-[0-9]{2}-[0-9]{2}"  # release date, YYYY-MM-DD

EDITS = {
    # manifest: freedesktop runtime pin
    "runtime-version": (
        "manifest",
        r"runtime-version: '" + VER + r"'",
        "runtime-version: '{runtime}'",
    ),
    # manifest: aseprite git source — tag line, plus commit line right below
    # (commit is optional in the pattern so it gets added if ever missing;
    # (?P=indent) reuses the tag line's indentation for it)
    "aseprite-tag": (
        "manifest",
        r"(?P<head>url: https://github\.com/aseprite/aseprite\n"
        r"(?P<indent>[ ]+)tag: )" + V + r"(?:\n(?P=indent)commit: " + SHA1 + r")?",
        r"\g<head>{ase_tag}\n\g<indent>commit: {ase_commit}",
    ),
    # metainfo: <release> element
    "metainfo-release": (
        "metainfo",
        r'<release version="' + VER + r'" date="' + DATE + r'"',
        '<release version="{ase_version}" date="{date}"',
    ),
    # README: version note in the header quote block
    "readme-version": (
        "readme",
        r"Aseprite version: " + V,
        "Aseprite version: {ase_tag}",
    ),
    # manifest: skia archive URL (-libstdc++ asset variant tolerated)
    "skia-url": (
        "manifest",
        r"url: https://github\.com/aseprite/skia/releases/download/m[0-9]+-[0-9a-f]+/Skia-Linux-Release-x64(?:-libstdc\+\+)?\.zip",
        "url: {skia_url}",
    ),
    # manifest: skia archive hash
    "skia-sha256": (
        "manifest",
        r"(?P<indent>[ ]*)sha256: " + SHA256,
        r"\g<indent>sha256: {skia_sha}",
    ),
}


def main() -> None:
    ap = argparse.ArgumentParser(description=(__doc__ or "").splitlines()[0])
    ap.add_argument(
        "--dry-run",
        action="store_true",
        help="validate every pattern and print a diff, edit nothing",
    )
    ap.add_argument("--skia-url", required=True)
    ap.add_argument("--skia-sha", required=True)
    ap.add_argument("--runtime", help="runtime version, e.g. 25.08")
    ap.add_argument("--ase-tag", help="aseprite tag, e.g. v1.3.18.1")
    ap.add_argument("--ase-commit", help="40-hex commit the tag points to")
    ap.add_argument("--date", help="release date, YYYY-MM-DD")
    ap.add_argument(
        "--skia-only",
        action="store_true",
        help="only refresh skia url/sha in the manifest",
    )
    args = ap.parse_args()

    values = {"skia_url": args.skia_url, "skia_sha": args.skia_sha}

    if args.skia_only:
        names = ["skia-url", "skia-sha256"]
    else:
        for req in ("runtime", "ase_tag", "ase_commit", "date"):
            if not getattr(args, req):
                ap.error(f"--{req.replace('_', '-')} is required unless --skia-only")
        values.update(
            runtime=args.runtime,
            ase_tag=args.ase_tag,
            ase_version=args.ase_tag.lstrip("v"),
            ase_commit=args.ase_commit,
            date=args.date,
        )
        names = list(EDITS)

    base = Path(__file__).resolve().parent
    # file_key -> current text (edits applied sequentially, in-place in memory)
    current: dict[str, str] = {}
    failures: list[tuple[str, str, str]] = []

    for name in names:
        file_key, pattern, template = EDITS[name]
        path = base / FILES[file_key]
        text = current.get(file_key, path.read_text())
        repl = template.format(**values)
        new, n = re.subn(pattern, repl, text, count=1)
        if n != 1:
            failures.append((name, path.name, pattern))
            current[file_key] = text  # keep baseline so later diffs are stable
            continue
        current[file_key] = new

    if failures:
        for name, fname, pattern in failures:
            sys.stderr.write(
                f"ERROR: edit '{name}' matched nothing in {fname}: {pattern!r}\n"
            )
        sys.exit(1)

    if args.dry_run:
        for file_key in dict.fromkeys(EDITS[name][0] for name in names):
            if file_key not in current:
                continue
            orig = (base / FILES[file_key]).read_text()
            updated = current[file_key]
            if orig == updated:
                continue
            path = base / FILES[file_key]
            diff = difflib.unified_diff(
                orig.splitlines(keepends=True),
                updated.splitlines(keepends=True),
                fromfile=f"a/{path.name}",
                tofile=f"b/{path.name}",
            )
            print(f"diff -- {path.name}")
            sys.stdout.writelines(diff)
        sys.exit(0)

    for file_key in current:
        (base / FILES[file_key]).write_text(current[file_key])
        print(f"  {FILES[file_key]}: applied")


if __name__ == "__main__":
    main()
