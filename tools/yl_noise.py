#!/usr/bin/env python3
"""Measure whether repeated runs actually produce non-zero numeric noise (ADR-0008 §4).

`cases/golden/*/tolerances.toml` carries a `[cross_path]` section marked
`status = "provisional"`, whose numbers are dimensional estimates ("atol = 1e-9 x
displacement scale"). Nothing measured them, and R28 records that using them as a
criterion would mean judging M4-02's cross-path comparison against an invented
number -- which can turn noise into a difference or a difference into noise.

The owner's ruling is to not turn this into a research project:

  1. first measure whether the same binary, on the same input, in the same
     environment, repeated, produces any non-zero difference at all;
  2. only if noise is observed, derive a tolerance from what was measured;
  3. if the runs are stable, compare strictly and introduce no tolerance.

This tool does step 1. It runs one binary N times per case through the isolated
runner, compares every pair of runs at EXACT equality (atol = rtol = 0), and
reports the largest |difference| actually seen.

Reading the result honestly:

  * `max|d| = 0` over N runs does NOT prove the run is deterministic. It bounds
    the OBSERVED noise at zero for this binary, this input, this environment and
    this repeat count -- and that is exactly the claim step 3 needs, no more.
    The verdict line says so in those words rather than "deterministic".
  * a non-zero result is a measurement, and the tolerance is then derived from
    the distribution printed here, not from a scale estimate.
  * the environment is held fixed on purpose (the runner already pins
    single-threaded execution and drops LD_LIBRARY_PATH). Varying the thread
    count is a DIFFERENT question and would answer a different one; if it is ever
    asked, it must be measured separately and labelled separately.

Usage:
    tools/yl_noise.py measure [--repeats N] [--binary build/release/hstar]
                              [--case ID ...] [-o docs/m4/evidence/noise/noise.json]
    tools/yl_noise.py measure --negative-control   # perturb one run, must be caught
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
import tomllib
from itertools import combinations
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAP = ROOT / "docs/m2/state-field-map.toml"


def cases_from_map() -> list[str]:
    return tomllib.loads(MAP.read_text(encoding="utf-8"))["cases"]


def one_run(case_id: str, binary: Path, runs_root: Path, label: str) -> Path:
    cp = subprocess.run([sys.executable, str(ROOT / "tools/yl_run.py"),
                         "--case-id", case_id, "--binary", str(binary),
                         "--runs-root", str(runs_root), "--label", label,
                         "--expect-status", "COMPLETED"],
                        capture_output=True, text=True)
    if cp.returncode != 0:
        raise SystemExit(f"{case_id}/{label}: runner failed rc={cp.returncode}\n"
                         f"{cp.stdout[-2000:]}\n{cp.stderr[-2000:]}")
    # The runner prints the run directory; find the newest one carrying results.json.
    cands = sorted((runs_root / case_id).glob(f"*_{label}"), key=lambda p: p.name)
    if not cands:
        cands = sorted((runs_root / case_id).iterdir(), key=lambda p: p.name)
    for d in reversed(cands):
        if (d / "results.json").is_file():
            return d
    raise SystemExit(f"{case_id}/{label}: no results.json under {runs_root / case_id}")


def compare(a: Path, b: Path) -> dict:
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tf:
        out = Path(tf.name)
    cp = subprocess.run([sys.executable, str(ROOT / "tools/yl_compare.py"),
                         str(a / "results.json"), str(b / "results.json"), "-o", str(out)],
                        capture_output=True, text=True)
    rep = json.loads(out.read_text(encoding="utf-8"))
    out.unlink(missing_ok=True)
    rep["_rc"] = cp.returncode
    return rep


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    m = sub.add_parser("measure")
    m.add_argument("--repeats", type=int, default=8)
    m.add_argument("--binary", default=str(ROOT / "build/release/hstar"))
    m.add_argument("--case", action="append", default=None)
    m.add_argument("-o", "--output", default=str(ROOT / "docs/m4/evidence/noise/noise.json"))
    m.add_argument("--runs-root", default=None)
    m.add_argument("--negative-control", action="store_true",
                   help="corrupt one value of one run before comparing; the pairwise "
                        "comparison must then report a non-zero max|d| naming it")
    a = ap.parse_args(argv)

    binary = Path(a.binary)
    if not binary.is_file():
        raise SystemExit(f"binary missing: {binary} (run tools/build.sh release)")
    if a.repeats < 2:
        raise SystemExit("--repeats must be at least 2: one run compares with nothing")
    cases = a.case or cases_from_map()
    runs_root = Path(a.runs_root) if a.runs_root else Path(tempfile.mkdtemp(prefix="yl-noise."))

    doc = {"version": 1, "binary": str(binary), "repeats": a.repeats,
           "negative_control": bool(a.negative_control), "cases": {}}
    worst = 0.0
    for cid in cases:
        runs = [one_run(cid, binary, runs_root, f"noise{i:02d}") for i in range(a.repeats)]
        print(f"{cid}: {len(runs)} runs")
        if a.negative_control:
            # Move one displacement component by 1 ulp-ish so the comparison has
            # something real to find; a control that changes nothing proves nothing.
            rj = runs[-1] / "results.json"
            d = json.loads(rj.read_text(encoding="utf-8"))
            blk = d["blocks"][0]
            nid = sorted(blk["rows"])[0]
            old = blk["rows"][nid][0]
            blk["rows"][nid][0] = old + (abs(old) * 1e-12 or 1e-18)
            rj.write_text(json.dumps(d), encoding="utf-8")
            print(f"  NEGATIVE CONTROL: {blk['name']} node {nid} comp 1 "
                  f"{old!r} -> {blk['rows'][nid][0]!r}")
        per_block: dict[str, float] = {}
        pairs, failed = 0, 0
        for x, y in combinations(runs, 2):
            rep = compare(x, y)
            pairs += 1
            if not rep.get("structure_ok", False):
                raise SystemExit(f"{cid}: structural difference between two runs of the "
                                 f"same binary -- that is not noise: {rep['problems'][:3]}")
            if not rep["passed"]:
                failed += 1
            for b in rep["blocks"]:
                per_block[b["name"]] = max(per_block.get(b["name"], 0.0), b["max_abs_diff"])
        doc["cases"][cid] = {"runs": [r.name for r in runs], "pairs": pairs,
                             "pairs_with_difference": failed,
                             "max_abs_diff_by_block": per_block}
        worst = max([worst] + list(per_block.values()))
        print("  " + "; ".join(f"{k}: max|d|={v:.3e}" for k, v in sorted(per_block.items()))
              + f"  ({pairs} pairs, {failed} with a difference)")

    doc["max_abs_diff_overall"] = worst
    doc["verdict"] = ("no non-zero noise observed" if worst == 0.0
                      else "non-zero noise observed")
    out = Path(a.output)
    if not a.negative_control:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(doc, indent=1) + "\n", encoding="utf-8")

    n = a.repeats
    if worst == 0.0:
        print(f"NOISE: none observed. {n} runs per case, "
              f"{n*(n-1)//2} pairs each, exact comparison, max|d| = 0 everywhere.")
        print("  This BOUNDS the observed noise at zero for this binary, this input, "
              "this environment and this repeat count. It is not a proof of determinism,")
        print("  and it says nothing about other thread counts or environments.")
        print("  Per ADR-0008 §4 the cross-path comparison is therefore STRICT: "
              "no tolerance is derived, because none was measured.")
        return 0 if not a.negative_control else 1
    if a.negative_control:
        print(f"NEGATIVE CONTROL FIRED: max|d| = {worst:.6e} -- the comparison does see "
              f"a difference this small, so a clean measurement is worth believing.")
        return 0
    print(f"NOISE: non-zero, max|d| = {worst:.6e} over {n} runs per case. "
          f"Derive the cross-path tolerance from this distribution, not from a scale estimate.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
