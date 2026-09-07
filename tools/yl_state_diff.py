#!/usr/bin/env python3
"""Compare two normalized state snapshots of the legacy YL solver (M2-02).

Structure first, values second (same house rule as tools/yl_compare.py): a snapshot
tree is the layout written by `tools/yl_state.py normalize` -- one directory per
checkpoint holding the nine §5 snapshot files (control.json, mesh.json+mesh.sha256,
dof.json+dof.sha256, groups.json, materials.json, constraints.json+constraints.sha256,
loads.json+loads.sha256, steps.json, numerics.json) plus a top-level fingerprint.json.

Passes
  structure  checkpoint set, unparsable/absent files, sidecar digest, per-field
             missing/extra, dtype, rank, shape, index_by, duplicate ids, id-set
             equality, id/value length agreement, non-finite floats.  Every finding
             is collected (no early stop); any finding on a field suppresses the
             value pass for that field.
  value      per docs/m2/state-field-map.toml `compare.rule`:
               exact    bitwise on the canonical representation (16-hex f64 token,
                        decimal int, latin-1 text) -- so -0.0 != 0.0 and NaN
                        payloads stay visible; floats are never decoded to compare
               abs_tol / rel_tol   |a-e| <= atol + rtol*|e| on decoded f64, worst
                        normalized violation reported
               hash     stored sha256 vs stored sha256, both recomputed from the
                        canonical bytes (a stored digest that disagrees with its own
                        values is a STRUCT digest finding); --expand-hash prints the
                        first differing index
               ignore   never compared; listed as SKIPPED only under --strict

Message grammar (one line per finding, continuation lines indented by two spaces)
  STRUCT stage=<cp> [file=<f>] [field=<id>] problem=<kind> [path=<p>] [expected=<..>]
         [actual=<..>] [count=<n>] [detail=<..>]
  MISMATCH stage=<cp> field=<id> path=<object.path[index].attr> rule=<rule>
         expected=<..> actual=<..> unit=<u> source=<reader id> legacy=<symbol>
  SKIPPED stage=<cp> field=<id> rule=ignore reason=<..>
  continuation: `  diff=.. atol=.. rtol=.. worst_path=.. count=n/total`,
                `  count=n/total`, `  first_diff=..`, `  secondary_of=<primary id>`

Exit codes
  0 everything compared clean (SKIPPED allowed)   1 value mismatches only
  2 any structural finding                        3 usage / unreadable input / map

Usage
  python3 tools/yl_state_diff.py REF ACTUAL [--map docs/m2/state-field-map.toml]
                                [--strict] [--expand-hash] [-o report.json]
  python3 tools/yl_state_diff.py --selftest [-o report.json]
  python3 tools/yl_state_diff.py --snapshot DIR [--raw-dir RAW] [-o report.json]

Only the Python standard library is used.  The map vocabulary is imported from
tools/yl_state_map.py rather than restated.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from yl_state_map import (COMPARE_RULES, DTYPES, MAP_DEFAULT, REPO_ROOT,  # noqa: E402,F401
                          SNAPSHOT_FILES, load_map)

CANON = dict(sort_keys=True, separators=(",", ":"), ensure_ascii=True)
FINGERPRINT = "fingerprint.json"


# --- small helpers -----------------------------------------------------------------------
def sha256_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def canon_bytes(obj) -> bytes:
    return (json.dumps(obj, **CANON) + "\n").encode("utf-8")


def json_name(snapshot_file: str) -> str:
    """The nine §5 names include four `.sha256` sidecars; the payload is the sibling .json."""
    return snapshot_file[:-len(".sha256")] + ".json" if snapshot_file.endswith(".sha256") else snapshot_file


JSON_FILES = [json_name(n) for n in SNAPSHOT_FILES]
FILE_ORDER = {n: i for i, n in enumerate(JSON_FILES)}


def q(v) -> str:
    """Render one `key=` value; quote when it would otherwise break the one-line grammar."""
    if v is None:
        return ""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (list, tuple)):
        return "[" + ",".join(q(x) for x in v) + "]"
    s = str(v)
    if s == "" or any(c in s for c in ' \t"'):
        return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'
    return s


def kv(*pairs) -> str:
    return " ".join(f"{k}={q(v)}" for k, v in pairs if v is not None)


def f64_of(tok: str) -> float:
    """Decode a 16-hex big-endian IEEE-754 token (the wire/normalized f64 form)."""
    return struct.unpack(">d", bytes.fromhex(tok))[0]


def short_float(x: float) -> str:
    """Shortest round-tripping decimal, scientific form (2.5e+10, nan, inf)."""
    if math.isnan(x):
        return "nan"
    if math.isinf(x):
        return "inf" if x > 0 else "-inf"
    for p in range(0, 18):
        s = f"{x:.{p}e}"
        if float(s) == x:
            # strip trailing zeros in the mantissa: 2.500e+10 -> 2.5e+10
            m, e = s.split("e")
            if "." in m:
                m = m.rstrip("0").rstrip(".")
            return f"{m}e{e}"
    return repr(x)


def show(dtype: str, tok) -> str:
    if dtype == "f64" and isinstance(tok, str):
        try:
            return f"{short_float(f64_of(tok))}({tok.upper()})"
        except (ValueError, struct.error):
            return str(tok)
    return str(tok)


def prod(xs) -> int:
    n = 1
    for x in xs:
        n *= int(x)
    return n


def iter_leaves(v, prefix=()):
    """Yield (index tuple, leaf) walking nested value lists depth first."""
    if isinstance(v, list):
        for i, x in enumerate(v):
            yield from iter_leaves(x, prefix + (i,))
    else:
        yield prefix, v


def hashable(x):
    return tuple(hashable(i) for i in x) if isinstance(x, list) else x


def first_shape_diff(r, a, prefix=()):
    """First position where two nested value trees disagree in structure.

    Returns (index tuple, expected, actual) or None.  This is what makes ragged fields
    (`shape: null`, one variable-length list per key) comparable at all: a group that
    lost an entry, or a flat sequence regrouped across keys, differs here even though the
    flattened leaf sequence may be identical."""
    if isinstance(r, list) != isinstance(a, list):
        return prefix, "list" if isinstance(r, list) else "scalar", "list" if isinstance(a, list) else "scalar"
    if not isinstance(r, list):
        return None
    if len(r) != len(a):
        return prefix, len(r), len(a)
    for i, (x, y) in enumerate(zip(r, a)):
        d = first_shape_diff(x, y, prefix + (i,))
        if d:
            return d
    return None


# --- snapshot model ----------------------------------------------------------------------
class FileData:
    __slots__ = ("name", "obj", "raw", "sidecar", "error")

    def __init__(self, name, obj=None, raw=None, sidecar=None, error=None):
        self.name, self.obj, self.raw, self.sidecar, self.error = name, obj, raw, sidecar, error

    @property
    def fields(self) -> dict:
        return (self.obj or {}).get("fields") or {}


class Snapshot:
    """checkpoint id -> {file name -> FileData}, plus the optional fingerprint document."""

    def __init__(self, label: str):
        self.label = label
        self.cps: dict[str, dict[str, FileData]] = {}
        self.fingerprint: dict | None = None

    def files(self, cp: str) -> dict[str, FileData]:
        return self.cps.get(cp, {})

    def objs(self) -> dict[str, dict[str, dict]]:
        return {cp: {n: copy.deepcopy(f.obj) for n, f in fs.items() if f.obj is not None}
                for cp, fs in self.cps.items()}


def sign_objs(objs: dict[str, dict[str, dict]], label: str = "memory", stale: dict | None = None) -> Snapshot:
    """Serialize in-memory envelopes canonically and attach matching sidecar digests.

    `stale` maps checkpoint -> {file name: digest} for sidecars that must be left unsigned
    (the S02 stale-digest class)."""
    snap = Snapshot(label)
    per_cp = {}
    for cp, files in objs.items():
        snap.cps[cp] = {}
        digests = {}
        for name in sorted(files, key=lambda n: FILE_ORDER.get(n, 99)):
            raw = canon_bytes(files[name])
            dig = sha256_bytes(raw)
            side = (stale or {}).get(cp, {}).get(name, dig)
            snap.cps[cp][name] = FileData(name, files[name], raw, side)
            digests[name] = dig
            digests[name[:-len(".json")] + ".sha256"] = sha256_bytes(
                f"{side}  {name}\n".encode("utf-8"))
        per_cp[cp] = digests
    joined = "".join(f"{cp}/{n}:{h}\n" for cp in sorted(per_cp) for n, h in sorted(per_cp[cp].items()))
    snap.fingerprint = {"schema": 1, "normalizer": "yl_state.py/1", "checkpoints": per_cp,
                        "fingerprint": sha256_bytes(joined.encode("utf-8"))}
    return snap


def load_dir(path: Path, covered: list[str]) -> Snapshot:
    snap = Snapshot(str(path))
    fp = path / FINGERPRINT
    if fp.is_file():
        try:
            snap.fingerprint = json.loads(fp.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            snap.fingerprint = None
    for cp in covered:
        d = path / cp
        if not d.is_dir():
            continue
        files: dict[str, FileData] = {}
        for name in JSON_FILES:
            f = d / name
            if not f.is_file():
                continue
            try:
                raw = f.read_bytes()
            except OSError as e:
                files[name] = FileData(name, error=f"unreadable: {e}")
                continue
            side = None
            sc = d / (name[:-len(".json")] + ".sha256")
            if sc.is_file():
                try:
                    side = sc.read_text(encoding="utf-8").split()[0]
                except (OSError, IndexError):
                    side = ""
            try:
                obj = json.loads(raw.decode("utf-8"))
            except (ValueError, UnicodeDecodeError) as e:
                files[name] = FileData(name, raw=raw, sidecar=side, error=f"JSON: {e}")
                continue
            files[name] = FileData(name, obj, raw, side)
        snap.cps[cp] = files
    return snap


# --- findings ----------------------------------------------------------------------------
class Finding:
    def __init__(self, kind, stage, phase, order, text, extra=None, **rec):
        self.kind, self.stage, self.phase, self.order = kind, stage, phase, order
        self.text, self.extra = text, list(extra or [])
        self.rec = rec
        self.secondary_of = None

    def lines(self) -> list[str]:
        out = [self.text] + ["  " + e for e in self.extra]
        if self.secondary_of:
            out.append(f"  secondary_of={self.secondary_of}")
        return out

    def as_json(self) -> dict:
        d = {"kind": self.kind, "stage": self.stage, "file": None, "field": None, "problem": None,
             "path": None, "rule": None, "expected": None, "actual": None,
             "secondary_of": self.secondary_of, "text": "\n".join(self.lines())}
        d.update(self.rec)
        return d


# --- map indexing ------------------------------------------------------------------------
class MapIndex:
    def __init__(self, doc: dict, path: Path | None = None):
        self.doc = doc
        self.path = path
        self.covered = [c["id"] for c in doc.get("checkpoint", []) if c.get("covered")]
        self.cp_order = {c: i for i, c in enumerate(self.covered)}
        self.fields: dict[str, dict[str, dict]] = {c: {} for c in self.covered}
        self.order: dict[str, dict[str, int]] = {c: {} for c in self.covered}
        for f in doc.get("field", []):
            cp = f["checkpoint"]
            if cp in self.fields:
                self.order[cp][f["id"]] = len(self.fields[cp])
                self.fields[cp][f["id"]] = f
        self.sha256 = sha256_bytes(path.read_bytes()) if path and path.is_file() else None

    def rule(self, cp: str, fid: str) -> str:
        f = self.fields.get(cp, {}).get(fid)
        return (f or {}).get("compare", {}).get("rule", "exact")

    def field(self, cp: str, fid: str) -> dict:
        return self.fields.get(cp, {}).get(fid, {})

    def fidx(self, cp: str, fid: str) -> int:
        return self.order.get(cp, {}).get(fid, 10_000)


# --- path rendering ----------------------------------------------------------------------
def container_of(index_by: str | None) -> str | None:
    if not index_by or index_by == "component":
        return None
    if index_by.endswith("[].id") or index_by.endswith("[].name"):
        return index_by.rsplit("[]", 1)[0]
    return None


def entity_path(fid: str, index_by, ids, i: int, bnodes=None) -> str:
    """Path prefix for entity `i`, without the inner component indices."""
    attr = fid.rsplit(".", 1)[-1]
    if ids is None or i is None or i >= len(ids):
        return fid
    key = ids[i]
    if index_by == "(node,dof)" and isinstance(key, list) and len(key) == 2:
        return f"{fid}[node={key[0]},dof={key[1]}]"
    cont = container_of(index_by)
    if cont is None:
        return f"{fid}[{key}]" if not isinstance(key, list) else f"{fid}[{','.join(map(str, key))}]"
    if isinstance(key, list) and len(key) == 2 and cont.endswith("boundary"):
        node = None
        if bnodes and i < len(bnodes):
            node = bnodes[i]
        inner = f"set={key[0]},rec={key[1]}" + (f",node={node}" if node is not None else "")
        return f"{cont}[{inner}].{attr}"
    if isinstance(key, list):
        return f"{cont}[{','.join(map(str, key))}].{attr}"
    return f"{cont}[{key}].{attr}"


def full_path(fid, index_by, ids, idx: tuple, bnodes=None) -> str:
    if ids is None:
        base, inner = fid, idx
    else:
        base, inner = entity_path(fid, index_by, ids, idx[0] if idx else None, bnodes), idx[1:]
    return base + "".join(f"[{k + 1}]" for k in inner)


# --- comparison --------------------------------------------------------------------------
STRUCT_PROBLEM_KEYS = ("path", "expected", "actual", "count", "detail")


def struct_finding(mi, cp, phase, fileidx, fidx, *, file=None, field=None, problem="",
                   path=None, expected=None, actual=None, count=None, detail=None, extra=None):
    text = "STRUCT " + kv(("stage", cp), ("file", file), ("field", field), ("problem", problem),
                          ("path", path), ("expected", expected), ("actual", actual),
                          ("count", count), ("detail", detail))
    return Finding("STRUCT", cp, phase, (mi.cp_order.get(cp, 99), phase, fileidx, fidx), text,
                   extra=extra, file=file, field=field, problem=problem, path=path,
                   expected=expected, actual=actual, rule=None)


def field_digest(entry: dict) -> str:
    canon = "|".join([str(entry.get("dtype")), json.dumps(entry.get("shape"), **CANON),
                      json.dumps(entry.get("ids"), **CANON), json.dumps(entry.get("values"), **CANON)])
    return sha256_bytes(canon.encode("utf-8"))


def check_field_structure(mi, cp, fname, fid, r, a, findings, fileidx):
    """Return True when the field is structurally clean on both sides."""
    fidx = mi.fidx(cp, fid)

    def add(**kw):
        findings.append(struct_finding(mi, cp, 2, fileidx, fidx, file=fname, field=fid, **kw))

    rd, ad = r.get("dtype"), a.get("dtype")
    if rd != ad:
        add(problem="dtype", expected=rd, actual=ad)
        return False
    rs, as_ = r.get("shape"), a.get("shape")
    if isinstance(rs, list) and isinstance(as_, list) and len(rs) != len(as_):
        add(problem="rank", expected=len(rs), actual=len(as_))
        return False
    if rs != as_:
        add(problem="shape", expected=rs, actual=as_)
        return False
    if r.get("index_by") != a.get("index_by"):
        add(problem="index_by", expected=r.get("index_by"), actual=a.get("index_by"))
        return False
    ids_r, ids_a = r.get("ids"), a.get("ids")
    if (ids_r is None) != (ids_a is None):
        add(problem="index_by", expected="ids" if ids_r is not None else "no ids",
            actual="ids" if ids_a is not None else "no ids")
        return False
    if ids_a is not None:
        seen: dict = {}
        for i, k in enumerate(ids_a):
            h = hashable(k)
            seen[h] = seen.get(h, 0) + 1
        dup = [k for k in ids_a if seen[hashable(k)] > 1]
        if dup:
            first = dup[0]
            add(problem="duplicate_id",
                path=entity_path(fid, a.get("index_by"), [first], 0).rsplit(".", 1)[0]
                if container_of(a.get("index_by")) else f"{fid}[{first}]",
                count=seen[hashable(first)])
            return False
        sr, sa = {hashable(k) for k in ids_r}, {hashable(k) for k in ids_a}
        if sr != sa:
            miss = [k for k in ids_r if hashable(k) not in sa][:5]
            extra = [k for k in ids_a if hashable(k) not in sr][:5]
            add(problem="id_set", expected=miss or None, actual=extra or None,
                detail=f"missing={len(sr - sa)} extra={len(sa - sr)}")
            return False
        for side, ids, vals in (("expected", ids_r, r.get("values")), ("actual", ids_a, a.get("values"))):
            if isinstance(vals, list) and len(vals) != len(ids):
                add(problem="length", expected=len(ids), actual=len(vals),
                    detail=f"{side}: ids/values disagree")
                return False
    # nested structure: dense extents and, crucially, per-key lengths of a ragged field
    d = first_shape_diff(r.get("values"), a.get("values"))
    if d:
        idx, want, got = d
        add(problem="length", path=full_path(fid, a.get("index_by"), ids_a, idx),
            expected=want, actual=got)
        return False
    if isinstance(as_, list) and as_:
        for side, entry in (("expected", r), ("actual", a)):
            n = len(list(iter_leaves(entry.get("values"))))
            if n != prod(as_):
                add(problem="length", expected=prod(as_), actual=n,
                    detail=f"{side}: leaf count disagrees with the declared shape")
                return False
    if a.get("dtype") == "f64":
        for side, entry in (("expected", r), ("actual", a)):
            for idx, tok in iter_leaves(entry.get("values")):
                if not isinstance(tok, str):
                    continue
                try:
                    v = f64_of(tok)
                except (ValueError, struct.error):
                    add(problem="token", path=full_path(fid, entry.get("index_by"), entry.get("ids"), idx),
                        actual=tok, detail=side)
                    return False
                if not math.isfinite(v):
                    add(problem="nonfinite",
                        path=full_path(fid, entry.get("index_by"), entry.get("ids"), idx),
                        **({"actual": short_float(v)} if side == "actual" else
                           {"expected": short_float(v), "detail": "reference"}))
                    return False
    return True


def compare_field_values(mi, cp, fname, fid, r, a, findings, fileidx, opts, bnodes):
    """Value pass for one structurally clean field.  Returns a status string."""
    mf = mi.field(cp, fid)
    rule = (mf.get("compare") or {}).get("rule", "exact")
    fidx = mi.fidx(cp, fid)
    dtype = a.get("dtype")
    ids, index_by = a.get("ids"), a.get("index_by")
    unit, src = mf.get("unit"), ",".join(mf.get("source") or []) or None
    legacy = mf.get("legacy_symbol")

    def mismatch(path, expected, actual, extra=None):
        text = "MISMATCH " + kv(("stage", cp), ("field", fid), ("path", path), ("rule", rule),
                                ("expected", expected), ("actual", actual), ("unit", unit),
                                ("source", src), ("legacy", legacy))
        findings.append(Finding("MISMATCH", cp, 3, (mi.cp_order.get(cp, 99), 3, fileidx, fidx),
                                text, extra=extra, file=fname, field=fid, problem=None,
                                path=path, rule=rule, expected=expected, actual=actual))

    if rule == "hash":
        rh, ah = r.get("sha256"), a.get("sha256")
        for side, entry, stored in (("expected", r, rh), ("actual", a, ah)):
            recomputed = field_digest(entry)
            if stored is not None and stored != recomputed:
                findings.append(struct_finding(mi, cp, 2, fileidx, fidx, file=fname, field=fid,
                                               problem="digest", expected=stored, actual=recomputed,
                                               detail=f"{side}: stored sha256 disagrees with its own values"))
                return "STRUCT(digest)"
        rh, ah = rh or field_digest(r), ah or field_digest(a)
        if rh != ah:
            extra = ['hint="hash-only field; rerun with --expand-hash"']
            if opts.expand_hash:
                extra = []
                rl, al = list(iter_leaves(r.get("values"))), list(iter_leaves(a.get("values")))
                for (ri, rv), (ai, av) in zip(rl, al):
                    if rv != av:
                        extra = [f"first_diff={q(full_path(fid, index_by, ids, ai, bnodes))} "
                                 f"expected={q(show(dtype, rv))} actual={q(show(dtype, av))}"]
                        break
                if not extra:
                    extra = [f"first_diff=length expected={len(rl)} actual={len(al)}"]
            mismatch(fid, f"sha256:{rh}", f"sha256:{ah}", extra)
            return "FAIL(hash)"
        return "PASS(hash)"

    rl, al = list(iter_leaves(r.get("values"))), list(iter_leaves(a.get("values")))
    total = len(rl)
    if total != len(al):  # defensive: the structure pass must have caught this already
        findings.append(struct_finding(mi, cp, 2, fileidx, fidx, file=fname, field=fid,
                                       problem="length", expected=total, actual=len(al),
                                       detail="leaf counts differ; values not compared"))
        return "STRUCT(length)"
    if rule in ("abs_tol", "rel_tol"):
        c = mf.get("compare") or {}
        atol, rtol = float(c.get("atol", 0.0)), float(c.get("rtol", 0.0))
        worst, worst_idx, worst_diff, bad = 0.0, None, 0.0, 0
        for (idx, rv), (_, av) in zip(rl, al):
            e, v = f64_of(rv) if isinstance(rv, str) else float(rv), f64_of(av) if isinstance(av, str) else float(av)
            d = abs(v - e)
            bound = atol + rtol * abs(e)
            norm = d / bound if bound > 0 else (0.0 if d == 0 else math.inf)
            if d > bound:
                bad += 1
            if norm > worst:
                worst, worst_idx, worst_diff = norm, idx, d
        if bad:
            path = full_path(fid, index_by, ids, worst_idx, bnodes)
            e = dict(rl)[worst_idx]
            v = dict(al)[worst_idx]
            mismatch(path, show(dtype, e), show(dtype, v),
                     [kv(("diff", short_float(worst_diff)), ("atol", atol), ("rtol", rtol),
                         ("worst_path", path), ("count", f"{bad}/{total}"))])
            return f"FAIL({rule} max_norm={worst:.3e})"
        return f"PASS({rule} max_norm={worst:.3e})"

    # exact: compare the canonical representation, never the decoded float
    first, bad = None, 0
    for (idx, rv), (_, av) in zip(rl, al):
        if rv != av:
            bad += 1
            if first is None:
                first = (idx, rv, av)
    if first is not None:
        idx, rv, av = first
        extra = [f"count={bad}/{total}"] if total > 1 else None
        mismatch(full_path(fid, index_by, ids, idx, bnodes), show(dtype, rv), show(dtype, av), extra)
        return "FAIL(exact)"
    return "PASS"


def compare_trees(ref: Snapshot, act: Snapshot, mi: MapIndex, opts) -> dict:
    findings: list[Finding] = []
    status: dict[str, dict[str, str]] = {}
    compared = skipped = 0
    failed: set[tuple[str, str]] = set()

    # 1 -- checkpoint set
    expected_cps = list(mi.covered)
    actual_cps = [c for c in act.cps if act.cps[c]]
    for cp in expected_cps:
        if cp not in actual_cps:
            findings.append(struct_finding(mi, cp, 0, -1, -1, problem="checkpoint_missing",
                                           expected=expected_cps, actual=actual_cps))
    ref_cps = [c for c in ref.cps if ref.cps[c]]
    for cp in expected_cps:
        if cp not in ref_cps:
            findings.append(struct_finding(mi, cp, 0, -1, -1, problem="checkpoint_missing",
                                           expected=expected_cps, actual=ref_cps,
                                           detail="reference"))
    for cp in actual_cps:
        if cp not in expected_cps:
            findings.append(Finding("STRUCT", cp, 0, (99, 0, -1, -1),
                                    "STRUCT " + kv(("stage", cp), ("problem", "checkpoint_extra"),
                                                   ("expected", expected_cps), ("actual", actual_cps)),
                                    file=None, field=None, problem="checkpoint_extra",
                                    expected=expected_cps, actual=actual_cps))

    for cp in expected_cps:
        status[cp] = {}
        if cp not in ref.cps or cp not in act.cps or not act.cps[cp]:
            continue
        rfiles, afiles = ref.files(cp), act.files(cp)
        # the map is the authority on which fields must exist, so a field absent from BOTH
        # trees is still a finding
        map_files: dict[str, set[str]] = {}
        for fid, f in mi.fields.get(cp, {}).items():
            if (f.get("compare") or {}).get("rule") == "ignore":
                continue
            map_files.setdefault(json_name(f.get("snapshot_file", "")), set()).add(fid)
        names = sorted(set(rfiles) | set(afiles) | set(map_files), key=lambda n: FILE_ORDER.get(n, 99))

        # 2 -- file level: unparsable, then sidecar digest
        for name in names:
            fi = FILE_ORDER.get(name, 99)
            for side, fd in (("expected", rfiles.get(name)), ("actual", afiles.get(name))):
                if fd is not None and fd.error:
                    findings.append(struct_finding(mi, cp, 1, fi, -1, file=name, problem="unparsable",
                                                   detail=f"{side}: {fd.error}"))
            fd = afiles.get(name)
            if fd is not None and fd.obj is not None:
                if fd.sidecar is not None and fd.raw is not None:
                    rec = sha256_bytes(fd.raw)
                    if fd.sidecar != rec:
                        findings.append(struct_finding(mi, cp, 1, fi, -1, file=name, problem="digest",
                                                       expected=fd.sidecar, actual=rec))
                if fd.obj.get("checkpoint") not in (None, cp):
                    findings.append(struct_finding(mi, cp, 1, fi, -1, file=name, problem="header",
                                                   expected=cp, actual=fd.obj.get("checkpoint")))

        # 3..5 -- field level
        bnodes_entry = None
        for name in names:
            e = (afiles.get(name).fields if afiles.get(name) else {}).get("steps0.boundary.nodes")
            if e:
                bnodes_entry = e
        bnodes = None
        if bnodes_entry:
            bnodes = [v for _, v in iter_leaves(bnodes_entry.get("values"))]

        for name in names:
            fi = FILE_ORDER.get(name, 99)
            rf = rfiles.get(name).fields if rfiles.get(name) else {}
            af = afiles.get(name).fields if afiles.get(name) else {}
            ids = sorted(set(rf) | set(af) | map_files.get(name, set()),
                         key=lambda f: (mi.fidx(cp, f), f))
            for fid in ids:
                if fid not in rf and fid not in af:
                    findings.append(struct_finding(mi, cp, 2, fi, mi.fidx(cp, fid), file=name,
                                                   field=fid, problem="missing",
                                                   expected="present", actual="absent",
                                                   detail="absent from both sides; the map expects it"))
                    status[cp][fid] = "STRUCT(missing)"
                    failed.add((cp, fid))
                    continue
                if fid in rf and fid not in af:
                    findings.append(struct_finding(mi, cp, 2, fi, mi.fidx(cp, fid), file=name,
                                                   field=fid, problem="missing",
                                                   expected="present", actual="absent"))
                    status[cp][fid] = "STRUCT(missing)"
                    failed.add((cp, fid))
                    continue
                if fid in af and fid not in rf:
                    findings.append(struct_finding(mi, cp, 2, fi, mi.fidx(cp, fid), file=name,
                                                   field=fid, problem="extra",
                                                   expected="absent", actual="present"))
                    status[cp][fid] = "STRUCT(extra)"
                    failed.add((cp, fid))
                    continue
                if mi.rule(cp, fid) == "ignore":
                    continue
                before = len(findings)
                ok = check_field_structure(mi, cp, name, fid, rf[fid], af[fid], findings, fi)
                if not ok:
                    status[cp][fid] = "STRUCT(" + str(findings[before].rec.get("problem")) + ")"
                    failed.add((cp, fid))
                    continue
                st = compare_field_values(mi, cp, name, fid, rf[fid], af[fid], findings, fi, opts, bnodes)
                status[cp][fid] = st
                compared += 1
                if st.startswith("FAIL") or st.startswith("STRUCT"):
                    failed.add((cp, fid))

        # ignore-rule fields
        for fid, f in mi.fields.get(cp, {}).items():
            if (f.get("compare") or {}).get("rule") != "ignore":
                continue
            skipped += 1
            if opts.strict:
                reason = (f.get("compare") or {}).get("reason") or f.get("reason") or ""
                findings.append(Finding("SKIPPED", cp, 4, (mi.cp_order.get(cp, 99), 4,
                                                           FILE_ORDER.get(json_name(f.get("snapshot_file", "")), 99),
                                                           mi.fidx(cp, fid)),
                                        "SKIPPED " + kv(("stage", cp), ("field", fid), ("rule", "ignore"),
                                                        ("reason", reason)),
                                        file=json_name(f.get("snapshot_file", "")), field=fid,
                                        problem=None, rule="ignore"))

    findings.sort(key=lambda f: f.order)

    # secondary_of: nearest failing ancestor along derived_from, same checkpoint
    for f in findings:
        fid, cp = f.rec.get("field"), f.stage
        if not fid or f.kind == "SKIPPED" or (cp, fid) not in failed:
            continue
        seen, queue = set(), list(mi.field(cp, fid).get("derived_from") or [])
        while queue:
            p = queue.pop(0)
            if p in seen:
                continue
            seen.add(p)
            if (cp, p) in failed:
                f.secondary_of = p
                break
            queue.extend(mi.field(cp, p).get("derived_from") or [])

    n_struct = sum(1 for f in findings if f.kind == "STRUCT")
    n_mis = sum(1 for f in findings if f.kind == "MISMATCH")
    code = 2 if n_struct else (1 if n_mis else 0)
    return {"passed": code == 0, "exit_code": code,
            "reference": ref.label, "actual": act.label,
            "map": {"path": str(mi.path) if mi.path else None, "sha256": mi.sha256},
            "summary": {"struct": n_struct, "mismatch": n_mis, "skipped": skipped, "compared": compared},
            "findings": [f.as_json() for f in findings],
            "fields": status, "_findings": findings}


def render(report: dict) -> list[str]:
    out: list[str] = []
    for f in report["_findings"]:
        out.extend(f.lines())
    s = report["summary"]
    out.append(f"PASS compared={s['compared']} skipped={s['skipped']}" if report["passed"] else
               f"FAIL struct={s['struct']} mismatch={s['mismatch']} "
               f"compared={s['compared']} skipped={s['skipped']}")
    return out


# --- raw state.txt trailer check (S02 class 8) -------------------------------------------
def check_raw_text(cp: str, text: str) -> list[str]:
    """Header/trailer/record-count validation of one raw `state.txt`.

    Delegates to yl_state.parse_state_text when that module is importable, keeping only the
    whole-file classes (header, truncated) so a partial fixture text does not drag in the
    per-field `missing` findings of a full normalize; otherwise applies the same checks
    locally, so this comparator's selftest never depends on a sibling tool being finished."""
    try:
        import yl_state
        mp = yl_state.MapIndex.load(MAP_DEFAULT)
        probs = yl_state.Problems()
        yl_state.parse_state_text(text, cp, mp, probs)
        whole = [p for p in probs if "problem=truncated" in p or "problem=header" in p]
        if whole:
            return whole
    except Exception:  # pragma: no cover - sibling tool absent or not yet functional
        pass
    lines = [ln for ln in text.splitlines() if ln.strip()]
    if not lines or not lines[0].startswith("HSTAR_STATE "):
        return ["STRUCT " + kv(("stage", cp), ("problem", "header"),
                               ("expected", "HSTAR_STATE schema=1"),
                               ("actual", lines[0] if lines else ""))]
    head = dict(p.split("=", 1) for p in lines[0].split()[1:] if "=" in p)
    if head.get("checkpoint") != cp:
        return ["STRUCT " + kv(("stage", cp), ("problem", "header"), ("expected", cp),
                               ("actual", head.get("checkpoint")))]
    records = sum(1 for ln in lines if ln.startswith("field="))
    if not lines[-1].startswith("HSTAR_STATE_END"):
        return ["STRUCT " + kv(("stage", cp), ("problem", "truncated"), ("expected", records),
                               ("actual", "missing trailer"))]
    tail = dict(p.split("=", 1) for p in lines[-1].split()[1:] if "=" in p)
    n_head, n_tail = int(head.get("fields", -1)), int(tail.get("fields", -1))
    if n_tail != records or n_head != records:
        return ["STRUCT " + kv(("stage", cp), ("problem", "truncated"), ("expected", records),
                               ("actual", n_tail if n_tail != records else n_head))]
    return []


