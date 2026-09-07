#!/usr/bin/env python3
"""State-perturbation probe runner for the legacy YL solver (M2-03).

Where `tools/yl_probe.py` damages an input and asserts a *diagnostic* (M1-02 exit
protocol), this tool perturbs exactly one well-formed input token and asserts a
*state difference*: the M2-02 normalized snapshot of a perturbed run, compared
against a frozen reference snapshot, must show precisely the field the map's
`[[perturbation]]` entry predicts and nothing else.

The materialisation, derive and write-guard logic is imported from
tools/yl_probe.py rather than duplicated; the comparison is delegated to
tools/yl_state_diff.py and every assertion is made against that tool's `-o`
JSON report, never against its text (the text is archived verbatim).

Subcommands
  list                            list the probe specs under cases/probes/state/
  freeze --case ID --from RUN     copy RUN/state to the case's reference/state and
                                  write reference/frozen.json (digests + provenance)
  verify --case ID                re-hash the frozen tree against frozen.json
  repeat --case ID --binary B     N dump-on runs of one binary; identical fingerprints
                                  and pairwise-PASS comparisons -> repeat-state-report.json
  run [--ids ...] --binary B      materialise, perturb, run, compare and assert
  --selftest                      guard rails, hermetically (no solver binary needed)

Freeze is deliberately one-shot and fail-closed:
  * the destination is computed, never taken from the command line: it is exactly
    cases/golden/<family>/<name>/reference/state;
  * an existing destination -- including a symlink -- is refused, and there is no
    --force: the frozen tree is evidence and is never rewritten in place;
  * the tree is COPIED from the run directory.  `yl_state.normalize()` rmtree()s its
    output directory before writing (tools/yl_state.py:702), so pointing the
    normalizer at reference/state would destroy the frozen baseline;
  * only regular files and directories are copied or hashed; a symlink anywhere in
    the source or the frozen tree is a hard error;
  * the run manifest's `case_id` is not taken on trust: the node and element counts
    read out of the snapshot itself must match the counts the destination case
    registered in observables.toml, so a tree cannot be filed under the wrong case.
  * `verify` runs automatically before every probe, so a probe can never compare
    against a baseline that drifted.

probe.toml (cases/probes/state/<id>/probe.toml)
  schema = 1
  id = "S03_BC_cooks"
  base_case = "static_2d.cooks_membrane"
  description = "..."
  original_token = "17*0."            # the token as it stands in the golden deck
  [[derive]]                          # exactly one, and it must be set_field
  op = "set_field"; file = "1.pre"; line = 5; field = 1; value = "1.0e-3,16*0."
  [expect_state]
  comparator_exit = 1                 # 1 = values only; 2 = structural
  mismatch_count  = 1                 # MISMATCH findings with secondary_of == null
  stage = "model_ready"               # \
  field = "steps0.boundary.value"     #  |
  path  = "steps[0].boundary[set=1,rec=1,node=1].value"   # string-exact against the
  rule  = "exact"                     #  |  first primary MISMATCH finding
  expected = "0e+00(0000000000000000)"#  |
  actual   = "1e-03(3F50624DD2F1A9FC)"# /
  changed_values = 1                  # leaves of `field` that differ between the frozen
                                      # baseline and the run, counted from the snapshot data
                                      # (the finding's `count=n/total` is only printed for
                                      # multi-leaf fields, so it is cross-checked, not parsed)
  allow_secondary = []                # every secondary MISMATCH must be listed here, and
                                      # each listed field must actually derive from `field`
                                      # (checked against the map's derived_from closure at
                                      # spec-load time, so a typo cannot widen the whitelist)
  forbid_fields = ["runtime.dof.fixed"]  # must be exported at all (an `ignore`/`emit = "none"`
                                      # field is refused at load: forbidding what is never
                                      # written asserts nothing); must appear in no finding;
                                      # and wherever the FROZEN
                                      # BASELINE exports them as all-zero, the perturbed run
                                      # must keep them all-zero (R24 turned into a test).  A
                                      # forbidden field that is legitimately non-zero in the
                                      # baseline is only held to the "no finding" rule.

A probe that changes an input but produces *no* finding is a FAILURE, never a pass:
`--selftest` contains a null-perturbation case that pins exactly this.

Only the Python standard library is used.
"""
from __future__ import annotations

import argparse
import hashlib
import itertools
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import yl_probe  # noqa: E402
import yl_state  # noqa: E402
from yl_probe import ProbeError  # noqa: E402
from yl_state_map import MAP_DEFAULT, SNAPSHOT_FILES, load_map  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent
CASES_DIR = REPO_ROOT / "cases"
GOLDEN_DIR = CASES_DIR / "golden"
PROBES_DIR = CASES_DIR / "probes" / "state"
YL_RUN = REPO_ROOT / "tools" / "yl_run.py"
YL_STATE_DIFF = REPO_ROOT / "tools" / "yl_state_diff.py"

TOOL = "yl_state_probe.py/1"
FROZEN_SCHEMA = 1
FROZEN_NAME = "frozen.json"
STATE_NAME = "state"
REFERENCE_NAME = "reference"
FINGERPRINT_NAME = "fingerprint.json"
JSON_FILES = [n[:-len(".sha256")] + ".json" if n.endswith(".sha256") else n for n in SNAPSHOT_FILES]
COUNT_RE = re.compile(r"\bcount=(\d+)/(\d+)\b")
EXPECT_REQUIRED = ("comparator_exit", "mismatch_count", "stage", "field", "path", "rule",
                   "expected", "actual", "changed_values")
EXPECT_STR = ("stage", "field", "path", "rule", "expected", "actual")
EXPECT_INT = ("comparator_exit", "mismatch_count", "changed_values")
EXPECT_LIST = ("allow_secondary", "forbid_fields")
EXPECT_KNOWN = set(EXPECT_REQUIRED) | set(EXPECT_LIST)


# ---------------------------------------------------------------- small helpers

def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, doc) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def is_int(x) -> bool:
    return isinstance(x, int) and not isinstance(x, bool)


def git_info() -> dict:
    def g(*args) -> str | None:
        try:
            r = subprocess.run(["git", "-C", str(REPO_ROOT), *args], capture_output=True, text=True, timeout=30)
        except (OSError, subprocess.SubprocessError):
            return None
        return r.stdout.strip() if r.returncode == 0 else None

    head = g("rev-parse", "HEAD")
    status = g("status", "--porcelain")
    return {"source_commit": head, "source_tree_dirty": None if status is None else bool(status.strip())}


# ---------------------------------------------------------------- paths and guards

def parse_case_id(case_id: str) -> tuple[str, str]:
    family, sep, name = str(case_id).partition(".")
    if not sep or not family or not name or "/" in case_id or "\\" in case_id or ".." in case_id.split("."):
        raise ProbeError(f"case id {case_id!r} must be <family>.<name>, e.g. static_2d.cooks_membrane")
    for part in (family, name):
        if part != Path(part).name or part in (".", ".."):
            raise ProbeError(f"case id {case_id!r} has an unusable path component {part!r}")
    return family, name


def resolve_golden_root(override: str | None) -> Path:
    """The root that holds <family>/<name>/.  Only --reference-root may move it, and never
    into the repository's cases/ tree: that override exists for the self-test fixture."""
    if not override:
        return GOLDEN_DIR
    root = Path(override).resolve()
    cases = CASES_DIR.resolve()
    if root == cases or root.is_relative_to(cases) or cases.is_relative_to(root):
        raise ProbeError(f"--reference-root {override} overlaps {CASES_DIR}: it is a self-test fixture override only")
    return root


def case_dir(case_id: str, golden_root: Path) -> Path:
    family, name = parse_case_id(case_id)
    d = golden_root / family / name
    if not (d / "legacy").is_dir():
        raise ProbeError(f"golden case not found for {case_id!r}: {d}")
    return d


def frozen_paths(case_id: str, golden_root: Path) -> tuple[Path, Path]:
    """(reference/state, reference/frozen.json) -- computed, never user supplied."""
    ref = case_dir(case_id, golden_root) / REFERENCE_NAME
    state = ref / STATE_NAME
    if state.name != STATE_NAME or state.parent.name != REFERENCE_NAME:
        raise ProbeError(f"internal: refusing an unexpected freeze destination {state}")
    # resolve the case directory, never the destination itself: `state` may be a
    # symlink planted to redirect the write, and following it would hide that
    if not ref.parent.resolve().is_relative_to(golden_root.resolve()):
        raise ProbeError(f"freeze destination {state} escapes {golden_root}")
    return state, ref / FROZEN_NAME


def hash_tree(root: Path) -> dict[str, str]:
    """{posix relative path: sha256} over every regular file below `root`.

    Symlinks and anything that is neither a regular file nor a directory are refused:
    a frozen baseline that can be re-pointed is not a baseline."""
    out: dict[str, str] = {}
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        here = Path(dirpath)
        for d in sorted(dirnames):
            if (here / d).is_symlink():
                raise ProbeError(f"{here / d} is a symlink: refusing to hash a frozen tree with symlinks")
        for f in sorted(filenames):
            p = here / f
            if p.is_symlink() or not p.is_file():
                raise ProbeError(f"{p} is not a regular file: refusing")
            out[p.relative_to(root).as_posix()] = sha256_file(p)
    return dict(sorted(out.items()))


def copy_tree_strict(src: Path, dst: Path) -> None:
    """Copy regular files and directories only; refuse symlinks and specials."""
    for dirpath, dirnames, filenames in os.walk(src, followlinks=False):
        here = Path(dirpath)
        rel = here.relative_to(src)
        (dst / rel).mkdir(parents=True, exist_ok=True)
        for d in dirnames:
            if (here / d).is_symlink():
                raise ProbeError(f"{here / d} is a symlink: refusing to freeze it")
        for f in filenames:
            p = here / f
            if p.is_symlink() or not p.is_file():
                raise ProbeError(f"{p} is not a regular file: refusing to freeze it")
            shutil.copy2(p, dst / rel / f)


# ---------------------------------------------------------------- map indexing

