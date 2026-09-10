#!/usr/bin/env python3
"""M4-02 exit condition: the adapter is the default entry, and the fallback is tested.

Four assertions, and the fourth is the one worth the tool:

  F1  DEFAULT (no flag) reproduces the frozen reference on every golden case, strictly.
      Strict is what ADR-0008 SS4 permits: the noise measurement found none.
  F2  --adapter=off reproduces it too. The fallback has to be a working path, not a
      documented one.
  F3  the two paths agree with each other, not merely with the reference. F1 and F2
      could both pass while the two paths differed on something the reference does not
      contain -- a checkpoint field, a different NaN, an output file only one writes.
  F4  the switch never decides anything by itself. On a deck the adapter refuses, the
      run must STOP with the dialect verdict; it must NOT quietly fall back to the
      legacy readers. An automatic fallback would mean a deck the adapter cannot model
      still produces numbers, with nothing in the output saying which path made them --
      which is exactly what the M4 exit condition forbids.

Usage:
    tools/yl_fallback_check.py [--binary build/release/hstar]
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAP = ROOT / "docs/m2/state-field-map.toml"


def cases() -> list[str]:
    return tomllib.loads(MAP.read_text(encoding="utf-8"))["cases"]


def run(case_id: str, binary: Path, root: Path, label: str, args: str | None,
        expect: str | None = "COMPLETED") -> tuple[int, Path | None, str]:
    cmd = [sys.executable, str(ROOT / "tools/yl_run.py"), "--case-id", case_id,
           "--binary", str(binary), "--runs-root", str(root), "--label", label]
    if args:
        cmd += ["--binary-args", args]
    if expect:
        cmd += ["--expect-status", expect]
    cp = subprocess.run(cmd, capture_output=True, text=True)
    dirs = sorted((root / case_id).glob(f"*_{label}"))
    d = dirs[-1] if dirs else None
    return cp.returncode, d, cp.stdout + cp.stderr


def compare(a: Path, b: Path) -> tuple[bool, str]:
    cp = subprocess.run([sys.executable, str(ROOT / "tools/yl_compare.py"), str(a), str(b)],
                        capture_output=True, text=True)
    return cp.returncode == 0, cp.stdout.strip().splitlines()[0] if cp.stdout else cp.stderr.strip()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--binary", default=str(ROOT / "build/release/hstar"))
    a = ap.parse_args(argv)
    binary = Path(a.binary)
    if not binary.is_file():
        raise SystemExit(f"binary missing: {binary} (run tools/build.sh release)")

    root = Path(tempfile.mkdtemp(prefix="yl-fallback."))
    problems: list[str] = []

    for cid in cases():
        name = cid.split(".", 1)[1]
        ref = ROOT / "cases/golden/static_2d" / name / "reference/results.json"

        rc, d_def, out = run(cid, binary, root, "default", None)
        if rc != 0 or d_def is None:
            problems.append(f"F1 {cid}: the DEFAULT run did not complete\n{out[-600:]}")
            continue
        ok, line = compare(ref, d_def / "results.json")
        print(f"  F1 {cid:<28} default        {line}")
        if not ok:
            problems.append(f"F1 {cid}: the default path does not reproduce the reference")

        rc, d_off, out = run(cid, binary, root, "off", "--adapter=off")
        if rc != 0 or d_off is None:
            problems.append(f"F2 {cid}: --adapter=off did not complete\n{out[-600:]}")
            continue
        ok, line = compare(ref, d_off / "results.json")
        print(f"  F2 {cid:<28} --adapter=off  {line}")
        if not ok:
            problems.append(f"F2 {cid}: the fallback path does not reproduce the reference")

        ok, line = compare(d_off / "results.json", d_def / "results.json")
        print(f"  F3 {cid:<28} off vs default {line}")
        if not ok:
            problems.append(f"F3 {cid}: the two paths disagree with each other")

    # F4 -- a deck the adapter refuses must STOP, not fall back.
    with tempfile.TemporaryDirectory(prefix="yl-fallback-deck.") as td:
        name = cases()[0].split(".", 1)[1]
        src = ROOT / "cases/golden/static_2d" / name / "legacy"
        work = Path(td)
        for f in src.iterdir():
            (work / f.name).write_bytes(f.read_bytes())
        glb = work / "1.glb"
        lines = glb.read_bytes().split(b"\n")
        # tension_joint_count: a capability row the adapter refuses (A-GLB).
        lines[64] = b"  1"
        glb.write_bytes(b"\n".join(lines))
        cp = subprocess.run([str(binary)], cwd=work, stdin=subprocess.DEVNULL,
                            capture_output=True, text=True, errors="replace")
        blob = cp.stdout + cp.stderr
        verdict = "UNSUPPORTED" in blob and "tension_joint_count" in blob
        # An EMPTY 1.flavia.res is not a result: global_data opens the GiD units before
        # the adapter entry runs, so the file exists as a zero-byte artefact of that open.
        # What must not happen is CONTENT.
        f = work / "1.flavia.res"
        res = f.is_file() and f.stat().st_size > 0
        print(f"  F4 refused deck                rc={cp.returncode} "
              f"verdict={'yes' if verdict else 'NO'} "
              f"results_written={'YES' if res else 'no'}")
        if cp.returncode != 3:
            problems.append(f"F4 a refused deck exited {cp.returncode}, not 3 "
                            f"(UNSUPPORTED); the outward verdict must survive the entry")
        if cp.returncode == 0:
            problems.append("F4 a deck the adapter refuses exited 0 -- the switch decided "
                            "for itself")
        if not verdict:
            problems.append("F4 the refusal did not name the dialect it refused")
        if res:
            problems.append("F4 the refused deck still produced 1.flavia.res -- something "
                            "fell back and the output does not say which path made it")

    for p in problems:
        print(f"FAIL {p}")
    if problems:
        print(f"FALLBACK FAIL: {len(problems)} problem(s)")
        return 1
    print("FALLBACK PASS: default path == fallback path == frozen reference on every "
          "golden case (strict), and a refused deck stops with its dialect named instead "
          "of falling back")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
