#!/usr/bin/env python3
"""Checkpoint x state-field map tooling for the legacy YL solver (M2-01).

Sub-commands
  check     validate docs/m2/state-field-map.toml against the M1 reader
            inventory (docs/m1/reader-inventory.toml) and the legacy sources
            (legacy/yl): vocabularies, anchors, reverse reader coverage,
            legacy symbols, consumers, compare rules, checkpoint placement,
            S03 perturbation targets; fail-closed (FAIL: n problems, exit 1)
  render    state-field-map.toml -> deterministic Markdown (stdout or -o); fail-closed: the
            full check runs first and on FAIL nothing is written (exit 1) unless --force
            (writes, still exits 1)
  --selftest  run the built-in bad/good samples through every check rule

Usage
  python3 tools/yl_state_map.py check [--map docs/m2/state-field-map.toml]
                                      [--inventory docs/m1/reader-inventory.toml]
                                      [--src legacy/yl]
  python3 tools/yl_state_map.py render [--map ...] [-o docs/m2/state-field-map.md] [--force]
  python3 tools/yl_state_map.py --selftest

Check rules (numbered as in .ccg/tasks/m2-01-state-field-map/analysis-schema.md §5)
   1 TOML parses; version == 1; cases non-empty; reader_inventory loads; float_format present
   2 checkpoint ids unique + in vocabulary; order strictly increasing; covered=false needs
     reason; covered=true needs site/anchor/after/first_consumer/snapshot_files (subset of the
     nine snapshot names) and at least one field
   3 anchor: site file in SOURCES and present, line exists, 12-hex anchor hash equals
     anchor_hash(full_statement(line)) ("source changed?" on drift); anchor_stmt is optional
     and, when present, must equal the whitespace/case-normalized statement; every `after`
     line is in the same routine and precedes the anchor, first_consumer greps as a routine
   4 field ids unique, match ^[a-z][a-z0-9]*(\\.[A-Za-z0-9_]+)+$, first segment in
     {case, mesh, materials, sections, amplitudes, interactions, steps<n>, solver, runtime,
     derived, control, output}
   5 field.checkpoint names a covered checkpoint
   6 source: reader ids exist in the inventory, are not reached_only and have executed_by;
     a single derived:<rule> (count|index_map|renumber|legacy_default|dof_expand) needs a
     non-empty, resolvable derived_from
   7 reverse coverage: every executed reader whose state_target is not a skip class
     (title_skip, empty_section, unused_switch) is referenced by >= 1 field source;
     warning only: each per-field ProblemState target of such a reader has an owner prefix
   8 legacy_symbol = <module>.<var>[%comp...] or <module>.<routine>.<var>[%comp...] for
     routine-local variables (e.g. prescribed.prescrib_set.list_fix): module found
     (case-insensitive), var declared between `module` and `contains`/`end module` (or inside
     the routine); the %comp chain is walked through the declared types: var must be
     `type(T0)`, %c1 must be a component of `type T0 ... end type` (searched in every source
     file, e.g. element_lib lives in Elements.f90), its own `type(T1)` gives the block for
     %c2, and so on; an intrinsic-typed entity ends the chain (a further %x FAILs)
   9 consumers non-empty; each greps as subroutine/function/program in legacy/yl
  10 shape symbols declared in [shape_symbols] or integer literals; dtype, unit, owner,
     determinism in vocabulary; non-float dtypes use unit 1 or id
  11 owner path matches the ADR-0003 regex (optional `[]` after the first segment); not_migrated needs reason; RuntimeState.* needs
     derived_from (resolvable)
  12 compare.rule in exact|abs_tol|rel_tol|hash|ignore; tolerance rules need positive
     atol/rtol, basis, and owner derived or RuntimeState.*; hash needs algo="sha256";
     ignore needs reason; non-deterministic fields use ignore or hash (order_dependent may be
     exact when compare.sorted_by is given)
  13 snapshot_file in the checkpoint's snapshot_files
  14 [[perturbation]]: case in cases, field exists, owner ProblemState.*, rule exact
  15 placement: no `call <first_consumer>` between the start of the enclosing routine and
     the anchor line
  16 fail-closed output: FAIL: n problems (<= 200 lines, exit 1) else PASS line (exit 0)

Only the Python standard library is used. Sources are decoded as latin-1 via the M1
helpers imported from tools/yl_io_inventory.py.
"""
from __future__ import annotations

import argparse
import copy
import re
import sys
import tomllib
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from yl_io_inventory import (END_ROUTINE, ROUTINE, SOURCES, anchor_hash, full_statement,  # noqa: E402
                             load_inventory, split_lines, strip_comment)

REPO_ROOT = Path(__file__).resolve().parent.parent
MAP_DEFAULT = REPO_ROOT / "docs" / "m2" / "state-field-map.toml"
SRC_DEFAULT = REPO_ROOT / "legacy" / "yl"

SNAPSHOT_FILES = ["control.json", "mesh.sha256", "dof.sha256", "groups.json", "materials.json",
                  "constraints.sha256", "loads.sha256", "steps.json", "numerics.json"]
SKIP_TARGETS = {"title_skip", "empty_section", "unused_switch"}
CHECKPOINT_ID = re.compile(r"^(model_ready|phase_ready\(\d+\)|increment_ready\(\d+,\d+\)|restart_ready)$")
FIELD_ID = re.compile(r"^[a-z][a-z0-9]*(\.[A-Za-z0-9_]+)+$")
FIELD_TOP = re.compile(r"^(case|mesh|materials|sections|amplitudes|interactions|steps\d+|solver|runtime|derived|control|output)$")
# plan regex plus an optional `[]` after the first segment (schema examples use materials[].E)
OWNER = re.compile(r"^(ProblemState\.(case|mesh|materials|sections|amplitudes|interactions|steps\[\d+\]|solver)(\[\])?(\.|$)|RuntimeState(\.|$)|derived$|not_migrated$)")
SITE = re.compile(r"^([A-Za-z_0-9.]+\.[fF]90):(\d+)$")
DERIVED_RULES = {"count", "index_map", "renumber", "legacy_default", "dof_expand"}
DTYPES = {"i32", "i64", "f64", "str", "bool"}
UNITS = {"1", "id", "m", "N", "Pa", "kg", "kg/m3", "m/s2", "s", "K", "1/K"}
DETERMINISM = {"deterministic", "uninitialized", "pointer", "order_dependent"}
COMPARE_RULES = {"exact", "abs_tol", "rel_tol", "hash", "ignore"}
OWNER_GROUPS = ["case", "mesh", "materials", "sections", "amplitudes", "interactions", "steps[0]", "solver",
                "RuntimeState", "derived", "not_migrated"]