# --- fixture and the nine S02 mutations ---------------------------------------------------
def hexf(v: float) -> str:
    return struct.pack(">d", v).hex().upper()


def envelope(cp: str, name: str, fields: dict) -> dict:
    return {"schema": 1, "checkpoint": cp, "file": name, "float_format": "hex",
            "map_sha256": "0" * 64, "fields": fields}


def build_fixture() -> dict[str, dict[str, dict]]:
    """3 nodes / 2 elements / 1 material / 1 elset / 2 boundary records, five shape families."""
    mr = "model_ready"
    control = envelope(mr, "control.json", {
        "mesh.dimension": {"dtype": "i32", "shape": [], "index_by": "component", "values": 2}})
    xyz = {"dtype": "f64", "shape": [2, 3], "index_by": "mesh.nodes[].id", "ids": [1, 2, 3],
           "values": [[hexf(0.0), hexf(0.0)], [hexf(20.0), hexf(0.0)], [hexf(20.0), hexf(10.0)]]}
    conn = {"dtype": "i32", "shape": [4, 2], "index_by": "mesh.elements[].id", "ids": [1, 2],
            "values": [[1, 2, 3, 1], [2, 3, 1, 2]]}
    unode = {"dtype": "i32", "shape": [3, 1], "index_by": "sections[].name", "ids": ["FRAME"],
             "values": [[1, 2, 3]]}
    unode["sha256"] = field_digest(unode)
    mesh = envelope(mr, "mesh.json", {"mesh.nodes.xyz": xyz, "mesh.elements.nodes": conn,
                                      "runtime.topology.unode_list": unode})
    dof = envelope(mr, "dof.json", {
        "runtime.dof.iffix": {"dtype": "i32", "shape": [6], "index_by": "(node,dof)",
                              "ids": [[1, 1], [1, 2], [2, 1], [2, 2], [3, 1], [3, 2]],
                              "values": [1, 1, 0, 0, 0, 0]}})
    groups = envelope(mr, "groups.json", {
        "mesh.sets.elset": {"dtype": "i32", "shape": None, "index_by": "sections[].name",
                            "keys": [1], "ids": ["FRAME"], "values": [[1, 2]]}})
    materials = envelope(mr, "materials.json", {
        "materials.E": {"dtype": "f64", "shape": [1], "index_by": "materials[].id", "ids": [1],
                        "values": [hexf(2.5e10)]}})
    constraints = envelope(mr, "constraints.json", {
        # ragged: one variable-length node list per boundary set (shape is null)
        "mesh.sets.nset": {"dtype": "i32", "shape": None, "index_by": "steps[0].boundary[].name",
                           "keys": [1, 2], "ids": [1, 2], "values": [[1, 2], [3, 4]]},
        "steps0.boundary.nodes": {"dtype": "i32", "shape": [2], "index_by": "steps[0].boundary[].name",
                                  "ids": [[1, 1], [1, 2]], "values": [1, 3]},
        "steps0.boundary.value": {"dtype": "f64", "shape": [2], "index_by": "steps[0].boundary[].name",
                                  "ids": [[1, 1], [1, 2]], "values": [hexf(0.0), hexf(0.001)]}})
    phase = envelope("phase_ready(1)", "numerics.json", {
        "runtime.eq.neq": {"dtype": "i32", "shape": [], "index_by": "component", "values": 6}})
    incr = envelope("increment_ready(1,1)", "steps.json", {
        "steps0.controls.max_iterations": {"dtype": "i32", "shape": [], "index_by": "component",
                                           "values": 30}})
    return {mr: {"control.json": control, "mesh.json": mesh, "dof.json": dof,
                 "groups.json": groups, "materials.json": materials,
                 "constraints.json": constraints},
            "phase_ready(1)": {"numerics.json": phase},
            "increment_ready(1,1)": {"steps.json": incr}}


