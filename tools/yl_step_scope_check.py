#!/usr/bin/env python3
"""Step-scope cross-check: does a `steps(1)` derivation publish state legacy re-derives
per BLOCK? (M7, after the loads_2d.wall_reservoir finding of 2026-09-16.)

WHY THIS EXISTS
  The .loa load domain added multi-step analyses, and the first real staged deck failed
  for a reason that was not in the new code at all. `yl_runtime_build` derives the
  degree-of-freedom freeze mask as "freeze everything, then free the elements of an
  ACTIVE section", reading `problem%steps(1)%activation`. On a one-step analysis that is
  exactly right and can never be observed to be wrong. On a staged analysis it freezes
  the group that appears in block 2 for the whole run: its nodes come out at exactly
  zero, the block carries no new load, and nothing says so.

  The lesson generalises past this one field, and past this one domain. Any process-type
  capability -- staging, time history, restart -- can be broken by a derivation that
  quietly treats the FIRST step's value as the analysis's value. That class of mistake is
  invisible to every gate this repository has, because the numbers it produces are
  perfectly self-consistent; only a real multi-step case can expose it, and only if one
  exists. So the property is checked directly instead.

WHAT IT CHECKS, IN BOTH DIRECTIONS
  The publishing modules -- `yl_runtime_build` and `yl_runtime_commit`, the only two that
  turn ProblemState into legacy globals -- are scanned for every `steps(1)%<path>` read.
  Each distinct path must carry exactly one row in docs/m3/step-scope.toml, and each row
  must name a path something actually reads. A path appearing with no row is the failure
  this tool is for; a row with no path is a claim about code that is gone.

  Every row declares a `legacy_symbol` and a `scope`, and the scope is then cross-checked
  against LEGACY ITSELF rather than against the row's prose:

    per_analysis        legacy assigns this symbol ONCE, outside the block loop. The
                        check fails if the symbol is assigned inside the loop body or
                        inside any of the input routines the loop calls per block
                        (prescrib_set, external_load_2, boundt) -- i.e. if legacy would
                        have changed it and this build would not.
    per_block           legacy re-derives it every block, and so must this one:
                        `recommitted_by` names a routine that the per-block commit path
                        actually runs, and that routine must mention either the path or
                        the `via` name it delegates to.
    per_block_refused   legacy re-derives it every block and this build cannot, so it
                        refuses a deck where the value differs between steps.
                        `refused_by` names the routine that raises.

  A `legacy_symbol` of the form `n/a: <reason>` is allowed for the handful of fields with
  no legacy counterpart, and then the scope check is skipped -- but the reason is printed
  on every run, so "no counterpart" stays a statement somebody can disagree with.

Usage:
    tools/yl_step_scope_check.py [--selftest]
"""
from __future__ import annotations

import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REGISTRY = ROOT / "docs/m3/step-scope.toml"
# The two modules that publish ProblemState into legacy globals. Nothing else may.
PUBLISHERS = ["src/runtime/yl_runtime_build.f90", "src/runtime/yl_runtime_commit.f90"]
FEM = ROOT / "legacy/yl/Fem.f90"
# The input routines legacy calls at the top of every block. These are exactly the ones
# the modern path switches off and must therefore replace per block.
PER_BLOCK_ROUTINES = {
    "prescrib_set": ROOT / "legacy/yl/Prescrib.f90",
    "external_load_2": ROOT / "legacy/yl/Load.f90",
    "boundt": ROOT / "legacy/yl/Temper.f90",
}
SCOPES = {"per_analysis", "per_block", "per_block_refused"}
BLOCK_LOOP = re.compile(r"^\s*do iblks=lblks\+1,runblks\s*$")


def read(path: Path) -> list[str]:
    return path.read_text(encoding="latin-1").split("\n")


def strip_comment(line: str) -> str:
    out, quote = [], None
    for ch in line:
        if quote:
            out.append(ch)
            if ch == quote:
                quote = None
        elif ch in "'\"":
            quote = ch
            out.append(ch)
        elif ch == "!":
            break
        else:
            out.append(ch)
    return "".join(out)


def paths_read() -> dict[str, list[str]]:
    """Every distinct `steps(1)%a%b(...)%c` read, mapped to where it is read."""
    found: dict[str, list[str]] = {}
    for rel in PUBLISHERS:
        for n, line in enumerate(read(ROOT / rel), 1):
            for m in re.finditer(r"steps\(1\)((?:%[A-Za-z_]\w*(?:\([^()]*\))?)+)",
                                 strip_comment(line)):
                p = "steps[]" + re.sub(r"\([^()]*\)", "[]", m.group(1)).replace("%", ".")
                found.setdefault(p, []).append(f"{Path(rel).name}:{n}")
    return found


