#!/usr/bin/env python3
"""M5 exit condition: the new input format drives the solver, and the numbers are the old ones.

The M5 acceptance criteria are user-visible capabilities, not internal state, so this gate
asserts exactly those:

  N1  every golden case runs from `--input=<case>/modern/case.toml` alone -- the legacy
      control deck (.glb/.man/.pre/.mat/.loa/.sol/...) is NOT copied into the work
      directory, so a run that still reads one cannot pass by accident. Only the mesh
      files the contract names (`mesh.file` -> `<prefix>.cor` / `.ele`) are present.
  N2  the results are byte-identical to the FROZEN legacy reference, strictly
      (atol = rtol = 0, per ADR-0008 SS4: the noise measurement found none).
  N4  a block a case declares `must_be_nonzero` really carries non-zero values. Frozen
      references make this mostly self-enforcing -- a run that stopped yielding would fail
      N2 -- but the claim "this deck exercises plasticity" should be a checked property of
      the case, not a sentence in a report, and it also guards against re-freezing from a
      degenerate run.
  N3  a deck the contract rejects STOPS with a readable diagnostic (exit 2 INVALID_INPUT
      or 3 UNSUPPORTED) and writes no results. Without N3 the gate would be satisfied by
      an --input that silently ignored what it could not understand. Three shapes, because
      they failed differently and one of them failed silently:
        a  an unlisted value  -> exit 3, key and value named
        b  a file that is not there, and one that is not the contract's TOML subset ->
           exit 2, the name the operator typed. Both used to fall through to the LEGACY
           reader, which prompted `Input the problem name?` and then produced a Fortran
           traceback: probn is set before the entry runs, so the entry never got its turn.
        c  three findings in one deck -> each rendered EXACTLY once, with its own line
           number. They were briefly printed twice, once by the validator's caller and
           once by the refusal, which is the sort of thing only an assertion catches.

N1 is the assertion that makes this different from the M4-02 fallback gate: that one
proved the adapter could drive the legacy solver from the legacy deck; this one proves the
authoring format can, from itself.

Usage:
    tools/yl_modern_check.py [--binary build/release/hstar]
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# The solver must run under the SAME pinned environment every frozen reference was made
# under; see yl_run.pinned_env for what happens when it does not.
import importlib.util as _ilu
_spec = _ilu.spec_from_file_location("yl_run", ROOT / "tools/yl_run.py")
_yl_run = _ilu.module_from_spec(_spec); _spec.loader.exec_module(_yl_run)
pinned_env = _yl_run.pinned_env

MANIFEST = ROOT / "cases/manifest.toml"


def cases() -> list[tuple[str, Path]]:
    """(case id, case directory) for every frozen case that has a modern deck.

    Read from cases/manifest.toml rather than from the state field map's `cases` list:
    that list is the STATIC pair, because it drives the M2 state comparison, and a
    material-domain case has no state baseline by design. Driving this gate from it would
    have quietly skipped every case after the first domain.
    """
    doc = tomllib.loads(MANIFEST.read_text(encoding="utf-8"))
    out = []
    for c in doc.get("case", []):
        d = ROOT / "cases" / c["path"]
        # `modern_gate = false` in the manifest excludes a case from this gate. It is
        # honoured, and PRINTED on every run rather than skipped quietly -- an exclusion
        # nobody sees is how a gate stops covering what people think it covers. No case
        # carries it at present; it was used for one day while loads_2d.wall_reservoir's
        # second step was being closed.
        if c.get("modern_gate") is False:
            print(f"  -- {c['id']:<28} modern gate OFF by manifest "
                  f"(reason in cases/manifest.toml)")
            continue
        if (d / "modern/case.toml").is_file():
            out.append((c["id"], d))
    if not out:
        raise SystemExit(f"{MANIFEST}: no frozen case carries modern/case.toml")
    return out


def mesh_prefix(deck: Path) -> str:
    """`mesh.file` out of the contract deck. Read with a line regex rather than a TOML
    parser because that is the one key this gate must agree with the Fortran reader on,
    and the Fortran reader accepts a strict subset."""
    for line in deck.read_text(encoding="utf-8").splitlines():
        m = re.match(r"\s*file\s*=\s*\"([^\"]*)\"\s*(#.*)?$", line)
        if m:
            return m.group(1)
    raise SystemExit(f"{deck}: no `file = \"...\"` line under [mesh]")


MESH_FILES = {
    "hstar-legacy-cor-ele": (".cor", ".ele"),
    # The node-interpolation table is mesh-generator output indexed by node id, and legacy
    # reads it on the modern path exactly as it reads .ele (neither read is guarded by
    # yl_input_enabled). So it is staged, not authored -- and which files get staged is
    # read off `mesh.format`, never widened silently.
    "hstar-legacy-cor-ele-nrt": (".cor", ".ele", ".nrt"),
}


def mesh_format(deck: Path) -> str:
    """`mesh.format` out of the contract deck, by the same line-regex rule as mesh_prefix."""
    for line in deck.read_text(encoding="utf-8").splitlines():
        m = re.match(r"\s*format\s*=\s*\"([^\"]*)\"\s*(#.*)?$", line)
        if m:
            return m.group(1)
    raise SystemExit(f"{deck}: no `format = \"...\"` line under [mesh]")


def stage(case_dir: Path, work: Path) -> Path:
    """The mesh and the contract deck. Nothing else -- see N1."""
    deck = case_dir / "modern/case.toml"
    prefix = mesh_prefix(deck)
    fmt = mesh_format(deck)
    if fmt not in MESH_FILES:
        raise SystemExit(f"{deck}: mesh.format {fmt!r} is not one this gate knows how to "
                         f"stage; add it to MESH_FILES with the files it names")
    for suffix in MESH_FILES[fmt]:
        src = case_dir / "legacy" / (prefix + suffix)
        shutil.copyfile(src, work / src.name)
    shutil.copyfile(deck, work / "case.toml")
    return work / "case.toml"


def nonzero_required(case_dir: Path, results: Path) -> list[tuple[str, int]]:
    """(block name, non-zero count) for every observable the case declares must_be_nonzero.

    The observable names the RESULT BLOCK it is about, in `block`. It used to be matched
    through `components`, which worked only because the one case that used it had a block
    whose name equalled its single component name ("PLASTICSTRAIN"). The first observable
    that did not -- DISPLACEMENT, whose components are ux/uy -- matched nothing at all, and
    the assertion silently asserted nothing while the gate stayed green. Measured
    2026-09-17. So the block is stated, and an observable that names a block the results do
    not contain is reported as a count of -1, which the caller treats as a failure: a
    must_be_nonzero that checks nothing is worse than none, because it reads as evidence.
    """
    obs = case_dir / "observables.toml"
    if not obs.is_file():
        return []
    doc = tomllib.loads(obs.read_text(encoding="utf-8"))
    wanted = {}
    for o in doc.get("observable", []):
        if not o.get("must_be_nonzero") or o.get("block") is None:
            continue
        # `in_range = [lo, hi]` is the half M11 was missing. damage_2d.concrete_gravdam's
        # Yield block passed must_be_nonzero on 169 values ABOVE 1e9 -- an uninitialised
        # local written into the output slot (PD-3) -- while a real damage value can only
        # be 0 or 1-sqrt(cc). A count alone cannot tell those apart; a declared range can,
        # and a non-zero count is only evidence when the values are values of the thing.
        wanted[o["block"]] = o.get("in_range")
    if not wanted:
        return []
    parsed = json.loads(results.read_text(encoding="utf-8"))
    counts: dict[str, int] = {b: -1 for b in wanted}
    outside: dict[str, int] = {b: 0 for b in wanted}
    worst: dict[str, float] = {}
    for b in parsed["blocks"]:
        if b["name"] not in wanted:
            continue
        lo_hi = wanted[b["name"]]
        n = 0
        for row in b["rows"].values():
            for v in row:
                if v == 0.0:
                    continue
                if lo_hi is not None and not (lo_hi[0] <= v <= lo_hi[1]):
                    outside[b["name"]] += 1
                    if abs(v) > abs(worst.get(b["name"], 0.0)):
                        worst[b["name"]] = v
                    continue
                n += 1
        counts[b["name"]] = max(counts[b["name"]], 0) + n
    return [(b, counts[b], outside[b], wanted[b], worst.get(b))
            for b in sorted(counts)]


def compare(ref: Path, actual: Path) -> tuple[bool, str]:
    cp = subprocess.run([sys.executable, str(ROOT / "tools/yl_compare.py"), str(ref), str(actual)],
                        capture_output=True, text=True)
    line = cp.stdout.strip().splitlines()[0] if cp.stdout.strip() else cp.stderr.strip()
    return cp.returncode == 0, line


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--binary", default=str(ROOT / "build/release/hstar"))
    a = ap.parse_args(argv)
    binary = Path(a.binary).resolve()
    if not binary.is_file():
        raise SystemExit(f"binary missing: {binary} (run tools/build.sh release)")

    problems: list[str] = []

    for cid, case_dir in cases():
        # .json or .json.gz: a big reference is compressed, and yl_compare reads either.
        ref = case_dir / "reference/results.json"
        if not ref.is_file():
            ref = case_dir / "reference/results.json.gz"
        with tempfile.TemporaryDirectory(prefix="yl-modern.") as td:
            work = Path(td)
            stage(case_dir, work)
            cp = subprocess.run([str(binary), "--input=case.toml"], cwd=work,
                                stdin=subprocess.DEVNULL, capture_output=True,
                                text=True, errors="replace", env=pinned_env())
            res = work / "1.flavia.res"
            if cp.returncode != 0 or not (res.is_file() and res.stat().st_size > 0):
                problems.append(f"N1 {cid}: the modern-input run exited {cp.returncode} "
                                f"without results\n{(cp.stdout + cp.stderr)[-800:]}")
                print(f"  N1 {cid:<28} rc={cp.returncode} FAIL")
                continue
            print(f"  N1 {cid:<28} rc=0, mesh + case.toml only")

            out = work / "results.json"
            pp = subprocess.run([sys.executable, str(ROOT / "tools/yl_parse_flavia.py"),
                                 str(res), "-o", str(out)], capture_output=True, text=True)
            if pp.returncode != 0:
                problems.append(f"N2 {cid}: the output did not parse\n{pp.stdout + pp.stderr}")
                continue
            ok, line = compare(ref, out)
            print(f"  N2 {cid:<28} vs frozen reference  {line}")
            if not ok:
                problems.append(f"N2 {cid}: the modern path does not reproduce the reference")
            for block, n, n_out, rng, worst in nonzero_required(case_dir, out):
                rtxt = "" if rng is None else f" in [{rng[0]}, {rng[1]}]"
                print(f"  N4 {cid:<28} {block} non-zero values{rtxt}: {n}"
                      + (f", OUTSIDE: {n_out} (worst {worst:.6g})" if n_out else ""))
                if n < 0:
                    problems.append(f"N4 {cid}: {block} is declared must_be_nonzero but the "
                                    f"results carry no such block -- the assertion checks "
                                    f"nothing")
                elif n == 0:
                    problems.append(f"N4 {cid}: {block} is declared must_be_nonzero and is "
                                    f"all zeros -- the case does not exercise what it is for")
                if n_out:
                    problems.append(f"N4 {cid}: {block} carries {n_out} value(s) outside the "
                                    f"declared range [{rng[0]}, {rng[1]}], worst {worst:.6g} "
                                    f"-- those are not values of the quantity, so counting "
                                    f"them as evidence is what PD-3 did")

    # N3 -- a deck the contract rejects must stop, readably.
    bad_id, bad_dir = cases()[0]

    def _step_count(case_dir: Path) -> int:
        text = (case_dir / "modern/case.toml").read_text(encoding="utf-8")
        return text.count("\n[[step]]") + text.startswith("[[step]]")

    def rejected(label: str, arg: str, mutate=None, case: str | None = None) -> str:
        """Run a deck that must be refused; assert the run stopped and wrote nothing.
        Returns the combined output so the caller can assert what it SAID."""
        if case is None:
            src = bad_dir
        else:
            _d = tomllib.loads(MANIFEST.read_text(encoding="utf-8"))
            src = ROOT / "cases" / next(c["path"] for c in _d["case"] if c["id"] == case)
        with tempfile.TemporaryDirectory(prefix="yl-modern-bad.") as td:
            work = Path(td)
            deck = stage(src, work)
            if mutate is not None:
                deck.write_text(mutate(deck.read_text(encoding="utf-8")), encoding="utf-8")
            cp = subprocess.run([str(binary), arg], cwd=work, stdin=subprocess.DEVNULL,
                                capture_output=True, text=True, errors="replace", env=pinned_env())
            res = work / "1.flavia.res"
            wrote = res.is_file() and res.stat().st_size > 0
            print(f"  N3 {label:<28} rc={cp.returncode} "
                  f"results_written={'YES' if wrote else 'no'}")
            if cp.returncode not in (2, 3):
                problems.append(f"N3 {label}: exited {cp.returncode}, not 2/3 -- a deck "
                                f"the contract refuses must stop with the input verdict")
            if wrote:
                problems.append(f"N3 {label}: still produced results")
            return cp.stdout + cp.stderr

    def sub(a: str, b: str):
        def f(text: str) -> str:
            assert a in text, f"deck no longer carries the mutated line: {a}"
            return text.replace(a, b, 1)
        return f

    def resub(pattern: str, b: str):
        """Regex form of `sub`, for a key whose VALUE differs between decks. The concrete
        mutation below picks whichever deck the manifest lists first, and the two CONCRETE
        decks write different crack models (6 and 3), so matching the literal line tied the
        test to one deck's value and broke the moment the other came first."""
        def f(text: str) -> str:
            new_text, n = re.subn(pattern, b, text, count=1)
            assert n == 1, f"deck no longer carries a line matching: {pattern}"
            return new_text
        return f

    # a -- a whitelisted key carrying an unlisted value: a capability refusal, not a typo.
    blob = rejected("unlisted value", "--input=case.toml",
                    sub('element     = "Q4"', 'element     = "Q8"'))
    if "element" not in blob or "Q8" not in blob:
        problems.append("N3 unlisted value: the rejection named neither the key nor the value")

    # b -- unreadable at all. The name the operator typed has to appear: these two used to
    # fall through to the legacy reader and die there with no mention of the input file.
    blob = rejected("file not there", "--input=absent.toml")
    if "absent.toml" not in blob:
        problems.append("N3 file not there: the refusal never named the file asked for")
    if "Input the problem name" in blob:
        problems.append("N3 file not there: fell through to the legacy reader's prompt")

    blob = rejected("not the TOML subset", "--input=case.toml",
                    lambda _: 'version = 1\n[case\nname = "x"\n')
    if "case.toml:2" not in blob:
        problems.append("N3 not the TOML subset: the refusal did not point at line 2")
    if "Input the problem name" in blob:
        problems.append("N3 not the TOML subset: fell through to the legacy reader's prompt")

    # b2 -- a mapping-stage finding, which the validator suite cannot reach: it runs the
    # validator alone, and this rule reads the MESH file to check the author's counts.
    blob = rejected("element counts do not add up", "--input=case.toml",
                    sub("element_count = 256", "element_count = 255"))
    if "element_count" not in blob:
        problems.append("N3 element counts: the refusal did not name the key")

    # b3 -- the refusals that belong to the mapping layer for the same reason as b2:
    # they are statements about what this BINARY can run, not about what the input
    # language can say. Two earlier controls lived here -- "a second analysis step" and
    # "a pressure load" -- and BOTH were retired on 2026-09-16, when those shapes became
    # supported. A control asserting a refusal that no longer happens does not fail safe;
    # it goes green for the wrong reason. What replaced them is here and in b4: the
    # refusals that are still true.
    def two_gravities(text: str) -> str:
        i = text.index("[[step.load]]")
        j = text.index("\n\n", i)
        return text[:j] + "\n" + text[i:j] + text[j:]

    blob = rejected("two gravity loads in one step", "--input=case.toml", two_gravities)
    if "gravity" not in blob:
        problems.append("N3 two gravity loads: the refusal did not name what it counted")

    # b4 -- the one thing a multi-step deck still cannot do. Prescribed degrees of
    # freedom are committed once, from step 1, so a deck whose second step releases a
    # constraint would run the whole analysis on step 1's constraints and produce
    # plausible numbers with nothing saying so. Predicted before running: exit 3, the
    # message naming steps[].boundary, no results.
    # Read from the manifest, not from cases(): the multi-step deck is exactly the one
    # whose modern gate is off, and this control is about the refusal, not the numbers.
    _doc = tomllib.loads(MANIFEST.read_text(encoding="utf-8"))
    multi = next((c["id"] for c in _doc.get("case", [])
                  if (ROOT / "cases" / c["path"] / "modern/case.toml").is_file()
                  and _step_count(ROOT / "cases" / c["path"]) > 1), None)
    if multi is not None:
        blob = rejected("boundaries that change between steps", "--input=case.toml",
                        lambda t: t.replace('nset  = "left_edge"\ndof   = [1]',
                                            'nset  = "base"\ndof   = [1]', 1)
                        if t.count('nset  = "left_edge"') >= 1 else t,
                        case=multi)
        if "boundary" not in blob:
            problems.append("N3 boundaries that change: the refusal did not name the field")

    # b5 -- the other half of the steps(1) hazard. Legacy reads some fields once for the
    # whole analysis, so this build commits them from step 1; a later step that disagrees
    # would be dropped silently. Predicted before running: exit 3, the message saying the
    # steps disagree about something legacy reads once.
    if multi is not None:
        blob = rejected("steps that disagree about a per-analysis field", "--input=case.toml",
                        lambda t: t.replace('procedure     = "static"',
                                            'procedure     = "dynamic"', 1)
                        if t.count('procedure     = "static"') > 1 else t,
                        case=multi)
        if "reads once" not in blob and "static" not in blob:
            problems.append("N3 steps disagree: the refusal did not say what it compared")

    # b6 -- the DUNCANCHANG block. Five controls, because the model adds five distinct ways
    # to be wrong and each has a different verdict. PREDICTED BEFORE RUNNING, all on the
    # deck that actually has the model except where noted:
    #   c1  bulk law "EV"            exit 3, names bulk_modulus_law and EV  (capability)
    #   c2  a parameter deleted      exit 2, names failure_ratio            (missing field)
    #   c3  fill_elevation deleted   exit 2, names initial_stress.fill_elevation
    #   c4  fill_elevation on mini_mc exit 2, names initial_stress.fill_elevation
    #   c5  a DC parameter on an elastic material   exit 2, names modulus_number
    # and what must stay SILENT: none of these may touch the six N2 comparisons above.
    duncan = next((c["id"] for c in _doc.get("case", [])
                   if (ROOT / "cases" / c["path"] / "modern/case.toml").is_file()
                   and 'model   = "duncanchang"' in
                       (ROOT / "cases" / c["path"] / "modern/case.toml").read_text(encoding="utf-8")),
                  None)
    if duncan is not None:
        blob = rejected("duncanchang bulk law EV", "--input=case.toml",
                        sub('bulk_modulus_law = "EB"', 'bulk_modulus_law = "EV"'), case=duncan)
        if "bulk_modulus_law" not in blob or "EV" not in blob:
            problems.append("N3 duncanchang bulk law: the refusal named neither the key nor "
                            "the value")

        blob = rejected("duncanchang parameter missing", "--input=case.toml",
                        lambda t: "\n".join(l for l in t.splitlines()
                                            if not l.startswith("failure_ratio")) + "\n",
                        case=duncan)
        if "failure_ratio" not in blob:
            problems.append("N3 duncanchang parameter missing: the refusal did not name the key")

        blob = rejected("duncanchang without a datum", "--input=case.toml",
                        lambda t: "\n".join(l for l in t.splitlines()
                                            if not l.startswith("fill_elevation")) + "\n",
                        case=duncan)
        if "fill_elevation" not in blob:
            problems.append("N3 duncanchang without a datum: the refusal did not name the key")

    # c4/c5 run on a case with NO duncanchang material: the forbidden-without-the-model
    # half. Without these two the required-together rule would be satisfied by a validator
    # that simply accepted the keys everywhere.
    plain = next((c["id"] for c in _doc.get("case", [])
                  if (ROOT / "cases" / c["path"] / "modern/case.toml").is_file()
                  and 'model   = "duncanchang"' not in
                      (ROOT / "cases" / c["path"] / "modern/case.toml").read_text(encoding="utf-8")),
                 None)
    if plain is not None:
        blob = rejected("a datum with no model that reads it", "--input=case.toml",
                        sub("[step.controls]",
                            "[step.initial_stress]\nfill_elevation = 0.0\n\n[step.controls]"),
                        case=plain)
        if "fill_elevation" not in blob:
            problems.append("N3 datum with no model: the refusal did not name the key")

        blob = rejected("a duncanchang parameter on another model", "--input=case.toml",
                        sub("[[section]]", "modulus_number = 300.0\n\n[[section]]"),
                        case=plain)
        if "modulus_number" not in blob:
            problems.append("N3 duncanchang parameter on another model: the refusal did not "
                            "name the key")

    # b7 -- the solver block. Three controls, PREDICTED BEFORE RUNNING:
    #   s1  matrix_type = 2       exit 3, names the key and the value   (capability)
    #   s2  matrix_type deleted   exit 2, names the key                 (missing field)
    #   s3  the block on a PROFILE case   exit 2, names the key         (forbidden)
    # and what must stay SILENT: none of these may disturb the eight N2 comparisons above.
    pardiso = next((c["id"] for c in _doc.get("case", [])
                    if (ROOT / "cases" / c["path"] / "modern/case.toml").is_file()
                    and 'linear = "pardiso"' in
                        (ROOT / "cases" / c["path"] / "modern/case.toml").read_text(encoding="utf-8")),
                   None)
    if pardiso is not None:
        blob = rejected("pardiso matrix type 2", "--input=case.toml",
                        sub("matrix_type   = -2", "matrix_type   = 2"), case=pardiso)
        if "matrix_type" not in blob:
            problems.append("N3 pardiso matrix type: the refusal did not name the key")

        blob = rejected("pardiso without a matrix type", "--input=case.toml",
                        lambda t: "\n".join(l for l in t.splitlines()
                                            if not l.startswith("matrix_type")) + "\n",
                        case=pardiso)
        if "matrix_type" not in blob:
            problems.append("N3 pardiso without a matrix type: the refusal did not name the key")

        # The forbidden direction: the settings on a case whose solver is not PARDISO.
        # Without it the required-together rule would be satisfied by a validator that
        # simply accepted the keys everywhere.
        blob = rejected("pardiso settings on a profile case", "--input=case.toml",
                        sub('linear = "pardiso"', 'linear = "profile"'), case=pardiso)
        if "pardiso" not in blob:
            problems.append("N3 pardiso settings on a profile case: the refusal did not name "
                            "the key")

    # b8 -- the CONCRETE block. PREDICTED BEFORE RUNNING:
    #   k1  crack_model = 2        exit 3, names the key and the value   (capability)
    #   k2  a parameter deleted    exit 2, names the key                 (missing field)
    #   k3  the block on another model   exit 2, names the key           (forbidden)
    # SILENT: none of these may disturb the nine N2 comparisons above.
    # A GATED concrete deck, not merely a concrete one: these three controls mutate a deck
    # and read the refusal, and a deck whose modern gate is off is one whose numbers are
    # not verified, so driving the controls from it would rest them on unchecked ground.
    # The distinction only became real when a second concrete deck arrived with its gate
    # off (elements_2d.rcbeam, 2026-09-18) and, being first in the manifest, silently
    # became the deck every concrete control mutated.
    _gated = {cid for cid, _ in cases()}
    conc = next((c["id"] for c in _doc.get("case", [])
                 if c["id"] in _gated
                 and (ROOT / "cases" / c["path"] / "modern/case.toml").is_file()
                 and 'model   = "concrete"' in
                     (ROOT / "cases" / c["path"] / "modern/case.toml").read_text(encoding="utf-8")),
                None)
    if conc is not None:
        blob = rejected("concrete crack model 2", "--input=case.toml",
                        resub(r"crack_model(\s*)= *\d+", r"crack_model\g<1>= 2"), case=conc)
        if "crack_model" not in blob:
            problems.append("N3 concrete crack model: the refusal did not name the key")

        blob = rejected("concrete without a strength", "--input=case.toml",
                        lambda t: "\n".join(l for l in t.splitlines()
                                            if not l.startswith("compressive_strength")) + "\n",
                        case=conc)
        if "compressive_strength" not in blob:
            problems.append("N3 concrete without a strength: the refusal did not name the key")

        # The forbidden direction: a CONCRETE parameter on the elastic material in the SAME
        # deck. Without it the required-together rule would be satisfied by a validator that
        # accepted the keys on any material.
        blob = rejected("concrete parameter on another model", "--input=case.toml",
                        sub('name    = "rock"', 'crack_model = 6\nname    = "rock"'), case=conc)
        if "crack_model" not in blob:
            problems.append("N3 concrete parameter on another model: the refusal did not name "
                            "the key")

    # c -- several findings at once, each reported exactly once.
    blob = rejected("three findings", "--input=case.toml",
                    lambda t: sub("density = 2400.0", 'density = "heavy"')(
                              sub("nu      = 0.2", "nu_typo = 0.2")(t)))
    for want, label in (("material[1].density", "wrong type"),
                        ("material[1].nu_typo", "unknown key"),
                        ("material[1].nu", "missing required")):
        n = sum(1 for line in blob.splitlines() if f"{want}:" in line)
        if n != 1:
            problems.append(f"N3 three findings: `{want}` ({label}) was rendered {n} times, "
                            f"not once")

    for p in problems:
        print(f"FAIL {p}")
    if problems:
        print(f"MODERN FAIL: {len(problems)} problem(s)")
        return 1
    print("MODERN PASS: every golden case runs from case.toml + mesh alone and reproduces "
          "the frozen legacy reference exactly; a rejected deck stops with the key named")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
