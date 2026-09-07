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

Usage:
  yl_compare.py REFERENCE.json ACTUAL.json [--tolerances tolerances.toml --section cross_path]
                [-o report.json]
Exit 0 only when everything passed.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
import tomllib
from pathlib import Path

BLOCK_TO_OBSERVABLE = {"DISPLACEMENT": "displacement", "STRESS": "stress"}


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def compare(ref: dict, act: dict, tol: dict[str, dict[str, float]]) -> dict:
    report = {"structure_ok": True, "problems": [], "blocks": [], "passed": False}
    rb, ab = ref["blocks"], act["blocks"]
    if [b["name"] for b in rb] != [b["name"] for b in ab]:
        report["structure_ok"] = False
        report["problems"].append(f"block names differ: {[b['name'] for b in rb]} vs {[b['name'] for b in ab]}")
        return report
    for r, a in zip(rb, ab):
        name = r["name"]
        entry = {"name": name, "ok": True, "n_values": 0, "max_abs_diff": 0.0, "max_abs_diff_at": None,
                 "max_norm_diff": 0.0, "max_norm_diff_at": None, "atol": 0.0, "rtol": 0.0}
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
                    report["problems"].append(f"{name}: non-finite at node {nid} comp {k + 1}")
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
        if not entry["ok"] and not any(p.startswith(name) for p in report["problems"]):
            report["problems"].append(f"{name}: tolerance exceeded, max |diff| {entry['max_abs_diff']:.6e} at {entry['max_abs_diff_at']}")
        if entry["max_norm_diff"] == math.inf:
            entry["max_norm_diff"] = "inf"
        report["blocks"].append(entry)
    report["passed"] = report["structure_ok"] and all(b["ok"] for b in report["blocks"]) and bool(report["blocks"])
    return report


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
    print(f"{verdict}  " + "; ".join(f"{b['name']}: n={b['n_values']} max|d|={b['max_abs_diff']:.3e}" for b in report["blocks"]))
    for p in report["problems"]:
        print("  " + p)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
