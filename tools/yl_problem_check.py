#!/usr/bin/env python3
"""ProblemState type x state-field map cross-check (M3-01).

Bidirectional, fail-closed coverage between the exported `ProblemState.*` rows of
docs/m2/state-field-map.toml and the Fortran derived types declared under src/problem.
The type field names are derived MECHANICALLY from the map's `owner` paths (never from
`id`, which still carries Fortran spellings such as `gid_u`, `icreep`, `type_nalgo`), so
the mapping is a function, not a hand-maintained table.

Sub-commands
  check     parse the map and every src/problem/*.f90 type module, resolve both
            directions and apply rules 1-13 below; fail-closed
            (FAIL: n problems, <= 200 lines, exit 1) else a PASS summary (exit 0)
  render    map + parsed types -> the deterministic per-field Markdown table of
            docs/m3/M3-01-problemstate.md (stdout or -o). The full check runs first and
            on FAIL nothing is written (exit 1) unless --force (writes, still exits 1).
            The doc is therefore generated and cannot drift by hand.
  --selftest  run the built-in in-memory fixtures: one good sample that must PASS plus
            one mutation per rule that must FAIL with a specific substring

Usage
  python3 tools/yl_problem_check.py check  [--map docs/m2/state-field-map.toml]
                                           [--src src/problem]
                                           [--doc docs/m3/M3-01-problemstate.md]
  python3 tools/yl_problem_check.py render [--map ...] [--src ...]
                                           [-o docs/m3/M3-01-problemstate.md] [--force]
  python3 tools/yl_problem_check.py --selftest

Check rules
   1 map: TOML parses, version == 1, [[field]] non-empty; the exported set is RECOMPUTED
     as `compare.rule != "ignore"` and `owner` starts with `ProblemState.` (never
     hard-coded) and must be non-empty
   2 declaration grammar: every file under --src parses under the CLOSED grammar below.
     A statement the grammar does not recognise is a FAIL, never a silent skip.
   3 type graph: the root type (`problem_state_t`) exists; every `type(T)` component
     resolves to a type declared under --src; no duplicate type names; no cycles. An
     `opt_*` wrapper component is ALWAYS a leaf and is never descended into, so it is
     excluded from the reported type count
   4 forward coverage: every exported `ProblemState.*` owner path resolves, via the
     owner-path rule below, to exactly one declared leaf field. Zero matches is a FAIL;
     a path that stops on a non-leaf (a `type(T)` component) is a FAIL
   5 reverse coverage: every declared leaf field traces back to at least one map field id
     or carries an `!@m5-only: <reason>` marker. An unmarked orphan is a FAIL
   6 marker discipline: markers parse under the marker grammar below; an `@m5-only`
     reason is >= 12 printable characters; an `@m5-only` field that DOES resolve to a map
     id is a FAIL (stale marker); an `@map:` marker naming an id absent from the exported
     set is a FAIL
   7 injectivity, both directions: no two map fields may resolve to the same type field
     (this is what catches the `sections[].material` and `steps[0].output.frequency`
     owner collisions), and no map id may be claimed by two type fields
   8 dtype agreement: i32/i64 -> `integer` or `type(opt_int)`; f64 -> `real` or
     `type(opt_real)`; str -> `character` or `type(opt_text)`; bool -> `logical` or
     `type(opt_logical)`. An UNDECLARED mismatch is a FAIL. The map `dtype` is the legacy
     WIRE type -- it drives `yl_state_map.py gen-fortran` and is baked into the frozen
     M2-03 baselines -- while the ProblemState type carries the modern semantics, so the
     two may legitimately differ where the bridge converts. Such a conversion must be
     DECLARED with an `!@repr: <dtype> from <dtype>; <reason>` marker whose `from` names
     the map row's actual dtype; the declared target then replaces the expectation. A
     `from` that does not match the map row is a FAIL, so the rule keeps its value. The
     motivating case is `solver%symmetric`, which the map records as i32 (`nonsym` is a
     0/1 flag at Solver.f90:7240) and the type models as `type(opt_logical)`, with the
     polarity inverted in the bridge
   9 optionality / ADR-0002 sentinel ban, DEFAULT-DENY: every leaf that maps to an
     exported row must be able to say `unset`, so it must be an `opt_*` wrapper or an
     allocatable collection. A bare `integer` / `real` / `character` / `logical` on a
     mapped field is a FAIL unless it carries `!@required: <reason>` recording why the
     value can never be absent. The default is inverted deliberately: keying the rule off
     an opt-in (`optional = true` on the row, or an `@optional` marker) left it DEAD,
     because the map carries no `optional` key on any of its rows and the types carry no
     `@optional` marker -- stripping every wrapper from the real module still passed. The
     converse is also checked: an `opt_*` component marked `@required`, or whose map row
     says `optional = false`, is a stale FAIL
  10 legacy slot names: the deny list is built MECHANICALLY from the map as
     {leaf name of every `legacy_symbol`} u {[shape_symbols] keys} u {leaf of every
     `derived.counts.*` id}, minus every segment that the exported `ProblemState.*` owner
     paths themselves use (YL sometimes already spells a name well: `name`, `density`,
     `thickness`, `material`, `class`, `nu`, `e`, `special`). A component name matching
     the remainder (case-insensitively) is a FAIL. The PASS line reports the size.
  11 case collisions: Fortran is case-insensitive, so two components of one type whose
     names differ only by case are a FAIL (they would be the same component)
  12 doc agreement (only when --doc is given): the file must exist and must equal exactly
     what `render` produces from the same map and types
  13 wrapper integrity: the `opt_*` bodies are not put through the component grammar and
     are never walked as nested types, so their load-bearing structure is checked directly
     instead. For every DECLARED wrapper, four assertions: the component block is
     `private`; a component named `has` exists; it is `logical`; and it carries the default
     initializer `= .false.`. A wrapper that is used but never declared under --src is also
     a FAIL. Without that initializer every instance starts undefined and the unset
     discipline the whole type layer rests on is void, which neither the gate nor the
     Fortran self-test would otherwise notice. Procedure bodies are still not parsed

Declaration grammar (closed inside a type block)

    <component>  ::= <type-spec> [ "," <attr> ]* "::" <entity> { "," <entity> }
    <type-spec>  ::= "integer" | "integer(" <kind> ")"
                   | "real"    | "real(" <kind> ")"
                   | "logical"
                   | "character(len=:)"
                   | "type(" <name> ")"
    <kind>       ::= [ "kind=" ] ( "int32" | "int64" | "real32" | "real64" | "dp" | "sp" )
    <attr>       ::= "allocatable"
    <entity>     ::= <name> [ "(" ":" { "," ":" } ")" ]

  Handled: `type, public :: name_t` headers, `type(opt_int) :: field` components,
  `real(real64), allocatable :: xyz(:)`, several entities on one line, a trailing
  `! comment`, and `&` continuation lines (joined before matching; a joined line that
  still does not match is a FAIL). Deliberately REJECTED, each with its own message, so
  that the reject is visible rather than silent: initializers (`integer :: n = 0`, which
  would defeat the unset discipline), `pointer` / `target` / `dimension` attributes,
  explicit or assumed-size bounds (`(3)`, `(*)`; extents are derived, never declared),
  `character(len=32)` (only deferred-length strings are allowed), `sequence`, `extends`,
  a type-bound `contains`, and preprocessor directives.

  Two scoped, documented exceptions, both reported rather than silent: the bodies of the
  `opt_int` / `opt_real` / `opt_text` / `opt_logical` wrapper types are NOT parsed (their
  `private` components and `has = .false.` initializers ARE the unset mechanism this tool
  checks for, so applying the component grammar to them would be self-contradictory; the
  wrapper is recorded by name, so a duplicate definition is still caught, but it is never
  descended into and always resolves as a leaf), and a `program` unit is skipped, since it
  can hold no ProblemState type -- a `type` header inside one is a FAIL, not a skip.

  Outside a type block the grammar is closed over the module prologue only: `module`,
  `end module`, `use`, `implicit none`, `private`, `public`, `save`, `parameter`
  declarations, and `interface` ... `end interface` blocks. An unrecognised prologue
  statement is a FAIL. Everything after a module-level `contains` is procedure body and
  is not parsed: this tool checks types, not code.

Marker grammar (the trailing comment of a component declaration)

    <comment>    ::= <prose> | <marker> { ";" <marker> }
    <marker>     ::= "@m5-only:" <reason>      reason >= 12 printable characters
                   | "@optional"
                   | "@required:" <reason>     why a mapped field may be a bare intrinsic
                   | "@map:" <field-id>        explicit provenance for a field the owner
                                               path cannot reach mechanically
                   | "@repr:" <to> "from" <from> ";" <reason>
                                               a declared representation change; <to> and
                                               <from> are map dtypes, must differ, and
                                               <from> must equal the map row's dtype
    <prose>      ::= any text whose first non-blank character is not "@"

  A comment that starts with "@" but matches no marker is a FAIL (a typo such as
  `!@m5only` must not read as prose). At most one of each marker per component. A `;`
  separates markers, so a piece that does not itself begin with "@" continues the previous
  marker's value: that is what lets an `@repr` or `@m5-only` reason contain a semicolon.

Owner-path -> Fortran-path rule (applied left to right, `ProblemState.` stripped)

   1 the first remaining segment is a component of the root type
   2 `steps[0]` -> `steps(k)`: the literal index is dropped, the segment is a collection
   3 a segment ending in `[]` is an allocatable rank-1 collection and takes a loop index;
     indices are assigned by collection ordinal (1st `i`, 2nd `j`, 3rd `l`, 4th `m`) with
     `steps` always taking `k`, which is the step index throughout the M3 docs
   4 every remaining `.x` becomes `%x` verbatim; no renaming is permitted, which is what
     makes the mapping mechanical and keeps `gid_` / `icreep` spellings (which live only
     in the map `id`) out of the types
   5 a leaf declared as an allocatable array is written with its deferred shape, e.g.
     `%xyz(:)`; a deferred-length string stays scalar
  Component matching is case-insensitive (Fortran semantics), which is why rule 11 exists.

Only the Python standard library is used. Sources are decoded as latin-1 via the M1
helper imported from tools/yl_io_inventory.py, matching tools/yl_state_map.py.
"""
from __future__ import annotations