FIXTURE_RAW = """HSTAR_STATE schema=1 checkpoint=model_ready fields=5
field=mesh.dimension shape=[] dtype=i32 values=2
field=mesh.nodes.xyz shape=[2,3] dtype=f64 order=F values=%s
field=mesh.elements.nodes shape=[4,2] dtype=i32 order=F values=1 2 3 1 2 3 1 2
field=materials.E shape=[1] dtype=f64 values=%s
field=runtime.dof.iffix shape=[6] dtype=i32 values=1 1 0 0 0 0
HSTAR_STATE_END fields=5
""" % (" ".join([hexf(0.0), hexf(0.0), hexf(20.0), hexf(0.0), hexf(20.0), hexf(10.0)]), hexf(2.5e10))


def pick_targets(objs: dict) -> dict:
    """Resolve mutation targets by scanning the reference tree, so the same nine mutations
    apply to the synthetic fixture and to a real normalized snapshot."""
    cps = [c for c in objs if objs[c]]
    mr = cps[0]
    t = {"cp": mr, "cp2": cps[1] if len(cps) > 1 else mr}

    def scan(pred, files=None):
        for name in sorted(objs[mr], key=lambda n: FILE_ORDER.get(n, 99)):
            if files and name not in files:
                continue
            for fid, e in objs[mr][name].get("fields", {}).items():
                if pred(fid, e):
                    return name, fid
        return None, None

    t["scalar_file"], t["scalar"] = scan(
        lambda f, e: e.get("dtype") == "f64" and e.get("ids") is not None, ["materials.json"])
    if t["scalar"] is None:
        t["scalar_file"], t["scalar"] = scan(lambda f, e: e.get("dtype") == "f64" and e.get("ids"))
    t["array_file"], t["array"] = scan(
        lambda f, e: e.get("dtype") == "f64" and isinstance(e.get("ids"), list) and len(e["ids"]) >= 3
        and isinstance(e.get("shape"), list) and len(e["shape"]) == 2, ["mesh.json"])
    t["id_file"], t["id"] = scan(
        lambda f, e: isinstance(e.get("ids"), list) and len(e["ids"]) >= 2 and f != t["array"],
        ["mesh.json"])

    def ragged(min_group):
        return lambda f, e: (e.get("shape") is None and isinstance(e.get("ids"), list)
                             and len(e["ids"]) >= 2
                             and all(isinstance(v, list) and len(v) >= min_group for v in e["values"]))
    t["ragged_file"], t["ragged"] = scan(ragged(2))
    if t["ragged"] is None:
        t["ragged_file"], t["ragged"] = scan(ragged(1))
    return t


