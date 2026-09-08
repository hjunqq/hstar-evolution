! yl_adapter_driver -- M4-01 L2-a: the sequencing driver for the repository-side legacy
! adapter (docs/m4/adapter-contract.md, .ccg/tasks/m4-01-legacy-adapter/plan.md).
!
! ONE public entry point, `adapt_legacy_deck`. It is the only adapter module allowed to
! open, close or position a deck unit (contract SS2: "不打开、不关闭、不 rewind 任何单元。
! 单元生命周期归 L2-a 驱动"), the only module allowed to call `yl_problem_builder`'s
! `builder_step_*` and `builder_set_solver` routines (contract SS2.1/SS2.2: every other
! parser only fills a leaf of the shared `step_parts_t`/`solver_parts_t`, because those
! builder calls are single-shot singletons and a second call from a second parser would
! be silently rejected -- or worse, silently accepted for the wrong reason), and the only
! module that calls `yl_problem_pipeline.prepare_problem`.
!
! WHAT THIS MODULE DOES NOT DO
!   It does not decide whether a value is admissible -- every whitelist judgement is the
!   owning parser's, and this module trusts a parser's silence (no new finding) as its
!   only signal that a file was fine. It does not read a single deck record itself for
!   modelling purposes -- see "the probn problem" below for the one narrow exception this
!   module cannot avoid, and why that exception reads nothing this module models.
!
! CALL ORDER, and why it is not simply "the five layer-1 modules in file order"
!   `parse_glb` is the sole writer of `deck_context_t` (contract SS2.2) and every other
!   parser except `parse_inp` takes `ctx` to size a read or take a branch that would
!   otherwise be a silent misparse (a wrong `ndimn` desyncs every following read; a MIF
!   deck read as FIX raises no I/O error at all). So `parse_glb` runs before
!   `parse_cor`/`parse_ele`/`parse_mat`/`parse_sol`/`parse_loa`/`parse_pre`/`parse_man`.
!
!   `parse_inp` is the one exception: its own header states `ctx` is unused there because
!   `inp` is read before `.glb` in FEM90's own order (Fem.f90:94-117 precedes `call
!   global_data`), so `ctx` cannot yet be filled when it runs. `inp` is nonetheless a
!   SEPARATE Fortran unit from every other deck file, so there is no shared-cursor reason
!   to call `parse_inp` before `parse_glb` -- unlike legacy, which reads `inp` first only
!   because `PROGRAM FEM90`'s body happens to run that way. This driver calls it first
!   anyway, matching Fem.f90's own order where there is no cost to doing so.
!
!   Among the seven `ctx`-dependent parsers, `yl_adapter_model.f90`'s own header states the
!   interleaving with `.cor`/`.ele` that legacy's `global_data` performs internally does not
!   bind this driver: "`.glb`/`.cor`/`.ele` are three independent Fortran units this
!   parser's own cursor... is unaffected... there is no sequencing constraint THIS module
!   needs from L2-a beyond... parse_glb on a `unit` positioned at the start... and do not
!   interleave another `.glb` read from elsewhere." No parser's header claims a sequencing
!   need on any OTHER parser beyond "after parse_glb", so this driver calls the seven in
!   the order the contract table lists them (SS1): cor, ele, mat, sol, loa, pre, man.
!
! THE PROBN PROBLEM -- the one read this module makes for a reason no parser has
!   Legacy names eight of the nine deck files `probn(1:len1)//'.ext'` (Global.f90:631-648),
!   with `probn` a value READ from `inp` (Fem.f90:103, before `call global_data` at :118).
!   This driver owns every `open`, so it must know that prefix before it can open `.glb`
!   and the rest -- but `parse_inp` (yl_adapter_fem90.f90) has no channel to report `probn`
!   back to a caller: it stores `case.name` straight into the builder, which exposes no
!   getter (`problem_builder_t`'s components are private and there is no `builder_get_case`
!   -- checked, yl_problem_builder.f90's public list has none). So this driver reads
!   `inp`'s first four records itself, on a SEPARATE, disposable Fortran unit, purely to
!   learn the prefix, then opens a second, canonical connection to `inp` and hands THAT one
!   to `parse_inp` untouched -- never rewound, never pre-read on the unit `parse_inp` itself
!   receives. `derive_deck_prefix` below is that read. It duplicates four of `parse_inp`'s
!   record shapes verbatim (same reason its own module header requires: legacy line
!   numbers alongside each read, so a future diff against Fem.f90 is textual, not
!   re-derived from memory) but interprets NONE of them -- no run_control flag is checked,
!   no whitelist is enforced, no builder call is made from this reader. `parse_inp`, on its
!   own untouched connection, still does every one of those things for real; this read
!   exists only to name a file.
!
!   A rewind of `parse_inp`'s own unit was considered and rejected: the contract's "parsers
!   never open/close/rewind" rule (SS2) exists precisely so a unit's position is owned by
!   exactly one place for its whole life. Rewinding the unit `parse_inp` is about to receive
!   would make this driver a second, silent participant in that one unit's position
!   invariant. A second, wholly separate connection keeps `parse_inp`'s unit exactly as
!   untouched as every other parser's.
!
! UNIT LIFETIME AND THE NINE FILES
!   Fem.f90's own body opens exactly ONE deck unit before `call global_data`: `inpunit`
!   (Fem.f90:95, `open(inpunit,file='inp',status='old',...)`). Every other deck file this
!   build parses is opened inside `global_data` (Global.f90:631-648): `gunit`/`.glb`,
!   `cunit`/`.cor`, `eunit`/`.ele`, `punit`/`.pre`, `munit`/`.mat`, `loadunit`/`.loa`,
!   `solveunit`/`.sol`, `mainunit`/`.man`. That is eight files opened by `global_data` plus
!   `inp`, nine in total -- not ten; grepped in full (`grep -na 'open *(' legacy/yl/Fem.f90`
!   and `legacy/yl/Global.f90`) rather than assumed. `Global.f90` opens a great many more
!   units in that same block (`.chk`, `.opr`, output streams, ...) but none of them is a
!   deck this build's parsers read, so this driver opens none of them. (Reported to the
!   team lead: the task brief's "FEM90's main body performs 10 opens before global_data" did
!   not match either file; nine total across both sites is what the source shows.)
!
!   Every unit this driver opens, it closes on every exit path -- success, a parser
!   finding, or a failure raised here -- via `close_all`, called exactly once, right after
!   the parse-and-assemble block, before this routine can return.
!
! TRANSACTION DISCIPLINE
!   `problem` and `manifest` are the caller's published outputs and are never touched
!   before the single call to `prepare_problem` at the very end, and `prepare_problem`
!   itself only publishes them via its own two-`move_alloc` success path (yl_problem_
!   pipeline.f90). Every failure branch in between -- an open failure, a parser finding, a
!   builder refusal -- returns before that call is ever reached, leaving both arguments
!   exactly as the caller passed them in. The local `draft` this routine builds (via
!   `problem_builder_t` + `builder_finish`) is itself never the caller's `problem`; it is
!   the private candidate `prepare_problem` expects as its own `intent(in)` argument.
!
! FAIL-FAST, not defect accumulation
!   Unlike `yl_problem_pipeline`'s WITHIN-stage accumulation (every independent defect in
!   one stage is collected before the barrier), this driver stops at the FIRST parser or
!   assembly step that adds a finding (`errors%count()` grown since the mark taken just
!   before that step) -- mirroring `prepare_problem`'s BETWEEN-stage barrier, because each
!   parser call here is closer to a barrier than to a stage: a `.glb` failure leaves `ctx`
!   unfilled, and calling `.cor`/`.ele`/... anyway would only add secondary "ctx not filled"
!   noise (PE_INTERNAL, each parser's own guard) on top of the real, primary defect.
module yl_adapter_driver

  use iso_fortran_env, only: int32
  use yl_problem_types, only: problem_state_t, step_t
  use yl_problem_optional, only: opt_get, opt_is_set
  use yl_problem_manifest, only: manifest_t
  use yl_problem_profile, only: PROFILE_TAG
  use yl_problem_errors, only: problem_errors_t, source_location_t, make_source_location, &
                                make_problem_error, PE_INVALID_INPUT, PE_INTERNAL
  use yl_problem_builder, only: problem_builder_t, step_builder_t, &
                                builder_begin, builder_finish, builder_failed, &
                                builder_note_failure, builder_add_step, builder_set_solver, &
                                builder_step_begin, builder_step_finish, &
                                builder_step_set_procedure, builder_step_set_load_mode, &
                                builder_step_set_controls, builder_step_set_load, &
                                builder_step_set_output, builder_step_add_boundary, &
                                builder_step_boundary_empty, builder_step_add_activation, &
                                builder_step_activation_empty
  use yl_problem_pipeline, only: prepare_problem
  use yl_adapter_parts, only: deck_context_t, deck_context_reset, &
                              step_parts_t, step_parts_reset, &
                              solver_parts_t, solver_parts_reset
  use yl_adapter_fem90, only: parse_inp, parse_man
  use yl_adapter_model, only: parse_glb
  use yl_adapter_mesh, only: parse_cor, parse_ele
  use yl_adapter_material, only: parse_mat, parse_sol
  use yl_adapter_load, only: parse_loa, parse_pre

  implicit none
  private

  public :: adapt_legacy_deck

  ! L2-b has not yet landed PE_STAGE_ADAPT (adapter-contract.md SS4). Same stand-in every
  ! parser module already carries; replace with the real constant once it lands.
  character(len=*), parameter :: STAGE_ADAPT = 'adapt'

  ! This module's own rule-id namespace (contract SS4's "A<n>/<condition>" shape, scoped
  ! locally the same way yl_adapter_load.f90's "A-IO/*" is): failures that belong to
  ! sequencing/lifetime, not to any one deck's content.
  character(len=*), parameter :: SITE = 'yl_adapter_driver.adapt_legacy_deck'

  integer, parameter :: IOMSG_LEN = 256
  integer, parameter :: UNSET_UNIT = -1  ! matches yl_state_io.f90's own "not open" sentinel

contains

  ! Opens every deck unit this build parses, drives the five parser modules in the order
  ! the module header derives, assembles steps[0]/solver exactly once, and hands the
  ! finished draft to prepare_problem. See the module header for the full rationale.
  subroutine adapt_legacy_deck(dir, problem, manifest, errors)
    character(len=*), intent(in) :: dir
    type(problem_state_t), allocatable, intent(inout) :: problem
    type(manifest_t), allocatable, intent(inout) :: manifest
    type(problem_errors_t), intent(inout) :: errors

    integer :: u_inp, u_glb, u_cor, u_ele, u_mat, u_sol, u_loa, u_pre, u_man
    character(len=:), allocatable :: prefix
    type(problem_builder_t) :: b
    type(deck_context_t) :: ctx
    type(step_parts_t) :: parts
    type(solver_parts_t) :: sparts
    type(step_builder_t) :: sb
    type(step_t) :: step_val
    type(problem_state_t), allocatable :: draft
    type(source_location_t) :: loc
    character(len=:), allocatable :: text_val
    logical :: ok, found
    integer :: mark0, mark, i

    u_inp = UNSET_UNIT; u_glb = UNSET_UNIT; u_cor = UNSET_UNIT; u_ele = UNSET_UNIT
    u_mat = UNSET_UNIT; u_sol = UNSET_UNIT; u_loa = UNSET_UNIT; u_pre = UNSET_UNIT
    u_man = UNSET_UNIT

    call deck_context_reset(ctx)
    call step_parts_reset(parts)
    call solver_parts_reset(sparts)
    call builder_begin(b)

    mark0 = errors%count()

    parse_all: do
      ! -- learn the deck's file-name prefix (see "THE PROBN PROBLEM" above) --------
      call derive_deck_prefix(dir, prefix, errors, ok)
      if (.not. ok) exit parse_all

      ! -- open every unit; legacy sites in the comment above each -------------------
      call open_deck_unit(join_path(dir, 'inp'), 'inp', errors, u_inp, ok)          ! Fem.f90:95
      if (.not. ok) exit parse_all
      call open_deck_unit(join_path(dir, prefix//'.glb'), '.glb', errors, u_glb, ok) ! Global.f90:631
      if (.not. ok) exit parse_all
      call open_deck_unit(join_path(dir, prefix//'.cor'), '.cor', errors, u_cor, ok) ! Global.f90:633
      if (.not. ok) exit parse_all
      call open_deck_unit(join_path(dir, prefix//'.ele'), '.ele', errors, u_ele, ok) ! Global.f90:635
      if (.not. ok) exit parse_all
      call open_deck_unit(join_path(dir, prefix//'.pre'), '.pre', errors, u_pre, ok) ! Global.f90:637
      if (.not. ok) exit parse_all
      call open_deck_unit(join_path(dir, prefix//'.mat'), '.mat', errors, u_mat, ok) ! Global.f90:639
      if (.not. ok) exit parse_all
      call open_deck_unit(join_path(dir, prefix//'.loa'), '.loa', errors, u_loa, ok) ! Global.f90:641
      if (.not. ok) exit parse_all
      call open_deck_unit(join_path(dir, prefix//'.sol'), '.sol', errors, u_sol, ok) ! Global.f90:644
      if (.not. ok) exit parse_all
      call open_deck_unit(join_path(dir, prefix//'.man'), '.man', errors, u_man, ok) ! Global.f90:646
      if (.not. ok) exit parse_all

      ! -- inp: no ctx dependency (see module header); called first, matching Fem.f90 --
      mark = errors%count()
      call parse_inp(u_inp, ctx, b, errors)
      if (errors%count() > mark) exit parse_all

      ! -- .glb: the sole writer of ctx; every other parser below depends on it --------
      mark = errors%count()
      call parse_glb(u_glb, ctx, b, parts, sparts, errors)
      if (errors%count() > mark) exit parse_all

      ! -- the six remaining ctx-readers, contract SS1 order -----------------------------
      mark = errors%count()
      call parse_cor(u_cor, ctx, b, errors)
      if (errors%count() > mark) exit parse_all

      mark = errors%count()
      call parse_ele(u_ele, ctx, b, errors)
      if (errors%count() > mark) exit parse_all

      mark = errors%count()
      call parse_mat(u_mat, ctx, b, errors)
      if (errors%count() > mark) exit parse_all

      mark = errors%count()
      call parse_sol(u_sol, ctx, b, sparts, errors)
      if (errors%count() > mark) exit parse_all

      mark = errors%count()
      call parse_loa(u_loa, ctx, b, parts, errors)
      if (errors%count() > mark) exit parse_all

      mark = errors%count()
      call parse_pre(u_pre, ctx, b, parts, errors)
      if (errors%count() > mark) exit parse_all

      mark = errors%count()
      call parse_man(u_man, ctx, b, parts, errors)
      if (errors%count() > mark) exit parse_all

      ! -- assemble steps[0] exactly once, from the shared step_parts_t (contract SS2.1) --
      loc = make_source_location(reader=SITE, &
              file='(steps[0] assembly: not one deck record, see module header)')

      call builder_step_begin(sb)

      ! procedure_/load_mode are opt_text, .glb's exclusive leaves (yl_adapter_parts.f90's
      ! leaf table); every other steps[0] leaf below is a typed aggregate already, filled
      ! leaf-by-leaf across files, and is handed to its singleton setter as a whole value.
      call opt_get(parts%procedure_, text_val, found)
      if (.not. found) then
        call builder_note_failure(b, PE_INTERNAL, 'D1/procedure-unset', 'steps[0]', &
          'procedure', 'parse_glb should have filled steps[0].procedure_ on success; ' // &
          'it did not', loc, errors)
        exit parse_all
      end if
      call builder_step_set_procedure(b, sb, text_val, loc, errors)
      if (builder_failed(b)) exit parse_all

      call opt_get(parts%load_mode, text_val, found)
      if (.not. found) then
        call builder_note_failure(b, PE_INTERNAL, 'D1/load-mode-unset', 'steps[0]', &
          'load_mode', 'parse_glb should have filled steps[0].load_mode on success; ' // &
          'it did not', loc, errors)
        exit parse_all
      end if
      call builder_step_set_load_mode(b, sb, text_val, loc, errors)
      if (builder_failed(b)) exit parse_all

      call builder_step_set_controls(b, sb, parts%controls, loc, errors)
      if (builder_failed(b)) exit parse_all

      call builder_step_set_load(b, sb, parts%load, loc, errors)
      if (builder_failed(b)) exit parse_all

      call builder_step_set_output(b, sb, parts%output, loc, errors)
      if (builder_failed(b)) exit parse_all

      ! boundary(:)/activation(:): unallocated means the owning parser never got this
      ! far (unreachable here -- both .pre and .glb always allocate, size 0 included, on
      ! their own success path), allocated size 0 means "ran, found none" and must reach
      ! the builder as an explicit empty declaration, not silence (yl_adapter_parts.f90's
      ! three-state comment; ADR-0002).
      if (allocated(parts%boundary)) then
        if (size(parts%boundary) == 0) then
          call builder_step_boundary_empty(b, sb, loc, errors)
          if (builder_failed(b)) exit parse_all
        else
          do i = 1, size(parts%boundary)
            call builder_step_add_boundary(b, sb, parts%boundary(i), loc, errors)
            if (builder_failed(b)) exit parse_all
          end do
        end if
      end if

      if (allocated(parts%activation)) then
        if (size(parts%activation) == 0) then
          call builder_step_activation_empty(b, sb, loc, errors)
          if (builder_failed(b)) exit parse_all
        else
          do i = 1, size(parts%activation)
            call builder_step_add_activation(b, sb, parts%activation(i), loc, errors)
            if (builder_failed(b)) exit parse_all
          end do
        end if
      end if

      call builder_step_finish(b, sb, step_val, loc, errors, ok)
      if (.not. ok) exit parse_all

      call builder_add_step(b, step_val, loc, errors)
      if (builder_failed(b)) exit parse_all

      ! -- solver: .glb's linear/symmetric + .sol's profile%*, one singleton call ---------
      call builder_set_solver(b, sparts%solver, loc, errors)
      if (builder_failed(b)) exit parse_all

      exit parse_all
    end do parse_all

    call close_all(u_inp, u_glb, u_cor, u_ele, u_mat, u_sol, u_loa, u_pre, u_man)

    ! Transactional: any finding raised above (from a parser or from this routine) means
    ! `problem`/`manifest` must stay exactly as the caller passed them in.
    if (errors%count() > mark0) return

    call builder_finish(b, draft, errors, ok)
    if (.not. ok .or. .not. allocated(draft)) return

    call prepare_problem(draft, PROFILE_TAG, problem, manifest, errors)
  end subroutine adapt_legacy_deck

  ! ==============================================================================
  ! private helpers
  ! ==============================================================================

  ! See the module header, "THE PROBN PROBLEM". Reproduces Fem.f90:97-103's four reads,
  ! on a connection of its own, purely to learn the prefix the other eight deck files are
  ! named with (Global.f90:631-648, `probn(1:len1)//'.ext'`). Interprets nothing it reads:
  ! no whitelist check, no builder call. `parse_inp`, called later on its OWN connection,
  ! is what actually parses `inp` for the model.
  subroutine derive_deck_prefix(dir, prefix, errors, ok)
    character(len=*), intent(in) :: dir
    character(len=:), allocatable, intent(out) :: prefix
    type(problem_errors_t), intent(inout) :: errors
    logical, intent(out) :: ok

    integer :: u, ios
    character(len=IOMSG_LEN) :: iomsg_buf
    character(len=80) :: title
    integer(int32) :: restart, relis, sysrelis, adina, uopt_r, gamamax
    character(len=200) :: probn

    ok = .false.

    open (newunit=u, file=join_path(dir, 'inp'), status='old', action='read', &
          iostat=ios, iomsg=iomsg_buf)
    if (ios /= 0) then
      call errors%add(make_problem_error(code=PE_INVALID_INPUT, stage=STAGE_ADAPT, &
        rule_id='D0/open-failed', object_path='(deck)', field='inp', &
        message='cannot open "inp" to learn the deck file-name prefix: '//trim(iomsg_buf), &
        source=make_source_location(reader=SITE//'.derive_deck_prefix', file='inp')))
      return
    end if

    ! RD: INP.FEM90.title#1 (Fem.f90:97) -- read here only to advance the cursor
    read (u, *, iostat=ios, iomsg=iomsg_buf) title
    if (.not. check_prefix_read(u, ios, iomsg_buf, 'INP.FEM90.title#1', 97_int32, errors)) return

    ! RD: INP.FEM90.run_control (Fem.f90:99) -- read here only to advance the cursor
    read (u, *, iostat=ios, iomsg=iomsg_buf) restart, relis, sysrelis, adina, uopt_r, gamamax
    if (.not. check_prefix_read(u, ios, iomsg_buf, 'INP.FEM90.run_control', 99_int32, errors)) &
      return

    ! RD: INP.FEM90.title#2 (Fem.f90:101) -- read here only to advance the cursor
    read (u, *, iostat=ios, iomsg=iomsg_buf) title
    if (.not. check_prefix_read(u, ios, iomsg_buf, 'INP.FEM90.title#2', 101_int32, errors)) return

    ! RD: INP.FEM90.problem_name (Fem.f90:103) -- the one value this read is for
    read (u, *, iostat=ios, iomsg=iomsg_buf) probn
    if (.not. check_prefix_read(u, ios, iomsg_buf, 'INP.FEM90.problem_name', 103_int32, errors)) &
      return

    close (u)
    prefix = trim(probn)
    ok = .true.
  end subroutine derive_deck_prefix

  ! Shared failure path for derive_deck_prefix's four reads: close the disposable unit
  ! and raise one finding naming the reader-inventory id and legacy line it mirrors.
  function check_prefix_read(u, ios, iomsg_buf, rd_id, line, errors) result(good)
    integer, intent(in) :: u, ios
    character(len=*), intent(in) :: iomsg_buf, rd_id
    integer(int32), intent(in) :: line
    type(problem_errors_t), intent(inout) :: errors
    logical :: good
    good = (ios == 0)
    if (.not. good) then
      close (u)
      call errors%add(make_problem_error(code=PE_INVALID_INPUT, stage=STAGE_ADAPT, &
        rule_id='D0/prefix-read-failed', object_path='(deck)', field=rd_id, &
        message='cannot read "inp" while learning the deck file-name prefix ('//rd_id// &
                ', Fem.f90:'//itoa(line)//'): '//trim(iomsg_buf), &
        source=make_source_location(reader=SITE//'.derive_deck_prefix', file='inp', &
                                     line=line)))
    end if
  end function check_prefix_read

  ! Opens one deck unit by absolute path, status='old' (every file this driver opens must
  ! already exist -- this build only ever reads a deck, never writes one). `unit` is left
  ! at UNSET_UNIT on failure so close_all does not try to close a unit that never opened.
  subroutine open_deck_unit(path, kind_label, errors, unit, ok)
    character(len=*), intent(in) :: path, kind_label
    type(problem_errors_t), intent(inout) :: errors
    integer, intent(out) :: unit
    logical, intent(out) :: ok

    integer :: ios
    character(len=IOMSG_LEN) :: iomsg_buf

    open (newunit=unit, file=path, status='old', action='read', iostat=ios, iomsg=iomsg_buf)
    ok = (ios == 0)
    if (.not. ok) then
      unit = UNSET_UNIT
      call errors%add(make_problem_error(code=PE_INVALID_INPUT, stage=STAGE_ADAPT, &
        rule_id='D0/open-failed', object_path='(deck)', field=kind_label, &
        message='cannot open deck file "'//trim(path)//'": '//trim(iomsg_buf), &
        source=make_source_location(reader=SITE, file=path)))
    end if
  end subroutine open_deck_unit

  ! Closes every unit this driver may have opened, in reverse order, skipping any that
  ! never opened. Called exactly once, on every exit path (contract SS2's unit lifetime
  ! belongs to this driver alone; a unit left open on a failure branch would be this
  ! module's own defect, not a deck's).
  subroutine close_all(u_inp, u_glb, u_cor, u_ele, u_mat, u_sol, u_loa, u_pre, u_man)
    integer, intent(inout) :: u_inp, u_glb, u_cor, u_ele, u_mat, u_sol, u_loa, u_pre, u_man
    call close_if_open(u_man)
    call close_if_open(u_pre)
    call close_if_open(u_loa)
    call close_if_open(u_sol)
    call close_if_open(u_mat)
    call close_if_open(u_ele)
    call close_if_open(u_cor)
    call close_if_open(u_glb)
    call close_if_open(u_inp)
  end subroutine close_all

  subroutine close_if_open(unit)
    integer, intent(inout) :: unit
    if (unit /= UNSET_UNIT) then
      close (unit)
      unit = UNSET_UNIT
    end if
  end subroutine close_if_open

  ! `dir` may or may not carry a trailing '/'; every deck file is named relative to it.
  function join_path(dir, name) result(full)
    character(len=*), intent(in) :: dir, name
    character(len=:), allocatable :: full
    integer :: n
    n = len_trim(dir)
    if (n > 0) then
      if (dir(n:n) == '/') n = n - 1
    end if
    full = dir(1:n)//'/'//trim(name)
  end function join_path

  ! Formats a legacy line number for an error message. No library-provided integer-to-
  ! string exists in this build's dependency set (checked: not in yl_problem_optional.f90's
  ! public list), so this is the same ad hoc formatter every other adapter module already
  ! carries for the same reason (see e.g. yl_adapter_model.f90's own `itoa`).
  function itoa(n) result(s)
    integer(int32), intent(in) :: n
    character(len=:), allocatable :: s
    character(len=32) :: buf
    write (buf, '(i0)') n
    s = trim(buf)
  end function itoa

end module yl_adapter_driver
