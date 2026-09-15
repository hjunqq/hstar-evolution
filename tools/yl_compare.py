#!/usr/bin/env python3
"""Compare two parsed result files (results.json from yl_run.py / yl_parse_flavia.py).

Structure first, values second (docs/06 "数值比较与容差登记"):
  * same block names in the same order, same result_type / ncomp / component names;
  * identical node-id sets per block;
  * then per component: |actual - reference| <= atol + rtol * |reference|.
Anything structural that differs, or any non-finite value, is a failure regardless
of tolerances. Tolerances default to exact equality (atol = rtol = 0), which is the
B02 repeat criterion; per-block tolerances can be supplied via --tolerances
(tolerances.toml section given by --section, e.g. cross_path).

Reporting is split on purpose. The REPORT FILE (-o) keeps everything, block by block and
value by value, so a result can be audited afterwards. STDOUT keeps only what a person can
act on: how many blocks, how many values, how many mismatched, the largest difference, and
-- only when something failed -- where the first mismatch is. A strength-reduction deck
runs to 600 blocks and half a million values, and a per-block line each would bury the one
fact that matters.

Usage:
  yl_compare.py REFERENCE.json ACTUAL.json [--tolerances tolerances.toml --section cross_path]
                [-o report.json]
Exit 0 only when everything passed.
"""
from __future__ import annotations

import argparse
import gzip
import json
import math
import sys
import tomllib
from pathlib import Path

BLOCK_TO_OBSERVABLE = {"DISPLACEMENT": "displacement", "STRESS": "stress"}


def load(path: Path) -> dict:
    """A results file, gzipped or not.

    A strength-reduction reference is 13.5 MB of JSON and 3.1 MB gzipped. The frozen
    artefact has to stay COMPLETE -- the roll-up on stdout is a summary, the file is the
    audit trail -- so it is compressed rather than trimmed. `.json` keeps working
    unchanged; only the reader learned a second spelling."""
    if path.suffix == ".gz":
        with gzip.open(path, "rt", encoding="utf-8") as fh:
            return json.load(fh)
    return json.loads(path.read_text(encoding="utf-8"))


