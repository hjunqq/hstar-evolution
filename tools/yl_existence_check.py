#!/usr/bin/env python3
"""The existence face's gates (ADR-0009).

`docs/m2/state-field-map.toml` answers "what do we compare".
`docs/m4/existence-face.toml` answers "what must exist" -- legacy arrays the solver
requires to be allocated and to carry the deck's values, but whose values no checkpoint
observes. Those two questions were safely confused until the adapter first drove a real
solve, at which point the difference showed up as an unallocated-array abort.

M3-03 put a single bijection between commit's derive rules and the map's model_ready
rows. That bijection is NOT widened here -- widening it is what would have made one table
mean two things. It keeps its exact meaning on the comparison face and this file gives
the existence face its own, of the same shape.

Three checks, every one a SET EQUALITY in both directions. Sufficient conditions are what
let a wrong claim through whichever one happens to hold; the L2-c fold's exit condition
was satisfiable by a lie for exactly that reason (docs/m4/L2c-fold-design.md).

  E1  the table's rows == deck_existence_t's `!@existence:` markers, and each component's
      NAME equals its row's `carrier`. The name half is not pedantry: until the residue
      carrier grew the same check (P12), renaming a component and leaving its marker alone
      passed every gate.
  E2  the table's rows == the symbols commit's existence pass writes, AND == the symbols
      commit_release releases. A row written and never released is a leak; a row released
      and never written is a claim about storage this module does not own.
  E3  the table's symbols are DISJOINT from the legacy symbols the map emits. A value that
      is compared must not also be registered as "not observed" -- if a symbol needs to be
      on both faces, the map is the one that wins and the row does not belong here.

Every row must also carry `observed_requirement`: the run that aborted for want of it, at
a named site. The defect this face exists to fix was a classification made by READING
(`order_time_mdofn` tagged "unused_switch / dynamic time integration") overturned by
EXECUTION. Admitting rows by reading would reproduce that defect one level up, so the
evidence line is mandatory and E0 refuses a row without one.

Usage:
    tools/yl_existence_check.py [--negative-control {carrier,commit,release,map,evidence}]
"""
from __future__ import annotations

import argparse
import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TABLE = ROOT / "docs/m4/existence-face.toml"
CARRIER = ROOT / "src/problem/yl_problem_existence.f90"
COMMIT = ROOT / "src/runtime/yl_runtime_commit.f90"
MAP = ROOT / "docs/m2/state-field-map.toml"

MARKER = re.compile(r"!@existence:\s*([A-Za-z_]\w*)")


def table_rows() -> dict[str, dict]:
    doc = tomllib.loads(TABLE.read_text(encoding="utf-8"))
    rows = {}
    for a in doc.get("array", []):
        sym = a.get("symbol")
        if not sym:
            raise SystemExit(f"{TABLE}: an [[array]] row has no symbol")
        if sym in rows:
            raise SystemExit(f"{TABLE}: symbol {sym} declared twice")
        rows[sym] = a
    if not rows:
        raise SystemExit(f"{TABLE}: no rows; the file exists to hold them")
    return rows


def carrier_components() -> dict[str, str]:
    """marker symbol -> the component name declared on the following line."""
    out, pending = {}, None
    for ln in CARRIER.read_text(encoding="utf-8").splitlines():
        m = MARKER.search(ln)
        if m and "::" not in ln:
            pending = m.group(1)
            continue
        if pending and "::" in ln:
            nm = re.search(r"::\s*([A-Za-z_]\w*)", ln)
            if nm:
                out[pending] = nm.group(1)
            pending = None
    return out


def commit_symbols() -> tuple[set[str], set[str]]:
    """(written by the existence pass, released by commit_release)."""
    written, released = set(), set()
    for ln in COMMIT.read_text(encoding="utf-8").splitlines():
        m = MARKER.search(ln)
        if not m:
            continue
        if "move_alloc" in ln:
            written.add(m.group(1))
        elif "deallocate" in ln:
            released.add(m.group(1))
    return written, released


def map_emitted_symbols() -> set[str]:
    doc = tomllib.loads(MAP.read_text(encoding="utf-8"))
    out = set()
    for f in doc["field"]:
        if f.get("emit") is None:
            continue
        sym = f.get("legacy_symbol")
        if sym:
            out.add(sym.rsplit(".", 1)[-1].lower())
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--negative-control",
                    choices=["carrier", "commit", "release", "map", "evidence"], default=None)
    a = ap.parse_args(argv)

    rows = table_rows()
    carriers = carrier_components()
    written, released = commit_symbols()
    emitted = map_emitted_symbols()

    nc = a.negative_control
    if nc:
        victim = sorted(rows)[0]
        print(f"NEGATIVE CONTROL ({nc}) on {victim}")
        if nc == "carrier":
            carriers.pop(victim, None)
        elif nc == "commit":
            written.discard(victim)
        elif nc == "release":
            released.discard(victim)
        elif nc == "map":
            emitted.add(victim)
        elif nc == "evidence":
            rows[victim] = {k: v for k, v in rows[victim].items()
                            if k != "observed_requirement"}

    problems = []

    # E0 -- every row carries the run that demanded it.
    for sym, r in sorted(rows.items()):
        if not str(r.get("observed_requirement", "")).strip():
            problems.append(f"E0 {sym}: no observed_requirement. A row may only be admitted "
                            f"after a real run aborted for want of it, at a named site; "
                            f"admitting it by reading is the defect this face exists to fix")

    # E1 -- table == carrier, both directions, and the names match.
    for sym in sorted(set(rows) - set(carriers)):
        problems.append(f"E1 {sym} is in {TABLE.name} but no deck_existence_t component "
                        f"claims it")
    for sym in sorted(set(carriers) - set(rows)):
        problems.append(f"E1 deck_existence_t claims {sym}, which is not a row of "
                        f"{TABLE.name}")
    for sym in sorted(set(rows) & set(carriers)):
        want = rows[sym].get("carrier")
        if carriers[sym] != want:
            problems.append(f"E1 {sym}: the component is named {carriers[sym]!r} but the "
                            f"table's carrier is {want!r}")

    # E2 -- table == written == released, both directions each.
    for sym in sorted(set(rows) - written):
        problems.append(f"E2 {sym} is a row of {TABLE.name} but commit's existence pass "
                        f"does not write it")
    for sym in sorted(written - set(rows)):
        problems.append(f"E2 commit's existence pass writes {sym}, which is not a row of "
                        f"{TABLE.name}")
    for sym in sorted(set(rows) - released):
        problems.append(f"E2 {sym} is written but commit_release does not release it -- "
                        f"a row this module allocates and never frees is a leak")
    for sym in sorted(released - set(rows)):
        problems.append(f"E2 commit_release releases {sym}, which is not a row of "
                        f"{TABLE.name} -- releasing storage this module may not own")

    # E3 -- the two faces are disjoint.
    for sym in sorted({s for s in rows if s.lower() in emitted}):
        problems.append(f"E3 {sym} is on BOTH faces: the map emits it and this table calls "
                        f"it unobserved. The map wins; drop the row here")

    for p in problems:
        print(f"FAIL {p}")
    if problems:
        print(f"EXISTENCE-FACE FAIL: {len(problems)} problem(s)")
        return 1
    print(f"EXISTENCE-FACE PASS: {len(rows)} row(s); table == carrier == commit writes == "
          f"commit releases (set equality, both directions each), disjoint from the "
          f"{len(emitted)} legacy symbols the map emits, every row carrying the run that "
          f"demanded it")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
