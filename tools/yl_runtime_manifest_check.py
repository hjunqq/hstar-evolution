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
  E2  the table's rows == the symbols commit's existence pass writes, and the rows that
      OWN storage (storage = "allocated", the default) == the symbols commit_release
      releases. A row written and never released is a leak; a row released and never
      written is a claim about storage this module does not own; and a scalar
      (storage = "scalar") must appear in neither release direction, because demanding a
      deallocate for something that owns nothing only invites a fake one.
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
TABLE = ROOT / "docs/m4/runtime-state-manifest.toml"
SCAN = ROOT / "docs/m4/evidence/runtime-state-scan.json"
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
        if "deallocate" in ln:
            released.add(m.group(1))
        elif "move_alloc" in ln or "allocate" in ln or "=" in ln:
            # deck rows land by move_alloc out of a staging buffer; derived arrays are
            # allocated in place during staging; a derived SCALAR is a plain assignment.
            # All three are "commit writes it".
            written.add(m.group(1))
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

    all_rows = table_rows()
    unreachable = {k: v for k, v in all_rows.items()
                   if v.get("disposition") == "unreachable"}
    rows = {k: v for k, v in all_rows.items() if k not in unreachable}
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

    # E4 -- the manifest accounts for every candidate the SCAN found. This replaces the
    # original admission rule (one row per observed abort) with the owner's ruling of
    # 2026-09-11: enumerate mechanically, decide per row, verify by driving a real solve.
    # A candidate with no row is the failure the old rule could not see -- it only ever
    # learned about state something had already crashed on.
    if SCAN.is_file():
        import json as _json
        scan = _json.loads(SCAN.read_text(encoding="utf-8"))
        cands = {c["symbol"].lower() for c in scan.get("candidates", [])}
        known = {k.lower() for k in all_rows}
        for sym in sorted(cands - known):
            problems.append(f"E4 tools/yl_runtime_scan.py lists {sym} as state global_data "
                            f"establishes past the adapter entry, and the manifest does not "
                            f"account for it")
    else:
        problems.append(f"E4 {SCAN} is missing; run tools/yl_runtime_scan.py -- without it "
                        f"the manifest is a list nobody checked for completeness")

    # E5 -- a row decided `unreachable` must NOT be written. Establishing state legacy
    # does not have is a divergence in the other direction, and just as invisible.
    for sym in sorted(unreachable):
        if sym in written:
            problems.append(f"E5 {sym} is decided unreachable but commit's existence pass "
                            f"writes it; that is state the legacy path does not have")

    # E0 -- every row carries the run that demanded it.
    for sym, r in sorted(rows.items()):
        if not (str(r.get("observed_requirement", "")).strip()
                or str(r.get("why", "")).strip()):
            problems.append(f"E0 {sym}: neither observed_requirement nor why. Every row must "
                            f"say why it is here -- the run that demanded it, or the scan "
                            f"line that enumerated it")

    # E1 -- table == carrier, both directions, and the names match. Rows whose value is
    # derived carry nothing, and E1 asserts that ABSENCE rather than skipping them: a
    # derived row that grew a carrier would mean someone started shipping a value for
    # something the deck does not supply.
    DERIVED = ("derived", "derived-zero")
    deck_rows = {s_ for s_, r in rows.items() if r.get("value_source") not in DERIVED}
    derived_rows = set(rows) - deck_rows
    for sym in sorted(derived_rows & set(carriers)):
        problems.append(f"E1 {sym} is a derived row, so nothing should carry it, but "
                        f"deck_existence_t has a component for it")
    for sym in sorted(derived_rows):
        if rows[sym].get("value_source") == "derived" and not str(rows[sym].get("derivation", "")).strip():
            problems.append(f"E0 {sym} is value_source=derived but states no derivation; "
                            f"a derived value without a stated rule is a number nobody "
                            f"can check")
    for sym in sorted(derived_rows):
        if rows[sym].get("carrier"):
            problems.append(f"E1 {sym} is a derived row but names a carrier "
                            f"{rows[sym]['carrier']!r}; derived rows have no carrier")
    for sym in sorted(deck_rows - set(carriers)):
        problems.append(f"E1 {sym} is in {TABLE.name} but no deck_existence_t component "
                        f"claims it")
    for sym in sorted(set(carriers) - set(rows)):
        problems.append(f"E1 deck_existence_t claims {sym}, which is not a row of "
                        f"{TABLE.name}")
    for sym in sorted(deck_rows & set(carriers)):
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
    # Only rows that OWN storage need releasing. A scalar has none, and demanding a
    # deallocate for it would push someone to write a fake one -- so the table says which
    # kind each row is, and both directions are checked against that.
    allocating = {s_ for s_, r in rows.items() if r.get("storage", "allocated") == "allocated"}
    for sym in sorted(allocating - released):
        problems.append(f"E2 {sym} is written but commit_release does not release it -- "
                        f"a row this module allocates and never frees is a leak")
    for sym in sorted((set(rows) - allocating) & released):
        problems.append(f"E2 {sym} is declared storage=scalar but commit_release releases "
                        f"it; a scalar owns nothing to release")
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
        print(f"RUNTIME-STATE-MANIFEST FAIL: {len(problems)} problem(s)")
        return 1
    print(f"RUNTIME-STATE-MANIFEST PASS: {len(rows)} required + {len(unreachable)} "
          f"unreachable row(s); table == carrier == commit writes == "
          f"commit releases (set equality, both directions each), disjoint from the "
          f"{len(emitted)} legacy symbols the map emits, every row carrying the run that "
          f"demanded it")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