class StateMap:
    """The subset of docs/m2/state-field-map.toml this tool needs."""

    def __init__(self, doc: dict, path: Path):
        self.doc, self.path = doc, path
        self.sha256 = sha256_file(path) if path.is_file() else None
        self.covered = [c["id"] for c in doc.get("checkpoint", []) if c.get("covered")]
        self.by_cp: dict[str, dict[str, dict]] = {c: {} for c in self.covered}
        self.ids: set[str] = set()
        for f in doc.get("field", []):
            self.ids.add(f["id"])
            if f.get("checkpoint") in self.by_cp:
                self.by_cp[f["checkpoint"]][f["id"]] = f

    @classmethod
    def load(cls, path) -> "StateMap":
        p = Path(path)
        if not p.is_file():
            raise ProbeError(f"field map not found: {p}")
        return cls(load_map(p), p)

    def ref(self) -> dict:
        try:
            rel = str(self.path.resolve().relative_to(REPO_ROOT))
        except ValueError:
            rel = str(self.path)
        return {"path": rel, "sha256": self.sha256}

    def field(self, cp: str, fid: str) -> dict:
        return self.by_cp.get(cp, {}).get(fid, {})

    def ancestors(self, cp: str, fid: str) -> set[str]:
        """Transitive derived_from closure of `fid` at checkpoint `cp` -- the same walk
        tools/yl_state_diff.py uses to attach `secondary_of`."""
        seen: set[str] = set()
        queue = list(self.field(cp, fid).get("derived_from") or [])
        while queue:
            p = queue.pop(0)
            if p in seen:
                continue
            seen.add(p)
            queue.extend(self.field(cp, p).get("derived_from") or [])
        return seen


# ---------------------------------------------------------------- probe specs

def load_state_probe(path: Path, smap: StateMap, golden_root: Path | None = None) -> dict:
    probe = tomllib.loads(path.read_text(encoding="utf-8"))
    for key in ("schema", "id", "base_case", "description", "derive", "expect_state"):
        if key not in probe:
            raise ProbeError(f"{path}: missing key {key!r}")
    if probe["schema"] != 1:
        raise ProbeError(f"{path}: unsupported schema {probe['schema']}")
    if probe["id"] != path.parent.name:
        raise ProbeError(f"{path}: id {probe['id']!r} does not match directory {path.parent.name!r}")
    parse_case_id(probe["base_case"])

    derive = probe["derive"]
    if not isinstance(derive, list) or len(derive) != 1:
        raise ProbeError(f"{path}: exactly one derive operation is required, got {len(derive) if isinstance(derive, list) else type(derive).__name__}")
    d = derive[0]
    if d.get("op") != "set_field":
        raise ProbeError(f"{path}: derive op must be set_field, got {d.get('op')!r}")
    for key in ("file", "line", "field", "value"):
        if key not in d:
            raise ProbeError(f"{path}: derive missing {key!r}")
    yl_probe.check_derive_file_name(str(d["file"]), path)
    if not is_int(d["line"]) or d["line"] < 1:
        raise ProbeError(f"{path}: derive line must be an integer >= 1")
    if not is_int(d["field"]) or d["field"] < 1:
        raise ProbeError(f"{path}: derive field must be an integer >= 1")
    if not isinstance(d["value"], str) or not d["value"] or any(c.isspace() for c in d["value"]):
        raise ProbeError(f"{path}: derive value must be one non-empty whitespace-free token")
    # original_token may sit beside the derive it guards or at the top level; both must agree
    tokens = [t for t in (probe.get("original_token"), d.get("original_token")) if t is not None]
    if not tokens:
        raise ProbeError(f"{path}: missing key 'original_token' (top level or inside [[derive]])")
    if any(not isinstance(t, str) or not t for t in tokens):
        raise ProbeError(f"{path}: original_token must be a non-empty string")
    if len(set(tokens)) != 1:
        raise ProbeError(f"{path}: original_token differs between the top level and the derive: {tokens}")
    probe["original_token"] = tokens[0]
    if d["value"] == probe["original_token"]:
        raise ProbeError(f"{path}: derive value equals original_token {d['value']!r}: a null perturbation cannot be detected")

    exp = probe["expect_state"]
    if not isinstance(exp, dict):
        raise ProbeError(f"{path}: expect_state must be a table")
    missing = [k for k in EXPECT_REQUIRED if k not in exp]
    if missing:
        raise ProbeError(f"{path}: expect_state missing {missing}")
    unknown = sorted(set(exp) - EXPECT_KNOWN)
    if unknown:
        raise ProbeError(f"{path}: expect_state has unknown key(s) {unknown}")
    for k in EXPECT_STR:
        if not isinstance(exp[k], str) or not exp[k]:
            raise ProbeError(f"{path}: expect_state.{k} must be a non-empty string")
    for k in EXPECT_INT:
        if not is_int(exp[k]) or exp[k] < 0:
            raise ProbeError(f"{path}: expect_state.{k} must be an integer >= 0")
    if exp["comparator_exit"] not in (1, 2):
        raise ProbeError(f"{path}: expect_state.comparator_exit must be 1 (values) or 2 (structural)")
    if exp["mismatch_count"] < 1:
        raise ProbeError(f"{path}: expect_state.mismatch_count must be >= 1: a probe that detects nothing is a failed probe")
    if exp["changed_values"] < 1:
        raise ProbeError(f"{path}: expect_state.changed_values must be >= 1")
    for k in EXPECT_LIST:
        v = exp.setdefault(k, [])
        if not isinstance(v, list) or not all(isinstance(x, str) and x for x in v):
            raise ProbeError(f"{path}: expect_state.{k} must be an array of field ids")

    cp, fid = exp["stage"], exp["field"]
    if cp not in smap.covered:
        raise ProbeError(f"{path}: expect_state.stage {cp!r} is not a covered checkpoint {smap.covered}")
    if not smap.field(cp, fid):
        raise ProbeError(f"{path}: expect_state.field {fid!r} is not a map field at checkpoint {cp!r}")
    for sec in exp["allow_secondary"]:
        if not smap.field(cp, sec):
            raise ProbeError(f"{path}: allow_secondary {sec!r} is not a map field at checkpoint {cp!r}")
        anc = smap.ancestors(cp, sec)
        if fid not in anc:
            raise ProbeError(f"{path}: allow_secondary {sec!r} does not derive from {fid!r} "
                             f"(derived_from closure: {sorted(anc) or 'empty'})")
    frozen_state = None
    if golden_root is not None:
        try:
            cand, _ = frozen_paths(probe["base_case"], golden_root)
            frozen_state = cand if cand.is_dir() and not cand.is_symlink() else None
        except ProbeError:
            frozen_state = None
    for bad in exp["forbid_fields"]:
        if bad not in smap.ids:
            raise ProbeError(f"{path}: forbid_fields {bad!r} is not a field of {smap.path.name}: "
                             f"a field that cannot exist can never be caught")
        if bad == fid:
            raise ProbeError(f"{path}: forbid_fields lists the expected field {fid!r}")
        # A field the solver never exports can never appear in a finding, so forbidding it
        # asserts nothing while reading in the report like positive evidence.  Refuse it.
        row = next((f for f in smap.doc.get("field", []) if f["id"] == bad), {})
        why = None
        if ((row.get("compare") or {}).get("rule")) == "ignore":
            why = "its compare rule is `ignore`"
        elif row.get("emit") == "none":
            why = "its map entry sets `emit = \"none\"`"
        elif frozen_state is not None and not snapshot_field_entries(frozen_state, bad):
            why = f"it is absent from the frozen baseline snapshot {frozen_state}"
        if why:
            raise ProbeError(f"{path}: forbid_fields {bad!r} is never exported to a snapshot "
                             f"({why}): forbidding it would assert nothing")
    probe["_path"] = path
    return probe


def load_state_probes(smap: StateMap, ids: list[str] | None = None, probes_dir: Path | None = None,
                      golden_root: Path | None = None) -> list[dict]:
    root = probes_dir or PROBES_DIR
    probes = [load_state_probe(p, smap, golden_root) for p in sorted(root.glob("*/probe.toml"))]
    if not ids:
        return probes
    by_id = {p["id"]: p for p in probes}
    out = []
    for want in ids:
        hits = [pid for pid in by_id if pid == want or pid.startswith(want + "_")]
        if want in by_id:
            out.append(by_id[want])
        elif len(hits) == 1:
            out.append(by_id[hits[0]])
        elif not hits:
            raise ProbeError(f"no state probe matches {want!r}")
        else:
            raise ProbeError(f"{want!r} is ambiguous: {hits}")
    return out


# ---------------------------------------------------------------- the single-token edit

def tokens_of(body: str) -> list[str]:
    """Whitespace-separated tokens, indexed the way yl_probe.set_field indexes them."""
    return [t for t in re.split(r"\s+", body) if t]


def read_lines(path: Path) -> list[str]:
    data = path.read_bytes()
    return [ln.decode("latin-1") for ln in yl_probe.split_lines_keepends(data)]


def check_original_token(golden_legacy: Path, d: dict, original: str) -> str:
    """The token must read as the spec says *before* anything is materialised."""
    yl_probe.check_derive_file_name(str(d["file"]), "derive set_field")
    target = yl_probe.check_inside(golden_legacy / d["file"], golden_legacy, "derive set_field target")
    if not target.is_file():
        raise ProbeError(f"original_token: {d['file']} is not in {golden_legacy}")
    lines = read_lines(target)
    ln = int(d["line"])
    if not 1 <= ln <= len(lines):
        raise ProbeError(f"original_token: {d['file']} has {len(lines)} line(s), line={ln}")
    toks = tokens_of(lines[ln - 1])
    idx = int(d["field"])
    if idx > len(toks):
        raise ProbeError(f"original_token: {d['file']} line {ln} has {len(toks)} token(s), field={idx}")
    got = toks[idx - 1]
    if got != original:
        raise ProbeError(f"original_token stale: {d['file']} line {ln} token {idx} is {got!r}, "
                         f"the spec expects {original!r}")
    return got


def check_single_token_change(golden_legacy: Path, case_legacy: Path, d: dict) -> dict:
    """Exactly one token of exactly one line may differ between the golden deck and the
    materialised deck, and it must be the one the spec names."""
    name, ln, idx, value = str(d["file"]), int(d["line"]), int(d["field"]), str(d["value"])
    a = read_lines(yl_probe.check_inside(golden_legacy / name, golden_legacy, "golden deck file"))
    b = read_lines(yl_probe.check_inside(case_legacy / name, case_legacy, "materialised deck file"))
    if len(a) != len(b):
        raise ProbeError(f"perturbation changed the line count of {name}: {len(a)} -> {len(b)}")
    differing = [i + 1 for i, (x, y) in enumerate(zip(a, b)) if x != y]
    if not differing:
        raise ProbeError(f"null perturbation: {name} is byte-identical to the golden deck, "
                         f"nothing was changed at line {ln} token {idx}")
    if differing != [ln]:
        raise ProbeError(f"perturbation of {name} changed line(s) {differing}, expected exactly [{ln}]")
    ta, tb = tokens_of(a[ln - 1]), tokens_of(b[ln - 1])
    if len(ta) != len(tb):
        raise ProbeError(f"perturbation of {name} line {ln} changed the token count: {len(ta)} -> {len(tb)}")
    changed = [i + 1 for i, (x, y) in enumerate(zip(ta, tb)) if x != y]
    if not changed:
        raise ProbeError(f"null perturbation: {name} line {ln} is unchanged, token {idx} still reads {ta[idx - 1]!r}")
    if changed != [idx]:
        raise ProbeError(f"perturbation of {name} line {ln} changed token(s) {changed}, expected exactly [{idx}]")
    if tb[idx - 1] != value:
        raise ProbeError(f"perturbation of {name} line {ln} token {idx} is {tb[idx - 1]!r}, expected {value!r}")
    # everything but that token, spacing included, must survive byte for byte
    for i, other in enumerate(a):
        if i + 1 != ln and other != b[i]:  # pragma: no cover - already covered by `differing`
            raise ProbeError(f"perturbation touched {name} line {i + 1}")
    return {"file": name, "line": ln, "field": idx, "original_token": ta[idx - 1],
            "new_token": tb[idx - 1], "lines_changed": differing, "tokens_changed": changed}


