#!/usr/bin/env python3
"""M5 exit condition: the new input format drives the solver, and the numbers are the old ones.

The M5 acceptance criteria are user-visible capabilities, not internal state, so this gate
asserts exactly those:

  N1  every golden case runs from `--input=<case>/modern/case.toml` alone -- the legacy
      control deck (.glb/.man/.pre/.mat/.loa/.sol/...) is NOT copied into the work
      directory, so a run that still reads one cannot pass by accident. Only the mesh
      files the contract names (`mesh.file` -> `<prefix>.cor` / `.ele`) are present.
  N2  the results are byte-identical to the FROZEN legacy reference, strictly
      (atol = rtol = 0, per ADR-0008 SS4: the noise measurement found none).
  N3  a deck the contract rejects STOPS with a readable diagnostic (exit 2 INVALID_INPUT
      or 3 UNSUPPORTED) and writes no results. Without N3 the gate would be satisfied by
      an --input that silently ignored what it could not understand.

N1 is the assertion that makes this different from the M4-02 fallback gate: that one
proved the adapter could drive the legacy solver from the legacy deck; this one proves the
authoring format can, from itself.

Usage:
    tools/yl_modern_check.py [--binary build/release/hstar]
"""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAP = ROOT / "docs/m2/state-field-map.toml"
GOLDEN = ROOT / "cases/golden/static_2d"


def cases() -> list[str]:
    return tomllib.loads(MAP.read_text(encoding="utf-8"))["cases"]


def mesh_prefix(deck: Path) -> str:
    """`mesh.file` out of the contract deck. Read with a line regex rather than a TOML
    parser because that is the one key this gate must agree with the Fortran reader on,
    and the Fortran reader accepts a strict subset."""
    for line in deck.read_text(encoding="utf-8").splitlines():
        m = re.match(r"\s*file\s*=\s*\"([^\"]*)\"\s*(#.*)?$", line)
        if m:
            return m.group(1)
    raise SystemExit(f"{deck}: no `file = \"...\"` line under [mesh]")


def stage(name: str, work: Path) -> Path:
    """The mesh and the contract deck. Nothing else -- see N1."""
    deck = GOLDEN / name / "modern/case.toml"
    prefix = mesh_prefix(deck)
    for suffix in (".cor", ".ele"):
        src = GOLDEN / name / "legacy" / (prefix + suffix)
        shutil.copyfile(src, work / src.name)
    shutil.copyfile(deck, work / "case.toml")
    return work / "case.toml"


def compare(ref: Path, actual: Path) -> tuple[bool, str]:
    cp = subprocess.run([sys.executable, str(ROOT / "tools/yl_compare.py"), str(ref), str(actual)],
                        capture_output=True, text=True)
    line = cp.stdout.strip().splitlines()[0] if cp.stdout.strip() else cp.stderr.strip()
    return cp.returncode == 0, line


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--binary", default=str(ROOT / "build/release/hstar"))
    a = ap.parse_args(argv)
    binary = Path(a.binary).resolve()
    if not binary.is_file():
        raise SystemExit(f"binary missing: {binary} (run tools/build.sh release)")

    problems: list[str] = []

    for cid in cases():
        name = cid.split(".", 1)[1]
        ref = GOLDEN / name / "reference/results.json"
        with tempfile.TemporaryDirectory(prefix="yl-modern.") as td:
            work = Path(td)
            stage(name, work)
            cp = subprocess.run([str(binary), "--input=case.toml"], cwd=work,
                                stdin=subprocess.DEVNULL, capture_output=True,
                                text=True, errors="replace")
            res = work / "1.flavia.res"
            if cp.returncode != 0 or not (res.is_file() and res.stat().st_size > 0):
                problems.append(f"N1 {cid}: the modern-input run exited {cp.returncode} "
                                f"without results\n{(cp.stdout + cp.stderr)[-800:]}")
                print(f"  N1 {cid:<28} rc={cp.returncode} FAIL")
                continue
            print(f"  N1 {cid:<28} rc=0, mesh + case.toml only")

            out = work / "results.json"
            pp = subprocess.run([sys.executable, str(ROOT / "tools/yl_parse_flavia.py"),
                                 str(res), "-o", str(out)], capture_output=True, text=True)
            if pp.returncode != 0:
                problems.append(f"N2 {cid}: the output did not parse\n{pp.stdout + pp.stderr}")
                continue
            ok, line = compare(ref, out)
            print(f"  N2 {cid:<28} vs frozen reference  {line}")
            if not ok:
                problems.append(f"N2 {cid}: the modern path does not reproduce the reference")

    # N3 -- a deck the contract rejects must stop, readably.
    name = cases()[0].split(".", 1)[1]
    with tempfile.TemporaryDirectory(prefix="yl-modern-bad.") as td:
        work = Path(td)
        deck = stage(name, work)
        text = deck.read_text(encoding="utf-8")
        # A capability refusal, not a typo: a whitelisted key carrying an unlisted value.
        assert 'element     = "Q4"' in text, "deck no longer carries the mutated line"
        deck.write_text(text.replace('element     = "Q4"', 'element     = "Q8"'), encoding="utf-8")
        cp = subprocess.run([str(binary), "--input=case.toml"], cwd=work,
                            stdin=subprocess.DEVNULL, capture_output=True,
                            text=True, errors="replace")
        blob = cp.stdout + cp.stderr
        named = "element" in blob and "Q8" in blob
        res = work / "1.flavia.res"
        wrote = res.is_file() and res.stat().st_size > 0
        print(f"  N3 refused deck                rc={cp.returncode} "
              f"names_key_and_value={'yes' if named else 'NO'} "
              f"results_written={'YES' if wrote else 'no'}")
        if cp.returncode not in (2, 3):
            problems.append(f"N3 a rejected deck exited {cp.returncode}, not 2/3")
        if not named:
            problems.append("N3 the rejection named neither the key nor the value")
        if wrote:
            problems.append("N3 the rejected deck still produced results")

    for p in problems:
        print(f"FAIL {p}")
    if problems:
        print(f"MODERN FAIL: {len(problems)} problem(s)")
        return 1
    print("MODERN PASS: every golden case runs from case.toml + mesh alone and reproduces "
          "the frozen legacy reference exactly; a rejected deck stops with the key named")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