import argparse
import re
import sys
import tomllib
from collections import defaultdict
from pathlib import Path
from typing import NamedTuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
from yl_io_inventory import split_lines  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent
MAP_DEFAULT = REPO_ROOT / "docs" / "m2" / "state-field-map.toml"
SRC_DEFAULT = REPO_ROOT / "src" / "problem"
DOC_DEFAULT = REPO_ROOT / "docs" / "m3" / "M3-01-problemstate.md"

ROOT_TYPE = "problem_state_t"
OWNER_PREFIX = "ProblemState."
OBJECT_ORDER = ["case", "mesh", "materials", "sections", "amplitudes", "interactions", "steps", "solver"]
INDEX_LETTERS = ["i", "j", "l", "m", "n"]
STEP_INDEX = "k"

OPT_WRAPPERS = {"opt_int": "integer", "opt_real": "real", "opt_text": "character",
                "opt_logical": "logical", "opt_bool": "logical"}


def is_nested(c: "Comp", types: dict) -> bool:
    """True only for a component that is a ProblemState member type to descend into.
    An `opt_*` wrapper is ALWAYS a leaf: it is registered in `types` so that a duplicate
    definition is still caught, but it carries the value, it does not contain fields."""
    return (c.base == "type" and (c.type_name or "").lower() in types
            and (c.type_name or "").lower() not in OPT_WRAPPERS)
DTYPE_BASE = {"i32": "integer", "i64": "integer", "f64": "real", "str": "character", "bool": "logical"}

# --- grammar ------------------------------------------------------------------------------
KINDS = r"(?:kind\s*=\s*)?(?:int32|int64|real32|real64|dp|sp)"
TS_INTEGER = re.compile(r"^integer\s*(?:\(\s*" + KINDS + r"\s*\))?$", re.I)
TS_REAL = re.compile(r"^real\s*(?:\(\s*" + KINDS + r"\s*\))?$", re.I)
TS_LOGICAL = re.compile(r"^logical$", re.I)
TS_CHARACTER = re.compile(r"^character\s*\(\s*len\s*=\s*:\s*\)$", re.I)
TS_CHAR_BAD = re.compile(r"^character\b", re.I)
TS_TYPE = re.compile(r"^type\s*\(\s*([A-Za-z_]\w*)\s*\)$", re.I)
ENTITY = re.compile(r"^([A-Za-z_]\w*)\s*(\(\s*:(?:\s*,\s*:)*\s*\))?$")
ENTITY_BAD_DIMS = re.compile(r"^([A-Za-z_]\w*)\s*\(")

TYPE_HEADER = re.compile(r"^type\s*(?:,\s*(?:public|private)\s*)?::\s*([A-Za-z_]\w*)$", re.I)
TYPE_HEADER_LOOSE = re.compile(r"^type\b(?!\s*\()", re.I)
END_TYPE = re.compile(r"^end\s*type\b", re.I)
PROLOGUE_OK = re.compile(
    r"^(module\s+[A-Za-z_]\w*|end\s*module(\s+[A-Za-z_]\w*)?|use\b|implicit\s+none\b|"
    r"private\s*$|public\b|save\s*$|.*\bparameter\b.*::|interface\b|end\s*interface\b)", re.I)

MARKER_M5 = "m5-only"
MARKER_REPR = "repr"
MARKER_NAMES = {MARKER_M5, "optional", "required", "map", MARKER_REPR}
REPR_VALUE = re.compile(r"^([a-z0-9]+)\s+from\s+([a-z0-9]+)\s*;\s*(.+)$", re.I)
MARKER = re.compile(r"^@([a-z0-9-]+)\s*(?::\s*(.*))?$")
FIELD_ID_RE = re.compile(r"^[a-z][a-z0-9]*(\.[A-Za-z0-9_]+)+$")
OWNER_SEG = re.compile(r"^([A-Za-z_]\w*)(\[\d*\])?$")
PRINTABLE = re.compile(r"^[ -~]+$")
WRAPPER_HAS = re.compile(r"^(.*?)\s*::\s*has\s*(=\s*(.*))?$", re.I)
WRAPPER_FALSE = re.compile(r"^\.false\.$", re.I)
M5_REASON_MIN = 12


class Comp(NamedTuple):
    """One declared component of one derived type."""
    name: str
    base: str               # integer | real | character | logical | type
    type_name: str | None   # for base == "type"
    allocatable: bool
    rank: int               # 0 scalar, >0 deferred-shape array
    markers: dict           # marker name -> value ("" when the marker takes none)
    where: str              # file:line
    spec: str = ""          # the type-spec exactly as declared


class TypeDef(NamedTuple):
    name: str
    where: str
    comps: list


class Field(NamedTuple):
    """A resolved leaf field of the ProblemState tree."""
    path: list              # [(component, index letter or None), ...]
    comp: Comp
    owner: str              # mechanical owner path, ProblemState.<...>


def split_comment(line: str) -> tuple[str, str]:
    """(code, comment) honouring Fortran quoting; mirrors yl_io_inventory.strip_comment."""
    out, quote = [], None
    for i, ch in enumerate(line):
        if quote:
            out.append(ch)
            if ch == quote:
                quote = None
        elif ch in ("'", '"'):
            quote = ch
            out.append(ch)
        elif ch == "!":
            return "".join(out), line[i + 1:].strip()
        else:
            out.append(ch)
    return "".join(out), ""


def split_top(text: str, sep: str = ",") -> list[str]:
    """Split on `sep` at paren depth 0."""
    out, depth, cur = [], 0, []
    for ch in text:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == sep and depth == 0:
            out.append("".join(cur).strip())
            cur = []
        else:
            cur.append(ch)
    out.append("".join(cur).strip())
    return out