# ---------------------------------------------------------------- freeze / verify

def registered_counts(case_path: Path) -> dict[str, int]:
    """The node/element counts the case registered in observables.toml (M0-05a)."""
    obs = case_path / "observables.toml"
    if not obs.is_file():
        raise ProbeError(f"{obs} is missing: nothing intrinsic to cross-check a frozen tree against")
    src = (tomllib.loads(obs.read_text(encoding="utf-8")).get("source") or {})
    out = {}
    for key, name in (("expected_node_count", "nodes"), ("expected_element_count", "elements")):
        if is_int(src.get(key)):
            out[name] = int(src[key])
    if not out:
        raise ProbeError(f"{obs} registers neither expected_node_count nor expected_element_count")
    return out


def tree_counts(state_dir: Path) -> dict[str, list[tuple[str, int]]]:
    """Node/element counts read back out of a normalized snapshot tree, from every field that
    carries them: the control-block scalars and the length of the mesh id vectors."""
    out: dict[str, list[tuple[str, int]]] = {"nodes": [], "elements": []}
    scalars = {"derived.counts.npoin": "nodes", "derived.counts.nelem": "elements"}
    vectors = {"mesh.nodes.id": "nodes", "mesh.elements.id": "elements"}
    for fid, what in scalars.items():
        for cp, _, e in snapshot_field_entries(state_dir, fid):
            vals = list(leaves(e.get("values")))
            if len(vals) == 1 and is_int(vals[0]):
                out[what].append((f"{cp}/{fid}", int(vals[0])))
    for fid, what in vectors.items():
        for cp, _, e in snapshot_field_entries(state_dir, fid):
            out[what].append((f"{cp}/{fid}", len(list(leaves(e.get("values"))))))
    return out


def check_tree_belongs_to_case(state_dir: Path, case_path: Path, case_id: str) -> dict[str, int]:
    """Refuse to freeze a snapshot whose own mesh size is not this case's.

    The run manifest's `case_id` is just text and can be edited; the mesh counts inside the
    snapshot cannot be, so they are what decides which case a tree belongs to."""
    want = registered_counts(case_path)
    got = tree_counts(state_dir)
    checked = 0
    for what, n in want.items():
        readings = got.get(what) or []
        if not readings:
            raise ProbeError(f"the snapshot exports no {what} count: cannot confirm it belongs to {case_id}")
        for where, value in readings:
            if value != n:
                raise ProbeError(f"snapshot does not belong to {case_id}: {where} says {value} "
                                 f"{what}, but {case_path.name} registers {n}")
            checked += 1
    return {**want, "readings_checked": checked}


def freeze(case_id: str, run_dir: Path, golden_root: Path) -> dict:
    case_path = case_dir(case_id, golden_root)
    dest, frozen_path = frozen_paths(case_id, golden_root)
    if dest.is_symlink() or dest.exists():
        raise ProbeError(f"freeze destination already exists: {dest} "
                         f"({'symlink' if dest.is_symlink() else 'directory' if dest.is_dir() else 'file'}); "
                         f"the frozen baseline is evidence and there is no --force")
    if frozen_path.is_symlink() or frozen_path.exists():
        raise ProbeError(f"{frozen_path} already exists: refusing to overwrite a freeze manifest")

    run_dir = Path(run_dir).resolve()
    man_path = run_dir / "run-manifest.json"
    if not man_path.is_file():
        raise ProbeError(f"no run-manifest.json under {run_dir}")
    man = read_json(man_path)
    if man.get("case_id") != case_id:
        raise ProbeError(f"{man_path}: case_id {man.get('case_id')!r} != {case_id!r}")
    if man.get("status") != "COMPLETED":
        raise ProbeError(f"{man_path}: status {man.get('status')!r}, only COMPLETED may be frozen")
    rc = (man.get("process") or {}).get("returncode")
    if rc != 0:
        raise ProbeError(f"{man_path}: returncode {rc!r}, only rc 0 may be frozen")
    state = man.get("state") or {}
    if not (state.get("normalize") or {}).get("ok"):
        raise ProbeError(f"{man_path}: the run has no clean --dump-state normalization")
    src = run_dir / STATE_NAME
    if src.is_symlink() or not src.is_dir():
        raise ProbeError(f"{src} is not a normalized state directory")
    if not (src / FINGERPRINT_NAME).is_file():
        raise ProbeError(f"{src / FINGERPRINT_NAME} is missing: not a normalized snapshot")
    # the manifest said this run is `case_id`; the tree itself has to agree, before anything is written
    identity = check_tree_belongs_to_case(src, case_path, case_id)

    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = Path(tempfile.mkdtemp(prefix=".freeze.", dir=str(dest.parent)))
    try:
        copy_tree_strict(src, tmp)
        os.rename(tmp, dest)
    finally:
        if tmp.exists():
            shutil.rmtree(tmp, ignore_errors=True)

    files = hash_tree(dest)
    fp_doc = read_json(dest / FINGERPRINT_NAME)
    src_case = Path(man.get("case_dir") or "")
    input_manifest = src_case / "input-manifest.json"
    inputs = {"path": None, "sha256": None, "files": []}
    if input_manifest.is_file():
        im = read_json(input_manifest)
        inputs = {"path": str(input_manifest), "sha256": sha256_file(input_manifest),
                  "files": [{"path": f["path"], "sha256": f["sha256"]} for f in im.get("files", [])]}
    bm_path = Path((man.get("build_manifest") or {}).get("path") or "")
    doc = {
        "schema": FROZEN_SCHEMA,
        "tool": TOOL,
        "case_id": case_id,
        "frozen_at": now(),
        "state_dir": dest.name,
        "fingerprint": fp_doc.get("fingerprint"),
        "case_identity": identity,
        "file_count": len(files),
        "total_bytes": sum((dest / rel).stat().st_size for rel in files),
        "files": files,
        "provenance": {
            **git_info(),
            "binary_path": (man.get("binary") or {}).get("path"),
            "binary_sha256": (man.get("binary") or {}).get("sha256"),
            "build_manifest_path": str(bm_path) if bm_path.name else None,
            "build_manifest_profile": (man.get("build_manifest") or {}).get("profile"),
            "build_manifest_sha256": sha256_file(bm_path) if bm_path.is_file() else None,
            "map": state.get("map") or {},
            "normalizer": fp_doc.get("normalizer") or yl_state.NORMALIZER,
            "source_run_id": run_dir.name,
            "source_run_dir": str(run_dir),
            "source_run_manifest_sha256": sha256_file(man_path),
            "source_case_dir": str(src_case) if src_case.name else None,
            "input_manifest_path": inputs["path"],
            "input_manifest_sha256": inputs["sha256"],
            "input_files": inputs["files"],
        },
    }
    write_json(frozen_path, doc)
    return doc


def verify(case_id: str, golden_root: Path) -> dict:
    dest, frozen_path = frozen_paths(case_id, golden_root)
    problems: list[str] = []
    if not frozen_path.is_file():
        return {"case_id": case_id, "state_dir": str(dest), "frozen": str(frozen_path), "ok": False,
                "checked": 0, "problems": [f"no freeze manifest: {frozen_path}"]}
    doc = read_json(frozen_path)
    if doc.get("schema") != FROZEN_SCHEMA:
        problems.append(f"{frozen_path}: unsupported schema {doc.get('schema')!r}")
    if doc.get("case_id") != case_id:
        problems.append(f"{frozen_path}: case_id {doc.get('case_id')!r} != {case_id!r}")
    if dest.is_symlink():
        problems.append(f"{dest} is a symlink")
    elif not dest.is_dir():
        problems.append(f"{dest} is missing")
    if problems:
        return {"case_id": case_id, "state_dir": str(dest), "frozen": str(frozen_path), "ok": False,
                "checked": 0, "problems": problems}
    expected = doc.get("files") or {}
    actual = hash_tree(dest)
    for rel, want in sorted(expected.items()):
        got = actual.get(rel)
        if got is None:
            problems.append(f"missing file: {rel}")
        elif got != want:
            problems.append(f"digest mismatch: {rel} expected {want[:16]}… got {got[:16]}…")
    for rel in sorted(set(actual) - set(expected)):
        problems.append(f"unexpected file: {rel}")
    fp = dest / FINGERPRINT_NAME
    if fp.is_file():
        got_fp = read_json(fp).get("fingerprint")
        if doc.get("fingerprint") and got_fp != doc["fingerprint"]:
            problems.append(f"fingerprint.json says {got_fp!r}, freeze manifest says {doc['fingerprint']!r}")
    return {"case_id": case_id, "state_dir": str(dest), "frozen": str(frozen_path),
            "fingerprint": doc.get("fingerprint"), "checked": len(expected),
            "ok": not problems, "problems": problems}


# ---------------------------------------------------------------- running and comparing

