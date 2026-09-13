#!/usr/bin/env python3
"""Freeze a case's legacy reference: run it N times, require identity, write reference/.

M0 froze the two static references by hand. The material domain needs one per capability,
and every later domain needs more, so the procedure becomes a script -- a migration method
that only exists as prose is not reproducible.

What it does, in order:
  1. runs the case N times (default 3) through tools/yl_run.py with --adapter=off, i.e. the
     LEGACY readers. The reference must be what legacy produces, never what the adapter
     produces, or the comparison that follows would be the adapter checking itself;
  2. requires every run to be COMPLETED, requires `1.flavia.res` to be BYTE identical
     across runs, and requires the parsed results to compare exactly (atol = rtol = 0,
     the B02 repeat criterion). Any deviation aborts and writes nothing;
  3. writes <case>/reference/: results.json, run-manifest-<k>.json, repeat-report.json.

It does NOT write a state baseline. The static cases carry one because M2 compares state
field by field across paths; a domain case is accepted on FINAL NUMERICAL equivalence, and
a state baseline that nothing compares is a file that can only rot.

Refuses to overwrite an existing reference/ without --force: a frozen reference that can be
silently regenerated is not frozen.

Usage:
    tools/yl_freeze.py --case-id plasticity.mini_mc --case-dir cases/golden/plasticity/mini_mc
                       [--binary build/release/hstar] [--runs 3] [--force]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def sha256(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--case-id", required=True)
    ap.add_argument("--case-dir", required=True)
    ap.add_argument("--binary", default="build/release/hstar")
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--force", action="store_true",
                    help="replace an existing reference/ (a deliberate re-freeze)")
    a = ap.parse_args(argv)

    case_dir = (ROOT / a.case_dir).resolve()
    binary = (ROOT / a.binary).resolve()
    ref = case_dir / "reference"
    if not binary.is_file():
        raise SystemExit(f"binary missing: {binary}")
    if ref.exists() and not a.force:
        raise SystemExit(f"{ref} already exists; re-freezing needs --force and a reason "
                         f"in the commit message")
    if a.runs < 2:
        raise SystemExit("--runs must be at least 2: one run cannot show repeatability")

    runs_root = Path(tempfile.mkdtemp(prefix="yl-freeze."))
    records, dirs = [], []
    for k in range(1, a.runs + 1):
        label = f"ref{k}"
        cp = subprocess.run(
            [sys.executable, str(ROOT / "tools/yl_run.py"), "--case-id", a.case_id,
             "--binary", str(binary), "--runs-root", str(runs_root), "--label", label,
             "--case-dir", str(case_dir), "--binary-args", "--adapter=off"],
            capture_output=True, text=True)
        found = sorted((runs_root / a.case_id).glob(f"*_{label}"))
        if cp.returncode != 0 or not found:
            raise SystemExit(f"run {label} did not complete:\n{cp.stdout}\n{cp.stderr}")
        d = found[-1]
        dirs.append(d)
        man = json.loads((d / "run-manifest.json").read_text())
        res = d / "work" / "1.flavia.res"
        records.append({
            "label": label,
            "status": man.get("status"),
            "wall_seconds": man.get("wall_seconds"),
            "max_rss_kib": man.get("max_rss_kib"),
            "flavia_res_sha256": sha256(res) if res.is_file() else None,
        })
        print(f"  {label}: {man.get('status')}  sha256={records[-1]['flavia_res_sha256']}")

    bad = [r for r in records if r["status"] != "COMPLETED"]
    if bad:
        raise SystemExit(f"not every run COMPLETED: {bad}")
    digests = {r["flavia_res_sha256"] for r in records}
    if len(digests) != 1 or None in digests:
        raise SystemExit(f"1.flavia.res is not byte-identical across runs: {digests}")

    # Byte identity already implies value identity, but the comparator is what every later
    # gate uses, so run it: if it disagreed with the bytes, the comparator is the problem
    # and this is where we want to find that out, not in a domain gate months later.
    for d in dirs[1:]:
        cp = subprocess.run([sys.executable, str(ROOT / "tools/yl_compare.py"),
                             str(dirs[0] / "results.json"), str(d / "results.json")],
                            capture_output=True, text=True)
        if cp.returncode != 0:
            raise SystemExit(f"identical bytes but the comparator disagrees:\n{cp.stdout}")
        print(f"  compare {dirs[0].name} vs {d.name}: {cp.stdout.strip().splitlines()[0]}")

    ref.mkdir(parents=True, exist_ok=True)
    # `source` in the runner's results.json is the path inside the scratch run directory,
    # which stops existing the moment this script cleans up. A frozen artefact pointing at
    # a vanished temp directory is worse provenance than none, so it is replaced by what
    # the reader actually needs: which case, which entry, which run.
    parsed = json.loads((dirs[0] / "results.json").read_text(encoding="utf-8"))
    parsed["source"] = (f"{a.case_id} legacy/1.flavia.res, produced by --adapter=off, "
                        f"run ref1 of {a.runs} (see repeat-report.json)")
    (ref / "results.json").write_text(json.dumps(parsed, indent=1) + "\n", encoding="utf-8")
    for k, d in enumerate(dirs, 1):
        shutil.copyfile(d / "run-manifest.json", ref / f"run-manifest-{k}.json")
    (ref / "repeat-report.json").write_text(json.dumps({
        "case_id": a.case_id,
        "test_id": "B02",
        "frozen_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "binary_sha256": sha256(binary),
        "build_profile": "release",
        "entry": "--adapter=off (legacy readers); the reference is what LEGACY produces",
        "threads": {k: os.environ.get(k, "1") for k in ("OMP_NUM_THREADS", "MKL_NUM_THREADS")},
        "runs": records,
        "all_completed": True,
        "flavia_res_identical": True,
        "comparison_rule": "atol = rtol = 0 (B02)",
    }, indent=1) + "\n", encoding="utf-8")
    shutil.rmtree(runs_root, ignore_errors=True)
    print(f"FROZEN {a.case_id} -> {ref.relative_to(ROOT)} ({a.runs} runs, identical)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