# --- Fortran source parsing ---------------------------------------------------------------
class Parser:
    """Parses the closed declaration grammar; every problem is recorded, never raised."""

    def __init__(self):
        self.types: dict = {}
        self.wrappers: dict = {}    # opt_* type name -> its body statements (unparsed)
        self.problems: list = []
        self.warnings: list = []

    def fail(self, msg: str):
        self.problems.append(msg)

    def parse_dir(self, root: Path):
        if not root.is_dir():
            self.fail(f"--src {root}: not a directory (rule 2)")
            return
        files = sorted(p for p in root.iterdir() if p.suffix.lower() in (".f90", ".F90"))
        if not files:
            self.fail(f"--src {root}: no Fortran source files (rule 2)")
        for p in files:
            self.parse_text(p.name, split_lines(p.read_bytes()))

    def parse_texts(self, texts: dict):
        for name in sorted(texts):
            self.parse_text(name, texts[name].split("\n"))

    def statements(self, name: str, lines: list):
        """Join `&` continuations into (line_no, code, comment) statements."""
        buf, cmts, start = "", [], None
        for no, raw in enumerate(lines, 1):
            code, cmt = split_comment(raw)
            code = code.strip()
            if code.startswith("#"):
                self.fail(f"{name}:{no}: preprocessor directive is not allowed (rule 2)")
                continue
            if buf:
                code = code.lstrip("&").strip()
            elif code:
                start = no
            if cmt:
                cmts.append(cmt)
            if code.endswith("&"):
                buf += code[:-1].strip() + " "
                continue
            stmt = (buf + code).strip()
            buf = ""
            if stmt:
                yield start, stmt, "; ".join(cmts)
            if not buf:
                cmts = []
        if buf:
            self.fail(f"{name}:{start}: continuation `&` never terminates (rule 2)")

    def parse_text(self, name: str, lines: list):
        cur: TypeDef | None = None
        after_contains = False
        skip_unit, skip_type = False, None
        for no, stmt, cmt in self.statements(name, lines):
            where = f"{name}:{no}"
            if skip_type:
                if END_TYPE.match(stmt):
                    skip_type = None
                else:
                    self.wrappers[skip_type].append((no, stmt))
                continue
            if skip_unit:
                if re.match(r"^end\s*program\b", stmt, re.I):
                    skip_unit = False
                elif TYPE_HEADER.match(stmt):
                    self.fail(f"{where}: type `{TYPE_HEADER.match(stmt).group(1)}` is declared "
                              f"inside a program unit, where the map can never reach it; "
                              f"ProblemState types must live in a module (rule 2)")
                continue
            if cur is None:
                if re.match(r"^program\s+[A-Za-z_]\w*$", stmt, re.I):
                    skip_unit = True     # a program unit can hold no ProblemState type
                    continue
                if after_contains:
                    continue
                if re.match(r"^contains$", stmt, re.I):
                    after_contains = True
                    continue
                m = TYPE_HEADER.match(stmt)
                if m:
                    tn = m.group(1)
                    if tn.lower() in self.types:
                        self.fail(f"{where}: duplicate type `{tn}`, first at "
                                  f"{self.types[tn.lower()].where} (rule 3)")
                    cur = TypeDef(tn, where, [])
                    self.types[tn.lower()] = cur
                    if tn.lower() in OPT_WRAPPERS:
                        # primitive layer: body not put through the component grammar, but
                        # kept verbatim for the narrow structural check of rule 13
                        cur, skip_type = None, tn.lower()
                        self.wrappers[skip_type] = []
                    continue
                if TYPE_HEADER_LOOSE.match(stmt):
                    self.fail(f"{where}: type header does not match "
                              f"`type[, public] :: name_t`: {stmt!r} (rule 2)")
                    continue
                if not PROLOGUE_OK.match(stmt):
                    self.fail(f"{where}: unrecognised module statement {stmt!r} (rule 2)")
                continue
            if END_TYPE.match(stmt):
                if not cur.comps:
                    self.fail(f"{where}: type `{cur.name}` has no components (rule 2)")
                cur = None
                continue
            self.component(cur, where, stmt, cmt)
        if cur is not None:
            self.fail(f"{cur.where}: type `{cur.name}` is never closed by `end type` (rule 2)")

    def component(self, td: TypeDef, where: str, stmt: str, cmt: str):
        low = stmt.lower()
        for bad, why in (("sequence", "`sequence` types are not allowed"),
                         ("contains", "type-bound procedures are not allowed"),
                         ("procedure", "type-bound procedures are not allowed")):
            if re.match(r"^" + bad + r"\b", low):
                self.fail(f"{where}: in type `{td.name}`: {why} (rule 2)")
                return
        if "::" not in stmt:
            self.fail(f"{where}: in type `{td.name}`: component declaration needs `::`: "
                      f"{stmt!r} (rule 2)")
            return
        decl, entities = stmt.split("::", 1)
        parts = split_top(decl)
        spec, attrs = parts[0].strip(), [p.strip().lower() for p in parts[1:] if p.strip()]
        markers = self.markers(where, td, cmt)
        base, type_name = self.type_spec(where, td, spec)
        if base is None:
            return
        alloc = False
        for a in attrs:
            if a == "allocatable":
                alloc = True
            elif a.startswith("dimension"):
                self.fail(f"{where}: in type `{td.name}`: `dimension` attribute is not "
                          f"allowed, declare the shape on the entity (rule 2)")
                return
            else:
                self.fail(f"{where}: in type `{td.name}`: attribute `{a}` is not allowed "
                          f"(rule 2)")
                return
        if base == "character" and not alloc:
            self.fail(f"{where}: in type `{td.name}`: `character(len=:)` needs "
                      f"`, allocatable` (rule 2)")
            return
        for ent in split_top(entities):
            if not ent:
                self.fail(f"{where}: in type `{td.name}`: empty entity in {stmt!r} (rule 2)")
                continue
            if "=" in ent:
                self.fail(f"{where}: in type `{td.name}`: initializer in {ent!r} defeats the "
                          f"unset discipline (rule 2)")
                continue
            m = ENTITY.match(ent)
            if not m:
                b = ENTITY_BAD_DIMS.match(ent)
                if b:
                    self.fail(f"{where}: in type `{td.name}`: {b.group(1)} declares explicit "
                              f"or assumed-size bounds; only deferred shape `(:)` is allowed "
                              f"(rule 2)")
                else:
                    self.fail(f"{where}: in type `{td.name}`: unrecognised entity {ent!r} "
                              f"(rule 2)")
                continue
            cname, dims = m.group(1), m.group(2)
            rank = dims.count(":") if dims else 0
            if rank and not alloc:
                self.fail(f"{where}: in type `{td.name}`: `{cname}` has deferred shape "
                          f"without `, allocatable` (rule 2)")
                continue
            if base == "real" and not re.search(r"\(", spec):
                self.warnings.append(f"{where}: `{cname}` declared as bare `real` without an "
                                     f"explicit kind")
            for prev in td.comps:
                if prev.name.lower() == cname.lower():
                    self.fail(f"{where}: in type `{td.name}`: component `{cname}` collides "
                              f"with `{prev.name}` at {prev.where}; Fortran is "
                              f"case-insensitive (rule 11)")
                    break
            else:
                td.comps.append(Comp(cname, base, type_name, alloc, rank, markers, where, spec.strip()))

    def type_spec(self, where: str, td: TypeDef, spec: str):
        s = spec.strip()
        if TS_INTEGER.match(s):
            return "integer", None
        if TS_REAL.match(s):
            return "real", None
        if TS_LOGICAL.match(s):
            return "logical", None
        if TS_CHARACTER.match(s):
            return "character", None
        m = TS_TYPE.match(s)
        if m:
            return "type", m.group(1)
        if TS_CHAR_BAD.match(s):
            self.fail(f"{where}: in type `{td.name}`: only `character(len=:)` is allowed, "
                      f"got {s!r} (rule 2)")
            return None, None
        self.fail(f"{where}: in type `{td.name}`: type-spec {s!r} is outside the closed "
                  f"grammar (rule 2)")
        return None, None

    def markers(self, where: str, td: TypeDef, cmt: str) -> dict:
        out: dict = {}
        text = cmt.strip()
        if not text or not text.startswith("@"):
            return out
        pieces: list = []
        for piece in text.split(";"):
            piece = piece.strip()
            if not piece:
                continue
            if piece.startswith("@") or not pieces:
                pieces.append(piece)
            else:                       # a reason may itself contain `;`
                pieces[-1] += "; " + piece
        for piece in pieces:
            m = MARKER.match(piece)
            if not m or m.group(1) not in MARKER_NAMES:
                self.fail(f"{where}: in type `{td.name}`: malformed marker {piece!r}; "
                          f"expected @m5-only:<reason> | @optional | @required:<reason> | @map:<id> "
                          f"| @repr:<dtype> from <dtype>; <reason> "
                          f"(rule 6)")
                continue
            key, val = m.group(1), (m.group(2) or "").strip()
            if key in out:
                self.fail(f"{where}: in type `{td.name}`: marker @{key} repeated (rule 6)")
                continue
            if key in (MARKER_M5, "required"):
                if m.group(2) is None or not val:
                    self.fail(f"{where}: in type `{td.name}`: @{key} needs "
                              f"`: <reason>` (rule 6)")
                    continue
                if len(val) < M5_REASON_MIN or not PRINTABLE.match(val):
                    self.fail(f"{where}: in type `{td.name}`: @{key} reason {val!r} must be "
                              f">= {M5_REASON_MIN} printable characters (rule 6)")
                    continue
            elif key == MARKER_REPR:
                r = REPR_VALUE.match(val)
                if not r:
                    self.fail(f"{where}: in type `{td.name}`: @repr needs "
                              f"`: <dtype> from <dtype>; <reason>`, got {val!r} (rule 6)")
                    continue
                to, frm, why = r.group(1).lower(), r.group(2).lower(), r.group(3).strip()
                if to not in DTYPE_BASE or frm not in DTYPE_BASE:
                    self.fail(f"{where}: in type `{td.name}`: @repr dtype must be one of "
                              f"{', '.join(sorted(DTYPE_BASE))}, got {to!r} from {frm!r} "
                              f"(rule 6)")
                    continue
                if to == frm:
                    self.fail(f"{where}: in type `{td.name}`: @repr declares no change "
                              f"({to} from {frm}) (rule 6)")
                    continue
                if len(why) < M5_REASON_MIN or not PRINTABLE.match(why):
                    self.fail(f"{where}: in type `{td.name}`: @repr reason {why!r} must be "
                              f">= {M5_REASON_MIN} printable characters (rule 6)")
                    continue
                val = f"{to} from {frm}; {why}"
            elif key == "map":
                if not val or not FIELD_ID_RE.match(val):
                    self.fail(f"{where}: in type `{td.name}`: @map needs a field id, "
                              f"got {val!r} (rule 6)")
                    continue
            elif val:
                self.fail(f"{where}: in type `{td.name}`: @{key} takes no value, "
                          f"got {val!r} (rule 6)")
                continue
            out[key] = val
        return out