DECL = re.compile(r"^\s*(integer|real|character|logical|complex|double\s+precision|type\s*\()", re.I)
DECL_PREFIX = re.compile(r"^\s*(integer|real|character|logical|complex|double\s+precision|type)\s*(\([^)]*\))?\s*", re.I)
TYPE_OF = re.compile(r"^\s*type\s*\(\s*([A-Za-z_]\w*)\s*\)", re.I)
TYPE_BEGIN = re.compile(r"^\s*type\s*(?:,[^:]*::|::)?\s*([A-Za-z_]\w*)\s*$", re.I)
TYPE_END = re.compile(r"^\s*end\s+type\b", re.I)
MODULE_BEGIN = re.compile(r"^\s*module\s+([A-Za-z_]\w*)\s*$", re.I)
MODULE_END = re.compile(r"^\s*(contains|end\s+module)\b", re.I)


# --- source access -----------------------------------------------------------------------
class SourceTree:
    """Comment-stripped view of the legacy sources (files missing from `src` are absent)."""

    def __init__(self, files: dict[str, list[str]]):
        self.code = {f: [strip_comment(ln) for ln in lines] for f, lines in files.items()}
        self._routines: set[str] | None = None
        self._module_spans: dict[str, tuple[str, int, int] | None] = {}
        self._routine_spans: dict[tuple[str, str], tuple[int, int] | None] = {}
        self._vars: dict[tuple[str, int, int], dict[str, str | None]] = {}
        self._type_index: dict[str, tuple[str, dict[str, str | None]]] | None = None

    @classmethod
    def from_dir(cls, src: Path) -> "SourceTree":
        files = {}
        for f in SOURCES:
            p = src / f
            if p.is_file():
                files[f] = split_lines(p.read_bytes())
        return cls(files)

    @classmethod
    def from_text(cls, files: dict[str, str]) -> "SourceTree":
        return cls({f: split_lines(t.encode("latin-1")) for f, t in files.items()})

    def routine_at(self, fname: str, line: int) -> tuple[str | None, int]:
        """(routine name, 1-based start line) enclosing `line`, scanning backwards."""
        code = self.code[fname]
        for i in range(min(line, len(code)) - 1, -1, -1):
            if END_ROUTINE.match(code[i]) and i + 1 < line:
                return None, 0
            m = ROUTINE.match(code[i])
            if m:
                return m.group(2), i + 1
        return None, 0

    def has_routine(self, name: str) -> bool:
        """True when `name` follows a subroutine/function/program keyword anywhere in the sources."""
        if self._routines is None:
            rx = re.compile(r"\b(?:subroutine|function|program)\s+([A-Za-z_]\w*)", re.I)
            self._routines = {m.group(1).lower() for code in self.code.values() for ln in code
                              for m in rx.finditer(ln)}
        return name.lower() in self._routines

    def module_span(self, mod: str) -> tuple[str, int, int] | None:
        """(file, first line index, end index) of the declaration part of module `mod`."""
        key = mod.lower()
        if key not in self._module_spans:
            self._module_spans[key] = self._find_module(key)
        return self._module_spans[key]

    def _find_module(self, mod: str) -> tuple[str, int, int] | None:
        for f, code in self.code.items():
            for i, ln in enumerate(code):
                m = MODULE_BEGIN.match(ln)
                if not (m and m.group(1).lower() == mod):
                    continue
                end = len(code)
                for j in range(i + 1, len(code)):
                    if MODULE_END.match(code[j]):
                        end = j
                        break
                return f, i + 1, end
        return None

    def routine_span(self, fname: str, name: str) -> tuple[int, int] | None:
        """(first line index after `subroutine name`, end index) inside file `fname`."""
        key = (fname, name.lower())
        if key not in self._routine_spans:
            code = self.code[fname]
            span = None
            for i, ln in enumerate(code):
                m = ROUTINE.match(ln)
                if m and m.group(2).lower() == key[1]:
                    end = next((j for j in range(i + 1, len(code)) if END_ROUTINE.match(code[j])), len(code))
                    span = (i + 1, end)
                    break
            self._routine_spans[key] = span
        return self._routine_spans[key]

    def statements(self, fname: str, start: int, end: int):
        """Yield joined statements (continuations merged) for code[start:end]."""
        code = self.code[fname]
        i = start
        while i < end:
            stmt = full_statement(code, i)
            n = 1
            while i + n - 1 < end and code[i + n - 1].rstrip().endswith("&"):
                n += 1
            yield stmt
            i += n

    def module_vars(self, fname: str, start: int, end: int) -> dict[str, str | None]:
        """{entity name: derived type name | None (intrinsic)} declared in code[start:end] (cached)."""
        key = (fname, start, end)
        if key not in self._vars:
            names: dict[str, str | None] = {}
            for stmt in self.statements(fname, start, end):
                names.update(decl_entries(stmt))
            self._vars[key] = names
        return self._vars[key]

    def type_block(self, tname: str) -> tuple[str, dict[str, str | None]] | None:
        """(file, {component: derived type | None}) of `type <tname> ... end type`, searched in all
        source files (first hit in SOURCES order wins)."""
        if self._type_index is None:
            self._type_index = {}
            for fname, code in self.code.items():
                i = 0
                while i < len(code):
                    m = TYPE_BEGIN.match(code[i])
                    if m:
                        j = i + 1
                        while j < len(code) and not TYPE_END.match(code[j]):
                            j += 1
                        comps: dict[str, str | None] = {}
                        for stmt in self.statements(fname, i + 1, j):
                            comps.update(decl_entries(stmt))
                        self._type_index.setdefault(m.group(1).lower(), (fname, comps))
                        i = j
                    i += 1
        return self._type_index.get(tname.lower())


def decl_entries(stmt: str) -> dict[str, str | None]:
    """{entity name (lower-case): derived type name (lower-case) or None for intrinsic types}
    declared by one Fortran declaration statement."""
    if not DECL.match(stmt):
        return {}
    tm = TYPE_OF.match(stmt)
    tname = tm.group(1).lower() if tm else None
    rhs = stmt.split("::", 1)[1] if "::" in stmt else DECL_PREFIX.sub("", stmt, count=1)
    names: dict[str, str | None] = {}
    depth, item = 0, []
    for ch in rhs + ",":
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            m = re.match(r"\s*([A-Za-z_]\w*)", "".join(item))
            if m:
                names[m.group(1).lower()] = tname
            item = []
        else:
            item.append(ch)
    return names