def routine_body(lines: list[str], name: str) -> list[str]:
    """The lines of `subroutine name` .. `end subroutine name`, case-insensitively."""
    lo = hi = None
    begin = re.compile(rf"^\s*(?:recursive\s+)?subroutine\s+{name}\b", re.I)
    end = re.compile(rf"^\s*end\s*subroutine\s+{name}\b", re.I)
    for i, line in enumerate(lines):
        if lo is None and begin.match(line):
            lo = i
        elif lo is not None and end.match(line):
            hi = i
            break
    if lo is None:
        return []
    return lines[lo:hi + 1] if hi is not None else lines[lo:]


def block_loop_body() -> list[str]:
    lines = read(FEM)
    start = next((i for i, l in enumerate(lines) if BLOCK_LOOP.match(l)), None)
    if start is None:
        raise SystemExit("Fem.f90: the block loop `do iblks=lblks+1,runblks` is gone; "
                         "this tool's whole premise moved and it must be re-read, not "
                         "re-pointed")
    depth = 0
    for j in range(start, len(lines)):
        t = strip_comment(lines[j]).strip().lower()
        if re.match(r"do\b", t) or re.search(r"\bdo\s+\w+\s*=", t):
            depth += 1
        if re.match(r"end\s*do\b", t):
            depth -= 1
            if depth == 0:
                return lines[start:j + 1]
    raise SystemExit("Fem.f90: the block loop does not close")


def per_block_text() -> str:
    """Everything legacy may re-derive per block: the loop body plus the input routines
    it calls at the top of every one."""
    parts = block_loop_body()
    for name, src in PER_BLOCK_ROUTINES.items():
        if src.is_file():
            parts += routine_body(read(src), name)
    return "\n".join(strip_comment(l) for l in parts)


def assigned(text: str, symbol: str) -> bool:
    """Is `symbol` written to in `text`?

    Two ways, and the second is the one that matters here: an ordinary assignment, and
    appearing in the item list of a READ. A read is a write -- `read(loadunit,*) gravy,
    factg(1:ndimn)` is exactly how legacy re-derives the body force every block -- and a
    checker that only looked for `=` would have called every per-block input a constant.
    """
    bare = symbol.split(".")[-1].split("%")[-1]
    assign = re.compile(
        rf"(?<![\w%]){re.escape(bare)}\s*(\([^()]*\))?\s*(%\s*\w+\s*)*=(?!=)", re.I)
    if assign.search(text):
        return True
    word = re.compile(rf"(?<![\w%]){re.escape(bare)}\b", re.I)
    for line in text.split("\n"):
        m = re.match(r"\s*(?:if\s*\(.*?\)\s*)?read\s*\(", line, re.I)
        if not m:
            continue
        depth, cut = 0, None
        for i, ch in enumerate(line[m.end() - 1:], m.end() - 1):
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    cut = i + 1
                    break
        if cut is not None and word.search(line[cut:]):
            return True
    return False


def check() -> list[str]:
    problems: list[str] = []
    if not REGISTRY.is_file():
        return [f"{REGISTRY} is missing"]
    doc = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    rows = doc.get("path", [])
    found = paths_read()
    by_path: dict[str, dict] = {}

    for r in rows:
        p = r.get("path", "")
        if p in by_path:
            problems.append(f"{p}: registered twice")
        by_path[p] = r
        for key in ("path", "scope", "legacy_symbol", "reason"):
            if not r.get(key):
                problems.append(f"{p or '<no path>'}: missing {key}")
        if r.get("scope") not in SCOPES:
            problems.append(f"{p}: scope {r.get('scope')!r} not in {sorted(SCOPES)}")

    for p in sorted(found):
        if p not in by_path:
            problems.append(f"{p}: read at {found[p][0]} with no row in "
                            f"{REGISTRY.relative_to(ROOT)}. A steps(1) read publishes the "
                            f"FIRST step's value for the whole analysis; say whether that "
                            f"is what legacy does")
    for p in sorted(by_path):
        if p not in found:
            problems.append(f"{p}: registered but no publisher reads it any more")

    text = per_block_text()
    commit = "\n".join(strip_comment(l) for l in read(ROOT / "src/runtime/yl_runtime_commit.f90"))
    for p in sorted(by_path):
        r = by_path[p]
        sym = str(r.get("legacy_symbol", ""))
        scope = r.get("scope")
        if sym.startswith("n/a:"):
            continue
        is_per_block = assigned(text, sym)
        if scope == "per_analysis" and is_per_block:
            problems.append(f"{p}: declared per_analysis, but legacy assigns "
                            f"{sym} inside the block loop or in an input routine it calls "
                            f"per block -- so this build would hold the first step's value "
                            f"while legacy changed it")
        if scope in ("per_block", "per_block_refused") and not is_per_block:
            problems.append(f"{p}: declared {scope}, but legacy never assigns {sym} "
                            f"per block; the row claims a re-derivation legacy does not do")
        if scope == "per_block":
            who = str(r.get("recommitted_by", ""))
            if not who:
                problems.append(f"{p}: per_block requires recommitted_by")
                continue
            body = "\n".join(routine_body(read(ROOT / "src/runtime/yl_runtime_commit.f90"), who))
            if not body:
                problems.append(f"{p}: recommitted_by {who} is not a subroutine of "
                                f"yl_runtime_commit")
                continue
            leaf = p.split(".")[-1].replace("[]", "")
            via = str(r.get("via", ""))
            if leaf not in body and (not via or via not in body):
                problems.append(f"{p}: {who} mentions neither {leaf} nor its `via` "
                                f"delegate; the row says it is re-committed there and it "
                                f"is not")
        # A per_analysis field that the CONTRACT still writes under a step is committed
        # from step 1, so a later step that disagrees would be dropped without a word.
        # That is the same hazard in a different place, and it needs the same answer: a
        # named refusal. Required of every steps[]-rooted per_analysis row.
        if scope == "per_analysis" and p.startswith("steps[]"):
            who = str(r.get("refused_by", ""))
            if not who or who not in commit:
                problems.append(f"{p}: legacy reads this once, so it is committed from "
                                f"step 1 -- a later step that disagrees must be REFUSED, "
                                f"and refused_by must name a routine in yl_runtime_commit; "
                                f"{who!r} is not there")
        if scope == "per_block_refused":
            who = str(r.get("refused_by", ""))
            if not who or who not in commit:
                problems.append(f"{p}: per_block_refused requires refused_by naming a "
                                f"routine in yl_runtime_commit; {who!r} is not there")
    return problems