# --- map helpers --------------------------------------------------------------------------
def exported(doc: dict) -> list:
    """Rule 1: recomputed, never hard-coded."""
    out = []
    for f in doc.get("field", []):
        if not str(f.get("owner", "")).startswith(OWNER_PREFIX):
            continue
        if (f.get("compare") or {}).get("rule") == "ignore":
            continue
        out.append(f)
    return out


def deny_list(doc: dict, rows: list) -> tuple[set, int]:
    """Rule 10: harvested mechanically from the map, minus the names the clean owner
    paths themselves already use. Returns (deny, raw harvest size)."""
    raw = set()
    for f in doc.get("field", []):
        sym = str(f.get("legacy_symbol", "") or "")
        if sym:
            raw.add(re.split(r"[%.]", sym)[-1].strip().lower())
        fid = str(f.get("id", ""))
        if fid.startswith("derived.counts."):
            raw.add(fid.rsplit(".", 1)[-1].lower())
    raw |= {str(s).lower() for s in (doc.get("shape_symbols") or {})}
    raw.discard("")
    keep = set()
    for f in rows:
        for seg in owner_segments(str(f["owner"])):
            keep.add(seg.lower())
    return raw - keep, len(raw)


def owner_segments(owner: str) -> list:
    body = owner[len(OWNER_PREFIX):] if owner.startswith(OWNER_PREFIX) else owner
    return [re.sub(r"\[\d*\]$", "", s) for s in body.split(".") if s]


def parse_owner(owner: str):
    """`ProblemState.steps[0].boundary[].value` -> [('steps', True), ('boundary', True),
    ('value', False)]; None when the path is malformed."""
    if not owner.startswith(OWNER_PREFIX):
        return None
    out = []
    for seg in owner[len(OWNER_PREFIX):].split("."):
        m = OWNER_SEG.match(seg)
        if not m:
            return None
        out.append((m.group(1), m.group(2) is not None))
    return out or None


def index_letter(name: str, ordinal: int) -> str:
    if name.lower() == "steps":
        return STEP_INDEX
    return INDEX_LETTERS[ordinal] if ordinal < len(INDEX_LETTERS) else f"i{ordinal}"


def fortran_path(path: list, comp: Comp, root: str | None = None) -> str:
    """path is [(Comp, index letter or None), ...] ending at `comp`."""
    parts = []
    for c, idx in path:
        parts.append(f"{c.name}({idx})" if idx else c.name)
    tail = parts[-1]
    if comp.rank:
        tail += "(" + ",".join([":"] * comp.rank) + ")"
        parts[-1] = tail
    p = "%".join(parts)
    return f"{root}%{p}" if root else p


