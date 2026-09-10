! yl_adapter_override -- the M4-02 adapter entry, called from inside the solver.
!
! WHERE IT IS CALLED FROM AND WHY THERE
!   legacy/yl/Fem.f90, one line, immediately before the `model_ready` anchor:
!
!       if (yl_adapter_mode) call yl_adapter_override(); if (yl_dump_enabled) call yl_state_dump('model_ready')
!
!   Two things about that line are deliberate.
!
!   (1) It is ONE line, joined with `;`, because inserting a line would shift every
!       Fem.f90 line below it: three checkpoint anchors, seven reader-registry sites
!       and the M2-01 prose all carry `Fem.f90:N`. Re-anchoring that cascade is a
!       documented but error-prone procedure (it cost a wrong turn in M1-03). A `;`
!       is uglier to read and cheaper to be right about. `git diff` on Fem.f90 shows
!       exactly one changed line and no others.
!
!   (2) The override runs BEFORE the dump, so the snapshot the observer writes is of
!       ADAPTER state, not of legacy-reader state. If the order were reversed the
!       shadow comparison would silently compare the legacy path with itself -- a
!       control that cannot fail, which this project does not count as evidence.
!
! WHAT THIS IS, STATED NARROWLY
!   This is OVERRIDE mode, not yet "the adapter is the entry". The legacy readers
!   still run; their results are then replaced wholesale by the adapter's commit, and
!   the solve continues on adapter data. What that tests is the load-bearing question
!   for M4-02: **is the state the map registers sufficient to reproduce the results?**
!   If `1.flavia.res` comes out identical, whatever the map does not cover did not
!   matter for these decks. If it differs, the difference names what is missing --
!   which is worth more than a passing comparison that never touched the solver.
!
!   Skipping the legacy readers outright is the NEXT step and a different change: the
!   reader calls in FEM90 are interleaved with derived work (set_elem_dofs, trans
!   allocation, the appear/matno processing at :1716-1717) that commit does not write,
!   so guarding them needs that work separated first. Doing override first means the
!   sufficiency question is answered before the harder edit is attempted, instead of
!   both being in flight at once.
!
! FAILURE BEHAVIOUR
!   Any finding from any of the three stages aborts the process (exit 4, INIT) with
!   the findings printed. It does NOT fall back to the legacy globals that are already
!   in place. Falling back would mean a run that was asked for the adapter path
!   quietly produced legacy results -- see the stub's header for why that is the one
!   thing a fallback switch must never do.
subroutine yl_adapter_override()

  use iso_fortran_env, only: output_unit, error_unit

  use yl_diag, only: diag_abort, EXIT_INIT

  ! Deck-INDEPENDENT legacy initialisation that global_data happens to perform on its
  ! way through the readers (Global.f90:1190). kinddefine builds the element-kind
  ! library -- Q4/T3/L2 shape functions, Gauss rules -- which no deck can influence.
  ! Switching global_data off therefore also switches this off, and modf_element_lib
  ! then dereferences an unassociated elkn(index)%ggaus.
  !
  ! It is called here rather than left to the legacy path because that is what it is:
  ! initialisation, not input. The distinction this whole task keeps having to make is
  ! "did the deck decide this, or did the code?" -- and everything on the deck's side
  ! comes through commit, while everything on the code's side has to keep running.
  use elements, only: kinddefine

  use yl_problem_types, only: problem_state_t
  use yl_problem_deck_residue, only: deck_residue_t
  use yl_problem_manifest, only: manifest_t
  use yl_problem_errors, only: problem_errors_t
  use yl_adapter_driver, only: adapt_legacy_deck

  use yl_runtime_types, only: runtime_state_t
  use yl_runtime_contract, only: CONTRACT_TAG
  use yl_runtime_build, only: build_runtime
  use yl_runtime_commit, only: commit_legacy_globals

  implicit none

  type(problem_state_t), allocatable :: problem
  type(deck_residue_t) :: residue
  type(manifest_t), allocatable :: pmanifest, rmanifest
  type(problem_errors_t) :: errors
  type(runtime_state_t), allocatable :: rt

  write (output_unit, '(a)') 'yl_adapter_override: adapter entry ON; the legacy readers '// &
    'below are switched off and these globals come from the deck through the adapter.'

  call kinddefine

  call adapt_legacy_deck('.', problem, residue, pmanifest, errors)
  if (errors%any() .or. .not. allocated(problem)) call fail('adapt_legacy_deck', errors)

  call build_runtime(problem, CONTRACT_TAG, rt, rmanifest, errors)
  if (errors%any() .or. .not. allocated(rt)) call fail('build_runtime', errors)

  call commit_legacy_globals(problem, residue, rt, errors)
  if (errors%any()) call fail('commit_legacy_globals', errors)

  write (output_unit, '(a)') 'yl_adapter_override: commit ok; the solve below runs on '// &
    'adapter state.'

contains

  subroutine fail(stage, errs)
    character(len=*), intent(in) :: stage
    type(problem_errors_t), intent(inout) :: errs
    integer :: i
    write (error_unit, '(a)') 'yl_adapter_override: '//stage//' raised a finding; refusing '// &
      'to continue on legacy state.'
    do i = 1, errs%count()
      write (error_unit, '(a)') '    '//stage//': '//errs%render(i)
    end do
    flush (output_unit)
    flush (error_unit)
    call diag_abort('INIT', EXIT_INIT, 'yl_adapter_override', &
         stage//' raised a finding under --adapter=on')
  end subroutine fail

end subroutine yl_adapter_override