def mutate_ragged(o: dict, t: dict, how: str):
    """`shrink` drops the last entry of the last key; `regroup` moves one entry from the
    first key to the second, leaving the flattened leaf sequence identical."""
    e = o[t["cp"]][t["ragged_file"]]["fields"][t["ragged"]]
    if how == "shrink":
        e["values"][-1] = e["values"][-1][:-1]
    else:
        moved = e["values"][0][-1]
        e["values"][0] = e["values"][0][:-1]
        e["values"][1] = [moved] + e["values"][1]


def mutate(name: str, objs: dict, t: dict):
    """Return (reference objs, actual objs, stale-sidecar map) for one class.

    Most classes leave the reference alone; the guard classes may mutate either side."""
    o = copy.deepcopy(objs)
    ro = objs
    cp, stale = t["cp"], {}
    if name == "deleted_field":
        del o[cp][t["scalar_file"]]["fields"][t["scalar"]]
    elif name == "wrong_shape":
        e = o[cp][t["array_file"]]["fields"][t["array"]]
        e["ids"] = e["ids"][:-1]
        e["values"] = e["values"][:-1]
        e["shape"] = list(e["shape"][:-1]) + [len(e["ids"])]
    elif name == "nonfinite":
        e = o[cp][t["array_file"]]["fields"][t["array"]]
        e["values"][1][0] = "7FF8000000000000"
    elif name == "duplicate_id":
        e = o[cp][t["id_file"]]["fields"][t["id"]]
        e["ids"][1] = e["ids"][0]
    elif name == "wrong_dtype":
        e = o[cp][t["scalar_file"]]["fields"][t["scalar"]]
        e["dtype"] = "i32"
        e["values"] = [1 for _ in e["values"]]
    elif name == "wrong_checkpoint":
        del o[t["cp2"]]
    elif name == "value_diff":
        e = o[cp][t["scalar_file"]]["fields"][t["scalar"]]
        idx, tok = next(iter_leaves(e["values"]))
        v = e["values"]
        for k in idx[:-1]:
            v = v[k]
        v[idx[-1]] = hexf(f64_of(tok) * 1.04)
    elif name == "truncated":
        pass  # raw layer, handled by check_raw_text
    elif name == "stale_digest":
        e = o[cp][t["array_file"]]["fields"][t["array"]]
        e["values"][1][0] = "7FF8000000000000"
        stale = {cp: {t["array_file"]: sha256_bytes(canon_bytes(objs[cp][t["array_file"]]))}}
    elif name == "ragged_length":
        mutate_ragged(o, t, "shrink")
    elif name == "ragged_regroup":
        mutate_ragged(o, t, "regroup")
    elif name == "ref_checkpoint_missing":
        ro = copy.deepcopy(objs)
        del ro[t["cp2"]]
    elif name == "missing_from_both":
        ro = copy.deepcopy(objs)
        del ro[cp][t["scalar_file"]]["fields"][t["scalar"]]
        del o[cp][t["scalar_file"]]["fields"][t["scalar"]]
    else:  # pragma: no cover
        raise ValueError(name)
    return ro, o, stale