# --- checks -------------------------------------------------------------------------------
class Checker:
    def __init__(self, doc: dict, inv: dict, src: SourceTree):
        self.doc, self.inv, self.src = doc, inv, src
        self.problems: list[str] = []
        self.warnings: list[str] = []
        self.checkpoints = doc.get("checkpoint", [])
        self.fields = doc.get("field", [])
        self.cp_by_id = {c.get("id"): c for c in self.checkpoints}
        self.field_ids = {f.get("id") for f in self.fields}
        self.readers = {r["id"]: r for r in inv.get("reader", [])}
        self.stats: dict = {}

    def fail(self, msg: str) -> None:
        self.problems.append(msg)

    def run(self) -> list[str]:
        self.check_top()
        self.check_checkpoints()
        for k, n in Counter(f.get("id") for f in self.fields).items():
            if n > 1:
                self.fail(f"duplicate field id {k}")
        for f in self.fields:
            self.check_field(f)
        self.check_reverse_coverage()
        self.check_perturbations()
        return self.problems

    # rule 1
    def check_top(self) -> None:
        d = self.doc
        if d.get("version") != 1:
            self.fail(f"version must be 1 (got {d.get('version')!r})")
        if not isinstance(d.get("cases"), list) or not d.get("cases"):
            self.fail("cases must be a non-empty list")
        if not d.get("reader_inventory"):
            self.fail("reader_inventory path missing")
        if not d.get("float_format"):
            self.fail("float_format missing (exact float comparison needs hex or 17-digit output)")
        for sym, rule in d.get("shape_symbols", {}).items():
            if not isinstance(rule, str) or not rule.strip():
                self.fail(f"shape_symbols.{sym}: derivation must be a non-empty string")

    # rules 2, 3, 15
    def check_checkpoints(self) -> None:
        last = None
        field_count = Counter(f.get("checkpoint") for f in self.fields)
        for k, n in Counter(c.get("id") for c in self.checkpoints).items():
            if n > 1:
                self.fail(f"duplicate checkpoint id {k}")
        for c in self.checkpoints:
            cid = str(c.get("id"))
            if not CHECKPOINT_ID.match(cid):
                self.fail(f"checkpoint {cid}: id not in vocabulary")
            order = c.get("order")
            if not isinstance(order, int) or (last is not None and order <= last):
                self.fail(f"checkpoint {cid}: order must be an int strictly increasing (got {order!r})")
            last = order if isinstance(order, int) else last
            if not c.get("covered"):
                if not c.get("reason"):
                    self.fail(f"checkpoint {cid}: covered=false requires reason")
                continue
            for key in ("site", "anchor", "after", "first_consumer", "snapshot_files"):
                if key not in c:
                    self.fail(f"checkpoint {cid}: covered=true requires {key}")
            for sf in c.get("snapshot_files", []):
                if sf not in SNAPSHOT_FILES:
                    self.fail(f"checkpoint {cid}: snapshot file {sf!r} not one of {SNAPSHOT_FILES}")
            if field_count[cid] == 0:
                self.fail(f"checkpoint {cid}: covered=true but has no fields")
            if "site" in c and "anchor" in c:
                self.check_anchor(c)

    def resolve_site(self, ctx: str, site) -> tuple[str, int] | None:
        m = SITE.match(str(site))
        if not m:
            self.fail(f"{ctx}: site {site!r} is not File.f90:line")
            return None
        fname, line = m.group(1), int(m.group(2))
        if fname not in SOURCES:
            self.fail(f"{ctx}: {fname} is not in SOURCES")
            return None
        if fname not in self.src.code:
            self.fail(f"{ctx}: source file {fname} missing")
            return None
        if not 1 <= line <= len(self.src.code[fname]):
            self.fail(f"{ctx}: line {line} outside {fname} ({len(self.src.code[fname])} lines)")
            return None
        return fname, line

    def check_anchor(self, c: dict) -> None:
        cid = c["id"]
        loc = self.resolve_site(f"checkpoint {cid}", c["site"])
        if loc is None:
            return
        fname, line = loc
        stmt = full_statement(self.src.code[fname], line - 1)
        got = anchor_hash(stmt)
        if got != c["anchor"]:
            self.fail(f"checkpoint {cid}: anchor {c['anchor']} != {got} at {c['site']} (source changed?)")
        if c.get("anchor_stmt") and re.sub(r"\s+", " ", c["anchor_stmt"].strip().lower()) != \
                re.sub(r"\s+", " ", stmt.strip().lower()):
            self.fail(f"checkpoint {cid}: anchor_stmt differs from source text at {c['site']} (source changed?)")
        routine, start = self.src.routine_at(fname, line)
        if routine is None:
            self.fail(f"checkpoint {cid}: no enclosing routine found for {c['site']}")
        for a in c.get("after", []):
            aloc = self.resolve_site(f"checkpoint {cid} after", a)
            if aloc is None:
                continue
            if aloc[0] != fname or self.src.routine_at(*aloc)[0] != routine:
                self.fail(f"checkpoint {cid}: after {a} is not in routine {routine} of {c['site']}")
            elif aloc[1] >= line:
                self.fail(f"checkpoint {cid}: after {a} does not precede anchor {c['site']}")
        fc = c.get("first_consumer", "")
        if not fc or not self.src.has_routine(fc):
            self.fail(f"checkpoint {cid}: first_consumer {fc!r} is not a subroutine/function in the sources")
        elif routine is not None:
            self.check_placement(cid, fname, start, line, fc)

    # rule 15
    def check_placement(self, cid: str, fname: str, start: int, line: int, fc: str) -> None:
        rx = re.compile(r"\bcall\s+" + re.escape(fc) + r"\b", re.I)
        for i in range(start - 1, line - 1):
            if rx.search(self.src.code[fname][i]):
                self.fail(f"checkpoint {cid}: placement: `call {fc}` at {fname}:{i + 1} precedes anchor {fname}:{line}")

    # rules 4-6, 8-13
    def check_field(self, f: dict) -> None:
        fid = str(f.get("id"))
        if not FIELD_ID.match(fid) or not FIELD_TOP.match(fid.split(".")[0]):
            self.fail(f"field {fid}: id does not match the field id rule")
        cp = self.cp_by_id.get(f.get("checkpoint"))
        if cp is None or not cp.get("covered"):
            self.fail(f"field {fid}: checkpoint {f.get('checkpoint')!r} is not a covered checkpoint")
        elif f.get("snapshot_file") not in cp.get("snapshot_files", []):
            self.fail(f"field {fid}: snapshot_file {f.get('snapshot_file')!r} not in {cp['id']}.snapshot_files")
        self.check_source(f)
        self.check_symbol(f)
        consumers = f.get("consumers", [])
        if not consumers:
            self.fail(f"field {fid}: consumers must be non-empty")
        for name in consumers:
            if not self.src.has_routine(str(name)):
                self.fail(f"field {fid}: consumer {name!r} is not a subroutine/function in the sources")
        self.check_vocab(f)
        self.check_owner(f)
        self.check_compare(f)

    def check_derived_from(self, f: dict, why: str) -> None:
        df = f.get("derived_from")
        if not isinstance(df, list) or not df:
            self.fail(f"field {f.get('id')}: {why} requires non-empty derived_from")
            return
        for d in df:
            if d not in self.field_ids:
                self.fail(f"field {f.get('id')}: derived_from {d!r} is not a field id")
            elif d == f.get("id"):
                self.fail(f"field {f.get('id')}: derived_from itself")

    def check_source(self, f: dict) -> None:
        fid, src = f.get("id"), f.get("source")
        if not isinstance(src, list) or not src:
            self.fail(f"field {fid}: source must be a non-empty list")
            return
        derived = [s for s in src if str(s).startswith("derived:")]
        if derived:
            if len(src) != 1:
                self.fail(f"field {fid}: derived:* source must be the only source entry")
            rule = str(derived[0]).split(":", 1)[1]
            if rule not in DERIVED_RULES:
                self.fail(f"field {fid}: derived rule {rule!r} not in {sorted(DERIVED_RULES)}")
            self.check_derived_from(f, f"source {derived[0]}")
        for s in src:
            if s in derived:
                continue
            r = self.readers.get(s)
            if r is None:
                self.fail(f"field {fid}: unknown reader {s!r}")
            elif r.get("reached_only"):
                self.fail(f"field {fid}: reader {s} is reached_only")
            elif not r.get("executed_by"):
                self.fail(f"field {fid}: reader {s} has empty executed_by")

    # rule 8
    def check_symbol(self, f: dict) -> None:
        fid, sym = f.get("id"), str(f.get("legacy_symbol", ""))
        m = re.match(r"^([A-Za-z_]\w*)\.([A-Za-z_]\w*)(?:\.([A-Za-z_]\w*))?((?:%[A-Za-z_]\w*)*)$", sym)
        if not m:
            self.fail(f"field {fid}: legacy_symbol {sym!r} is not <module>[.<routine>].<var>[%comp...]")
            return
        mod, routine, var = m.group(1), (m.group(2) if m.group(3) else None), (m.group(3) or m.group(2))
        comps = [c for c in m.group(4).split("%") if c]
        span = self.src.module_span(mod)
        if span is None:
            self.fail(f"field {fid}: module {mod!r} not found in the sources")
            return
        fname, start, end = span
        if routine is not None:
            span = self.src.routine_span(fname, routine)
            if span is None:
                self.fail(f"field {fid}: routine {routine!r} not found in {fname}")
                return
            start, end = span
        declared = self.src.module_vars(fname, start, end)
        if var.lower() not in declared:
            where = f"routine {routine} of " if routine else "module "
            self.fail(f"field {fid}: {var!r} not declared in {where}{mod} ({fname}:{start}-{end})")
            return
        # chain walk: <var> : type(T0) -> %c1 declared in `type T0` with type(T1) -> %c2 in `type T1` ...
        tname, path = declared[var.lower()], var
        for c in comps:
            if tname is None:
                self.fail(f"field {fid}: component %{c} follows intrinsic-typed {path} (no further components)")
                return
            block = self.src.type_block(tname)
            if block is None:
                self.fail(f"field {fid}: type {tname!r} of {path} has no type block in the sources")
                return
            tfile, tcomps = block
            if c.lower() not in tcomps:
                self.fail(f"field {fid}: component %{c} not declared in type {tname} ({tfile})")
                return
            tname, path = tcomps[c.lower()], f"{path}%{c}"

    # rule 10
    def check_vocab(self, f: dict) -> None:
        fid = f.get("id")
        symbols = self.doc.get("shape_symbols", {})
        shape = f.get("shape")
        if not isinstance(shape, list):
            self.fail(f"field {fid}: shape must be a list")
        else:
            for s in shape:
                ok = isinstance(s, int) or (isinstance(s, str) and (s in symbols or re.fullmatch(r"\d+", s)))
                if not ok:
                    self.fail(f"field {fid}: shape symbol {s!r} not declared in [shape_symbols]")
        dtype = str(f.get("dtype"))
        if dtype not in DTYPES and not re.fullmatch(r"enum:[A-Za-z_]\w*", dtype):
            self.fail(f"field {fid}: dtype {dtype!r} not in vocabulary")
        unit = f.get("unit")
        if unit not in UNITS:
            self.fail(f"field {fid}: unit {unit!r} not in {sorted(UNITS)}")
        elif dtype != "f64" and unit not in ("1", "id"):
            self.fail(f"field {fid}: unit {unit!r} incompatible with non-float dtype {dtype}")
        if f.get("determinism") not in DETERMINISM:
            self.fail(f"field {fid}: determinism {f.get('determinism')!r} not in {sorted(DETERMINISM)}")
        if not f.get("index_by") and shape:
            self.warnings.append(f"field {fid}: array without index_by")

    # rule 11
    def check_owner(self, f: dict) -> None:
        fid, owner = f.get("id"), str(f.get("owner", ""))
        if not OWNER.match(owner):
            self.fail(f"field {fid}: owner {owner!r} not in vocabulary")
            return
        if owner == "not_migrated" and not f.get("reason"):
            self.fail(f"field {fid}: owner not_migrated requires reason")
        if owner.startswith("RuntimeState"):
            self.check_derived_from(f, "owner RuntimeState.*")

    # rule 12
    def check_compare(self, f: dict) -> None:
        fid, cmp_ = f.get("id"), f.get("compare")
        if not isinstance(cmp_, dict) or cmp_.get("rule") not in COMPARE_RULES:
            self.fail(f"field {fid}: compare.rule must be one of {sorted(COMPARE_RULES)}")
            return
        rule, owner, det = cmp_["rule"], str(f.get("owner", "")), f.get("determinism")
        if rule in ("abs_tol", "rel_tol"):
            self.check_tolerance(fid, rule, cmp_, owner)
        elif rule == "hash" and cmp_.get("algo") != "sha256":
            self.fail(f"field {fid}: hash requires algo=\"sha256\"")
        elif rule == "ignore" and not (cmp_.get("reason") or f.get("reason")):
            self.fail(f"field {fid}: ignore requires reason")
        if det in DETERMINISM and det != "deterministic":
            sorted_ok = det == "order_dependent" and rule == "exact" and bool(cmp_.get("sorted_by"))
            if rule not in ("ignore", "hash") and not sorted_ok:
                self.fail(f"field {fid}: determinism {det} requires compare ignore or hash "
                          f"(order_dependent may be exact with sorted_by)")

    def check_tolerance(self, fid, rule: str, cmp_: dict, owner: str) -> None:
        atol, rtol = cmp_.get("atol"), cmp_.get("rtol")
        num = (int, float)
        if not isinstance(atol, num) or atol <= 0:
            self.fail(f"field {fid}: {rule} requires atol > 0")
        if rule == "rel_tol" and (not isinstance(rtol, num) or rtol <= 0):
            self.fail(f"field {fid}: rel_tol requires rtol > 0")
        if rtol is not None and (not isinstance(rtol, num) or rtol < 0):
            self.fail(f"field {fid}: rtol must be a non-negative number")
        if not cmp_.get("basis"):
            self.fail(f"field {fid}: {rule} requires basis")
        if not (owner == "derived" or owner.startswith("RuntimeState")):
            self.fail(f"field {fid}: tolerance rule {rule} on owner {owner} (only derived / RuntimeState.*)")

    # rule 7
    def check_reverse_coverage(self) -> None:
        referenced = {s for f in self.fields for s in f.get("source", []) if isinstance(s, str)}
        owners = [str(f.get("owner", "")) for f in self.fields]
        required, skip = [], 0
        for rid, r in self.readers.items():
            if r.get("reached_only") or not r.get("executed_by"):
                continue
            if r.get("state_target") in SKIP_TARGETS:
                skip += 1
                continue
            required.append(rid)
            if rid not in referenced:
                self.fail(f"reader {rid} (state_target {r.get('state_target')}) not referenced by any field source")
                continue
            for target in reader_targets(r):
                if not any(o.startswith("ProblemState." + target) for o in owners):
                    self.warnings.append(f"reader {rid}: target {target} has no field owner with that prefix")
        self.stats.update(readers_required=len(required), readers_covered=sum(r in referenced for r in required),
                          skip_class=skip)

    # rule 14
    def check_perturbations(self) -> None:
        by_id = {f.get("id"): f for f in self.fields}
        cases = self.doc.get("cases", [])
        for p in self.doc.get("perturbation", []):
            pid = p.get("id", "?")
            if p.get("case") not in cases:
                self.fail(f"perturbation {pid}: case {p.get('case')!r} not in cases")
            f = by_id.get(p.get("field"))
            if f is None:
                self.fail(f"perturbation {pid}: field {p.get('field')!r} does not exist")
                continue
            if not str(f.get("owner", "")).startswith("ProblemState."):
                self.fail(f"perturbation {pid}: field {f['id']} owner {f.get('owner')} is not ProblemState.*")
            if (f.get("compare") or {}).get("rule") != "exact":
                self.fail(f"perturbation {pid}: field {f['id']} compare rule must be exact")