# --- checker ------------------------------------------------------------------------------
class Checker:
    def __init__(self, doc: dict, parser: Parser):
        self.doc = doc
        self.p = parser
        self.problems: list = list(parser.problems)
        self.warnings: list = list(parser.warnings)
        self.rows: list = []
        self.fields: dict = {}      # fortran path (lower) -> Field
        self.by_type: dict = defaultdict(list)   # fortran path (lower) -> [map ids]
        self.by_id: dict = {}       # map id -> fortran path
        self.deny: set = set()
        self.deny_raw = 0
        self.stats: dict = {}

    def fail(self, msg: str):
        self.problems.append(msg)

    def run(self) -> list:
        self.rule1()
        if self.rule3():
            self.enumerate_fields()
            self.rule10_11()
            self.rule4()
            self.rule5_6()
            self.rule7()
            self.rule8_9()
            self.rule13()
        return self.problems

    # rule 1
    def rule1(self):
        if self.doc.get("version") != 1:
            self.fail(f"map: version must be 1, got {self.doc.get('version')!r} (rule 1)")
        if not self.doc.get("field"):
            self.fail("map: no [[field]] entries (rule 1)")
        self.rows = exported(self.doc)
        if not self.rows:
            self.fail("map: the exported ProblemState.* set is empty (rule 1)")
        self.deny, self.deny_raw = deny_list(self.doc, self.rows)

    # rule 3
    def rule3(self) -> bool:
        types = self.p.types
        if ROOT_TYPE not in types:
            self.fail(f"types: root type `{ROOT_TYPE}` is not declared under --src (rule 3)")
            return False
        for td in types.values():
            for c in td.comps:
                if c.base == "type" and c.type_name.lower() not in types:
                    self.fail(f"{c.where}: `{td.name}%{c.name}` uses undeclared type "
                              f"`{c.type_name}` (rule 3)")
        seen: set = set()

        def walk(tn: str, stack: tuple):
            if tn in stack:
                self.fail(f"types: cycle through `{' -> '.join(stack + (tn,))}` (rule 3)")
                return
            seen.add(tn)
            for c in types.get(tn, TypeDef("", "", [])).comps:
                if is_nested(c, types):
                    walk(c.type_name.lower(), stack + (tn,))
        walk(ROOT_TYPE, ())
        return not any("cycle through" in p for p in self.problems)

    def enumerate_fields(self):
        """Depth-first walk of the type graph from the root, enumerating every leaf."""
        types = self.p.types

        def walk(tn: str, path: list, owner: list, ordinal: int):
            for c in types[tn].comps:
                idx = None
                nordinal = ordinal
                if is_nested(c, types):
                    if c.allocatable and c.rank == 1:
                        idx = index_letter(c.name, ordinal)
                        nordinal = ordinal + 1
                    elif c.allocatable or c.rank:
                        self.fail(f"{c.where}: nested collection `{c.name}` must be a rank-1 "
                                  f"`allocatable` (rule 2)")
                        continue
                    walk(c.type_name.lower(), path + [(c, idx)],
                         owner + [c.name + ("[]" if idx else "")], nordinal)
                    continue
                full = path + [(c, None)]
                key = fortran_path(full, c).lower()
                own = OWNER_PREFIX + ".".join(owner + [c.name])
                if key in self.fields:
                    self.fail(f"{c.where}: duplicate field path `{key}` (rule 11)")
                    continue
                self.fields[key] = Field(full, c, own)
        walk(ROOT_TYPE, [], [], 0)

    # rule 10 + 11 (11 is also enforced per type during parsing)
    def rule10_11(self):
        for f in self.fields.values():
            if f.comp.name.lower() in self.deny:
                self.fail(f"{f.comp.where}: component `{f.comp.name}` is a legacy slot name "
                          f"harvested from the map (rule 10)")

    def resolve(self, owner: str):
        """Owner path -> (key, Field) or (None, reason)."""
        segs = parse_owner(owner)
        if segs is None:
            return None, f"owner path {owner!r} is malformed"
        types = self.p.types
        tn, path, ordinal = ROOT_TYPE, [], 0
        for i, (name, indexed) in enumerate(segs):
            comp = next((c for c in types[tn].comps if c.name.lower() == name.lower()), None)
            if comp is None:
                return None, f"no component `{name}` in type `{types[tn].name}`"
            last = i == len(segs) - 1
            if is_nested(comp, types):
                if last:
                    return None, (f"resolves to `{comp.type_name}`, which is a nested type, "
                                  f"not a leaf field")
                idx = index_letter(comp.name, ordinal) if indexed else None
                if indexed and not (comp.allocatable and comp.rank == 1):
                    return None, f"`{comp.name}` is indexed in the map but is not a collection"
                if idx:
                    ordinal += 1
                path.append((comp, idx))
                tn = comp.type_name.lower()
                continue
            if not last:
                return None, f"`{comp.name}` is a leaf but the owner path continues"
            path.append((comp, None))
            return fortran_path(path, comp).lower(), self.fields.get(fortran_path(path, comp).lower())
        return None, "empty owner path"

    # rule 4
    def rule4(self):
        for f in self.rows:
            owner, fid = str(f["owner"]), str(f["id"])
            key, res = self.resolve(owner)
            if key is None:
                self.fail(f"map field `{fid}` owner {owner}: {res} (rule 4)")
                continue
            if res is None:
                self.fail(f"map field `{fid}` owner {owner}: resolved path `{key}` is not an "
                          f"enumerated leaf (rule 4)")
                continue
            self.by_type[key].append(fid)
            self.by_id[fid] = key

    # rules 5 and 6
    def rule5_6(self):
        ids = {str(f["id"]) for f in self.rows}
        for key, f in self.fields.items():
            mk = f.comp.markers
            if "map" in mk:
                mid = mk["map"]
                if mid not in ids:
                    self.fail(f"{f.comp.where}: @map:{mid} is not an exported map field id "
                              f"(rule 6)")
                else:
                    self.by_type[key].append(mid)
                    self.by_id.setdefault(mid, key)
            mapped = bool(self.by_type.get(key))
            if MARKER_M5 in mk:
                if mapped:
                    self.fail(f"{f.comp.where}: `{self.show(key)}` carries a stale @m5-only marker but "
                              f"resolves to map field(s) {', '.join(self.by_type[key])} "
                              f"(rule 6)")
                continue
            if not mapped:
                self.fail(f"{f.comp.where}: orphan field `{self.show(key)}` traces to no map id and "
                          f"carries no @m5-only marker (rule 5)")

    # rule 7
    def rule7(self):
        for key, ids in sorted(self.by_type.items()):
            if len(set(ids)) > 1:
                self.fail(f"type field `{self.show(key)}` is claimed by {len(set(ids))} map fields: "
                          f"{', '.join(sorted(set(ids)))} (rule 7)")
        owners: dict = defaultdict(list)
        for key, ids in self.by_type.items():
            for fid in set(ids):
                owners[fid].append(key)
        for fid, keys in sorted(owners.items()):
            if len(set(keys)) > 1:
                self.fail(f"map field `{fid}` is claimed by {len(set(keys))} type fields: "
                          f"{', '.join(self.show(k) for k in sorted(set(keys)))} (rule 7)")

    # rules 8 and 9
    def rule8_9(self):
        rows = {str(f["id"]): f for f in self.rows}
        for key, ids in sorted(self.by_type.items()):
            f = self.fields.get(key)
            if f is None:
                continue
            c = f.comp
            base = OPT_WRAPPERS.get((c.type_name or "").lower()) if c.base == "type" else c.base
            for fid in sorted(set(ids)):
                row = rows.get(fid)
                if row is None:
                    continue
                dtype = str(row.get("dtype"))
                want = DTYPE_BASE.get(dtype)
                if want is None:
                    self.fail(f"map field `{fid}`: unknown dtype {dtype!r} (rule 8)")
                    self.optionality_rule(key, f, row)
                    continue
                rep = REPR_VALUE.match(c.markers.get(MARKER_REPR, ""))
                if rep:
                    to, frm = rep.group(1).lower(), rep.group(2).lower()
                    if frm != dtype:
                        self.fail(f"{c.where}: `{self.show(key)}` declares `@repr: {to} from "
                                  f"{frm}` but map field `{fid}` is dtype {dtype}; the `from` "
                                  f"dtype must name the legacy wire type (rule 8)")
                    else:
                        want = DTYPE_BASE[to]
                if base != want:
                    extra = "" if rep else ("; declare an intended conversion with "
                                            "`!@repr: <dtype> from " + dtype + "; <reason>`")
                    self.fail(f"{c.where}: `{self.show(key)}` is `{self.decl_of(c)}` but map field "
                              f"`{fid}` is dtype {dtype} (expected {want} or "
                              f"the matching opt_* wrapper){extra} (rule 8)")
                self.optionality_rule(key, f, row)

    def show(self, key: str) -> str:
        f = self.fields.get(key)
        return fortran_path(f.path, f.comp) if f else key

    def decl_of(self, c: Comp) -> str:
        """The declaration exactly as written, so the generated doc shows the real type."""
        return (c.spec or c.base) + (", allocatable" if c.allocatable else "")

    def is_opt(self, c: Comp) -> bool:
        return c.base == "type" and (c.type_name or "").lower() in OPT_WRAPPERS

    def optionality_rule(self, key: str, f: Field, row: dict):
        """Rule 9, default-deny: a mapped leaf must be able to say `unset`. An `opt_*`
        wrapper or an allocatable does; a bare intrinsic does not, and is a FAIL unless
        `@required: <reason>` records why the value can never be absent. The default is
        inverted deliberately: keying the rule off an opt-in (`optional = true` on the row,
        or an `@optional` marker) made it dead against a map that carries neither."""
        c = f.comp
        marked = "optional" in c.markers
        row_opt = row.get("optional")
        wrapped = self.is_opt(c) or c.allocatable
        if not wrapped:
            if marked or row_opt is True:
                why = "the map row" if row_opt is True else "an @optional marker"
                self.fail(f"{c.where}: `{self.show(key)}` is optional per {why} but is "
                          f"declared `{self.decl_of(c)}`; ADR-0002 bans bare sentinels, use "
                          f"an opt_* wrapper or an allocatable collection (rule 9)")
            elif "required" not in c.markers:
                self.fail(f"{c.where}: `{self.show(key)}` is declared `{self.decl_of(c)}`, "
                          f"which cannot express unset; a mapped field needs an opt_* "
                          f"wrapper or an allocatable collection, or `!@required: <reason>` "
                          f"stating why it can never be absent (rule 9)")
        if self.is_opt(c) and (row_opt is False or "required" in c.markers):
            self.fail(f"{c.where}: `{self.show(key)}` is declared `{self.decl_of(c)}` but is marked "
                      f"required; the optionality wrapper is stale (rule 9)")

    # rule 13
    def rule13(self):
        """The wrapper bodies are not put through the component grammar, so check their
        one load-bearing property directly: `has` must be private and default `.false.`,
        or every wrapper starts life undefined and the whole unset discipline is void.
        Every DECLARED wrapper is checked, not only the ones currently used, and a wrapper
        that is used but never declared is a FAIL."""
        used = {(c.type_name or "").lower() for td in self.p.types.values() for c in td.comps
                if c.base == "type" and (c.type_name or "").lower() in OPT_WRAPPERS}
        for w in sorted(used | set(self.p.wrappers)):
            body = self.p.wrappers.get(w)
            if body is None:
                self.fail(f"types: wrapper `{w}` is used but its type is not declared under "
                          f"--src (rule 13)")
                continue
            where = self.p.types[w].where
            file = where.split(":")[0]
            if not any(re.match(r"^private$", b, re.I) for _, b in body):
                self.fail(f"{where}: wrapper `{w}` does not make its components `private`; "
                          f"the flag and the value must not be reachable without the "
                          f"accessors (rule 13)")
            hit = next(((n, WRAPPER_HAS.match(b)) for n, b in body if WRAPPER_HAS.match(b)),
                       None)
            if hit is None:
                self.fail(f"{where}: wrapper `{w}` declares no `has` component (rule 13)")
                continue
            n, m = hit
            kind, init = m.group(1).strip(), (m.group(3) or "").strip()
            if not re.match(r"^logical$", kind, re.I):
                self.fail(f"{file}:{n}: wrapper `{w}` declares `has` as {kind!r}, "
                          f"expected `logical` (rule 13)")
            if not WRAPPER_FALSE.match(init):
                self.fail(f"{file}:{n}: wrapper `{w}` declares `has` without the default "
                          f"initializer `= .false.`" + (f" (got {init!r})" if init else "") +
                          f"; every instance would start undefined and the unset "
                          f"discipline would be void (rule 13)")

    # rule 12
    def rule12(self, doc_path: Path | None):
        if doc_path is None:
            return
        if not doc_path.exists():
            self.fail(f"{doc_path}: --doc names a file that does not exist; run `render` "
                      f"(rule 12)")
            return
        want = render(self)
        got = doc_path.read_text(encoding="utf-8")
        if got != want:
            self.fail(f"{doc_path}: differs from `render` output; the field table is "
                      f"generated, re-run render (rule 12)")

    # reporting
    def summary(self) -> str:
        m5 = sum(1 for f in self.fields.values() if MARKER_M5 in f.comp.markers)
        opt = sum(1 for f in self.fields.values() if self.is_opt(f.comp))
        return (f"PASS: {len(self.rows)} exported ProblemState fields, "
                f"{len(self.fields)} type fields ({opt} optional, {m5} M5-only), "
                f"{sum(1 for t in self.p.types if t not in OPT_WRAPPERS)} types, "
                f"deny list {len(self.deny)}/{self.deny_raw} legacy slot names")


