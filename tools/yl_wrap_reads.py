#!/usr/bin/env python3
"""Checked-I/O rewriter for the legacy YL solver (M1-02, Layer 2).

Rewrites legacy/yl/*.f90 in place, driven by docs/m1/reader-inventory.toml and
the generated src/diagnostics/yl_diag_registry.f90:

  * every [[reader]] (incl. reached_only): `read(u,*)` -> `read(u,*,iostat=yl_ios,iomsg=yl_msg)`
    followed by `call diag_check_read(yl_ios,yl_msg,RD_<id>,<index>)` (index
    expression from INDEX_EXPR, 0 otherwise). One-line `if (c) read(...)`
    readers keep the inline form and get `if (c) call diag_check_read(...)`
    (the condition is a pure comparison; this keeps the census `inline_if`
    property that the inventory `reached_only` entries rely on).
  * the 14 input-file opens (INPUT_OPENS): `,status='old',iostat=yl_ios,iomsg=yl_msg`
    plus `call diag_check_open(yl_ios,yl_msg,<file expr>,'<unit>','<new site>')`.
  * `use yl_diag` / `use yl_diag_registry` at the head of the modules and
    PROGRAM FEM90 that contain rewritten statements.
  * Fem.f90 hooks: `call diag_set_mode_from_argv()` before the first executable
    statement of FEM90; `if (diag_check_mode()) call diag_summary_and_exit()`
    before `ttime=lttime` in process_analysis.

Sources are handled as latin-1 bytes split on LF only; a line's own CR (CRLF
files) is reproduced on the lines inserted next to it. No other byte changes.
Every site is located by `site` and verified against `anchor` (same hash as
tools/yl_io_inventory.py); any mismatch aborts before anything is written.
Idempotent: a statement counts as already wrapped only when its whole structure
is present and every argument of the check call is the one this tool would emit
(read: `iostat=yl_ios,iomsg=yl_msg` in the control list and, on the line after
the statement's last continuation line, `call diag_check_read(yl_ios,yl_msg,
RD_<id>,<index>)` with the right constant and the INDEX_EXPR index, guarded by
the same `if (cond)` for inline-if readers; open: `status='old'` + iostat/iomsg
and `call diag_check_open(yl_ios,yl_msg,<file expr>,'<unit>','<file>:<line>')`
on the next line, the file expression equal to the open's file= specifier and
the site equal to the open's current line). Anything else that mentions
iostat=yl_ios / diag_check_* at the site is a partially wrapped site: ABORT.

Usage:
  yl_wrap_reads.py [--dry-run] [--line-map OUT.json]
    --line-map writes {"<file>": {"<old line>": <new line>, ...}} for every
    source line, used to re-anchor the inventory after rewriting.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import tomllib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from yl_io_inventory import anchor_hash, full_statement, sanitize_id, strip_comment, strip_if_prefix  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = REPO_ROOT / "legacy" / "yl"
INVENTORY = REPO_ROOT / "docs" / "m1" / "reader-inventory.toml"
REGISTRY = REPO_ROOT / "src" / "diagnostics" / "yl_diag_registry.f90"

# reader id -> index expression passed as 4th argument of diag_check_read (else 0)
INDEX_EXPR = {
    "COR.global_data.node_coordinates": "ipoin",
    "ELE.read_element.element_connectivity": "ielem",
    "PRE.prescrib_set.reached_only_Prescrib_213": "ifixset",
    "PRE.prescrib_set.set_header": "ifixset",
    "PRE.prescrib_set.set_nodes": "ifixset",
    "PRE.prescrib_set.set_values": "ifixset",
    "MAT.material_set.comment_line#1": "iline",
    "GLB.global_data.group_header": "igroup",
    "GLB.global_data.group_mass_damping": "igroup",
    "GLB.global_data.group_order_time": "igroup",
    "GLB.global_data.group_nfdof": "igroup",
    "GLB.global_data.group_listdof": "igroup",
    "GLB.global_data.appear_process": "iblk",
    "GLB.global_data.matno_process": "iblk",
    "MAN.STATIC_U.increment_control": "iincs",
    "MAN.STATIC_U.tolerances": "iincs",
}
# cursor_op ids of the input-file opens that get status='old' + diag_check_open
INPUT_OPENS = [
    "INP.FEM90.open_Fem_92",
    "GLB.global_data.open_Global_628", "COR.global_data.open_Global_629", "ELE.global_data.open_Global_630",
    "PRE.global_data.open_Global_631", "MAT.global_data.open_Global_632", "LOA.global_data.open_Global_633",
    "SOL.global_data.open_Global_635", "MAN.global_data.open_Global_636", "OPR.global_data.open_Global_637",
    "TEM.global_data.open_Global_649", "FTR.global_data.open_Global_651", "IFS.global_data.open_Global_652",
    "NRT.global_data.open_Global_654",
]
# module / program headers that receive the use lines: file -> header regex
USE_TARGETS = {
    "Global.f90": r"^\s*module\s+global_var\b",
    "Material.f90": r"^\s*module\s+materials\b",
    "Load.f90": r"^\s*module\s+applied_load\b",
    "Prescrib.f90": r"^\s*module\s+prescribed\b",
    "Solver.f90": r"^\s*module\s+solver\b",
    "Output.f90": r"^\s*module\s+output\b",
    "Temper.f90": r"^\s*module\s+temperature\b",
    "Stiff.f90": r"^\s*module\s+stiffness_matrix\b",
    "Elements.f90": r"^\s*module\s+elements\b",
    "Fem.f90": r"^\s*program\s+fem90\b",
}
USE_LINES = ["use yl_diag", "use yl_diag_registry"]
IOSTAT = ",iostat=yl_ios,iomsg=yl_msg"
READ_CTL = re.compile(r"(read\s*\(\s*[A-Za-z_0-9]+\s*,\s*\*\s*)(\))", re.I)
OPEN_RE = re.compile(r"\bopen\s*\(", re.I)
USE_RE = re.compile(r"^\s*use\s+([A-Za-z_0-9]+)", re.I)


class Abort(SystemExit):
    pass


def read_source(name: str) -> list[str]:
    return (SRC_DIR / name).read_bytes().decode("latin-1").split("\n")


def eol(line: str) -> str:
    return "\r" if line.endswith("\r") else ""


def indent_of(line: str) -> str:
    """Leading whitespace of the statement, skipping a numeric label ("22    read ...")."""
    m = re.match(r"^(\s*)(\d+\s+)?", line)
    return " " * (len(m.group(1)) + len(m.group(2) or ""))


def statement_end(lines: list[str], i: int) -> int:
    while strip_comment(lines[i]).rstrip().endswith("&"):
        i += 1
    return i


def registry_constants_from_file(path: Path) -> dict[int, str]:
    consts = {}
    for m in re.finditer(r"integer,\s*parameter\s*::\s*(RD_\w+)\s*=\s*(\d+)", path.read_text(encoding="utf-8")):
        consts[int(m.group(2))] = m.group(1)
    return consts


def split_args(text: str) -> list[str]:
    """Split a Fortran argument list on top-level commas (quote and paren aware)."""
    args, depth, quote, cur = [], 0, None, []
    for ch in text:
        if quote:
            cur.append(ch)
            if ch == quote:
                quote = None
            continue
        if ch in ("'", '"'):
            quote = ch
        elif ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            args.append("".join(cur)); cur = []
        else:
            cur.append(ch)
    args.append("".join(cur))
    return args


def paren_span(code: str, start: int) -> int:
    """Index of the ')' matching the '(' at code[start]."""
    depth, quote = 0, None
    for j in range(start, len(code)):
        ch = code[j]
        if quote:
            if ch == quote:
                quote = None
        elif ch in ("'", '"'):
            quote = ch
        elif ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return j
    raise Abort(f"unbalanced parentheses in: {code!r}")


class FileEdits:
    def __init__(self, name: str, lines: list[str]):
        self.name = name
        self.lines = lines
        self.before: dict[int, list[str]] = {}   # inserted before line index
        self.after: dict[int, list[str]] = {}    # inserted after line index
        self.replace: dict[int, str] = {}
        self.log: list[str] = []

    def ins_before(self, i: int, text: str) -> None:
        self.before.setdefault(i, []).append(text + eol(self.lines[i]))

    def ins_after(self, i: int, text: str) -> None:
        self.after.setdefault(i, []).append(text + eol(self.lines[i]))

    def set(self, i: int, text: str) -> None:
        if i in self.replace:
            raise Abort(f"{self.name}:{i + 1}: two replacements on one line")
        self.replace[i] = text

    def line_map(self) -> dict[int, int]:
        """old 1-based line -> new 1-based line"""
        out, shift = {}, 0
        for i in range(len(self.lines)):
            shift += len(self.before.get(i, []))
            out[i + 1] = i + 1 + shift
            shift += len(self.after.get(i, []))
        return out

    def render(self) -> list[str]:
        out = []
        for i, line in enumerate(self.lines):
            out.extend(self.before.get(i, []))
            out.append(self.replace.get(i, line))
            out.extend(self.after.get(i, []))
        return out

    def changed(self) -> bool:
        return bool(self.before or self.after or self.replace)


def locate(edits: FileEdits, site: str, anchor: str) -> int:
    fname, ln = site.split(":")
    i = int(ln) - 1
    if i >= len(edits.lines):
        raise Abort(f"{site}: beyond end of file")
    text = full_statement(edits.lines, i)
    if anchor_hash(text) != anchor:
        raise Abort(f"{site}: anchor mismatch (inventory {anchor}, source {anchor_hash(text)}): {text!r}")
    return i


def squash(text: str) -> str:
    """Normalise Fortran code for comparison: drop the trailing comment, then lower-case and
    remove blanks/tabs outside string literals only; the contents of '...' / "..." literals
    (file names, unit names, sites) are kept byte for byte so a differing literal is seen."""
    out, quote = [], None
    for ch in strip_comment(text):
        if quote:
            out.append(ch)
            if ch == quote:
                quote = None
        elif ch in ("'", '"'):
            quote = ch
            out.append(ch)
        elif ch in (" ", "\t"):
            continue
        else:
            out.append(ch.lower())
    return "".join(out)


def check_call_args(nxt: str, fn: str) -> list[str] | None:
    """Arguments of `call <fn>(...)` when the squashed line `nxt` is exactly that call
    (nothing else on the line); None otherwise."""
    head = f"call{fn}("
    if not nxt.startswith(head):
        return None
    lp = len(head) - 1
    try:
        rp = paren_span(nxt, lp)
    except Abort:
        return None
    if nxt[rp + 1:].strip():
        return None
    return [a.strip() for a in split_args(nxt[lp + 1:rp])]


def already_wrapped_read(edits: FileEdits, i: int, entry: dict, const: str) -> bool:
    """True when the read at line i carries the complete wrapper: iostat/iomsg in the
    control list and, on the next line, `call diag_check_read(yl_ios,yl_msg,<const>,<index>)`
    with exactly the four arguments this tool would emit (same `if (cond)` guard for
    inline-if readers). Abort when the site is only partially wrapped or the call
    differs in any argument."""
    code = strip_comment(edits.lines[i])
    sq = squash(code)
    has_iostat = "iostat=yl_ios" in sq and "iomsg=yl_msg" in sq
    end = statement_end(edits.lines, i)
    nxt = squash(edits.lines[end + 1]) if end + 1 < len(edits.lines) else ""
    _, cond = strip_if_prefix(code)
    guard = squash(code[:code.lower().index("read")]) if cond is not None else ""
    expect = ["yl_ios", "yl_msg", const.lower(), squash(INDEX_EXPR.get(entry["id"], "0"))]
    args = check_call_args(nxt[len(guard):], "diag_check_read") if nxt.startswith(guard) else None
    has_call = args == expect
    if has_iostat and has_call:
        return True
    if "iostat=yl_ios" in sq or "diag_check_read" in nxt:
        raise Abort(f"{entry['site']}: partially wrapped read ({entry['id']}): iostat/iomsg={has_iostat}, "
                    f"check call={has_call} (args {args}, expected {expect}, guard {guard!r}); next line {nxt[:100]!r}")
    return False


def open_file_expr(code: str, site: str) -> tuple[list[str], str]:
    """(argument list, file= expression) of the single-line `open(...)` statement `code`."""
    m = OPEN_RE.search(code)
    if not m:
        raise Abort(f"{site}: cannot find `open(` in {code!r}")
    lp = m.end() - 1
    rp = paren_span(code, lp)
    args = split_args(code[lp + 1:rp])
    file_expr = None
    for a in args:
        am = re.match(r"\s*file\s*=\s*(.*)$", a, re.I | re.S)
        if am:
            file_expr = am.group(1).strip()
    if file_expr is None:
        raise Abort(f"{site}: no file= specifier in {code!r}")
    return args, file_expr


def already_wrapped_open(edits: FileEdits, i: int, entry: dict) -> bool:
    """True when the open at line i has status='old' + iostat/iomsg and the next line is
    `call diag_check_open(yl_ios,yl_msg,<file expr>,'<unit>','<file>:<line>')` with the
    open's own file= expression, its unit and its current site. Abort on anything
    partial or different."""
    code = squash(edits.lines[i])
    has_status = "status='old'" in code and "iostat=yl_ios" in code and "iomsg=yl_msg" in code
    nxt = squash(edits.lines[i + 1]) if i + 1 < len(edits.lines) else ""
    args = check_call_args(nxt, "diag_check_open")
    expect = None
    if has_status:
        _, file_expr = open_file_expr(strip_comment(edits.lines[i]), entry["site"])
        expect = ["yl_ios", "yl_msg", squash(file_expr), f"'{entry['unit_var']}'", f"'{edits.name}:{i + 1}'"]
    has_call = expect is not None and args == expect
    if has_status and has_call:
        return True
    if has_status or "iostat=yl_ios" in code or "diag_check_open" in nxt:
        raise Abort(f"{entry['site']}: partially wrapped open ({entry['id']}): status/iostat={has_status}, "
                    f"check call={has_call} (args {args}, expected {expect}); next line {nxt[:100]!r}")
    return False


def wrap_read(edits: FileEdits, entry: dict, const: str) -> None:
    i = locate(edits, entry["site"], entry["anchor"])
    line = edits.lines[i]
    if already_wrapped_read(edits, i, entry, const):
        edits.log.append(f"skip   {entry['site']} already wrapped ({entry['id']})")
        return
    code = strip_comment(line)
    m = READ_CTL.search(code)
    if not m:
        raise Abort(f"{entry['site']}: cannot find `read(<unit>,*)` control list in {line!r}")
    new_line = line[:m.start(2)] + IOSTAT + line[m.start(2):]
    index = INDEX_EXPR.get(entry["id"], "0")
    call = f"call diag_check_read(yl_ios,yl_msg,{const},{index})"
    _, cond = strip_if_prefix(code)
    if cond is not None:
        # one-line `if (cond) read(...)`: keep the form, repeat the guard on the check
        prefix = code[:code.lower().index("read")]  # `if (cond)` incl. its spacing style
        edits.set(i, new_line)
        edits.ins_after(i, prefix + call)
        edits.log.append(f"read   {entry['site']} inline-if {const} index={index}")
        return
    end = statement_end(edits.lines, i)
    edits.set(i, new_line)
    edits.ins_after(end, indent_of(line) + call)
    tag = f"cont+{end - i}" if end > i else ""
    edits.log.append(f"read   {entry['site']} {const} index={index} {tag}".rstrip())


SITE_PLACEHOLDER = "@SITE@"


def wrap_open(edits: FileEdits, entry: dict) -> None:
    i = locate(edits, entry["site"], entry["anchor"])
    line = edits.lines[i]
    if already_wrapped_open(edits, i, entry):
        edits.log.append(f"skip   {entry['site']} already wrapped ({entry['id']})")
        return
    code = strip_comment(line)
    if code.rstrip().endswith("&") or strip_if_prefix(code)[1] is not None:
        raise Abort(f"{entry['site']}: continued or guarded open not supported: {line!r}")
    args, file_expr = open_file_expr(code, entry["site"])
    rp = paren_span(code, OPEN_RE.search(code).end() - 1)
    if any(re.match(r"\s*status\s*=", a, re.I) for a in args):
        raise Abort(f"{entry['site']}: open already has status=: {line!r}")
    new_line = line[:rp] + ",status='old'" + IOSTAT + line[rp:]
    call = f"call diag_check_open(yl_ios,yl_msg,{file_expr},'{entry['unit_var']}','{SITE_PLACEHOLDER}')"
    edits.set(i, new_line)
    edits.ins_after(i, indent_of(line) + call)
    edits.log.append(f"open   {entry['site']} -> {SITE_PLACEHOLDER} {entry['unit_var']} file={file_expr}")


def finalize_open_sites(edits: FileEdits) -> None:
    """Replace the site placeholder of diag_check_open calls by the post-rewrite site."""
    lm = edits.line_map()
    for i, lines in edits.after.items():
        edits.after[i] = [x.replace(SITE_PLACEHOLDER, f"{edits.name}:{lm[i + 1]}") for x in lines]
    edits.log = [x.replace(SITE_PLACEHOLDER, f"{edits.name}:{lm[int(x.split()[1].split(':')[1])]}") if SITE_PLACEHOLDER in x else x
                 for x in edits.log]


def add_use(edits: FileEdits, header_re: str) -> None:
    hdr = None
    for i, line in enumerate(edits.lines):
        if re.match(header_re, strip_comment(line), re.I):
            hdr = i
            break
    if hdr is None:
        raise Abort(f"{edits.name}: header {header_re!r} not found")
    first_use, present = None, set()
    for j in range(hdr + 1, len(edits.lines)):
        code = strip_comment(edits.lines[j])
        m = USE_RE.match(code)
        if m:
            present.add(m.group(1).lower())
            if first_use is None:
                first_use = j
            continue
        if re.match(r"^\s*(implicit|contains|integer|real|character|logical|type|private|public|save|parameter|include)\b", code, re.I):
            break
    missing = [u for u in USE_LINES if u.split()[1] not in present]
    if not missing:
        edits.log.append(f"skip   {edits.name} use lines present")
        return
    if first_use is not None:
        indent = re.match(r"^\s*", edits.lines[first_use]).group(0)
        for u in missing:
            edits.ins_before(first_use, indent + u)
        where = f"before line {first_use + 1}"
    else:
        indent = re.match(r"^\s*", edits.lines[hdr]).group(0)
        for u in reversed(missing):
            edits.ins_after(hdr, indent + u)
        where = f"after header line {hdr + 1}"
    edits.log.append(f"use    {edits.name} {', '.join(missing)} {where}")


def add_fem_hooks(edits: FileEdits) -> None:
    src = "\n".join(edits.lines).lower()
    # 1) FEM90: before open(inpunit,file='inp')
    prog = next(i for i, l in enumerate(edits.lines) if re.match(r"^\s*program\s+fem90\b", l, re.I))
    if "diag_set_mode_from_argv" in src:
        edits.log.append("skip   Fem.f90 diag_set_mode_from_argv present")
    else:
        for i in range(prog, len(edits.lines)):
            if re.match(r"^\s*open\s*\(\s*inpunit\s*,", strip_comment(edits.lines[i]), re.I):
                edits.ins_before(i, indent_of(edits.lines[i]) + "call diag_set_mode_from_argv()")
                edits.log.append(f"hook   Fem.f90:{i + 1} call diag_set_mode_from_argv() before open(inpunit)")
                break
        else:
            raise Abort("Fem.f90: open(inpunit,...) not found in FEM90")
    # 2) process_analysis: before ttime=lttime
    if "diag_summary_and_exit" in src:
        edits.log.append("skip   Fem.f90 diag_summary_and_exit present")
        return
    sub = next(i for i, l in enumerate(edits.lines) if re.match(r"^\s*subroutine\s+process_analysis\b", l, re.I))
    for i in range(sub, len(edits.lines)):
        if re.match(r"^\s*ttime\s*=\s*lttime\b", strip_comment(edits.lines[i]), re.I):
            edits.ins_before(i, indent_of(edits.lines[i]) + "if (diag_check_mode()) call diag_summary_and_exit()")
            edits.log.append(f"hook   Fem.f90:{i + 1} check-mode exit before ttime=lttime")
            break
        if re.match(r"^\s*end\s+subroutine", edits.lines[i], re.I):
            raise Abort("Fem.f90: ttime=lttime not found in process_analysis")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--inventory", default=str(INVENTORY))
    ap.add_argument("--registry", default=str(REGISTRY))
    ap.add_argument("--line-map", metavar="OUT.json")
    a = ap.parse_args(argv)

    inv = tomllib.loads(Path(a.inventory).read_text(encoding="utf-8"))
    readers = inv["reader"]
    consts = registry_constants_from_file(Path(a.registry))
    if len(consts) != len(readers):
        raise Abort(f"registry has {len(consts)} RD_ constants, inventory {len(readers)} readers (regenerate with gen-fortran)")
    for idx, r in enumerate(readers, 1):
        if consts.get(idx) != sanitize_id(r["id"], idx):
            raise Abort(f"registry idx {idx}: {consts.get(idx)} != {sanitize_id(r['id'], idx)} for {r['id']}")
    cursor = {c["id"]: c for c in inv.get("cursor_op", [])}
    missing = [o for o in INPUT_OPENS if o not in cursor]
    if missing:
        raise Abort(f"input opens not in inventory: {missing}")
    unknown = [k for k in INDEX_EXPR if k not in {r["id"] for r in readers}]
    if unknown:
        raise Abort(f"INDEX_EXPR ids not in inventory: {unknown}")

    files: dict[str, FileEdits] = {}

    def edits_for(site: str) -> FileEdits:
        name = site.split(":")[0]
        if name not in files:
            files[name] = FileEdits(name, read_source(name))
        return files[name]

    try:
        for idx, r in enumerate(readers, 1):
            wrap_read(edits_for(r["site"]), r, consts[idx])
        # opens: the site written into diag_check_open is the post-rewrite line, which
        # needs the read/use/hook insertions of the same file planned first.
        for name, hdr in USE_TARGETS.items():
            add_use(edits_for(name + ":0"), hdr)
        add_fem_hooks(files["Fem.f90"])
        for o in INPUT_OPENS:
            wrap_open(edits_for(cursor[o]["site"]), cursor[o])
        for e in files.values():
            finalize_open_sites(e)
    except Abort as ex:
        print(f"ABORT: {ex}", file=sys.stderr)
        print("no file written", file=sys.stderr)
        return 1

    total = 0
    for name in sorted(files):
        e = files[name]
        for l in e.log:
            print(l)
        total += sum(1 for l in e.log if not l.startswith("skip"))
    print(f"{'DRY-RUN: ' if a.dry_run else ''}{total} edits in {sum(1 for e in files.values() if e.changed())} files")
    if a.line_map:
        Path(a.line_map).write_text(json.dumps({n: files[n].line_map() for n in sorted(files)}, indent=0) + "\n")
    if a.dry_run:
        return 0
    for name, e in files.items():
        if e.changed():
            (SRC_DIR / name).write_bytes("\n".join(e.render()).encode("latin-1"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