def reader_targets(r: dict) -> list[str]:
    """ProblemState targets from a reader's `name[dims]:type[:target]` field entries."""
    out = []
    for entry in r.get("fields", []):
        parts = str(entry).split(":")
        if len(parts) < 3:
            continue
        # `steps[0].load(gravity).magnitude` -> `steps[0].load.gravity.magnitude`; a bare trailing `(x)` is dropped
        target = re.sub(r"\(([^)]*)\)$", "", parts[2])
        target = re.sub(r"\(([^)]*)\)", r".\1", target)
        if re.match(r"^(case|mesh|materials|sections|amplitudes|interactions|steps\[\d+\]|solver)(\.|$)", target):
            out.append(target)
    return out


def summarize(ck: Checker) -> str:
    covered = sum(1 for c in ck.checkpoints if c.get("covered"))
    s = ck.stats
    return (f"PASS: {len(ck.fields)} fields, {len(ck.checkpoints)} checkpoints ({covered} covered), "
            f"readers covered {s.get('readers_covered', 0)}/{s.get('readers_required', 0)}, "
            f"skip-class {s.get('skip_class', 0)}")


def report(ck: Checker) -> int:
    for w in ck.warnings:
        print("  WARN " + w)
    if ck.problems:
        print(f"FAIL: {len(ck.problems)} problems")
        for p in ck.problems[:200]:
            print("  " + p)
        return 1
    print(summarize(ck))
    return 0