def compare(ref: dict, act: dict, tol: dict[str, dict[str, float]]) -> dict:
    report = {"structure_ok": True, "problems": [], "blocks": [], "passed": False,
              "n_blocks": 0, "n_values": 0, "n_mismatch": 0, "max_abs_diff": 0.0,
              "first_mismatch": None}
    rb, ab = ref["blocks"], act["blocks"]
    rn, an = [b["name"] for b in rb], [b["name"] for b in ab]
    if rn != an:
        report["structure_ok"] = False
        # NOT the two full lists: a 100-step deck has 600 blocks and printing both names
        # every one of them buries the fact. Counts, then the first position that differs.
        where = next((i for i, (x, y) in enumerate(zip(rn, an)) if x != y), min(len(rn), len(an)))
        report["problems"].append(
            f"block names differ: reference has {len(rn)}, actual has {len(an)}; "
            f"first difference at block {where + 1}: "
            f"{rn[where] if where < len(rn) else '<none>'} vs "
            f"{an[where] if where < len(an) else '<none>'}")
        return report
    for r, a in zip(rb, ab):
        name = r["name"]
        entry = {"name": name, "ok": True, "n_values": 0, "n_mismatch": 0,
                 "max_abs_diff": 0.0, "max_abs_diff_at": None,
                 "max_norm_diff": 0.0, "max_norm_diff_at": None, "atol": 0.0, "rtol": 0.0,
                 "step": r.get("step")}
        for key in ("result_type", "ncomp", "components"):
            if r.get(key) != a.get(key):
                report["structure_ok"] = False
                report["problems"].append(f"{name}: {key} differs ({r.get(key)} vs {a.get(key)})")
                entry["ok"] = False
        rids, aids = set(r["rows"]), set(a["rows"])
        if rids != aids:
            report["structure_ok"] = False
            missing, extra = sorted(rids - aids, key=int)[:5], sorted(aids - rids, key=int)[:5]
            report["problems"].append(f"{name}: node sets differ (missing {missing}…, extra {extra}…)")
            entry["ok"] = False
        if not entry["ok"]:
            report["blocks"].append(entry)
            continue
        t = tol.get(BLOCK_TO_OBSERVABLE.get(name, name.lower()), {})
        atol, rtol = float(t.get("atol", 0.0)), float(t.get("rtol", 0.0))
        entry["atol"], entry["rtol"] = atol, rtol
        for nid in sorted(rids, key=int):
            rv, av = r["rows"][nid], a["rows"][nid]
            for k, (x, y) in enumerate(zip(rv, av)):
                entry["n_values"] += 1
                if not (math.isfinite(x) and math.isfinite(y)):
                    entry["ok"] = False
                    entry["n_mismatch"] += 1
                    note(report, entry, nid, k + 1, x, y, "non-finite")
                    continue
                d = abs(y - x)
                if d > entry["max_abs_diff"]:
                    entry["max_abs_diff"], entry["max_abs_diff_at"] = d, {"node": int(nid), "component": k + 1, "reference": x, "actual": y}
                bound = atol + rtol * abs(x)
                norm = d / bound if bound > 0 else (0.0 if d == 0 else math.inf)
                if norm > entry["max_norm_diff"]:
                    entry["max_norm_diff"], entry["max_norm_diff_at"] = norm, {"node": int(nid), "component": k + 1}
                if d > bound:
                    entry["ok"] = False
                    entry["n_mismatch"] += 1
                    note(report, entry, nid, k + 1, x, y, "outside tolerance")
        if entry["max_norm_diff"] == math.inf:
            entry["max_norm_diff"] = "inf"
        report["blocks"].append(entry)
    for b in report["blocks"]:
        report["n_values"] += b["n_values"]
        report["n_mismatch"] += b["n_mismatch"]
        if isinstance(b["max_abs_diff"], float):
            report["max_abs_diff"] = max(report["max_abs_diff"], b["max_abs_diff"])
    report["n_blocks"] = len(report["blocks"])
    report["passed"] = report["structure_ok"] and all(b["ok"] for b in report["blocks"]) and bool(report["blocks"])
    return report


def note(report: dict, entry: dict, nid: str, comp: int, x: float, y: float, why: str) -> None:
    """Record WHERE the first mismatch is, once. Blocks are walked in file order and nodes
    in id order, so `first` is deterministic and not merely "whichever we noticed"."""
    if report["first_mismatch"] is not None:
        return
    report["first_mismatch"] = {"block": entry["name"], "step": entry.get("step"),
                                "node": int(nid), "component": comp,
                                "reference": x, "actual": y, "why": why}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("reference")
    ap.add_argument("actual")
    ap.add_argument("--tolerances")
    ap.add_argument("--section", default="cross_path")
    ap.add_argument("-o", "--output")
    args = ap.parse_args(argv)
    tol: dict = {}
    if args.tolerances:
        doc = tomllib.loads(Path(args.tolerances).read_text(encoding="utf-8"))
        sec = doc.get(args.section, {})
        tol = {k: v for k, v in sec.items() if isinstance(v, dict)}
    report = compare(load(Path(args.reference)), load(Path(args.actual)), tol)
    report["reference"], report["actual"], report["tolerance_section"] = args.reference, args.actual, args.section if args.tolerances else "exact"
    if args.output:
        Path(args.output).write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    verdict = "PASS" if report["passed"] else "FAIL"
    print(f"{verdict}  blocks={report['n_blocks']} values={report['n_values']} "
          f"mismatches={report['n_mismatch']} max|d|={report['max_abs_diff']:.3e}")
    if not report["passed"]:
        for p in report["problems"][:5]:
            print("  structure: " + p)
        if len(report["problems"]) > 5:
            print(f"  structure: +{len(report['problems']) - 5} more (see the report file)")
        fm = report["first_mismatch"]
        if fm:
            where = f"{fm['block']}"
            if fm.get("step") is not None:
                where += f" step={fm['step']}"
            print(f"  first mismatch: {where} node={fm['node']} comp={fm['component']} "
                  f"{fm['why']}: reference={fm['reference']!r} actual={fm['actual']!r}")
        if not args.output:
            print("  (re-run with -o report.json for the full per-block detail)")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
