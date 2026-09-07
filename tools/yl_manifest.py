#!/usr/bin/env python3
"""Generate and verify SHA-256 file manifests (M0-01).

Fail-closed: `check` exits non-zero on any missing, changed, or unlisted file.
Only the Python standard library is used.

Usage:
  yl_manifest.py generate ROOT [-o OUT] [--meta KEY=VALUE ...] [--exclude GLOB ...]
  yl_manifest.py check MANIFEST [--root ROOT]
"""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

MANIFEST_VERSION = 1
REPO_ROOT = Path(__file__).resolve().parent.parent


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def rel_to_repo(path: Path) -> str:
    try:
        return path.resolve().relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return path.resolve().as_posix()


def walk_files(root: Path, excludes: list[str]) -> list[Path]:
    files = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for name in sorted(filenames):
            p = Path(dirpath) / name
            rel = p.relative_to(root).as_posix()
            if any(fnmatch.fnmatch(rel, pat) or fnmatch.fnmatch(name, pat) for pat in excludes):
                continue
            files.append(p)
    return files


def build_manifest(root: Path, excludes: list[str], meta: dict[str, str]) -> dict:
    entries = []
    for p in walk_files(root, excludes):
        entries.append(
            {
                "path": p.relative_to(root).as_posix(),
                "bytes": p.stat().st_size,
                "sha256": sha256_of(p),
            }
        )
    # Case-insensitive collisions (e.g. 1.LOA vs 1.loa) are recorded, not resolved.
    by_lower: dict[str, list[dict]] = {}
    for e in entries:
        by_lower.setdefault(e["path"].lower(), []).append(e)
    collisions = []
    for group in by_lower.values():
        if len(group) > 1:
            collisions.append(
                {
                    "paths": [e["path"] for e in group],
                    "identical_bytes": len({e["sha256"] for e in group}) == 1,
                }
            )
    return {
        "manifest_version": MANIFEST_VERSION,
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "root": rel_to_repo(root),
        "file_count": len(entries),
        "total_bytes": sum(e["bytes"] for e in entries),
        "excludes": excludes,
        "meta": meta,
        "case_insensitive_collisions": collisions,
        "files": entries,
    }


def cmd_generate(args: argparse.Namespace) -> int:
    root = Path(args.root)
    if not root.is_dir():
        print(f"ERROR: root is not a directory: {root}", file=sys.stderr)
        return 2
    meta = {}
    for kv in args.meta or []:
        if "=" not in kv:
            print(f"ERROR: --meta expects KEY=VALUE, got {kv!r}", file=sys.stderr)
            return 2
        k, v = kv.split("=", 1)
        meta[k] = v
    manifest = build_manifest(root, args.exclude or [], meta)
    text = json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"
    if args.output:
        Path(args.output).write_text(text, encoding="utf-8")
        print(f"wrote {args.output}: {manifest['file_count']} files, {manifest['total_bytes']} bytes")
    else:
        sys.stdout.write(text)
    return 0


def cmd_check(args: argparse.Namespace) -> int:
    mpath = Path(args.manifest)
    try:
        manifest = json.loads(mpath.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL: cannot read manifest {mpath}: {exc}", file=sys.stderr)
        return 1
    if manifest.get("manifest_version") != MANIFEST_VERSION:
        print("FAIL: unsupported manifest_version", file=sys.stderr)
        return 1
    root = Path(args.root) if args.root else REPO_ROOT / manifest["root"]
    if not root.is_dir():
        print(f"FAIL: root missing: {root}", file=sys.stderr)
        return 1
    problems = []
    listed = {e["path"]: e for e in manifest["files"]}
    for rel, e in listed.items():
        p = root / rel
        if not p.is_file():
            problems.append(f"MISSING  {rel}")
            continue
        size = p.stat().st_size
        if size != e["bytes"]:
            problems.append(f"SIZE     {rel}: {size} != {e['bytes']}")
        digest = sha256_of(p)
        if digest != e["sha256"]:
            problems.append(f"HASH     {rel}")
    actual = {p.relative_to(root).as_posix() for p in walk_files(root, manifest.get("excludes", []))}
    for rel in sorted(actual - set(listed)):
        problems.append(f"UNLISTED {rel}")
    if problems:
        print(f"FAIL: {mpath} ({len(problems)} problems)")
        for line in problems:
            print("  " + line)
        return 1
    print(f"PASS: {mpath} ({len(listed)} files verified)")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("generate", help="hash every file under ROOT")
    g.add_argument("root")
    g.add_argument("-o", "--output")
    g.add_argument("--meta", action="append", metavar="KEY=VALUE")
    g.add_argument("--exclude", action="append", metavar="GLOB")
    g.set_defaults(func=cmd_generate)
    c = sub.add_parser("check", help="verify a manifest; non-zero exit on any deviation")
    c.add_argument("manifest")
    c.add_argument("--root")
    c.set_defaults(func=cmd_check)
    args = ap.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