def load_map(path: Path) -> dict:
    return tomllib.loads(path.read_text(encoding="utf-8"))


def inventory_path(doc: dict, override: str | None, map_path: Path) -> Path:
    if override:
        return Path(override)
    p = Path(str(doc.get("reader_inventory", "")))
    return p if p.is_absolute() else (map_path.parent / p if (map_path.parent / p).exists() else REPO_ROOT / p)


def load_checker(a) -> Checker | None:
    """Load map + inventory + sources and run every check; None (after a FAIL line) when a file
    cannot be loaded."""
    map_path = Path(a.map)
    try:
        doc = load_map(map_path)
    except (OSError, tomllib.TOMLDecodeError) as e:
        print(f"FAIL: 1 problems\n  {map_path}: {e}")
        return None
    inv_path = inventory_path(doc, a.inventory, map_path)
    try:
        inv = load_inventory(inv_path)
    except (OSError, tomllib.TOMLDecodeError) as e:
        print(f"FAIL: 1 problems\n  reader_inventory {inv_path}: {e}")
        return None
    ck = Checker(doc, inv, SourceTree.from_dir(Path(a.src)))
    ck.run()
    return ck


def cmd_check(a) -> int:
    ck = load_checker(a)
    return 1 if ck is None else report(ck)


# --- render -------------------------------------------------------------------------------
def md_cell(v) -> str:
    if v is None:
        return ""
    if isinstance(v, list):
        return ", ".join(f"`{x}`" for x in v)
    return str(v).replace("|", "\\|").replace("\n", " ")


def render_compare(f: dict) -> str:
    c = f.get("compare") or {}
    rule = c.get("rule", "?")
    if rule in ("abs_tol", "rel_tol"):
        tol = f"abs {c.get('atol')}" if rule == "abs_tol" else f"rel {c.get('rtol')}"
        extra = f" rtol {c.get('rtol')}" if rule == "abs_tol" and c.get("rtol") is not None else ""
        extra = extra or (f" atol {c.get('atol')}" if rule == "rel_tol" and c.get("atol") is not None else "")
        return f"{tol} {f.get('unit', '')}{extra} ({c.get('basis', '')})"
    if rule == "hash":
        return str(c.get("algo", "hash"))
    if rule == "ignore":
        return f"ignore: {c.get('reason') or f.get('reason') or ''}"
    if c.get("sorted_by"):
        return f"exact (sorted by {c['sorted_by']})"
    return rule


def owner_group(owner: str) -> str:
    if owner.startswith("ProblemState."):
        return owner.split(".")[1].removesuffix("[]")
    if owner.startswith("RuntimeState"):
        return "RuntimeState"
    return owner


def group_key(g: str) -> tuple[int, str]:
    return (OWNER_GROUPS.index(g), g) if g in OWNER_GROUPS else (len(OWNER_GROUPS), g)


def render_header(doc: dict, ck: Checker) -> list[str]:
    covered = [c for c in ck.checkpoints if c.get("covered")]
    per_cp = Counter(f.get("checkpoint") for f in ck.fields)
    executed = sum(1 for r in ck.readers.values() if r.get("executed_by") and not r.get("reached_only"))
    s = ck.stats
    out = ["# M2-01 检查点 × 状态字段映射（static_2d）", "",
           f"- 路径：{doc.get('path', '')}",
           f"- 算例：{', '.join(f'`{c}`' for c in doc.get('cases', []))}",
           f"- 权威文件：`docs/m2/state-field-map.toml`；reader 注册表：`{doc.get('reader_inventory', '')}`；"
           f"浮点格式：`{doc.get('float_format', '')}`",
           "- 生成命令：`python3 tools/yl_state_map.py render -o docs/m2/state-field-map.md`；"
           "校验：`python3 tools/yl_state_map.py check`",
           f"- 字段 {len(ck.fields)}；检查点 {len(ck.checkpoints)}（覆盖 {len(covered)}）；"
           f"reader 覆盖 {s.get('readers_covered', 0)}/{s.get('readers_required', 0)}（非 skip 类，已执行 {executed}）；"
           f"skip 类 {s.get('skip_class', 0)}",
           "- 各检查点字段数：" + "；".join(f"`{c['id']}` {per_cp.get(c['id'], 0)}" for c in ck.checkpoints),
           "- 校验结果：" + ("PASS" if not ck.problems else f"FAIL（{len(ck.problems)} 个问题，见 check 输出）"), ""]
    syms = doc.get("shape_symbols", {})
    if syms:
        out += ["## 形状记号", "", "| 记号 | 派生规则 |", "|---|---|"]
        out += [f"| `{k}` | {md_cell(v)} |" for k, v in syms.items()]
        out.append("")
    return out