def report(ck: Checker) -> int:
    for w in ck.warnings:
        print("  WARN " + w)
    if ck.problems:
        print(f"FAIL: {len(ck.problems)} problems")
        for p in ck.problems[:200]:
            print("  " + p)
        return 1
    print(ck.summary())
    return 0


def load_all(a) -> Checker | None:
    try:
        doc = tomllib.loads(Path(a.map).read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError) as e:
        print(f"FAIL: 1 problems\n  {a.map}: {e}")
        return None
    p = Parser()
    try:
        p.parse_dir(Path(a.src))
    except OSError as e:
        print(f"FAIL: 1 problems\n  {a.src}: {e}")
        return None
    ck = Checker(doc, p)
    ck.run()
    return ck


def cmd_check(a) -> int:
    ck = load_all(a)
    if ck is None:
        return 1
    if not ck.problems:
        ck.rule12(Path(a.doc) if a.doc else None)
    return report(ck)


# --- render -------------------------------------------------------------------------------
def object_of(key: str) -> str:
    return key.split("%", 1)[0].split("(", 1)[0]


def object_key(name: str) -> tuple:
    return (OBJECT_ORDER.index(name), name) if name in OBJECT_ORDER else (len(OBJECT_ORDER), name)


def lifecycle(row: dict | None) -> tuple:
    """Mechanical: a row produced by a single `derived:*` rule is written by finalize;
    everything else is authored and arrives with the reader. The normalize/finalize split
    is refined in M3-02."""
    if row is None:
        return "-", "M5"
    src = row.get("source") or []
    if len(src) == 1 and str(src[0]).startswith("derived:"):
        return "finalized", "finalize"
    return "draft", "reader"


def optionality_of(ck: Checker, f: Field, row: dict | None) -> str:
    if f.comp.allocatable and f.comp.rank:
        return "collection"
    if ck.is_opt(f.comp) or "optional" in f.comp.markers or (row or {}).get("optional") is True:
        return "optional"
    return "required"


def render(ck: Checker) -> str:
    rows = {str(f["id"]): f for f in ck.rows}
    groups: dict = defaultdict(list)
    for key, f in ck.fields.items():
        groups[object_of(key)].append((key, f))
    out = ["# M3-01 ProblemState 逐字段表", "",
           "由 `python3 tools/yl_problem_check.py render` 生成，请勿手工编辑。",
           "字段名由 `docs/m2/state-field-map.toml` 的 `owner` 路径机械推导；"
           "`map id` 为该行的溯源，`M5-only` 表示本阶段无 legacy 槽位。", "",
           "可选性约定：`required` 在 finalize 后必定已设置；`optional` 未写入时为 unset，"
           "写入的零是真实的零；`collection` 区分未分配（unset）与零长（empty）。", "",
           f"字段总数 {len(ck.fields)}，其中已导出映射 {len(ck.by_id)} 项。", ""]
    for name in sorted(groups, key=object_key):
        items = sorted(groups[name])
        out.append(f"## {name} ({len(items)} fields)")
        out.append("")
        out.append("| field | type | unit | optionality | map id | lifecycle | owner |")
        out.append("|---|---|---|---|---|---|---|")
        for key, f in items:
            ids = sorted(set(ck.by_type.get(key, [])))
            row = rows.get(ids[0]) if ids else None
            stage, writer = lifecycle(row)
            if ids:
                prov = "`" + "`, `".join(ids) + "`"
                unit = str(row.get("unit", "1")) if row else "-"
            else:
                prov = "M5-only: " + f.comp.markers.get(MARKER_M5, "")
                unit = "-"
            out.append(f"| `{fortran_path(f.path, f.comp)}` | `{ck.decl_of(f.comp)}` | {unit} | "
                       f"{optionality_of(ck, f, row)} | {prov} | {stage} | {writer} |")
        out.append("")
    return "\n".join(out) + "\n"


def cmd_render(a) -> int:
    ck = load_all(a)
    if ck is None:
        return 1
    rc = report(ck)
    if rc and not a.force:
        return rc
    text = render(ck)
    if a.output:
        Path(a.output).write_text(text, encoding="utf-8")
    else:
        sys.stdout.write(text)
    return rc


# --- selftest -----------------------------------------------------------------------------
GOOD_TYPES = """\
module yl_problem_types
  use yl_problem_optional, only: opt_int, opt_real, opt_text
  implicit none
  private
  public :: problem_state_t

  type, public :: case_t
    character(len=:), allocatable :: name
    character(len=:), allocatable :: units   !@m5-only: authoring contract, no legacy slot
  end type case_t

  type, public :: node_t
    integer :: id  !@required: a node without an identifier cannot be read
    real(real64), allocatable :: xyz(:)
  end type node_t

  type, public :: mesh_t
    integer :: dimension  !@required: every deck states the spatial dimension
    type(node_t), allocatable :: nodes(:)
  end type mesh_t

  type, public :: material_t
    character(len=:), allocatable :: name
    type(opt_real) :: E                      ! Young modulus
    type(opt_real) :: density
    integer :: revision, edition             !@m5-only: two entities on one line
    real(real64), allocatable :: &
         trace(:)                            !@m5-only: joined continuation line
  end type material_t

  type, public :: boundary_t
    character(len=:), allocatable :: name
    type(opt_real) :: value
  end type boundary_t

  type, public :: step_t
    type(boundary_t), allocatable :: boundary(:)
  end type step_t

  type, public :: solver_t
    type(opt_logical) :: symmetric  !@repr: bool from i32; nonsym is a 0/1 flag
  end type solver_t

  type, public :: problem_state_t
    type(case_t) :: case
    type(mesh_t) :: mesh
    type(material_t), allocatable :: materials(:)
    type(step_t), allocatable :: steps(:)
    type(solver_t) :: solver
  end type problem_state_t
end module yl_problem_types
"""


def good_map() -> dict:
    def f(fid, owner, dtype, unit, sym, **kw):
        row = {"id": fid, "owner": owner, "dtype": dtype, "unit": unit,
               "legacy_symbol": sym, "source": ["R." + fid.replace(".", "_")],
               "compare": {"rule": "exact"}}
        row.update(kw)
        return row
    return {
        "version": 1,
        "shape_symbols": {"npoin": "count(mesh.nodes)", "nmats": "count(materials)"},
        "field": [
            f("case.name", "ProblemState.case.name", "str", "1", "global_var.title"),
            f("mesh.dimension", "ProblemState.mesh.dimension", "i32", "1", "global_var.ndimn"),
            f("mesh.nodes.id", "ProblemState.mesh.nodes[].id", "i32", "id", "global_var.lnods"),
            f("mesh.nodes.xyz", "ProblemState.mesh.nodes[].xyz", "f64", "m", "global_var.coord"),
            f("materials.name", "ProblemState.materials[].name", "str", "1",
              "materials.props%name"),
            f("materials.E", "ProblemState.materials[].E", "f64", "Pa",
              "materials.props%mechanical%solid%e", optional=True),
            f("materials.density", "ProblemState.materials[].density", "f64", "kg/m3",
              "materials.props%density", optional=True),
            f("steps0.boundary.set", "ProblemState.steps[0].boundary[].name", "str", "id",
              "prescribed.prescrib%nodfix"),
            f("steps0.boundary.value", "ProblemState.steps[0].boundary[].value", "f64", "m",
              "prescribed.prescrib%vdofix", optional=True),
            f("solver.symmetric", "ProblemState.solver.symmetric", "i32", "1",
              "solver.nonsym"),
            # not exported: exercises rule 1's recomputation
            {"id": "control.nonsym", "owner": "not_migrated", "dtype": "i32", "unit": "1",
             "legacy_symbol": "solver.nonsym", "source": ["R.x"],
             "compare": {"rule": "ignore"}, "reason": "switch"},
            {"id": "derived.counts.npoin", "owner": "derived", "dtype": "i32", "unit": "1",
             "legacy_symbol": "global_var.npoin", "source": ["derived:count"],
             "compare": {"rule": "ignore"}, "reason": "count"},
        ],
    }


