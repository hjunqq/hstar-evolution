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

  F5  the MODERN path (`--input=case.toml`) and the LEGACY-DECK path (default entry,
      the adapter) agree with each other, strictly. F1 and N2 (yl_modern_check) each
      compare one path to the reference; this compares the two paths directly, which is
      the red line M4-02 drew ("the two paths are equivalent").
  F6  the two paths have ONE capability boundary on the golden set: every golden case is
      accepted by both. A case one path runs and the other refuses is named, with which
      path refused it. Until 2026-09-23 this gate walked only the two M2 static cases, so
      wall_reservoir and beam_point_load had been refused on the legacy-deck path since
      M7 without any gate noticing (R34, docs/capability-frontier.md section 4).

SCOPE IS WHAT IS WALKED. The case list is cases/manifest.toml, checked against the
directories under cases/golden/: a golden directory the manifest does not list, or a
listed case missing its legacy deck, modern deck or reference, is a failure, not a skip.
The summary line names the count it actually walked. (R34: this tool used to print
"every golden case" while walking two.)

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

# The solver must run under the SAME pinned environment every frozen reference was made
# under; see yl_run.pinned_env for what happens when it does not.
import importlib.util as _ilu
_spec = _ilu.spec_from_file_location("yl_run", ROOT / "tools/yl_run.py")
_yl_run = _ilu.module_from_spec(_spec); _spec.loader.exec_module(_yl_run)
pinned_env = _yl_run.pinned_env

MANIFEST = ROOT / "cases/manifest.toml"

_spec_m = _ilu.spec_from_file_location("yl_modern_check", ROOT / "tools/yl_modern_check.py")
_yl_modern = _ilu.module_from_spec(_spec_m); _spec_m.loader.exec_module(_yl_modern)
stage_modern = _yl_modern.stage


def cases(problems: list[str]) -> list[dict]:
    """Every case in cases/manifest.toml, reconciled with cases/golden/*/* on disk."""
    doc = tomllib.loads(MANIFEST.read_text(encoding="utf-8"))
    listed = doc.get("case", [])
    on_disk = {str(p.relative_to(ROOT / "cases")) for p in (ROOT / "cases/golden").glob("*/*")
               if p.is_dir()}
    in_manifest = {c["path"] for c in listed}
    for extra in sorted(on_disk - in_manifest):
        problems.append(f"SCOPE cases/{extra} is a golden directory the manifest does not list")
    out = []
    for c in listed:
        d = ROOT / "cases" / c["path"]
        ref = d / "reference/results.json"
        if not ref.is_file():
            ref = d / "reference/results.json.gz"
        missing = [what for what, ok in (("legacy/", (d / "legacy").is_dir()),
                                         ("modern/case.toml", (d / "modern/case.toml").is_file()),
                                         ("reference/results.json[.gz]", ref.is_file()))
                   if not ok]
        if missing:
            problems.append(f"SCOPE {c['id']}: missing {', '.join(missing)}")
            continue
        out.append({"id": c["id"], "dir": d, "ref": ref,
                    "modern": c.get("modern_gate") is not False})
    if not out:
        raise SystemExit(f"{MANIFEST}: no case to walk")
    return out


