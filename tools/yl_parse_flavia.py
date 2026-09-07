#!/usr/bin/env python3
"""Parse a GiD "flavia.res" ASCII result file written by YL (M0-04a).

Layout observed on the reference runs (2026-09-07):

    <name> <analysis> <step> <result_type> <location> <describe_components>
    [<component name> ...]            only when describe_components == 1
    <node_id> <v1> ... <vN>           one row per node, E-format, 8 significant digits

result_type 2 = vector, 3 = matrix. The number of components is taken from the
data rows; every row of a block must have the same length.

Validation is fail-closed: missing node ids, duplicated ids, non-finite values,
ragged rows, unexpected node count or an empty file all make `validate` return
problems and the CLI exit 1.

Usage:
  yl_parse_flavia.py FILE [--expect-nodes N] [-o OUT.json]
"""
from __future__ import annotations

import argparse
import json
import math
import re
import sys
from pathlib import Path

NUM_ROW = re.compile(r"^\s*\d+\s+[-+0-9.NnIi]")  # digits, sign, or NaN/Inf tokens


def parse(path: Path) -> dict:
    text = path.read_text(encoding="latin-1")
    lines = [ln.rstrip("\n") for ln in text.splitlines()]
    blocks: list[dict] = []
    i = 0
    n = len(lines)
    while i < n:
        s = lines[i].strip()
        if not s:
            i += 1
            continue
        if NUM_ROW.match(lines[i]):
            raise ValueError(f"{path}: data row without a block header at line {i + 1}")
        head = s.split()
        if len(head) < 6:
            raise ValueError(f"{path}: malformed block header at line {i + 1}: {s!r}")
        block = {
            "name": head[0],
            "analysis": int(head[1]),
            "step": float(head[2]),
            "result_type": int(head[3]),
            "location": int(head[4]),
            "describe_components": int(head[5]),
            "components": [],
            "ncomp": None,
            "rows": {},
        }
        i += 1
        if block["describe_components"] == 1:
            # Component names: one per line until a numeric row starts.
            while i < n and lines[i].strip() and not NUM_ROW.match(lines[i]):
                block["components"].append(lines[i].strip())
                i += 1
        while i < n and NUM_ROW.match(lines[i]):
            parts = lines[i].split()
            nid = int(parts[0])
            vals = [float(v) for v in parts[1:]]
            if block["ncomp"] is None:
                block["ncomp"] = len(vals)
            elif len(vals) != block["ncomp"]:
                raise ValueError(f"{path}: ragged row for node {nid} in block {block['name']} at line {i + 1}")
            if nid in block["rows"]:
                raise ValueError(f"{path}: duplicate node id {nid} in block {block['name']}")
            block["rows"][nid] = vals
            i += 1
        blocks.append(block)
    return {"format": "gid-flavia-ascii", "source": str(path), "blocks": blocks}


def validate(parsed: dict, expect_nodes: int | None) -> list[str]:
    problems: list[str] = []
    if not parsed["blocks"]:
        problems.append("no result blocks")
        return problems
    for b in parsed["blocks"]:
        tag = b["name"]
        if not b["rows"]:
            problems.append(f"{tag}: no data rows")
            continue
        if b["components"] and len(b["components"]) != b["ncomp"]:
            problems.append(f"{tag}: {len(b['components'])} component names but {b['ncomp']} values per row")
        ids = sorted(b["rows"])
        if expect_nodes is not None:
            if len(ids) != expect_nodes:
                problems.append(f"{tag}: {len(ids)} nodes, expected {expect_nodes}")
            if ids[0] != 1 or ids[-1] != len(ids):
                problems.append(f"{tag}: node ids are not 1..{len(ids)} (first {ids[0]}, last {ids[-1]})")
        for nid, vals in b["rows"].items():
            for k, v in enumerate(vals):
                if not math.isfinite(v):
                    problems.append(f"{tag}: non-finite value at node {nid} component {k + 1}")
                    break
    return problems


def summary(parsed: dict) -> dict:
    out = []
    for b in parsed["blocks"]:
        flat = [v for vals in b["rows"].values() for v in vals]
        out.append(
            {
                "name": b["name"],
                "result_type": b["result_type"],
                "step": b["step"],
                "components": b["components"],
                "ncomp": b["ncomp"],
                "nodes": len(b["rows"]),
                "max_abs": max((abs(v) for v in flat), default=None),
            }
        )
    return {"blocks": out}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("file")
    ap.add_argument("--expect-nodes", type=int)
    ap.add_argument("-o", "--output")
    args = ap.parse_args(argv)
    p = Path(args.file)
    if not p.is_file() or p.stat().st_size == 0:
        print(f"FAIL: {p} missing or empty", file=sys.stderr)
        return 1
    try:
        parsed = parse(p)
    except ValueError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    problems = validate(parsed, args.expect_nodes)
    if args.output:
        doc = {**parsed, "blocks": [{**b, "rows": {str(k): v for k, v in b["rows"].items()}} for b in parsed["blocks"]]}
        Path(args.output).write_text(json.dumps(doc, indent=1) + "\n", encoding="utf-8")
    if problems:
        print(f"FAIL: {p}")
        for line in problems:
            print("  " + line)
        return 1
    print(json.dumps(summary(parsed)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
