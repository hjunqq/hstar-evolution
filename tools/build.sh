#!/usr/bin/env bash
# HSTAR Evolution — reproducible Linux build of the legacy YL solver (M0-02).
#
#   tools/build.sh [release|debug] [--src DIR] [--out DIR] [--label NAME]
#   tools/build.sh problem-types [--profile release|strict] [--out DIR] [--label NAME]
#                                [--allow-external-out]
#   tools/build.sh runtime        [--profile ...] [--out DIR] [--label NAME]
#                                [--allow-external-out]
#   tools/build.sh runtime-bridge [--profile ...] [--src DIR] [--out DIR] [--label NAME]
#   tools/build.sh adapter        [--profile ...] [--src DIR] [--out DIR] [--label NAME]
#                                [--allow-external-out]
#
# Profiles:
#   release  -O2                                  (reference numerics)
#   trace    -O0 -g -traceback, no runtime checks; for gdb breakpoint
#            counting of I/O statements (tools/yl_io_trace.sh, M1-01)
#   debug    -O0 -g -traceback -check bounds,pointers
#            On the pure snapshot this aborts at Fem.f90:12288 (tcurves(0)
#            read when a prescribed set has itcurve=0) -> M1 firewall target.
#   strict   debug + -init=snan,arrays -fpe0 (ifx traps on the signalling NaN
#            even without -fpe0). Aborts earlier at Elements.f90:2588
#            (uninitialised t/u for 1-D element kinds) -> M1 firewall target.
#   sanitize strict + -check uninit (MemorySanitizer). UNBLOCKED 2026-09-09.
#            It really did trip MSan before main -- but the report is a false
#            positive inside the UNINSTRUMENTED OpenMP runtime
#            (__kmp_affinity_insert_numa_nodes, z_Linux_util.cpp:364), reached
#            while libiomp reads the machine topology, before any repository or
#            legacy code runs. Setting KMP_AFFINITY=disabled skips that topology
#            walk; the runtime-bridge suite then completes 720/720 under MSan.
#            This is a workaround for an uninstrumented dependency, NOT a
#            suppression of a finding in our own code: nothing here is silenced,
#            and any MSan report from repository or legacy code still fails the
#            run. Note also that this profile is MemorySanitizer (use of
#            uninitialised memory); it does NOT detect leaks. Leak evidence needs
#            -fsanitize=address or valgrind and is still NOT PERFORMED.
#   asan     -O1 -g -fsanitize=address: AddressSanitizer, and with it
#            LeakSanitizer, which is on by default. THE CONVERSE OF `sanitize`,
#            not a stronger version of it: `sanitize` is MemorySanitizer and
#            finds reads of uninitialised memory but NOT leaks; this profile
#            finds leaks and use-after-free but NOT uninitialised reads. Neither
#            substitutes for the other, and M4-01 step 6 needs this one.
#            WHAT LEAKSANITIZER CANNOT SEE: it reports blocks that are
#            UNREACHABLE at exit. Memory still referenced by a live module
#            variable is not a leak to it, however wrong holding it may be. That
#            is why the leak controls must release the OWNER (so the inner
#            target becomes unreachable) rather than simply skip a deallocate
#            while the global still points at it -- measured on a deliberate
#            leak before any of this was built: a pointer left live in the main
#            program is reported as nothing at all.
#   Only `release` is the M0 reference build; the checking profiles are kept
#   so that the recorded evidence can be reproduced (docs/build-linux.md).
#
# Outputs (default OUT=build/<profile>[-<label>]):
#   OUT/obj/*.o *.mod        OUT/hstar          OUT/build.log
#   OUT/build-manifest.json  compiler/flags/deps/hashes/ldd; fail-closed
#
# Targets `problem-types` (M3-01, extended by M3-02), `runtime` and
# `runtime-bridge` (M3-03) and `adapter` (M4-01) are SEPARATE targets, not solver
# profiles. None of their objects is an input to build/<profile>/hstar.
#
# `adapter` is `runtime-bridge`'s link surface plus the eight src/adapter modules,
# and it builds three programs instead of one: yl_adapter_bridge_test (L3-b, run
# here), yl_adapter_dialect_test (L2-b, run here on BOTH golden decks), and
# yl_adapter_shadow (L3-c, built here but driven by tools/yl_shadow_diff.py, which
# needs two child processes in two directories). It exists because until it did,
# all three were built by throwaway scratch scripts, and a suite with no build
# target is not a gate however green it runs by hand. It also refuses to finish if
# anything under cases/ changed during the run.
#
# `runtime` compiles the problem modules and then src/runtime/yl_runtime_{types,
# contract,rules,build}.f90 and links src/runtime/yl_runtime_selftest.f90. It does
# NOT compile yl_runtime_commit.f90: that module USEs the legacy modules, so it
# belongs to `runtime-bridge` alone -- which is also the mechanical guarantee that
# no self-test in the `runtime` binary can write a legacy global.
#
# `runtime-bridge` is the isolated bridge executable: the real legacy modules
# through Level.f90 (Fem.f90 excluded, so there is no solver main), src/state,
# src/problem, src/runtime INCLUDING yl_runtime_commit.f90, and its own PROGRAM.
# It is the only target that compiles the commit module. Its evidence is PARTIAL by
# construction: no solver consumer runs in it.
#
# Target `problem-types` in detail. It compiles, in dependency order,
#   src/problem/yl_problem_{optional,types,errors,profile,manifest,builder,
#                           pipeline}.f90
# and links TWO self-test programs, each into its own binary:
#   src/problem/yl_problem_selftest.f90          -> OUT/yl_problem_selftest
#   src/problem/yl_problem_pipeline_selftest.f90 -> OUT/yl_problem_pipeline_selftest
# Both are run; both must pass or the target fails, and the log names the suite
# that broke. The target uses its own output and module directory
# (default OUT=build/problem-types/<profile>[-<label>]) and its own manifest
# OUT/problem-types-manifest.json, which records every source in compile order
# with its sha256 and both test binaries. src/problem/* MUST NOT appear in the solver
# source list, object list, link command or SRC_ENTRIES: per
# .ccg/tasks/m3-01-problemstate-types/analysis-codex.md S5 the new objects stay
# out of the solver link chain, so the solver binary cannot drift. The
# non-drift criterion is GNU build-id equality (readelf -n), not whole-file
# SHA-256: two builds from identical sources into the same path differ in a
# few bytes of a random temp-file token embedded by the compiler, while the
# build-id is constant. legacy/source-manifest.json is not touched by this
# target; these sources were never solver inputs.
#
# The target erases --out before building, so --out is write-guarded in the
# style of the --runs-root guard in tools/yl_probe.py: a destination that is,
# contains, or is contained by the repository root, a solver output root
# (build/{release,debug,strict,trace,sanitize}) or a source tree
# (cases/ legacy/ src/ tools/ docs/ schemas/) is refused before anything is
# deleted. A destination outside the repository needs --allow-external-out,
# so that a mistyped path cannot silently erase something elsewhere.
# --src selects the legacy solver tree and has no meaning here; passing it
# with problem-types is an error rather than a silently ignored flag.
#
# Compile order: src/diagnostics/{yl_diag_registry,yl_diag}.f90 (repository
# side, M1-02) first, then the legacy modules through Level.f90, then
# src/state/*.f90 (repository side, M2-02), then the main program Fem.f90.
#
# The build refuses to start if legacy/source-manifest.json does not verify
# against --src when --src is the in-repo snapshot, so that every binary is
# tied to hashed sources. For an external tree (e.g. the dirty candidate
# worktree, M0-04c) pass --src and --label; the manifest records the tree's
# own hash list instead.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tools/env.sh
source "$ROOT/tools/env.sh"

PROFILE=release; SRC="$ROOT/legacy/yl"; OUT=""; LABEL=""; TARGET=solver
SRC_GIVEN=0; ALLOW_EXTERNAL_OUT=0
while [ $# -gt 0 ]; do
    case "$1" in
        release|trace|debug|strict|sanitize|asan) PROFILE="$1";;
        problem-types) TARGET=problem-types;;
        runtime) TARGET=runtime;;
        runtime-bridge) TARGET=runtime-bridge;;
        adapter) TARGET=adapter;;
        solver-adapter) TARGET=solver-adapter;;
        --profile)
            case "$2" in
                release|trace|debug|strict|sanitize|asan) PROFILE="$2";;
                *) echo "build.sh: unknown profile: $2" >&2; exit 2;;
            esac
            shift;;
        --src) SRC="$(cd "$2" && pwd)"; SRC_GIVEN=1; shift;;
        --allow-external-out) ALLOW_EXTERNAL_OUT=1;;
        --out) OUT="$2"; shift;;
        --label) LABEL="$2"; shift;;
        -h|--help) sed -n '2,50p' "$0"; exit 0;;
        *) echo "unknown argument: $1" >&2; exit 2;;
    esac
    shift