def run_solver(case_id: str, case_dir_path: Path, binary: Path, runs_root: Path, label: str,
               map_path: Path, timeout: float) -> dict:
    cmd = [sys.executable, str(YL_RUN), "--case-id", case_id, "--case-dir", str(case_dir_path),
           "--binary", str(binary), "--runs-root", str(runs_root), "--label", label,
           "--timeout", str(timeout), "--dump-state", "--state-map", str(map_path),
           "--expect-status", "COMPLETED"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    run_dir = None
    last = r.stdout.strip().splitlines()[-1] if r.stdout.strip() else ""
    m = re.search(r"->\s+(\S+)\s*$", last)
    if m and Path(m.group(1)).is_dir():
        run_dir = Path(m.group(1))
    else:
        base = runs_root / case_id
        cands = sorted(base.glob(f"*_{label}")) if base.is_dir() else []
        run_dir = cands[-1] if cands else None
    man = None
    if run_dir and (run_dir / "run-manifest.json").is_file():
        man = read_json(run_dir / "run-manifest.json")
    return {"command": cmd, "returncode": r.returncode, "stdout": r.stdout.strip()[-2000:],
            "stderr": r.stderr.strip()[-2000:], "run_dir": str(run_dir) if run_dir else None,
            "manifest": man}


def run_problems(run: dict) -> list[str]:
    man = run.get("manifest")
    if man is None:
        return [f"no run-manifest.json (runner rc={run['returncode']}): "
                f"{(run['stderr'] or run['stdout'])[-300:]}"]
    out = []
    if man.get("status") != "COMPLETED":
        out.append(f"run status {man.get('status')!r} != 'COMPLETED'")
    rc = (man.get("process") or {}).get("returncode")
    if rc != 0:
        out.append(f"solver returncode {rc!r} != 0")
    state = man.get("state") or {}
    if not state:
        out.append("run-manifest has no state block (--dump-state did not take effect)")
    elif not (state.get("normalize") or {}).get("ok"):
        probs = (state.get("normalize") or {}).get("problems") or []
        out.append(f"state.normalize.ok is false ({len(probs)} problem(s)): {probs[:2]}")
    elif not state.get("fingerprint"):
        out.append("state.fingerprint is empty")
    return out


def run_comparator(ref: Path, actual: Path, out_json: Path, map_path: Path) -> dict:
    cmd = [sys.executable, str(YL_STATE_DIFF), str(ref), str(actual), "--map", str(map_path),
           "-o", str(out_json)]
    out_json.parent.mkdir(parents=True, exist_ok=True)
    r = subprocess.run(cmd, capture_output=True, text=True)
    report = read_json(out_json) if out_json.is_file() else None
    return {"command": cmd, "returncode": r.returncode, "text": r.stdout,
            "stderr": r.stderr.strip()[-2000:], "report": report, "report_path": str(out_json)}


def snapshot_field_entries(state_dir: Path, fid: str) -> list[tuple[str, str, dict]]:
    """Every (checkpoint, file, entry) at which `fid` is exported in a snapshot tree."""
    found: list[tuple[str, str, dict]] = []
    if not state_dir.is_dir():
        return found
    for cp_dir in sorted(p for p in state_dir.iterdir() if p.is_dir() and not p.is_symlink()):
        for name in JSON_FILES:
            f = cp_dir / name
            if not f.is_file():
                continue
            try:
                entry = (read_json(f).get("fields") or {}).get(fid)
            except (OSError, ValueError):
                continue
            if entry is not None:
                found.append((cp_dir.name, name, entry))
    return found


def leaves(v):
    if isinstance(v, list):
        for x in v:
            yield from leaves(x)
    else:
        yield v


def nonzero_leaves(dtype: str, values) -> list:
    """Canonical-token zero test: f64 is the 16-hex form, so -0.0 (8000…) is NOT zero."""
    bad = []
    for v in leaves(values):
        if v is None:
            continue
        if dtype == "f64":
            try:
                z = int(str(v), 16) == 0
            except ValueError:
                z = False
        elif dtype == "bool":
            z = v in (False, 0, "0", "false", "F")
        elif isinstance(v, str):
            try:
                z = int(v) == 0
            except ValueError:
                z = False
        else:
            z = v == 0
        if not z:
            bad.append(v)
        if len(bad) >= 4:
            break
    return bad


def differing_leaves(reference_state: Path | None, actual_state: Path, stage: str, fid: str) -> dict:
    """Count the leaves of `fid` that differ between the two snapshot trees at `stage`.

    This is the source of truth for `changed_values`.  The comparator's `count=n/total`
    continuation is NOT parsed: yl_state_diff prints it only when a field has more than one
    leaf (tools/yl_state_diff.py:542), so the three single-leaf probes would have no text to
    read, and a missing line must never be read as zero.  Leaves are compared on the canonical
    representation, exactly as the `exact` rule does, so -0.0 and 0.0 stay distinct."""
    out: dict = {"changed": None, "total": None, "problem": None}
    if reference_state is None:
        out["problem"] = "no frozen baseline to count leaves against"
        return out
    ref = [e for cp, _, e in snapshot_field_entries(reference_state, fid) if cp == stage]
    act = [e for cp, _, e in snapshot_field_entries(actual_state, fid) if cp == stage]
    if not ref or not act:
        out["problem"] = (f"field {fid!r} is not exported at {stage} by the "
                          f"{'baseline' if not ref else 'perturbed run'} snapshot")
        return out
    rl, al = list(leaves(ref[0].get("values"))), list(leaves(act[0].get("values")))
    out["total"] = len(rl)
    if len(rl) != len(al):
        out["problem"] = f"leaf count differs at {stage}/{fid}: baseline {len(rl)}, run {len(al)}"
        return out
    out["changed"] = sum(1 for x, y in zip(rl, al) if x != y)
    return out


def assert_expect_state(exp: dict, comparator: dict, actual_state: Path,
                        reference_state: Path | None = None) -> tuple[list[str], dict]:
    """Assert `[expect_state]` against the comparator's JSON report.  Never against its text.

    The first thing checked is that the probe detected *anything*: a clean comparison
    means the perturbation did not reach the state, which is a failure of the probe and
    is reported as such, never as a pass."""
    problems: list[str] = []
    reference_state = reference_state if reference_state is None else Path(reference_state)
    report = comparator.get("report")
    if report is None:
        return ([f"comparator produced no JSON report (rc={comparator['returncode']}): "
                 f"{comparator.get('stderr', '')[-300:]}"], {})

    findings = report.get("findings") or []
    primaries = [f for f in findings if f.get("kind") == "MISMATCH" and f.get("secondary_of") is None]
    secondaries = [f for f in findings if f.get("kind") == "MISMATCH" and f.get("secondary_of") is not None]
    structs = [f for f in findings if f.get("kind") == "STRUCT"]
    observed = {"exit_code": report.get("exit_code"), "summary": report.get("summary"),
                "primary_count": len(primaries), "secondary_count": len(secondaries),
                "struct_count": len(structs),
                "primary_fields": [f.get("field") for f in primaries],
                "secondary_fields": [f.get("field") for f in secondaries]}

    # --- 1. the probe must have detected something ------------------------------------
    if report.get("passed") or report.get("exit_code") == 0:
        problems.append("PROBE DETECTED NOTHING: the comparator reported PASS "
                        "(the perturbation did not reach the state, or the wrong baseline was used)")
    if not primaries:
        problems.append(f"PROBE DETECTED NOTHING: no primary MISMATCH finding "
                        f"(secondary_of == null), expected {exp['mismatch_count']}")

    # --- 2. exit code and counts ------------------------------------------------------
    if report.get("exit_code") != exp["comparator_exit"]:
        problems.append(f"comparator exit_code {report.get('exit_code')!r} != {exp['comparator_exit']}")
    if comparator["returncode"] != exp["comparator_exit"]:
        problems.append(f"comparator process rc {comparator['returncode']} != {exp['comparator_exit']}")
    if len(primaries) != exp["mismatch_count"]:
        problems.append(f"primary MISMATCH count {len(primaries)} != {exp['mismatch_count']} "
                        f"(fields: {observed['primary_fields']})")
    if exp["comparator_exit"] == 1 and structs:
        problems.append(f"{len(structs)} structural finding(s) on a value-only probe: "
                        f"{[f.get('problem') for f in structs[:3]]}")

    # --- 3. the primary finding, string-exact ------------------------------------------
    if primaries:
        f0 = primaries[0]
        for key in EXPECT_STR:
            got = f0.get(key)
            if got != exp[key]:
                problems.append(f"primary finding {key}={got!r} != {exp[key]!r}")
        # changed_values comes from the snapshot data, never from the finding's text
        lc = differing_leaves(reference_state, actual_state, exp["stage"], exp["field"])
        observed["leaf_count"] = lc
        observed["changed_values"], observed["total_values"] = lc["changed"], lc["total"]
        if lc["problem"]:
            problems.append(f"cannot count changed leaves: {lc['problem']}")
        elif lc["changed"] != exp["changed_values"]:
            problems.append(f"changed values {lc['changed']}/{lc['total']} != {exp['changed_values']}")
        # the printed continuation, when the field has more than one leaf, must agree with it
        m = COUNT_RE.search(f0.get("text") or "")
        observed["count_line"] = m.group(0) if m else None
        if m and lc["changed"] is not None and exp["rule"] == "exact" and (
                int(m.group(1)) != lc["changed"] or int(m.group(2)) != lc["total"]):
            problems.append(f"the comparator reports {m.group(0)} but the snapshots differ in "
                            f"{lc['changed']}/{lc['total']} leaves")

    # --- 4. secondaries: only whitelisted fields, only below the primary ---------------
    allow = set(exp.get("allow_secondary") or [])
    for f in secondaries:
        if f.get("field") not in allow:
            problems.append(f"unexpected secondary MISMATCH on {f.get('field')!r} "
                            f"(secondary_of={f.get('secondary_of')!r}); allow_secondary={sorted(allow)}")
        elif f.get("secondary_of") != exp["field"] and f.get("secondary_of") not in allow:
            problems.append(f"secondary {f.get('field')!r} derives from {f.get('secondary_of')!r}, "
                            f"which is neither the expected field nor whitelisted")

    # --- 5. forbidden fields: absent from the report and still all-zero on disk --------
    forbid = list(exp.get("forbid_fields") or [])
    seen_fields = {f.get("field") for f in findings if f.get("field")}
    observed["forbid_fields"] = {}
    for bad in forbid:
        if bad in seen_fields:
            problems.append(f"forbidden field {bad!r} appears in the comparison report")
        entries = snapshot_field_entries(actual_state, bad)
        # The zero rule is taken from the baseline, not assumed: a forbidden field that the
        # frozen reference exports as all-zero must still be all-zero after the perturbation
        # (R24 -- runtime.dof.fixed is not written until after the model_ready anchor).  A
        # forbidden field that is legitimately non-zero in the baseline is only required to
        # stay out of the report.
        zero_in_ref = {cp for cp, _, e in snapshot_field_entries(reference_state, bad)
                       if not nonzero_leaves(str(e.get("dtype")), e.get("values"))} if reference_state else set()
        rec = {"exported": bool(entries), "exported_at": [cp for cp, _, _ in entries],
               "zero_in_reference": sorted(zero_in_ref),
               "all_zero": True if entries else None}
        observed["forbid_fields"][bad] = rec
        if not entries:
            # unreachable after the load guard; kept so a report can never read `all_zero: true`
            # for a field that was never looked at
            problems.append(f"forbidden field {bad!r} is not exported by this run's snapshot: "
                            f"the check would be vacuous")
            continue
        for cp, fname, entry in entries:
            bad_vals = nonzero_leaves(str(entry.get("dtype")), entry.get("values"))
            if not bad_vals:
                continue
            rec["all_zero"] = False
            if cp in zero_in_ref:
                problems.append(f"forbidden field {bad!r} is all-zero in the frozen baseline but not "
                                f"in this run at {cp}/{fname}: first non-zero value(s) {bad_vals}")
    return problems, observed


# ---------------------------------------------------------------- commands

def cmd_list(args: argparse.Namespace) -> int:
    smap = StateMap.load(args.map)
    probes = load_state_probes(smap)
    print(f"{'id':22s} {'base_case':26s} {'file':7s} {'ln':>4s} {'tok':>4s} field")
    for p in probes:
        d = p["derive"][0]
        print(f"{p['id']:22s} {p['base_case']:26s} {d['file']:7s} {d['line']:4d} {d['field']:4d} "
              f"{p['expect_state']['field']}")
    print(f"{len(probes)} state probe(s)")
    return 0


def cmd_freeze(args: argparse.Namespace) -> int:
    golden_root = resolve_golden_root(args.reference_root)
    doc = freeze(args.case, Path(args.from_run), golden_root)
    dest, frozen_path = frozen_paths(args.case, golden_root)
    print(f"frozen {doc['file_count']} file(s), {doc['total_bytes']} bytes -> {dest}")
    print(f"  fingerprint = {doc['fingerprint']}")
    print(f"  source run  = {doc['provenance']['source_run_id']}")
    print(f"  commit      = {doc['provenance']['source_commit']} "
          f"(dirty={doc['provenance']['source_tree_dirty']})")
    print(f"  binary      = {(doc['provenance']['binary_sha256'] or '')[:16]}…")
    print(f"  manifest    -> {frozen_path}")
    return 0


def cmd_verify(args: argparse.Namespace) -> int:
    golden_root = resolve_golden_root(args.reference_root)
    res = verify(args.case, golden_root)
    print(f"{'PASS' if res['ok'] else 'FAIL'}  {args.case}  files={res['checked']}  {res['state_dir']}")
    for p in res["problems"]:
        print("  " + p)
    return 0 if res["ok"] else 1


def cmd_repeat(args: argparse.Namespace) -> int:
    smap = StateMap.load(args.map)
    golden_root = resolve_golden_root(args.reference_root)
    case_path = case_dir(args.case, golden_root)
    runs_root = yl_probe.check_runs_root(Path(args.runs_root))
    out_path = Path(args.output).resolve() if args.output else (runs_root / f"repeat-state-report-{args.case}.json")
    if out_path.is_relative_to(CASES_DIR.resolve()):
        raise ProbeError(f"-o {out_path} lies inside {CASES_DIR}: refusing to write")
    binary = Path(args.binary).resolve()
    if not binary.is_file():
        raise ProbeError(f"binary not found: {binary}")
    if args.runs < 2:
        raise ProbeError(f"--runs must be >= 2 to compare anything, got {args.runs}")
    binary_sha = sha256_file(binary)

    report = {"schema": 1, "tool": TOOL, "test_id": "S01", "case_id": args.case,
              "generated_at": now(), "binary": str(binary), "binary_sha256": binary_sha,
              "build_profile": None, "threads": None, "map": smap.ref(),
              "runs_root": str(runs_root), "runs": [], "pairs": [], "problems": []}
    fingerprints: list[str] = []
    state_dirs: list[Path] = []
    for i in range(1, args.runs + 1):
        label = f"s01r{i}"
        run = run_solver(args.case, case_path, binary, runs_root, label, smap.path, args.timeout)
        probs = run_problems(run)
        man = run.get("manifest") or {}
        state = man.get("state") or {}
        got_sha = (man.get("binary") or {}).get("sha256")
        if got_sha and got_sha != binary_sha:
            probs.append(f"run used binary {got_sha[:16]}… but --binary hashes to {binary_sha[:16]}…: "
                         f"fingerprints are only comparable within one binary (R26)")
        entry = {"label": label, "run_id": Path(run["run_dir"]).name if run["run_dir"] else None,
                 "run_dir": run["run_dir"], "status": man.get("status"),
                 "returncode": (man.get("process") or {}).get("returncode"),
                 "wall_seconds": (man.get("process") or {}).get("wall_seconds"),
                 "max_rss_kib": (man.get("process") or {}).get("max_rss_kib"),
                 "binary_sha256": got_sha,
                 "flavia_res_sha256": (man.get("required_output") or {}).get("sha256"),
                 "state_fingerprint": state.get("fingerprint"),
                 "state_normalize_ok": bool((state.get("normalize") or {}).get("ok")),
                 "problems": probs}
        report["runs"].append(entry)
        report["problems"].extend(f"{label}: {p}" for p in probs)
        if report["build_profile"] is None:
            report["build_profile"] = (man.get("build_manifest") or {}).get("profile")
            report["threads"] = man.get("threads")
        if not probs:
            fingerprints.append(state.get("fingerprint"))
            state_dirs.append(Path(run["run_dir"]) / STATE_NAME)

    report["all_completed"] = all(r["status"] == "COMPLETED" for r in report["runs"])
    report["all_normalized"] = all(r["state_normalize_ok"] for r in report["runs"])
    report["fingerprint_identical"] = bool(fingerprints) and len(set(fingerprints)) == 1
    report["fingerprint"] = fingerprints[0] if report["fingerprint_identical"] else None
    report["output_sha_identical"] = len({r["flavia_res_sha256"] for r in report["runs"]}) == 1
    if fingerprints and not report["fingerprint_identical"]:
        report["problems"].append(f"state fingerprints differ across runs: {sorted(set(fingerprints))}")

    pairs_dir = runs_root / "repeat-diffs"
    for (i, a), (j, b) in itertools.combinations(list(enumerate(state_dirs, 1)), 2):
        cmp_res = run_comparator(a, b, pairs_dir / f"{args.case}_{i}v{j}.json", smap.path)
        rep = cmp_res.get("report") or {}
        entry = {"a": report["runs"][i - 1]["label"], "b": report["runs"][j - 1]["label"],
                 "exit_code": rep.get("exit_code", cmp_res["returncode"]),
                 "passed": bool(rep.get("passed")), "summary": rep.get("summary"),
                 "report_path": cmp_res["report_path"]}
        report["pairs"].append(entry)
        if not entry["passed"]:
            report["problems"].append(f"pairwise diff {entry['a']} vs {entry['b']} did not PASS "
                                      f"(exit {entry['exit_code']})")
    report["all_pairs_passed"] = bool(report["pairs"]) and all(p["passed"] for p in report["pairs"])
    report["verdict"] = "PASS" if (report["all_completed"] and report["all_normalized"]
                                   and report["fingerprint_identical"] and report["all_pairs_passed"]
                                   and not report["problems"]) else "FAIL"
    write_json(out_path, report)

    print(f"{report['verdict']}  {args.case}  runs={len(report['runs'])}  "
          f"fingerprint={(report['fingerprint'] or 'differ')[:12]}  pairs={len(report['pairs'])}")
    for r in report["runs"]:
        print(f"  {r['label']:8s} {str(r['status']):12s} rc={r['returncode']} "
              f"state={(r['state_fingerprint'] or '-')[:12]} wall={r['wall_seconds']}s")
    for p in report["pairs"]:
        s = p.get("summary") or {}
        print(f"  {p['a']} vs {p['b']}: {'PASS' if p['passed'] else 'FAIL'} "
              f"exit={p['exit_code']} compared={s.get('compared')}")
    for p in report["problems"]:
        print("  ! " + p)
    print(f"  -> {out_path}")
    return 0 if report["verdict"] == "PASS" else 1


def execute_probe(probe: dict, binary: Path, runs_root: Path, diffs_dir: Path, smap: StateMap,
                  golden_root: Path, timeout: float) -> dict:
    pid = probe["id"]
    entry = {"id": pid, "base_case": probe["base_case"], "description": probe["description"],
             "expect_state": probe["expect_state"], "verify": None, "edit": None,
             "materialize": None, "run": None, "comparator": None, "observed": None,
             "status": None, "problems": []}
    case_path = case_dir(probe["base_case"], golden_root)
    frozen_state, _ = frozen_paths(probe["base_case"], golden_root)

    # 1. the baseline must still be exactly what was frozen
    ver = verify(probe["base_case"], golden_root)
    entry["verify"] = {"ok": ver["ok"], "checked": ver["checked"], "problems": ver["problems"],
                       "fingerprint": ver.get("fingerprint")}
    if not ver["ok"]:
        entry["status"] = "ERROR"
        entry["problems"] = [f"frozen baseline verify failed: {p}" for p in ver["problems"]]
        return entry

    d = probe["derive"][0]
    probe_root = runs_root / pid
    try:
        # 2. the token must read as the spec says, before anything is written
        check_original_token(case_path / "legacy", d, probe["original_token"])
        # 3. materialise + apply the single set_field + regenerate input-manifest.json
        entry["materialize"] = yl_probe.materialize(probe, probe_root, runs_root)
        # 4. exactly that one token may have changed
        entry["edit"] = check_single_token_change(case_path / "legacy", probe_root / "case" / "legacy", d)
    except ProbeError as e:
        entry["status"], entry["problems"] = "ERROR", [str(e)]
        return entry

    # 5. run with --dump-state
    run = run_solver(probe["base_case"], probe_root / "case", binary, probe_root / "runs", pid,
                     smap.path, timeout)
    man = run.get("manifest") or {}
    state = man.get("state") or {}
    entry["run"] = {"run_dir": run["run_dir"], "run_id": Path(run["run_dir"]).name if run["run_dir"] else None,
                    "status": man.get("status"), "returncode": (man.get("process") or {}).get("returncode"),
                    "normalize_ok": bool((state.get("normalize") or {}).get("ok")),
                    "fingerprint": state.get("fingerprint"),
                    "runner_returncode": run["returncode"]}
    probs = run_problems(run)
    if probs:
        entry["status"], entry["problems"] = "FAIL", probs
        return entry

    # 6. compare against the frozen baseline and assert
    actual_state = Path(run["run_dir"]) / STATE_NAME
    cmp_res = run_comparator(frozen_state, actual_state, diffs_dir / f"{pid}.json", smap.path)
    text_path = diffs_dir / f"{pid}.txt"
    text_path.parent.mkdir(parents=True, exist_ok=True)
    text_path.write_text(cmp_res["text"] or "", encoding="utf-8")
    entry["comparator"] = {"exit_code": (cmp_res.get("report") or {}).get("exit_code", cmp_res["returncode"]),
                           "process_returncode": cmp_res["returncode"],
                           "summary": (cmp_res.get("report") or {}).get("summary"),
                           "report_path": cmp_res["report_path"], "text_path": str(text_path),
                           "reference": str(frozen_state), "actual": str(actual_state)}
    entry["problems"], entry["observed"] = assert_expect_state(probe["expect_state"], cmp_res,
                                                               actual_state, frozen_state)
    entry["status"] = "PASS" if not entry["problems"] else "FAIL"
    return entry


def cmd_run(args: argparse.Namespace) -> int:
    smap = StateMap.load(args.map)
    golden_root = resolve_golden_root(args.reference_root)
    probes = load_state_probes(smap, args.ids, golden_root=golden_root)
    if not probes:
        raise ProbeError(f"no state probes under {PROBES_DIR}")
    runs_root = yl_probe.check_runs_root(Path(args.runs_root))
    diffs_dir = Path(args.diffs_dir).resolve() if args.diffs_dir else runs_root / "diffs"
    out_path = Path(args.output).resolve() if args.output else runs_root / "state-probe-report.json"
    for p in (diffs_dir, out_path):
        if p.is_relative_to(CASES_DIR.resolve()):
            raise ProbeError(f"{p} lies inside {CASES_DIR}: refusing to write")
    binary = Path(args.binary).resolve()
    if not binary.is_file():
        raise ProbeError(f"binary not found: {binary}")

    report = {"schema": 1, "tool": TOOL, "test_id": "S03", "generated_at": now(),
              "binary": str(binary), "binary_sha256": sha256_file(binary), "map": smap.ref(),
              "runs_root": str(runs_root), "diffs_dir": str(diffs_dir), "probes": []}
    for p in probes:
        report["probes"].append(execute_probe(p, binary, runs_root, diffs_dir, smap, golden_root, args.timeout))
    counts: dict[str, int] = {}
    for e in report["probes"]:
        counts[e["status"]] = counts.get(e["status"], 0) + 1
    report["summary"] = counts
    write_json(out_path, report)

    print(f"{'id':22s} {'result':8s} {'exit':>4s} {'mis':>4s} field / problem")
    for e in report["probes"]:
        c = e.get("comparator") or {}
        obs = e.get("observed") or {}
        detail = "; ".join(e["problems"]) if e["problems"] else (e["expect_state"]["field"])
        print(f"{e['id']:22s} {e['status']:8s} {str(c.get('exit_code', '-')):>4s} "
              f"{str(obs.get('primary_count', '-')):>4s} {detail[:100]}")
    print(f"summary: {counts}  -> {out_path}")
    return 0 if all(e["status"] == "PASS" for e in report["probes"]) else 1


# ---------------------------------------------------------------- self-test

def _fixture_map(path: Path) -> None:
    """A minimal but real field map: yl_state_map.load_map is tomllib.loads, and both
    yl_state_diff and this tool index the same vocabulary, so a fixture map exercises
    the production code paths without needing the solver."""
    path.write_text('''# generated by yl_state_probe.py --selftest
version = 1
float_format = "hex"
reader_inventory = "(selftest)"

[[checkpoint]]
id = "model_ready"
order = 1
covered = true
snapshot_files = ["control.json", "mesh.sha256", "dof.sha256", "groups.json", "materials.json",
                  "constraints.sha256", "loads.sha256", "steps.json", "numerics.json"]

[[field]]
id = "materials.E"
checkpoint = "model_ready"
legacy_symbol = "materials.props%mechanical%solid%e"
source = ["MAT.elastic"]
consumers = ["stiff_u"]
shape = ["nmats"]
dtype = "f64"
unit = "Pa"
owner = "ProblemState.materials[].E"
index_by = "materials[].id"
snapshot_file = "materials.json"
determinism = "deterministic"
compare = { rule = "exact" }

[[field]]
id = "runtime.material.dmatx"
checkpoint = "model_ready"
legacy_symbol = "global_var.element%field%dmatx"
source = ["MAT.elastic"]
consumers = ["stiff_u"]
derived_from = ["materials.E"]
shape = ["nmats"]
dtype = "f64"
unit = "Pa"
owner = "RuntimeState.material.dmatx"
index_by = "materials[].id"
snapshot_file = "materials.json"
determinism = "deterministic"
compare = { rule = "exact" }

[[field]]
id = "runtime.dof.fixed"
checkpoint = "model_ready"
legacy_symbol = "prescribed.prescrib%ifpre"
source = ["PRE.prescrib_set"]
consumers = ["solve"]
shape = ["nnodes"]
dtype = "i32"
unit = "1"
owner = "RuntimeState.dof.fixed"
index_by = "mesh.nodes[].id"
snapshot_file = "dof.sha256"
determinism = "deterministic"
compare = { rule = "exact" }

[[field]]
id = "control.run.scratch"
checkpoint = "model_ready"
legacy_symbol = "global_var.deltafi"
source = ["COR.node_coordinates"]
consumers = ["solve"]
shape = ["nnodes"]
dtype = "f64"
unit = "1"
owner = "not_migrated"
index_by = "component"
emit = "none"
snapshot_file = "control.json"
determinism = "uninitialized"
compare = { rule = "ignore", reason = "solver scratch, never initialized on this path" }

[[field]]
id = "mesh.nodes.id"
checkpoint = "model_ready"
legacy_symbol = "global_var.lnods"
source = ["COR.node_coordinates"]
consumers = ["stiff_u"]
shape = ["nnodes"]
dtype = "i32"
unit = "1"
owner = "ProblemState.mesh.nodes[].id"
index_by = "component"
snapshot_file = "mesh.sha256"
determinism = "deterministic"
compare = { rule = "exact" }
''', encoding="utf-8")


def _hexf(x: float) -> str:
    import struct
    return struct.pack(">d", x).hex().upper()


def _fixture_tree(root: Path, e_values: list[float], fixed: list[int],
                  dmatx: list[float] | None = None) -> None:
    """Write a normalized snapshot tree via yl_state's own renderer, so the sidecar
    digests and fingerprint.json are produced exactly the way a real run's are."""
    cp = "model_ready"
    ids = [1, 2]

    def env(name: str, fields: dict) -> dict:
        return {"schema": yl_state.SCHEMA, "checkpoint": cp, "file": name,
                "float_format": yl_state.FLOAT_FORMAT, "map_sha256": "selftest", "fields": fields}

    files = {name: env(name, {}) for name in JSON_FILES}
    files["materials.json"]["fields"] = {
        "materials.E": {"dtype": "f64", "shape": [len(e_values)], "index_by": "materials[].id",
                        "ids": ids[:len(e_values)], "values": [_hexf(v) for v in e_values]},
        "runtime.material.dmatx": {"dtype": "f64", "shape": [len(e_values)], "index_by": "materials[].id",
                                   "ids": ids[:len(e_values)],
                                   "values": [_hexf(v) for v in (dmatx or [1.0, 2.0])[:len(e_values)]]},
    }
    files["dof.json"]["fields"] = {
        "runtime.dof.fixed": {"dtype": "i32", "shape": [len(fixed)], "index_by": "mesh.nodes[].id",
                              "ids": list(range(1, len(fixed) + 1)), "values": list(fixed)},
    }
    files["mesh.json"]["fields"] = {
        "mesh.nodes.id": {"dtype": "i32", "shape": [2], "index_by": "component", "values": [1, 2]},
    }
    blobs = yl_state.render_tree({cp: files})
    fp, per = yl_state.fingerprint_of(blobs)
    for rel, body in blobs.items():
        p = root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(body)
    manifest = {"schema": yl_state.SCHEMA, "normalizer": yl_state.NORMALIZER,
                "map": {"path": "selftest", "sha256": "selftest"}, "checkpoints": per, "fingerprint": fp}
    (root / FINGERPRINT_NAME).write_bytes((yl_state.dumps(manifest) + "\n").encode("utf-8"))


def _fixture_run_dir(root: Path, case_id: str, case_path: Path, state_src: Path) -> Path:
    run_dir = root
    run_dir.mkdir(parents=True, exist_ok=True)
    shutil.copytree(state_src, run_dir / STATE_NAME, dirs_exist_ok=True)
    fp = read_json(run_dir / STATE_NAME / FINGERPRINT_NAME)
    write_json(run_dir / "run-manifest.json", {
        "manifest_version": 1, "case_id": case_id, "case_dir": str(case_path), "status": "COMPLETED",
        "binary": {"path": "/selftest/hstar", "sha256": "0" * 64},
        "build_manifest": {"path": str(root / "build-manifest.json"), "profile": "release",
                           "binary_sha256": "0" * 64},
        "process": {"returncode": 0, "wall_seconds": 0.01, "max_rss_kib": 1024},
        "required_output": {"sha256": "1" * 64},
        "threads": {"OMP_NUM_THREADS": "1"},
        "state": {"requested": True, "normalize": {"ok": True, "problems": []},
                  "fingerprint": fp["fingerprint"], "map": {"path": "selftest", "sha256": "selftest"}},
    })
    write_json(root / "build-manifest.json", {"profile": "release", "binary": {"sha256": "0" * 64}})
    return run_dir


def _spec(tmp: Path, pid: str, exp: dict, *, base="static_2d.fixture", original="7*0.",
          derive=None, extra="") -> Path:
    d = derive or {"op": "set_field", "file": "1.pre", "line": 2, "field": 1, "value": "5.0e-4,6*0."}
    body = [f'schema = 1', f'id = "{pid}"', f'base_case = "{base}"',
            'description = "selftest fixture"', f'original_token = "{original}"', extra,
            "[[derive]]", f'op = "{d["op"]}"', f'file = "{d["file"]}"',
            f'line = {d["line"]}', f'field = {d["field"]}', f'value = "{d["value"]}"',
            "[expect_state]"]
    for k, v in exp.items():
        body.append(f"{k} = {json.dumps(v)}")
    p = tmp / pid / "probe.toml"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text("\n".join(body) + "\n", encoding="utf-8")
    return p


BASE_EXPECT = {"comparator_exit": 1, "mismatch_count": 1, "stage": "model_ready",
               "field": "materials.E", "path": "materials[1].E", "rule": "exact",
               "expected": "1.5e+10(420BF08EB0000000)", "actual": "1.7e+10(420FAA3B50000000)",
               "changed_values": 1, "allow_secondary": [], "forbid_fields": ["runtime.dof.fixed"]}


def selftest() -> int:
    results: list[tuple[bool, str, str]] = []

    def check(ok: bool, name: str, detail: str = "") -> None:
        results.append((bool(ok), name, detail))

    def expect_error(name: str, needle: str, fn) -> None:
        try:
            fn()
        except ProbeError as e:
            check(needle in str(e), name, f"{'' if needle in str(e) else 'wrong error: '}{e}")
        except Exception as e:  # noqa: BLE001
            check(False, name, f"unexpected {type(e).__name__}: {e}")
        else:
            check(False, name, "no error raised")

    tmp = Path(tempfile.mkdtemp(prefix="yl_state_probe_selftest."))
    try:
        map_path = tmp / "map.toml"
        _fixture_map(map_path)
        smap = StateMap.load(map_path)
        case_id = "static_2d.fixture"
        golden_root = tmp / "golden"
        case_path = golden_root / "static_2d" / "fixture"
        (case_path / "legacy").mkdir(parents=True)
        (case_path / "legacy" / "1.pre").write_text("head\n 7*0. 1.0\n", encoding="latin-1")
        (case_path / "observables.toml").write_text(
            '[source]\nfile = "1.flavia.res"\nexpected_node_count = 2\n', encoding="utf-8")
        write_json(case_path / "input-manifest.json", {"files": [{"path": "1.pre", "sha256": "ab" * 32}]})

        ref_tree = tmp / "ref-state"
        _fixture_tree(ref_tree, [1.5e10, 1.5e10], [0, 0, 0])
        run_dir = _fixture_run_dir(tmp / "run1", case_id, case_path, ref_tree)

        # --- freeze ------------------------------------------------------------------
        doc = freeze(case_id, run_dir, golden_root)
        dest, frozen_path = frozen_paths(case_id, golden_root)
        check(dest.is_dir() and frozen_path.is_file() and doc["file_count"] == 14,
              "freeze writes the tree and frozen.json", f"files={doc['file_count']}")
        prov = doc["provenance"]
        check(all(prov.get(k) for k in ("binary_sha256", "build_manifest_sha256", "normalizer",
                                        "source_run_id", "input_manifest_sha256"))
              and prov["input_files"] and "source_commit" in prov,
              "frozen.json records provenance", ", ".join(k for k in ("binary_sha256", "build_manifest_sha256",
                                                                      "normalizer", "source_run_id",
                                                                      "input_manifest_sha256") if not prov.get(k)))
        expect_error("freeze onto an existing destination is refused", "already exists",
                     lambda: freeze(case_id, run_dir, golden_root))
        (tmp / "elsewhere").mkdir()
        link_case = golden_root / "static_2d" / "linked"
        (link_case / "legacy").mkdir(parents=True)
        (link_case / "observables.toml").write_text('[source]\nexpected_node_count = 2\n', encoding="utf-8")
        (link_case / REFERENCE_NAME).mkdir()
        (link_case / REFERENCE_NAME / STATE_NAME).symlink_to(tmp / "elsewhere")
        expect_error("freeze onto a symlinked destination is refused", "already exists",
                     lambda: freeze("static_2d.linked", run_dir, golden_root))
        wrong_case = golden_root / "static_2d" / "wrongsize"
        (wrong_case / "legacy").mkdir(parents=True)
        (wrong_case / "observables.toml").write_text(
            '[source]\nexpected_node_count = 5\nexpected_element_count = 4\n', encoding="utf-8")
        # the attack: a hand-edited manifest that claims the tree belongs to another case
        forged = _fixture_run_dir(tmp / "forged", "static_2d.wrongsize", wrong_case, ref_tree)
        fman = read_json(forged / "run-manifest.json")
        fman["case_id"] = "static_2d.wrongsize"
        write_json(forged / "run-manifest.json", fman)
        expect_error("a forged manifest cannot file a tree under the wrong case",
                     "does not belong to static_2d.wrongsize",
                     lambda: freeze("static_2d.wrongsize", forged, golden_root))
        check(not (wrong_case / REFERENCE_NAME / STATE_NAME).exists(),
              "the refused freeze wrote nothing")
        no_obs = golden_root / "static_2d" / "noobs"
        (no_obs / "legacy").mkdir(parents=True)
        forged2 = _fixture_run_dir(tmp / "forged2", "static_2d.noobs", no_obs, ref_tree)
        f2 = read_json(forged2 / "run-manifest.json")
        f2["case_id"] = "static_2d.noobs"
        write_json(forged2 / "run-manifest.json", f2)
        expect_error("freezing into a case with no registered counts is refused", "is missing",
                     lambda: freeze("static_2d.noobs", forged2, golden_root))
        check(doc["case_identity"]["nodes"] == 2 and doc["case_identity"]["readings_checked"] >= 1,
              "frozen.json records the identity reading that was checked",
              str(doc.get("case_identity")))
        expect_error("--reference-root inside cases/ is refused", "overlaps",
                     lambda: resolve_golden_root(str(GOLDEN_DIR)))
        expect_error("a path-escaping case id is refused", "case id",
                     lambda: frozen_paths("static_2d./..", golden_root))
        expect_error("--runs-root inside cases/ is refused", "overlaps",
                     lambda: yl_probe.check_runs_root(CASES_DIR / "probes" / "x"))

        # --- verify ------------------------------------------------------------------
        v = verify(case_id, golden_root)
        check(v["ok"] and v["checked"] == 14, "verify passes on the frozen tree", "; ".join(v["problems"]))
        victim = dest / "model_ready" / "materials.json"
        keep = victim.read_bytes()
        victim.write_bytes(keep.replace(b'"schema"', b'"schemA"'))
        check(not verify(case_id, golden_root)["ok"], "verify fails on a modified file")
        victim.write_bytes(keep)
        (dest / "model_ready" / "intruder.json").write_text("{}", encoding="utf-8")
        v2 = verify(case_id, golden_root)
        check(not v2["ok"] and any("unexpected file" in p for p in v2["problems"]),
              "verify fails on an extra file", "; ".join(v2["problems"])[:80])
        (dest / "model_ready" / "intruder.json").unlink()
        gone = dest / "model_ready" / "numerics.json"
        body = gone.read_bytes()
        gone.unlink()
        v3 = verify(case_id, golden_root)
        check(not v3["ok"] and any("missing file" in p for p in v3["problems"]),
              "verify fails on a missing file", "; ".join(v3["problems"])[:80])
        gone.write_bytes(body)
        check(verify(case_id, golden_root)["ok"], "verify passes again once restored")

        # --- spec loading guards -----------------------------------------------------
        expect_error("allow_secondary outside the derived_from closure fails at load", "does not derive from",
                     lambda: load_state_probe(_spec(tmp / "specs", "S_bad_secondary",
                                                    {**BASE_EXPECT, "allow_secondary": ["mesh.nodes.id"]}), smap))
        p_ok = load_state_probe(_spec(tmp / "specs", "S_ok_secondary",
                                      {**BASE_EXPECT, "allow_secondary": ["runtime.material.dmatx"]}), smap)
        check(p_ok["expect_state"]["allow_secondary"] == ["runtime.material.dmatx"],
              "a real derived_from descendant is accepted as allow_secondary")
        expect_error("a never-exported forbid_fields entry fails at load", "would assert nothing",
                     lambda: load_state_probe(_spec(tmp / "specs", "S_vacuous",
                                                    {**BASE_EXPECT, "forbid_fields": ["control.run.scratch"]}), smap))
        # the same guard, driven by the frozen baseline rather than the map: a field the tree
        # does not carry cannot be caught either
        strip_case = golden_root / "static_2d" / "stripped"
        (strip_case / "legacy").mkdir(parents=True)
        (strip_case / "observables.toml").write_text('[source]\nexpected_node_count = 2\n', encoding="utf-8")
        shutil.copytree(dest, strip_case / REFERENCE_NAME / STATE_NAME)
        dof_json = strip_case / REFERENCE_NAME / STATE_NAME / "model_ready" / "dof.json"
        stripped = read_json(dof_json)
        stripped["fields"].pop("runtime.dof.fixed")
        dof_json.write_bytes((yl_state.dumps(stripped) + "\n").encode("utf-8"))
        expect_error("a forbid_fields entry absent from the frozen baseline fails at load",
                     "absent from the frozen baseline snapshot",
                     lambda: load_state_probe(_spec(tmp / "specs", "S_absent", BASE_EXPECT,
                                                    base="static_2d.stripped"), smap, golden_root))
        p_present = load_state_probe(_spec(tmp / "specs", "S_present", BASE_EXPECT), smap, golden_root)
        check(p_present["expect_state"]["forbid_fields"] == ["runtime.dof.fixed"],
              "a forbid_fields entry the baseline does carry is accepted")
        expect_error("a forbid_fields typo fails at load", "is not a field of",
                     lambda: load_state_probe(_spec(tmp / "specs", "S_bad_forbid",
                                                    {**BASE_EXPECT, "forbid_fields": ["runtime.dof.fixedd"]}), smap))
        expect_error("mismatch_count = 0 is refused", "a probe that detects nothing is a failed probe",
                     lambda: load_state_probe(_spec(tmp / "specs", "S_zero", {**BASE_EXPECT, "mismatch_count": 0}), smap))
        expect_error("a no-op set_field is refused at load", "null perturbation",
                     lambda: load_state_probe(_spec(tmp / "specs", "S_noop", BASE_EXPECT,
                                                    derive={"op": "set_field", "file": "1.pre", "line": 2,
                                                            "field": 1, "value": "7*0."}), smap))
        expect_error("two derives are refused", "exactly one derive",
                     lambda: load_state_probe(_spec(tmp / "specs", "S_two", BASE_EXPECT,
                                                    extra='[[derive]]\nop = "set_field"\nfile = "1.pre"\n'
                                                          'line = 2\nfield = 1\nvalue = "9."\n'), smap))
        expect_error("a path-escaping derive file is refused", "bare file name",
                     lambda: load_state_probe(_spec(tmp / "specs", "S_escape", BASE_EXPECT,
                                                    derive={"op": "set_field", "file": "../1.pre", "line": 2,
                                                            "field": 1, "value": "9."}), smap))
        expect_error("a non set_field derive is refused", "must be set_field",
                     lambda: load_state_probe(_spec(tmp / "specs", "S_op", BASE_EXPECT,
                                                    derive={"op": "delete_file", "file": "1.pre", "line": 2,
                                                            "field": 1, "value": "9."}), smap))

        # --- original_token / single-token guards ------------------------------------
        good = {"op": "set_field", "file": "1.pre", "line": 2, "field": 1, "value": "5.0e-4,6*0."}
        check(check_original_token(case_path / "legacy", good, "7*0.") == "7*0.",
              "original_token matches the golden deck")
        expect_error("a stale original_token fails before running", "original_token stale",
                     lambda: check_original_token(case_path / "legacy", good, "6*0."))
        expect_error("a token index past the end of the line fails", "token(s), field=",
                     lambda: check_original_token(case_path / "legacy",
                                                 {**good, "field": 9}, "7*0."))
        edited = tmp / "edited" / "legacy"
        edited.mkdir(parents=True)
        shutil.copy2(case_path / "legacy" / "1.pre", edited / "1.pre")
        yl_probe.apply_derive(edited, good)
        info = check_single_token_change(case_path / "legacy", edited, good)
        check(info["tokens_changed"] == [1] and info["new_token"] == "5.0e-4,6*0.",
              "exactly one token changed after the edit", str(info))
        untouched = tmp / "untouched" / "legacy"
        untouched.mkdir(parents=True)
        shutil.copy2(case_path / "legacy" / "1.pre", untouched / "1.pre")
        expect_error("an unchanged deck is refused as a null perturbation", "null perturbation",
                     lambda: check_single_token_change(case_path / "legacy", untouched, good))
        twotok = tmp / "twotok" / "legacy"
        twotok.mkdir(parents=True)
        shutil.copy2(case_path / "legacy" / "1.pre", twotok / "1.pre")
        yl_probe.apply_derive(twotok, good)
        yl_probe.apply_derive(twotok, {**good, "field": 2, "value": "2.0"})
        expect_error("a second changed token is refused", "changed token(s) [1, 2]",
                     lambda: check_single_token_change(case_path / "legacy", twotok, good))

        # --- the comparator contract, end to end on real snapshot trees ---------------
        spec_ok = load_state_probe(_spec(tmp / "specs", "S_live", BASE_EXPECT), smap)
        exp = spec_ok["expect_state"]

        # (a) NULL PERTURBATION: an unchanged snapshot must be reported as a probe FAILURE
        null_tree = tmp / "null-state"
        _fixture_tree(null_tree, [1.5e10, 1.5e10], [0, 0, 0])
        c_null = run_comparator(dest, null_tree, tmp / "out" / "null.json", map_path)
        probs_null, obs_null = assert_expect_state(exp, c_null, null_tree, dest)
        check(c_null["returncode"] == 0 and (c_null["report"] or {}).get("passed") is True,
              "null perturbation: the comparator itself reports PASS", f"rc={c_null['returncode']}")
        check(bool(probs_null) and any("PROBE DETECTED NOTHING" in p for p in probs_null),
              "NULL PERTURBATION is reported as a probe FAILURE, never a pass",
              "; ".join(probs_null)[:160] or "no problem raised")

        # (b) the positive path, so (a) is not vacuous
        hit_tree = tmp / "hit-state"
        _fixture_tree(hit_tree, [1.7e10, 1.5e10], [0, 0, 0])
        c_hit = run_comparator(dest, hit_tree, tmp / "out" / "hit.json", map_path)
        probs_hit, obs_hit = assert_expect_state(exp, c_hit, hit_tree, dest)
        check(not probs_hit, "a real single-field perturbation asserts PASS",
              "; ".join(probs_hit)[:200])
        check(obs_hit.get("changed_values") == 1 and obs_hit.get("total_values") == 2
              and obs_hit.get("count_line") == "count=1/2",
              "changed_values is counted from the snapshots and agrees with the printed count",
              str(obs_hit.get("leaf_count")))

        # a single-leaf field prints no count= continuation at all; changed_values must still be 1
        one_ref, one_act = tmp / "one-ref", tmp / "one-act"
        _fixture_tree(one_ref, [1.5e10], [0, 0, 0])
        _fixture_tree(one_act, [1.7e10], [0, 0, 0])
        c_one = run_comparator(one_ref, one_act, tmp / "out" / "one.json", map_path)
        probs_one, obs_one = assert_expect_state(exp, c_one, one_act, one_ref)
        check(not probs_one and obs_one["count_line"] is None and obs_one["changed_values"] == 1
              and obs_one["total_values"] == 1,
              "a single-leaf field prints no count= line and still asserts changed_values = 1",
              f"{obs_one.get('leaf_count')} {'; '.join(probs_one)[:120]}")
        probs_one_bad, _ = assert_expect_state({**exp, "changed_values": 2}, c_one, one_act, one_ref)
        check(any("changed values 1/1 != 2" in p for p in probs_one_bad),
              "a wrong changed_values on a single-leaf field is caught, not silently accepted",
              "; ".join(probs_one_bad)[:120])

        # (c) a wrong expectation must fail, string-exact
        probs_wrong, _ = assert_expect_state({**exp, "path": "materials[2].E"}, c_hit, hit_tree, dest)
        check(any("primary finding path=" in p for p in probs_wrong),
              "a wrong path is caught string-exact", "; ".join(probs_wrong)[:120])

        # (d) an unexpected secondary is caught; whitelisting it makes it pass
        sec_tree = tmp / "sec-state"
        _fixture_tree(sec_tree, [1.7e10, 1.5e10], [0, 0, 0])
        d_json = sec_tree / "model_ready" / "materials.json"
        obj = read_json(d_json)
        obj["fields"]["runtime.material.dmatx"]["values"][1] = _hexf(9.9e9)
        d_json.write_bytes((yl_state.dumps(obj) + "\n").encode("utf-8"))
        c_sec = run_comparator(dest, sec_tree, tmp / "out" / "sec.json", map_path)
        probs_sec, _ = assert_expect_state(exp, c_sec, sec_tree, dest)
        check(any("unexpected secondary MISMATCH" in p for p in probs_sec),
              "an unlisted secondary MISMATCH fails the probe", "; ".join(probs_sec)[:160])
        probs_sec_ok, _ = assert_expect_state({**exp, "allow_secondary": ["runtime.material.dmatx"]},
                                              c_sec, sec_tree, dest)
        check(not probs_sec_ok, "the same secondary passes once whitelisted", "; ".join(probs_sec_ok)[:160])

        # (e) forbid_fields: caught both as a finding and as a non-zero export
        fz_tree = tmp / "fixed-state"
        _fixture_tree(fz_tree, [1.7e10, 1.5e10], [0, 1, 0])
        c_fz = run_comparator(dest, fz_tree, tmp / "out" / "fz.json", map_path)
        probs_fz, obs_fz = assert_expect_state(exp, c_fz, fz_tree, dest)
        check(any("appears in the comparison report" in p for p in probs_fz),
              "a forbidden field that shows up in the report fails the probe", "; ".join(probs_fz)[:160])
        check(any("all-zero in the frozen baseline but not" in p for p in probs_fz),
              "a forbidden field that was zero in the baseline and is not now fails the probe",
              "; ".join(probs_fz)[:160])
        # the same non-zero value is tolerated when the baseline is itself non-zero there
        nz_ref = tmp / "nz-ref"
        _fixture_tree(nz_ref, [1.5e10, 1.5e10], [7, 7, 7])
        nz_act = tmp / "nz-act"
        _fixture_tree(nz_act, [1.7e10, 1.5e10], [7, 7, 7])
        c_nz = run_comparator(nz_ref, nz_act, tmp / "out" / "nz.json", map_path)
        probs_nz, obs_nz = assert_expect_state(exp, c_nz, nz_act, nz_ref)
        check(not probs_nz and obs_nz["forbid_fields"]["runtime.dof.fixed"]["zero_in_reference"] == [],
              "a legitimately non-zero forbidden field is only required to stay out of the report",
              "; ".join(probs_nz)[:160])
        check(obs_hit["forbid_fields"]["runtime.dof.fixed"]["all_zero"] and
              obs_hit["forbid_fields"]["runtime.dof.fixed"]["exported_at"] == ["model_ready"],
              "an all-zero forbidden field is recorded as exported and clean")

        # (f) a missing comparator report is a failure, not a pass
        probs_none, _ = assert_expect_state(exp, {"returncode": 3, "report": None, "stderr": "boom"}, hit_tree, dest)
        check(bool(probs_none), "no comparator report is a failure")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    width = max(len(n) for _, n, _ in results)
    for ok, name, detail in results:
        print(f"  {'ok  ' if ok else 'FAIL'} {name:{width}s}" + (f"   {detail}" if detail and not ok else ""))
    bad = sum(1 for ok, _, _ in results if not ok)
    print(f"{'PASS' if not bad else 'FAIL'}: {len(results) - bad}/{len(results)} self-test checks")
    return 0 if not bad else 1


# ---------------------------------------------------------------- CLI

def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if "--selftest" in argv:
        if len(argv) != 1:
            print("error: --selftest takes no other arguments", file=sys.stderr)
            return 2
        return selftest()

    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--selftest", action="store_true", help="run the guard-rail self-test and exit")
    sub = ap.add_subparsers(dest="cmd", required=True)

    def common(p, *, ref_root=True):
        p.add_argument("--map", default=str(MAP_DEFAULT), help="M2-02 field map")
        if ref_root:
            p.add_argument("--reference-root", help=argparse.SUPPRESS)  # self-test fixture override

    p = sub.add_parser("list", help="list the state probe specs")
    common(p, ref_root=False)
    p.set_defaults(fn=cmd_list)

    p = sub.add_parser("freeze", help="copy a run's normalized state into the case's reference/state")
    p.add_argument("--case", required=True, metavar="CASE_ID")
    p.add_argument("--from", dest="from_run", required=True, metavar="RUN_DIR")
    common(p)
    p.set_defaults(fn=cmd_freeze)

    p = sub.add_parser("verify", help="re-hash the frozen tree against reference/frozen.json")
    p.add_argument("--case", required=True, metavar="CASE_ID")
    common(p)
    p.set_defaults(fn=cmd_verify)

    p = sub.add_parser("repeat", help="N dump-on runs of one binary; identical fingerprints, pairwise PASS")
    p.add_argument("--case", required=True, metavar="CASE_ID")
    p.add_argument("--binary", required=True)
    p.add_argument("--runs", type=int, default=3)
    p.add_argument("--runs-root", default=str(REPO_ROOT / "runs" / "state-repeat"))
    p.add_argument("--timeout", type=float, default=600.0)
    p.add_argument("-o", "--output")
    common(p)
    p.set_defaults(fn=cmd_repeat)

    p = sub.add_parser("run", help="materialise, perturb, run, compare and assert the state probes")
    p.add_argument("--ids", nargs="+", help="probe ids or unique prefixes (default: all)")
    p.add_argument("--binary", default=str(REPO_ROOT / "build" / "release" / "hstar"))
    p.add_argument("--runs-root", default=str(REPO_ROOT / "runs" / "state-probes"))
    p.add_argument("--diffs-dir", help="where the full comparator text is archived (default <runs-root>/diffs)")
    p.add_argument("--timeout", type=float, default=600.0)
    p.add_argument("-o", "--output")
    common(p)
    p.set_defaults(fn=cmd_run)

    args = ap.parse_args(argv)
    try:
        return args.fn(args)
    except ProbeError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