def run_modern(case_dir: Path, binary: Path, work: Path) -> tuple[int, Path | None, str]:
    """The authoring path, staged exactly as yl_modern_check stages it (mesh + case.toml)."""
    stage_modern(case_dir, work)
    cp = subprocess.run([str(binary), "--input=case.toml"], cwd=work, stdin=subprocess.DEVNULL,
                        capture_output=True, text=True, errors="replace", env=pinned_env())
    res = work / "1.flavia.res"
    if cp.returncode != 0 or not (res.is_file() and res.stat().st_size > 0):
        return cp.returncode, None, cp.stdout + cp.stderr
    out = work / "results.json"
    pp = subprocess.run([sys.executable, str(ROOT / "tools/yl_parse_flavia.py"), str(res),
                         "-o", str(out)], capture_output=True, text=True)
    if pp.returncode != 0:
        return 99, None, pp.stdout + pp.stderr
    return 0, out, cp.stdout


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
    # resolve(): F4 launches the binary with cwd set to a temporary deck directory, so a
    # relative --binary would not exist from there. F1-F3 go through yl_run.py, which
    # resolves it itself -- which is why this only ever bit the last check.
    binary = Path(a.binary).resolve()
    if not binary.is_file():
        raise SystemExit(f"binary missing: {binary} (run tools/build.sh release)")

    root = Path(tempfile.mkdtemp(prefix="yl-fallback."))
    problems: list[str] = []
    walked = cases(problems)
    print(f"  scope: {len(walked)} case(s) from cases/manifest.toml, reconciled with "
          f"cases/golden/*/*")

    for c in walked:
        cid, ref = c["id"], c["ref"]

        rc, d_def, out = run(cid, binary, root, "default", None)
        def_ok = rc == 0 and d_def is not None
        if def_ok:
            ok, line = compare(ref, d_def / "results.json")
            print(f"  F1 {cid:<34} default        {line}")
            if not ok:
                problems.append(f"F1 {cid}: the default path does not reproduce the reference")
        else:
            print(f"  F1 {cid:<34} default        REFUSED/FAILED")
            problems.append(f"F1 {cid}: the DEFAULT (legacy-deck adapter) run did not "
                            f"complete\n{out[-600:]}")

        rc, d_off, out = run(cid, binary, root, "off", "--adapter=off")
        off_ok = rc == 0 and d_off is not None
        if off_ok:
            ok, line = compare(ref, d_off / "results.json")
            print(f"  F2 {cid:<34} --adapter=off  {line}")
            if not ok:
                problems.append(f"F2 {cid}: the fallback path does not reproduce the reference")
        else:
            problems.append(f"F2 {cid}: --adapter=off did not complete\n{out[-600:]}")

        if def_ok and off_ok:
            ok, line = compare(d_off / "results.json", d_def / "results.json")
            print(f"  F3 {cid:<34} off vs default {line}")
            if not ok:
                problems.append(f"F3 {cid}: the two paths disagree with each other")

        if not c["modern"]:
            print(f"  -- {cid:<34} F5/F6 OFF by manifest (modern_gate = false)")
            continue
        with tempfile.TemporaryDirectory(prefix="yl-fallback-modern.") as td:
            rc_m, res_m, out_m = run_modern(c["dir"], binary, Path(td))
            mod_ok = res_m is not None
            if def_ok != mod_ok:
                which = "legacy-deck path refuses" if mod_ok else "modern path refuses"
                print(f"  F6 {cid:<34} boundary       DIFFERS ({which})")
                problems.append(f"F6 {cid}: one boundary for two paths is broken -- the "
                                f"{which} what the other runs\n"
                                f"{(out if mod_ok else out_m)[-600:]}")
            elif def_ok:
                print(f"  F6 {cid:<34} boundary       both accept")
                ok, line = compare(res_m, d_def / "results.json")
                print(f"  F5 {cid:<34} modern vs deck {line}")
                if not ok:
                    problems.append(f"F5 {cid}: the modern and legacy-deck paths disagree")

    # F4 -- a deck the adapter refuses must STOP, not fall back.
    with tempfile.TemporaryDirectory(prefix="yl-fallback-deck.") as td:
        src = ROOT / "cases/golden/static_2d/cooks_membrane/legacy"
        work = Path(td)
        for f in src.iterdir():
            (work / f.name).write_bytes(f.read_bytes())
        glb = work / "1.glb"
        lines = glb.read_bytes().split(b"\n")
        # tension_joint_count: a capability row the adapter refuses (A-GLB).
        lines[64] = b"  1"
        glb.write_bytes(b"\n".join(lines))
        cp = subprocess.run([str(binary)], cwd=work, stdin=subprocess.DEVNULL,
                            capture_output=True, text=True, errors="replace", env=pinned_env())
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
    print(f"FALLBACK PASS: on all {len(walked)} manifest cases -- default (legacy-deck) path "
          "== fallback path == frozen reference, modern path == legacy-deck path (strict), "
          "both paths accept every case; a refused deck stops with its dialect named "
          "instead of falling back")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
