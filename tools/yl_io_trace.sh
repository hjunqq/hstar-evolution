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
CASE_DIR="$ROOT/cases/golden/static_2d/$CASE_NAME"
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

( cd "$WORK" && OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 gdb -batch -x bp.gdb "$BIN" > gdb-console.txt 2>&1 ) || true
cp "$WORK/gdb-console.txt" "$OUT/gdb-console.txt"
python3 "$ROOT/tools/yl_io_inventory.py" hits --log "$WORK/hits.log" --case-id "$CASE_ID" -o "$OUT/hits.json"

REF_RES="$CASE_DIR/reference/results.json"
python3 "$ROOT/tools/yl_parse_flavia.py" "$WORK/1.flavia.res" -o "$WORK/results.json" >/dev/null
if python3 "$ROOT/tools/yl_compare.py" "$REF_RES" "$WORK/results.json" -o "$OUT/compare-vs-reference.json" >/dev/null; then
    echo "OK: $CASE_ID traced; results identical to reference; evidence in $OUT"
else
    echo "REJECTED: $CASE_ID results differ from reference under gdb; see $OUT/compare-vs-reference.json" >&2
    exit 5
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