def render_checkpoints(ck: Checker) -> list[str]:
    per_cp = Counter(f.get("checkpoint") for f in ck.fields)
    out = ["## 检查点", "", "| ID | order | 锚点 | anchor | after | first_consumer | snapshot files | 字段数 | covered / reason |",
           "|---|---|---|---|---|---|---|---|---|"]
    for c in ck.checkpoints:
        status = "covered" if c.get("covered") else f"covered=false：{md_cell(c.get('reason'))}"
        if c.get("note"):
            status += f"（{md_cell(c['note'])}）"
        out.append(f"| `{c.get('id')}` | {c.get('order', '')} | {md_cell(c.get('site'))} | `{c.get('anchor', '')}` | "
                   f"{md_cell(c.get('after'))} | {md_cell(c.get('first_consumer'))} | {md_cell(c.get('snapshot_files'))} | "
                   f"{per_cp.get(c.get('id'), 0)} | {status} |")
    out.append("")
    return out


def render_fields(ck: Checker) -> list[str]:
    out = []
    cols = "| ID | legacy symbol | source | consumers | shape | dtype | unit | owner | compare | determinism | snapshot | note |"
    for c in ck.checkpoints:
        if not c.get("covered"):
            continue
        rows = [f for f in ck.fields if f.get("checkpoint") == c.get("id")]
        out += [f"## `{c.get('id')}`（{len(rows)} 字段）", ""]
        groups = defaultdict(list)
        for f in rows:
            groups[owner_group(str(f.get("owner", "")))].append(f)
        for g in sorted(groups, key=group_key):
            out += [f"### {g}（{len(groups[g])}）", "", cols, "|" + "---|" * 12]
            for f in groups[g]:
                src = ", ".join(f"`{s}`" for s in f.get("source", []))
                if f.get("derived_from"):
                    src += " ← " + ", ".join(f"`{d}`" for d in f["derived_from"])
                shape = "[" + ", ".join(str(s) for s in f.get("shape", [])) + "]"
                note = md_cell(f.get("note"))
                if f.get("reason"):
                    note = (note + " " if note else "") + f"reason: {md_cell(f['reason'])}"
                out.append(f"| `{f.get('id')}` | `{f.get('legacy_symbol', '')}` | {src} | {md_cell(f.get('consumers'))} | "
                           f"`{shape}` | {f.get('dtype', '')} | {f.get('unit', '')} | `{f.get('owner', '')}` | "
                           f"{md_cell(render_compare(f))} | {f.get('determinism', '')} | `{f.get('snapshot_file', '')}` | {note} |")
            out.append("")
    return out


def render_perturbations(doc: dict) -> list[str]:
    out = ["## S03 扰动目标（perturbation）", ""]
    perts = doc.get("perturbation", [])
    if not perts:
        return out + ["（无登记）", ""]
    out += ["| ID | 算例 | 字段 | index | legacy edit | expected_only | 说明 |", "|---|---|---|---|---|---|---|"]
    for p in perts:
        out.append(f"| `{p.get('id', '')}` | `{p.get('case', '')}` | `{p.get('field', '')}` | `{p.get('index', '')}` | "
                   f"{md_cell(p.get('legacy_edit'))} | {p.get('expected_only', '')} | {md_cell(p.get('note'))} |")
    return out + [""]


def render_excluded(ck: Checker) -> list[str]:
    referenced = {s for f in ck.fields for s in f.get("source", [])}
    out = ["## 未覆盖 / 排除", ""]
    missing = [rid for rid, r in ck.readers.items() if r.get("executed_by") and not r.get("reached_only")
               and r.get("state_target") not in SKIP_TARGETS and rid not in referenced]
    out.append(f"### 已执行、非 skip 类但无字段引用的 reader（{len(missing)}，check 要求为 0）")
    out += ([""] + [f"- `{rid}`（`{ck.readers[rid].get('state_target')}`）" for rid in missing]) if missing else ["", "（无）"]
    skip = Counter(r.get("state_target") for r in ck.readers.values()
                   if r.get("executed_by") and not r.get("reached_only") and r.get("state_target") in SKIP_TARGETS)
    out += ["", f"### skip 类 reader（{sum(skip.values())}）", ""]
    out += [f"- `{k}`：{skip[k]}" for k in sorted(skip)]
    out.append("- 说明：标题行不携带状态；节顺序已由 reader `seq` 固定；空节与未用开关不进入 ProblemState。")
    ignored = [f for f in ck.fields if (f.get("compare") or {}).get("rule") == "ignore" or f.get("owner") == "not_migrated"]
    out += ["", f"### ignore / not_migrated 字段（{len(ignored)}）", ""]
    out += [f"- `{f.get('id')}`（{f.get('owner')}，{render_compare(f)}）：{md_cell(f.get('reason') or (f.get('compare') or {}).get('reason'))}"
            for f in ignored] or ["（无）"]
    nondet = [f for f in ck.fields if f.get("determinism") not in (None, "deterministic")]
    out += ["", f"### 非确定性字段（{len(nondet)}）", ""]
    out += [f"- `{f.get('id')}`：{f.get('determinism')} → {render_compare(f)}" for f in nondet] or ["（无）"]
    unc = [c for c in ck.checkpoints if not c.get("covered")]
    out += ["", f"### 未覆盖检查点（{len(unc)}）", ""]
    out += [f"- `{c.get('id')}`：{md_cell(c.get('reason'))}" for c in unc] or ["（无）"]
    return out + [""]


def render_checked(ck: Checker) -> str:
    """Markdown for an already-run Checker."""
    doc = ck.doc
    out = render_header(doc, ck) + render_checkpoints(ck) + render_fields(ck) + render_perturbations(doc) + render_excluded(ck)
    return "\n".join(out) + "\n"


def render(doc: dict, inv: dict, src: SourceTree) -> str:
    ck = Checker(doc, inv, src)
    ck.run()
    return render_checked(ck)


def cmd_render(a) -> int:
    """Fail-closed: the full check runs first; on FAIL the problems are printed and nothing is
    written (exit 1) unless --force, which writes the Markdown and still exits 1."""
    ck = load_checker(a)
    if ck is None:
        return 1
    rc = 0
    if ck.problems:
        rc = report(ck)
        if not a.force:
            print(f"render: refusing to write (use --force to write anyway)")
            return rc
    text = render_checked(ck)
    if a.output:
        Path(a.output).parent.mkdir(parents=True, exist_ok=True)
        Path(a.output).write_text(text, encoding="utf-8")
        print(f"wrote {a.output}")
    else:
        sys.stdout.write(text)
    return rc


