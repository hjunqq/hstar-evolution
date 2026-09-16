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

  use iso_fortran_env, only: int32, output_unit, error_unit

  use yl_problem_optional, only: opt_get, opt_set

  use yl_diag, only: diag_abort, EXIT_INIT, EXIT_INPUT, EXIT_UNSUPPORTED,                     &
                     yl_input_enabled, yl_input_file

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
  use yl_problem_existence, only: deck_existence_t
  use yl_problem_manifest, only: manifest_t
  use yl_problem_errors, only: problem_errors_t
  use yl_adapter_driver, only: adapt_legacy_deck
  use yl_authoring_toml, only: toml_doc_t, toml_read
  use yl_authoring_keys, only: authoring_validate
  use yl_authoring_report, only: authoring_render
  use yl_authoring_map, only: authoring_build_problem
  use yl_authoring_defaults, only: default_residue, default_existence

  use yl_runtime_types, only: runtime_state_t
  use yl_runtime_contract, only: CONTRACT_TAG
  use yl_runtime_build, only: build_runtime
  use yl_runtime_commit, only: commit_legacy_globals, commit_step_invariants
  use yl_adapter_session, only: session_problem, session_runtime, session_committed

  implicit none

  type(problem_state_t), allocatable :: problem
  type(deck_residue_t) :: residue
  type(deck_existence_t) :: existence
  type(manifest_t), allocatable :: pmanifest, rmanifest
  type(problem_errors_t) :: errors
  type(runtime_state_t), allocatable :: rt

  ! legacy calls this from INSIDE its block loop (Fem.f90, just before the model_ready
  ! dump), so on a two-block analysis it is called twice. The full commit is a once-per-
  ! run act -- it allocates the legacy globals and would refuse its own second call --
  ! and everything that legitimately differs between blocks is committed by
  ! yl_adapter_block_override at the TOP of each block instead.
  if (session_committed) return

  write (output_unit, '(a)') 'yl_adapter_override: adapter entry ON; the legacy readers '// &
    'below are switched off and these globals come from the deck through the adapter.'

  call kinddefine

  if (yl_input_enabled) then
    call from_modern_input(problem, residue, existence, pmanifest, errors)
  else
    call adapt_legacy_deck('.', problem, residue, existence, pmanifest, errors)
  end if
  if (errors%any() .or. .not. allocated(problem)) then
    if (yl_input_enabled) then
      call fail(trim(yl_input_file), errors)
    else
      call fail('adapt_legacy_deck', errors)
    end if
  end if

  call commit_step_invariants(problem, errors)
  if (errors%any()) call fail('commit_step_invariants', errors)

  call build_runtime(problem, CONTRACT_TAG, rt, rmanifest, errors)
  if (errors%any() .or. .not. allocated(rt)) call fail('build_runtime', errors)

  call commit_legacy_globals(problem, residue, existence, rt, errors)
  if (errors%any()) call fail('commit_legacy_globals', errors)

  ! Hand the committed state to the session so the blocks that follow can re-commit
  ! their own share of it. move_alloc, not a copy: there is exactly one ProblemState per
  ! run and the session owns it from here on.
  call move_alloc(problem, session_problem)
  call move_alloc(rt, session_runtime)
  session_committed = .true.

  ! The modern values that need a size commit computes.
  if (yl_input_enabled) call yl_modern_after_commit()

  write (output_unit, '(a)') 'yl_adapter_override: commit ok; the solve below runs on '// &
    'adapter state.'