done
case "$TARGET" in
    problem-types|runtime|runtime-bridge|adapter)
        [ -z "$OUT" ] && OUT="$ROOT/build/$TARGET/$PROFILE${LABEL:+-$LABEL}";;
    solver-adapter)
        [ -z "$OUT" ] && OUT="$ROOT/build/solver-adapter${LABEL:+-$LABEL}";;
    *)
        [ -z "$OUT" ] && OUT="$ROOT/build/$PROFILE${LABEL:+-$LABEL}";;
esac

hstar_env_check || { echo "build.sh: toolchain check failed" >&2; exit 3; }

STUB="$ROOT/legacy/stubs/gidpost_stub.c"
# asan only; see its header for why it is here and not under legacy/stubs/.
OMP_STUB="$ROOT/tools/asan/omp_stub.c"
MKL_INC="$HSTAR_MKLROOT/include"
MKL_LIB="$HSTAR_MKLROOT/lib"

case "$PROFILE" in
    release)  FFLAGS=(-O2);;
    trace)    FFLAGS=(-O0 -g -traceback);;
    debug)    FFLAGS=(-O0 -g -traceback -check bounds,pointers);;
    strict)   FFLAGS=(-O0 -g -traceback -check bounds,pointers -init=snan,arrays -fpe0);;
    sanitize) FFLAGS=(-O0 -g -traceback -check bounds,pointers,uninit -init=snan,arrays -fpe0);;
    asan)     FFLAGS=(-O1 -g -fsanitize=address);;
esac
LDFLAGS=(-qopenmp "-L$MKL_LIB" -lmkl_intel_lp64 -lmkl_intel_thread -lmkl_core
         "-L$HSTAR_IOMP_LIBDIR" -liomp5 -lpthread -lm -ldl
         "-Wl,--disable-new-dtags" "-Wl,-rpath,$MKL_LIB" "-Wl,-rpath,$HSTAR_IOMP_LIBDIR")

# asan LINKS WITHOUT -qopenmp, AND THAT IS NOT A TIDY-UP -- IT IS THE WHOLE PROFILE.
# MEASURED: the same deliberate leak (a pointer array allocated in a procedure and
# nullified) is reported by LeakSanitizer when linked plainly, and reported as NOTHING
# when `-qopenmp` is on the link line. Bisected: MKL alone still reports it; -qopenmp
# alone silences it. The Intel OpenMP runtime disables LSan, with no diagnostic --
# ASan itself stays fully active, so the binary looks instrumented and reports clean.
#
# That is why this override exists rather than a note: with -qopenmp the leak half of
# this profile is silently off, and M4-01 step 6's entire exit condition is "valgrind or
# ASan must REPORT a deliberately reintroduced leak". A profile that cannot fail its own
# positive control would have certified the release path clean while detecting nothing.
# It was caught by running the positive control first, which is the only reason this
# comment is here and not a false all-clear in the report.
#
# The sequential MKL layer replaces the threaded one because the threaded layer is what
# needs iomp5. Nothing this profile builds runs the solver's threaded numerics: it exists
# to exercise commit -> release -> commit and count what was not freed.
if [ "$PROFILE" = asan ]; then
    # $HSTAR_IOMP_LIBDIR stays on the line: it is the Intel COMPILER library directory and
    # resolves libimf/libintlc as well as libiomp5. Only the OpenMP runtime itself is
    # dropped -- removing the whole -L took libimf.so with it and build.sh's own
    # runtime-dependency check caught that immediately.
    LDFLAGS=("-L$MKL_LIB" -lmkl_intel_lp64 -lmkl_sequential -lmkl_core
             "-L$HSTAR_IOMP_LIBDIR" -lpthread -lm -ldl
             "-Wl,--disable-new-dtags" "-Wl,-rpath,$MKL_LIB" "-Wl,-rpath,$HSTAR_IOMP_LIBDIR")
fi
# Dropping the OpenMP runtime leaves exactly two undefined references in the legacy tree
# (omp_get_max_threads, omp_get_thread_num, both Stiff.f90). tools/asan/omp_stub.c
# supplies them, for this profile only -- its header carries the measurements that force
# the whole arrangement.
# --disable-new-dtags emits RPATH instead of RUNPATH: RPATH also resolves the
# transitive Intel runtime libraries (libintlc, libimf) that MKL itself needs,
# so the binary runs without LD_LIBRARY_PATH.

