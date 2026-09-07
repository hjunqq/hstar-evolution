#!/usr/bin/env python3
"""Input-reader inventory tooling for the legacy YL solver (M1-01).

Sub-commands
  scan        static census of every READ/OPEN/CLOSE/REWIND/BACKSPACE/INQUIRE
              statement in legacy/yl -> docs/m1/io-sites.json
  gdb-script  emit a gdb batch script with one breakpoint per site that logs
              "HIT <file>:<line>" and continues (used by yl_io_trace.sh)
  hits        parse one or more gdb hit logs -> hits.json {site: count}
  check       validate docs/m1/reader-inventory.toml against the census, the
              source text (anchors) and the evidence (hits); fail-closed
  render      reader-inventory.toml -> Markdown tables (stdout or -o)

Only the Python standard library is used. Sources are ISO-8859 encoded and are
decoded as latin-1 so byte offsets and line numbers are exact.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import tomllib
from collections import Counter, defaultdict
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = REPO_ROOT / "legacy" / "yl"
SOURCES = ["Vartype.f90", "Array.f90", "Elements.f90", "gidpost.F90", "vsl_gauss_module.f90", "Global.f90",
           "Material.f90", "meshfine.f90", "Load.f90", "Prescrib.f90", "Solver.f90", "Output.f90",
           "Temper.f90", "Stiff.f90", "Residu.f90", "Level.f90", "Fem.f90"]
STMT = re.compile(r"^\s*(?:\d+\s+)?(read|open|close|rewind|backspace|inquire)\s*\(\s*([A-Za-z_0-9*]+)", re.I)
IF_PREFIX = re.compile(r"^\s*if\s*\(", re.I)
ROUTINE = re.compile(r"^\s*(?:recursive\s+)?(subroutine|function|program)\s+([A-Za-z_0-9]+)", re.I)
END_ROUTINE = re.compile(r"^\s*end\s+(subroutine|function|program)\b", re.I)
STATE_TARGET_VOCAB = re.compile(r"^(case|mesh|materials|sections|amplitudes|interactions|steps|solver)(\.|\[|$)|^(derived|not_migrated|unused_switch|empty_section|output_control|runtime_only|title_skip)$")
PHASE_VOCAB = re.compile(r"^(startup|phase_lazy\(\d+\)|increment_lazy\(\d+,\d+\)|solver_lazy|rewind_reread)$")


def strip_comment(line: str) -> str:
    out, quote = [], None
    for ch in line:
        if quote:
            out.append(ch)
            if ch == quote:
                quote = None
        elif ch in ("'", '"'):
            quote = ch
            out.append(ch)
        elif ch == "!":
            break
        else:
            out.append(ch)
    return "".join(out)


def split_lines(data: bytes) -> list[str]:
    """Split on LF/CRLF only. str.splitlines() would also split on U+0085 (NEL),
    which appears inside GBK comments once decoded as latin-1, and shift line numbers."""
    return data.decode("latin-1").replace("\r\n", "\n").split("\n")


def strip_if_prefix(code: str) -> tuple[str, str | None]:
    """For one-line `if (cond) stmt` return (stmt, cond); otherwise (code, None)."""
    if not IF_PREFIX.match(code):
        return code, None
    start = code.index("(")
    depth, j = 0, start
    while j < len(code):
        if code[j] == "(":
            depth += 1
        elif code[j] == ")":
            depth -= 1
            if depth == 0:
                break
        j += 1
    rest = code[j + 1:].strip()
    if re.match(r"^then\b", rest, re.I) or not rest:
        return code, None
    return rest, code[start + 1:j].strip()


def full_statement(lines: list[str], i: int) -> str:
    """Join continuation lines (trailing &) starting at index i; return one-line text."""
    parts = []
    while i < len(lines):
        code = strip_comment(lines[i]).rstrip()
        cont = code.endswith("&")
        parts.append(code.rstrip("&").strip().lstrip("&").strip())
        if not cont:
            break
        i += 1
    return " ".join(p for p in parts if p)


def anchor_hash(text: str) -> str:
    return hashlib.sha256(re.sub(r"\s+", " ", text.strip().lower()).encode()).hexdigest()[:12]


def scan() -> list[dict]:
    sites = []
    for f in SOURCES:
        lines = split_lines((SRC_DIR / f).read_bytes())
        routine = "?"
        for i, raw in enumerate(lines):
            code = strip_comment(raw)
            m = ROUTINE.match(code)
            if m:
                routine = m.group(2)
            if END_ROUTINE.match(code):
                routine = "?"
            stmt_code, cond = strip_if_prefix(code)
            m = STMT.match(stmt_code)
            if not m:
                continue
            kind, unit = m.group(1).lower(), m.group(2)
            if kind == "read" and unit == "*":
                continue  # stdin
            text = full_statement(lines, i)
            sites.append({"site": f"{f}:{i + 1}", "file": f, "line": i + 1, "routine": routine, "stmt": kind,
                          "unit": unit, "inline_if": cond, "text": text, "anchor": anchor_hash(text)})
    return sites


def cmd_scan(a):
    sites = scan()
    doc = {"version": 1, "sources": SOURCES, "site_count": len(sites),
           "by_stmt": dict(Counter(s["stmt"] for s in sites)), "sites": sites}
    out = Path(a.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(doc, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"wrote {out}: {len(sites)} sites {doc['by_stmt']}")
    return 0


def cmd_gdb_script(a):
    sites = json.loads(Path(a.sites).read_text(encoding="utf-8"))["sites"]
    log = Path(a.log).resolve()
    lines = ["set pagination off", "set confirm off", "set breakpoint pending on", "set print thread-events off",
             f"set logging file {log}", "set logging overwrite on", "set logging redirect on", "set logging enabled on"]
    for s in sites:
        lines += [f"break {s['site']}", "commands", "silent", f'printf "HIT {s["site"]}\\n"', "continue", "end"]
    lines += ["run < /dev/null > gdb-stdout.txt 2> gdb-stderr.txt", 'printf "EXIT %d\\n", $_exitcode', "quit"]
    Path(a.output).write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {a.output}: {len(sites)} breakpoints")
    return 0


def parse_hits(path: Path) -> tuple[Counter, int | None]:
    hits, exit_code = Counter(), None
    for ln in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if ln.startswith("HIT "):
            hits[ln.split()[1]] += 1
        elif ln.startswith("EXIT "):
            exit_code = int(ln.split()[1])
    return hits, exit_code


def cmd_hits(a):
    hits, exit_code = parse_hits(Path(a.log))
    doc = {"version": 1, "case_id": a.case_id, "exit_code": exit_code, "total_hits": sum(hits.values()),
           "distinct_sites": len(hits), "hits": dict(sorted(hits.items()))}
    Path(a.output).parent.mkdir(parents=True, exist_ok=True)
    Path(a.output).write_text(json.dumps(doc, indent=1) + "\n", encoding="utf-8")
    print(f"wrote {a.output}: {doc['distinct_sites']} sites, {doc['total_hits']} hits, exit {exit_code}")
    return 0


def load_inventory(path: Path) -> dict:
    return tomllib.loads(path.read_text(encoding="utf-8"))


def cmd_check(a):
    inv = load_inventory(Path(a.inventory))
    census = {s["site"]: s for s in json.loads(Path(a.sites).read_text(encoding="utf-8"))["sites"]}
    evidence = {}
    for p in a.evidence:
        doc = json.loads(Path(p).read_text(encoding="utf-8"))
        evidence[doc["case_id"]] = doc
    problems = []
    readers = inv.get("reader", [])
    cursor_ops = inv.get("cursor_op", [])
    ids = [r["id"] for r in readers] + [c["id"] for c in cursor_ops]
    for k, n in Counter(ids).items():
        if n > 1:
            problems.append(f"duplicate id {k}")
    registered_sites = {}
    for entry in readers + cursor_ops:
        site = entry.get("site")
        if site in registered_sites:
            problems.append(f"{entry['id']}: site {site} already registered as {registered_sites[site]}")
        registered_sites[site] = entry["id"]
        c = census.get(site)
        if c is None:
            problems.append(f"{entry['id']}: site {site} not in census")
            continue
        if entry.get("anchor") != c["anchor"]:
            problems.append(f"{entry['id']}: anchor {entry.get('anchor')} != census {c['anchor']} (source changed?)")
        if entry.get("routine") != c["routine"]:
            problems.append(f"{entry['id']}: routine {entry.get('routine')} != census {c['routine']}")
        if entry.get("unit_var") != c["unit"]:
            problems.append(f"{entry['id']}: unit_var {entry.get('unit_var')} != census {c['unit']}")
        exp = "read" if entry in readers else c["stmt"]
        if c["stmt"] != exp and entry in readers:
            problems.append(f"{entry['id']}: registered as reader but census stmt is {c['stmt']}")
        # evidence consistency. A breakpoint on a one-line `if (cond) stmt` fires when
        # the line is reached even if cond is false; such entries carry reached_only=true
        # plus condition_value and must claim no execution.
        reached_only = bool(entry.get("reached_only", False))
        if reached_only and not c.get("inline_if"):
            problems.append(f"{entry['id']}: reached_only but census has no inline if")
        if reached_only and not entry.get("condition_value"):
            problems.append(f"{entry['id']}: reached_only requires condition_value")
        for case_id, doc in evidence.items():
            n = doc["hits"].get(site, 0)
            claimed = entry.get("hits", {}).get(case_id)
            if claimed is None:
                problems.append(f"{entry['id']}: no hits recorded for {case_id}")
            elif claimed != n:
                problems.append(f"{entry['id']}: hits[{case_id}]={claimed} but evidence says {n}")
            executed = case_id in entry.get("executed_by", [])
            if reached_only:
                if executed:
                    problems.append(f"{entry['id']}: reached_only entries cannot be executed_by {case_id}")
            elif (n > 0) != executed:
                problems.append(f"{entry['id']}: executed_by inconsistent with evidence for {case_id}")
    for r in readers:
        if r.get("reached_only"):
            continue
        for key in ("fields", "format", "phase", "state_target", "guard", "consumers"):
            if key not in r:
                problems.append(f"{r['id']}: missing {key}")
        if "phase" in r and not PHASE_VOCAB.match(r["phase"]):
            problems.append(f"{r['id']}: phase {r['phase']!r} not in vocabulary")
        if "state_target" in r and not STATE_TARGET_VOCAB.match(r["state_target"]):
            problems.append(f"{r['id']}: state_target {r['state_target']!r} not in vocabulary")
        if r.get("format") not in ("list_directed", "text_skip", "formatted", "unformatted"):
            problems.append(f"{r['id']}: format {r.get('format')!r} invalid")
    # completeness: every executed read/open/rewind site must be registered
    for case_id, doc in evidence.items():
        for site, n in doc["hits"].items():
            if n > 0 and site not in registered_sites:
                problems.append(f"executed site {site} ({census.get(site, {}).get('stmt')}, {census.get(site, {}).get('unit')}) in {case_id} is not registered")
    # not_on_path coverage: every census unit must be either registered or explained
    explained = {n["unit_var"] for n in inv.get("not_on_path", [])}
    executed_units = {census[s]["unit"] for s in registered_sites if s in census}
    for unit, n in Counter(c["unit"] for c in census.values()).items():
        if unit not in executed_units and unit not in explained:
            problems.append(f"unit {unit} ({n} sites) neither executed nor listed in not_on_path")
    if problems:
        print(f"FAIL: {len(problems)} problems")
        for p in problems[:200]:
            print("  " + p)
        return 1
    print(f"PASS: {len(readers)} readers, {len(cursor_ops)} cursor ops, {len(inv.get('not_on_path', []))} not_on_path groups, evidence {sorted(evidence)}")
    return 0


def cmd_render(a):
    inv = load_inventory(Path(a.inventory))
    out = []
    by_file = defaultdict(list)
    for r in inv.get("reader", []):
        by_file[r["file"]].append(r)
    out.append("## 已执行读取点（reader）\n")
    for f in sorted(by_file, key=lambda x: (x != "inp", x)):
        rows = sorted(by_file[f], key=lambda r: (r.get("seq") is None, r.get("seq") or 0))
        out.append(f"### `{f}`（{rows[0]['unit_var']}，{len(rows)} 条）\n")
        out.append("| ID | 例程 | 锚点 | seq | 字段 | 格式 | guard | 阶段 | 消费者 | ProblemState 目标 | 命中 |")
        out.append("|---|---|---|---|---|---|---|---|---|---|---|")
        for r in rows:
            hits = ", ".join(f"{k}:{v}" for k, v in r.get("hits", {}).items())
            if r.get("reached_only"):
                out.append(f"| `{r['id']}` | {r['routine']} | `{r['site']}` | — | *reached only*: `{r.get('statement', '')[:80]}` | — | {r.get('condition_value', '')} | — | — | — | {hits} |")
                continue
            fields = "<br>".join(f"`{f}`" for f in r["fields"])
            out.append(f"| `{r['id']}` | {r['routine']} | `{r['site']}` | {r.get('seq', '')} | {fields} | {r['format']} | {r['guard']} | {r['phase']} | {r['consumers']} | `{r['state_target']}` | {hits} |")
        out.append("")
    out.append("## 游标操作（cursor_op）\n")
    out.append("| ID | 语句 | 单元 | 例程 | 锚点 | 文件 | 说明 |")
    out.append("|---|---|---|---|---|---|---|")
    for c in inv.get("cursor_op", []):
        out.append(f"| `{c['id']}` | {c['stmt']} | {c['unit_var']} | {c['routine']} | `{c['site']}` | {c.get('file', '')} | {c.get('note', '')} |")
    out.append("")
    out.append("## 未在本路径执行的读取候选（not_on_path）\n")
    out.append("| 单元 | 候选数 | 例程 | guard / 原因 | 归属阶段 |")
    out.append("|---|---|---|---|---|")
    for n in inv.get("not_on_path", []):
        out.append(f"| {n['unit_var']} | {n['site_count']} | {n.get('routines', '')} | {n['reason']} | {n.get('migration_phase', '')} |")
    text = "\n".join(out) + "\n"
    if a.output:
        Path(a.output).write_text(text, encoding="utf-8")
        print(f"wrote {a.output}")
    else:
        sys.stdout.write(text)
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("scan"); s.add_argument("-o", "--output", default=str(REPO_ROOT / "docs/m1/io-sites.json")); s.set_defaults(func=cmd_scan)
    g = sub.add_parser("gdb-script"); g.add_argument("--sites", default=str(REPO_ROOT / "docs/m1/io-sites.json")); g.add_argument("--log", required=True); g.add_argument("-o", "--output", required=True); g.set_defaults(func=cmd_gdb_script)
    h = sub.add_parser("hits"); h.add_argument("--log", required=True); h.add_argument("--case-id", required=True); h.add_argument("-o", "--output", required=True); h.set_defaults(func=cmd_hits)
    c = sub.add_parser("check"); c.add_argument("--inventory", default=str(REPO_ROOT / "docs/m1/reader-inventory.toml")); c.add_argument("--sites", default=str(REPO_ROOT / "docs/m1/io-sites.json")); c.add_argument("--evidence", nargs="+", required=True); c.set_defaults(func=cmd_check)
    r = sub.add_parser("render"); r.add_argument("--inventory", default=str(REPO_ROOT / "docs/m1/reader-inventory.toml")); r.add_argument("-o", "--output"); r.set_defaults(func=cmd_render)
    a = ap.parse_args(argv)
    return a.func(a)


if __name__ == "__main__":
    sys.exit(main())
