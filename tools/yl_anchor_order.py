#!/usr/bin/env python3
"""M2-01 judgement 4: derive the anchor/reader call order from execution, not from prose.

`docs/m2/M2-01-checkpoints.md` §2 argues that each of the three state-dump anchors
sits "after the last executed reader and before the first consumer".  The
`yl_io_inventory.py check` gate only ever scanned *within* the routine an anchor
lives in; the cross-routine half of that argument -- "and no model-level reader
runs in some other routine after the anchor" -- was carried by a hand-written
call-order table.  The M2 acceptance matrix recorded it as ASSERTION-ONLY
(judgement 4) for exactly that reason.

This tool replaces the prose with a measurement.  It runs the trace-profile
binary under gdb with a breakpoint on every registered reader site **and** on
each anchor line, and reads the resulting hit log **in order**.  The order is
observed cross-routine, because it comes from the process, not from a reading of
the sources.

What it then asserts (each failure names the reader and the bucket):

  A1  every registered reader's phase agrees with the bucket it was actually
      observed in.  `startup` must fall before `model_ready`; `solver_lazy` and
      `phase_lazy(1)` between `model_ready` and `phase_ready(1)`; and
      `increment_lazy(1,1)` between `phase_ready(1)` and `increment_ready(1,1)`.
      This turns the hand-maintained `phase` key into a derived fact.

  A2  the judgement the matrix asked for: **before the `model_ready` anchor,
      every read site that is reached either executed, or is a registered
      `reached_only` site carrying the inline condition that suppressed it.**
      An unexecuted, unregistered read before the anchor would mean the snapshot
      claims "the model is fully loaded" while some field was never read.

  A3  no site is reached that the registry does not know about -- otherwise A2
      is checking a set it does not control.

Scope, stated so it is not overread:
  * Two golden cases.  A conditional reader whose guard is false on both decks is
    reported as `reached_only`, and that is a statement about **these decks**,
    not about the dialect.
  * Read sites that never appear on this path at all are the registry's
    `not_on_path` table (54 groups); this tool sees only what the run reaches.
    It therefore cannot say "no reader exists elsewhere" -- only "nothing the
    run reached is unaccounted for".
  * Ordering is by first hit of a site.  A line that compiles to several
    addresses (R27) contributes several HIT records; only the earliest is used.

Usage:
    tools/yl_anchor_order.py check [--case ID ...] [--binary build/trace/hstar]
                                   [--out docs/m2/evidence/anchor-order]
    tools/yl_anchor_order.py check --negative-control {phase,anchor,reached}
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from yl_io_inventory import dump_line_table, line_addresses  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
REGISTRY = ROOT / "docs/m1/reader-inventory.toml"
MAP = ROOT / "docs/m2/state-field-map.toml"

# Bucket 0 is "before the first anchor"; bucket k is "after anchor k-1".
# The anchor sites are read from the M2 map so this tool cannot drift from it.
PHASE_BUCKET = {
    "startup": 0,
    "solver_lazy": 1,
    "phase_lazy(1)": 1,
    "increment_lazy(1,1)": 2,
}


def anchors() -> list[tuple[str, str]]:
    doc = tomllib.loads(MAP.read_text(encoding="utf-8"))
    out = [(c["id"], c["site"]) for c in doc["checkpoint"] if c.get("covered")]
    if len(out) != 3:
        raise SystemExit(f"expected 3 checkpoints in {MAP}, found {len(out)}")
    return out


def registry() -> list[dict]:
    return tomllib.loads(REGISTRY.read_text(encoding="utf-8"))["reader"]


def gdb_script(binary: Path, sites: list[str], log: Path, out: Path) -> str:
    addr = line_addresses(dump_line_table(binary))
    lines = ["set pagination off", "set confirm off", "set breakpoint pending on",
             "set print thread-events off", f"set logging file {log}",
             "set logging overwrite on", "set logging redirect on", "set logging enabled on"]
    n = 0
    for s in sites:
        f, ln = s.rsplit(":", 1)
        got = sorted(addr.get(f, {}).get(int(ln), []))
        specs = [f"break *{a:#x}" for a in got] or [f"break {s}"]
        for spec in specs:
            lines += [spec, "commands", "silent", f'printf "HIT {s}\\n"', "continue", "end"]
            n += 1
    # --adapter=off explicitly: this check is ABOUT the legacy reader order, and since
    # 2026-09-11 the solver's default entry is the adapter, which switches those readers
    # off. Without the flag every registered reader reports as "never reached" -- which is
    # true of the adapter path and beside the point here.
    lines += [f'printf "LOCATIONS %d {n}\\n", $bpnum',
              "run --adapter=off < /dev/null > gdb-stdout.txt 2> gdb-stderr.txt",
              'printf "EXIT %d\\n", $_exitcode', "quit"]
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return f"{len(sites)} sites -> {n} breakpoint locations"


def run_case(case_id: str, binary: Path, sites: list[str], keep: Path | None) -> list[str]:
    """Return the ordered list of site strings as they were hit."""
    case_dir = ROOT / "cases/golden/static_2d" / case_id.split(".", 1)[1]
    if not case_dir.is_dir():
        raise SystemExit(f"case directory missing: {case_dir}")
    subprocess.run([sys.executable, str(ROOT / "tools/yl_manifest.py"), "check",
                    str(case_dir / "input-manifest.json")], check=True,
                   stdout=subprocess.DEVNULL)
    work = Path(tempfile.mkdtemp(prefix="yl-anchor-order."))
    try:
        for f in (case_dir / "legacy").iterdir():
            shutil.copy2(f, work / f.name)
        log = work / "hits.log"
        note = gdb_script(binary, sites, log, work / "bp.gdb")
        print(f"  {case_id}: {note}")
        env = {"OMP_NUM_THREADS": "1", "MKL_NUM_THREADS": "1", "PATH": "/usr/bin:/bin",
               "HOME": str(work)}
        subprocess.run(["gdb", "-batch", "-nx", "-x", "bp.gdb", str(binary)],
                       cwd=work, env=env, capture_output=True, text=True)
        if not log.is_file():
            raise SystemExit(f"{case_id}: gdb produced no hit log")
        order, exit_code, locs = [], None, None
        for ln in log.read_text(encoding="utf-8", errors="replace").splitlines():
            if ln.startswith("HIT "):
                order.append(ln.split()[1])
            elif ln.startswith("EXIT "):
                exit_code = int(ln.split()[1])
            elif ln.startswith("LOCATIONS "):
                locs = ln.split()[1:]
        if exit_code is None:
            raise SystemExit(f"{case_id}: hit log has no EXIT line -- the run did not finish "
                             f"under gdb, so the order is a prefix and proves nothing")
        if exit_code != 0:
            raise SystemExit(f"{case_id}: traced run exited {exit_code}")
        if locs and locs[0] != locs[1]:
            raise SystemExit(f"{case_id}: gdb created {locs[0]} of {locs[1]} breakpoints")
        if keep:
            # The raw log is ~600 kB of repeated HIT lines; keep it gzipped as the
            # primary evidence and write the derived order beside it for reading.
            import gzip
            keep.mkdir(parents=True, exist_ok=True)
            with gzip.open(keep / "hits-ordered.log.gz", "wb") as gz:
                gz.write(log.read_bytes())
        return order
    finally:
        shutil.rmtree(work, ignore_errors=True)


def bucketise(order: list[str], anchor_sites: list[str]) -> tuple[dict[str, int], list[str]]:
    """site -> bucket index by first hit; plus the anchors that never fired."""
    first: dict[str, int] = {}
    for i, s in enumerate(order):
        first.setdefault(s, i)
    missing = [a for a in anchor_sites if a not in first]
    cuts = [first.get(a, len(order) + 1) for a in anchor_sites]
    if cuts != sorted(cuts):
        raise SystemExit(f"anchors did not fire in registered order: {list(zip(anchor_sites, cuts))}")
    out = {}
    for s, pos in first.items():
        b = 0
        for c in cuts:
            if pos > c:
                b += 1
        out[s] = b
    return out, missing


def check_case(case_id: str, readers: list[dict], binary: Path, out_root: Path | None,
               mutate: dict | None) -> list[str]:
    names = [n for n, _ in anchors()]
    anchor_sites = [s for _, s in anchors()]
    if mutate and mutate["kind"] == "anchor":
        anchor_sites[0] = mutate["site"]
    # Breakpoint the whole census of `read` statements, not just the registered
    # ones -- otherwise A3 could never fire, because the only sites instrumented
    # would be the sites already in the registry.
    census = json.loads((ROOT / "docs/m1/io-sites.json").read_text(encoding="utf-8"))["sites"]
    sites = sorted({c["site"] for c in census if c["stmt"] == "read"}
                   | {r["site"] for r in readers} | set(anchor_sites))
    keep = (out_root / case_id.split(".", 1)[1]) if out_root else None
    order = run_case(case_id, binary, sites, keep)
    bucket, missing = bucketise(order, anchor_sites)
    if keep:
        (keep / "anchor-order.json").write_text(json.dumps(
            {"version": 1, "case": case_id, "binary": str(binary),
             "anchors": dict(zip(names, anchor_sites)), "total_hits": len(order),
             "distinct_sites": len(bucket),
             "bucket": {s: bucket[s] for s in sorted(bucket)}}, indent=1) + "\n",
            encoding="utf-8")
    problems = []
    for a, n in zip(anchor_sites, names):
        if a in missing:
            problems.append(f"{case_id}: anchor {n} ({a}) was never reached in the traced run")
    if problems:
        return problems

    by_site = {}
    for r in readers:
        by_site.setdefault(r["site"], []).append(r)

    # A3 -- nothing reached that the registry does not know about.
    for s in bucket:
        if s not in by_site and s not in anchor_sites:
            problems.append(f"{case_id}: A3 site {s} was reached but is in no registry entry")

    for r in readers:
        s, rid = r["site"], r["id"]
        phase = r.get("phase")
        reached_only = bool(r.get("reached_only"))
        executed = bool(r.get("executed_by"))
        if mutate and mutate["kind"] == "phase" and rid == mutate["id"]:
            phase = mutate["phase"]
        if mutate and mutate["kind"] == "reached" and rid == mutate["id"]:
            # Drop only the reached_only registration: the read still does not
            # execute, so A2 must notice that nothing accounts for it.
            reached_only = False

        if s not in bucket:
            # Registered but never reached on this deck.  Only legitimate for a
            # site the registry itself says this case does not execute.
            if executed:
                problems.append(f"{case_id}: {rid} is registered executed_by but its site "
                                f"{s} was never reached")
            continue
        b = bucket[s]

        if reached_only or not executed:
            # A2 -- an unexecuted read before model_ready must be a registered
            # reached_only entry naming the condition that suppressed it.
            if b == 0:
                if not reached_only:
                    problems.append(f"{case_id}: A2 {rid} ({s}) is reached before "
                                    f"{names[0]} but the registry records no execution "
                                    f"and no reached_only condition")
                elif not r.get("condition_value"):
                    problems.append(f"{case_id}: A2 {rid} ({s}) is reached_only before "
                                    f"{names[0]} with no condition_value recorded")
            continue

        want = PHASE_BUCKET.get(phase)
        if want is None:
            problems.append(f"{case_id}: A1 {rid} carries phase {phase!r}, which this tool "
                            f"has no bucket for; extend PHASE_BUCKET deliberately")
        elif want != b:
            where = ["before " + names[0]] + [f"between {names[i]} and {names[i+1]}"
                                              for i in range(len(names) - 1)] + ["after " + names[-1]]
            problems.append(f"{case_id}: A1 {rid} ({s}) has phase {phase!r} (expects "
                            f"{where[want]}) but was observed {where[b]}")
    return problems


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check")
    c.add_argument("--case", action="append", default=None)
    c.add_argument("--binary", default=str(ROOT / "build/trace/hstar"))
    c.add_argument("--out", default=str(ROOT / "docs/m2/evidence/anchor-order"))
    c.add_argument("--negative-control", choices=["phase", "anchor", "reached"], default=None)
    a = ap.parse_args(argv)

    binary = Path(a.binary)
    if not binary.is_file():
        raise SystemExit(f"trace binary missing: {binary} (run tools/build.sh trace)")
    readers = registry()
    cases = a.case or tomllib.loads(REGISTRY.read_text(encoding="utf-8"))["cases"]

    mutate = None
    if a.negative_control == "phase":
        # A reader that really runs at startup, relabelled as if it ran lazily.
        mutate = {"kind": "phase", "id": "GLB.global_data.title#1", "phase": "increment_lazy(1,1)"}
    elif a.negative_control == "anchor":
        # Move model_ready to the top of FEM90: everything then falls in the wrong bucket.
        mutate = {"kind": "anchor", "site": "Fem.f90:97"}
    elif a.negative_control == "reached":
        # Un-register the condition that suppresses a conditional read.
        mutate = {"kind": "reached", "id": "GLB.global_data.reached_only_Global_691"}
    if mutate:
        print(f"NEGATIVE CONTROL ({a.negative_control}): {mutate}")
        cases = cases[:1]

    out_root = None if mutate else Path(a.out)
    problems = []
    for cid in cases:
        problems += check_case(cid, readers, binary, out_root, mutate)

    n_reached_only = sum(1 for r in readers if r.get("reached_only"))
    if problems:
        for p in problems:
            print(f"FAIL {p}")
        print(f"ANCHOR-ORDER FAIL: {len(problems)} problem(s) over {len(cases)} case(s)")
        return 1
    print(f"ANCHOR-ORDER PASS: {len(readers)} registered readers, {len(cases)} case(s); "
          f"every reader observed in the bucket its phase claims; "
          f"the only unexecuted reads reached before model_ready are the "
          f"{n_reached_only} registered reached_only sites, each naming its false condition")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
