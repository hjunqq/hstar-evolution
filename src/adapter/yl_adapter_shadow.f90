! yl_adapter_shadow -- M4-01 L3-c: the NEW-path child process of the shadow differential.
!
! WHAT THIS PROGRAM IS
!   One half of the L3-c shadow harness (.ccg/tasks/m4-01-legacy-adapter/plan.md,
!   "L3-c 影子进程夹具 -- 独立子进程 + 独立目录，复用 yl_state_diff / yl_state_probe").
!   The OTHER half is the unmodified legacy solver `build/<profile>/hstar`, run by
!   tools/yl_run.py in its own isolated directory. This program is deliberately shaped so
!   that the two halves are interchangeable from the harness's point of view:
!
!     * it runs with cwd = its own working directory, whose contents are a copy of the
!       case's `legacy/` deck -- the same layout tools/yl_run.py materialises for hstar;
!     * it takes its options through `diag_set_mode_from_argv`, the SAME argv parser the
!       solver uses, so `--dump-state=state` means exactly what it means for hstar;
!     * it emits its checkpoint snapshot through `yl_state_dump`, the SAME generated
!       observer the solver calls at Fem.f90:1908.
!
!   Nothing about the comparison surface is defined here. The adjudication is done by
!   tools/yl_state.py normalize + tools/yl_state_diff.py against docs/m2/state-field-map.toml's
!   own `compare.rule` per row. This program contains no comparator, no tolerance and no
!   ignore list, on purpose: a second set of tolerance/ignore semantics is the drift
!   pattern ADR-0001/0004 exist to prevent, and the plan names it explicitly ("不新建
!   ProblemState 比较器作为判据").
!
! THE PIPELINE IT RUNS
!     legacy deck (cwd) --adapt_legacy_deck--> problem_state_t
!                       --build_runtime-->     runtime_state_t
!                       --commit_legacy_globals--> the real legacy globals
!                       --yl_state_dump('model_ready')--> <dump dir>/model_ready/state.txt
!
!   It is the same first three stages as src/adapter/yl_adapter_bridge_test.f90 (L3-b).
!   The difference is the fourth: L3-b read the committed globals back with its own
!   hand-written row-by-row reader and compared against the frozen baseline JSON; this
!   program reads NOTHING back itself and instead hands the globals to the M2 observer,
!   so the artefact it produces is a state dump in the M2-02 wire format, byte-comparable
!   with one the legacy solver writes.
!
! ONLY `model_ready`
!   `yl_state_dump` is registered for three checkpoints. This program can reach exactly
!   one of them. `phase_ready(1)` and `increment_ready(1,1)` are emitted from inside
!   FEM90's solve (Fem.f90:3602 and :3656); this binary links no main solver and runs no
!   solve, so there is no point in its execution at which either checkpoint's state
!   exists. Emitting an empty or partial snapshot for them would be manufacturing
!   evidence, so it emits neither, and the harness reports the two checkpoints as not
!   comparable with that reason rather than as a pass.
!
! SCRATCH DISCIPLINE (the rule of src/adapter/yl_adapter_bridge_test.f90's own header)
!   This program never names a path under `cases/`. It opens deck files relative to its
!   cwd and writes only under the `--dump-state=DIR` directory, also relative to cwd. The
!   harness (tools/yl_shadow_diff.py) is what stages the copy; keeping the path knowledge
!   out of here is what makes "never write into cases/" checkable by looking at the
!   harness alone.
!
! EXIT CODES
!   0  the dump was written
!   2  usage: --dump-state=DIR was not given (diag_set_mode_from_argv itself exits 2 on a
!      malformed argv, before this program sees it)
!   4  a pipeline stage raised a finding; the findings are printed and NO dump is written.
!      The harness turns this into UNVERIFIED rows, never into a pass.
!   Any abort inside yl_state_dump is `diag_abort`'s own exit 6 (INTERNAL) with an
!   HSTAR_DIAG line on stderr naming the field it could not emit -- that path is a real
!   possible outcome here, not a defensive branch: commit_legacy_globals writes only the
!   46 model_ready `RuntimeState.*` rows plus their extents (its own header, "WHAT IS
!   WRITTEN"), while `model_ready` has 162 emitted rows. See docs/m4/L3c-shadow-report.md.
program yl_adapter_shadow

  use iso_fortran_env, only: output_unit, error_unit

  use yl_diag, only: diag_set_mode_from_argv, yl_dump_enabled, yl_dump_dir

  use yl_problem_types, only: problem_state_t
  use yl_problem_manifest, only: manifest_t
  use yl_problem_errors, only: problem_errors_t
  use yl_adapter_driver, only: adapt_legacy_deck

  use yl_runtime_types, only: runtime_state_t
  use yl_runtime_contract, only: CONTRACT_TAG
  use yl_runtime_build, only: build_runtime
  use yl_runtime_commit, only: commit_legacy_globals

  use yl_state_serializer, only: yl_state_dump

  implicit none

  type(problem_state_t), allocatable :: problem
  type(manifest_t), allocatable :: pmanifest, rmanifest
  type(problem_errors_t) :: errors
  type(runtime_state_t), allocatable :: rt

  call diag_set_mode_from_argv()
  if (.not. yl_dump_enabled) then
    write (error_unit, '(a)') 'yl_adapter_shadow: --dump-state=DIR is required '// &
      '(this program exists to write a state dump; without one it has no output).'
    call exit_with(2)
  end if

  write (output_unit, '(a)') 'yl_adapter_shadow: NEW path (adapter -> build_runtime -> '// &
    'commit_legacy_globals -> yl_state_dump), cwd is the deck directory.'
  write (output_unit, '(a)') 'yl_adapter_shadow: dump dir = '//trim(yl_dump_dir)

  call adapt_legacy_deck('.', problem, pmanifest, errors)
  if (errors%any() .or. .not. allocated(problem)) then
    call print_findings('adapt_legacy_deck', errors)
    call exit_with(4)
  end if
  write (output_unit, '(a)') 'yl_adapter_shadow: adapt_legacy_deck ok'

  call build_runtime(problem, CONTRACT_TAG, rt, rmanifest, errors)
  if (errors%any() .or. .not. allocated(rt)) then
    call print_findings('build_runtime', errors)
    call exit_with(4)
  end if
  write (output_unit, '(a)') 'yl_adapter_shadow: build_runtime ok (contract '//CONTRACT_TAG//')'

  call commit_legacy_globals(rt, errors)
  if (errors%any()) then
    call print_findings('commit_legacy_globals', errors)
    call exit_with(4)
  end if
  write (output_unit, '(a)') 'yl_adapter_shadow: commit_legacy_globals ok'

  ! The one checkpoint this path can reach. Anything this call cannot emit aborts inside
  ! yl_state_io:state_fail with an HSTAR_DIAG line naming the field; that is the honest
  ! outcome and is not caught here.
  call yl_state_dump('model_ready')
  write (output_unit, '(a)') 'yl_adapter_shadow: yl_state_dump(model_ready) ok'

contains

  subroutine print_findings(stage, errs)
    character(len=*), intent(in) :: stage
    type(problem_errors_t), intent(inout) :: errs
    integer :: i
    write (error_unit, '(a)') 'yl_adapter_shadow: '//stage//' raised a finding; no dump written.'
    do i = 1, errs%count()
      write (error_unit, '(a)') '    '//stage//': '//errs%render(i)
    end do
  end subroutine print_findings

  subroutine exit_with(code)
    integer, intent(in) :: code
    flush (output_unit)
    flush (error_unit)
    if (code /= 0) then
      error stop code
    end if
  end subroutine exit_with

end program yl_adapter_shadow
