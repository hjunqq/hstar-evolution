#!/usr/bin/env python3
"""R29: check the adapter's reader coverage mechanically, instead of counting it by hand.

`docs/m1/reader-inventory.toml` is the register of legacy reads on the static path.
`src/adapter/**` reproduces them, each read carrying a marker comment naming the inventory
id it stands for:

    ! seq 7 -- RD: GLB.global_data.init_and_blocks (Global.f90:762)

Nothing checked the two against each other until now, which is R29: every claim of the
form "the adapter covers all the reads on this path" was neither provable nor refutable.
Two independent hand counts of the gap disagreed (28 vs 36), and at least one entry in the
gap turned out to be covered all along -- the marker just spelled the id differently.

Six assertions:

  C1  every marker line yields at least one id, and every id it yields is a real inventory
      id. This is the one that catches a misspelled marker: an id nobody can resolve is
      indistinguishable from no coverage, and reads like coverage.
  C2  every ON-PATH reader (one the golden-case evidence recorded as executed) is either
      referenced by a marker or registered in docs/m1/adapter-coverage.toml.
  C3  nothing is both marked and registered -- the registry says "no parser covers this",
      and a marker says one does.
  C4  every registered id exists, is on-path, and its `state_target` matches the
      inventory's. A registry row cannot drift away from the census it excuses.
  C5  a registered row whose target is not `title_skip` / `empty_section` -- one that
      carries a real value -- must carry `evidence`.
  C6  the registry is printed BY NAME on every run. A named list can be reviewed; the
      number that opened R29 could not.

Duplicate markers are allowed and are not an error: two adapter call sites legitimately
reproduce the same legacy read (`derive_deck_prefix` and `parse_inp` both walk `.inp`).

Usage:
    tools/yl_coverage_check.py [--quiet]
    tools/yl_coverage_check.py --selftest
"""
from __future__ import annotations

import argparse
import re
import sys
import tomllib
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INVENTORY = ROOT / "docs/m1/reader-inventory.toml"
REGISTRY = ROOT / "docs/m1/adapter-coverage.toml"
ADAPTER = ROOT / "src/adapter"

MARKER = "RD:"
# <FILE>.<routine>.<record slug>[#k] -- the inventory's own id rule.
ID = re.compile(r"\b[A-Z][A-Z0-9]*\.[A-Za-z0-9_]+\.[A-Za-z0-9_]+(?:#\d+)?")
# Targets a registry row may excuse without further evidence: a line that is thrown away,
# and a count that is zero. Anything else carries a value.
BENIGN = {"title_skip", "empty_section"}


def load_inventory(path: Path) -> dict[str, dict]:
    return {r["id"]: r for r in tomllib.loads(path.read_text(encoding="utf-8"))["reader"]}


def load_registry(path: Path) -> list[dict]:
    return tomllib.loads(path.read_text(encoding="utf-8")).get("not_adapted", [])