GOOD_OPTIONAL = """\
module yl_problem_optional
  use iso_fortran_env, only: int32, real64
  implicit none
  private
  public :: opt_int, opt_real, opt_text, opt_logical

  type, public :: opt_int
    private
    logical :: has = .false.
    integer(int32) :: value = 0_int32
  end type opt_int

  type, public :: opt_real
    private
    logical :: has = .false.
    real(real64) :: value = 0.0_real64
  end type opt_real

  type, public :: opt_text
    private
    logical :: has = .false.
    character(len=:), allocatable :: value
  end type opt_text

  type, public :: opt_logical
    private
    logical :: has = .false.
    logical :: value = .false.
  end type opt_logical
end module yl_problem_optional
"""

GOOD_PROGRAM = """\
program yl_problem_selftest
  use yl_problem_optional, only: opt_int
  implicit none
  type(opt_int) :: probe
  integer :: n = 0
  n = n + 1
end program yl_problem_selftest
"""


def build(types: str = GOOD_TYPES, doc: dict | None = None, extra: dict | None = None) -> Checker:
    """Always parses the wrapper module alongside the types module, which is the real
    src/problem layout: registering `opt_*` in the type table must not turn an `opt_*`
    component into a nested type (the two-module regression)."""
    p = Parser()
    files = {"yl_problem_optional.f90": GOOD_OPTIONAL, "yl_problem_types.f90": types,
             "yl_problem_selftest.f90": GOOD_PROGRAM}
    files.update(extra or {})
    p.parse_texts(files)
    ck = Checker(doc if doc is not None else good_map(), p)
    ck.run()
    return ck


DIM = "    integer :: dimension  !@required: every deck states the spatial dimension\n"


def sub(old: str, new: str, text: str = GOOD_TYPES) -> str:
    assert old in text, old
    return text.replace(old, new, 1)


def self_cases() -> list:
    """(name, expected substring, checker factory) -- each must FAIL."""
    def drop_type_field():
        return build(sub("    type(opt_real) :: density\n", ""))

    def orphan():
        return build(sub("  type, public :: case_t\n",
                         "  type, public :: case_t\n    integer :: revision\n"))

    def dup_map_to_one_type():
        d = good_map()
        d["field"].append({"id": "materials.E_header", "owner": "ProblemState.materials[].E",
                           "dtype": "f64", "unit": "Pa", "legacy_symbol": "materials.props%e2",
                           "source": ["R.y"], "compare": {"rule": "exact"}})
        return build(GOOD_TYPES, d)

    def dup_type_to_one_map():
        return build(sub("    type(opt_real) :: density\n",
                         "    type(opt_real) :: density\n"
                         "    type(opt_real) :: rho   !@map: materials.density\n"))

    def optional_bare():
        return build(sub("    type(opt_real) :: value\n", "    real(real64) :: value\n"))

    def slot_name():
        return build(sub(DIM, DIM + "    integer :: npoin\n"))

    def bad_marker():
        return build(sub("!@m5-only: authoring contract, no legacy slot", "!@m5only whatever"))

    def short_reason():
        return build(sub("!@m5-only: authoring contract, no legacy slot", "!@m5-only: tiny"))

    def stale_marker():
        return build(sub("    type(opt_real) :: density\n",
                         "    type(opt_real) :: density   !@m5-only: this one is mapped\n"))

    def dead_map_marker():
        return build(sub("    type(opt_real) :: density\n",
                         "    type(opt_real) :: density   !@map: materials.no_such_row\n"))

    def unknown_decl():
        return build(sub(DIM, "    integer, pointer :: dimension\n"))

    def initializer():
        return build(sub(DIM, "    integer :: dimension = 0\n"))

    def explicit_bounds():
        return build(sub("    real(real64), allocatable :: xyz(:)\n",
                         "    real(real64), allocatable :: xyz(3)\n"))

    def fixed_char():
        return build(sub("    character(len=:), allocatable :: name\n",
                         "    character(len=32) :: name\n"))

    def prologue():
        return build(sub("  implicit none\n", "  implicit none\n  common /junk/ x\n"))

    def case_collision():
        return build(sub(DIM, DIM + "    integer :: DIMENSION\n"))

    def dtype_mismatch():
        d = good_map()
        next(r for r in d["field"] if r["id"] == "mesh.dimension")["dtype"] = "f64"
        return build(GOOD_TYPES, d)

    def stale_optional():
        d = good_map()
        next(r for r in d["field"] if r["id"] == "materials.E")["optional"] = False
        return build(GOOD_TYPES, d)

    def missing_root():
        return build(GOOD_TYPES.replace("problem_state_t", "root_t"))

    def unresolved_type():
        return build(sub("    type(case_t) :: case\n", "    type(missing_t) :: case\n"))

    def type_in_program():
        return build(extra={"yl_problem_selftest.f90": GOOD_PROGRAM.replace(
            "  integer :: n = 0\n",
            "  type, public :: stray_t\n    integer :: q\n  end type stray_t\n")})

    def wrapper_no_default():
        return build(extra={"yl_problem_optional.f90": GOOD_OPTIONAL.replace(
            "    logical :: has = .false.\n    real(real64) :: value",
            "    logical :: has\n    real(real64) :: value")})

    def wrapper_has_kind():
        return build(extra={"yl_problem_optional.f90": GOOD_OPTIONAL.replace(
            "  type, public :: opt_int\n    private\n    logical :: has",
            "  type, public :: opt_int\n    private\n    integer :: has")})

    def wrapper_no_has():
        return build(extra={"yl_problem_optional.f90": GOOD_OPTIONAL.replace(
            "    logical :: has = .false.\n    character(len=:), allocatable :: value",
            "    character(len=:), allocatable :: value")})

    def wrapper_not_private():
        return build(extra={"yl_problem_optional.f90": GOOD_OPTIONAL.replace(
            "  type, public :: opt_text\n    private\n",
            "  type, public :: opt_text\n")})

    def wrapper_missing():
        return build(extra={"yl_problem_optional.f90":
                            GOOD_OPTIONAL.replace("opt_logical", "opt_unused")})

    def bare_unmarked():
        return build(sub(DIM, "    integer :: dimension\n"))

    def wrappers_stripped():
        """The lead's reproduction: strip every optionality wrapper from the good sample.
        Nothing opts in, so this is exactly the case the old opt-in rule 9 waved through."""
        t = GOOD_TYPES
        for w, bare in (("type(opt_int) ::", "integer(int32) ::"),
                        ("type(opt_real) ::", "real(real64) ::"),
                        ("type(opt_text) ::", "character(len=:), allocatable ::"),
                        ("type(opt_logical) ::", "logical ::")):
            t = t.replace(w, bare)
        return build(t)

    def undeclared_repr():
        return build(sub("  !@repr: bool from i32; nonsym is a 0/1 flag\n", "\n"))

    def repr_wrong_from():
        return build(sub("@repr: bool from i32;", "@repr: bool from f64;"))

    def repr_malformed():
        return build(sub("@repr: bool from i32;", "@repr: bool i32;"))

    def bad_version():
        d = good_map()
        d["version"] = 2
        return build(GOOD_TYPES, d)

    def owner_not_leaf():
        d = good_map()
        next(r for r in d["field"] if r["id"] == "case.name")["owner"] = "ProblemState.case"
        return build(GOOD_TYPES, d)

    return [
        ("rule 1  version",            "version must be 1",                  bad_version),
        ("rule 2  unknown attribute",  "attribute `pointer` is not allowed", unknown_decl),
        ("rule 2  initializer",        "initializer in",                     initializer),
        ("rule 2  explicit bounds",    "explicit or assumed-size bounds",    explicit_bounds),
        ("rule 2  fixed-length char",  "only `character(len=:)`",            fixed_char),
        ("rule 2  unknown prologue",   "unrecognised module statement",      prologue),
        ("rule 2  type in program",    "inside a program unit",              type_in_program),
        ("rule 3  missing root",       "root type `problem_state_t`",        missing_root),
        ("rule 3  undeclared type",    "undeclared type `missing_t`",        unresolved_type),
        ("rule 4  map field unmapped", "no component `density`",             drop_type_field),
        ("rule 4  owner not a leaf",   "which is a nested type",             owner_not_leaf),
        ("rule 5  orphan type field",  "orphan field",                       orphan),
        ("rule 6  malformed marker",   "malformed marker",                   bad_marker),
        ("rule 6  short reason",       "printable characters",               short_reason),
        ("rule 6  stale m5 marker",    "stale @m5-only marker",              stale_marker),
        ("rule 6  dead @map id",       "is not an exported map field id",    dead_map_marker),
        ("rule 7  2 map -> 1 type",    "is claimed by 2 map fields",         dup_map_to_one_type),
        ("rule 7  2 type -> 1 map",    "is claimed by 2 type fields",        dup_type_to_one_map),
        ("rule 8  dtype mismatch",     "is dtype f64",                       dtype_mismatch),
        ("rule 8  undeclared repr",    "declare an intended conversion",     undeclared_repr),
        ("rule 8  repr wrong `from`",  "must name the legacy wire type",     repr_wrong_from),
        ("rule 6  repr malformed",     "@repr needs",                        repr_malformed),
        ("rule 9  optional bare real", "ADR-0002 bans bare sentinels",       optional_bare),
        ("rule 9  bare, unmarked",     "which cannot express unset",         bare_unmarked),
        ("rule 9  wrappers stripped",  "which cannot express unset",         wrappers_stripped),
        ("rule 9  stale wrapper",      "optionality wrapper is stale",       stale_optional),
        ("rule 13 no `.false.` default", "without the default initializer",  wrapper_no_default),
        ("rule 13 `has` not logical",  "declares `has` as",                  wrapper_has_kind),
        ("rule 13 no `has` component", "declares no `has` component",        wrapper_no_has),
        ("rule 13 wrapper not private", "does not make its components",      wrapper_not_private),
        ("rule 13 wrapper undeclared",  "uses undeclared type `opt_logical`", wrapper_missing),
        ("rule 10 legacy slot name",   "is a legacy slot name",              slot_name),
        ("rule 11 case collision",     "Fortran is",                         case_collision),
    ]


