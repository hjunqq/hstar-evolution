#!/usr/bin/env bash
# HSTAR Evolution — pinned toolchain environment (M0-02).
#
# Source this file; it does NOT rely on Intel's setvars.sh or on anything in
# the caller's PATH. Every external dependency is an absolute path that the
# build manifest records together with its version and hash.
#
#   source tools/env.sh
#
# Override any HSTAR_* variable before sourcing to point at a different
# installation; build.sh will record whatever was actually used.

: "${HSTAR_FC:=/opt/intel/oneapi/compiler/2025.3/bin/ifx}"
: "${HSTAR_CC:=/usr/bin/gcc}"
: "${HSTAR_MKLROOT:=/opt/intel/oneapi/mkl/2026.1}"
# libiomp5.so ships with the compiler, not with MKL.
: "${HSTAR_IOMP_LIBDIR:=/opt/intel/oneapi/compiler/2025.3/lib}"
: "${HSTAR_UNIT_PROFILE:=SI-v1}"

export HSTAR_FC HSTAR_CC HSTAR_MKLROOT HSTAR_IOMP_LIBDIR HSTAR_UNIT_PROFILE

hstar_env_check() {
    local ok=0
    for v in HSTAR_FC HSTAR_CC; do
        if [ ! -x "${!v}" ]; then echo "env.sh: $v not executable: ${!v}" >&2; ok=1; fi
    done
    for f in "$HSTAR_MKLROOT/include/mkl_rci.f90" "$HSTAR_MKLROOT/include/mkl_vsl.f90" \
             "$HSTAR_MKLROOT/lib/libmkl_intel_lp64.so" "$HSTAR_MKLROOT/lib/libmkl_intel_thread.so" \
             "$HSTAR_MKLROOT/lib/libmkl_core.so" "$HSTAR_IOMP_LIBDIR/libiomp5.so"; do
        if [ ! -f "$f" ]; then echo "env.sh: missing dependency: $f" >&2; ok=1; fi
    done
    return $ok
}

# Binaries built by build.sh carry an RPATH to the pinned MKL/compiler libs.
# An inherited LD_LIBRARY_PATH (e.g. from setvars.sh of another oneAPI version)
# would silently override that pin, so it is cleared here.
unset LD_LIBRARY_PATH

# Deterministic single-thread execution is the M0 reference configuration.
export OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}"
export MKL_NUM_THREADS="${MKL_NUM_THREADS:-1}"
export MKL_DYNAMIC=FALSE