def selftest() -> int:
    """Each fixture breaks one rule and must be caught by it."""
    import copy
    base = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    found = paths_read()
    ok = True

    def run(label: str, mutate, expect: str) -> None:
        nonlocal ok
        doc = copy.deepcopy(base)
        mutate(doc)
        saved = REGISTRY.read_text(encoding="utf-8")
        try:
            REGISTRY.write_text(dump(doc), encoding="utf-8")
            got = check()
        finally:
            REGISTRY.write_text(saved, encoding="utf-8")
        hit = any(expect in g for g in got)
        print(f"  {'ok  ' if hit else 'FAIL'} {label}")
        if not hit:
            ok = False
            for g in got[:3]:
                print(f"       got: {g}")

    def dump(doc: dict) -> str:
        out = [f"version = {doc.get('version', 1)}", ""]
        for r in doc.get("path", []):
            out.append("[[path]]")
            for k, v in r.items():
                out.append(f'{k} = "{v}"' if isinstance(v, str) else f"{k} = {v}")
            out.append("")
        return "\n".join(out) + "\n"

    victim = next(iter(sorted(found)))
    run("a read with no row is caught",
        lambda d: d["path"].__setitem__(
            slice(0, len(d["path"])),
            [r for r in d["path"] if r["path"] != victim]),
        f"{victim}: read at")
    run("a row with no read is caught",
        lambda d: d["path"].append({"path": "steps[].no.such.field", "scope": "per_analysis",
                                    "legacy_symbol": "n/a: fixture", "reason": "fixture"}),
        "no publisher reads it any more")
    grav = next(r for r in base["path"] if r["path"] == "steps[].load.gravity.direction")
    run("a per-block value declared per_analysis is caught",
        lambda d: [r.update(scope="per_analysis") for r in d["path"]
                   if r["path"] == grav["path"]],
        "declared per_analysis, but legacy assigns")
    run("a per_block row whose recommitter does not mention it is caught",
        lambda d: [r.update(recommitted_by="commit_surface_edges", via="") for r in d["path"]
                   if r["path"] == grav["path"]],
        "mentions neither")
    fmt = next(r for r in base["path"] if r["path"] == "steps[].output.format")
    run("a per_analysis value declared per_block is caught",
        lambda d: [r.update(scope="per_block", recommitted_by="commit_block_state")
                   for r in d["path"] if r["path"] == fmt["path"]],
        "legacy never assigns")
    return 0 if ok else 1


def main() -> int:
    if "--selftest" in sys.argv:
        print("-- step-scope self-test")
        rc = selftest()
        print("SELFTEST PASS" if rc == 0 else "SELFTEST FAIL")
        return rc
    problems = check()
    doc = tomllib.loads(REGISTRY.read_text(encoding="utf-8"))
    rows = doc.get("path", [])
    counts: dict[str, int] = {}
    for r in rows:
        counts[str(r.get("scope"))] = counts.get(str(r.get("scope")), 0) + 1
    for r in sorted(rows, key=lambda r: str(r.get("path"))):
        if str(r.get("legacy_symbol", "")).startswith("n/a:"):
            print(f"  no legacy counterpart: {r['path']} -- "
                  f"{r['legacy_symbol'][4:].strip()}")
    for p in problems:
        print(f"FAIL {p}")
    if problems:
        print(f"STEP-SCOPE FAIL: {len(problems)} problem(s)")
        return 1
    print("STEP-SCOPE PASS: " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items()))
          + " -- every steps(1) read is accounted for, and every scope agrees with what "
            "legacy does per block")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
