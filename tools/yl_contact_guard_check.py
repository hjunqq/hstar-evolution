#!/usr/bin/env python3
"""M12 fail-closed contact guards: positive and negative controls.

The guards themselves are three statements appended (with `;`) to existing legacy lines:

  Stiff.f90:878 / Residu.f90:1156   PD-4  a GOODMAN/JANBU material whose .mat header does
                                          NOT declare name=CONTACT is refused, because
                                          gapg/natural_thickness are allocated only for a
                                          CONTACT material (Fem.f90:11999-12008).
  Fem.f90:12768                     PD-5  a CONTACT material with igap0 /= 99 is refused,
                                          because natural_thickness is ASSIGNED only on the
                                          igap0==99 path (Fem.f90:12882-12884) while it is
                                          CONSUMED at Fem.f90:12936 and Stiff.f90:880.

A guard that never fires is not evidence, and a guard that fires on a legal deck is worse
than none. So this gate runs both directions:

  C1  NEGATIVE, PD-4 -- a real GOODMAN deck whose joint material is declared SOLID must now
      stop with exit 3 and site="Stiff.f90:dep", instead of the SIGSEGV (rc=174, no output)
      it produced before the guard. The deck lives in the curated case library OUTSIDE this
      repository, so when it is not present this control prints SKIP and names the path --
      loudly, never silently, and never as a pass.
  C2  NEGATIVE, PD-5 -- derived at run time from an in-repo golden deck: one material header
      is rewritten to `MECHANICAL CONTACT n` and an `igap0 gap0 ftcontact icft` record with
      igap0=1 is inserted. Must stop with exit 3 and site="Fem.f90:contact_state".
      NOTHING physical is invented: the run is refused at the moment igap0 is read, before
      any of those numbers is consumed, and the fixture is never written into cases/.
  C3  POSITIVE -- the same golden deck, unmodified, must still run to completion. This is
      what makes C2 mean something: the only difference between them is the declaration.

The nine golden cases reproducing their frozen references bit-for-bit (yl_modern_check /
yl_fallback_check) is the wider positive control; this gate does not duplicate it.

Usage:
    tools/yl_contact_guard_check.py [--binary build/release/hstar]
                                    [--goodman-deck DIR] [--keep]
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

import importlib.util as _ilu
_spec = _ilu.spec_from_file_location("yl_run", ROOT / "tools/yl_run.py")
_yl_run = _ilu.module_from_spec(_spec); _spec.loader.exec_module(_yl_run)
pinned_env = _yl_run.pinned_env

GOLDEN = ROOT / "cases/golden/plasticity/mini_mc/legacy"
# The curated library is not part of this repository; C1 names it and skips when absent.
DEFAULT_GOODMAN = Path("/home/huijun/HSTAR_Next/cases/cases/goodman_evolution")

DIAG = re.compile(r'(\w+)="((?:[^"\\]|\\.)*)"|(\w+)=(\S+)')


def parse_diag(stderr: str) -> dict | None:
    for line in stderr.splitlines():
        if not line.startswith("HSTAR_DIAG "):
            continue
        out = {}
        for m in DIAG.finditer(line[len("HSTAR_DIAG "):]):
            k = m.group(1) or m.group(3)
            v = m.group(2) if m.group(1) else m.group(4)
            out[k] = v.replace('\\"', '"')
        return out
    return None


def run(deck: Path, binary: Path, work: Path) -> tuple[int, dict | None, int]:
    work.mkdir(parents=True, exist_ok=True)
    for f in deck.iterdir():
        if f.is_file() and f.name != "1.flavia.res":
            shutil.copy2(f, work / f.name)
    if not (work / "inp").exists():
        (work / "inp").write_text(
            "restart,relis,sysrelis,ADINA,Uopt_R,gamamax\n0  0  0  0  0  0\nprobn\n1\n1\n")
    res = work / "1.flavia.res"
    if res.exists():
        res.unlink()
    p = subprocess.run([str(binary), "--adapter=off"], cwd=work, input=b"\n\n\n\n",
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=1800,
                       env={**os.environ, **pinned_env()})
    size = res.stat().st_size if res.exists() else 0
    return p.returncode, parse_diag(p.stderr.decode("latin-1")), size


def derive_contact_igap0(src: Path, dst: Path, igap0: int) -> None:
    """Copy the deck, declaring material 1 as CONTACT with the given igap0.

    Two edits to 1.mat only, both on latin-1 bytes with line endings kept:
      * the material-1 header's PHASE token SOLID -> CONTACT (Material.f90:283 reads
        property, name, imat; `name` is what Fem.f90:11741/12763 compare against 'CONTACT');
      * one record `igap0 gap0 ftcontact icft` inserted where Material.f90:419 reads it,
        i.e. after the generic solid record and before the next material_serial.
    """
    dst.mkdir(parents=True, exist_ok=True)
    for f in src.iterdir():
        if f.is_file() and f.name != "1.flavia.res":
            shutil.copy2(f, dst / f.name)
    mat = dst / "1.mat"
    lines = mat.read_bytes().split(b"\n")
    hdr = None
    for i, l in enumerate(lines):
        if b"material_serial" in l and i + 1 < len(lines) and b"SOLID" in lines[i + 1]:
            hdr = i + 1
            break
    if hdr is None:
        raise SystemExit("derive: no material header with phase SOLID in " + str(mat))
    lines[hdr] = lines[hdr].replace(b"SOLID", b"CONTACT", 1)
    nxt = next((j for j in range(hdr + 1, len(lines)) if b"material_serial" in lines[j]), None)
    if nxt is None:
        raise SystemExit("derive: material 1 is the last record; need a following one")
    eol = b"\r" if lines[nxt].endswith(b"\r") else b""
    lines.insert(nxt, b"  %d  0.0  0.0  0" % igap0 + eol)
    mat.write_bytes(b"\n".join(lines))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--binary", default="build/release/hstar")
    ap.add_argument("--goodman-deck", default=str(DEFAULT_GOODMAN))
    ap.add_argument("--keep", action="store_true")
    a = ap.parse_args()
    binary = Path(a.binary).resolve()
    if not binary.exists():
        print(f"CONTACT-GUARD FAIL: no such binary {binary}", file=sys.stderr)
        return 1

    tmp = Path(tempfile.mkdtemp(prefix="contact-guard-"))
    failures: list[str] = []
    try:
        # C1 -- PD-4, on a real deck.
        deck = Path(a.goodman_deck)
        if not deck.is_dir():
            print(f"  C1 PD-4 GOODMAN declared SOLID   SKIP -- deck not present: {deck}")
            print("     (curated library is outside this repository; this control did NOT run)")
        else:
            rc, d, size = run(deck, binary, tmp / "c1")
            ok = (rc == 3 and d and d.get("code") == "UNSUPPORTED"
                  and d.get("site") == "Stiff.f90:dep" and "PD-4" in d.get("message", "")
                  and size == 0)
            print(f"  C1 PD-4 GOODMAN declared SOLID   rc={rc} site={d and d.get('site')} "
                  f"results_written={'no' if size == 0 else 'YES'} {'PASS' if ok else 'FAIL'}")
            if ok:
                print(f"     {d['message'][:150]}")
            else:
                failures.append("C1: expected exit 3 at Stiff.f90:dep naming PD-4, "
                                f"got rc={rc} diag={d}")

        # C3 -- POSITIVE first: the unmodified golden deck must still run.
        rc, d, size = run(GOLDEN, binary, tmp / "c3")
        ok = rc == 0 and size > 0
        print(f"  C3 golden deck unmodified        rc={rc} results={size}B "
              f"{'PASS' if ok else 'FAIL'}")
        if not ok:
            failures.append(f"C3: the guards changed a legal path -- rc={rc} diag={d}")

        # C2 -- PD-5, derived from that same deck.
        derive_contact_igap0(GOLDEN, tmp / "c2-deck", igap0=1)
        rc, d, size = run(tmp / "c2-deck", binary, tmp / "c2")
        ok = (rc == 3 and d and d.get("code") == "UNSUPPORTED"
              and d.get("site") == "Fem.f90:contact_state" and "PD-5" in d.get("message", "")
              and size == 0)
        print(f"  C2 PD-5 CONTACT with igap0=1     rc={rc} site={d and d.get('site')} "
              f"results_written={'no' if size == 0 else 'YES'} {'PASS' if ok else 'FAIL'}")
        if ok:
            print(f"     {d['message'][:150]}")
        else:
            failures.append("C2: expected exit 3 at Fem.f90:contact_state naming PD-5, "
                            f"got rc={rc} diag={d}")
    finally:
        if a.keep:
            print(f"  (fixtures kept in {tmp})")
        else:
            shutil.rmtree(tmp, ignore_errors=True)

    if failures:
        for f in failures:
            print("CONTACT-GUARD FAIL: " + f, file=sys.stderr)
        return 1
    print("CONTACT-GUARD PASS: the contact fail-closed guards refuse the two shapes they name "
          "and leave a legal deck untouched")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
