#!/usr/bin/env python3
"""Isolated, fail-closed runner for the legacy YL solver (M0-03).

Every run:
  1. verifies the case's input-manifest.json (INPUT_HASH_MISMATCH otherwise);
  2. copies the inputs into a fresh directory runs/<case_id>/<utc>_<hash8>/work;
  3. runs the binary there with stdin=/dev/null in its own process group,
     single-threaded, without LD_LIBRARY_PATH, under a wall-clock timeout
     (SIGTERM to the group, then SIGKILL after a grace period);
  4. classifies the outcome (see STATUS_ORDER) and parses the required output;
  5. re-verifies the golden inputs (GOLDEN_MODIFIED otherwise);
  6. writes run-manifest.json (+ results.json when the output parsed).

Only COMPLETED may feed a comparison. Exit code is 0 only for COMPLETED.

Usage:
  yl_run.py --case-id static_2d.cooks_membrane --binary build/release/hstar
            [--timeout 600] [--runs-root runs] [--label NAME]
            [--case-dir DIR]   # override the case directory (self-tests)
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import resource
import shutil
import signal
import subprocess
import sys
import time
import tomllib
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import yl_manifest  # noqa: E402
import yl_parse_flavia  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent
STATUS_ORDER = ["INPUT_HASH_MISMATCH", "TIMEOUT", "CRASHED", "FAILED", "MISSING_OUTPUT", "GOLDEN_MODIFIED", "COMPLETED"]
CRASH_PATTERNS = re.compile(r"forrtl:|severe \(|Segmentation fault|MemorySanitizer|core dumped", re.I)
# The legacy program writes its wall-clock stamps to stderr; nothing else is expected there.
BENIGN_STDERR = re.compile(r"^\s*time(?:\(\w+\))?:\s*\d\d:\d\d:\d\d\s*$")
GRACE_SECONDS = 5.0


def sha256(path: Path) -> str:
    return yl_manifest.sha256_of(path)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def find_case(case_id: str) -> Path:
    manifest = tomllib.loads((REPO_ROOT / "cases" / "manifest.toml").read_text(encoding="utf-8"))
    for c in manifest.get("case", []):
        if c["id"] == case_id:
            return REPO_ROOT / "cases" / c["path"]
    raise SystemExit(f"case id not registered in cases/manifest.toml: {case_id}")


def check_manifest(manifest_path: Path, root: Path) -> list[str]:
    """Return a list of problems (empty when the manifest verifies)."""
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    problems = []
    listed = {e["path"]: e for e in manifest["files"]}
    for rel, e in listed.items():
        p = root / rel
        if not p.is_file():
            problems.append(f"MISSING {rel}")
        elif p.stat().st_size != e["bytes"] or sha256(p) != e["sha256"]:
            problems.append(f"CHANGED {rel}")
    actual = {p.relative_to(root).as_posix() for p in yl_manifest.walk_files(root, manifest.get("excludes", []))}
    problems += [f"UNLISTED {rel}" for rel in sorted(actual - set(listed))]
    return problems


def run(args: argparse.Namespace) -> int:
    case_dir = Path(args.case_dir).resolve() if args.case_dir else find_case(args.case_id)
    legacy_dir = case_dir / "legacy"
    input_manifest = case_dir / "input-manifest.json"
    observables = tomllib.loads((case_dir / "observables.toml").read_text(encoding="utf-8"))
    required_output = observables["source"]["file"]
    expect_nodes = int(observables["source"]["expected_node_count"])
    binary = Path(args.binary).resolve()
    if not binary.is_file():
        raise SystemExit(f"binary not found: {binary}")

    record: dict = {
        "manifest_version": 1,
        "case_id": args.case_id,
        "case_dir": str(case_dir),
        "label": args.label,
        "status": None,
        "binary": {"path": str(binary), "sha256": sha256(binary)},
        "build_manifest": None,
        "platform": {"os": platform.platform(), "machine": platform.machine(), "hostname": platform.node()},
        "threads": {"OMP_NUM_THREADS": "1", "MKL_NUM_THREADS": "1"},
        "timeout_seconds": args.timeout,
        "input_check_before": None,
        "input_check_after": None,
        "process": None,
        "required_output": {"file": required_output, "present": False, "bytes": None, "sha256": None, "parse": None},
        "outputs": [],
    }
    bm = binary.parent / "build-manifest.json"
    if bm.is_file():
        bmj = json.loads(bm.read_text(encoding="utf-8"))
        record["build_manifest"] = {"path": str(bm), "profile": bmj.get("profile"), "binary_sha256": bmj.get("binary", {}).get("sha256")}
        if record["build_manifest"]["binary_sha256"] not in (None, record["binary"]["sha256"]):
            record["build_manifest"]["note"] = "binary hash differs from build manifest"

    # 1. inputs must match the frozen manifest before anything is copied
    before = check_manifest(input_manifest, legacy_dir)
    record["input_check_before"] = {"ok": not before, "problems": before}
    input_hash8 = hashlib.sha256(input_manifest.read_bytes()).hexdigest()[:8]
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_dir = Path(args.runs_root).resolve() / args.case_id / f"{stamp}_{input_hash8}{'_' + args.label if args.label else ''}"
    work = run_dir / "work"
    run_dir.mkdir(parents=True, exist_ok=False)
    if before:
        record["status"] = "INPUT_HASH_MISMATCH"
        return finish(record, run_dir)

    # 2. isolated copy
    work.mkdir()
    for p in legacy_dir.iterdir():
        if p.is_file():
            shutil.copy2(p, work / p.name)
    inputs_copied = sorted(p.name for p in work.iterdir())

    # 3. run
    env = {k: v for k, v in os.environ.items() if k not in ("LD_LIBRARY_PATH", "LD_PRELOAD")}
    env.update({"OMP_NUM_THREADS": "1", "MKL_NUM_THREADS": "1", "MKL_DYNAMIC": "FALSE"})
    if args.case_dir:  # self-test hook: lets a fake binary find the golden dir
        env["YL_RUN_GOLDEN_DIR"] = str(legacy_dir)
    stdout_f = open(run_dir / "stdout.txt", "wb")
    stderr_f = open(run_dir / "stderr.txt", "wb")
    t0 = time.monotonic()
    started = utc_now()
    proc = subprocess.Popen([str(binary)], cwd=work, stdin=subprocess.DEVNULL, stdout=stdout_f, stderr=stderr_f, env=env, start_new_session=True)
    timed_out = False
    try:
        proc.wait(timeout=args.timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        try:
            os.killpg(proc.pid, signal.SIGTERM)
            proc.wait(timeout=GRACE_SECONDS)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()
        except ProcessLookupError:
            pass
    wall = time.monotonic() - t0
    stdout_f.close(); stderr_f.close()
    ru = resource.getrusage(resource.RUSAGE_CHILDREN)
    rc = proc.returncode
    stderr_text = (run_dir / "stderr.txt").read_text(encoding="latin-1", errors="replace")
    stderr_unexpected = [ln for ln in stderr_text.splitlines() if ln.strip() and not BENIGN_STDERR.match(ln)]
    record["process"] = {
        "command": [str(binary)],
        "cwd": str(work),
        "started_at": started,
        "wall_seconds": round(wall, 3),
        "user_seconds": ru.ru_utime,
        "system_seconds": ru.ru_stime,
        "max_rss_kib": ru.ru_maxrss,
        "returncode": rc,
        "signal": -rc if rc is not None and rc < 0 else None,
        "timed_out": timed_out,
        "stderr_bytes": len(stderr_text.encode("latin-1", errors="replace")),
        "stderr_unexpected_lines": stderr_unexpected[:20],
        "stderr_crash_pattern": bool(CRASH_PATTERNS.search(stderr_text)),
        "inputs_copied": inputs_copied,
    }

    # 4. outputs
    for p in sorted(work.iterdir()):
        if p.is_file() and p.name not in inputs_copied:
            record["outputs"].append({"name": p.name, "bytes": p.stat().st_size, "sha256": sha256(p) if p.stat().st_size else None})
    req = work / required_output
    ro = record["required_output"]
    if req.is_file() and req.stat().st_size > 0:
        ro.update(present=True, bytes=req.stat().st_size, sha256=sha256(req))
        try:
            parsed = yl_parse_flavia.parse(req)
            problems = yl_parse_flavia.validate(parsed, expect_nodes)
            ro["parse"] = {"ok": not problems, "problems": problems, "summary": yl_parse_flavia.summary(parsed)}
            if not problems:
                doc = {**parsed, "blocks": [{**b, "rows": {str(k): v for k, v in b["rows"].items()}} for b in parsed["blocks"]]}
                (run_dir / "results.json").write_text(json.dumps(doc, indent=1) + "\n", encoding="utf-8")
        except ValueError as exc:
            ro["parse"] = {"ok": False, "problems": [str(exc)]}
    elif req.exists():
        ro.update(present=True, bytes=0)

    # 5. golden must be untouched
    after = check_manifest(input_manifest, legacy_dir)
    record["input_check_after"] = {"ok": not after, "problems": after}

    # 6. classify (first matching status wins)
    p = record["process"]
    if p["timed_out"]:
        status = "TIMEOUT"
    elif p["signal"] is not None or p["stderr_crash_pattern"]:
        status = "CRASHED"
    elif rc != 0 or p["stderr_unexpected_lines"]:
        status = "FAILED"
    elif not (ro["present"] and ro["parse"] and ro["parse"]["ok"]):
        status = "MISSING_OUTPUT"
    elif after:
        status = "GOLDEN_MODIFIED"
    else:
        status = "COMPLETED"
    record["status"] = status
    return finish(record, run_dir)


def finish(record: dict, run_dir: Path) -> int:
    record["finished_at"] = utc_now()
    record["run_dir"] = str(run_dir)
    (run_dir / "run-manifest.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    p = record.get("process") or {}
    print(f"{record['status']:20s} {record['case_id']}  rc={p.get('returncode')}  wall={p.get('wall_seconds')}s  rss={p.get('max_rss_kib')}KiB  -> {run_dir}")
    return 0 if record["status"] == "COMPLETED" else 1


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--case-id", required=True)
    ap.add_argument("--binary", required=True)
    ap.add_argument("--timeout", type=float, default=600.0)
    ap.add_argument("--runs-root", default=str(REPO_ROOT / "runs"))
    ap.add_argument("--label")
    ap.add_argument("--case-dir", help="override case directory (self-tests only)")
    return run(ap.parse_args(argv))


if __name__ == "__main__":
    sys.exit(main())