# --- target: problem-types (M3-01) --------------------------------------------
# Deliberately placed BEFORE any solver source list, object list or link
# command. It reuses the profile FFLAGS and the runtime-path link flags defined
# above and then exits, so nothing below this block ever sees src/problem/*.
if [ "$TARGET" = problem-types ] || [ "$TARGET" = runtime ]; then
    # --src selects the legacy solver tree; these targets always build the
    # repository's own src/. Refuse rather than ignore it silently.
    if [ "$SRC_GIVEN" = 1 ]; then
        echo "build.sh: $TARGET does not accept --src: it always builds $ROOT/src" >&2
        echo "          (--src selects the legacy solver tree and applies to the solver target only)" >&2
        exit 2
    fi

    # Write guard, in the style of check_runs_root/check_inside in
    # tools/yl_probe.py. $OUT is erased a few lines below, so every refusal
    # below happens before anything is deleted. `realpath -m` resolves a path
    # that does not exist yet.
    PT_OUT_ABS="$(realpath -m "$OUT")"
    PT_ROOT_ABS="$(realpath -m "$ROOT")"
    # pt_covers A B: true when B is A or lies under A.
    pt_covers() { [ "$2" = "$1" ] || case "$2" in "$1"/*) return 0;; *) return 1;; esac; }
    pt_refuse() { echo "build.sh: $TARGET: --out $OUT $1: refusing to erase it" >&2; exit 2; }
    pt_covers "$PT_OUT_ABS" "$PT_ROOT_ABS" && pt_refuse "is the repository root $PT_ROOT_ABS, or contains it"
    for pt_p in "$PT_ROOT_ABS/build/release" "$PT_ROOT_ABS/build/debug" \
                "$PT_ROOT_ABS/build/strict" "$PT_ROOT_ABS/build/trace" \
                "$PT_ROOT_ABS/build/sanitize" "$PT_ROOT_ABS/cases" \
                "$PT_ROOT_ABS/legacy" "$PT_ROOT_ABS/src" "$PT_ROOT_ABS/tools" \
                "$PT_ROOT_ABS/docs" "$PT_ROOT_ABS/schemas"; do
        pt_covers "$pt_p" "$PT_OUT_ABS" && pt_refuse "is $pt_p, or lies inside it"
        pt_covers "$PT_OUT_ABS" "$pt_p" && pt_refuse "contains $pt_p"
    done
    if ! pt_covers "$PT_ROOT_ABS" "$PT_OUT_ABS" && [ "$ALLOW_EXTERNAL_OUT" != 1 ]; then
        echo "build.sh: $TARGET: --out $OUT lies outside the repository $PT_ROOT_ABS." >&2
        echo "          Pass --allow-external-out if that is intended; it is erased before the build." >&2
        exit 2
    fi

    # Compile order is the dependency chain: optional wrappers -> aggregate
    # types -> error accumulator -> default profile/capability table -> manifest
    # accumulator -> draft builder -> the four pipeline stages.
    PT_PROBLEM_SRCS=(src/problem/yl_problem_optional.f90
                     src/problem/yl_problem_types.f90
                     src/problem/yl_problem_deck_residue.f90
                     src/problem/yl_problem_runtime_scalars.f90
                     src/problem/yl_problem_existence.f90
                     src/problem/yl_problem_errors.f90
                     src/problem/yl_problem_profile.f90
                     src/problem/yl_problem_manifest.f90
                     src/problem/yl_problem_builder.f90
                     src/problem/yl_problem_pipeline.f90)
    if [ "$TARGET" = problem-types ]; then
        PT_SRCS=("${PT_PROBLEM_SRCS[@]}")
        # Each main is a PROGRAM: compiled on its own and linked into its own binary.
        PT_MAINS=(src/problem/yl_problem_selftest.f90
                  src/problem/yl_problem_pipeline_selftest.f90)
    else
        # target `runtime` (M3-03). The problem modules come first because
        # build_runtime consumes a finished ProblemState, its error accumulator and
        # its manifest; then the runtime types, the versioned execution contract, the
        # walkable build-rule table and build_runtime itself.
        #
        # yl_runtime_commit.f90 is deliberately ABSENT: it USEs the legacy modules, so
        # it belongs to the `runtime-bridge` target and to nothing else. Keeping it out
        # here is what makes this target buildable without the legacy tree, and it is
        # also the mechanical guarantee that no self-test in this binary can write a
        # legacy global.
        PT_SRCS=("${PT_PROBLEM_SRCS[@]}"
                 src/runtime/yl_runtime_types.f90
                 src/runtime/yl_runtime_contract.f90
                 src/runtime/yl_runtime_rules.f90
                 src/runtime/yl_runtime_build.f90)
        PT_MAINS=(src/runtime/yl_runtime_selftest.f90)
    fi
    for f in "${PT_SRCS[@]}" "${PT_MAINS[@]}"; do
        [ -f "$ROOT/$f" ] || {
            echo "build.sh: $TARGET: missing source $ROOT/$f" >&2
            echo "build.sh: this target needs, in this order:" >&2
            for g in "${PT_SRCS[@]}" "${PT_MAINS[@]}"; do
                [ -f "$ROOT/$g" ] && echo "            ok      $g" >&2 || echo "            MISSING $g" >&2
            done
            echo "build.sh: (M3-01 deliverables 2-4, the M3-02 pipeline modules and," >&2
            echo "build.sh:  for target runtime, the M3-03 runtime modules)." >&2
            exit 4
        }
    done
    # Only the runtime-path part of the solver link line is needed: the problem
    # types call no MKL. -L/-rpath on HSTAR_IOMP_LIBDIR together with
    # --disable-new-dtags is required, otherwise the binary cannot find
    # libintlc at run time.
    PT_LDFLAGS=("-L$HSTAR_IOMP_LIBDIR" -lpthread -lm -ldl
                "-Wl,--disable-new-dtags" "-Wl,-rpath,$HSTAR_IOMP_LIBDIR")
    # Repository-side code is held to a stricter diagnostic level than the
    # legacy tree; warnings are recorded in the manifest, they do not fail here.
    PT_FFLAGS=("${FFLAGS[@]}" -warn all -stand f18)

    rm -rf "$OUT"; mkdir -p "$OUT/obj"
    LOG="$OUT/build.log"; : > "$LOG"
    T0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    log() { echo "$*" | tee -a "$LOG"; }
    run() { log "\$ $*"; "$@" >>"$LOG" 2>&1; }
    # Compiler diagnostics land in $LOG, not on the terminal. Without this the
    # `set -e` abort on a failed compile leaves the caller with a bare exit 1
    # and no indication of which source did not build.
    pt_run() {
        local what="$1"; shift
        local rc diag
        set +e; run "$@"; rc=$?; set -e
        [ "$rc" -eq 0 ] && return 0
        # Read the log into a variable before appending to it, so the message
        # cannot be fed back into its own grep.
        diag="$(grep -E "error #|catastrophic|compilation aborted" "$LOG" | tail -20)"
        log "=== COMPILE FAILED ($TARGET/$PROFILE): $what (rc=$rc)"
        log "--- diagnostics (full log: $LOG):"
        printf '%s\n' "$diag" | tee -a "$LOG" >&2
        exit 7
    }

    log "=== HSTAR Evolution build: target=$TARGET profile=$PROFILE out=$OUT"
    log "FC: $HSTAR_FC ($("$HSTAR_FC" --version | head -1))"
    log "FFLAGS: ${PT_FFLAGS[*]}"
    log "note: no solver object is built here and no object here enters the solver."

    PT_OBJS=()
    for f in "${PT_SRCS[@]}"; do
        b="$(basename "$f")"; obj="$OUT/obj/${b%.*}.o"
        pt_run "compiling $f" "$HSTAR_FC" -c "${PT_FFLAGS[@]}" -module "$OUT/obj" -I "$OUT/obj" "$ROOT/$f" -o "$obj"
        PT_OBJS+=("$obj")
    done
    # One binary per PROGRAM: the two mains must not be linked together.
    PT_EXES=()
    for f in "${PT_MAINS[@]}"; do
        b="$(basename "$f")"; stem="${b%.*}"; obj="$OUT/obj/$stem.o"; exe="$OUT/$stem"
        pt_run "compiling $f" "$HSTAR_FC" -c "${PT_FFLAGS[@]}" -module "$OUT/obj" -I "$OUT/obj" "$ROOT/$f" -o "$obj"
        pt_run "linking $stem" "$HSTAR_FC" "${FFLAGS[@]}" "${PT_OBJS[@]}" "$obj" -o "$exe" "${PT_LDFLAGS[@]}"
        PT_EXES+=("$exe")
    done
    T1=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    PT_WARNINGS=$(grep -c -iE "warning #|remark #" "$LOG" || true)
    log "warnings/remarks in log: $PT_WARNINGS"

    # Sources are recorded in compile order, the mains last in the order they
    # are linked; the binaries follow, separated by the literal "--".
    PT_ENTRIES=()
    for f in "${PT_SRCS[@]}" "${PT_MAINS[@]}"; do PT_ENTRIES+=("$f|$ROOT/$f"); done
    python3 - "$OUT" "$PROFILE" "$ROOT" "$T0" "$T1" "$PT_WARNINGS" "$TARGET" \
        "${PT_FFLAGS[*]}" "${PT_LDFLAGS[*]}" "${PT_ENTRIES[@]}" -- "${PT_EXES[@]}" <<'PT_PY'
import hashlib, json, os, platform, re, subprocess, sys
out, profile, root, t0, t1, warnings, target, fflags, ldflags, *rest = sys.argv[1:]
sep = rest.index('--')
entries, exes = rest[:sep], rest[sep + 1:]
srcs = [e.split('|', 1) for e in entries]
def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for c in iter(lambda: f.read(1 << 20), b''): h.update(c)
    return h.hexdigest()
def ver(cmd):
    try: return subprocess.run([cmd, '--version'], capture_output=True, text=True).stdout.splitlines()[0]
    except Exception as e: return f'unavailable: {e}'
def build_id(p):
    txt = subprocess.run(['readelf', '-n', p], capture_output=True, text=True).stdout
    m = re.search(r'Build ID:\s*([0-9a-f]+)', txt)
    return m.group(1) if m else None
def ldd_deps(p):
    out_ = subprocess.run(['ldd', p], capture_output=True, text=True).stdout
    ds = []
    for line in out_.splitlines():
        m = re.match(r'\s*(\S+)\s*=>\s*(\S+)', line)
        if m and os.path.isfile(m.group(2)):
            ds.append({'soname': m.group(1), 'path': m.group(2), 'sha256': sha(m.group(2))})
        elif 'not found' in line:
            ds.append({'soname': line.split()[0], 'path': None, 'sha256': None})
    return ds
binaries = [{'path': e, 'bytes': os.path.getsize(e), 'sha256': sha(e),
             'gnu_build_id': build_id(e), 'runtime_dependencies': ldd_deps(e)}
            for e in exes]
unresolved = sorted({d['soname'] for b in binaries for d in b['runtime_dependencies']
                     if d['path'] is None})
env = {k: os.environ[k] for k in ('HSTAR_FC','HSTAR_MKLROOT','HSTAR_IOMP_LIBDIR','HSTAR_UNIT_PROFILE')}
manifest = {
    'manifest_version': 1,
    'target': target,
    'profile': profile,
    'started_at': t0, 'finished_at': t1,
    'solver_linkage': ('none: these objects are not linked into build/<profile>/hstar, '
                       'and these sources are absent from legacy/source-manifest.json '
                       'because they were never solver inputs'),
    'platform': {'os': platform.platform(), 'machine': platform.machine(), 'python': platform.python_version()},
    'toolchain': {**env, 'fc_version': ver(env['HSTAR_FC'])},
    'flags': {'fflags': fflags.split(), 'ldflags': ldflags.split()},
    'sources': {'dir': root, 'identity': 'repository:src',
                'files': [{'path': rel, 'sha256': sha(abs_)} for rel, abs_ in srcs]},
    'binaries': binaries,
    'warnings_or_remarks': int(warnings),
    'unresolved_runtime_deps': unresolved,
}
json.dump(manifest, open(os.path.join(out, target + '-manifest.json'), 'w'), indent=2)
if unresolved:
    print('build.sh: unresolved runtime dependencies:', unresolved, file=sys.stderr)
    sys.exit(5)
for b in binaries:
    print(f"binary {b['path']} sha256={b['sha256'][:16]} build-id={b['gnu_build_id']} "
          f"deps={len(b['runtime_dependencies'])} warnings={warnings}")
PT_PY

    # Every suite is run even if an earlier one fails, so one invocation reports
    # the state of both; the target fails if any of them failed.
    PT_FAILED=()
    for exe in "${PT_EXES[@]}"; do
        log "--- running self-test: $exe"
        # `set -euo pipefail` is in force: without suspending -e the failing
        # `$exe | tee` pipeline would abort the script here, before the result
        # is reported and before the remaining suites are run.
        set +e
        "$exe" 2>&1 | tee -a "$LOG"
        PT_RC=${PIPESTATUS[0]}
        set -e
        if [ "$PT_RC" -ne 0 ]; then
            log "--- SELF-TEST FAILED: $(basename "$exe") rc=$PT_RC"
            PT_FAILED+=("$(basename "$exe") (rc=$PT_RC)")
        else
            log "--- SELF-TEST PASSED: $(basename "$exe")"
        fi
    done
    if [ "${#PT_FAILED[@]}" -ne 0 ]; then
        log "=== SELF-TESTS FAILED ($TARGET/$PROFILE): ${PT_FAILED[*]}"
        exit 6
    fi

    # yl_problem_check's OWN self-test. It was never wired into any target, and on
    # 2026-09-09 a rule added to that checker (rule 15, closing M3 acceptance criterion 5)
    # took its self-test from 56/56 to 54/56 -- the synthetic fixtures legitimately omit
    # `determinism`, and the rule judged a missing key as a violation. Nothing reported it,
    # because `grep -c yl_problem_check tools/build.sh` was 0: a tool that guards the map
    # had a suite guarding the tool, and no gate ran it. Found by accept-m2m3 while
    # building the M4-01 acceptance matrix.
    log "--- self-test: tools/yl_problem_check.py"
    set +e
    python3 "$ROOT/tools/yl_problem_check.py" --selftest 2>&1 | tee -a "$LOG" | tail -1
    PT_CHECK_RC=${PIPESTATUS[0]}
    set -e
    if [ "$PT_CHECK_RC" -ne 0 ]; then
        log "=== yl_problem_check SELF-TEST FAILED ($TARGET/$PROFILE) rc=$PT_CHECK_RC"
        exit 6
    fi

    # The BACKWARD half of the rule-table bijection (M3-03). The self-test asserts the
    # forward and injective halves in Fortran and exports its table as RULES|/RULE|
    # lines; only Python can read docs/m2/state-field-map.toml and answer the other
    # direction -- "does every model_ready RuntimeState row have a producing rule?".
    #
    # It runs HERE, inside the target, rather than as a habit someone has to remember,
    # because the failure it catches is invisible from inside the binary: a build that
    # simply never produces a map row passes every in-binary assertion, and its own
    # export is self-consistent. Fail-closed, like every other gate in this file.
    if [ "$TARGET" = runtime ]; then
        log "--- cross-check: rule table vs docs/m2/state-field-map.toml (backward bijection)"
        set +e
        python3 "$ROOT/tools/yl_state_map.py" runtime-rules --export "$LOG" 2>&1 | tee -a "$LOG"
        PT_XRC=${PIPESTATUS[0]}
        set -e
        if [ "$PT_XRC" -ne 0 ]; then
            log "=== RULE-TABLE CROSS-CHECK FAILED ($TARGET/$PROFILE) rc=$PT_XRC"
            exit 6
        fi
    fi
    log "=== BUILD OK ($TARGET/$PROFILE) $T0 -> $T1: ${#PT_EXES[@]} self-test suites passed"
    exit 0
fi

# Repository-side Fortran compiled before the legacy tree (M1-02 diagnostics:
# registry generated by tools/yl_io_inventory.py gen-fortran, then yl_diag).
# Paths are relative to the repository root; recorded in the manifest as such.
DIAG_SRCS=(src/diagnostics/yl_diag_registry.f90 src/diagnostics/yl_diag.f90)

# Module dependency order (same as the original Windows project / build_linux.sh),
# with Fem.f90 (the main program) split out: it now uses yl_state_serializer, so
# the repository-side state observer must be compiled after the legacy modules
# it reads and before Fem.f90 (M2-02).
SRCS=(Vartype.f90 Array.f90 Elements.f90 gidpost.F90 vsl_gauss_module.f90
      Global.f90 Material.f90 meshfine.f90 Load.f90 Prescrib.f90 Solver.f90
      Output.f90 Temper.f90 Stiff.f90 Residu.f90 Level.f90)
MAIN_SRCS=(Fem.f90)

# --- the M4-02 adapter entry seam ---------------------------------------------
# Fem.f90 calls the external subroutine yl_adapter_override() before the
# model_ready anchor, guarded by --adapter=on. Exactly one implementation is
# linked, and which one is the whole difference between the two solver targets:
#
#   solver          -> src/adapter/yl_adapter_entry_stub.f90  (REFUSES, exit 3)
#   solver-adapter  -> src/adapter/yl_adapter_entry.f90       (adapts and commits)
#
# The stub exists so that `release` keeps its property of linking no adapter
# object file -- mechanically checkable with
#   grep -o "yl_adapter_[a-z_]*\.o" build/release/build.log
# which must print only yl_adapter_entry_stub.o. The stub refuses rather than
# returning quietly: a fallback switch whose "on" silently means "off" in some
# builds is worse than no switch (see the stub's own header).
ENTRY_SRCS=(src/adapter/yl_adapter_entry_stub.f90)
SOLVER_REPO_SRCS=()
if [ "$TARGET" = solver-adapter ]; then
    ENTRY_SRCS=(src/adapter/yl_adapter_entry.f90)
    SOLVER_REPO_SRCS=(src/problem/yl_problem_optional.f90
                      src/problem/yl_problem_types.f90
                      src/problem/yl_problem_deck_residue.f90
                      src/problem/yl_problem_runtime_scalars.f90
                      src/problem/yl_problem_existence.f90
                      src/problem/yl_problem_errors.f90
                      src/problem/yl_problem_profile.f90
                      src/problem/yl_problem_manifest.f90
                      src/problem/yl_problem_builder.f90
                      src/problem/yl_problem_pipeline.f90
                      src/runtime/yl_runtime_types.f90
                      src/runtime/yl_runtime_contract.f90
                      src/runtime/yl_runtime_rules.f90
                      src/runtime/yl_runtime_build.f90
                      src/runtime/yl_runtime_commit.f90
                      src/adapter/yl_adapter_parts.f90
                      src/adapter/yl_adapter_mesh.f90
                      src/adapter/yl_adapter_model.f90
                      src/adapter/yl_adapter_material.f90
                      src/adapter/yl_adapter_load.f90
                      src/adapter/yl_adapter_temper.f90
                      src/adapter/yl_adapter_fem90.f90
                      src/adapter/yl_adapter_harvest.f90
                      src/adapter/yl_adapter_driver.f90)
fi

# Repository-side state observer (M2-02). yl_state_dump.f90 is generated by
# tools/yl_state_map.py gen-fortran from docs/m2/state-field-map.toml.
# Paths are relative to the repository root; recorded in the manifest as such.
STATE_SRCS=(src/state/yl_state_io.f90 src/state/yl_state_adapters.f90
            src/state/yl_state_dump.f90)

# The generated file records the map's sha256 on its `! Source :` line. That line
# is the only claim that the observer matches the map it was generated from, and
# it drifted silently once already: commit cded7f4's own message said it had
# regenerated the dump so the line matched, and it had not (dump said 8ec26e625672,
# map was 5224c8aa06f7; found by the L2-c design review, 2026-09-09). The drift was
# cosmetic that time -- regenerating changed nothing but the line itself -- but
# "cosmetic this time" is not a property anyone can check by looking at the line.
# So the check is mechanical and fail-closed, not a convention.
state_dump_provenance_check() {
    local dump="$ROOT/src/state/yl_state_dump.f90"
    local map="$ROOT/docs/m2/state-field-map.toml"
    local claimed actual
    claimed=$(grep -m1 -oP '(?<=sha256 )[0-9a-f]+' "$dump" 2>/dev/null || true)
    actual=$(sha256sum "$map" | cut -c1-12)
    if [ -z "$claimed" ]; then
        echo "build.sh: $dump carries no '! Source : ... (sha256 ...)' line" >&2
        return 1
    fi
    if [ "$claimed" != "$actual" ]; then
        echo "build.sh: yl_state_dump.f90 was generated from a different map:" >&2
        echo "  the file claims sha256 $claimed, docs/m2/state-field-map.toml is $actual" >&2
        echo "  regenerate: python3 tools/yl_state_map.py gen-fortran -o src/state/yl_state_dump.f90" >&2
        return 1
    fi
    echo "  ok   yl_state_dump.f90 provenance matches the map (sha256 $actual)"
}

# --- target: runtime-bridge (M3-03) -------------------------------------------
# The ISOLATED bridge executable. It links the REAL legacy modules -- the same
# sources, in the same order, as the solver -- plus src/state (the M2 observers),
# src/problem, src/runtime AND src/runtime/yl_runtime_commit.f90, and its own
# PROGRAM instead of Fem.f90. It is the only target that compiles the commit
# module, because that module is the only repository file that USEs global_var.
#
# WHY IT IS A SEPARATE BINARY AND NOT A SOLVER PROFILE
#   Fem.f90 is excluded, so there is no solver main here and nothing can start a
#   run; and no object built here is ever an input to build/<profile>/hstar. The
#   solver binary therefore cannot drift, and the non-drift criterion is the same
#   one the problem-types target uses: GNU build-id equality (readelf -n), not a
#   whole-file hash.
#
#   This block sits AFTER the solver source lists because it reuses them verbatim
#   -- one list, so the bridge cannot link a different legacy tree than the solver
#   compiles -- and BEFORE the solver's own compile loop and link command, which it
#   never reaches because it exits. Nothing below it ever sees src/runtime/*.
#
# WHAT IT PROVES, AND WHAT IT DOES NOT
#   That commit_legacy_globals lands the runtime rows in the real globals with the
#   real types, and that the existing observers read them back. It does NOT prove
#   the solver is satisfied by them: no solver consumer runs in this binary. Any
#   conclusion drawn from it must be labelled PARTIAL.
if [ "$TARGET" = runtime-bridge ] || [ "$TARGET" = adapter ]; then
    RB_OUT_ABS="$(realpath -m "$OUT")"
    RB_ROOT_ABS="$(realpath -m "$ROOT")"
    rb_covers() { [ "$2" = "$1" ] || case "$2" in "$1"/*) return 0;; *) return 1;; esac; }
    rb_refuse() { echo "build.sh: runtime-bridge: --out $OUT $1: refusing to erase it" >&2; exit 2; }
    rb_covers "$RB_OUT_ABS" "$RB_ROOT_ABS" && rb_refuse "is the repository root $RB_ROOT_ABS, or contains it"
    for rb_p in "$RB_ROOT_ABS/build/release" "$RB_ROOT_ABS/build/debug" \
                "$RB_ROOT_ABS/build/strict" "$RB_ROOT_ABS/build/trace" \
                "$RB_ROOT_ABS/build/sanitize" "$RB_ROOT_ABS/cases" \
                "$RB_ROOT_ABS/legacy" "$RB_ROOT_ABS/src" "$RB_ROOT_ABS/tools" \
                "$RB_ROOT_ABS/docs" "$RB_ROOT_ABS/schemas"; do
        rb_covers "$rb_p" "$RB_OUT_ABS" && rb_refuse "is $rb_p, or lies inside it"
        rb_covers "$RB_OUT_ABS" "$rb_p" && rb_refuse "contains $rb_p"
    done
    if ! rb_covers "$RB_ROOT_ABS" "$RB_OUT_ABS" && [ "$ALLOW_EXTERNAL_OUT" != 1 ]; then
        echo "build.sh: runtime-bridge: --out $OUT lies outside the repository $RB_ROOT_ABS." >&2
        echo "          Pass --allow-external-out if that is intended; it is erased before the build." >&2
        exit 2
    fi

    # Repository-side sources, in dependency order. The problem and runtime modules
    # are compiled with the strict repository flags; the legacy tree keeps the
    # profile flags, exactly as in the solver build.
    RB_REPO_SRCS=(src/problem/yl_problem_optional.f90
                  src/problem/yl_problem_types.f90
                  src/problem/yl_problem_deck_residue.f90
                  src/problem/yl_problem_runtime_scalars.f90
                  src/problem/yl_problem_existence.f90
                  src/problem/yl_problem_errors.f90
                  src/problem/yl_problem_profile.f90
                  src/problem/yl_problem_manifest.f90
                  src/problem/yl_problem_builder.f90
                  src/problem/yl_problem_pipeline.f90
                  src/runtime/yl_runtime_types.f90
                  src/runtime/yl_runtime_contract.f90
                  src/runtime/yl_runtime_rules.f90
                  src/runtime/yl_runtime_build.f90
                  src/runtime/yl_runtime_commit.f90
                  # Global.f90 now calls the external yl_adapter_override() behind
                  # `if (yl_adapter_mode)`, so EVERY target that links the legacy tree
                  # needs one implementation of it. These test programs never set the
                  # flag, so they link the stub -- which refuses rather than returning,
                  # so a target that somehow did set it could not quietly run the old path.
                  src/adapter/yl_adapter_entry_stub.f90)
    RB_MAIN=src/runtime/yl_runtime_bridge_test.f90
    RB_EXTRA_RUN=()

    # --- target: adapter (M4-01) ----------------------------------------------
    # The same link surface as runtime-bridge plus the eight adapter modules, and
    # THREE programs instead of one. It exists because until it did, all three
    # adapter test programs were built by throwaway scratch scripts: a suite with
    # no build target is not a gate, however green it runs by hand.
    #   yl_adapter_bridge_test  L3-b -- adapter -> build_runtime -> commit, read
    #                           back from the real legacy globals, compared to
    #                           cases/golden/*/reference/state/model_ready
    #   yl_adapter_dialect_test L2-b -- 58 dialect counter-examples, one per row
    #   yl_adapter_shadow       L3-c -- the new-path child process; it is BUILT
    #                           here but not run here, because the differential is
    #                           driven by tools/yl_shadow_diff.py, which manages
    #                           two processes in two directories.
    if [ "$TARGET" = adapter ]; then
        RB_REPO_SRCS+=(src/adapter/yl_adapter_parts.f90
                       src/adapter/yl_adapter_mesh.f90
                       src/adapter/yl_adapter_model.f90
                       src/adapter/yl_adapter_material.f90
                       src/adapter/yl_adapter_load.f90
                       src/adapter/yl_adapter_temper.f90
                       src/adapter/yl_adapter_fem90.f90
                       src/adapter/yl_adapter_harvest.f90
                       src/adapter/yl_adapter_driver.f90)
        RB_MAIN=src/adapter/yl_adapter_bridge_test.f90
        RB_EXTRA_RUN=(src/adapter/yl_adapter_dialect_test.f90
                      src/adapter/yl_adapter_shadow.f90)
    fi

    if [ "$SRC" = "$ROOT/legacy/yl" ]; then
        python3 "$ROOT/tools/yl_manifest.py" check "$ROOT/legacy/source-manifest.json" >/dev/null \
            || { echo "build.sh: legacy/source-manifest.json does not verify; refusing to build" >&2; exit 4; }
        RB_SRC_IDENTITY="legacy/source-manifest.json"
    else
        RB_SRC_IDENTITY="external:$SRC"
    fi
    # The map is prose plus measurements; where its reason/note asserts a value the
    # frozen baseline can contradict it. Three such defects were found in M4-01 only
    # by tripping over them. --positive-control makes the checker prove it can still
    # find one before a clean result is believed.
    #
    # BEFORE the dump-provenance check on purpose: any map edit changes its sha256, so
    # running that first would shadow this one behind "regenerate the dump" whenever
    # the map is what is wrong. (Found by a control that blocked for the wrong reason.)
    python3 "$ROOT/tools/yl_map_selfcheck.py" --positive-control || exit 4
    state_dump_provenance_check || exit 4
    # M2-01 judgement 5: the anchor guard table (M2-01-checkpoints.md §1) is prose that
    # every anchor argument and every dead-code claim rests on, and nothing compared it
    # to a measurement until one row (stab_matde) was found wrong by hand during M4-01.
    # yl_guard_check.py compares it to the frozen baseline, and prints by name every
    # guard it CANNOT confirm -- silence there reads exactly like confirmation, which
    # is how the wrong row survived.
    python3 "$ROOT/tools/yl_guard_check.py" >/dev/null || {
        python3 "$ROOT/tools/yl_guard_check.py" >&2; exit 4; }
    # ADR-0009: the existence face. The map answers "what do we compare"; existence-face.toml
    # answers "what must exist". Its gates are set equalities in both directions between the
    # table, deck_existence_t, commit's existence pass and commit_release -- the comparison
    # face's bijection is untouched, this is a second one of the same shape.
    python3 "$ROOT/tools/yl_runtime_manifest_check.py" >/dev/null || {
        python3 "$ROOT/tools/yl_runtime_manifest_check.py" >&2; exit 4; }
    for f in "${DIAG_SRCS[@]}" "${STATE_SRCS[@]}" "${RB_REPO_SRCS[@]}" "$RB_MAIN" "${RB_EXTRA_RUN[@]}"; do
        [ -f "$ROOT/$f" ] || {
            echo "build.sh: runtime-bridge: missing source $ROOT/$f" >&2
            echo "build.sh: this target needs, in this order:" >&2
            for g in "${DIAG_SRCS[@]}" "${STATE_SRCS[@]}" "${RB_REPO_SRCS[@]}" "$RB_MAIN" "${RB_EXTRA_RUN[@]}"; do
                [ -f "$ROOT/$g" ] && echo "            ok      $g" >&2 || echo "            MISSING $g" >&2
            done
            echo "build.sh: (the M3-03 commit module and its isolated bridge program)." >&2
            exit 4
        }
    done
    for f in "${SRCS[@]}"; do [ -f "$SRC/$f" ] || { echo "build.sh: missing legacy source $SRC/$f" >&2; exit 4; }; done
    [ -f "$STUB" ] || { echo "build.sh: missing $STUB" >&2; exit 4; }

    rm -rf "$OUT"; mkdir -p "$OUT/obj"
    LOG="$OUT/build.log"; : > "$LOG"
    T0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    log() { echo "$*" | tee -a "$LOG"; }
    run() { log "\$ $*"; "$@" >>"$LOG" 2>&1; }
    rb_run() {
        local what="$1"; shift
        local rc diag
        set +e; run "$@"; rc=$?; set -e
        [ "$rc" -eq 0 ] && return 0
        diag="$(grep -E "error #|catastrophic|compilation aborted|undefined reference" "$LOG" | tail -20)"
        log "=== COMPILE FAILED (runtime-bridge/$PROFILE): $what (rc=$rc)"
        log "--- diagnostics (full log: $LOG):"
        printf '%s\n' "$diag" | tee -a "$LOG" >&2
        exit 7
    }

    RB_FFLAGS=("${FFLAGS[@]}" -warn all -stand f18)

    log "=== HSTAR Evolution build: target=runtime-bridge profile=$PROFILE src=$SRC out=$OUT"
    log "FC: $HSTAR_FC ($("$HSTAR_FC" --version | head -1))"
    log "note: Fem.f90 is NOT compiled here and no object here enters the solver binary."

    rb_run "compiling the gidpost stub" "$HSTAR_CC" -c "$STUB" -o "$OUT/obj/gidpost_stub.o"
    RB_OBJS=("$OUT/obj/gidpost_stub.o")
    if [ "$PROFILE" = asan ]; then
        rb_run "compiling the OpenMP stub (asan only)" "$HSTAR_CC" -c "$OMP_STUB" -o "$OUT/obj/omp_stub.o"
        RB_OBJS+=("$OUT/obj/omp_stub.o")
    fi
    for f in "${DIAG_SRCS[@]}"; do
        b="$(basename "$f")"; obj="$OUT/obj/${b%.*}.o"
        rb_run "compiling $f" "$HSTAR_FC" -c "${FFLAGS[@]}" -module "$OUT/obj" -I "$OUT/obj" "$ROOT/$f" -o "$obj"
        RB_OBJS+=("$obj")
    done
    for f in "${SRCS[@]}"; do
        obj="$OUT/obj/${f%.*}.o"
        rb_run "compiling $f" "$HSTAR_FC" -c "${FFLAGS[@]}" -module "$OUT/obj" -I "$OUT/obj" -I "$MKL_INC" "$SRC/$f" -o "$obj"
        RB_OBJS+=("$obj")
    done
    for f in "${STATE_SRCS[@]}" "${RB_REPO_SRCS[@]}"; do
        b="$(basename "$f")"; obj="$OUT/obj/${b%.*}.o"
        rb_run "compiling $f" "$HSTAR_FC" -c "${RB_FFLAGS[@]}" -module "$OUT/obj" -I "$OUT/obj" -I "$MKL_INC" "$ROOT/$f" -o "$obj"
        RB_OBJS+=("$obj")
    done
    b="$(basename "$RB_MAIN")"; RB_STEM="${b%.*}"
    rb_run "compiling $RB_MAIN" "$HSTAR_FC" -c "${RB_FFLAGS[@]}" -module "$OUT/obj" -I "$OUT/obj" -I "$MKL_INC" "$ROOT/$RB_MAIN" -o "$OUT/obj/$RB_STEM.o"
    RB_EXE="$OUT/$RB_STEM"
    rb_run "linking $RB_STEM" "$HSTAR_FC" "${FFLAGS[@]}" "${RB_OBJS[@]}" "$OUT/obj/$RB_STEM.o" -o "$RB_EXE" "${LDFLAGS[@]}"
    RB_EXTRA_EXES=()
    for f in "${RB_EXTRA_RUN[@]}"; do
        b="$(basename "$f")"; st="${b%.*}"
        rb_run "compiling $f" "$HSTAR_FC" -c "${RB_FFLAGS[@]}" -module "$OUT/obj" -I "$OUT/obj" -I "$MKL_INC" "$ROOT/$f" -o "$OUT/obj/$st.o"
        rb_run "linking $st" "$HSTAR_FC" "${FFLAGS[@]}" "${RB_OBJS[@]}" "$OUT/obj/$st.o" -o "$OUT/$st" "${LDFLAGS[@]}"
        RB_EXTRA_EXES+=("$OUT/$st")
    done
    T1=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    RB_WARNINGS=$(grep -c -iE "warning #|remark #" "$LOG" || true)
    log "warnings/remarks in log: $RB_WARNINGS"

    RB_ENTRIES=()
    for f in "${DIAG_SRCS[@]}"; do RB_ENTRIES+=("$f|$ROOT/$f"); done
    for f in "${SRCS[@]}"; do RB_ENTRIES+=("$f|$SRC/$f"); done
    for f in "${STATE_SRCS[@]}" "${RB_REPO_SRCS[@]}" "$RB_MAIN" "${RB_EXTRA_RUN[@]}"; do RB_ENTRIES+=("$f|$ROOT/$f"); done
    python3 - "$OUT" "$PROFILE" "$ROOT" "$T0" "$T1" "$RB_WARNINGS" "$TARGET" \
        "${RB_FFLAGS[*]}" "${LDFLAGS[*]}" "$RB_SRC_IDENTITY" "${RB_ENTRIES[@]}" -- "$RB_EXE" "${RB_EXTRA_EXES[@]}" <<'RB_PY'
import hashlib, json, os, platform, re, subprocess, sys
out, profile, root, t0, t1, warnings, target, fflags, ldflags, identity, *rest = sys.argv[1:]
sep = rest.index('--')
entries, exes = rest[:sep], rest[sep + 1:]
srcs = [e.split('|', 1) for e in entries]
def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for c in iter(lambda: f.read(1 << 20), b''): h.update(c)
    return h.hexdigest()
def ver(cmd):
    try: return subprocess.run([cmd, '--version'], capture_output=True, text=True).stdout.splitlines()[0]
    except Exception as e: return f'unavailable: {e}'
def build_id(p):
    txt = subprocess.run(['readelf', '-n', p], capture_output=True, text=True).stdout
    m = re.search(r'Build ID:\s*([0-9a-f]+)', txt)
    return m.group(1) if m else None
def ldd_deps(p):
    out_ = subprocess.run(['ldd', p], capture_output=True, text=True).stdout
    ds = []
    for line in out_.splitlines():
        m = re.match(r'\s*(\S+)\s*=>\s*(\S+)', line)
        if m and os.path.isfile(m.group(2)):
            ds.append({'soname': m.group(1), 'path': m.group(2), 'sha256': sha(m.group(2))})
        elif 'not found' in line:
            ds.append({'soname': line.split()[0], 'path': None, 'sha256': None})
    return ds
binaries = [{'path': e, 'bytes': os.path.getsize(e), 'sha256': sha(e),
             'gnu_build_id': build_id(e), 'runtime_dependencies': ldd_deps(e)}
            for e in exes]
unresolved = sorted({d['soname'] for b in binaries for d in b['runtime_dependencies']
                     if d['path'] is None})
env = {k: os.environ[k] for k in ('HSTAR_FC','HSTAR_CC','HSTAR_MKLROOT','HSTAR_IOMP_LIBDIR','HSTAR_UNIT_PROFILE')}
manifest = {
    'manifest_version': 1,
    'target': target,
    'profile': profile,
    'started_at': t0, 'finished_at': t1,
    'solver_linkage': ('none: Fem.f90 is not compiled here and no object built here is an '
                       'input to build/<profile>/hstar'),
    'proves': ('commit_legacy_globals writes the model_ready RuntimeState rows into the real '
               'legacy globals and the M2 observers read them back; PARTIAL -- no solver '
               'consumer runs in this binary'),
    'platform': {'os': platform.platform(), 'machine': platform.machine(), 'python': platform.python_version()},
    'toolchain': {**env, 'fc_version': ver(env['HSTAR_FC']), 'cc_version': ver(env['HSTAR_CC'])},
    'flags': {'fflags': fflags.split(), 'ldflags': ldflags.split()},
    'sources': {'dir': root, 'identity': identity,
                'files': [{'path': rel, 'sha256': sha(abs_)} for rel, abs_ in srcs]},
    'binaries': binaries,
    'warnings_or_remarks': int(warnings),
    'unresolved_runtime_deps': unresolved,
}
json.dump(manifest, open(os.path.join(out, target + '-manifest.json'), 'w'), indent=2)
if unresolved:
    print('build.sh: unresolved runtime dependencies:', unresolved, file=sys.stderr)
    sys.exit(5)
for b in binaries:
    print(f"binary {b['path']} sha256={b['sha256'][:16]} build-id={b['gnu_build_id']} "
          f"deps={len(b['runtime_dependencies'])} warnings={warnings}")
RB_PY

    # See the `sanitize` note in the header: libiomp's topology walk is
    # uninstrumented and reports a false positive before main. Disabling the walk
    # is the smallest thing that lets MSan reach our code; it silences nothing we
    # own.
    RB_RUN_ENV=()
    if [ "$PROFILE" = sanitize ]; then
        RB_RUN_ENV=(env KMP_AFFINITY=disabled)
        log "--- sanitize: running with KMP_AFFINITY=disabled (uninstrumented libiomp false positive)"
    fi

    log "--- running the bridge suite: $RB_EXE"
    set +e
    "${RB_RUN_ENV[@]}" "$RB_EXE" 2>&1 | tee -a "$LOG"
    RB_RC=${PIPESTATUS[0]}
    set -e
    if [ "$RB_RC" -ne 0 ]; then
        log "=== BRIDGE SUITE FAILED ($TARGET/$PROFILE) rc=$RB_RC"
        exit 6
    fi

    # The BACKWARD half of the commit provenance ledger (M4-01 step 1). The bridge test
    # exports yl_runtime_commit's table as PROVS|/PROV| lines and asserts the half Fortran
    # can see (well-formed, injective, every state nameable); only Python can read
    # docs/m2/state-field-map.toml and answer the other direction -- "does every row a
    # model_ready snapshot carries have a recorded source?".
    #
    # It runs HERE, inside the target, for the same reason the rule-table cross-check does:
    # the failure it catches is invisible from inside the binary. A map row that no ledger
    # entry names still passes every in-binary assertion, and the export is self-consistent
    # whether or not it is complete. This is also where the fold's remaining debt gets
    # counted out loud -- the NOT_MIGRATED tally is printed on every build.
    #
    # Only for `runtime-bridge`: the PROV| export is printed by yl_runtime_bridge_test,
    # and the `adapter` target's main program is yl_adapter_bridge_test, which does not
    # print it. Running the check there would fail on a missing export rather than on a
    # missing entry -- a gate that fires for the wrong reason, which is worse than no gate
    # because the next person learns to ignore it. (Caught by running the target: the
    # first version of this hook was unconditional and broke `adapter`.)
    if [ "$TARGET" = runtime-bridge ]; then
        # Every ProblemState leaf the commit staging reads must be checked by
        # verify_problem_inputs. Source-level and map-independent, but run here because
        # this is the target that compiles the commit module. The defect it prevents is
        # the one found at M4-01 step 3b: a staging read whose input was never authored
        # is published as a default, and neither the staging poison (overwritten by the
        # fallback) nor the ledger (which records origin, not presence) can see it.
        log "--- cross-check: commit staging reads vs verify_problem_inputs"
        set +e
        python3 "$ROOT/tools/yl_state_map.py" commit-inputs 2>&1 | tee -a "$LOG"
        RB_IRC=${PIPESTATUS[0]}
        set -e
        if [ "$RB_IRC" -ne 0 ]; then
            log "=== COMMIT-INPUTS CROSS-CHECK FAILED ($TARGET/$PROFILE) rc=$RB_IRC"
            exit 6
        fi

        log "--- cross-check: commit provenance vs docs/m2/state-field-map.toml (backward bijection)"
        set +e
        python3 "$ROOT/tools/yl_state_map.py" commit-provenance --export "$LOG" 2>&1 | tee -a "$LOG"
        RB_XRC=${PIPESTATUS[0]}
        set -e
        if [ "$RB_XRC" -ne 0 ]; then
            log "=== COMMIT-PROVENANCE CROSS-CHECK FAILED ($TARGET/$PROFILE) rc=$RB_XRC"
            exit 6
        fi
    fi

    if [ "$TARGET" = adapter ]; then
        # The dialect suite takes a deck directory and a scratch directory; it is run
        # on BOTH golden decks because a counter-example that only fires on one deck
        # is evidence about that deck, not about the rule. The scratch directory is
        # under $OUT so nothing is written next to the golden inputs.
        DT="$OUT/yl_adapter_dialect_test"
        DT_SCRATCH="$OUT/dialect-scratch"
        mkdir -p "$DT_SCRATCH"
        for c in cooks_membrane lame_cylinder; do
            log "--- running the dialect suite on $c"
            set +e
            "${RB_RUN_ENV[@]}" "$DT" "$ROOT/cases/golden/static_2d/$c/legacy" "$DT_SCRATCH" 2>&1 | tee -a "$LOG"
            DT_RC=${PIPESTATUS[0]}
            set -e
            if [ "$DT_RC" -ne 0 ]; then
                log "=== DIALECT SUITE FAILED ($c) rc=$DT_RC"
                exit 6
            fi
        done
        rm -rf "$DT_SCRATCH"
        # yl_adapter_shadow is built, not run: the L3-c differential needs two child
        # processes in two directories and is driven by tools/yl_shadow_diff.py.
        log "--- yl_adapter_shadow built (not run here; see tools/yl_shadow_diff.py)"
        # Nothing this target does may write into the golden inputs.
        if [ -n "$(git -C "$ROOT" status --porcelain cases/ 2>/dev/null)" ]; then
            log "=== FAILED: this target modified cases/; that is never allowed"
            git -C "$ROOT" status --porcelain cases/ | tee -a "$LOG"
            exit 6
        fi
        log "=== BUILD OK (adapter/$PROFILE) $T0 -> $T1: bridge + dialect suites passed on both golden decks"
        exit 0
    fi

    log "=== BUILD OK (runtime-bridge/$PROFILE) $T0 -> $T1: bridge suite passed (PARTIAL evidence)"
    exit 0
fi

# --- source integrity ---------------------------------------------------------
if [ "$SRC" = "$ROOT/legacy/yl" ]; then
    python3 "$ROOT/tools/yl_manifest.py" check "$ROOT/legacy/source-manifest.json" >/dev/null \
        || { echo "build.sh: legacy/source-manifest.json does not verify; refusing to build" >&2; exit 4; }
    SRC_IDENTITY="legacy/source-manifest.json"
else
    SRC_IDENTITY="external:$SRC"
fi
for f in "${DIAG_SRCS[@]}" "${STATE_SRCS[@]}"; do [ -f "$ROOT/$f" ] || { echo "build.sh: missing source $ROOT/$f" >&2; exit 4; }; done
# The map is prose plus measurements; where its reason/note asserts a value the
# frozen baseline can contradict it. Three such defects were found in M4-01 only
# by tripping over them. --positive-control makes the checker prove it can still
# find one before a clean result is believed.
#
# BEFORE the dump-provenance check on purpose: any map edit changes its sha256, so
# running that first would shadow this one behind "regenerate the dump" whenever
# the map is what is wrong. (Found by a control that blocked for the wrong reason.)
python3 "$ROOT/tools/yl_map_selfcheck.py" --positive-control || exit 4
state_dump_provenance_check || exit 4
# M2-01 judgement 5: the anchor guard table (M2-01-checkpoints.md §1) is prose that
# every anchor argument and every dead-code claim rests on, and nothing compared it
# to a measurement until one row (stab_matde) was found wrong by hand during M4-01.
# yl_guard_check.py compares it to the frozen baseline, and prints by name every
# guard it CANNOT confirm -- silence there reads exactly like confirmation, which
# is how the wrong row survived.
python3 "$ROOT/tools/yl_guard_check.py" >/dev/null || {
    python3 "$ROOT/tools/yl_guard_check.py" >&2; exit 4; }
# ADR-0009: the existence face. The map answers "what do we compare"; existence-face.toml
# answers "what must exist". Its gates are set equalities in both directions between the
# table, deck_existence_t, commit's existence pass and commit_release -- the comparison
# face's bijection is untouched, this is a second one of the same shape.
python3 "$ROOT/tools/yl_runtime_manifest_check.py" >/dev/null || {
    python3 "$ROOT/tools/yl_runtime_manifest_check.py" >&2; exit 4; }
for f in "${SOLVER_REPO_SRCS[@]}" "${ENTRY_SRCS[@]}"; do [ -f "$ROOT/$f" ] || { echo "build.sh: missing source $ROOT/$f" >&2; exit 4; }; done
for f in "${SRCS[@]}" "${MAIN_SRCS[@]}"; do [ -f "$SRC/$f" ] || { echo "build.sh: missing source $SRC/$f" >&2; exit 4; }; done
[ -f "$STUB" ] || { echo "build.sh: missing $STUB" >&2; exit 4; }

rm -rf "$OUT"; mkdir -p "$OUT/obj"
LOG="$OUT/build.log"; : > "$LOG"
T0=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log() { echo "$*" | tee -a "$LOG"; }
run() { log "\$ $*"; "$@" >>"$LOG" 2>&1; }

log "=== HSTAR Evolution build: profile=$PROFILE src=$SRC out=$OUT"
log "FC: $HSTAR_FC ($("$HSTAR_FC" --version | head -1))"
log "CC: $HSTAR_CC ($("$HSTAR_CC" --version | head -1))"
log "MKLROOT: $HSTAR_MKLROOT   IOMP: $HSTAR_IOMP_LIBDIR"
log "FFLAGS: ${FFLAGS[*]}"

run "$HSTAR_CC" -c "$STUB" -o "$OUT/obj/gidpost_stub.o"
OBJS=("$OUT/obj/gidpost_stub.o")
for f in "${DIAG_SRCS[@]}"; do
    b="$(basename "$f")"; obj="$OUT/obj/${b%.*}.o"
    run "$HSTAR_FC" -c "${FFLAGS[@]}" -module "$OUT/obj" -I "$OUT/obj" "$ROOT/$f" -o "$obj"
    OBJS+=("$obj")
done
for f in "${SRCS[@]}"; do
    obj="$OUT/obj/${f%.*}.o"
    run "$HSTAR_FC" -c "${FFLAGS[@]}" -module "$OUT/obj" -I "$OUT/obj" -I "$MKL_INC" "$SRC/$f" -o "$obj"
    OBJS+=("$obj")
done
for f in "${SOLVER_REPO_SRCS[@]}" "${STATE_SRCS[@]}" "${ENTRY_SRCS[@]}"; do
    b="$(basename "$f")"; obj="$OUT/obj/${b%.*}.o"
    run "$HSTAR_FC" -c "${FFLAGS[@]}" -module "$OUT/obj" -I "$OUT/obj" -I "$MKL_INC" "$ROOT/$f" -o "$obj"
    OBJS+=("$obj")
done
for f in "${MAIN_SRCS[@]}"; do
    obj="$OUT/obj/${f%.*}.o"
    run "$HSTAR_FC" -c "${FFLAGS[@]}" -module "$OUT/obj" -I "$OUT/obj" -I "$MKL_INC" "$SRC/$f" -o "$obj"
    OBJS+=("$obj")
done
run "$HSTAR_FC" "${FFLAGS[@]}" "${OBJS[@]}" -o "$OUT/hstar" "${LDFLAGS[@]}"
T1=$(date -u +%Y-%m-%dT%H:%M:%SZ)

WARNINGS=$(grep -c -iE "warning #|remark #" "$LOG" || true)
log "warnings/remarks in log: $WARNINGS"

# --- manifest -----------------------------------------------------------------
# sources.files lists every compiled Fortran file in compile order as "<recorded
# path>|<absolute path>": repository files (DIAG_SRCS, STATE_SRCS) by their
# repo-relative path, legacy files by their name inside --src.
SRC_ENTRIES=()
for f in "${DIAG_SRCS[@]}"; do SRC_ENTRIES+=("$f|$ROOT/$f"); done
for f in "${SRCS[@]}"; do SRC_ENTRIES+=("$f|$SRC/$f"); done
for f in "${STATE_SRCS[@]}"; do SRC_ENTRIES+=("$f|$ROOT/$f"); done
for f in "${MAIN_SRCS[@]}"; do SRC_ENTRIES+=("$f|$SRC/$f"); done
python3 - "$OUT" "$PROFILE" "$SRC" "$SRC_IDENTITY" "$T0" "$T1" "$WARNINGS" \
    "${FFLAGS[*]}" "${LDFLAGS[*]}" "${SRC_ENTRIES[@]}" <<'PY'
import hashlib, json, os, platform, re, subprocess, sys
out, profile, src, src_identity, t0, t1, warnings, fflags, ldflags, *entries = sys.argv[1:]
srcs = [e.split('|', 1) for e in entries]
def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for c in iter(lambda: f.read(1 << 20), b''): h.update(c)
    return h.hexdigest()
def ver(cmd):
    try: return subprocess.run([cmd, '--version'], capture_output=True, text=True).stdout.splitlines()[0]
    except Exception as e: return f'unavailable: {e}'
exe = os.path.join(out, 'hstar')
ldd = subprocess.run(['ldd', exe], capture_output=True, text=True).stdout
deps = []
for line in ldd.splitlines():
    m = re.match(r'\s*(\S+)\s*=>\s*(\S+)', line)
    if m and os.path.isfile(m.group(2)):
        deps.append({'soname': m.group(1), 'path': m.group(2), 'sha256': sha(m.group(2))})
    elif 'not found' in line:
        deps.append({'soname': line.split()[0], 'path': None, 'sha256': None})
env = {k: os.environ[k] for k in ('HSTAR_FC','HSTAR_CC','HSTAR_MKLROOT','HSTAR_IOMP_LIBDIR','HSTAR_UNIT_PROFILE')}
manifest = {
    'manifest_version': 1,
    'profile': profile,
    'started_at': t0, 'finished_at': t1,
    'platform': {'os': platform.platform(), 'machine': platform.machine(), 'python': platform.python_version()},
    'toolchain': {**env, 'fc_version': ver(env['HSTAR_FC']), 'cc_version': ver(env['HSTAR_CC'])},
    'flags': {'fflags': fflags.split(), 'ldflags': ldflags.split()},
    'sources': {'dir': src, 'identity': src_identity,
                'files': [{'path': rel, 'sha256': sha(abs_)} for rel, abs_ in srcs]},
    'gidpost': 'stub (link-only, no GiD binary output)',
    'binary': {'path': exe, 'bytes': os.path.getsize(exe), 'sha256': sha(exe)},
    'runtime_dependencies': deps,
    'warnings_or_remarks': int(warnings),
    'unresolved_runtime_deps': [d['soname'] for d in deps if d['path'] is None],
}
json.dump(manifest, open(os.path.join(out, 'build-manifest.json'), 'w'), indent=2)
if manifest['unresolved_runtime_deps']:
    print('build.sh: unresolved runtime dependencies:', manifest['unresolved_runtime_deps'], file=sys.stderr)
    sys.exit(5)
print(f"binary {exe} sha256={manifest['binary']['sha256'][:16]}… deps={len(deps)} warnings={warnings}")
PY
log "=== BUILD OK ($PROFILE) $T0 → $T1"

# M2-01 judgement 4: the cross-routine half of the anchor argument ("no model-level
# reader runs after the anchor in some other routine") was carried by a hand-written
# call-order table; yl_io_inventory check only ever scanned within the anchor's own
# routine. The trace binary is the only build that can settle it, so the check runs
# here, where that binary has just been produced.
if [ "$PROFILE" = "trace" ] && [ "${HSTAR_SKIP_ANCHOR_ORDER:-0}" != "1" ]; then
    log "=== anchor order (M2-01 judgement 4)"
    python3 "$ROOT/tools/yl_anchor_order.py" check --binary "$OUT/hstar" 2>&1 | tee -a "$LOG"
    [ "${PIPESTATUS[0]}" -eq 0 ] || { echo "build.sh: anchor-order check failed" >&2; exit 6; }
fi