CLASSES = [("deleted_field", "delete one field entry from materials.json"),
           ("wrong_shape", "drop the last entity id/value block and shrink shape"),
           ("nonfinite", "set one f64 token to the quiet-NaN payload"),
           ("duplicate_id", "repeat the first entity id"),
           ("wrong_dtype", "retype the field f64 -> i32"),
           ("wrong_checkpoint", "delete the second covered checkpoint"),
           ("value_diff", "scale one f64 value by 1.04"),
           ("truncated", "raw state.txt trailer fields= one short"),
           ("stale_digest", "mutate mesh.json without re-signing the sidecar")]

# guard classes: fail-open paths found in review, kept out of the nine-entry S02 evidence list
GUARDS = [("ragged_length", "drop the last entry of the last key of a ragged field"),
          ("ragged_regroup", "move one entry between ragged keys, flat sequence unchanged"),
          ("ref_checkpoint_missing", "delete the second covered checkpoint from the REFERENCE"),
          ("missing_from_both", "delete a map-required field from both sides")]


def run_class(name: str, objs: dict, t: dict, mi: MapIndex, opts, raw_text: str | None):
    if name == "truncated":
        text = (raw_text or FIXTURE_RAW).replace("HSTAR_STATE_END fields=5", "HSTAR_STATE_END fields=4")
        if raw_text:
            head = raw_text.splitlines()[0]
            n = int(dict(p.split("=", 1) for p in head.split()[1:] if "=" in p).get("fields", 0))
            tail = f"HSTAR_STATE_END fields={n}"
            text = raw_text.replace(tail, f"HSTAR_STATE_END fields={n - 1}")
        lines = check_raw_text(t["cp"], text)
        return {"exit_code": 2 if lines else 0, "lines": lines,
                "report": {"passed": not lines, "exit_code": 2 if lines else 0,
                           "findings": [{"kind": "STRUCT", "stage": t["cp"], "field": None,
                                         "problem": "truncated", "text": lines[0] if lines else ""}],
                           "summary": {"struct": len(lines), "mismatch": 0, "skipped": 0, "compared": 0}}}
    ro, mo, stale = mutate(name, objs, t)
    ref = sign_objs(ro, "reference")
    act = sign_objs(mo, f"actual[{name}]", stale)
    rep = compare_trees(ref, act, mi, opts)
    return {"exit_code": rep["exit_code"], "lines": render(rep)[:-1], "report": rep}