contains

  !> The modern path: read, validate, map. The residue and the runtime-state manifest are
  !> filled from the contract's default table rather than from a deck -- they are constants
  !> of the capability whitelist (yl_authoring_defaults), which is exactly why the modern
  !> input does not have to carry them.
  subroutine from_modern_input(problem, residue, existence, pmanifest, errors)
    type(problem_state_t), allocatable, intent(inout) :: problem
    type(deck_residue_t), intent(out) :: residue
    type(deck_existence_t), intent(out) :: existence
    type(manifest_t), allocatable, intent(inout) :: pmanifest
    type(problem_errors_t), intent(inout) :: errors
    type(toml_doc_t) :: doc
    integer(int32) :: npoin, nelem, ngroup, mdofn, k
    integer :: i

    write (output_unit, '(a)') 'yl_adapter_override: modern input '//trim(yl_input_file)

    call toml_read(trim(yl_input_file), doc)
    if (doc%failed) then
      write (error_unit, '(a,i0,a)') trim(yl_input_file)//':', doc%fail_line, &
        ': INVALID_INPUT: '//trim(doc%message)
      flush (output_unit)
      flush (error_unit)
      call diag_abort('RANGE', EXIT_INPUT, 'yl_adapter_override', &
           'case.toml is not readable as the authoring contract''s TOML subset')
    end if

    ! Findings are NOT printed here. `fail` below renders every one of them, and printing
    ! them in both places showed an operator each error twice.
    call authoring_validate(doc, trim(yl_input_file), errors)
    if (errors%any()) return

    call authoring_build_problem(doc, '.', problem, pmanifest, errors,                       &
                                 file=trim(yl_input_file))
    if (errors%any() .or. .not. allocated(problem)) return

    npoin = int(size(problem%mesh%nodes), int32)
    nelem = int(size(problem%mesh%elements), int32)
    ngroup = int(size(problem%sections), int32)
    mdofn = int(int_at_dim(problem), int32)
    call default_residue(residue, npoin)
    ! `uinitial` is one value PER BLOCK, so the default table's single zero only ever fit
    ! a one-step analysis. The author states it per step (`reset_state`); this is the
    ! fan-out, and commit refuses a size that does not match the step count.
    ! How many blocks legacy will run. The default table's 1 was only ever right for a
    ! one-step analysis; commit now checks this against the step count rather than
    ! against 1, so a disagreement is a finding instead of a silently truncated run.
    call opt_set(residue%runblks, int(max(1, int(doc%count_of('step'))), int32))
    if (allocated(residue%uinitial)) deallocate (residue%uinitial)
    allocate (residue%uinitial(max(1, int(doc%count_of('step')))))
    residue%uinitial = 0_int32
    do i = 1, int(doc%count_of('step'))
      k = doc%find('step['//itoa(i)//'].reset_state')
      if (k /= 0_int32) residue%uinitial(i) = merge(1_int32, 0_int32, doc%entry(k)%lvalue)
    end do
    call default_existence(existence, nelem, ngroup, mdofn)
  end subroutine from_modern_input

  !> mdofn: degrees of freedom per node. On the whitelist it is the spatial dimension --
  !> a displacement field in 2-D. Read from the problem rather than pinned, so the day a
  !> pressure field is whitelisted this is where it stops being the dimension.
  integer function int_at_dim(problem) result(n)
    type(problem_state_t), intent(in) :: problem
    integer(int32) :: d
    logical :: found
    call opt_get(problem%mesh%dimension, d, found)
    n = 0
    if (found) n = int(d)
  end function int_at_dim

  pure function itoa(v) result(out)
    integer, intent(in) :: v
    character(len=12) :: buf
    character(len=:), allocatable :: out
    write (buf, '(i0)') v
    out = trim(buf)
  end function itoa

  subroutine fail(stage, errs)
    character(len=*), intent(in) :: stage
    type(problem_errors_t), intent(inout) :: errs
    integer :: i
    integer :: code
    ! The header an OPERATOR reads. On the modern path they typed a file name and expect a
    ! sentence about that file, not the name of the routine that noticed; the legacy-deck
    ! path keeps its internal wording because its audience is this project.
    if (yl_input_enabled) then
      write (error_unit, '(a)') stage//' was not accepted; nothing was solved and no '// &
        'results were written.'
    else
      write (error_unit, '(a)') 'yl_adapter_override: '//stage//' raised a finding; '// &
        'refusing to continue on legacy state.'
    end if
    do i = 1, errs%count()
      ! An authoring finding knows its own file and line, and `authoring_render` puts them
      ! where an editor can jump to them. A legacy-deck finding has no such location, so it
      ! keeps the generic rendering with the stage as its prefix.
      if (yl_input_enabled) then
        write (error_unit, '(a)') authoring_render(errs, i)
      else
        write (error_unit, '(a)') '    '//stage//': '//errs%render(i)
      end if
    end do
    flush (output_unit)
    flush (error_unit)
    ! Carry the finding's OWN verdict outward instead of flattening everything to INIT.
    ! A refused dialect is exit 3 (UNSUPPORTED) and a malformed record is exit 2 (INPUT);
    ! reporting both as 4 would erase the distinction the exit protocol exists to make,
    ! and M4-01's judgement 5 asserts the outward verdict for a refused dialect is uniform.
    ! Found 2026-09-11 by the fallback gate, which asked what a refused deck actually
    ! reports and got INIT.
    code = errs%exit_code()
    select case (code)
    case (EXIT_UNSUPPORTED)
      call diag_abort('UNSUPPORTED', EXIT_UNSUPPORTED, 'yl_adapter_override', &
           stage//' refused this deck under --adapter=on; rerun with --adapter=off to '// &
           'use the legacy readers')
    case (EXIT_INPUT)
      call diag_abort('RANGE', EXIT_INPUT, 'yl_adapter_override', &
           stage//' rejected this deck under --adapter=on')
    case default
      call diag_abort('INIT', EXIT_INIT, 'yl_adapter_override', &
           stage//' raised a finding under --adapter=on')
    end select
  end subroutine fail

end subroutine yl_adapter_override


!> The per-block half of the adapter entry: what legacy re-reads at the top of every
!> block, supplied from ProblemState instead.
!>
!> WHERE IT IS CALLED AND WHY THERE
!>   Fem.f90 calls it at the top of the block loop, BEFORE the loop reads
!>   `appear_process(:, iblks)` and `matno_process(:, iblks)` into `appear` and
!>   `group%matno`. That ordering is the whole point: those two arrays are committed
!>   once, by block 1's full commit, and block 2 consumes them before anything else
!>   happens. Putting this hook where `yl_adapter_override` already sits -- after
!>   `external_load_2`, near the model_ready dump -- would commit block 2's loads after
!>   block 2 had already decided which groups are active.
!>
!>   It is guarded on `iblks > 1` at the call site, so block 1 keeps EXACTLY the path it
!>   had before this existed: one commit, in one place, at the end of which
!>   `commit_block_state` supplies block 1's own loads.
subroutine yl_adapter_block_override(iblks)

  use iso_fortran_env, only: int32, output_unit

  use yl_diag, only: diag_abort, EXIT_INIT
  use yl_problem_errors, only: problem_errors_t
  use yl_runtime_commit, only: commit_block_state
  use yl_adapter_session, only: session_problem, session_runtime, session_committed

  implicit none

  integer(int32), intent(in) :: iblks
  type(problem_errors_t) :: errors
  integer :: i

  ! Nothing committed means the adapter entry never ran, which cannot happen through
  ! Fem.f90's guard -- but a silent return here would be a block running on the previous
  ! block's loads, so it is a refusal rather than an assumption.
  if (.not. session_committed .or. .not. allocated(session_problem) .or.                      &
      .not. allocated(session_runtime)) then
    call diag_abort('INIT', EXIT_INIT, 'yl_adapter_block_override',                           &
         'legacy asked for block state before the adapter committed anything')
  end if

  call commit_block_state(session_problem, session_runtime, iblks, errors)
  if (errors%any()) then
    do i = 1, errors%count()
      write (output_unit, '(a)') '    '//trim(errors%render(i))
    end do
    call diag_abort('INIT', EXIT_INIT, 'yl_adapter_block_override',                           &
         'the per-block commit raised a finding; refusing to run this block on the '//        &
         'previous block''s loads')
  end if
end subroutine yl_adapter_block_override
