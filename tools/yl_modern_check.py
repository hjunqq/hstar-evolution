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
      an --input that silently ignored what it could not understand. Three shapes, because
      they failed differently and one of them failed silently:
        a  an unlisted value  -> exit 3, key and value named
        b  a file that is not there, and one that is not the contract's TOML subset ->
           exit 2, the name the operator typed. Both used to fall through to the LEGACY
           reader, which prompted `Input the problem name?` and then produced a Fortran
           traceback: probn is set before the entry runs, so the entry never got its turn.
        c  three findings in one deck -> each rendered EXACTLY once, with its own line
           number. They were briefly printed twice, once by the validator's caller and
           once by the refusal, which is the sort of thing only an assertion catches.

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

    def rejected(label: str, arg: str, mutate=None) -> str:
        """Run a deck that must be refused; assert the run stopped and wrote nothing.
        Returns the combined output so the caller can assert what it SAID."""
        with tempfile.TemporaryDirectory(prefix="yl-modern-bad.") as td:
            work = Path(td)
            deck = stage(name, work)
            if mutate is not None:
                deck.write_text(mutate(deck.read_text(encoding="utf-8")), encoding="utf-8")
            cp = subprocess.run([str(binary), arg], cwd=work, stdin=subprocess.DEVNULL,
                                capture_output=True, text=True, errors="replace")
            res = work / "1.flavia.res"
            wrote = res.is_file() and res.stat().st_size > 0
            print(f"  N3 {label:<28} rc={cp.returncode} "
                  f"results_written={'YES' if wrote else 'no'}")
            if cp.returncode not in (2, 3):
                problems.append(f"N3 {label}: exited {cp.returncode}, not 2/3 -- a deck "
                                f"the contract refuses must stop with the input verdict")
            if wrote:
                problems.append(f"N3 {label}: still produced results")
            return cp.stdout + cp.stderr

    def sub(a: str, b: str):
        def f(text: str) -> str:
            assert a in text, f"deck no longer carries the mutated line: {a}"
            return text.replace(a, b, 1)
        return f

    # a -- a whitelisted key carrying an unlisted value: a capability refusal, not a typo.
    blob = rejected("unlisted value", "--input=case.toml",
                    sub('element     = "Q4"', 'element     = "Q8"'))
    if "element" not in blob or "Q8" not in blob:
        problems.append("N3 unlisted value: the rejection named neither the key nor the value")

    # b -- unreadable at all. The name the operator typed has to appear: these two used to
    # fall through to the legacy reader and die there with no mention of the input file.
    blob = rejected("file not there", "--input=absent.toml")
    if "absent.toml" not in blob:
        problems.append("N3 file not there: the refusal never named the file asked for")
    if "Input the problem name" in blob:
        problems.append("N3 file not there: fell through to the legacy reader's prompt")

    blob = rejected("not the TOML subset", "--input=case.toml",
                    lambda _: 'version = 1\n[case\nname = "x"\n')
    if "case.toml:2" not in blob:
        problems.append("N3 not the TOML subset: the refusal did not point at line 2")
    if "Input the problem name" in blob:
        problems.append("N3 not the TOML subset: fell through to the legacy reader's prompt")

    # c -- several findings at once, each reported exactly once.
    blob = rejected("three findings", "--input=case.toml",
                    lambda t: sub("density = 2400.0", 'density = "heavy"')(
                              sub("nu      = 0.2", "nu_typo = 0.2")(t)))
    for want, label in (("material[1].density", "wrong type"),
                        ("material[1].nu_typo", "unknown key"),
                        ("material[1].nu", "missing required")):
        n = sum(1 for line in blob.splitlines() if f"{want}:" in line)
        if n != 1:
            problems.append(f"N3 three findings: `{want}` ({label}) was rendered {n} times, "
                            f"not once")

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