def scan_markers(root: Path) -> tuple[dict[str, list[str]], list[tuple[str, int, str]]]:
    """Marker id -> where it appears, plus every marker line that yielded no id at all."""
    found: dict[str, list[str]] = defaultdict(list)
    barren: list[tuple[str, int, str]] = []
    for p in sorted(root.rglob("*.f90")):
        rel = p.relative_to(ROOT)
        for n, line in enumerate(p.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            if MARKER not in line:
                continue
            tail = line.split(MARKER, 1)[1]
            ids = ID.findall(tail)
            if not ids:
                barren.append((str(rel), n, tail.strip()[:72]))
                continue
            for i in ids:
                found[i].append(f"{rel}:{n}")
    return found, barren


def check(inventory: dict[str, dict], registry: list[dict],
          marked: dict[str, list[str]], barren) -> list[str]:
    problems: list[str] = []
    on_path = {i for i, r in inventory.items() if r.get("executed_by")}

    # C1 -- markers resolve.
    for rel, n, text in barren:
        problems.append(f"C1 {rel}:{n}: a marker line with no resolvable reader id: {text!r}. "
                        f"Either it names a reader and the id is misspelled, or it is prose "
                        f"and should not carry the marker prefix")
    for i, sites in sorted(marked.items()):
        if i not in inventory:
            problems.append(f"C1 {sites[0]}: `{i}` is not an id in {INVENTORY.name}")

    registered = {row.get("id"): row for row in registry}

    # C2 -- every on-path reader is accounted for.
    for i in sorted(on_path):
        if i not in marked and i not in registered:
            r = inventory[i]
            problems.append(f"C2 {i} ({r['site']}): on the executed path, no adapter marker "
                            f"and no row in {REGISTRY.name}")

    # C3 -- not both.
    for i in sorted(set(marked) & set(registered)):
        problems.append(f"C3 {i}: marked at {marked[i][0]} AND registered as not adapted; "
                        f"one of the two is wrong")

    # C4/C5 -- the registry cannot drift, and cannot excuse a value silently.
    for row in registry:
        i = row.get("id")
        if i not in inventory:
            problems.append(f"C4 {i!r}: registered but not an id in {INVENTORY.name}")
            continue
        if i not in on_path:
            problems.append(f"C4 {i}: registered but not on the executed path; a reader that "
                            f"never runs needs no excuse")
        want = inventory[i].get("state_target")
        if row.get("state_target") != want:
            problems.append(f"C4 {i}: registry says state_target={row.get('state_target')!r}, "
                            f"the inventory says {want!r}")
        if not str(row.get("reason", "")).strip():
            problems.append(f"C4 {i}: registered with no reason")
        if want not in BENIGN and not str(row.get("evidence", "")).strip():
            problems.append(f"C5 {i}: state_target={want!r} carries a value, so the row needs "
                            f"`evidence`, measured rather than argued")
    return problems


def report(inventory, registry, marked, quiet: bool) -> None:
    on_path = {i for i, r in inventory.items() if r.get("executed_by")}
    covered = sorted(on_path & set(marked))
    print(f"  readers on the executed path: {len(on_path)} of {len(inventory)} in the census")
    print(f"  covered by an adapter marker: {len(covered)}")
    print(f"  registered as not adapted:    {len(registry)}")
    if quiet:
        return
    # C6 -- by name, every run. This is the half of the gate a human reads.
    by_file: dict[str, list[str]] = defaultdict(list)
    for row in registry:
        by_file[inventory.get(row["id"], {}).get("file", "?")].append(row["id"])
    for f in sorted(by_file):
        print(f"  NOT ADAPTED {f}: " + ", ".join(sorted(by_file[f])))


def selftest() -> int:
    """Every assertion gets a fixture that trips it. A gate nobody has seen fail is a gate
    nobody has tested."""
    inv = {
        "GLB.a.kept":    {"site": "G:1", "executed_by": ["c"], "state_target": "derived", "file": ".glb"},
        "GLB.a.title#1": {"site": "G:2", "executed_by": ["c"], "state_target": "title_skip", "file": ".glb"},
        "GLB.a.value":   {"site": "G:3", "executed_by": ["c"], "state_target": "output_control", "file": ".glb"},
        "GLB.a.never":   {"site": "G:4", "executed_by": [],    "state_target": "title_skip", "file": ".glb"},
    }
    ok_marked = {"GLB.a.kept": ["x.f90:1"]}
    ok_reg = [{"id": "GLB.a.title#1", "state_target": "title_skip", "reason": "r"},
              {"id": "GLB.a.value", "state_target": "output_control", "reason": "r", "evidence": "e"}]

    cases = [
        ("clean", ok_marked, ok_reg, [], None),
        ("C1 unresolvable marker", ok_marked, ok_reg, [("a.f90", 9, "same reader id")], "C1"),
        ("C1 invented id", {**ok_marked, "GLB.a.nope": ["a.f90:2"]}, ok_reg, [], "C1"),
        ("C2 uncovered", {}, ok_reg, [], "C2"),
        ("C3 both", {**ok_marked, "GLB.a.title#1": ["a.f90:3"]}, ok_reg, [], "C3"),
        ("C4 drifted target", ok_marked,
         [{**ok_reg[0], "state_target": "derived"}, ok_reg[1]], [], "C4"),
        ("C4 off-path row", ok_marked,
         ok_reg + [{"id": "GLB.a.never", "state_target": "title_skip", "reason": "r"}], [], "C4"),
        ("C4 no reason", ok_marked,
         [{"id": "GLB.a.title#1", "state_target": "title_skip"}, ok_reg[1]], [], "C4"),
        ("C5 value with no evidence", ok_marked,
         [ok_reg[0], {"id": "GLB.a.value", "state_target": "output_control", "reason": "r"}], [], "C5"),
    ]
    bad = 0
    for name, marked, reg, barren, want in cases:
        got = check(inv, reg, marked, barren)
        codes = {p.split()[0] for p in got}
        if want is None:
            ok = not got
        else:
            ok = want in codes
        print(f"  {'ok  ' if ok else 'FAIL'} {name}" + ("" if ok else f" -> {got}"))
        bad += 0 if ok else 1
    print(f"-- {len(cases) - bad}/{len(cases)} self-test cases passed")
    return 1 if bad else 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--quiet", action="store_true", help="counts only; skip the C6 listing")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args(argv)
    if a.selftest:
        return selftest()

    inventory = load_inventory(INVENTORY)
    registry = load_registry(REGISTRY)
    marked, barren = scan_markers(ADAPTER)

    problems = check(inventory, registry, marked, barren)
    report(inventory, registry, marked, a.quiet)
    for p in problems:
        print(f"FAIL {p}")
    if problems:
        print(f"COVERAGE FAIL: {len(problems)} problem(s)")
        return 1
    print("COVERAGE PASS: every reader on the executed path is either reproduced by a "
          "marked adapter read or registered, by name, as not adapted")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