class Opts:
    def __init__(self, strict=False, expand_hash=False):
        self.strict, self.expand_hash = strict, expand_hash


def fixture_map(objs: dict) -> MapIndex:
    """The real map narrowed to the fixture's fields (ignore rows kept, so the SKIPPED count
    stays real).  Field metadata still comes from docs/m2/state-field-map.toml, so the
    expected MISMATCH text is the production text; what changes is only which non-ignore
    fields the map requires, which is what the missing-from-both rule keys off."""
    doc = copy.deepcopy(load_map(MAP_DEFAULT))
    keep = {fid for files in objs.values() for env in files.values() for fid in env["fields"]}
    doc["field"] = [f for f in doc["field"]
                    if f["id"] in keep or (f.get("compare") or {}).get("rule") == "ignore"]
    return MapIndex(doc, MAP_DEFAULT)


def selftest() -> int:
    objs = build_fixture()
    mi = fixture_map(objs)
    t = pick_targets(objs)
    opts = Opts()
    ok = True

    ref = sign_objs(objs, "reference")
    base = compare_trees(ref, sign_objs(copy.deepcopy(objs), "actual"), mi, opts)
    print(f"  self-compare            exit={base['exit_code']} {render(base)[-1]}")
    if base["exit_code"] != 0:
        ok = False
        for ln in render(base)[:6]:
            print("    " + ln)

    nan_file_digest = sha256_bytes(canon_bytes(objs[t["cp"]][t["array_file"]]))
    _, mutated_nan, _ = mutate("stale_digest", objs, t)
    recomputed = sha256_bytes(canon_bytes(mutated_nan[t["cp"]][t["array_file"]]))
    expect = {
        "deleted_field": (2, "STRUCT stage=model_ready file=materials.json field=materials.E "
                             "problem=missing expected=present actual=absent"),
        "wrong_shape": (2, "STRUCT stage=model_ready file=mesh.json field=mesh.nodes.xyz "
                           "problem=shape expected=[2,3] actual=[2,2]"),
        "nonfinite": (2, "STRUCT stage=model_ready file=mesh.json field=mesh.nodes.xyz "
                         "problem=nonfinite path=mesh.nodes[2].xyz[1] actual=nan"),
        "duplicate_id": (2, "STRUCT stage=model_ready file=mesh.json field=mesh.elements.nodes "
                            "problem=duplicate_id path=mesh.elements[1] count=2"),
        "wrong_dtype": (2, "STRUCT stage=model_ready file=materials.json field=materials.E "
                           "problem=dtype expected=f64 actual=i32"),
        "wrong_checkpoint": (2, "STRUCT stage=phase_ready(1) problem=checkpoint_missing "
                                "expected=[model_ready,phase_ready(1),increment_ready(1,1)] "
                                "actual=[model_ready,increment_ready(1,1)]"),
        "value_diff": (1, "MISMATCH stage=model_ready field=materials.E path=materials[1].E "
                          f"rule=exact expected=2.5e+10({hexf(2.5e10)}) actual=2.6e+10({hexf(2.6e10)}) "
                          "unit=Pa source=MAT.material_set.elastic_isotropic "
                          "legacy=materials.props%mechanical%solid%e"),
        "truncated": (2, "STRUCT stage=model_ready problem=truncated expected=5 actual=4"),
        "stale_digest": (2, f"STRUCT stage=model_ready file=mesh.json problem=digest "
                            f"expected={nan_file_digest} actual={recomputed}"),
        "ragged_length": (2, "STRUCT stage=model_ready file=constraints.json field=mesh.sets.nset "
                             "problem=length path=steps[0].boundary[2].nset expected=2 actual=1"),
        "ragged_regroup": (2, "STRUCT stage=model_ready file=constraints.json field=mesh.sets.nset "
                              "problem=length path=steps[0].boundary[1].nset expected=2 actual=1"),
        "ref_checkpoint_missing": (2, "STRUCT stage=phase_ready(1) problem=checkpoint_missing "
                                      "expected=[model_ready,phase_ready(1),increment_ready(1,1)] "
                                      "actual=[model_ready,increment_ready(1,1)] detail=reference"),
        "missing_from_both": (2, "STRUCT stage=model_ready file=materials.json field=materials.E "
                                 "problem=missing expected=present actual=absent "
                                 'detail="absent from both sides; the map expects it"'),
    }
    for name, _desc in CLASSES + GUARDS:
        res = run_class(name, objs, t, mi, opts, None)
        want_code, want_line = expect[name]
        got = res["lines"][0] if res["lines"] else "<no output>"
        good = res["exit_code"] == want_code and got == want_line
        f0 = (res["report"].get("findings") or [{}])[0]
        good = good and f0.get("stage") is not None and (f0.get("problem") or f0.get("path"))
        print(f"  {'ok  ' if good else 'FAIL'} {name:<17} exit={res['exit_code']}\n       {got}")
        if not good:
            ok = False
            print(f"       expected exit={want_code}\n       {want_line}")

    # --strict lists ignore-rule fields as SKIPPED and stays exit 0
    st = compare_trees(ref, sign_objs(copy.deepcopy(objs), "actual"), mi, Opts(strict=True))
    strict_ok = st["exit_code"] == 0 and st["summary"]["skipped"] > 0 and \
        any(line.startswith("SKIPPED ") for line in render(st))
    print(f"  {'ok  ' if strict_ok else 'FAIL'} strict-skipped    skipped={st['summary']['skipped']}")
    ok = ok and strict_ok

    # hash rule + secondary_of: change the connectivity a hash field derives from
    mo = copy.deepcopy(objs)
    mo["model_ready"]["mesh.json"]["fields"]["mesh.elements.nodes"]["values"][0][0] = 3
    u = mo["model_ready"]["mesh.json"]["fields"]["runtime.topology.unode_list"]
    u["values"][0][0] = 3
    u["sha256"] = field_digest(u)
    hrep = compare_trees(ref, sign_objs(mo, "actual[hash]"), mi, Opts(expand_hash=True))
    hl = render(hrep)
    hash_ok = hrep["exit_code"] == 1 and any("rule=hash" in x for x in hl) and \
        any(x.strip().startswith("secondary_of=mesh.elements.nodes") for x in hl) and \
        any(x.strip().startswith("first_diff=") for x in hl)
    print(f"  {'ok  ' if hash_ok else 'FAIL'} hash+secondary_of exit={hrep['exit_code']}")
    for line in hl:
        if "rule=hash" in line or line.strip().startswith(("secondary_of=", "first_diff=")):
            print("       " + line)
    ok = ok and hash_ok

    print(("PASS " if ok else "FAIL ") +
          f"selftest s02={len(CLASSES)} guards={len(GUARDS)} checks={len(CLASSES) + len(GUARDS) + 3}")
    return 0 if ok else 1


