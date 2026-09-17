#!/usr/bin/env bash
# Count executions of every I/O statement site for one golden case (M1-01).
#
#   tools/yl_io_trace.sh <case_id> [--binary build/trace/hstar] [--out docs/m1/evidence/<case>]
#
# Runs the trace-profile binary under gdb -batch in an isolated copy of the
# case inputs, breakpoints on every address each census site's line compiles to
# (docs/m1/io-sites.json; see R27 -- one line can be several ranges), and
# writes hits.json, bp-locations.json, gdb-console.txt and a comparison of 1.flavia.res
# against the frozen reference. The comparison must be IDENTICAL, otherwise
# the instrumentation perturbed the run and the evidence is rejected.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tools/env.sh"

CASE_ID="${1:?case id}"; shift
BIN="$ROOT/build/trace/hstar"; OUT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --binary) BIN="$2"; shift;;
        --out) OUT="$2"; shift;;
        *) echo "unknown argument: $1" >&2; exit 2;;
    esac; shift
done
CASE_NAME="${CASE_ID#*.}"
# The case directory comes from cases/manifest.toml, not from a hard-coded family name:
# the .loa load domain put a third case (loads_2d.wall_reservoir) into the inventory's
# evidence set, and a tracer that can only find static_2d cases would have silently
# traced the wrong directory or none at all.
CASE_DIR="$ROOT/$(python3 - "$CASE_ID" <<'PYEOF'
import sys, tomllib, pathlib
root = pathlib.Path(__file__).resolve().parent if False else None
m = tomllib.loads(open("cases/manifest.toml", "rb").read().decode("utf-8"))
for c in m["case"]:
    if c["id"] == sys.argv[1]:
        print("cases/" + c["path"]); break
else:
    raise SystemExit(f"{sys.argv[1]}: not in cases/manifest.toml")
PYEOF
)"
[ -d "$CASE_DIR" ] || { echo "case directory not found: $CASE_DIR" >&2; exit 3; }
[ -z "$OUT" ] && OUT="$ROOT/docs/m1/evidence/$CASE_NAME"
[ -x "$BIN" ] || { echo "trace binary missing: $BIN (run tools/build.sh trace)" >&2; exit 3; }
[ -f "$ROOT/docs/m1/io-sites.json" ] || { echo "census missing: run tools/yl_io_inventory.py scan" >&2; exit 3; }
command -v gdb >/dev/null || { echo "gdb not found" >&2; exit 3; }

python3 "$ROOT/tools/yl_manifest.py" check "$CASE_DIR/input-manifest.json" >/dev/null \
    || { echo "input manifest does not verify for $CASE_ID" >&2; exit 4; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/yl-io-trace.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
cp "$CASE_DIR"/legacy/* "$WORK/"
mkdir -p "$OUT"
python3 "$ROOT/tools/yl_io_inventory.py" gdb-script --log "$WORK/hits.log" -o "$WORK/bp.gdb" \
    --binary "$BIN" --locations "$OUT/bp-locations.json"

# The control run: the SAME binary, same inputs, no gdb. What this comparison has to
# establish is that the instrumentation is inert -- breakpoints did not perturb the run --
# and the only comparison that establishes it is against this binary's own output.
#
# It used to compare against the frozen reference instead, which is a DIFFERENT claim: the
# reference is produced by the release (-O2) build and the tracer runs the trace (-O0)
# build, so that comparison was really asserting build independence, which this project
# has registered as open debt rather than established. It passed on the static pair by
# luck and failed on the first deck with genuinely zero shear stresses
# (loads_2d.beam_point_load, 2026-09-17: 6 of 756 values, max|d| = 1.3e-10, all of them
# noise around zero). Both comparisons are made now; only the one the tracer can honestly
# claim is fatal.
( cd "$WORK" && OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 "$BIN" --adapter=off < /dev/null > plain.txt 2>&1 ) || true
[ -s "$WORK/1.flavia.res" ] || { echo "control run wrote no results for $CASE_ID" >&2; exit 5; }
cp "$WORK/1.flavia.res" "$WORK/plain.flavia.res"

( cd "$WORK" && OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 gdb -batch -x bp.gdb "$BIN" > gdb-console.txt 2>&1 ) || true
cp "$WORK/gdb-console.txt" "$OUT/gdb-console.txt"
python3 "$ROOT/tools/yl_io_inventory.py" hits --log "$WORK/hits.log" --case-id "$CASE_ID" -o "$OUT/hits.json"

if ! cmp -s "$WORK/plain.flavia.res" "$WORK/1.flavia.res"; then
    echo "REJECTED: $CASE_ID -- the same binary produced different results with and without" >&2
    echo "          gdb, so the instrumentation perturbed the run and the hit counts are" >&2
    echo "          evidence about a different execution than the one being measured." >&2
    exit 5
fi

# And, reported rather than enforced: how this build compares with the frozen reference.
# A large difference here would mean the trace build is a different program, which is
# worth seeing even though it is not what this tool is for.
# .json or .json.gz: yl_freeze compresses a big reference and yl_compare reads either.
# rcbeam is the first traced case whose reference is compressed, and without this the
# comparison died on a missing file AFTER the evidence had already been collected --
# a non-zero exit that said "trace failed" about a step this tool only reports.
REF_RES="$CASE_DIR/reference/results.json"
[ -f "$REF_RES" ] || REF_RES="$CASE_DIR/reference/results.json.gz"
python3 "$ROOT/tools/yl_parse_flavia.py" "$WORK/1.flavia.res" -o "$WORK/results.json" >/dev/null
if python3 "$ROOT/tools/yl_compare.py" "$REF_RES" "$WORK/results.json" -o "$OUT/compare-vs-reference.json" >/dev/null; then
    echo "OK: $CASE_ID traced; instrumentation inert, and this build also matches the frozen reference exactly"
else
    echo "OK: $CASE_ID traced; instrumentation inert (same binary, with and without gdb, byte identical)."
    python3 - "$OUT/compare-vs-reference.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
print(f"    note: the trace build differs from the release reference on "
      f"{d['n_mismatch']}/{d['n_values']} values, max|d| = {d['max_abs_diff']:.3e} -- "
      f"that is build independence (open debt), not instrumentation")
PYEOF
fi
python3 - "$BIN" "$OUT" <<'PY'
import hashlib, json, sys, pathlib
b, out = sys.argv[1], pathlib.Path(sys.argv[2])
doc = json.loads((out / "hits.json").read_text())
doc["binary_sha256"] = hashlib.sha256(pathlib.Path(b).read_bytes()).hexdigest()
bm = pathlib.Path(b).parent / "build-manifest.json"
doc["build_profile"] = json.loads(bm.read_text())["profile"] if bm.is_file() else None
(out / "hits.json").write_text(json.dumps(doc, indent=1) + "\n")
PY
