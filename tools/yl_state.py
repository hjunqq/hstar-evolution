#!/usr/bin/env python3
"""Normalize the legacy YL state dump into canonical JSON (M2-02, Python side).

The instrumented solver writes one `state.txt` per checkpoint under
`<work>/state/<sanitized checkpoint>/` in the M2-02 wire format:

    HSTAR_STATE schema=1 checkpoint=<id> fields=N
    field=<id> key=[k1,...] shape=[d1,d2,...] dtype=<t> [order=F] values=[<tok>,...]
    ...
    HSTAR_STATE_END fields=N

`fields=N` counts logical field ids (a ragged field written as one line per outer
key still counts once).  `key=[]` is the writer's dense marker and means "no key"; a
non-empty key holds the outermost dimensions first, so `sections.dof_list(nfdof,
nrfields, ngroup)` arrives as `key=[igroup,ifield] shape=[nfdof]`.  f64 tokens are 16 hex digits of the IEEE-754 bit pattern in
big-endian textual order, i32/i64 are decimal, str is `x` followed by the byte hex
(`x` alone is the empty string), dense arrays are flattened in Fortran order.

`normalize` re-reads that dump against the authoritative field map
(docs/m2/state-field-map.toml), validates it fail-closed, and writes the nine
snapshot names of docs/01 section 5 per checkpoint plus, next to each `.sha256`
name, the structured sibling `.json` it digests, plus `fingerprint.json`.  Nothing
is written when a single problem is found (a temporary directory is renamed into
place only on success), so a malformed dump can never masquerade as evidence.

Sub-commands
  normalize   RAW_DIR -> OUT_DIR: parse, validate, re-key, reconstruct, write the
              canonical tree and fingerprint.json
  fingerprint DIR: print the fingerprint of an already-normalized tree (or of a raw
              dump, normalized into a temporary directory first) for the M2-03
              three-run repeat check
  --selftest  in-memory fixtures: every parser error class, the five shape families,
              the (node,dof) bijection assertion, the reconstruct table match, and
              byte-for-byte idempotence of normalize

Usage
  python3 tools/yl_state.py normalize RAW_DIR -o OUT_DIR
                            [--map docs/m2/state-field-map.toml] [--case-id ID] [--quiet]
  python3 tools/yl_state.py fingerprint RAW_OR_NORMALIZED_DIR [--map ...]
  python3 tools/yl_state.py --selftest

Exit codes: 0 success; 1 normalization problems; 3 usage / map load failure.
The last line is always `PASS ...` or `FAIL ...`.

Validation (every problem is a STRUCT line; all of them carry `line=` except the
whole-file `truncated` class, whose text is fixed by the S02 selftest table):
  header            first line is not `HSTAR_STATE schema=1 checkpoint=<expected> fields=N`
  truncated         `HSTAR_STATE_END fields=M` missing, or M / header N disagree with
                    the number of distinct field ids actually present
  extra             field id unknown to the map, registered at another checkpoint, or
                    carrying the compare rule `ignore`
  duplicate_record  the same (field, key) twice
  missing           a non-ignore, non-reconstruct field of this checkpoint has no line
  dtype             dtype differs from the map
  rank              record rank is not (map rank - key arity), give or take the one
                    ragged dimension the map's symbolic shape cannot express
  length            len(values) != product(shape) of that record
  token             f64 not 16 hex digits, i32/i64 not decimal, str not `x` + even hex
  nonfinite         a decoded f64 is NaN or +-Inf
  key               a non-empty `key=` on an `index_by = "component"` field, a
                    non-positive key component, a key arity that differs between the records
                    of one field, or a ragged field written without any key
  syntax            the line is not a well-formed record (no `values=`, no shape/dtype)
  index_map         nodfn is not a bijection onto 1..ntotv, or is unavailable, so no
                    `shape = ["ntotv"]` field of that checkpoint can be re-keyed
  reconstruct       a `reconstruct` recipe cannot be evaluated (missing input, empty group),
                    or the row the solver dumped disagrees with the recipe

Canonical JSON everywhere: `sort_keys=True, separators=(",",":"), ensure_ascii=True`
plus a trailing newline.  Nesting follows Fortran order with the LAST dimension
outermost, so `coord(ndimn,npoin)` yields one `[x,y]` block per node.  Entity-keyed
fields carry sorted `ids` aligned with `values`; ragged fields additionally carry
`keys` (the legacy ordinals).  `shape = ["ntotv"]` fields are re-keyed to
`[[node,dof],...]` through `nodfn`, whose bijection onto 1..ntotv is asserted.

Only the Python standard library is used; the field map, the snapshot names and the
compare vocabulary are imported from tools/yl_state_map.py rather than restated.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import shutil
import struct
import sys
import tempfile
import tomllib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from yl_state_map import (COMPARE_RULES, DTYPES, MAP_DEFAULT, REPO_ROOT,  # noqa: E402
                          SNAPSHOT_FILES, load_map)

SCHEMA = 1
NORMALIZER = "yl_state.py/1"
FLOAT_FORMAT = "hex"
# the four digest names of docs/01 section 5 and the structured sibling each one digests
SIDECAR = {n: n[:-len(".sha256")] + ".json" for n in SNAPSHOT_FILES if n.endswith(".sha256")}
INT_DTYPES = {"i32", "i64", "bool"}
HEX16 = re.compile(r"^[0-9A-Fa-f]{16}$")
DEC_INT = re.compile(r"^[+-]?\d+$")
HEXBYTES = re.compile(r"^[0-9A-Fa-f]*$")
HEADER = re.compile(r"^HSTAR_STATE\s+schema=(\d+)\s+checkpoint=(\S+)\s+fields=(\d+)\s*$")
TRAILER = re.compile(r"^HSTAR_STATE_END\s+fields=(\d+)\s*$")
# entity label -> the field whose values carry the human-readable ids of that entity
ID_PROVIDER = {"mesh.nodes[].id": "mesh.nodes.id",
               "mesh.elements[].id": "mesh.elements.id",
               "materials[].id": "materials.id",
               "sections[].name": "sections.name",
               "amplitudes[].name": "amplitudes.name"}
BOUNDARY_INDEX = "steps[0].boundary[].name"
BOUNDARY_SET = "steps0.boundary.set"
NTOTV_SHAPE = ["ntotv"]
NTOTV_INDEX = "(node,dof)"


def dumps(obj) -> str:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def sha256_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def sanitize(checkpoint: str) -> str:
    """`phase_ready(1)` -> `phase_ready_1` (the Fortran side cannot create odd dir names)."""
    return re.sub(r"_+$", "", re.sub(r"[^A-Za-z0-9_]+", "_", checkpoint))


def prod(dims) -> int:
    n = 1
    for d in dims:
        n *= d
    return n


def nest(flat: list, shape: list[int]):
    """Fortran-order flat -> nested lists with the LAST dimension outermost."""
    if not shape:
        return flat[0]
    outer, block = shape[-1], prod(shape[:-1])
    if len(shape) == 1:
        return list(flat)
    return [nest(flat[i * block:(i + 1) * block], shape[:-1]) for i in range(outer)]


# --- field map ----------------------------------------------------------------------------
class MapIndex:
    """Derived indexes over docs/m2/state-field-map.toml (loaded via yl_state_map.load_map)."""

    def __init__(self, doc: dict, path: Path | None = None, sha: str | None = None):
        self.doc = doc
        self.path = path
        self.sha256 = sha
        cps = [c for c in doc.get("checkpoint", []) if c.get("covered")]
        self.order = [c["id"] for c in sorted(cps, key=lambda c: c.get("order", 0))]
        self.fields = {r["id"]: r for r in doc.get("field", [])}
        self.by_cp: dict[str, list[dict]] = {cp: [] for cp in self.order}
        for r in doc.get("field", []):
            if r["checkpoint"] in self.by_cp:
                self.by_cp[r["checkpoint"]].append(r)
        self.ragged = {s for s, txt in doc.get("shape_symbols", {}).items()
                       if "ragged" in str(txt).lower()}

    @classmethod
    def load(cls, path) -> "MapIndex":
        p = Path(path)
        return cls(load_map(p), p, sha256_bytes(p.read_bytes()))

    @staticmethod
    def rule(row: dict) -> str:
        return row.get("compare", {}).get("rule", "exact")

    def dumped(self, row: dict) -> bool:
        """True when the solver is expected to write this field into state.txt."""
        return self.rule(row) != "ignore" and "reconstruct" not in row

    def map_ref(self) -> dict:
        try:
            rel = str(self.path.resolve().relative_to(REPO_ROOT))
        except (AttributeError, ValueError):
            rel = str(self.path) if self.path else "<in-memory>"
        return {"path": rel, "sha256": self.sha256 or ""}


# --- parsed records -----------------------------------------------------------------------
class Record:
    __slots__ = ("field", "key", "shape", "dtype", "values", "line")

    def __init__(self, field, key, shape, dtype, values, line):
        self.field, self.key, self.shape = field, key, shape
        self.dtype, self.values, self.line = dtype, values, line


class Problems(list):
    def add(self, stage, code, *, file=None, field=None, line=None, **kw):
        parts = [f"STRUCT stage={stage}"]
        if file:
            parts.append(f"file={file}")
        if field:
            parts.append(f"field={field}")
        parts.append(f"problem={code}")
        if line is not None:
            parts.append(f"line={line}")
        for k, v in kw.items():
            parts.append(f"{k}=" + (dumps(v) if isinstance(v, str) and (" " in v or not v) else
                                    (dumps(v) if isinstance(v, (list, dict)) else str(v))))
        self.append(" ".join(parts))


def split_list(text: str) -> list[str]:
    s = text.strip()
    if s.startswith("["):
        s = s[1:]
    if s.endswith("]"):
        s = s[:-1]
    return [t for t in re.split(r"[\s,]+", s) if t]


def decode_f64(tok: str) -> float:
    return struct.unpack(">d", bytes.fromhex(tok))[0]


def parse_state_text(text: str, checkpoint: str, mp: MapIndex,
                     problems: Problems, file: str = "state.txt") -> dict[str, list[Record]]:
    """Wire format -> {field id: [Record, ...]}; every violation is appended to `problems`."""
    lines = text.splitlines()
    while lines and not lines[-1].strip():
        lines.pop()
    if not lines:
        problems.add(checkpoint, "header", file=file, line=1, detail="empty state.txt")
        return {}
    m = HEADER.match(lines[0].strip())
    if not m or m.group(1) != str(SCHEMA) or m.group(2) != checkpoint:
        problems.add(checkpoint, "header", file=file, line=1,
                     expected=f"HSTAR_STATE schema={SCHEMA} checkpoint={checkpoint} fields=N",
                     actual=lines[0].strip())
        return {}
    declared = int(m.group(3))
    body, trailer = lines[1:], None
    if body and TRAILER.match(body[-1].strip()):
        trailer = int(TRAILER.match(body[-1].strip()).group(1))
        body = body[:-1]

    records: dict[str, list[Record]] = {}
    for off, raw in enumerate(body):
        lineno = off + 2
        line = raw.strip()
        if not line:
            continue
        rec = parse_record(line, lineno, checkpoint, mp, problems, file)
        if rec is None:
            continue
        prev = records.setdefault(rec.field, [])
        if any(p.key == rec.key for p in prev):
            problems.add(checkpoint, "duplicate_record", file=file, field=rec.field, line=lineno,
                         key=("null" if rec.key is None else list(rec.key)))
            continue
        prev.append(rec)

    observed = len(records)
    if trailer is None:
        problems.add(checkpoint, "truncated", file=file, line=len(lines),
                     expected=declared, actual=observed, detail="missing HSTAR_STATE_END")
    elif trailer != observed:
        # verbatim text of the S02 truncation class: no file=/line= keys
        problems.append(f"STRUCT stage={checkpoint} problem=truncated "
                        f"expected={observed} actual={trailer}")
    elif declared != observed:
        problems.append(f"STRUCT stage={checkpoint} problem=truncated "
                        f"expected={declared} actual={observed}")

    for fid, recs in records.items():
        row = mp.fields[fid]
        keyed = any(r.key is not None for r in recs)
        if keyed and any(r.key is None for r in recs):
            problems.add(checkpoint, "key", file=file, field=fid, line=recs[0].line,
                         detail="mixed keyed and unkeyed records")
        if not keyed and is_ragged(mp, row):
            problems.add(checkpoint, "key", file=file, field=fid, line=recs[0].line,
                         detail="ragged field written without key=")
        arities = {len(r.key) for r in recs if r.key is not None}
        if len(arities) > 1:
            problems.add(checkpoint, "key", file=file, field=fid, line=recs[0].line,
                         actual=sorted(arities), detail="key arity differs between records")
        ranks = {len(r.shape) for r in recs}
        mr, ka = len(row["shape"]), (max(arities) if arities else 0)
        # a key of arity k consumes the k outermost dimensions; a field that is ragged inside
        # its innermost declared dimension keeps one dimension the map cannot express
        allowed = {mr} if not ka else {max(mr - ka, 0), mr - ka + 1}
        if len(ranks) > 1 or not (ranks & allowed):
            problems.add(checkpoint, "rank", file=file, field=fid, line=recs[0].line,
                         expected=sorted(allowed), actual=sorted(ranks))

    for row in mp.by_cp.get(checkpoint, []):
        if mp.dumped(row) and row["id"] not in records:
            problems.add(checkpoint, "missing", file=file, field=row["id"],
                         line=len(lines), expected="present", actual="absent")
    return records


def is_ragged(mp: MapIndex, row: dict) -> bool:
    return bool(set(map(str, row["shape"])) & mp.ragged)


def parse_record(line: str, lineno: int, checkpoint: str, mp: MapIndex,
                 problems: Problems, file: str) -> Record | None:
    head, sep, tail = line.partition("values=")
    if not sep:
        problems.add(checkpoint, "syntax", file=file, line=lineno, detail="no values= on the line")
        return None
    attrs: dict[str, str] = {}
    for tok in head.split():
        k, eq, v = tok.partition("=")
        if not eq:
            problems.add(checkpoint, "syntax", file=file, line=lineno, detail=f"bad token {tok}")
            return None
        attrs[k] = v
    fid = attrs.get("field")
    if fid is None or "shape" not in attrs or "dtype" not in attrs:
        problems.add(checkpoint, "syntax", file=file, line=lineno,
                     detail="field=/shape=/dtype= required")
        return None
    row = mp.fields.get(fid)
    if row is None or row["checkpoint"] != checkpoint or MapIndex.rule(row) == "ignore":
        why = ("unknown field id" if row is None else
               f"registered at {row['checkpoint']}" if row["checkpoint"] != checkpoint else
               "compare rule is ignore")
        problems.add(checkpoint, "extra", file=file, field=fid, line=lineno, detail=why)
        return None

    key = None
    ktoks = split_list(attrs.get("key", ""))  # `key=[]` is the writer's dense marker (NO_KEY)
    if ktoks:
        if row["index_by"] == "component":
            problems.add(checkpoint, "key", file=file, field=fid, line=lineno,
                         detail="non-empty key= on an index_by=component field")
            return None
        if any(not DEC_INT.match(k) or int(k) < 1 for k in ktoks):
            problems.add(checkpoint, "key", file=file, field=fid, line=lineno,
                         actual=attrs["key"], detail="key components must be positive integers")
            return None
        key = tuple(int(k) for k in ktoks)

    shape = []
    for tok in split_list(attrs["shape"]):
        if not DEC_INT.match(tok) or int(tok) < 0:
            problems.add(checkpoint, "syntax", file=file, field=fid, line=lineno,
                         detail=f"bad shape extent {tok}")
            return None
        shape.append(int(tok))
    dtype = attrs["dtype"]
    if dtype not in DTYPES:
        problems.add(checkpoint, "syntax", file=file, field=fid, line=lineno,
                     detail=f"unknown dtype {dtype}")
        return None
    if dtype != row["dtype"]:
        problems.add(checkpoint, "dtype", file=file, field=fid, line=lineno,
                     expected=row["dtype"], actual=dtype)
        return None

    toks = split_list(tail)
    if len(toks) != prod(shape):
        problems.add(checkpoint, "length", file=file, field=fid, line=lineno,
                     expected=prod(shape), actual=len(toks))
        return None
    values = decode_tokens(toks, dtype, fid, lineno, checkpoint, problems, file)
    if values is None:
        return None
    return Record(fid, key, shape, dtype, values, lineno)


def decode_tokens(toks, dtype, fid, lineno, checkpoint, problems: Problems, file) -> list | None:
    out = []
    for i, t in enumerate(toks):
        if dtype == "f64":
            if not HEX16.match(t):
                problems.add(checkpoint, "token", file=file, field=fid, line=lineno,
                             index=i + 1, actual=t, detail="f64 needs 16 hex digits")
                return None
            v = decode_f64(t)
            if not math.isfinite(v):
                problems.add(checkpoint, "nonfinite", file=file, field=fid, line=lineno,
                             index=i + 1, actual=("nan" if math.isnan(v) else
                                                  ("inf" if v > 0 else "-inf")))
                return None
            out.append(t.upper())
        elif dtype in INT_DTYPES:
            if not DEC_INT.match(t):
                problems.add(checkpoint, "token", file=file, field=fid, line=lineno,
                             index=i + 1, actual=t, detail="i32 needs a decimal integer")
                return None
            out.append(int(t))
        elif dtype == "str":
            if not t.startswith("x") or len(t) % 2 == 0 or not HEXBYTES.match(t[1:]):
                problems.add(checkpoint, "token", file=file, field=fid, line=lineno,
                             index=i + 1, actual=t, detail="str needs x + even-length hex")
                return None
            out.append(bytes.fromhex(t[1:]).decode("latin-1"))
        else:  # pragma: no cover - DTYPES is closed and every member is handled above
            problems.add(checkpoint, "syntax", file=file, field=fid, line=lineno,
                         detail=f"unsupported dtype {dtype}")
            return None
    return out


# --- checkpoint context -------------------------------------------------------------------
class Context:
    """Records of one checkpoint, falling back to the first checkpoint for nodfn / ids."""

    def __init__(self, records: dict[str, list[Record]], base: "Context | None" = None):
        self.records = records
        self.base = base

    def get(self, fid: str) -> list[Record] | None:
        r = self.records.get(fid)
        if r:
            return r
        return self.base.get(fid) if self.base else None

    def flat(self, fid: str) -> list | None:
        recs = self.get(fid)
        if not recs:
            return None
        if len(recs) == 1 and recs[0].key is None:
            return recs[0].values
        out = []
        for r in sorted(recs, key=lambda r: r.key):
            out.extend(r.values)
        return out

    def scalar(self, fid: str):
        v = self.flat(fid)
        return v[0] if v else None

    def groups(self, fid: str, sizes_field: str) -> list[list] | None:
        """Ragged field as a list per outer key: keyed records, else split by `sizes_field`."""
        recs = self.get(fid)
        if not recs:
            return None
        if any(r.key is not None for r in recs):
            return [r.values for r in sorted(recs, key=lambda r: r.key)]
        sizes = self.flat(sizes_field)
        if not sizes:
            return None
        flat, out, at = recs[0].values, [], 0
        for n in sizes:
            out.append(flat[at:at + n])
            at += n
        return out


# --- reconstruct recipes ------------------------------------------------------------------
def rc_active_flags(ctx: Context, row: dict, cp: str, problems: Problems):
    """derived.dof.active_flags(i) = merge(1, 0, lmdofn(i) /= 0)."""
    lm = ctx.flat("runtime.dof.lmdofn")
    if lm is None:
        problems.add(cp, "reconstruct", field=row["id"], detail="runtime.dof.lmdofn absent")
        return None
    return Record(row["id"], None, [len(lm)], "i32", [1 if v else 0 for v in lm], 0)


def rc_material_header(ctx: Context, row: dict, cp: str, problems: Problems):
    """sections.material_header(g) = element(group(g)%list(1))%matno."""
    groups = ctx.groups("mesh.sets.elset", "sections.elset_size")
    mat = ctx.flat("mesh.elements.material")
    if groups is None or mat is None:
        problems.add(cp, "reconstruct", field=row["id"],
                     detail="mesh.sets.elset / mesh.elements.material absent")
        return None
    out = []
    for g, lst in enumerate(groups):
        if not lst:
            problems.add(cp, "reconstruct", field=row["id"], group=g + 1, detail="empty elset")
            return None
        e = lst[0]
        if not 1 <= e <= len(mat):
            problems.add(cp, "reconstruct", field=row["id"], group=g + 1, actual=e,
                         detail="elset entry outside mesh.elements")
            return None
        out.append(mat[e - 1])
    return Record(row["id"], None, [len(out)], "i32", out, 0)


RECONSTRUCT = {"derived.dof.active_flags": rc_active_flags,
               "sections.material_header": rc_material_header}


def reconstruct_ids(mp: MapIndex) -> set[str]:
    return {r["id"] for r in mp.doc.get("field", []) if "reconstruct" in r}


# --- normalization ------------------------------------------------------------------------
def entity_labels(index_by: str, ext: int, ctx: Context) -> list:
    """Labels of the entities 1..ext behind `index_by`; legacy ordinals when unavailable."""
    if index_by == BOUNDARY_INDEX:
        sets = ctx.flat(BOUNDARY_SET)
        if sets is not None and len(sets) == ext:
            seen: dict[int, int] = {}
            out = []
            for s in sets:
                seen[s] = seen.get(s, 0) + 1
                out.append([s, seen[s]])
            return out
    prov = ID_PROVIDER.get(index_by)
    vals = ctx.flat(prov) if prov else None
    if vals is not None and len(vals) == ext:
        return list(vals)
    return list(range(1, ext + 1))


def dof_map(ctx: Context, cp: str, problems: Problems) -> list[list[int]] | None:
    """nodfn(cdofn,npoin) -> [[node,dof], ...] ordered by totv number; None on a violation."""
    recs = ctx.get("runtime.dof.nodfn")
    ntotv = ctx.scalar("runtime.dof.ntotv")
    if not recs or ntotv is None:
        problems.add(cp, "index_map", field="runtime.dof.nodfn",
                     detail="nodfn or runtime.dof.ntotv unavailable for (node,dof) re-keying")
        return None
    rec = recs[0]
    cdofn = rec.shape[0] if rec.shape else 0
    slot: dict[int, list[int]] = {}
    for i, t in enumerate(rec.values):
        if t == 0:
            continue
        node, dof = i // cdofn + 1, i % cdofn + 1
        if t < 1 or t > ntotv:
            problems.add(cp, "index_map", field="runtime.dof.nodfn",
                         detail=f"t={t} outside 1..{ntotv}")
            return None
        if t in slot:
            problems.add(cp, "index_map", field="runtime.dof.nodfn", detail=f"t={t} hit 2x")
            return None
        slot[t] = [node, dof]
    if len(slot) != ntotv:
        problems.add(cp, "index_map", field="runtime.dof.nodfn",
                     detail=f"{len(slot)} numbered dofs for ntotv={ntotv}")
        return None
    return [slot[t] for t in range(1, ntotv + 1)]


def build_entry(row: dict, recs: list[Record], ctx: Context, cp: str, mp: MapIndex,
                dofs: list[list[int]] | None, problems: Problems) -> dict | None:
    keyed = any(r.key is not None for r in recs)
    index_by = row["index_by"]
    if keyed:
        recs = sorted(recs, key=lambda r: r.key)
        raw = [list(r.key) for r in recs]
        labels = entity_labels(index_by, max(k[0] for k in raw), ctx)
        entry = {"dtype": row["dtype"], "shape": None, "index_by": index_by,
                 "keys": [k[0] if len(k) == 1 else k for k in raw],
                 "ids": [labels[k[0] - 1] if len(k) == 1 else [labels[k[0] - 1]] + k[1:]
                         for k in raw],
                 "values": [nest(r.values, r.shape) for r in recs]}
    else:
        rec = recs[0]
        if row["shape"] == NTOTV_SHAPE:
            if dofs is None:
                return None
            if len(rec.values) != len(dofs):
                problems.add(cp, "index_map", field=row["id"], line=rec.line,
                             expected=len(dofs), actual=len(rec.values))
                return None
            return {"dtype": row["dtype"], "shape": list(rec.shape), "index_by": NTOTV_INDEX,
                    "ids": [list(p) for p in dofs], "values": list(rec.values)}
        entry = {"dtype": row["dtype"], "shape": list(rec.shape), "index_by": index_by,
                 "values": nest(rec.values, rec.shape)}
        if index_by != "component" and rec.shape:
            entry["ids"] = entity_labels(index_by, rec.shape[-1], ctx)
    if MapIndex.rule(row) == "hash":
        entry["sha256"] = sha256_bytes(
            f'{entry["dtype"]}|{dumps(entry["shape"])}|{dumps(entry.get("ids"))}|'
            f'{dumps(entry["values"])}'.encode("utf-8"))
    return entry


def build_checkpoint(cp: str, records: dict[str, list[Record]], mp: MapIndex,
                     problems: Problems, base: Context | None = None) -> tuple[dict, Context]:
    """{snapshot json name: envelope} for one checkpoint, plus its context for later ones."""
    ctx = Context(records, base)
    for fid, fn in RECONSTRUCT.items():
        row = mp.fields.get(fid)
        if row is None or row["checkpoint"] != cp or "reconstruct" not in row:
            continue
        if fid in records:
            # the solver emitted the row through an adapter: keep its values, but hold the
            # recipe against them whenever the recipe's own inputs are available
            check = Problems()
            rec = fn(ctx, row, cp, check)
            got = ctx.flat(fid)
            if rec is not None and not check and list(rec.values) != list(got or []):
                problems.add(cp, "reconstruct", field=fid, expected=rec.values[:8],
                             actual=(got or [])[:8], detail="dumped value differs from the recipe")
            continue
        rec = fn(ctx, row, cp, problems)
        if rec is not None:
            records[fid] = [rec]
    dofs = None
    if any(r["shape"] == NTOTV_SHAPE and mp.rule(r) != "ignore" and r["id"] in records
           for r in mp.by_cp.get(cp, [])):
        dofs = dof_map(ctx, cp, problems)
        if dofs is None:
            for r in mp.by_cp.get(cp, []):
                if r["shape"] == NTOTV_SHAPE and mp.rule(r) != "ignore" and r["id"] in records:
                    problems.add(cp, "index_map", field=r["id"],
                                 detail="not re-keyed: nodfn is not a bijection onto 1..ntotv")
    files = {}
    for name in SNAPSHOT_FILES:
        files[SIDECAR.get(name, name)] = {}
    for row in mp.by_cp.get(cp, []):
        recs = records.get(row["id"])
        if not recs or mp.rule(row) == "ignore":
            continue
        entry = build_entry(row, recs, ctx, cp, mp, dofs, problems)
        if entry is not None:
            files[SIDECAR.get(row["snapshot_file"], row["snapshot_file"])][row["id"]] = entry
    out = {}
    for name, fields in files.items():
        out[name] = {"schema": SCHEMA, "checkpoint": cp, "file": name,
                     "float_format": FLOAT_FORMAT, "map_sha256": mp.sha256 or "",
                     "fields": fields}
    return out, ctx


def normalize_text(text: str, checkpoint: str, mp: MapIndex | None = None,
                   base: Context | None = None) -> tuple[dict, list[str], Context]:
    """One checkpoint, string in: ({json name: envelope}, problems, context)."""
    mp = mp or MapIndex.load(MAP_DEFAULT)
    problems = Problems()
    records = parse_state_text(text, checkpoint, mp, problems)
    files, ctx = build_checkpoint(checkpoint, records, mp, problems, base)
    return files, list(problems), ctx


def render_tree(tree: dict[str, dict[str, dict]]) -> dict[str, bytes]:
    """{checkpoint: {json name: envelope}} -> {relative path: exact bytes}, digests included."""
    out: dict[str, bytes] = {}
    for cp, files in tree.items():
        for name, env in files.items():
            out[f"{cp}/{name}"] = (dumps(env) + "\n").encode("utf-8")
        for digest, sibling in SIDECAR.items():
            body = out[f"{cp}/{sibling}"]
            out[f"{cp}/{digest}"] = f"{sha256_bytes(body)}  {sibling}\n".encode("utf-8")
    return out


def fingerprint_of(blobs: dict[str, bytes]) -> tuple[str, dict[str, dict[str, str]]]:
    per: dict[str, dict[str, str]] = {}
    for rel, body in blobs.items():
        cp, _, name = rel.rpartition("/")
        per.setdefault(cp, {})[name] = sha256_bytes(body)
    joined = "".join(sorted(f"{rel}:{sha256_bytes(body)}\n" for rel, body in blobs.items()))
    return sha256_bytes(joined.encode("utf-8")), per


def normalize(raw_dir, out_dir, map_path=None, quiet: bool = True,
              expect_checkpoints: list | None = None) -> dict:
    """Parse `raw_dir`, write the canonical tree into `out_dir`; nothing is written on failure."""
    raw_dir, out_dir = Path(raw_dir), Path(out_dir)
    mp = map_path if isinstance(map_path, MapIndex) else MapIndex.load(map_path or MAP_DEFAULT)
    problems = Problems()
    tree, counts, raws = {}, {}, {}
    base = None
    # `expect_checkpoints` narrows WHICH checkpoints must be present; it changes nothing
    # else. Default (None) is every covered checkpoint, exactly as before.
    #
    # WHY IT EXISTS. "All covered checkpoints must be present" is a property of the
    # PRODUCER, not of the format. It is right for the solver, which emits all three. It
    # is wrong by construction for M4-01's shadow binary, which runs no solve and so
    # emits model_ready alone -- emitting an empty phase_ready would be manufacturing
    # evidence, and its module header says so. Because normalize writes nothing on
    # failure, that binary's complete 162-row model_ready snapshot was being discarded
    # and yl_shadow_diff reported all 380 rows UNVERIFIED. (Found by dev-fold2 the first
    # time the fold made a full snapshot producible, 2026-09-09.)
    #
    # THE NARROWING IS SAFE ONLY BECAUSE IT MOVES A CHECK, NOT BECAUSE IT DROPS ONE.
    # The caller that narrows must still decide what a missing checkpoint means; in
    # yl_shadow_diff the absent ones become UNVERIFIED, never MATCH. Every malformed-
    # content check below is untouched: a checkpoint that IS present is parsed exactly as
    # strictly as before, whether or not it was named here.
    want = list(mp.order) if expect_checkpoints is None else list(expect_checkpoints)
    unknown = [cp for cp in want if cp not in mp.order]
    if unknown:
        for cp in unknown:
            problems.add(cp, "unknown-checkpoint", expected="a covered checkpoint of the map",
                         actual="not in the map", detail=f"--expect names {cp!r}")
    for cp in mp.order:
        d = raw_dir / sanitize(cp)
        if not d.is_dir():
            d = raw_dir / cp
        path = d / "state.txt"
        if not path.is_file():
            if cp in want:
                problems.add(cp, "missing", file=str(path.name), expected="present",
                             actual="absent", detail=f"no state.txt under {d}")
            continue
        body = path.read_bytes()
        text = body.decode("latin-1")
        records = parse_state_text(text, cp, mp, problems)
        files, ctx = build_checkpoint(cp, records, mp, problems, base)
        base = base or ctx
        tree[cp] = files
        counts[cp] = sum(len(f["fields"]) for f in files.values())
        raws[cp] = {"raw_file": f"{d.name}/state.txt", "raw_bytes": len(body),
                    "raw_sha256": sha256_bytes(body), "fields": counts[cp]}
    blobs = render_tree(tree)
    fp, per_file = fingerprint_of(blobs)
    result = {"ok": not problems, "problems": list(problems), "map": mp.map_ref(),
              "dump_dir": str(raw_dir), "normalized_dir": str(out_dir),
              "checkpoints": raws, "fingerprint": fp if not problems else None,
              "fields": sum(counts.values())}
    if problems:
        return result
    manifest = {"schema": SCHEMA, "normalizer": NORMALIZER, "map": mp.map_ref(),
                "checkpoints": per_file, "fingerprint": fp}
    tmp = Path(tempfile.mkdtemp(prefix=".yl_state.", dir=str(out_dir.parent if out_dir.parent.is_dir()
                                                             else Path.cwd())))
    try:
        for rel, blob in blobs.items():
            p = tmp / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(blob)
        (tmp / "fingerprint.json").write_bytes((dumps(manifest) + "\n").encode("utf-8"))
        if out_dir.exists():
            shutil.rmtree(out_dir)
        out_dir.parent.mkdir(parents=True, exist_ok=True)
        tmp.replace(out_dir)
    finally:
        if tmp.exists():
            shutil.rmtree(tmp, ignore_errors=True)
    return result


# --- CLI ----------------------------------------------------------------------------------
def load_map_index(path) -> MapIndex | None:
    try:
        return MapIndex.load(path)
    except (OSError, tomllib.TOMLDecodeError, KeyError) as e:
        print(f"FAIL problems=1\n  map {path}: {e}")
        return None


def cmd_normalize(a) -> int:
    mp = load_map_index(a.map)
    if mp is None:
        return 3
    raw = Path(a.raw_dir)
    out = Path(a.output) if a.output else raw.parent.parent / "state"
    expect = [c.strip() for c in a.expect_checkpoints.split(",")] \
        if a.expect_checkpoints else None
    res = normalize(raw, out, mp, expect_checkpoints=expect)
    if not res["ok"]:
        if not a.quiet:
            for p in res["problems"][:200]:
                print("  " + p)
        print(f"FAIL problems={len(res['problems'])}")
        return 1
    print(f"PASS checkpoints={len(res['checkpoints'])} fields={res['fields']} "
          f"fingerprint={res['fingerprint'][:12]}")
    return 0


def cmd_fingerprint(a) -> int:
    d = Path(a.dir)
    fp_file = d / "fingerprint.json"
    if fp_file.is_file():
        doc = json.loads(fp_file.read_text(encoding="utf-8"))
        blobs = {}
        for cp, files in doc["checkpoints"].items():
            for name in files:
                p = d / cp / name
                if not p.is_file():
                    print(f"  STRUCT stage={cp} file={name} problem=missing\nFAIL problems=1")
                    return 1
                blobs[f"{cp}/{name}"] = p.read_bytes()
        fp, _ = fingerprint_of(blobs)
        ok = fp == doc["fingerprint"]
        if not ok:
            print(f"  recorded={doc['fingerprint']} recomputed={fp}\nFAIL problems=1")
            return 1
        print(f"PASS fingerprint={fp} checkpoints={len(doc['checkpoints'])} source=normalized")
        return 0
    mp = load_map_index(a.map)
    if mp is None:
        return 3
    with tempfile.TemporaryDirectory() as tmp:
        res = normalize(d, Path(tmp) / "state", mp)
    if not res["ok"]:
        for p in res["problems"][:200]:
            print("  " + p)
        print(f"FAIL problems={len(res['problems'])}")
        return 1
    print(f"PASS fingerprint={res['fingerprint']} checkpoints={len(res['checkpoints'])} source=raw")
    return 0


# --- selftest fixtures --------------------------------------------------------------------
def f64(v: float) -> str:
    return struct.pack(">d", v).hex().upper()


def s(text: str) -> str:
    return "x" + text.encode("latin-1").hex()


def field_row(fid, shape, dtype, index_by, snapshot_file, rule="exact", **extra) -> dict:
    row = {"id": fid, "checkpoint": "model_ready", "shape": shape, "dtype": dtype,
           "index_by": index_by, "snapshot_file": snapshot_file, "compare": {"rule": rule}}
    if rule == "hash":
        row["compare"]["algo"] = "sha256"
    row.update(extra)
    return row


def self_map() -> MapIndex:
    """A 20-row map covering the five shape families, both reconstruct recipes and hashing."""
    doc = {
        "version": 1, "float_format": "hex",
        "shape_symbols": {"ndimn": "2", "npoin": "3", "nelem": "2", "nnode": "2", "ngaus": "1",
                          "ngroup": "2", "nmats": "1", "cdofn": "2", "mdofn": "2", "ntotv": "6", "nfdof": "2", "nrfields": "1",
                          "ndofix": "3", "nelgroup": "elements per group (ragged over groups)"},
        "checkpoint": [{"id": "model_ready", "order": 1, "covered": True,
                        "snapshot_files": list(SNAPSHOT_FILES)}],
        "field": [
            field_row("control.run.ndimn", [], "i32", "component", "control.json"),
            field_row("mesh.nodes.id", ["npoin"], "i32", "mesh.nodes[].id", "mesh.sha256"),
            field_row("mesh.nodes.xyz", ["ndimn", "npoin"], "f64", "mesh.nodes[].id", "mesh.sha256"),
            field_row("mesh.elements.id", ["nelem"], "i32", "mesh.elements[].id", "mesh.sha256"),
            field_row("mesh.elements.material", ["nelem"], "i32", "mesh.elements[].id", "mesh.sha256"),
            field_row("runtime.gauss.cartd", ["ndimn", "nnode", "ngaus", "nelem"], "f64",
                      "mesh.elements[].id", "mesh.sha256", rule="abs_tol"),
            field_row("sections.name", ["ngroup"], "str", "sections[].name", "groups.json"),
            field_row("sections.elset_size", ["ngroup"], "i32", "sections[].name", "groups.json"),
            field_row("mesh.sets.elset", ["nelgroup", "ngroup"], "i32", "sections[].name",
                      "groups.json"),
            field_row("sections.material_header", ["ngroup"], "i32", "sections[].name",
                      "groups.json", reconstruct="material_header(igroup) = "
                      "element(group(igroup)%list(1))%matno"),
            field_row("sections.dof_list", ["nfdof", "nrfields", "ngroup"], "i32",
                      "sections[].name", "groups.json"),
            field_row("materials.id", ["nmats"], "i32", "materials[].id", "materials.json"),
            field_row("materials.name", ["nmats"], "str", "materials[].id", "materials.json"),
            field_row("runtime.dof.nodfn", ["cdofn", "npoin"], "i32", "component", "dof.sha256",
                      rule="hash"),
            field_row("runtime.dof.ntotv", [], "i32", "component", "dof.sha256"),
            field_row("runtime.dof.lmdofn", ["mdofn"], "i32", "component", "dof.sha256"),
            field_row("derived.dof.active_flags", ["mdofn"], "i32", "component", "dof.sha256",
                      reconstruct="active_flags(idofn) = merge(1, 0, lmdofn(idofn) /= 0)"),
            field_row("runtime.dof.iffix", ["ntotv"], "i32", "component", "dof.sha256"),
            field_row("runtime.vectors.tofor", ["ntotv"], "f64", "component", "dof.sha256"),
            field_row("runtime.vectors.deltafi", ["ntotv"], "f64", "component", "dof.sha256",
                      rule="ignore", reason="increment scratch"),
            field_row("steps0.boundary.set", ["ndofix"], "i32", BOUNDARY_INDEX,
                      "constraints.sha256"),
            field_row("steps0.boundary.nodes", ["ndofix"], "i32", BOUNDARY_INDEX,
                      "constraints.sha256"),
            field_row("steps0.boundary.value", ["ndofix"], "f64", BOUNDARY_INDEX,
                      "constraints.sha256"),
        ]}
    return MapIndex(doc, Path("<selftest>"), sha256_bytes(dumps(doc).encode("utf-8")))


def self_lines() -> list[str]:
    """A well-formed model_ready dump in the writer's syntax: `key=[]` is the dense marker,
    a non-empty key holds the outermost dimensions first, values are bracketed.
    3 nodes, 2 elements, 2 elsets, 1 material, 6 dofs."""
    def vals(*toks) -> str:
        return "values=[" + ",".join(str(v) for v in toks) + "]"
    return [
        "field=control.run.ndimn key=[] shape=[] dtype=i32 " + vals(2),
        "field=mesh.nodes.id key=[] shape=[3] dtype=i32 " + vals(1, 2, 3),
        "field=mesh.nodes.xyz key=[] shape=[2,3] dtype=f64 order=F "
        + vals(f64(0.0), f64(0.0), f64(20.0), f64(0.0), f64(20.0), f64(10.0)),
        "field=mesh.elements.id key=[] shape=[2] dtype=i32 " + vals(11, 12),
        "field=mesh.elements.material key=[] shape=[2] dtype=i32 " + vals(7, 7),
        "field=runtime.gauss.cartd key=[] shape=[2,2,1,2] dtype=f64 order=F "
        + vals(*(f64(v) for v in (-0.5, -0.5, 0.5, -0.5, -0.25, 0.25, 0.75, 1.25))),
        f"field=sections.name key=[] shape=[2] dtype=str values=[{s('FRAME')},{s('SKIN')}]",
        "field=sections.elset_size key=[] shape=[2] dtype=i32 " + vals(1, 1),
        "field=sections.dof_list key=[1,1] shape=[2] dtype=i32 " + vals(1, 2),
        "field=sections.dof_list key=[2,1] shape=[2] dtype=i32 " + vals(1, 2),
        "field=mesh.sets.elset key=[1] shape=[1] dtype=i32 " + vals(1),
        "field=mesh.sets.elset key=[2] shape=[1] dtype=i32 " + vals(2),
        "field=materials.id key=[] shape=[1] dtype=i32 " + vals(7),
        f"field=materials.name key=[] shape=[1] dtype=str values=[{s('')}]",
        "field=runtime.dof.nodfn key=[] shape=[2,3] dtype=i32 order=F " + vals(1, 2, 3, 4, 5, 6),
        "field=runtime.dof.ntotv key=[] shape=[] dtype=i32 " + vals(6),
        "field=runtime.dof.lmdofn key=[] shape=[2] dtype=i32 " + vals(1, 2),
        "field=runtime.dof.iffix key=[] shape=[6] dtype=i32 " + vals(1, 1, 0, 0, 0, 0),
        "field=runtime.vectors.tofor key=[] shape=[6] dtype=f64 "
        + vals(*(f64(v) for v in (0.0, 0.0, 0.0, 0.0, 1.5, -2.5))),
        "field=steps0.boundary.set key=[] shape=[3] dtype=i32 " + vals(1, 1, 2),
        "field=steps0.boundary.nodes key=[] shape=[3] dtype=i32 " + vals(1, 2, 3),
        "field=steps0.boundary.value key=[] shape=[3] dtype=f64 "
        + vals(*(f64(v) for v in (0.0, 0.0, 0.001))),
    ]


MATERIAL_HEADER = "field=sections.material_header key=[] shape=[2] dtype=i32 values=[%d,%d]"


def n_fields(lines: list[str]) -> int:
    return len({ln.split()[0][len("field="):] for ln in lines})


def wire(lines: list[str], checkpoint: str = "model_ready",
         declared: int | None = None, trailer: int | None = None) -> str:
    n = n_fields(lines) if declared is None else declared
    t = n if trailer is None else trailer
    return "\n".join([f"HSTAR_STATE schema={SCHEMA} checkpoint={checkpoint} fields={n}"]
                     + lines + [f"HSTAR_STATE_END fields={t}", ""])


def replace_line(lines: list[str], fid: str, new: str | None) -> list[str]:
    out = []
    for ln in lines:
        if ln.startswith(f"field={fid} ") and new is not None:
            out.append(new)
        elif not ln.startswith(f"field={fid} "):
            out.append(ln)
    return out


def build_fixture(mp: MapIndex | None = None) -> dict[str, dict[str, dict]]:
    """The synthetic normalized tree, for the yl_state_diff.py selftest: {cp: {json name: obj}}."""
    mp = mp or self_map()
    files, problems, _ = normalize_text(wire(self_lines()), "model_ready", mp)
    if problems:  # pragma: no cover - the fixture is well-formed by construction
        raise AssertionError("build_fixture: " + "; ".join(problems))
    return {"model_ready": files}


# --- selftest -----------------------------------------------------------------------------
NEGATIVES = [
    ("header", lambda ls: ("HSTAR_STATE schema=2 checkpoint=model_ready fields=20\n"
                           + "\n".join(ls) + "\nHSTAR_STATE_END fields=20\n")),
    ("truncated", lambda ls: wire(ls, trailer=n_fields(ls) - 1)),
    ("extra", lambda ls: wire(ls + ["field=mesh.nodes.bogus key=[] shape=[] dtype=i32 "
                                    "values=[1]"])),
    ("duplicate_record", lambda ls: wire(ls + ["field=mesh.sets.elset key=[2] shape=[1] "
                                               "dtype=i32 values=[2]"])),
    ("missing", lambda ls: wire(replace_line(ls, "materials.id", None))),
    ("dtype", lambda ls: wire(replace_line(ls, "materials.id",
                                           "field=materials.id key=[] shape=[1] dtype=f64 "
                                           f"values=[{f64(7.0)}]"))),
    ("rank", lambda ls: wire(replace_line(ls, "mesh.nodes.xyz",
                                          "field=mesh.nodes.xyz key=[] shape=[6] dtype=f64 "
                                          "values=[" + ",".join([f64(0.0)] * 6) + "]"))),
    ("length", lambda ls: wire(replace_line(ls, "mesh.nodes.id",
                                            "field=mesh.nodes.id key=[] shape=[3] dtype=i32 "
                                            "values=[1,2]"))),
    ("token", lambda ls: wire(replace_line(ls, "steps0.boundary.value",
                                           "field=steps0.boundary.value key=[] shape=[3] "
                                           "dtype=f64 values=[00000000000000," + f64(0.0)
                                           + "," + f64(1.0) + "]"))),
    ("nonfinite", lambda ls: wire(replace_line(ls, "steps0.boundary.value",
                                               "field=steps0.boundary.value key=[] shape=[3] "
                                               "dtype=f64 values=[7FF8000000000000," + f64(0.0)
                                               + "," + f64(1.0) + "]"))),
    ("key", lambda ls: wire(replace_line(ls, "runtime.dof.ntotv",
                                         "field=runtime.dof.ntotv key=[1] shape=[] dtype=i32 "
                                         "values=[6]"))),
    ("syntax", lambda ls: wire(ls[:-1] + ["field=steps0.boundary.value key=[] shape=[3] "
                                          "dtype=f64"])),
    ("index_map", lambda ls: wire(replace_line(ls, "runtime.dof.nodfn",
                                               "field=runtime.dof.nodfn key=[] shape=[2,3] "
                                               "dtype=i32 values=[1,2,3,4,5,5]"))),
    ("reconstruct", lambda ls: wire(replace_line(ls, "mesh.sets.elset", None)
                                    + ["field=mesh.sets.elset key=[1] shape=[2] dtype=i32 "
                                       "values=[1,2]",
                                       "field=mesh.sets.elset key=[2] shape=[0] dtype=i32 "
                                       "values=[]"])),
]


def selftest() -> int:
    mp = self_map()
    ok = 0
    total = 0

    def check(name: str, cond: bool, detail: str = "") -> None:
        nonlocal ok, total
        total += 1
        ok += int(bool(cond))
        print(("ok   " if cond else "BAD  ") + name + (f": {detail}" if detail else ""))

    files, problems, ctx = normalize_text(wire(self_lines()), "model_ready", mp)
    check("good fixture normalizes clean", not problems, "; ".join(problems[:3]))

    # --- the five shape families -------------------------------------------------------
    fs = {name: env["fields"] for name, env in files.items()}
    check("family scalar/component",
          fs["control.json"]["control.run.ndimn"] ==
          {"dtype": "i32", "shape": [], "index_by": "component", "values": 2},
          dumps(fs["control.json"].get("control.run.ndimn")))
    xyz = fs["mesh.json"]["mesh.nodes.xyz"]
    check("family dense 2-D entity-keyed",
          xyz["ids"] == [1, 2, 3] and xyz["shape"] == [2, 3] and
          xyz["values"][1] == [f64(20.0), f64(0.0)], dumps(xyz))
    cartd = fs["mesh.json"]["runtime.gauss.cartd"]
    check("family per-element 4-D nesting",
          cartd["ids"] == [11, 12] and len(cartd["values"]) == 2 and
          len(cartd["values"][0]) == 1 and len(cartd["values"][0][0]) == 2 and
          cartd["values"][1][0][1] == [f64(0.75), f64(1.25)], dumps(cartd)[:160])
    elset = fs["groups.json"]["mesh.sets.elset"]
    check("family ragged set-keyed",
          elset == {"dtype": "i32", "shape": None, "index_by": "sections[].name",
                    "keys": [1, 2], "ids": ["FRAME", "SKIN"], "values": [[1], [2]]},
          dumps(elset))
    iffix = fs["dof.json"]["runtime.dof.iffix"]
    check("family ntotv re-keyed",
          iffix == {"dtype": "i32", "shape": [6], "index_by": NTOTV_INDEX,
                    "ids": [[1, 1], [1, 2], [2, 1], [2, 2], [3, 1], [3, 2]],
                    "values": [1, 1, 0, 0, 0, 0]}, dumps(iffix))
    check("boundary ids are [set, record]",
          fs["constraints.json"]["steps0.boundary.value"]["ids"] == [[1, 1], [1, 2], [2, 1]],
          dumps(fs["constraints.json"]["steps0.boundary.value"]))
    check("ignore rows are not normalized", "runtime.vectors.deltafi" not in fs["dof.json"])
    check("hash rows carry sha256 and full values",
          fs["dof.json"]["runtime.dof.nodfn"]["values"] == [[1, 2], [3, 4], [5, 6]] and
          len(fs["dof.json"]["runtime.dof.nodfn"]["sha256"]) == 64)
    check("reconstruct: derived.dof.active_flags",
          fs["dof.json"]["derived.dof.active_flags"]["values"] == [1, 1])
    check("reconstruct: sections.material_header",
          fs["groups.json"]["sections.material_header"]["values"] == [7, 7])
    check("str decoding incl. the empty string",
          fs["materials.json"]["materials.name"]["values"] == [""])
    dense = [ln for ln in self_lines() if "key=[]" in ln]
    check("key=[] is the dense marker, not a key",
          len(dense) == len(self_lines()) - 4 and
          all("key=[" in ln for ln in self_lines()) and
          "keys" not in fs["control.json"]["control.run.ndimn"] and
          "keys" not in fs["mesh.json"]["mesh.nodes.xyz"] and
          fs["mesh.json"]["mesh.nodes.xyz"]["shape"] == [2, 3])
    dof_list = fs["groups.json"]["sections.dof_list"]
    check("multi-dimensional key: outermost dimension first",
          dof_list == {"dtype": "i32", "shape": None, "index_by": "sections[].name",
                       "keys": [[1, 1], [2, 1]],
                       "ids": [["FRAME", 1], ["SKIN", 1]], "values": [[1, 2], [1, 2]]},
          dumps(dof_list))
    ok_dump, probs_ok, _ = normalize_text(wire(self_lines() + [MATERIAL_HEADER % (7, 7)]),
                                          "model_ready", mp)
    check("a dumped reconstruct row is kept and agrees with the recipe",
          not probs_ok and
          ok_dump["groups.json"]["fields"]["sections.material_header"]["values"] == [7, 7],
          "; ".join(probs_ok[:1]))
    _, probs_bad, _ = normalize_text(wire(self_lines() + [MATERIAL_HEADER % (9, 9)]),
                                     "model_ready", mp)
    check("a dumped reconstruct row that contradicts the recipe fails",
          any("problem=reconstruct" in p for p in probs_bad), "; ".join(probs_bad[:1]))
    check("all nine snapshot names present per checkpoint",
          sorted(files) == sorted({SIDECAR.get(n, n) for n in SNAPSHOT_FILES}))

    # --- reconstruct table matches the authoritative map --------------------------------
    check("reconstruct table matches the fixture map", set(RECONSTRUCT) == reconstruct_ids(mp))
    if MAP_DEFAULT.is_file():
        real = MapIndex.load(MAP_DEFAULT)
        check("reconstruct table matches docs/m2/state-field-map.toml",
              set(RECONSTRUCT) == reconstruct_ids(real),
              f"table={sorted(RECONSTRUCT)} map={sorted(reconstruct_ids(real))}")
        check("map compare rules are the yl_state_map vocabulary",
              {MapIndex.rule(r) for r in real.doc["field"]} <= COMPARE_RULES)
    else:  # pragma: no cover - the map is committed
        check("docs/m2/state-field-map.toml present", False, str(MAP_DEFAULT))

    # --- every parser error class -------------------------------------------------------
    for code, mutate in NEGATIVES:
        _, probs, _ = normalize_text(mutate(self_lines()), "model_ready", mp)
        hit = next((p for p in probs if f"problem={code}" in p), None)
        check(f"negative {code}", hit is not None and (code == "extra" or probs[0] == hit),
              hit or "; ".join(probs[:2]) or "no problem reported")

    # --- checkpoint identity ------------------------------------------------------------
    _, probs, _ = normalize_text(wire(self_lines(), checkpoint="phase_ready(1)"),
                                 "model_ready", mp)
    check("negative wrong checkpoint in the header",
          any("problem=header" in p for p in probs), "; ".join(probs[:1]))

    # --- normalize on disk: clean tree, fingerprint, byte-for-byte idempotence -----------
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        raw = root / "work" / "state" / "model_ready"
        raw.mkdir(parents=True)
        (raw / "state.txt").write_text(wire(self_lines()), encoding="latin-1")
        r1 = normalize(raw.parent, root / "a", mp)
        r2 = normalize(raw.parent, root / "b", mp)
        check("normalize writes a clean tree", r1["ok"], "; ".join(r1["problems"][:2]))
        a = {p.relative_to(root / "a"): p.read_bytes() for p in (root / "a").rglob("*") if p.is_file()}
        b = {p.relative_to(root / "b"): p.read_bytes() for p in (root / "b").rglob("*") if p.is_file()}
        check("normalize is byte-for-byte idempotent",
              a == b and r1["fingerprint"] == r2["fingerprint"] and r1["fingerprint"])
        check("13 files per checkpoint + fingerprint.json", len(a) == 14, str(sorted(map(str, a))))
        digest = (root / "a" / "model_ready" / "mesh.sha256").read_text(encoding="utf-8")
        body = (root / "a" / "model_ready" / "mesh.json").read_bytes()
        check("sidecar digests the sibling json bytes",
              digest == f"{sha256_bytes(body)}  mesh.json\n", digest.strip())
        fp = json.loads((root / "a" / "fingerprint.json").read_text(encoding="utf-8"))
        check("fingerprint.json records every file",
              fp["fingerprint"] == r1["fingerprint"] and
              len(fp["checkpoints"]["model_ready"]) == 13)
        check("fingerprint sub-command verifies a normalized tree",
              cmd_fingerprint(argparse.Namespace(dir=str(root / "a"), map=str(MAP_DEFAULT))) == 0)
        # a failing normalize must leave the destination untouched
        (raw / "state.txt").write_text(wire(replace_line(self_lines(), "materials.id", None)),
                                       encoding="latin-1")
        r3 = normalize(raw.parent, root / "c", mp)
        check("fail-closed: nothing written on a problem",
              not r3["ok"] and not (root / "c").exists(), "; ".join(r3["problems"][:1]))

    print(f"SELFTEST {'PASS' if ok == total else 'FAIL'}: {ok}/{total} expectations")
    return 0 if ok == total else 1


def main(argv=None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv[:1] == ["--selftest"]:
        return selftest()
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("normalize", help="raw state dump -> canonical JSON tree")
    p.add_argument("raw_dir", help="<work>/state, holding one directory per checkpoint")
    p.add_argument("-o", "--output", default=None, help="output tree (default RAW_DIR/../../state)")
    p.add_argument("--case-id", default=None, help="recorded by the caller; not part of any digest")
    p.add_argument("--quiet", action="store_true", help="only the PASS/FAIL line")
    p.add_argument("--expect-checkpoints", default=None, metavar="A,B",
                   help="comma-separated checkpoints that MUST be present. Default: every "
                        "covered checkpoint of the map. Narrows only the presence check -- a "
                        "checkpoint that IS present is parsed exactly as strictly either way. "
                        "For a producer that by design emits a subset (M4-01's shadow binary "
                        "runs no solve and emits model_ready alone); the CALLER then owns what "
                        "an absent checkpoint means, and yl_shadow_diff makes it UNVERIFIED.")
    p.set_defaults(func=cmd_normalize)
    p = sub.add_parser("fingerprint", help="fingerprint of a normalized (or raw) state tree")
    p.add_argument("dir")
    p.set_defaults(func=cmd_fingerprint)
    for q in (sub.choices["normalize"], sub.choices["fingerprint"]):
        q.add_argument("--map", default=str(MAP_DEFAULT))
    a = ap.parse_args(argv)
    return a.func(a)


if __name__ == "__main__":
    sys.exit(main())