def snapshot_mode(dirpath: Path, raw_dir: Path | None, mi: MapIndex, opts) -> tuple[int, dict]:
    snap = load_dir(dirpath, mi.covered)
    objs = snap.objs()
    if not any(objs.values()):
        print(f"FAIL: no normalized checkpoint found under {dirpath}")
        return 3, {}
    t = pick_targets(objs)
    raw_text = None
    if raw_dir:
        for cp_dir in (t["cp"], t["cp"].replace("(", "_").replace(",", "_").replace(")", "")):
            p = raw_dir / cp_dir / "state.txt"
            if p.is_file():
                raw_text = p.read_text(encoding="latin-1")
                break
    out = {"snapshot": str(dirpath), "raw_dir": str(raw_dir) if raw_dir else None,
           "targets": t, "classes": [], "guards": []}
    for key, table in (("classes", CLASSES), ("guards", GUARDS)):
        for name, desc in table:
            res = run_class(name, objs, t, mi, opts, raw_text)
            first = res["lines"][0] if res["lines"] else ""
            out[key].append({"class": name, "mutation": desc, "exit_code": res["exit_code"],
                             "first_line": first,
                             "on": "synthetic" if name == "truncated" and not raw_text else "snapshot"})
            print(f"{name:<22} exit={res['exit_code']}\n  {first}")
    return 0, out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter,
                                 add_help=True)
    ap.add_argument("reference", nargs="?")
    ap.add_argument("actual", nargs="?")
    ap.add_argument("--map", default=str(MAP_DEFAULT))
    ap.add_argument("--strict", action="store_true", help="list ignore-rule fields as SKIPPED")
    ap.add_argument("--expand-hash", action="store_true", help="print the first differing index of a hash field")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--snapshot", help="apply the nine S02 mutations to a real normalized snapshot")
    ap.add_argument("--raw-dir", help="raw <work>/state directory, for the S02 truncation class")
    ap.add_argument("-o", "--output")
    a = ap.parse_args(argv)

    if a.selftest and a.snapshot:
        print("FAIL: --selftest and --snapshot are mutually exclusive")
        return 3
    if not a.selftest and not a.snapshot and not (a.reference and a.actual):
        ap.print_usage(sys.stderr)
        print("FAIL: REF and ACTUAL are required", file=sys.stderr)
        return 3

    map_path = Path(a.map)
    try:
        mi = MapIndex(load_map(map_path), map_path)
    except Exception as e:
        print(f"FAIL: map {map_path}: {e}")
        return 3

    if a.selftest:
        return selftest()

    opts = Opts(a.strict, a.expand_hash)
    if a.snapshot:
        code, out = snapshot_mode(Path(a.snapshot), Path(a.raw_dir) if a.raw_dir else None, mi, opts)
        if a.output and out:
            Path(a.output).write_text(json.dumps(out, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        return code

    for p in (Path(a.reference), Path(a.actual)):
        if not p.is_dir():
            print(f"FAIL: not a snapshot directory: {p}")
            return 3
    ref = load_dir(Path(a.reference), mi.covered)
    act = load_dir(Path(a.actual), mi.covered)
    report = compare_trees(ref, act, mi, opts)
    for line in render(report):
        print(line)
    if a.output:
        pub = {k: v for k, v in report.items() if k != "_findings"}
        Path(a.output).write_text(json.dumps(pub, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return report["exit_code"]


if __name__ == "__main__":
    sys.exit(main())
