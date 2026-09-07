#!/usr/bin/env python3
"""
Failure-injection probe runner for the legacy YL solver (M1-02).

A probe is `cases/probes/failure/<id>/probe.toml`: a golden base case, a list of
`derive` operations that damage one input file, and an `expect` block naming the
status / diagnostic the checked-I/O binary must produce.

`run` does, per probe:
  1. materialise: copy the golden case's legacy/, observables.toml and
     tolerances.toml to <runs-root>/<id>/case/, apply the derive operations to
     case/legacy/ (text files are handled as latin-1 bytes, line endings kept),
     then regenerate case/input-manifest.json with tools/yl_manifest.py;
  2. run: tools/yl_run.py --case-dir <case> --expect-status <expect.status>;
  3. assert: run-manifest.json status, first diagnostic (code / stage / file
     suffix / reader / index), exit code, no core file;
  4. summarise into <report> and print a table. Exit 1 if any probe fails.

Write guards (checked before anything is deleted or written; exit 2 on violation):
  * --runs-root must not lie inside cases/ nor contain it;
  * every materialised case directory must resolve inside --runs-root;
  * every derive `file` is a bare file name (no directory part, not `..`) and
    its target resolves inside the materialised case/legacy/.

Usage:
  yl_probe.py list
  yl_probe.py run [--ids F20_cor_eof ...] [--binary build/release/hstar]
                  [--runs-root runs/probes] [--report runs/probes/report.json]
                  [--materialize-only]

Derive operations (all paths are relative to case/legacy/):
  delete_file(file)                         remove the file
  empty_file(file)                          keep the file, zero bytes
  truncate_lines(file, keep)                keep the first `keep` lines
  truncate_bytes(file, keep)                keep the first `keep` bytes
  replace_line(file, line, text)            replace line `line` (1-based); its
                                            original line ending is preserved
  replace_token(file, line, old, new,       replace `old` on line `line`; `count`
                count=1, occurrence=1)      replacements starting at the
                                            `occurrence`-th match (1-based)
Only the Python standard library is used.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tomllib
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PROBES_DIR = REPO_ROOT / "cases" / "probes" / "failure"
GOLDEN_DIR = REPO_ROOT / "cases" / "golden"
YL_RUN = REPO_ROOT / "tools" / "yl_run.py"
YL_MANIFEST = REPO_ROOT / "tools" / "yl_manifest.py"
CASE_COPY_FILES = ("observables.toml", "tolerances.toml")
CORE_FILE = re.compile(r"^core(\.\d+)?$")
DERIVE_OPS = {"delete_file", "empty_file", "truncate_lines", "truncate_bytes", "replace_line", "replace_token"}
EXPECT_REQUIRED = ("status", "exit_code", "code", "stage", "file_suffix", "no_core", "max_wall_seconds")
CASES_DIR = REPO_ROOT / "cases"


class ProbeError(Exception):
    pass


# ---------------------------------------------------------------- probes

def load_probe(path: Path) -> dict:
    probe = tomllib.loads(path.read_text(encoding="utf-8"))
    for key in ("schema", "id", "base_case", "description", "derive", "expect"):
        if key not in probe:
            raise ProbeError(f"{path}: missing key {key!r}")
    if probe["schema"] != 1:
        raise ProbeError(f"{path}: unsupported schema {probe['schema']}")
    if probe["id"] != path.parent.name:
        raise ProbeError(f"{path}: id {probe['id']!r} does not match directory {path.parent.name!r}")
    for d in probe["derive"]:
        if d.get("op") not in DERIVE_OPS:
            raise ProbeError(f"{path}: unknown derive op {d.get('op')!r}")
        if "file" not in d:
            raise ProbeError(f"{path}: derive without file")
        check_derive_file_name(str(d["file"]), path)
    missing = [k for k in EXPECT_REQUIRED if k not in probe["expect"]]
    if missing:
        raise ProbeError(f"{path}: expect missing {missing}")
    probe["_path"] = path
    return probe


def check_derive_file_name(name: str, origin: Path | str) -> None:
    """A derive target is a bare file name: no directory part, no `.`/`..`, non-empty."""
    if not name or name in (".", "..") or Path(name).name != name or "/" in name or "\\" in name:
        raise ProbeError(f"{origin}: derive file {name!r} must be a bare file name inside case/legacy/")


def check_runs_root(runs_root: Path) -> Path:
    """--runs-root must neither lie inside cases/ nor contain it (would clobber golden decks)."""
    rr = runs_root.resolve()
    cases = CASES_DIR.resolve()
    if rr == cases or rr.is_relative_to(cases) or cases.is_relative_to(rr):
        raise ProbeError(f"--runs-root {runs_root} overlaps {CASES_DIR}: refusing to materialise there")
    return rr


def check_inside(path: Path, root: Path, what: str) -> Path:
    """`path` (need not exist) must resolve inside `root`; returns the resolved path."""
    resolved = path.resolve()
    root_resolved = root.resolve()
    if not resolved.is_relative_to(root_resolved):
        raise ProbeError(f"{what} {path} resolves outside {root}: refusing to write")
    return resolved


def load_probes(ids: list[str] | None = None) -> list[dict]:
    probes = [load_probe(p) for p in sorted(PROBES_DIR.glob("*/probe.toml"))]
    if ids:
        by_id = {p["id"]: p for p in probes}
        selected = []
        for want in ids:
            hits = [pid for pid in by_id if pid == want or pid.startswith(want + "_")]
            if not hits:
                raise ProbeError(f"no probe matches {want!r}")
            if len(hits) > 1 and want not in by_id:
                raise ProbeError(f"{want!r} is ambiguous: {hits}")
            selected.append(by_id[want] if want in by_id else by_id[hits[0]])
        return selected
    return probes


def golden_case_dir(base_case: str) -> Path:
    family, _, name = base_case.partition(".")
    d = GOLDEN_DIR / family / name
    if not (d / "legacy").is_dir():
        raise ProbeError(f"golden case not found for {base_case!r}: {d}")
    return d


# ---------------------------------------------------------------- derive

def split_lines_keepends(data: bytes) -> list[bytes]:
    """Split on LF only, keeping line endings (CRLF stays intact, a bare CR is not a
    line break); a trailing partial line is kept. bytes.splitlines() would also
    split on CR and other separators and change the line count of CRLF files."""
    if not data:
        return []
    parts = re.split(rb"(?<=\n)", data)
    return [x for x in parts if x]


def line_ending(line: bytes) -> bytes:
    if line.endswith(b"\r\n"):
        return b"\r\n"
    if line.endswith(b"\n"):
        return b"\n"
    return b""


def apply_derive(legacy: Path, d: dict) -> str:
    op = d["op"]
    check_derive_file_name(str(d["file"]), f"derive {op}")
    target = check_inside(legacy / d["file"], legacy, f"derive {op} target")
    if not target.is_file():
        raise ProbeError(f"derive {op}: {d['file']} not in legacy/")
    if op == "delete_file":
        target.unlink()
        return f"deleted {d['file']}"
    if op == "empty_file":
        target.write_bytes(b"")
        return f"emptied {d['file']}"
    data = target.read_bytes()
    if op == "truncate_bytes":
        keep = int(d["keep"])
        target.write_bytes(data[:keep])
        return f"{d['file']}: kept {min(keep, len(data))} of {len(data)} bytes"
    lines = split_lines_keepends(data)
    if op == "truncate_lines":
        keep = int(d["keep"])
        if keep > len(lines):
            raise ProbeError(f"truncate_lines: {d['file']} has only {len(lines)} lines, keep={keep}")
        target.write_bytes(b"".join(lines[:keep]))
        return f"{d['file']}: kept {keep} of {len(lines)} lines"
    ln = int(d["line"])
    if not 1 <= ln <= len(lines):
        raise ProbeError(f"{op}: {d['file']} has {len(lines)} lines, line={ln}")
    old_line = lines[ln - 1]
    ending = line_ending(old_line)
    body = old_line[: len(old_line) - len(ending)].decode("latin-1")
    if op == "replace_line":
        new_body = str(d["text"])
    else:  # replace_token
        old, new = str(d["old"]), str(d["new"])
        count, occurrence = int(d.get("count", 1)), int(d.get("occurrence", 1))
        positions = [m.start() for m in re.finditer(re.escape(old), body)]
        if len(positions) < occurrence + count - 1:
            raise ProbeError(f"replace_token: {d['file']} line {ln} has {len(positions)} match(es) of {old!r}, need {occurrence + count - 1}")
        start = positions[occurrence - 1]
        head, tail = body[:start], body[start:]
        new_body = head + tail.replace(old, new, count)
    lines[ln - 1] = new_body.encode("latin-1") + ending
    target.write_bytes(b"".join(lines))
    return f"{d['file']} line {ln}: {body.strip()!r} -> {new_body.strip()!r}"


def materialize(probe: dict, probe_root: Path, runs_root: Path) -> dict:
    src = golden_case_dir(probe["base_case"])
    case = check_inside(probe_root / "case", runs_root, "materialised case dir")
    if case == runs_root.resolve() or case.is_relative_to(src.resolve()) or src.resolve().is_relative_to(case):
        raise ProbeError(f"materialised case dir {case} overlaps the golden case {src}")
    for d in probe["derive"]:  # validated at load time too; re-check before the first write
        check_derive_file_name(str(d["file"]), probe["_path"])
    if case.exists():
        shutil.rmtree(case)
    case.mkdir(parents=True)
    shutil.copytree(src / "legacy", case / "legacy")
    for name in CASE_COPY_FILES:
        if (src / name).is_file():
            shutil.copy2(src / name, case / name)
    applied = [apply_derive(case / "legacy", d) for d in probe["derive"]]
    cmd = [sys.executable, str(YL_MANIFEST), "generate", str(case / "legacy"), "-o", str(case / "input-manifest.json"),
           "--meta", f"probe={probe['id']}", "--meta", f"derived_from={probe['base_case']}"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise ProbeError(f"yl_manifest generate failed: {r.stderr.strip() or r.stdout.strip()}")
    return {"case_dir": str(case), "source": str(src), "derive_applied": applied}


# ---------------------------------------------------------------- run + assert

def run_case(probe: dict, probe_root: Path, binary: Path) -> dict:
    expect = probe["expect"]
    runs_root = probe_root / "runs"
    cmd = [sys.executable, str(YL_RUN), "--case-id", probe["base_case"], "--case-dir", str(probe_root / "case"),
           "--binary", str(binary), "--timeout", str(expect["max_wall_seconds"]), "--runs-root", str(runs_root),
           "--label", probe["id"], "--expect-status", str(expect["status"])]
    r = subprocess.run(cmd, capture_output=True, text=True)
    run_dir = None
    m = re.search(r"->\s+(\S+)\s*$", r.stdout.strip().splitlines()[-1] if r.stdout.strip() else "")
    if m and Path(m.group(1)).is_dir():
        run_dir = Path(m.group(1))
    else:
        candidates = sorted((runs_root / probe["base_case"]).glob(f"*_{probe['id']}")) if (runs_root / probe["base_case"]).is_dir() else []
        run_dir = candidates[-1] if candidates else None
    out = {"command": cmd, "runner_returncode": r.returncode, "runner_stdout": r.stdout.strip()[-2000:],
           "runner_stderr": r.stderr.strip()[-2000:], "run_dir": str(run_dir) if run_dir else None, "run_manifest": None}
    if run_dir and (run_dir / "run-manifest.json").is_file():
        out["run_manifest"] = json.loads((run_dir / "run-manifest.json").read_text(encoding="utf-8"))
    return out


def check_expectations(probe: dict, run: dict) -> list[str]:
    exp = probe["expect"]
    man = run.get("run_manifest")
    problems: list[str] = []
    if man is None:
        return [f"no run-manifest.json (runner rc={run['runner_returncode']}): {run['runner_stderr'][-300:] or run['runner_stdout'][-300:]}"]
    if man.get("status") != exp["status"]:
        problems.append(f"status {man.get('status')!r} != {exp['status']!r}")
    rc = (man.get("process") or {}).get("returncode")
    if rc != exp["exit_code"]:
        problems.append(f"exit code {rc!r} != {exp['exit_code']!r}")
    diags = man.get("diagnostics") or []
    if not diags:
        problems.append("no HSTAR_DIAG diagnostic recorded")
    else:
        d = diags[0]
        if d.get("code") != exp["code"]:
            problems.append(f"diag code {d.get('code')!r} != {exp['code']!r}")
        if d.get("stage") != exp["stage"]:
            problems.append(f"diag stage {d.get('stage')!r} != {exp['stage']!r}")
        f = str(d.get("file", ""))
        if not f.endswith(exp["file_suffix"]):
            problems.append(f"diag file {f!r} does not end with {exp['file_suffix']!r}")
        if "reader" in exp and d.get("reader") != exp["reader"]:
            problems.append(f"diag reader {d.get('reader')!r} != {exp['reader']!r}")
        if "index" in exp:
            got = d.get("index")
            try:
                got_i = int(got)
            except (TypeError, ValueError):
                got_i = None
            if got_i != int(exp["index"]):
                problems.append(f"diag index {got!r} != {exp['index']!r}")
    if exp["no_core"]:
        cores = [o.get("name") for o in man.get("outputs", []) if CORE_FILE.match(str(o.get("name", "")))]
        if cores or man.get("core_dump"):
            problems.append(f"core file present: {cores or man.get('core_dump')}")
    return problems


# ---------------------------------------------------------------- commands

def cmd_list(_: argparse.Namespace) -> int:
    probes = load_probes()
    print(f"{'id':28s} {'base_case':26s} {'code':12s} {'stage':22s} {'file':6s} reader")
    for p in probes:
        e = p["expect"]
        print(f"{p['id']:28s} {p['base_case']:26s} {e['code']:12s} {e['stage']:22s} {e['file_suffix']:6s} {e.get('reader', '-')}")
    print(f"{len(probes)} probe(s)")
    return 0


def cmd_run(args: argparse.Namespace) -> int:
    probes = load_probes(args.ids)
    runs_root = check_runs_root(Path(args.runs_root))
    if Path(args.report).resolve().is_relative_to(CASES_DIR.resolve()):
        raise ProbeError(f"--report {args.report} lies inside {CASES_DIR}: refusing to write")
    binary = Path(args.binary).resolve()
    if not args.materialize_only and not binary.is_file():
        raise SystemExit(f"binary not found: {binary}")
    report = {"generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"), "binary": str(binary),
              "runs_root": str(runs_root), "materialize_only": args.materialize_only, "probes": []}
    for p in probes:
        entry = {"id": p["id"], "base_case": p["base_case"], "description": p["description"], "expect": p["expect"],
                 "materialize": None, "run": None, "status": None, "problems": []}
        try:
            entry["materialize"] = materialize(p, runs_root / p["id"], runs_root)
        except ProbeError as e:
            entry["status"], entry["problems"] = "ERROR", [f"materialize: {e}"]
            report["probes"].append(entry)
            continue
        if args.materialize_only:
            entry["status"] = "MATERIALIZED"
            report["probes"].append(entry)
            continue
        run = run_case(p, runs_root / p["id"], binary)
        entry["run"] = {k: v for k, v in run.items() if k != "run_manifest"}
        entry["run"]["manifest_status"] = (run.get("run_manifest") or {}).get("status")
        entry["run"]["diagnostic"] = ((run.get("run_manifest") or {}).get("diagnostics") or [None])[0]
        entry["problems"] = check_expectations(p, run)
        entry["status"] = "PASS" if not entry["problems"] else "FAIL"
        report["probes"].append(entry)

    report_path = Path(args.report).resolve()
    report_path.parent.mkdir(parents=True, exist_ok=True)
    counts = {}
    for e in report["probes"]:
        counts[e["status"]] = counts.get(e["status"], 0) + 1
    report["summary"] = counts
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    print(f"{'id':28s} {'result':12s} {'run status':16s} detail")
    for e in report["probes"]:
        st = (e.get("run") or {}).get("manifest_status") or "-"
        detail = "; ".join(e["problems"]) if e["problems"] else (e["materialize"] or {}).get("derive_applied", [""])[0]
        print(f"{e['id']:28s} {e['status']:12s} {st:16s} {detail[:110]}")
    print(f"summary: {counts}  -> {report_path}")
    return 0 if all(e["status"] in ("PASS", "MATERIALIZED") for e in report["probes"]) else 1


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list", help="list probes").set_defaults(fn=cmd_list)
    r = sub.add_parser("run", help="materialise, run and assert probes")
    r.add_argument("--ids", nargs="+", help="probe ids or unique prefixes (default: all)")
    r.add_argument("--binary", default=str(REPO_ROOT / "build" / "release" / "hstar"))
    r.add_argument("--runs-root", default=str(REPO_ROOT / "runs" / "probes"))
    r.add_argument("--report", default=None, help="default <runs-root>/report.json")
    r.add_argument("--materialize-only", action="store_true", help="derive the cases but do not run the binary")
    r.set_defaults(fn=cmd_run)
    args = ap.parse_args(argv)
    if args.cmd == "run" and args.report is None:
        args.report = str(Path(args.runs_root) / "report.json")
    try:
        return args.fn(args)
    except ProbeError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
