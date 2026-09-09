#!/usr/bin/env python3
"""Cross-check docs/m2/state-field-map.toml's prose against the frozen baseline.

WHY THIS EXISTS
    Three defects of one shape have been found in the map by tripping over them
    during M4-01, never by looking:

      * control.glb.stab_matde's note said the field is 0 and concluded
        stab_initialize runs every step; both decks carry 99999, a disable
        sentinel, and it never runs.
      * the 2026-09-08 correction for that landed on control.run.restart's note,
        overwriting text that was about restart and leaving stab_matde's own note
        still carrying the disproven claim (fixed in a8d4646).
      * derived.counts.nsmat's note said "0 on both cases"; both decks carry 1,
        and at 0 the stiffness-reform condition at Fem.f90:15499 is
        unconditionally true rather than true once per step (fixed in 0646de3).

    Each one inverted a control-flow conclusion, and each was found only because
    the fold happened to touch that row. The map's `reason` and `note` are prose
    a human wrote; the frozen baseline under cases/golden/*/reference/state/ is
    measured. Where the prose states a value, the two can be compared
    mechanically, and that is all this does.

WHAT IT CHECKS, AND WHAT IT DELIBERATELY DOES NOT
    CHECKED: a model_ready row whose reason/note asserts a concrete value in one
    of the recognised phrasings ("pinned N", "N on both cases", "value N"), where
    the baseline records a scalar for that row. If none of the numbers the prose
    asserts equals the baseline value on either deck, the row is reported.

    The "none of the numbers" rule is deliberately lenient: notes are full of line
    numbers (Fem.f90:3658) and a strict rule would drown in them. The cost is a
    known blind spot, stated rather than hidden -- a note that mentions several
    numbers passes if ANY of them matches. That is exactly why it does not catch
    the misplacement defect above, where the wrong note happened to contain a 0
    and the row's baseline was 0.

    NOT CHECKED: misplacement (a note about a different field). A detector for
    that was written and validated -- it does flag control.run.restart on the map
    as it stood before a8d4646, and stops flagging it after -- but it reports ~51
    rows on a clean map, because a note legitimately explains its field in terms
    of other symbols ("= count(mesh.nodes); sizes coord/nodfn"). At that
    signal-to-noise it is an audit one runs by hand, not a gate: a gate that fires
    on noise teaches the next person to ignore it. It is not included here.

VALIDATION (positive control, not an assertion)
    Run with --positive-control to check the detector against the map as it stood
    before 0646de3, where it must report derived.counts.nsmat. A detector that
    finds nothing is worthless unless it has been shown to find something.
"""
from __future__ import annotations

import argparse
import glob
import json
import re
import subprocess
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CASES = ["cooks_membrane", "lame_cylinder"]

# "pinned 0", "pinned guard: value 0", "0 on both cases", "both golden decks carry 99999"
CLAIM = re.compile(
    r"(?:pinned(?:\s+guard:)?\s*(?:value\s+)?|value\s+|is\s+)(-?\d+)\b"
    r"|(-?\d+)\s+on both"
    r"|both\s+(?:golden\s+)?(?:cases|decks)[^.]{0,30}?(-?\d+)",
    re.I,
)


def load_baseline() -> dict[str, dict]:
    out = {}
    for case in CASES:
        merged = {}
        pat = ROOT / "cases/golden/static_2d" / case / "reference/state/model_ready/*.json"
        for f in glob.glob(str(pat)):
            j = json.load(open(f))
            merged.update(j.get("fields", j))
        out[case] = merged
    return out


def scalar_of(entry):
    if isinstance(entry, dict):
        entry = entry.get("values", entry.get("value"))
    return entry if isinstance(entry, (int, float)) else None


def check(map_text: bytes, baseline) -> tuple[int, list[str]]:
    m = tomllib.loads(map_text.decode("utf-8"))
    checked, findings = 0, []
    for r in m["field"]:
        if r.get("checkpoint") != "model_ready":
            continue
        vals = {c: scalar_of(baseline[c].get(r["id"])) for c in CASES}
        vals = {c: v for c, v in vals.items() if v is not None}
        if not vals:
            continue
        # reason and note are checked SEPARATELY. Joining them lets a correct
        # number in one mask a wrong number in the other -- found by a negative
        # control: injecting a false `reason` for control.glb.stab_matde while
        # its note still said 99999 produced no finding at all.
        for field in ("reason", "note"):
            prose = r.get(field)
            if not prose:
                continue
            claims = {int(g) for mm in CLAIM.finditer(prose)
                      for g in mm.groups() if g is not None}
            if not claims:
                continue
            checked += 1
            if not any(v in claims for v in vals.values()):
                findings.append(
                    f"{r['id']} ({field}): asserts {sorted(claims)}, the frozen "
                    f"baseline records {vals}\n    \"{prose[:200]}\""
                )
    return checked, findings


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--map", default=str(ROOT / "docs/m2/state-field-map.toml"))
    ap.add_argument(
        "--positive-control",
        action="store_true",
        help="also run against the map before 0646de3, where derived.counts.nsmat MUST be reported",
    )
    a = ap.parse_args()
    baseline = load_baseline()

    if a.positive_control:
        old = subprocess.run(
            ["git", "show", "0646de3^:docs/m2/state-field-map.toml"],
            cwd=ROOT, capture_output=True,
        )
        if old.returncode != 0:
            print("positive control: cannot read the pre-fix map; NOT VERIFIED", file=sys.stderr)
            return 3
        _, found = check(old.stdout, baseline)
        if not any(f.startswith("derived.counts.nsmat ") for f in found):
            print("positive control FAILED: the detector no longer finds the nsmat defect "
                  "it was built from -- a clean result from it would mean nothing", file=sys.stderr)
            return 3
        print("  ok   positive control: the detector still finds the known nsmat defect")

    checked, findings = check(Path(a.map).read_bytes(), baseline)
    for f in findings:
        print(f"  MAP-PROSE {f}")
    if findings:
        print(f"FAIL: {len(findings)} of {checked} value-asserting reason/note fields "
              f"contradict the frozen baseline")
        return 1
    print(f"  ok   {checked} value-asserting reason/note fields agree with the frozen baseline")
    return 0


if __name__ == "__main__":
    sys.exit(main())