# --- selftest -----------------------------------------------------------------------------
SELF_FEM = """    subroutine process_analysis
    call prescrib_set
    call external_load_2
    call solve
    call static_U
    end subroutine process_analysis
    SUBROUTINE STATIC_U
    END SUBROUTINE STATIC_U
    subroutine prescrib_set
    end subroutine prescrib_set
    subroutine external_load_2
    end subroutine external_load_2
    subroutine solve
    end subroutine solve
"""
SELF_GLOBAL = """    Module global_var
    integer(ink) npoin,ndimn   ! sizes
    real    (irk),allocatable::coord(:,:),deltafi(:),     &
                               delitfi(:)
    type solid_skeleton
       character(20)material
       real(irk) e,nu
    end type solid_skeleton
    contains
    subroutine stiff_u
    integer(ink) local_k
    end subroutine stiff_u
    end module global_var
"""
# 3-hop chain props%mechanical%solid%e; solid_skeleton deliberately lives in Global.f90
SELF_MATERIAL = """    module materials
    type mechanical_property
        type(solid_skeleton),pointer::solid
    end type mechanical_property
    type material_property
        character(20)name
        type(mechanical_property),pointer::mechanical
    end type material_property
    type(material_property),   allocatable::props(:)
    end module materials
"""
SELF_CASES = ["static_2d.demo"]


def self_inventory() -> dict:
    def rd(rid, target, fields, executed=True, reached=False):
        r = {"id": rid, "site": "Global.f90:2", "fields": fields, "state_target": target,
             "executed_by": SELF_CASES if executed else []}
        if reached:
            r["reached_only"] = True
        return r
    return {"reader": [rd("COR.node_coordinates", "mesh.nodes[].xyz", ["coord[1:ndimn]:real:mesh.nodes[].xyz"]),
                       rd("MAT.elastic", "materials", ["e:real:materials[].E"]),
                       rd("GLB.title#1", "title_skip", ["text:str"]),
                       rd("GLB.reached", "derived", [], reached=True),
                       rd("GLB.unused", "unused_switch", ["k:int"], executed=False)]}


def self_map() -> dict:
    fem = split_lines(SELF_FEM.encode("latin-1"))
    return {"version": 1, "cases": SELF_CASES, "path": "selftest", "reader_inventory": "(in-memory)",
            "float_format": "hex", "shape_symbols": {"ndimn": "mesh.dimension", "npoin": "count(mesh.nodes)"},
            "checkpoint": [
                {"id": "model_ready", "order": 1, "covered": True, "site": "Fem.f90:4",
                 "anchor": anchor_hash(full_statement(fem, 3)), "after": ["Fem.f90:3"], "first_consumer": "solve",
                 "snapshot_files": ["mesh.sha256", "materials.json", "dof.sha256"]},
                {"id": "restart_ready", "order": 2, "covered": False, "reason": "no restart on static_2d"}],
            "field": [
                {"id": "mesh.nodes.xyz", "checkpoint": "model_ready", "legacy_symbol": "global_var.coord",
                 "source": ["COR.node_coordinates"], "consumers": ["stiff_u"], "shape": ["ndimn", "npoin"],
                 "dtype": "f64", "unit": "m", "owner": "ProblemState.mesh.nodes[].xyz", "index_by": "mesh.nodes[].id",
                 "compare": {"rule": "exact"}, "determinism": "deterministic", "snapshot_file": "mesh.sha256"},
                {"id": "materials.E", "checkpoint": "model_ready", "legacy_symbol": "materials.props%mechanical%solid%e",
                 "source": ["MAT.elastic"], "consumers": ["stiff_u"], "shape": ["1"], "dtype": "f64", "unit": "Pa",
                 "owner": "ProblemState.materials[].E", "index_by": "materials[].id",
                 "compare": {"rule": "exact"}, "determinism": "deterministic", "snapshot_file": "materials.json"},
                {"id": "runtime.dof.count", "checkpoint": "model_ready", "legacy_symbol": "global_var.stiff_u.local_k",
                 "source": ["derived:count"], "derived_from": ["mesh.nodes.xyz"], "consumers": ["stiff_u"],
                 "shape": [], "dtype": "i32", "unit": "1", "owner": "RuntimeState.dof.count",
                 "compare": {"rule": "abs_tol", "atol": 1, "basis": "count"}, "determinism": "deterministic",
                 "snapshot_file": "dof.sha256"}],
            "perturbation": [{"id": "P-E", "case": "static_2d.demo", "field": "materials.E", "index": "[1]",
                              "legacy_edit": "demo.mat record 3", "expected_only": True}]}


