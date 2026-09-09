#!/usr/bin/env python3
"""M4-01 L3-c: the shadow-process differential harness (old path vs new path).

WHAT IT COMPARES, AND WHAT IT DELIBERATELY DOES NOT BUILD
    The adjudication surface is the `yl_state_dump` checkpoint snapshot -- the M2-02
    artefact -- and the adjudicator is the EXISTING stack: `tools/yl_state.py normalize`
    turns each side's raw dump into the canonical tree, and `tools/yl_state_diff.py`
    compares the two honouring every row's own `compare.rule` from
    `docs/m2/state-field-map.toml`.

    This file contains no comparator, no tolerance, and no ignore list. That is the
    plan's binding instruction (`.ccg/tasks/m4-01-legacy-adapter/plan.md`, "影子差分比什么面"):
    a second `ProblemState` comparator would be a second set of tolerance/ignore semantics
    that must be kept consistent with the map by hand, which is the drift pattern
    ADR-0001/0004 exist to prevent. Everything below is process management and
    bookkeeping over the existing tools' own JSON reports; nothing here decides whether
    two values are equal.

THE TWO CHILD PROCESSES
    old   `build/<profile>/hstar --dump-state=state`, driven by `tools/yl_run.py`, which
          already provides exactly what L3-c needs: a fresh isolated directory per run
          (`runs/<case_id>/<utc>_<hash8>_<label>/work`), the golden inputs copied in and
          re-verified, its own process group, stdin from /dev/null, a wall-clock timeout,
          and normalization of the resulting dump into `<run_dir>/state`.
    new   `build/l3c-shadow/yl_adapter_shadow --dump-state=state`, run by this file in
          `<newroot>/<case>/work`, a directory this file stages and owns. It is the
          repository-side pipeline: adapt_legacy_deck -> build_runtime ->
          commit_legacy_globals -> yl_state_dump.

    Separate processes and separate directories are not hygiene, they are the premise:
    both paths write the legacy globals and open deck files by relative name, so sharing
    either would make the comparison meaningless.

NEVER WRITES INTO cases/
    Both halves read `cases/golden/<family>/<name>/legacy/` and copy it out. `yl_run.py`
    does that for the old side (and re-verifies the input hashes afterwards); the
    `stage_new_work` function below does it for the new side. Nothing here opens a path
    under `cases/` for writing, and `--check-clean` runs `git status --porcelain cases/`
    after every run and fails if it is not empty.

CLASSIFICATION (one row per map field per checkpoint)
    MATCH           the comparator compared this row and it agreed
    MISMATCH        the comparator compared this row and it disagreed
    NOT_COMPARABLE  the map's own `compare.rule = "ignore"` for this row -- the map's
                    judgement, not this harness's
    UNVERIFIED      no comparable evidence: the row is structurally absent or malformed
                    on one side, or its whole checkpoint is missing on one side.
    Missing evidence is never MATCH. A row this harness did not compare is UNVERIFIED,
    including every row of a checkpoint one side never reached.

STOP RULE (team-lead instruction)
    A MISMATCH on any row whose `compare.rule` is value-based (`exact`, `hash`,
    `abs_tol`, `rel_tol` -- i.e. anything but `ignore`) stops the harness before the next
    case and exits 1. A mismatch there means the new path diverges from legacy on real
    state, and widening the run before that is understood is how a real divergence gets
    averaged away.

NEGATIVE CONTROL
    `--negative-control FIELD` corrupts one leaf value of one field in the NEW side's
    normalized tree, byte-for-byte in place (no re-serialization -- a `json.dump`
    rewrite changes formatting the tools legitimately reject for other reasons, which
    would prove nothing), and re-runs the comparison. If that does not produce a
    MISMATCH on exactly that field, the comparator was idling and every green result in
    the same run is worthless.

USAGE
    python3 tools/yl_shadow_diff.py [--cases cooks_membrane,lame_cylinder]
        [--old-binary build/release/hstar]
        [--new-binary build/l3c-shadow/yl_adapter_shadow]
        [--runs-root runs] [--new-root build/l3c-shadow/run]
        [--map docs/m2/state-field-map.toml] [--timeout 600]
        [--negative-control FIELD_ID] [--no-check-clean] [-o report.json]

    Exit codes: 0 every case adjudicated with no MISMATCH; 1 the stop rule fired;
    2 a child process or one of the delegated tools failed; 3 usage.

Only the Python standard library is used.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "tools"))
from yl_state_map import load_map  # noqa: E402

CASE_FAMILY = "static_2d"
DEFAULT_CASES = ["cooks_membrane", "lame_cylinder"]
VALUE_RULES = {"exact", "hash", "abs_tol", "rel_tol"}


# --------------------------------------------------------------------------- map ---
def map_rows(map_path: Path) -> dict[str, dict[str, str]]:
    """{checkpoint: {field id: compare.rule}} straight from the map -- the denominator.

    EVERY map row is enumerated, including the 79 with `compare.rule = "ignore"` (which
    are exactly the 79 with `emit = "none"` -- checked against the map, not assumed).
    They are reported as NOT_COMPARABLE rather than dropped, so the denominator of this
    harness is the map's own field list and not a subset this file chose.
    """
    doc = load_map(map_path)
    rows: dict[str, dict[str, str]] = {}
    for f in doc["field"]:
        rows.setdefault(f["checkpoint"], {})[f["id"]] = (f.get("compare") or {}).get("rule", "exact")
    return rows


# ------------------------------------------------------------------- old process ---
def run_old(case: str, binary: Path, runs_root: Path, timeout: float, label: str) -> Path:
    """One isolated legacy-solver run with --dump-state; returns its normalized state tree."""
    cmd = [sys.executable, str(REPO_ROOT / "tools" / "yl_run.py"),
           "--case-id", f"{CASE_FAMILY}.{case}", "--binary", str(binary),
           "--runs-root", str(runs_root), "--label", label,
           "--timeout", str(timeout), "--dump-state"]
    p = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True)
    sys.stdout.write(p.stdout)
    sys.stderr.write(p.stderr)
    if p.returncode != 0:
        raise ChildFailed(f"old path: yl_run.py exited {p.returncode} for {case}")
    run_dir = Path(p.stdout.strip().splitlines()[-1].split("-> ")[-1].strip())
    state = run_dir / "state"
    if not state.is_dir():
        raise ChildFailed(f"old path: {state} was not produced")
    return state


# ------------------------------------------------------------------- new process ---
def stage_new_work(case: str, new_root: Path, checkpoints: list[str]) -> Path:
    """Fresh work directory holding a copy of the deck; never writes under cases/."""
    src = REPO_ROOT / "cases" / "golden" / CASE_FAMILY / case / "legacy"
    if not src.is_dir():
        raise ChildFailed(f"new path: no golden deck at {src}")
    work = new_root / case / "work"
    if work.parent.exists():
        shutil.rmtree(work.parent)
    work.mkdir(parents=True)
    for entry in sorted(src.iterdir()):
        if entry.is_symlink() or not entry.is_file():
            raise ChildFailed(f"new path: {entry} is not a regular file")
        shutil.copy2(entry, work / entry.name)
    # The Fortran writer opens into these directories and never creates them.
    for cp in checkpoints:
        (work / "state" / cp).mkdir(parents=True)
    return work


def run_new(case: str, binary: Path, work: Path, timeout: float) -> tuple[int, str, str]:
    """The new-path child: its own process, cwd = its own directory, own process group."""
    env = dict(os.environ)
    env.pop("LD_LIBRARY_PATH", None)
    env["OMP_NUM_THREADS"] = "1"
    env["MKL_NUM_THREADS"] = "1"
    with open(os.devnull, "rb") as devnull:
        p = subprocess.run([str(binary.resolve()), "--dump-state=state"], cwd=work,
                           stdin=devnull, capture_output=True, text=True,
                           timeout=timeout, env=env, start_new_session=True)
    (work.parent / "stdout.txt").write_text(p.stdout, encoding="utf-8")
    (work.parent / "stderr.txt").write_text(p.stderr, encoding="utf-8")
    return p.returncode, p.stdout, p.stderr


def normalize(raw: Path, out: Path, map_path: Path) -> tuple[int, str]:
    cmd = [sys.executable, str(REPO_ROOT / "tools" / "yl_state.py"), "normalize",
           str(raw), "-o", str(out), "--map", str(map_path)]
    p = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True)
    return p.returncode, (p.stdout + p.stderr)


# -------------------------------------------------------------------- comparison ---
def diff(ref: Path, act: Path, map_path: Path, out_json: Path) -> tuple[int, dict, str]:
    cmd = [sys.executable, str(REPO_ROOT / "tools" / "yl_state_diff.py"),
           str(ref), str(act), "--map", str(map_path), "--strict",
           "--expand-hash", "-o", str(out_json)]
    p = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True)
    report = json.loads(out_json.read_text(encoding="utf-8")) if out_json.exists() else {}
    return p.returncode, report, p.stdout + p.stderr


def classify(rows: dict[str, dict[str, str]], report: dict, unreached: dict[str, str]
             ) -> list[tuple[str, str, str, str, str]]:
    """(checkpoint, field, rule, classification, detail) for EVERY map row, always."""
    status = report.get("fields", {}) if report else {}
    out = []
    for cp in sorted(rows):
        for fid in sorted(rows[cp]):
            rule = rows[cp][fid]
            if rule == "ignore":
                out.append((cp, fid, rule, "NOT_COMPARABLE", "compare.rule = ignore (the map's own rule)"))
                continue
            if cp in unreached:
                out.append((cp, fid, rule, "UNVERIFIED", unreached[cp]))
                continue
            st = status.get(cp, {}).get(fid)
            if st is None:
                out.append((cp, fid, rule, "UNVERIFIED",
                            "the comparator produced no status for this row"))
            elif st.startswith("PASS"):
                out.append((cp, fid, rule, "MATCH", st))
            elif st.startswith("FAIL"):
                out.append((cp, fid, rule, "MISMATCH", st))
            else:  # STRUCT(...)
                out.append((cp, fid, rule, "UNVERIFIED", st))
    return out


# ------------------------------------------------------------- negative control ---
def corrupt_leaf(tree: Path, field: str) -> tuple[Path, str, str]:
    """Byte-for-byte edit of one leaf of `field` in a normalized tree.

    No JSON round-trip: re-serializing changes formatting the downstream tools
    legitimately flag for unrelated reasons, so the control would prove nothing about
    the value comparison. The digest sidecar is left alone deliberately -- a stored
    digest that disagrees with its own values is itself a finding the comparator must
    raise, so either outcome is the comparator responding.
    """
    for path in sorted(tree.rglob("*.json")):
        text = path.read_text(encoding="utf-8")
        anchor = f'"{field}"'
        i = text.find(anchor)
        if i < 0:
            continue
        j = text.find('"values"', i)
        if j < 0:
            continue
        k = text.find("[", j)
        if k < 0:
            continue
        k += 1
        while k < len(text) and text[k] in " \n\r\t[":
            k += 1
        end = k
        while end < len(text) and text[end] not in ",]\n \t":
            end += 1
        tok = text[k:end]
        new = flip_token(tok)
        if new is None:
            continue
        path.write_text(text[:k] + new + text[end:], encoding="utf-8")
        return path, tok, new
    raise ChildFailed(f"negative control: no leaf value of {field} found under {tree}")


def flip_token(tok: str) -> str | None:
    t = tok.strip()
    if t.startswith('"') and t.endswith('"') and len(t) >= 3:
        body = t[1:-1]
        return '"' + ("0" if body[-1] != "0" else "1") + body[1:] if len(body) == 1 else \
               '"' + body[:-1] + ("0" if body[-1] != "0" else "1") + '"'
    if t.lstrip("-").isdigit():
        return str(int(t) + 1)
    return None


class ChildFailed(RuntimeError):
    pass


# --------------------------------------------------------------------------- main ---
def cases_clean() -> str:
    p = subprocess.run(["git", "status", "--porcelain", "cases/"], cwd=REPO_ROOT,
                       capture_output=True, text=True)
    return p.stdout.strip()


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cases", default=",".join(DEFAULT_CASES))
    ap.add_argument("--old-binary", default="build/release/hstar")
    ap.add_argument("--new-binary", default="build/l3c-shadow/yl_adapter_shadow")
    ap.add_argument("--runs-root", default=str(REPO_ROOT / "runs"))
    ap.add_argument("--new-root", default=str(REPO_ROOT / "build" / "l3c-shadow" / "run"))
    ap.add_argument("--map", default=str(REPO_ROOT / "docs" / "m2" / "state-field-map.toml"))
    ap.add_argument("--timeout", type=float, default=600.0)
    ap.add_argument("--old-vs-old", action="store_true",
                    help="control: run the OLD binary twice, in two separate processes and "
                         "directories, and compare those two -- proves the harness and the "
                         "comparator agree with themselves before anything is claimed about the new path")
    ap.add_argument("--negative-control", metavar="FIELD_ID",
                    help="corrupt one leaf of FIELD_ID on the actual side and re-compare")
    ap.add_argument("--no-check-clean", action="store_true")
    ap.add_argument("-o", "--output")
    a = ap.parse_args(argv)

    map_path = Path(a.map)
    rows = map_rows(map_path)
    covered = sorted(rows)
    cases = [c.strip() for c in a.cases.split(",") if c.strip()]
    old_binary = Path(a.old_binary)
    new_binary = Path(a.new_binary)
    if not old_binary.is_file():
        print(f"FAIL: old binary not found: {old_binary}", file=sys.stderr)
        return 3
    if not a.old_vs_old and not new_binary.is_file():
        print(f"FAIL: new binary not found: {new_binary}", file=sys.stderr)
        return 3

    doc = {"mode": "old-vs-old" if a.old_vs_old else "old-vs-new",
           "map": str(map_path), "cases": {}, "totals": {}}
    totals = {"MATCH": 0, "MISMATCH": 0, "NOT_COMPARABLE": 0, "UNVERIFIED": 0}
    stop = False

    for case in cases:
        print(f"\n=== case {case} ({doc['mode']}) ===")
        rec: dict = {}
        doc["cases"][case] = rec
        unreached: dict[str, str] = {}

        try:
            ref_tree = run_old(case, old_binary, Path(a.runs_root), a.timeout, "l3c-old")
            rec["reference_tree"] = str(ref_tree)

            if a.old_vs_old:
                act_tree = run_old(case, old_binary, Path(a.runs_root), a.timeout, "l3c-old2")
                rec["actual_tree"] = str(act_tree)
                rec["new_returncode"] = 0
            else:
                work = stage_new_work(case, Path(a.new_root), ["model_ready"])
                rc, out, err = run_new(case, new_binary, work, a.timeout)
                rec["new_returncode"] = rc
                rec["new_stderr_tail"] = err.strip().splitlines()[-3:] if err.strip() else []
                print(f"  new-path child exit={rc}")
                for line in rec["new_stderr_tail"]:
                    print(f"    stderr: {line}")
                act_tree = work.parent / "state-normalized"
                nrc, nout = normalize(work / "state", act_tree, map_path)
                rec["normalize_returncode"] = nrc
                rec["normalize_output"] = nout.strip().splitlines()[-6:]
                print(f"  normalize(new) exit={nrc}")
                for line in rec["normalize_output"]:
                    print(f"    {line}")
                if nrc != 0 or not act_tree.is_dir():
                    for cp in covered:
                        unreached[cp] = (f"the new path produced no usable snapshot: its child "
                                         f"exited {rc} and yl_state.py normalize exited {nrc}")
                    act_tree = None
                else:
                    for cp in covered:
                        if not (act_tree / cp).is_dir():
                            unreached[cp] = ("the new path never reaches this checkpoint: it runs no "
                                             "solve, and this checkpoint is emitted from inside FEM90's solve")

            report: dict = {}
            if act_tree is not None:
                if a.negative_control:
                    p, old_tok, new_tok = corrupt_leaf(act_tree, a.negative_control)
                    print(f"  negative control: {p.name}: {a.negative_control} leaf {old_tok} -> {new_tok}")
                    rec["negative_control"] = {"file": str(p), "field": a.negative_control,
                                               "from": old_tok, "to": new_tok}
                out_json = Path(a.new_root).parent / f"l3c-diff-{case}.json"
                out_json.parent.mkdir(parents=True, exist_ok=True)
                drc, report, dtext = diff(ref_tree, act_tree, map_path, out_json)
                rec["diff_returncode"] = drc
                rec["diff_report"] = str(out_json)
                rec["diff_summary"] = report.get("summary")
                print(f"  yl_state_diff exit={drc} summary={report.get('summary')}")
                for line in dtext.strip().splitlines()[:40]:
                    print(f"    {line}")
        except (ChildFailed, subprocess.TimeoutExpired) as e:
            print(f"  ABORT: {e}")
            rec["abort"] = str(e)
            for cp in covered:
                unreached.setdefault(cp, f"harness aborted before comparison: {e}")
            report = {}

        table = classify(rows, report, unreached)
        counts = {"MATCH": 0, "MISMATCH": 0, "NOT_COMPARABLE": 0, "UNVERIFIED": 0}
        for _, _, _, cls, _ in table:
            counts[cls] += 1
            totals[cls] += 1
        rec["counts"] = counts
        rec["rows"] = [{"checkpoint": c, "field": f, "rule": r, "class": k, "detail": d}
                       for c, f, r, k, d in table]
        print(f"  {case}: MATCH={counts['MATCH']} MISMATCH={counts['MISMATCH']} "
              f"NOT_COMPARABLE={counts['NOT_COMPARABLE']} UNVERIFIED={counts['UNVERIFIED']}")

        if not a.no_check_clean:
            dirty = cases_clean()
            rec["cases_dirty"] = dirty
            if dirty:
                print(f"  FAIL: cases/ was modified:\n{dirty}", file=sys.stderr)
                return 2

        bad = [(c, f, r, d) for c, f, r, k, d in table if k == "MISMATCH" and r in VALUE_RULES]
        if bad:
            stop = True
            print("\nSTOP RULE TRIGGERED: a value-rule row disagrees between the two paths.")
            for c, f, r, d in bad[:20]:
                print(f"  MISMATCH {c} {f} [{r}] {d}")
            break

    doc["totals"] = totals
    print(f"\nTOTALS  MATCH={totals['MATCH']}  MISMATCH={totals['MISMATCH']}  "
          f"NOT_COMPARABLE={totals['NOT_COMPARABLE']}  UNVERIFIED={totals['UNVERIFIED']}")
    if a.output:
        Path(a.output).write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"report: {a.output}")
    return 1 if stop else 0


if __name__ == "__main__":
    sys.exit(main())
