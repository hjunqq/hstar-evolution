#!/usr/bin/env python3
"""Mechanically enumerate the runtime state the solver needs past the adapter entry.

ADR-0009 as first written admitted a row only after a real run aborted for want of it.
The owner replaced that rule on 2026-09-11: enumerate mechanically, then verify by
driving a real solve. This tool is the enumeration half.

WHAT IT SCANS
  `legacy/yl/Global.f90`, from the adapter entry line to the end of `global_data`. That
  span is exactly the work the adapter path skips: on `--adapter=on` the entry commits and
  returns, so every allocation, initialisation and size dependency below it stops
  happening. Anything the solver later touches has to be established by the commit layer
  instead.

WHAT IT REPORTS, per allocation
  symbol, dimension expression, the enclosing `if` guard (so a branch that is dead on the
  static path is visible as dead rather than silently ignored), the initialisation
  statement that follows if there is one, and the source line.

WHAT IT DOES NOT DO
  It does not decide. It produces the candidate set; `docs/m4/runtime-state-manifest.toml`
  records the decision for each row and `tools/yl_existence_check.py` gates that the
  manifest and the commit layer agree. Splitting it this way is deliberate: a scan that
  also decided would be a scan nobody could contradict.

  It is a SCAN, not a proof of completeness. It sees `allocate` statements in one routine.
  State established elsewhere, or by assignment rather than allocation, is outside it --
  which is why the ruling pairs it with "verify by driving a real solve".

Usage:
    tools/yl_runtime_scan.py [--json docs/m4/evidence/runtime-state-scan.json]
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GLOBAL_F90 = ROOT / "legacy/yl/Global.f90"
COMMIT = ROOT / "src/runtime/yl_runtime_commit.f90"
HOOK = "yl_adapter_override"


def source_lines() -> list[str]:
    return GLOBAL_F90.read_bytes().decode("latin-1").split("\n")


def span(lines: list[str]) -> tuple[int, int]:
    hook = [i for i, l in enumerate(lines, 1) if HOOK in l and "call" in l]
    if len(hook) != 1:
        raise SystemExit(f"{GLOBAL_F90}: expected exactly one adapter entry call, found {len(hook)}")
    end = [i for i, l in enumerate(lines, 1)
           if re.match(r"\s*end\s+subroutine\s+global_data", l, re.I)]
    if not end:
        raise SystemExit(f"{GLOBAL_F90}: end of global_data not found")
    return hook[0], min(e for e in end if e > hook[0])


def module_types() -> dict[str, tuple[str, str]]:
    """name -> (declared base type, owning module), for the scalars the manifest carries."""
    out: dict[str, tuple[str, str]] = {}
    for f in sorted((ROOT / "legacy/yl").glob("*.f90")):
        txt = f.read_bytes().decode("latin-1").split("\n")
        in_routine = False
        in_type = False
        mod = ""
        for l in txt:
            head = l.split("!")[0]
            mm = re.match(r"\s*module\s+([A-Za-z_]\w*)\s*$", head, re.I)
            if mm:
                mod, in_routine = mm.group(1), False
            # Module variables are declared BEFORE `contains`; everything after belongs to
            # the module's own procedures. Without this, locals declared old-style inside
            # global_data (lgroup, listf, neface) were attributed to global_var and the
            # generated `use` named entities the module does not have.
            if re.match(r"\s*contains\s*$", head, re.I):
                in_routine = True
            if re.match(r"\s*type\s*(,|::|\s+[A-Za-z_])", head, re.I) and \
               not re.match(r"\s*type\s*\(", head, re.I):
                in_type = True
            if re.match(r"\s*end\s*type\b", head, re.I):
                in_type = False
                continue
            if in_type:
                continue
            s_ = l.split("!")[0]
            if re.match(r"\s*(subroutine|function|program)\s", s_, re.I):
                in_routine = True
            if re.match(r"\s*end\s+(subroutine|function|program)", s_, re.I):
                in_routine = False
            if in_routine:
                continue
            d = re.match(r"\s*(integer|real|double\s+precision|logical|character)\b"
                         r"\s*(\([^)]*\))?\s*(\*\s*\d+)?\s*(::)?\s*(.*)$", s_, re.I)
            if not d or not d.group(5).strip():
                continue
            base = re.sub(r"\s+", " ", d.group(1).lower())
            for m in re.finditer(r"\b([A-Za-z_]\w*)\b", d.group(5)):
                out.setdefault(m.group(1).lower(), (base, mod))
    return out


def module_names() -> set[str]:
    """Names declared at MODULE scope anywhere in the legacy tree.

    A name allocated inside global_data is a global iff it was declared by one of the
    modules rather than by the routine. Parsing declarations exactly is more than this
    needs: an over-broad set only lets locals through as candidates, and the manifest
    records a decision for every candidate either way.
    """
    names: set[str] = set()
    for f in sorted((ROOT / "legacy/yl").glob("*.f90")):
        txt = f.read_bytes().decode("latin-1").split("\n")
        depth_in_routine = False
        in_type = False
        for l in txt:
            s = l.split("!")[0]
            if re.match(r"\s*type\s*(,|::|\s+[A-Za-z_])", s, re.I) and \
               not re.match(r"\s*type\s*\(", s, re.I):
                in_type = True
            if re.match(r"\s*end\s*type\b", s, re.I):
                in_type = False
                continue
            if in_type:
                continue
            if re.match(r"\s*(subroutine|function|program)\s", s, re.I):
                depth_in_routine = True
            if re.match(r"\s*end\s+(subroutine|function|program)", s, re.I):
                depth_in_routine = False
            if depth_in_routine:
                continue
            if re.match(r"\s*contains\s*$", s, re.I):
                depth_in_routine = True
                continue
            if "::" in s:
                decl = s.split("::", 1)[1]
            else:
                # Old-style declarations carry no `::`:  `real   (irk) alfa_p4,stiff_p4`.
                # Missing them made every such global look routine-local, which is how
                # alfa_p4 -- a .glb scalar the adapter path leaves uninitialised -- stayed
                # out of the candidate set until -init=snan trapped on it.
                d = re.match(r"\s*(integer|real|double\s+precision|logical|character|type)\b"
                             r"\s*(\([^)]*\))?\s*(\*\s*\d+)?\s*(.*)$", s, re.I)
                if not d or not d.group(4).strip():
                    continue
                decl = d.group(4)
            for m in re.finditer(r"\b([A-Za-z_]\w*)\b", decl):
                names.add(m.group(1).lower())
    return names


def guard_of(lines: list[str], i: int) -> str:
    """The nearest enclosing single-line/block `if` condition, textually."""
    s = lines[i - 1].split("!")[0].strip()
    m = re.match(r"if\s*\((.*?)\)\s*(allocate|then)", s, re.I)
    if m:
        return m.group(1)
    depth = 0
    for j in range(i - 1, max(0, i - 200), -1):
        t = lines[j - 1].split("!")[0].strip()
        if re.match(r"end\s*if\b|endif\b", t, re.I):
            depth += 1
        m2 = re.match(r"if\s*\((.*)\)\s*then\s*$", t, re.I)
        if m2:
            if depth == 0:
                return m2.group(1)
            depth -= 1
    return ""


def alloc_targets(body: str) -> list[tuple[str, str]]:
    out, depth, cur = [], 0, ""
    for ch in body:
        if ch == "(":
            depth += 1
        if ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    out.append(cur)
    res = []
    for part in out:
        t = part.strip()
        if not t:
            continue
        # The SYMBOL is the whole component path with subscripts stripped, e.g.
        # element(ie)%field(1)%stres0(n) -> element%field%stres0. Using only the base name
        # would hide every inner allocation behind a base the commit layer already writes:
        # `element` is committed, so `element(ie)%field(1)%stres0` would have counted as
        # established while nothing had allocated it. (Found 2026-09-11 when the first
        # solve past the load assembly produced NaN.)
        base = re.match(r"\s*([A-Za-z_]\w*)", t)
        if not base:
            continue
        segs, depth, cur = [], 0, ""
        for ch in t:
            if ch == "(":
                depth += 1
                if depth == 1:
                    continue
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    continue
            if depth == 0:
                cur += ch
            else:
                pass
        path = "".join(cur.split())
        dims = ""
        m = re.search(r"\(([^()]*(?:\([^()]*\)[^()]*)*)\)\s*$", t)
        if m:
            dims = m.group(1).strip()
        res.append((path or base.group(1), dims))
    return res


def committed_symbols() -> set[str]:
    """What the commit layer already establishes, in the same component-path form.

    Three shapes count: a move_alloc into a legacy global; a manifest marker; and an
    `allocate` on a staging buffer, whose `s_` prefix is stripped so
    `s_group(ig)%list(n)` reads as `group%list` -- the same identity the scan gives the
    legacy site it stands in for. Without that last one every inner allocation commit
    already makes would show up as an unaccounted candidate.
    """
    txt = COMMIT.read_text()
    out = set(x.lower() for x in re.findall(r"move_alloc\s*\([^,]+,\s*([A-Za-z_]\w*)", txt))
    out |= set(x.lower() for x in re.findall(r"!@existence:\s*([A-Za-z_%]+)", txt))
    # Scalars commit establishes by plain assignment, including the `a = x;  b = y`
    # compound lines. Without these every legacy scalar commit already writes -- nblks,
    # type_problem, ntotv -- would report as an unaccounted candidate.
    for line in txt.split("\n"):
        body = line.split("!")[0]
        for stmt in body.split(";"):
            m2 = re.match(r"\s*([A-Za-z_]\w*)\s*=[^=]", stmt)
            if m2:
                out.add(m2.group(1).lower())
    for m in re.finditer(r"\ballocate\s*\((.*)\)\s*$", txt, re.M):
        for name, _dims in alloc_targets(m.group(1)):
            low = name.lower()
            if low.startswith("s_"):
                low = low[2:]
            out.add(low)
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--json", default=str(ROOT / "docs/m4/evidence/runtime-state-scan.json"))
    a = ap.parse_args(argv)

    lines = source_lines()
    lo, hi = span(lines)
    globals_ = module_names()
    types = module_types()
    committed = committed_symbols()

    rows, i = [], lo
    while i <= hi:
        s = lines[i - 1].split("!")[0]
        m = re.search(r"\ballocate\s*\((.*)\)\s*$", s.strip(), re.I)
        if m:
            g = guard_of(lines, i)
            init = ""
            for k in range(i + 1, min(i + 4, hi)):
                t = lines[k - 1].split("!")[0].strip()
                if re.match(r"[A-Za-z_]\w*(\s*\(.*\))?\s*=", t):
                    init = t
                    break
            for name, dims in alloc_targets(m.group(1)):
                low = name.lower()
                # Scope is decided by the BASE name (the module variable); identity is the
                # whole component path, so an inner allocation is its own candidate.
                base = low.split("%", 1)[0]
                rows.append({
                    "symbol": name, "line": i, "dims": dims, "guard": g,
                    "init_after": init,
                    "module_scope": base in globals_,
                    # `%` and `_` forms are the same identity: the manifest names rows
                    # with underscores (they become Fortran component names) while the
                    # legacy site is a component path.
                    "already_committed": (low in committed
                                          or low.replace("%", "_") in committed),
                })
        i += 1

    # --- scalars ------------------------------------------------------------------
    # The allocation scan cannot see them, and they are just as required: `alfa_p4` is a
    # .glb scalar read past the entry, and under -init=snan the adapter path trapped on
    # `if (alfa_p4 > 0)` in modf_element_lib while the legacy path ran clean.
    # Enumerated from the item lists of `read(...)` statements in the span, which is where
    # a deck scalar enters, filtered to module scope and to what commit does not write.
    srows = []
    for k in range(lo, hi + 1):
        t = lines[k - 1].split("!")[0].strip()
        m = re.match(r"read\s*\([^)]*\)\s*(.*)$", t, re.I)
        if not m or not m.group(1).strip():
            continue
        for item in m.group(1).split(","):
            nm = re.match(r"\s*([A-Za-z_]\w*)\s*$", item)
            if not nm:
                continue           # subscripted items are arrays, covered above
            low = nm.group(1).lower()
            if low in globals_ and low not in committed:
                srows.append({"symbol": nm.group(1), "line": k, "kind": "scalar",
                              "type": types.get(low, ("?", ""))[0],
                              "module": types.get(low, ("?", ""))[1],
                              "guard": guard_of(lines, k), "statement": t[:120]})
    seen, scalars = set(), []
    for r in srows:
        if r["symbol"].lower() in seen:
            continue
        seen.add(r["symbol"].lower())
        scalars.append(r)

    cand = [r for r in rows if r["module_scope"] and not r["already_committed"]]
    doc = {"version": 1, "source": "legacy/yl/Global.f90",
           "span": {"from_adapter_entry": lo, "to_end_of_global_data": hi},
           "allocations_seen": len(rows),
           "module_scope": sum(1 for r in rows if r["module_scope"]),
           "already_committed": sum(1 for r in rows if r["already_committed"]),
           "candidates": cand,
           "scalar_candidates": scalars}
    out = Path(a.json)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(doc, indent=1) + "\n", encoding="utf-8")

    print(f"scan span Global.f90:{lo}..{hi} (adapter entry .. end of global_data)")
    print(f"  allocate statements seen : {len(rows)}")
    print(f"  targeting module scope   : {doc['module_scope']}")
    print(f"  already established by commit : {doc['already_committed']}")
    print(f"  CANDIDATES for the runtime state manifest : {len(cand)}")
    for r in cand:
        g = f"  guard[{r['guard']}]" if r["guard"] else ""
        print(f"    Global.f90:{r['line']:<5} {r['symbol']:<24} dims({r['dims']}){g}")
    print(f"  SCALAR candidates (read past the entry, not committed) : {len(scalars)}")
    for r in scalars:
        print(f"    Global.f90:{r['line']:<5} {r['symbol']}")
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
