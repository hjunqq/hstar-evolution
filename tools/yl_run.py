#!/usr/bin/env python3
"""Isolated, fail-closed runner for the legacy YL solver (M0-03).

Every run:
  1. verifies the case's input-manifest.json (INPUT_HASH_MISMATCH otherwise);
  2. copies the inputs into a fresh directory runs/<case_id>/<utc>_<hash8>/work;
  3. runs the binary there with stdin=/dev/null in its own process group,
     single-threaded, without LD_LIBRARY_PATH, under a wall-clock timeout
     (SIGTERM to the group, then SIGKILL after a grace period);
  4. parses the binary's structured diagnostics (stderr `HSTAR_DIAG ...` lines,
     M1-02 exit protocol; every integer key must be an integer; every record is
     kept in order, M1-03 string keys value= / allowed= included) and check-mode
     summary (stdout `HSTAR_CHECK*` lines, same strict shlex rules as HSTAR_DIAG:
     schema=1, mode=check-legacy, integer errors, readers_executed == number of
     HSTAR_CHECK_READER lines, zero included);
  5. parses the required output and re-verifies the golden inputs; with
     --dump-state, normalizes the M2-02 state dump the binary wrote under
     <work>/state into <run_dir>/state via yl_state.normalize;
  6. classifies the outcome (first match in STATUS_ORDER wins): INPUT_ERROR /
     UNSUPPORTED / INIT_ERROR / SOLVE_ERROR / INTERNAL_ERROR require rc == the
     diagnostic's exit= (2..6); a malformed HSTAR_DIAG line, an exit= outside
     2..6 or rc != exit= is a protocol violation -> FAILED; a check summary that
     is malformed or not (status=OK, errors=0) with rc 0 is FAILED too;
     GOLDEN_MODIFIED is decided before CHECKED / MISSING_OUTPUT / COMPLETED;
     a requested state dump that does not normalize turns CHECKED /
     MISSING_OUTPUT / COMPLETED into FAILED (GOLDEN_MODIFIED and every status
     more specific than FAILED are left alone);
  7. writes run-manifest.json (+ results.json when the output parsed).

Only COMPLETED may feed a comparison. The process exit code is 0 iff the final
status equals --expect-status (default COMPLETED); the manifest records both
`expected_status` and `expectation_met`.

Usage:
  yl_run.py --case-id static_2d.cooks_membrane --binary build/release/hstar
            [--timeout 600] [--runs-root runs] [--label NAME]
            [--expect-status COMPLETED] [--binary-args "--check-legacy"]
            [--case-dir DIR]   # override the case directory (self-tests / probes)
            [--dump-state] [--state-map docs/m2/state-field-map.toml]

--dump-state pre-creates <work>/state/<sanitized checkpoint>/ for every covered
checkpoint of the field map (the Fortran writer opens into those directories and
never creates them), appends the relative `--dump-state=state` to the binary
command line (relative because the process runs with cwd=<work>, so the recorded
command stays host independent) and normalizes the result afterwards.  It is
mutually exclusive with `--binary-args "--check-legacy"`: check mode exits before
the first checkpoint, so the combination is refused here (exit 3) rather than left
to the binary, whose PARSE exit 2 would be misread as INPUT_ERROR.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import resource
import shlex
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
STATUS_ORDER = [
    "INPUT_HASH_MISMATCH", "TIMEOUT", "CRASHED",
    "INPUT_ERROR", "UNSUPPORTED", "INIT_ERROR", "SOLVE_ERROR", "INTERNAL_ERROR", "FAILED",
    "GOLDEN_MODIFIED", "CHECKED", "MISSING_OUTPUT", "COMPLETED",
]
CRASH_PATTERNS = re.compile(r"forrtl:|severe \(|Segmentation fault|MemorySanitizer|core dumped", re.I)
# The legacy program writes its wall-clock stamps to stderr; nothing else is expected there.
BENIGN_STDERR = re.compile(r"^\s*time(?:\(\w+\))?:\s*\d\d:\d\d:\d\d\s*$")
GRACE_SECONDS = 5.0
# M1-02 exit protocol: one structured line per diagnostic on stderr, summary lines on stdout.
DIAG_PREFIX = "HSTAR_DIAG "
CHECK_PREFIX = "HSTAR_CHECK"
DIAG_INT_KEYS = {"exit", "seq", "index", "iostat", "schema"}
CHECK_INT_KEYS = {"errors", "readers_executed", "readers_registered", "schema", "n"}
CHECK_MODE = "check-legacy"
CORE_FILE = re.compile(r"^core(?:\..*)?$")
DIAG_SCHEMA = 1
# exit code -> status, for a run whose rc equals the exit= of a well-formed HSTAR_DIAG line
EXIT_STATUS = {2: "INPUT_ERROR", 3: "UNSUPPORTED", 4: "INIT_ERROR", 5: "SOLVE_ERROR", 6: "INTERNAL_ERROR"}
# M2-02 state dump: subdirectory of <work> written by the binary, mirrored normalized under <run_dir>
STATE_SUBDIR = "state"
STATE_FLAG = f"--dump-state={STATE_SUBDIR}"
CHECK_FLAG = "--check-legacy"
USAGE_EXIT = 3
# a requested dump that does not normalize demotes these statuses to FAILED; every status ahead of
# FAILED in STATUS_ORDER is more specific, and GOLDEN_MODIFIED must never be masked by a dump problem
STATE_DEMOTES = {"FAILED", "CHECKED", "MISSING_OUTPUT", "COMPLETED"}


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


def parse_kv_line(line: str, int_keys: set[str], strict: bool = False) -> dict:
    """Parse `key=value key="quoted value"` (shlex rules) into a dict; listed keys become int when possible.
    strict: raise ValueError on unbalanced quotes instead of falling back to whitespace splitting."""
    out: dict = {}
    try:
        tokens = shlex.split(line)
    except ValueError:
        if strict:
            raise
        tokens = line.split()
    for tok in tokens:
        if "=" not in tok:
            continue
        k, v = tok.split("=", 1)
        if k in int_keys:
            try:
                v = int(v)
            except ValueError:
                pass
        out[k] = v
    return out


def parse_diag_line(body: str) -> dict:
    """Strict HSTAR_DIAG record: shlex-parsable, schema=1, a code, an integer exit, and every
    present integer key (exit/seq/index/iostat/schema) an integer. ValueError otherwise.
    String keys (field, message, M1-03 value / allowed, ...) are kept as parsed."""
    kv = parse_kv_line(body, DIAG_INT_KEYS, strict=True)
    if kv.get("schema") != DIAG_SCHEMA:
        raise ValueError(f"schema {kv.get('schema')!r} != {DIAG_SCHEMA}")
    if not kv.get("code"):
        raise ValueError("missing code")
    if not isinstance(kv.get("exit"), int):
        raise ValueError(f"exit {kv.get('exit')!r} is not an integer")
    bad = [f"{k}={kv[k]!r}" for k in sorted(DIAG_INT_KEYS) if k in kv and not isinstance(kv[k], int)]
    if bad:
        raise ValueError(f"non-integer {', '.join(bad)}")
    return kv


def parse_diagnostics(stderr_text: str) -> tuple[list[dict], list[str], list[str]]:
    """Split stderr into well-formed HSTAR_DIAG records, malformed HSTAR_DIAG lines and the
    remaining non-benign lines."""
    diags, malformed, other = [], [], []
    for ln in stderr_text.splitlines():
        if ln.startswith(DIAG_PREFIX):
            try:
                diags.append(parse_diag_line(ln[len(DIAG_PREFIX):]))
            except ValueError as exc:
                malformed.append(f"{ln[:300]}  [{exc}]")
        elif ln.strip() and not BENIGN_STDERR.match(ln):
            other.append(ln)
    return diags, malformed, other


def parse_check_summary(stdout_text: str) -> tuple[dict | None, list[str]]:
    """Collect stdout HSTAR_CHECK / HSTAR_CHECK_READER lines -> (summary, problems).
    summary is None when the binary emitted none. problems lists every deviation from the
    check-mode contract: every line strictly shlex-parsable (unbalanced quotes reject the
    line); exactly one HSTAR_CHECK line with schema=1, mode=check-legacy, a status, integer
    errors and readers_executed; readers_executed equal to the number of HSTAR_CHECK_READER
    lines (zero included); every HSTAR_CHECK_READER with an id and integer n."""
    summary: dict | None = None
    readers: dict[str, int] = {}
    problems: list[str] = []
    reader_lines = 0
    summary_malformed = False
    for ln in stdout_text.splitlines():
        if not ln.startswith(CHECK_PREFIX):
            continue
        tag, _, rest = ln.partition(" ")
        try:
            kv = parse_kv_line(rest, CHECK_INT_KEYS, strict=True)
        except ValueError as exc:  # unbalanced quotes: the line is rejected as a whole
            problems.append(f"malformed {tag} line ({exc}): {ln[:200]}")
            if tag == "HSTAR_CHECK_READER":
                reader_lines += 1
            elif tag == "HSTAR_CHECK":
                summary_malformed = True
                if summary is None:
                    summary = {"status": None, "readers_executed": None}
            continue
        if tag == "HSTAR_CHECK_READER":
            reader_lines += 1
            rid, n = kv.get("id"), kv.get("n")
            if not rid or not isinstance(n, int):
                problems.append(f"malformed HSTAR_CHECK_READER line: {ln[:200]}")
                continue
            readers[str(rid)] = readers.get(str(rid), 0) + n
        elif tag == "HSTAR_CHECK":
            if summary is not None:
                problems.append(f"duplicate HSTAR_CHECK line: {ln[:200]}")
                continue
            summary = {"status": kv.get("status"), "readers_executed": kv.get("readers_executed"),
                       **{k: v for k, v in kv.items() if k not in ("status", "readers_executed")}}
        else:
            problems.append(f"unknown HSTAR_CHECK* tag: {ln[:200]}")
    if summary is None and not readers and not problems:
        return None, []
    if summary is None:
        summary = {"status": None, "readers_executed": None}
        problems.append("HSTAR_CHECK summary line missing")
    elif not summary_malformed:
        if summary.get("schema") != DIAG_SCHEMA:
            problems.append(f"schema {summary.get('schema')!r} != {DIAG_SCHEMA}")
        if summary.get("mode") != CHECK_MODE:
            problems.append(f"mode {summary.get('mode')!r} != {CHECK_MODE!r}")
        if not summary.get("status"):
            problems.append("missing status")
        if not isinstance(summary.get("errors"), int):
            problems.append(f"errors {summary.get('errors')!r} is not an integer")
        if not isinstance(summary.get("readers_executed"), int):
            problems.append(f"readers_executed {summary.get('readers_executed')!r} is not an integer")
        elif summary["readers_executed"] != reader_lines:  # zero lines must match readers_executed=0 too
            problems.append(f"readers_executed={summary['readers_executed']} but {reader_lines} HSTAR_CHECK_READER lines")
    summary["readers"] = readers
    return summary, problems


def check_ok(check: dict | None, check_malformed: list[str]) -> bool:
    """True when the check summary satisfies the contract: well-formed, status=OK, errors=0."""
    return check is not None and not check_malformed and check.get("status") == "OK" and check.get("errors") == 0


def classify(p: dict, ro: dict, after: list[str], diags: list[dict], malformed: list[str], check: dict | None,
             check_malformed: list[str], core_dump: bool) -> str:
    """First matching status in STATUS_ORDER wins (INPUT_HASH_MISMATCH is decided before the run)."""
    rc = p["returncode"]
    exits = {d.get("exit") for d in diags}
    if p["timed_out"]:
        return "TIMEOUT"
    if p["signal"] is not None or p["stderr_crash_pattern"] or core_dump:
        return "CRASHED"
    protocol_ok = not malformed and exits <= set(EXIT_STATUS) and (not diags or rc in exits)
    if protocol_ok and rc in EXIT_STATUS and rc in exits:
        return EXIT_STATUS[rc]
    if rc != 0 or p["stderr_unexpected_lines"] or not protocol_ok:
        return "FAILED"  # includes protocol violations: malformed lines, exit= outside the protocol, rc != exit=
    if check is not None and not check_ok(check, check_malformed):
        return "FAILED"  # check summary emitted but malformed, or status != OK / errors != 0 with rc 0
    if after:
        return "GOLDEN_MODIFIED"  # decided before CHECKED/COMPLETED: a run that touched the golden inputs is never accepted
    if check is not None:
        return "CHECKED"  # check mode stops before the solve: no required output expected
    if not ro.get("not_applicable") and not (ro["present"] and ro["parse"] and ro["parse"]["ok"]):
        return "MISSING_OUTPUT"
    return "COMPLETED"


def failure_reason(p: dict, diags: list[dict], malformed: list[str], check: dict | None, check_malformed: list[str]) -> str | None:
    """Why classify() returned FAILED (None for any other status)."""
    rc = p["returncode"]
    exits = {d.get("exit") for d in diags}
    if malformed:
        return f"malformed HSTAR_DIAG line(s): {len(malformed)}"
    if not exits <= set(EXIT_STATUS):
        return f"HSTAR_DIAG exit= outside 2..6: {sorted(exits - set(EXIT_STATUS))}"
    if diags and rc not in exits:
        return f"rc={rc} does not equal any HSTAR_DIAG exit= {sorted(exits)}"
    if rc != 0:
        return f"rc={rc} without a matching HSTAR_DIAG line"
    if p["stderr_unexpected_lines"]:
        return f"unexpected stderr line(s): {len(p['stderr_unexpected_lines'])}"
    if check_malformed:
        return f"malformed HSTAR_CHECK summary: {check_malformed[0]}"
    if check is not None and not check_ok(check, check_malformed):
        return f"HSTAR_CHECK status={check.get('status')!r} errors={check.get('errors')!r} with rc 0"
    return None


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


def usage_error(msg: str):
    """Reject an unusable flag combination before anything is created (exit 3, never a run status)."""
    print(f"usage error: {msg}", file=sys.stderr)
    raise SystemExit(USAGE_EXIT)


def load_state_map(map_path: str | None):
    """(yl_state module, MapIndex) for the M2-02 field map; usage error when it cannot be loaded."""
    import yl_state  # local: a plain run must not depend on the M2-02 tooling being importable
    path = Path(map_path).resolve() if map_path else yl_state.MAP_DEFAULT
    try:
        return yl_state, yl_state.MapIndex.load(path)
    except Exception as exc:  # OSError / TOMLDecodeError / KeyError / ...
        return usage_error(f"cannot load the state field map {path}: {type(exc).__name__}: {exc}")


def prepare_state_dirs(yl_state, mp, work: Path) -> Path:
    """Pre-create <work>/state/<sanitized checkpoint>/ for every covered checkpoint of the map.

    The Fortran writer opens `state/<dir>/state.txt` and has no portable mkdir, so a missing
    directory is a structural failure of the dump rather than a recoverable condition."""
    raw = work / STATE_SUBDIR
    for cp in mp.order:
        (raw / yl_state.sanitize(cp)).mkdir(parents=True, exist_ok=True)
    return raw


def normalize_state(yl_state, mp, raw: Path, out: Path) -> dict:
    """Normalize the raw dump into `out` and return the manifest `state` block (fail-closed)."""
    try:
        res = yl_state.normalize(raw, out, mp)
    except Exception as exc:  # a normalizer crash is a dump problem, never a runner crash
        res = {"ok": False, "problems": [f"yl_state.normalize raised {type(exc).__name__}: {exc}"],
               "map": mp.map_ref(), "checkpoints": {}, "fingerprint": None}
    ok = bool(res.get("ok"))
    return {
        "requested": True,
        "dump_dir": str(raw),
        "normalized_dir": str(out) if ok else None,  # nothing is written unless the dump is clean
        "map": res.get("map") or mp.map_ref(),
        "checkpoints": res.get("checkpoints") or {},
        "fingerprint": res.get("fingerprint"),
        "normalize": {"ok": ok, "problems": list(res.get("problems") or [])},
    }


def run(args: argparse.Namespace) -> int:
    case_dir = Path(args.case_dir).resolve() if args.case_dir else find_case(args.case_id)
    legacy_dir = case_dir / "legacy"
    input_manifest = case_dir / "input-manifest.json"
    observables_path = case_dir / "observables.toml"
    if observables_path.is_file():
        observables = tomllib.loads(observables_path.read_text(encoding="utf-8"))
        required_output = observables["source"]["file"]
        expect_nodes = int(observables["source"]["expected_node_count"])
        ro_init = {"file": required_output, "present": False, "bytes": None, "sha256": None, "parse": None}
    elif args.case_dir:  # derived probe cases may carry no observables: output parsing is not applicable
        required_output, expect_nodes = None, None
        ro_init = {"file": None, "present": None, "parse": None, "not_applicable": True}
    else:
        raise SystemExit(f"observables.toml missing in registered case: {case_dir}")
    binary = Path(args.binary).resolve()
    if not binary.is_file():
        raise SystemExit(f"binary not found: {binary}")
    binary_args = shlex.split(args.binary_args) if args.binary_args else []
    if args.expect_status not in STATUS_ORDER:
        raise SystemExit(f"--expect-status must be one of {STATUS_ORDER}, got {args.expect_status!r}")
    # check mode exits before the first checkpoint: refuse the combination here, so the binary's
    # PARSE exit 2 is never classified as INPUT_ERROR
    if args.dump_state and any(a == CHECK_FLAG or a.startswith(CHECK_FLAG + "=") for a in binary_args):
        usage_error(f"--dump-state and {CHECK_FLAG} are mutually exclusive")
    state_mod, state_map = load_state_map(args.state_map) if args.dump_state else (None, None)
    if args.dump_state:
        binary_args = [*binary_args, STATE_FLAG]

    record: dict = {
        "manifest_version": 1,
        "case_id": args.case_id,
        "case_dir": str(case_dir),
        "label": args.label,
        "status": None,
        "expected_status": args.expect_status,
        "expectation_met": None,
        "binary": {"path": str(binary), "sha256": sha256(binary)},
        "build_manifest": None,
        "platform": {"os": platform.platform(), "machine": platform.machine(), "hostname": platform.node()},
        "threads": {"OMP_NUM_THREADS": "1", "MKL_NUM_THREADS": "1"},
        "timeout_seconds": args.timeout,
        "input_check_before": None,
        "input_check_after": None,
        "process": None,
        "required_output": ro_init,
        "outputs": [],
        "diagnostics": [],
        "diagnostics_malformed": [],
        "check_summary": None,
        "check_malformed": [],
        "protocol_violation": None,
        "core_dump": False,
        "state": None,  # M2-02 dump; stays null unless --dump-state was given
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
    # the checkpoint directories are created after inputs_copied, so `state` is never counted as
    # an input, and before the launch, because the Fortran writer cannot create them
    state_raw = prepare_state_dirs(state_mod, state_map, work) if args.dump_state else None

    # 3. run
    env = {k: v for k, v in os.environ.items() if k not in ("LD_LIBRARY_PATH", "LD_PRELOAD")}
    env.update({"OMP_NUM_THREADS": "1", "MKL_NUM_THREADS": "1", "MKL_DYNAMIC": "FALSE"})
    if args.case_dir:  # self-test hook: lets a fake binary find the golden dir
        env["YL_RUN_GOLDEN_DIR"] = str(legacy_dir)
    stdout_f = open(run_dir / "stdout.txt", "wb")
    stderr_f = open(run_dir / "stderr.txt", "wb")
    t0 = time.monotonic()
    started = utc_now()
    command = [str(binary), *binary_args]
    proc = subprocess.Popen(command, cwd=work, stdin=subprocess.DEVNULL, stdout=stdout_f, stderr=stderr_f, env=env, start_new_session=True)
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
    stdout_text = (run_dir / "stdout.txt").read_text(encoding="latin-1", errors="replace")
    diags, malformed, stderr_unexpected = parse_diagnostics(stderr_text)
    record["diagnostics"] = diags
    record["diagnostics_malformed"] = malformed
    record["check_summary"], record["check_malformed"] = parse_check_summary(stdout_text)
    record["process"] = {
        "command": command,
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
            if CORE_FILE.match(p.name):
                record["core_dump"] = True
    ro = record["required_output"]
    req = work / required_output if required_output else None
    if req is None:
        pass
    elif req.is_file() and req.stat().st_size > 0:
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

    # 5b. the requested state dump, normalized next to the run
    if args.dump_state:
        record["state"] = normalize_state(state_mod, state_map, state_raw, run_dir / STATE_SUBDIR)

    # 6. classify (first matching status wins)
    record["status"] = classify(record["process"], ro, after, diags, malformed, record["check_summary"], record["check_malformed"], record["core_dump"])
    if record["status"] == "FAILED":
        record["protocol_violation"] = failure_reason(record["process"], diags, malformed, record["check_summary"], record["check_malformed"])
    state = record["state"]
    if state and not state["normalize"]["ok"] and record["status"] in STATE_DEMOTES:
        # an accepted run must never carry an invalid snapshot; a pre-existing reason keeps priority
        first = (state["normalize"]["problems"] or ["no problem reported"])[0]
        record["status"] = "FAILED"
        record["protocol_violation"] = record["protocol_violation"] or f"state dump malformed: {first}"
    return finish(record, run_dir)


def finish(record: dict, run_dir: Path) -> int:
    record["finished_at"] = utc_now()
    record["run_dir"] = str(run_dir)
    expected = record.get("expected_status") or "COMPLETED"
    record["expectation_met"] = record["status"] == expected
    (run_dir / "run-manifest.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    p = record.get("process") or {}
    extra = f"  expected={expected}" if expected != "COMPLETED" else ""
    if record.get("diagnostics"):
        d = record["diagnostics"][0]
        extra += f"  diag={d.get('code')}@{d.get('reader') or d.get('file')}"
    state = record.get("state")
    if state:
        extra += (f"  state={state['fingerprint'][:12]}" if state["normalize"]["ok"]
                  else f"  state=FAIL({len(state['normalize']['problems'])})")
    if record.get("protocol_violation"):
        extra += f"  reason={record['protocol_violation']}"
    print(f"{record['status']:20s} {record['case_id']}  rc={p.get('returncode')}  wall={p.get('wall_seconds')}s  rss={p.get('max_rss_kib')}KiB{extra}  -> {run_dir}")
    return 0 if record["expectation_met"] else 1


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--case-id", required=True)
    ap.add_argument("--binary", required=True)
    ap.add_argument("--timeout", type=float, default=600.0)
    ap.add_argument("--runs-root", default=str(REPO_ROOT / "runs"))
    ap.add_argument("--label")
    ap.add_argument("--case-dir", help="override case directory (self-tests / derived probe cases)")
    ap.add_argument("--expect-status", default="COMPLETED", metavar="STATUS", help="exit 0 iff the final status equals this (default COMPLETED)")
    ap.add_argument("--binary-args", default="", metavar="ARGS", help="extra arguments appended to the binary command line (shlex-split)")
    ap.add_argument("--dump-state", action="store_true",
                    help=f"pre-create <work>/{STATE_SUBDIR}/<checkpoint>/, append `{STATE_FLAG}` to the binary "
                         f"and normalize the dump into <run_dir>/{STATE_SUBDIR}/ (excludes {CHECK_FLAG})")
    ap.add_argument("--state-map", metavar="TOML", help="M2-02 field map (default docs/m2/state-field-map.toml)")
    argv = list(sys.argv[1:] if argv is None else argv)
    # `--binary-args "--check-legacy"`: join so argparse does not mistake the value for an option
    for i, tok in enumerate(argv[:-1]):
        if tok in ("--binary-args", "--expect-status") and argv[i + 1].startswith("-"):
            argv[i:i + 2] = [f"{tok}={argv[i + 1]}"]
            break
    return run(ap.parse_args(argv))


if __name__ == "__main__":
    sys.exit(main())