OWNER_RULE_CASES = [
    # (owner path, expected Fortran path); the 8 real paths of analysis-claude.md section 4
    ("ProblemState.case.name", "ps%case%name"),
    ("ProblemState.mesh.nodes[].xyz", "ps%mesh%nodes(i)%xyz(:)"),
    ("ProblemState.mesh.elements[].nodes", "ps%mesh%elements(i)%nodes(:)"),
    ("ProblemState.mesh.elsets[].members", "ps%mesh%elsets(i)%members(:)"),
    ("ProblemState.materials[].E", "ps%materials(i)%E"),
    ("ProblemState.amplitudes[].points[].time", "ps%amplitudes(i)%points(j)%time"),
    ("ProblemState.steps[0].boundary[].value", "ps%steps(k)%boundary(j)%value"),
    ("ProblemState.steps[0].output.field.u", "ps%steps(k)%output%field%u"),
]

OWNER_RULE_TYPES = """\
module yl_problem_types
  implicit none
  private
  type, public :: case_t
    character(len=:), allocatable :: name
  end type case_t
  type, public :: node_t
    real(real64), allocatable :: xyz(:)
  end type node_t
  type, public :: element_t
    integer, allocatable :: nodes(:)
  end type element_t
  type, public :: elset_t
    integer, allocatable :: members(:)
  end type elset_t
  type, public :: mesh_t
    type(node_t), allocatable :: nodes(:)
    type(element_t), allocatable :: elements(:)
    type(elset_t), allocatable :: elsets(:)
  end type mesh_t
  type, public :: material_t
    type(opt_real) :: E
  end type material_t
  type, public :: point_t
    type(opt_real) :: time
  end type point_t
  type, public :: amplitude_t
    type(point_t), allocatable :: points(:)
  end type amplitude_t
  type, public :: boundary_t
    type(opt_real) :: value
  end type boundary_t
  type, public :: field_t
    integer :: u
  end type field_t
  type, public :: output_t
    type(field_t) :: field
  end type output_t
  type, public :: step_t
    type(boundary_t), allocatable :: boundary(:)
    type(output_t) :: output
  end type step_t
  type, public :: problem_state_t
    type(case_t) :: case
    type(mesh_t) :: mesh
    type(material_t), allocatable :: materials(:)
    type(amplitude_t), allocatable :: amplitudes(:)
    type(step_t), allocatable :: steps(:)
  end type problem_state_t
end module yl_problem_types
"""


def selftest_owner_rule() -> int:
    p = Parser()
    p.parse_texts({"t.f90": OWNER_RULE_TYPES})
    ck = Checker({"version": 1, "field": [{"id": "x.y", "owner": "ProblemState.case.name",
                                           "dtype": "str", "unit": "1", "legacy_symbol": "",
                                           "source": [], "compare": {"rule": "exact"}}]}, p)
    ck.rule1()
    ck.rule3()
    ck.enumerate_fields()
    n = 0
    for owner, want in OWNER_RULE_CASES:
        key, res = ck.resolve(owner)
        got = fortran_path(res.path, res.comp, "ps") if key and isinstance(res, Field) else f"UNRESOLVED ({res})"
        if got == want:
            n += 1
            print(f"ok   owner rule: {owner} -> {got}")
        else:
            print(f"BAD  owner rule: {owner} -> {got}, expected {want}")
    return n


def selftest() -> int:
    base = build()
    ok = not base.problems
    print(("ok   " if ok else "BAD  ") + "good sample: " +
          (base.summary() if ok else "; ".join(base.problems)))
    n_ok = int(ok)
    cases = self_cases()
    for name, expect, factory in cases:
        problems = factory().problems
        hit = next((p for p in problems if expect in p), None)
        if hit:
            n_ok += 1
            print(f"ok   {name}: {hit}")
        else:
            print(f"BAD  {name}: expected {expect!r}, got {problems}")
    # regression: an `opt_*` component must enumerate as a leaf even though the wrapper
    # module is parsed alongside the types module and registered in the type table
    leaf = "materials(i)%e" in base.fields and "materials(i)%e" in base.by_type
    key, res = base.resolve("ProblemState.materials[].E")
    leaf = leaf and isinstance(res, Field) and res.comp.type_name.lower() == "opt_real"
    leaf = leaf and "opt_real" in base.p.types and "24 types" not in base.summary()
    n_ok += int(leaf)
    print(("ok   " if leaf else "BAD  ") + "opt_* wrapper components resolve as leaves "
          "with the wrapper module parsed alongside: " + base.summary())
    miss = build()
    miss.rule12(Path("/nonexistent/M3-01-problemstate.md"))
    gone = any("does not exist" in p for p in miss.problems)
    n_ok += int(gone)
    print(("ok   " if gone else "BAD  ") + "rule 12: --doc naming a missing file FAILs")
    t1, t2 = render(base), render(build())
    idem = t1 == t2 and "M5-only: authoring contract" in t1 and "## materials (6 fields)" in t1
    n_ok += int(idem)
    print(("ok   " if idem else "BAD  ") + "render deterministic + M5 provenance present")
    n_ok += selftest_owner_rule()
    total = len(cases) + 4 + len(OWNER_RULE_CASES)
    print(f"SELFTEST {'PASS' if n_ok == total else 'FAIL'}: {n_ok}/{total} expectations")
    return 0 if n_ok == total else 1


def main(argv=None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv[:1] == ["--selftest"]:
        return selftest()
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub_ = ap.add_subparsers(dest="cmd", required=True)
    for name, func in (("check", cmd_check), ("render", cmd_render)):
        p = sub_.add_parser(name)
        p.add_argument("--map", default=str(MAP_DEFAULT))
        p.add_argument("--src", default=str(SRC_DEFAULT), help="ProblemState type modules")
        if name == "check":
            p.add_argument("--doc", default=None,
                           help="also require this file to equal `render` output (rule 12)")
        else:
            p.add_argument("-o", "--output", default=None)
            p.add_argument("--force", action="store_true",
                           help="write the Markdown even when the check FAILs (exit stays 1)")
        p.set_defaults(func=func)
    a = ap.parse_args(argv)
    return a.func(a)


if __name__ == "__main__":
    sys.exit(main())
