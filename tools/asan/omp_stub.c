/*
 * omp_stub.c - the two OpenMP entry points the legacy tree calls, supplied for the
 *              `asan` build profile ONLY.
 *
 * WHY IT LIVES IN tools/ AND NOT legacy/stubs/
 *
 *   legacy/stubs/ is inside the frozen tree that legacy/source-manifest.json verifies --
 *   `stubs/gidpost_stub.c` is one of its 39 entries. Putting this file there made
 *   `tools/build.sh` refuse to build at all ("source-manifest.json does not verify"),
 *   which is the manifest doing precisely its job: this is a repository-owned build
 *   artefact for one profile, not legacy source, and the frozen tree must not gain files
 *   because a test profile found them convenient.
 *
 * WHY IT EXISTS AT ALL
 *
 *   M4-01 step 6's exit condition is that a deliberately reintroduced leak MUST be
 *   reported. valgrind is not installed on this machine and cannot be (no root), so the
 *   instrument is AddressSanitizer's LeakSanitizer. It works -- and the Intel OpenMP
 *   runtime switches it off, silently.
 *
 *   Measured, on one deliberate leak (a pointer array allocated in a procedure and
 *   nullified, so the block is unreachable at exit):
 *
 *     linked plainly ............................. LeakSanitizer REPORTS it
 *     linked with MKL, no OpenMP ................. LeakSanitizer REPORTS it
 *     linked with -qopenmp ....................... silent
 *     linked with -liomp5, no -qopenmp ........... silent
 *     linked with -liomp5 + an explicit
 *       __lsan_do_leak_check() before exit ....... silent
 *
 *   So it is the OpenMP RUNTIME LIBRARY, not the compile flag and not teardown ordering;
 *   ASAN_OPTIONS=detect_leaks=1 does not override it. ASan itself stays fully active,
 *   which is what makes this dangerous: the binary looks instrumented, runs the whole
 *   suite, and reports clean while detecting no leak at all. The first positive control
 *   of step 6 was run against exactly that configuration and found nothing -- which is
 *   the only reason this was discovered rather than written up as "no leaks found".
 *
 * WHY ONLY TWO SYMBOLS
 *
 *   Dropping the OpenMP runtime leaves exactly two undefined references across the whole
 *   legacy link surface: `omp_get_max_threads` and `omp_get_thread_num`, both from
 *   Stiff.f90 (:3549 and :3560). Nothing else in the tree calls the OpenMP API.
 *
 * WHAT THESE VALUES MEAN, AND WHAT THEY COST
 *
 *   1 thread, thread 0 -- the honest answer for a binary with no OpenMP runtime. The
 *   programs built with this profile run no solver numerics: they exercise
 *   commit -> release -> commit and read the globals back, so these call sites are linked
 *   and never executed.
 *
 *   That is a claim, and it is checked rather than assumed: the suite's result under this
 *   profile must equal its result under every other profile. A stub that changed
 *   behaviour would have to change it somewhere, and the suite compares every committed
 *   global against its source.
 *
 *   A leak that only appears under real multithreading would be invisible here. Nothing
 *   in commit_legacy_globals is threaded, so there is no such leak to miss today; if that
 *   changes, this profile stops being sufficient.
 *
 * NEVER IN THE SOLVER BUILD
 *
 *   tools/build.sh links this file under `--profile asan` and nowhere else. The solver
 *   and every other profile keep the real Intel OpenMP runtime.
 */

int omp_get_max_threads(void)
{
    return 1;
}

int omp_get_thread_num(void)
{
    return 0;
}
