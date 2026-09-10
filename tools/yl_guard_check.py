#!/usr/bin/env python3
"""M2-01 judgement 5: cross-check the anchor guard table against the frozen baseline.

`docs/m2/M2-01-checkpoints.md` §1 lists the guard values the three anchors depend
on ("valid only under restart=0, nblks=1, ..."). Every anchor argument, every
dead-code claim and every `pinned guard` row in the map rests on that table, and
until now nothing compared it to a measurement. The M2 acceptance matrix found
one row wrong by hand (`stab_matde` declared 0, actually 99999) -- a hand check
that happened once and would not happen again.

This tool does that comparison mechanically. It parses the guard table out of the
prose, resolves each guard name to a field of the frozen baseline snapshots by
matching the last dotted segment of the field id, and compares the declared value
to the frozen one on both golden cases.

Three outcomes, and the third one is the point:

  CONFIRMED    the guard is on the snapshot export face and the declared value
               matches the frozen baseline on every case.
  MISMATCH     it is on the face and the declared value is wrong -> exit 1.
  NOT_ON_FACE  the guard is not exported in any snapshot, so this tool cannot
               confirm it. Reported by name, every run. A guard that cannot be
               confirmed must stay visible: silence here would read exactly like
               confirmation, which is how the table came to carry a wrong row.

Scope: the two golden decks. "The declared value matches the run" is a statement
about these decks, not about the dialect.

Usage:
    tools/yl_guard_check.py [--negative-control GUARD]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOC = ROOT / "docs/m2/M2-01-checkpoints.md"
MAP = ROOT / "docs/m2/state-field-map.toml"
CASES_DIR = ROOT / "cases/golden/static_2d"

TABLE_HEAD = "| 守卫 | 值 | 来源"


def parse_guard_table(text: str) -> list[tuple[str, str, str]]:
    """-> [(guard name, declared value, raw row)]; a row may declare several guards."""
    lines = text.splitlines()
    try:
        i = next(k for k, ln in enumerate(lines) if ln.startswith(TABLE_HEAD))
    except StopIteration:
        raise SystemExit(f"{DOC}: guard table header not found ({TABLE_HEAD!r}); "
                         f"the parser is pinned to that heading on purpose -- if the "
                         f"table moved, this check must be re-pointed deliberately")
    out, rows = [], 0
    for ln in lines[i + 2:]:
        if not ln.startswith("|"):
            break
        cells = [c.strip() for c in ln.strip().strip("|").split("|")]
        if len(cells) < 2:
            break
        rows += 1
        names = re.findall(r"`([^`]+)`", cells[0])
        if not names:
            raise SystemExit(f"{DOC}: guard row {ln!r} names no guard in backticks")
        vals = [v.strip(" `*") for v in cells[1].split(",")]
        if len(vals) == 1:
            vals = vals * len(names)
        if len(vals) != len(names):
            raise SystemExit(f"{DOC}: guard row {ln!r} declares {len(names)} guards "
                             f"but {len(vals)} values")
        for n, v in zip(names, vals):
            out.append((n, v, ln))
    if rows == 0:
        raise SystemExit(f"{DOC}: guard table parsed to zero rows")
    print(f"guard table: {rows} rows -> {len(out)} guard values")
    return out


def load_snapshots() -> dict[str, dict[str, dict]]:
    """case -> {field id: value}, merged over all checkpoints of the frozen baseline."""
    doc = tomllib.loads(MAP.read_text(encoding="utf-8"))
    cases = doc["cases"]
    out: dict[str, dict] = {}
    for cid in cases:
        base = CASES_DIR / cid.split(".", 1)[1] / "reference/state"
        if not base.is_dir():
            raise SystemExit(f"frozen baseline missing: {base}")
        merged: dict[str, dict] = {}
        for jf in sorted(base.rglob("*.json")):
            if jf.name == "fingerprint.json":
                continue
            d = json.loads(jf.read_text(encoding="utf-8"))
            for fid, rec in d.get("fields", {}).items():
                merged.setdefault(fid, rec)
        out[cid] = merged
    return out


def guard_index() -> dict[str, list[str]]:
    """guard name -> map field ids, resolved through the map's own `legacy_symbol`.

    The map records, for every field, the legacy global it came from. Resolving
    through that key rather than through a hand-written alias table is what keeps
    this check from rotting when a field is renamed: the map is the same artifact
    the snapshot writer is generated from.
    """
    doc = tomllib.loads(MAP.read_text(encoding="utf-8"))
    idx: dict[str, set] = {}
    for f in doc["field"]:
        fid = f["id"]
        keys = {fid.rsplit(".", 1)[-1].lower()}
        sym = f.get("legacy_symbol")
        if sym:
            keys.add(sym.rsplit(".", 1)[-1].lower())
        for k in keys:
            idx.setdefault(k, set()).add(fid)
    return {k: sorted(v) for k, v in idx.items()}


def resolve(name: str, index: dict[str, list[str]], fields: dict[str, dict]) -> tuple[list[str], str]:
    """-> (field ids present in the snapshot, reason when there are none)."""
    key = name.split("(")[0].lower()
    known = index.get(key, [])
    if not known:
        return [], "no field in the map carries this legacy symbol"
    present = [f for f in known if f in fields]
    if not present:
        return [], f"mapped to {', '.join(known)}, none of which is exported in any checkpoint"
    return present, ""


def coerce(declared: str):
    try:
        return int(declared)
    except ValueError:
        return declared


def compare(name: str, declared: str, value) -> tuple[bool, str]:
    m = re.match(r"^[A-Za-z_]\w*\((\d+)\)$", name)
    if m:
        idx = int(m.group(1))
        if not isinstance(value, list) or len(value) < idx:
            return False, f"declared element {idx} but snapshot value is {value!r}"
        value = value[idx - 1]
    want = coerce(declared)
    if isinstance(value, list) and not isinstance(want, list):
        if len(value) == 1:
            value = value[0]
    if isinstance(want, str) and isinstance(value, str):
        ok = want.strip().upper() == value.strip().upper()
    else:
        ok = want == value
    return ok, f"declared {want!r}, frozen {value!r}"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--negative-control", metavar="GUARD", default=None,
                    help="corrupt this guard's declared value in memory; the check must "
                         "then report exactly one MISMATCH naming it")
    a = ap.parse_args(argv)

    guards = parse_guard_table(DOC.read_text(encoding="utf-8"))
    snaps = load_snapshots()

    if a.negative_control:
        hit = [g for g in guards if g[0] == a.negative_control]
        if not hit:
            raise SystemExit(f"--negative-control {a.negative_control}: not a guard in the table")
        guards = [(n, ("999" if v != "999" else "998"), r) if n == a.negative_control else (n, v, r)
                  for n, v, r in guards]
        print(f"NEGATIVE CONTROL: {a.negative_control} declared value corrupted")

    index = guard_index()
    confirmed, mismatched, not_on_face = [], [], []
    for name, declared, _row in guards:
        per_case, ids, why = [], None, ""
        for cid, fields in snaps.items():
            found, why = resolve(name, index, fields)
            if not found:
                per_case = None
                break
            ids = found
            for fid in found:
                ok, how = compare(name, declared, fields[fid]["values"])
                per_case.append((cid, fid, ok, how))
        if per_case is None:
            not_on_face.append((name, why))
            continue
        bad = [(c, f, h) for c, f, ok, h in per_case if not ok]
        if bad:
            mismatched.append((name, ids, bad))
        else:
            confirmed.append((name, ids))

    for name, ids in confirmed:
        print(f"CONFIRMED   {name:<14} = frozen {ids[0]}"
              + (f" (+{len(ids)-1} more field ids)" if len(ids) > 1 else ""))
    for name, why in not_on_face:
        print(f"NOT_ON_FACE {name:<14} -- {why}; this tool cannot confirm it")
    for name, ids, bad in mismatched:
        for cid, fid, how in bad:
            print(f"MISMATCH    {name:<14} {cid} {fid}: {how}")

    print(f"GUARD-CHECK {'FAIL' if mismatched else 'PASS'}: "
          f"{len(confirmed)} confirmed, {len(mismatched)} mismatched, "
          f"{len(not_on_face)} not on the export face "
          f"({len(guards)} declared guard values, {len(snaps)} cases)")
    return 1 if mismatched else 0


if __name__ == "__main__":
    raise SystemExit(main())