def self_cases() -> list[tuple[str, str, callable]]:
    """(name, expected problem substring, mutator) for one bad sample per rule category."""
    def dup(d): d["field"].append(copy.deepcopy(d["field"][0]))
    def unknown_reader(d): d["field"][0]["source"] = ["COR.nope"]
    def reached(d): d["field"][0]["source"] = ["GLB.reached"]
    def bad_dtype(d): d["field"][0]["dtype"] = "float"
    def bad_unit(d): d["field"][2]["unit"] = "Pa"
    def bad_shape(d): d["field"][0]["shape"] = ["nelem"]
    def bad_owner(d): d["field"][0]["owner"] = "ProblemState.nodes"
    def bad_fid(d): d["field"][0]["id"] = "Mesh.nodes"
    def drift(d): d["checkpoint"][0]["anchor"] = "000000000000"
    def bad_line(d): d["checkpoint"][0]["site"] = "Fem.f90:999"
    def after_late(d): d["checkpoint"][0]["after"] = ["Fem.f90:5"]
    def placement(d): d["checkpoint"][0]["site"] = "Fem.f90:5"; d["checkpoint"][0]["anchor"] = anchor_hash("call static_U")
    def no_reason_ignore(d): d["field"][0]["compare"] = {"rule": "ignore"}
    def no_reason_nm(d): d["field"][2]["owner"] = "not_migrated"; d["field"][2]["compare"] = {"rule": "exact"}
    def no_reason_cp(d): d["checkpoint"][1].pop("reason")
    def zero_fields(d): d["checkpoint"][1].update(covered=True, site="Fem.f90:4", anchor=d["checkpoint"][0]["anchor"], after=[], first_consumer="solve", snapshot_files=["mesh.sha256"])
    def tol_on_ps(d): d["field"][1]["compare"] = {"rule": "abs_tol", "atol": 1e-6, "basis": "x"}
    def tol_no_basis(d): d["field"][2]["compare"] = {"rule": "abs_tol", "atol": 1e-6}
    def hash_algo(d): d["field"][0]["compare"] = {"rule": "hash", "algo": "md5"}
    def pert_nonexact(d): d["field"][1]["compare"] = {"rule": "hash", "algo": "sha256"}
    def pert_case(d): d["perturbation"][0]["case"] = "static_2d.other"
    def pert_field(d): d["perturbation"][0]["field"] = "materials.nu"
    def pert_runtime(d): d["perturbation"][0]["field"] = "runtime.dof.count"
    def bad_var(d): d["field"][0]["legacy_symbol"] = "global_var.stiff_u"
    def bad_comp(d): d["field"][1]["legacy_symbol"] = "materials.props%rho"
    def chain_skip(d): d["field"][1]["legacy_symbol"] = "materials.props%e%nu"
    def chain_past_intrinsic(d): d["field"][1]["legacy_symbol"] = "materials.props%mechanical%solid%e%nu"
    def chain_no_type(d): d["field"][1]["legacy_symbol"] = "materials.props%mechanical%solid%material%x"
    def bad_module(d): d["field"][0]["legacy_symbol"] = "nomod.coord"
    def bad_local(d): d["field"][0]["legacy_symbol"] = "global_var.stiff_u.coord"
    def bad_routine(d): d["field"][0]["legacy_symbol"] = "global_var.nosub.coord"
    def bad_consumer(d): d["field"][0]["consumers"] = ["stiff_v"]
    def no_consumer(d): d["field"][0]["consumers"] = []
    def uncovered(d): d["field"][1]["source"] = ["COR.node_coordinates"]
    def snap(d): d["field"][0]["snapshot_file"] = "loads.sha256"
    def snap_vocab(d): d["checkpoint"][0]["snapshot_files"].append("extra.json")
    def bad_cp(d): d["field"][0]["checkpoint"] = "restart_ready"
    def order(d): d["checkpoint"][1]["order"] = 1
    def bad_cp_id(d): d["checkpoint"][1]["id"] = "phase_ready"
    def nondet(d): d["field"][0]["determinism"] = "uninitialized"
    def det_vocab(d): d["field"][0]["determinism"] = "random"
    def derived_missing(d): d["field"][2]["derived_from"] = ["mesh.nope"]
    def derived_rule(d): d["field"][2]["source"] = ["derived:magic"]
    def version(d): d["version"] = 2
    def fmt(d): d.pop("float_format")
    def first_consumer(d): d["checkpoint"][0]["first_consumer"] = "nosuch"
    return [("duplicate field id", "duplicate field id", dup), ("unknown reader", "unknown reader", unknown_reader),
            ("reached_only reader", "reached_only", reached), ("dtype vocab", "dtype", bad_dtype),
            ("unit incompatible", "incompatible", bad_unit), ("shape symbol", "shape symbol", bad_shape),
            ("owner vocab", "owner", bad_owner), ("field id regex", "field id rule", bad_fid),
            ("anchor drift", "source changed?", drift), ("anchor line", "outside", bad_line),
            ("after not before anchor", "does not precede", after_late), ("placement rule 15", "placement", placement),
            ("ignore without reason", "ignore requires reason", no_reason_ignore),
            ("not_migrated without reason", "not_migrated requires reason", no_reason_nm),
            ("uncovered checkpoint without reason", "covered=false requires reason", no_reason_cp),
            ("zero-field covered checkpoint", "has no fields", zero_fields),
            ("tolerance on ProblemState owner", "tolerance rule", tol_on_ps), ("tolerance without basis", "requires basis", tol_no_basis),
            ("hash algo", "sha256", hash_algo), ("perturbation on non-exact field", "must be exact", pert_nonexact),
            ("perturbation unknown case", "not in cases", pert_case), ("perturbation unknown field", "does not exist", pert_field),
            ("perturbation on RuntimeState", "not ProblemState", pert_runtime),
            ("legacy var not declared", "not declared in module", bad_var), ("legacy component missing", "component %rho not declared in type material_property", bad_comp),
            ("legacy chain skips a hop", "component %e not declared in type material_property", chain_skip),
            ("legacy chain past intrinsic", "component %nu follows intrinsic-typed props%mechanical%solid%e", chain_past_intrinsic),
            ("legacy chain past character", "component %x follows intrinsic-typed", chain_no_type),
            ("legacy module missing", "module 'nomod' not found", bad_module),
            ("legacy local var missing", "not declared in routine stiff_u", bad_local),
            ("legacy routine missing", "routine 'nosub' not found", bad_routine),
            ("unknown consumer", "consumer", bad_consumer), ("empty consumers", "consumers must be non-empty", no_consumer),
            ("reverse coverage", "not referenced by any field", uncovered), ("snapshot_file mismatch", "snapshot_file", snap),
            ("snapshot vocab", "snapshot file", snap_vocab), ("field on uncovered checkpoint", "not a covered checkpoint", bad_cp),
            ("order not increasing", "strictly increasing", order), ("checkpoint id vocab", "id not in vocabulary", bad_cp_id),
            ("non-deterministic with exact", "requires compare ignore or hash", nondet),
            ("determinism vocab", "determinism 'random'", det_vocab),
            ("derived_from unresolved", "is not a field id", derived_missing), ("derived rule vocab", "derived rule", derived_rule),
            ("version", "version must be 1", version), ("float_format missing", "float_format", fmt),
            ("first_consumer unknown", "first_consumer", first_consumer)]


def selftest() -> int:
    src = SourceTree.from_text({"Fem.f90": SELF_FEM, "Global.f90": SELF_GLOBAL, "Material.f90": SELF_MATERIAL})
    inv = self_inventory()
    base = Checker(self_map(), inv, src)
    base.run()
    ok = not base.problems
    print(("ok   " if ok else "BAD  ") + "good sample: " + (summarize(base) if ok else "; ".join(base.problems)))
    n_ok = int(ok)
    cases = self_cases()
    for name, expect, mutate in cases:
        doc = self_map()
        mutate(doc)
        problems = Checker(doc, inv, src).run()
        hit = next((p for p in problems if expect in p), None)
        if hit:
            n_ok += 1
            print(f"ok   {name}: {hit}")
        else:
            print(f"BAD  {name}: expected {expect!r}, got {problems}")
    text1, text2 = render(self_map(), inv, src), render(self_map(), inv, src)
    idem = text1 == text2 and "## 未覆盖 / 排除" in text1
    n_ok += int(idem)
    print(("ok   " if idem else "BAD  ") + "render idempotent + excluded section present")
    total = len(cases) + 2
    print(f"SELFTEST {'PASS' if n_ok == total else 'FAIL'}: {n_ok}/{total} expectations")
    return 0 if n_ok == total else 1


def main(argv=None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv[:1] == ["--selftest"]:
        return selftest()
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name, func in (("check", cmd_check), ("render", cmd_render)):
        p = sub.add_parser(name)
        p.add_argument("--map", default=str(MAP_DEFAULT))
        p.add_argument("--inventory", default=None, help="override the map's reader_inventory path")
        p.add_argument("--src", default=str(SRC_DEFAULT), help="legacy source directory")
        if name == "render":
            p.add_argument("-o", "--output")
            p.add_argument("--force", action="store_true",
                           help="write the Markdown even when the check FAILs (exit code stays 1)")
        p.set_defaults(func=func)
    a = ap.parse_args(argv)
    return a.func(a)


if __name__ == "__main__":
    sys.exit(main())
