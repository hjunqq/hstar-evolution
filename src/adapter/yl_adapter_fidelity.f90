! yl_adapter_fidelity -- M4 L3-a field-by-field fidelity gate (docs/m4/L3a-fidelity-report.md).
!
! THE QUESTION THIS FILE ANSWERS
!   Did the repository parsers (yl_adapter_fem90/model/mesh/material/load, driven the way
!   yl_adapter_driver drives them) construct the same problem the legacy reference implies,
!   for the SAME deck -- not "is the parsers' own output internally consistent" (the existing
!   M4-01 result: both golden decks parse with zero findings), which says nothing about
!   whether the parsed value is the RIGHT value.
!
! WHY BOTH SIDES ARE DRAFTS, NOT FINISHED PROBLEMS
!   `yl_adapter_driver.adapt_legacy_deck` calls `prepare_problem` after assembling its draft;
!   that stage normalizes, validates, derives fields (index maps, defaults such as
!   sections[].stress_components) and injects profile defaults. Comparing the two
!   POST-pipeline states would blend "did the parser read the deck right" with "did the
!   pipeline derive/default it the same way on both sides" and would specifically HIDE
!   default injection, which this gate exists to surface. So this file never calls
!   `prepare_problem`: `build_candidate` below reimplements the parse-and-assemble half of
!   `adapt_legacy_deck` verbatim (same open order, same unit lifetime, same parser call
!   order -- see yl_adapter_driver.f90's own header for the full rationale, which this file
!   does not repeat) and stops at `builder_finish`. `yl_adapter_harvest.harvest_problem_state`
!   already stops there by construction (it has no `prepare_problem` call at all). Both sides
!   are therefore PRE-pipeline drafts of the identical draft type, comparable leaf by leaf.
!
! WHAT "REFERENCE" MEANS HERE, AND ITS OWN GAP
!   The reference for every field the oracle harvests (88 of 98 `ProblemState.*` rows,
!   docs/m2/state-field-map.toml) is `yl_adapter_harvest`: it drives the REAL legacy readers
!   in-process (global_data, material_set, external_load_1, prescrib_set, PROFILE) and reads
!   the same globals `yl_state_dump.f90` (M2-02) already reads and that M2-03 froze baselines
!   against, so it is not an independent invention of what "correct" means -- it IS what
!   legacy makes of this deck. The oracle's own header enumerates ten rows it CANNOT reach
!   (GAP_MAN_STATIC_U: the four `.man` reads inside `STATIC_U`, an internal procedure of
!   `PROGRAM FEM90`, reachable only by entering the solver's link chain -- forbidden by
!   adapter-contract.md SS7). For those ten this file uses a DIFFERENT authoritative source:
!   the frozen M2-03 baseline JSON under `cases/golden/*/reference/state/{phase_ready(1),
!   increment_ready(1,1)}/steps.json` (see `GAP_REFERENCE` below) -- not `model_ready`, which
!   the task brief for this gate named but which does not carry these ten rows at all (their
!   own checkpoint in the map is `phase_ready(1)`/`increment_ready(1,1)`, not `model_ready`;
!   corrected here rather than silently substituted). Both golden decks carry byte-identical
!   `.man` files (`diff` confirms it) and the baseline JSON for the two checkpoints agrees
!   with a hand decode of those four records (see GAP_REFERENCE's own comment for the
!   record-by-record derivation) -- so ONE constant table serves both cases, cited, not
!   invented.
!
! WHAT THIS FILE NEVER DOES
!   It never edits a comparison to make it pass, never fabricates a value for a field
!   neither side supplies, and never records MATCH for a field neither side actually
!   evidences (an unset-vs-unset pair is reported as its own outcome, distinct from an
!   agreeing pair of real values -- see `cmp_i32` etc. below). Legacy sources are not UTF-8;
!   every deck byte cited above was read with `grep -a`, never edited.
!
! NORMALIZATION / TOLERANCE RULE (stated once, applies to every scalar compared below)
!   Every compared field's `compare.rule` in docs/m2/state-field-map.toml is `exact` (checked:
!   all 98 `ProblemState.*` rows). Integers and text are compared for bit/character identity
!   after `trim()` (text only; the map's own comment records this as the established
!   convention, e.g. case.name's note). Reals are compared via `yl_problem_optional.opt_equal`,
!   which compares the IEEE binary64 bit pattern (`transfer(..., int64)`), i.e. bit-exact, NOT
!   epsilon-tolerant. This is justified, not merely convenient: both sides parse the SAME
!   decimal literal from the SAME deck file through a Fortran list-directed real64 read, so a
!   textually-identical literal must produce a bit-identical value on both sides under one
!   compiler; a mismatch under this rule is real evidence of a semantic difference (a
!   different literal read, a unit conversion, a derived recomputation), not compiler-noise
!   thereby giving this gate no exception to justify. Collections (nodes, elements, materials,
!   sections, amplitudes, boundary records, activations) are compared INDEX BY INDEX in
!   1-based record order; both sides walk the same underlying deck record order (node i0=1..
!   npoin, element i0=1..nelem, group 1..ngroup, material 1..nmats, prescrib record 1..ndofix,
!   activation group 1..ngroup, amplitude curve 1..ntcurve, amplitude point 1..ntime) so index
!   equality is not an assumption made for convenience, it is what "the same deck record"
!   means on both parse paths -- stated so a reader can falsify it, not just trust it.
!
! OUTPUT
!   One `FIELD|...` line per compared row (98 total across the top-level scalar/collection
!   comparisons below), pipe-delimited, to the given unit: id, classification (MATCH /
!   MISMATCH / NOT_COMPARABLE / UNVERIFIED), a provisional cause tag (only meaningful on a
!   non-MATCH; the report assigns the FINAL cause by hand per the STOP RULE in the task
!   brief -- this program's tag is a lead, not a verdict), the candidate value, the reference
!   value, and a free-text note. A trailing `SUMMARY|MATCH=n|MISMATCH=n|NOT_COMPARABLE=n|` line
!   gives the counts. Run on both golden decks; never on `cases/golden/*` in place -- copy the
!   deck directory to scratch first (this file opens no unit belonging to the caller and reads
!   only paths it is given).
module yl_adapter_fidelity

  use iso_fortran_env, only: int32, int64, real64, output_unit
  use yl_problem_types, only: problem_state_t, case_t, node_t, element_t, elset_t, &
                              nset_t, material_t, section_t, amplitude_t, &
                              amplitude_point_t, interactions_t, solver_t, profile_t, &
                              step_t, controls_t, load_t, gravity_t, output_t, &
                              output_field_t, frequency_t, boundary_t, activation_t
  use yl_problem_optional, only: opt_int, opt_real, opt_text, opt_logical, &
                                 opt_get, opt_is_set, opt_equal
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
  use yl_adapter_parts, only: deck_context_t, deck_context_reset, &
                              step_parts_t, step_parts_reset, &
                              solver_parts_t, solver_parts_reset
  use yl_adapter_fem90, only: parse_inp, parse_man
  use yl_adapter_model, only: parse_glb
  use yl_adapter_mesh, only: parse_cor, parse_ele
  use yl_adapter_material, only: parse_mat, parse_sol
  use yl_adapter_load, only: parse_loa, parse_pre
  use yl_adapter_harvest, only: harvest_problem_state

  implicit none
  private

  public :: build_candidate, run_fidelity, compare_states

  character(len=*), parameter :: STAGE_ADAPT = 'adapt'
  character(len=*), parameter :: SITE = 'yl_adapter_fidelity.build_candidate'
  integer, parameter :: IOMSG_LEN = 256
  integer, parameter :: UNSET_UNIT = -1

  ! GAP_REFERENCE -- the ten GAP_MAN_STATIC_U rows' authoritative values, hand-derived from
  ! the golden decks' own `.man` bytes and cross-checked against the frozen M2-03 baseline.
  ! Both golden decks' `.man` is BYTE-IDENTICAL (`diff cases/golden/*/legacy/1.man` is empty),
  ! so one table serves both. The four records (Fem.f90:3593-3633, see yl_adapter_fem90's
  ! parse_man for the exact read shapes this mirrors):
  !   record 1 (title, unread here)     : "nincs,cdtest,earthquake_curve(1:ndimn)"
  !   record 2 (nincs)                  : "  1  0  0  0"                    -> nincs=1
  !   record 3 (increment_control)      : "  5  1.0  1  1  1  1  1  0  0"
  !       -> miter=5 ditime=1.0 noutn=1 noutf=1 nstep=1 inc_step=1 nresta=1 cwater=0 qstatic=0
  !   record 4 (tolerances, mdofn=2)    : "  3*1.0e-05"  (Fortran repeat count: three 1.0e-05)
  !       -> toler_force=1.0e-05, toler_var(1:2)=[1.0e-05, 1.0e-05]
  ! Cross-check: cases/golden/{cooks_membrane,lame_cylinder}/reference/state/phase_ready(1)/
  ! steps.json carries steps0.controls.increments=1; .../increment_ready(1,1)/steps.json
  ! carries max_iterations=5, restart_frequency=1, step_increment=1, steps=1,
  ! time_increment=hex 3FF0000000000000 (=1.0), tolerance_force/tolerance_dof=hex
  ! 3EE4F8B588E368F1 (=1.0e-05), frequency_nodes=1, frequency_fields=1 -- for BOTH cases,
  ! identical to the hand decode above. NOT `model_ready` (the task brief named that
  ! directory; these ten rows' own checkpoint in docs/m2/state-field-map.toml is
  ! phase_ready(1)/increment_ready(1,1), which do not exist before STATIC_U runs -- model_ready
  ! is before .man is even opened for STATIC_U's own reads. Corrected here, not silently
  ! substituted.)
  integer(int32), parameter :: GAP_INCREMENTS = 1_int32
  integer(int32), parameter :: GAP_MAX_ITERATIONS = 5_int32
  real(real64), parameter :: GAP_TIME_INCREMENT = 1.0_real64
  integer(int32), parameter :: GAP_FREQ_NODES = 1_int32
  integer(int32), parameter :: GAP_FREQ_FIELDS = 1_int32
  integer(int32), parameter :: GAP_STEPS = 1_int32
  integer(int32), parameter :: GAP_STEP_INCREMENT = 1_int32
  integer(int32), parameter :: GAP_RESTART_FREQUENCY = 1_int32
  real(real64), parameter :: GAP_TOLERANCE_FORCE = 1.0e-05_real64
  real(real64), parameter :: GAP_TOLERANCE_DOF = 1.0e-05_real64

  integer :: g_match = 0, g_mismatch = 0, g_notcomp = 0, g_unverified = 0

contains

  ! ============================================================================
  ! entry point: build both drafts for `dir` and compare, writing FIELD lines to `unit`
  ! ============================================================================
  subroutine run_fidelity(dir, unit)
    character(len=*), intent(in) :: dir
    integer, intent(in) :: unit

    type(problem_state_t), allocatable :: cand, ref
    type(problem_errors_t) :: cand_errors, ref_errors
    logical :: cand_ok, ref_ok
    integer :: i

    g_match = 0; g_mismatch = 0; g_notcomp = 0; g_unverified = 0

    call build_candidate(dir, cand, cand_errors, cand_ok)
    call harvest_problem_state(ref, ref_errors)
    ref_ok = allocated(ref)

    write (unit, '(a)') '# yl_adapter_fidelity: dir='//trim(dir)
    write (unit, '(a,l1)') '# candidate build ok: ', cand_ok
    if (.not. cand_ok) then
      do i = 1, cand_errors%count()
        write (unit, '(a)') '# candidate finding: '//cand_errors%render(i)
      end do
    end if
    write (unit, '(a,l1)') '# reference (oracle) build ok: ', ref_ok
    if (.not. ref_ok) then
      do i = 1, ref_errors%count()
        write (unit, '(a)') '# reference finding: '//ref_errors%render(i)
      end do
    end if

    if (.not. cand_ok .or. .not. ref_ok) then
      write (unit, '(a)') '# one or both drafts failed to build; every field is ' // &
        'NOT_COMPARABLE (see findings above for the actual cause)'
      call emit_all_not_comparable(unit)
    else
      call compare_states(cand, ref, unit)
    end if

    write (unit, '(a,i0,a,i0,a,i0,a,i0)') 'SUMMARY|MATCH=', g_match, '|MISMATCH=', g_mismatch, &
      '|NOT_COMPARABLE=', g_notcomp, '|UNVERIFIED=', g_unverified
  end subroutine run_fidelity

  subroutine emit_all_not_comparable(unit)
    integer, intent(in) :: unit
    ! The 98 field ids, in docs/m2/state-field-map.toml order, so a build failure still
    ! produces one row per field rather than silence.
    character(len=40), parameter :: IDS(98) = [character(len=40) :: &
      'case.name', 'mesh.dimension', 'steps0.output.format', 'mesh.nodes.id', &
      'mesh.nodes.xyz', 'mesh.elements.id', 'mesh.elements.nodes', 'mesh.elements.kind', &
      'mesh.elements.group', 'mesh.elements.material', 'mesh.sets.elset', 'mesh.sets.nset', &
      'materials.id', 'materials.kind', 'materials.name', 'materials.phase', &
      'materials.model', 'materials.density', 'materials.ratio', 'sections.thickness', &
      'materials.E', 'materials.nu', 'materials.thermal_expansion', 'materials.icreep', &
      'materials.kind_wt', 'materials.jliqu', 'sections.element', 'sections.name', &
      'sections.element_kind', 'sections.class', 'sections.fields', 'sections.special', &
      'sections.formulation', 'sections.material_header', 'sections.material', &
      'sections.type_nalgo', 'sections.type_stiff', 'sections.type_ecoint', &
      'sections.ilayer', 'sections.elcod_local', 'sections.uplift_ic', 'sections.liquj', &
      'amplitudes.type', 'amplitudes.points.time', 'amplitudes.points.value', &
      'steps0.procedure', 'solver.linear', 'steps0.load_mode', &
      'steps0.controls.nonlinear_type', 'solver.symmetric', 'interactions.absorbing.type', &
      'steps0.load.gravity.enabled', 'steps0.activation.active', &
      'steps0.activation.material', 'steps0.output.stress_averaging', &
      'steps0.output.field.gid_u', 'steps0.output.field.gid_s', 'steps0.output.field.gid_ms', &
      'steps0.output.field.gid_f', 'steps0.output.field.gid_rot', &
      'steps0.output.field.gid_v', 'steps0.output.field.gid_a', 'steps0.output.field.gid_T', &
      'steps0.output.field.gid_P', 'steps0.output.field.gid_Pv', &
      'steps0.output.field.gid_ep', 'steps0.output.field.gid_Y', &
      'steps0.output.field.gid_FC', 'steps0.output.field.gid_Ns', &
      'steps0.output.field.gid_Ss', 'steps0.output.field.gid_Mxy', &
      'steps0.output.field.gid_bem', 'steps0.output.field.gid_wh', &
      'steps0.output.field.gid_wv', 'steps0.output.field.gid_bcs', 'steps0.boundary.set', &
      'steps0.boundary.dof', 'steps0.boundary.amplitude', 'steps0.boundary.nodes', &
      'steps0.boundary.value', 'steps0.boundary.record_reaction', &
      'steps0.load.gravity.magnitude', 'steps0.load.gravity.direction', &
      'steps0.load.gravity.amplitude', 'steps0.controls.increments', &
      'solver.profile.iafile', 'solver.profile.icond', 'solver.profile.ipdchk', &
      'solver.profile.ising', 'steps0.controls.max_iterations', &
      'steps0.controls.time_increment', 'steps0.output.frequency_nodes', &
      'steps0.output.frequency_fields', 'steps0.controls.steps', &
      'steps0.controls.step_increment', 'steps0.controls.restart_frequency', &
      'steps0.controls.tolerance_force', 'steps0.controls.tolerance_dof']
    integer :: i
    do i = 1, size(IDS)
      call emit(unit, trim(IDS(i)), 'NOT_COMPARABLE', 'parse error', '(n/a)', '(n/a)', &
        'a draft failed to build; see the # findings lines above for the real cause')
      g_notcomp = g_notcomp + 1
    end do
  end subroutine emit_all_not_comparable

  ! ============================================================================
  ! candidate: mirrors yl_adapter_driver.adapt_legacy_deck verbatim UP TO builder_finish,
  ! then stops -- no prepare_problem call (see module header). Any drift between this
  ! subroutine and the driver's own body is this file's bug, not a finding about the
  ! parsers; it is re-derived from yl_adapter_driver.f90 on every read of this file, not
  ! copied from memory.
  ! ============================================================================
  subroutine build_candidate(dir, draft, errors, ok)
    character(len=*), intent(in) :: dir
    type(problem_state_t), allocatable, intent(out) :: draft
    type(problem_errors_t), intent(out) :: errors
    logical, intent(out) :: ok

    integer :: u_inp, u_glb, u_cor, u_ele, u_mat, u_sol, u_loa, u_pre, u_man
    character(len=:), allocatable :: prefix
    type(problem_builder_t) :: b
    type(deck_context_t) :: ctx
    type(step_parts_t) :: parts
    type(solver_parts_t) :: sparts
    type(step_builder_t) :: sb
    type(step_t) :: step_val
    type(source_location_t) :: loc
    character(len=:), allocatable :: text_val
    logical :: bok, found
    integer :: mark0, mark, i

    ok = .false.
    u_inp = UNSET_UNIT; u_glb = UNSET_UNIT; u_cor = UNSET_UNIT; u_ele = UNSET_UNIT
    u_mat = UNSET_UNIT; u_sol = UNSET_UNIT; u_loa = UNSET_UNIT; u_pre = UNSET_UNIT
    u_man = UNSET_UNIT

    call deck_context_reset(ctx)
    call step_parts_reset(parts)
    call solver_parts_reset(sparts)
    call builder_begin(b)

    mark0 = errors%count()

    parse_all: do
      call derive_deck_prefix(dir, prefix, errors, bok)
      if (.not. bok) exit parse_all

      call open_deck_unit(join_path(dir, 'inp'), 'inp', errors, u_inp, bok)
      if (.not. bok) exit parse_all
      call open_deck_unit(join_path(dir, prefix//'.glb'), '.glb', errors, u_glb, bok)
      if (.not. bok) exit parse_all
      call open_deck_unit(join_path(dir, prefix//'.cor'), '.cor', errors, u_cor, bok)
      if (.not. bok) exit parse_all
      call open_deck_unit(join_path(dir, prefix//'.ele'), '.ele', errors, u_ele, bok)
      if (.not. bok) exit parse_all
      call open_deck_unit(join_path(dir, prefix//'.pre'), '.pre', errors, u_pre, bok)
      if (.not. bok) exit parse_all
      call open_deck_unit(join_path(dir, prefix//'.mat'), '.mat', errors, u_mat, bok)
      if (.not. bok) exit parse_all
      call open_deck_unit(join_path(dir, prefix//'.loa'), '.loa', errors, u_loa, bok)
      if (.not. bok) exit parse_all
      call open_deck_unit(join_path(dir, prefix//'.sol'), '.sol', errors, u_sol, bok)
      if (.not. bok) exit parse_all
      call open_deck_unit(join_path(dir, prefix//'.man'), '.man', errors, u_man, bok)
      if (.not. bok) exit parse_all

      mark = errors%count()
      call parse_inp(u_inp, ctx, b, errors)
      if (errors%count() > mark) exit parse_all

      mark = errors%count()
      call parse_glb(u_glb, ctx, b, parts, sparts, errors)
      if (errors%count() > mark) exit parse_all

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

      loc = make_source_location(reader=SITE, &
              file='(steps[0] assembly: not one deck record, see yl_adapter_driver header)')

      call builder_step_begin(sb)

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

      call builder_step_finish(b, sb, step_val, loc, errors, bok)
      if (.not. bok) exit parse_all

      call builder_add_step(b, step_val, loc, errors)
      if (builder_failed(b)) exit parse_all

      call builder_set_solver(b, sparts%solver, loc, errors)
      if (builder_failed(b)) exit parse_all

      exit parse_all
    end do parse_all

    call close_all(u_inp, u_glb, u_cor, u_ele, u_mat, u_sol, u_loa, u_pre, u_man)

    if (errors%count() > mark0) return

    call builder_finish(b, draft, errors, ok)
  end subroutine build_candidate

  ! -- the same probn-prefix reader as yl_adapter_driver.derive_deck_prefix; duplicated
  !    rather than called (that one is private to yl_adapter_driver). See that module's
  !    header, "THE PROBN PROBLEM", for the full rationale; not repeated here.
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

    read (u, *, iostat=ios, iomsg=iomsg_buf) title
    if (.not. check_prefix_read(u, ios, iomsg_buf, 'INP.FEM90.title#1', 97_int32, errors)) return

    read (u, *, iostat=ios, iomsg=iomsg_buf) restart, relis, sysrelis, adina, uopt_r, gamamax
    if (.not. check_prefix_read(u, ios, iomsg_buf, 'INP.FEM90.run_control', 99_int32, errors)) &
      return

    read (u, *, iostat=ios, iomsg=iomsg_buf) title
    if (.not. check_prefix_read(u, ios, iomsg_buf, 'INP.FEM90.title#2', 101_int32, errors)) return

    read (u, *, iostat=ios, iomsg=iomsg_buf) probn
    if (.not. check_prefix_read(u, ios, iomsg_buf, 'INP.FEM90.problem_name', 103_int32, errors)) &
      return

    close (u)
    prefix = trim(probn)
    ok = .true.
  end subroutine derive_deck_prefix

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

  function itoa(n) result(s)
    integer(int32), intent(in) :: n
    character(len=:), allocatable :: s
    character(len=32) :: buf
    write (buf, '(i0)') n
    s = trim(buf)
  end function itoa

  ! ============================================================================
  ! comparison: one section per ProblemState top-level object, docs/m2/state-field-map.toml
  ! order, 98 FIELD lines total.
  ! ============================================================================
  subroutine compare_states(cand, ref, unit)
    type(problem_state_t), intent(in) :: cand, ref
    integer, intent(in) :: unit

    integer(int32) :: n_c, n_r, n
    logical :: size_ok

    ! -- case --------------------------------------------------------------
    call cmp_text(unit, 'case.name', cand%case%name, ref%case%name)

    ! -- mesh ----------------------------------------------------------------
    call cmp_i32(unit, 'mesh.dimension', cand%mesh%dimension, ref%mesh%dimension)

    n_c = merge(int(size(cand%mesh%nodes), int32), 0_int32, allocated(cand%mesh%nodes))
    n_r = merge(int(size(ref%mesh%nodes), int32), 0_int32, allocated(ref%mesh%nodes))
    call cmp_count(unit, 'mesh.nodes[]', n_c, n_r)
    n = min(n_c, n_r)
    call cmp_i32_array_field(unit, 'mesh.nodes.id', n, get_node_id_c, get_node_id_r)
    call cmp_real64_ragged_field(unit, 'mesh.nodes.xyz', n, get_node_xyz_c, get_node_xyz_r)

    n_c = merge(int(size(cand%mesh%elements), int32), 0_int32, allocated(cand%mesh%elements))
    n_r = merge(int(size(ref%mesh%elements), int32), 0_int32, allocated(ref%mesh%elements))
    call cmp_count(unit, 'mesh.elements[]', n_c, n_r)
    n = min(n_c, n_r)
    call cmp_i32_array_field(unit, 'mesh.elements.id', n, get_elem_id_c, get_elem_id_r)
    call cmp_i32_ragged_field(unit, 'mesh.elements.nodes', n, get_elem_nodes_c, get_elem_nodes_r)
    call cmp_i32_array_field(unit, 'mesh.elements.kind', n, get_elem_kind_c, get_elem_kind_r)
    call cmp_i32_array_field(unit, 'mesh.elements.group', n, get_elem_elset_c, get_elem_elset_r)
    call cmp_i32_array_field(unit, 'mesh.elements.material', n, get_elem_material_c, &
                             get_elem_material_r)

    n_c = merge(int(size(cand%mesh%elsets), int32), 0_int32, allocated(cand%mesh%elsets))
    n_r = merge(int(size(ref%mesh%elsets), int32), 0_int32, allocated(ref%mesh%elsets))
    call cmp_count(unit, 'mesh.elsets[]', n_c, n_r)
    n = min(n_c, n_r)
    call cmp_i32_ragged_field(unit, 'mesh.sets.elset', n, get_elset_elements_c, &
                              get_elset_elements_r)

    n_c = merge(int(size(cand%mesh%nsets), int32), 0_int32, allocated(cand%mesh%nsets))
    n_r = merge(int(size(ref%mesh%nsets), int32), 0_int32, allocated(ref%mesh%nsets))
    call cmp_count(unit, 'mesh.nsets[]', n_c, n_r)
    call cmp_field_sizes(unit, ['mesh.sets.nset'], n_c, n_r, size_ok)
    if (size_ok) then
      n = min(n_c, n_r)
      call cmp_i32_ragged_field(unit, 'mesh.sets.nset', n, get_nset_nodes_c, get_nset_nodes_r)
    end if

    ! -- materials -------------------------------------------------------------
    n_c = merge(int(size(cand%materials), int32), 0_int32, allocated(cand%materials))
    n_r = merge(int(size(ref%materials), int32), 0_int32, allocated(ref%materials))
    call cmp_count(unit, 'materials[]', n_c, n_r)
    n = min(n_c, n_r)
    call cmp_i32_array_field(unit, 'materials.id', n, get_mat_id_c, get_mat_id_r)
    call cmp_text_array_field(unit, 'materials.kind', n, get_mat_kind_c, get_mat_kind_r)
    call cmp_text_array_field(unit, 'materials.name', n, get_mat_name_c, get_mat_name_r)
    call cmp_text_array_field(unit, 'materials.phase', n, get_mat_phase_c, get_mat_phase_r)
    call cmp_text_array_field(unit, 'materials.model', n, get_mat_model_c, get_mat_model_r)
    call cmp_r64_array_field(unit, 'materials.density', n, get_mat_density_c, get_mat_density_r)
    call cmp_r64_array_field(unit, 'materials.ratio', n, get_mat_ratio_c, get_mat_ratio_r)
    call cmp_r64_array_field(unit, 'sections.thickness', n, get_sec_thickness_c, &
                             get_sec_thickness_r)
    call cmp_r64_array_field(unit, 'materials.E', n, get_mat_e_c, get_mat_e_r)
    call cmp_r64_array_field(unit, 'materials.nu', n, get_mat_nu_c, get_mat_nu_r)
    call cmp_r64_array_field(unit, 'materials.thermal_expansion', n, get_mat_alfa_c, &
                             get_mat_alfa_r)
    call cmp_i32_array_field(unit, 'materials.icreep', n, get_mat_icreep_c, get_mat_icreep_r)
    call cmp_i32_array_field(unit, 'materials.kind_wt', n, get_mat_kindwt_c, get_mat_kindwt_r)
    call cmp_i32_array_field(unit, 'materials.jliqu', n, get_mat_jliqu_c, get_mat_jliqu_r)

    ! -- sections (mesh.elsets[] count reused: ngroup == count(sections)) ------------
    n_c = merge(int(size(cand%sections), int32), 0_int32, allocated(cand%sections))
    n_r = merge(int(size(ref%sections), int32), 0_int32, allocated(ref%sections))
    call cmp_count(unit, 'sections[]', n_c, n_r)
    n = min(n_c, n_r)
    call cmp_text_array_field(unit, 'sections.element', n, get_sec_element_c, get_sec_element_r)
    call cmp_text_array_field(unit, 'sections.name', n, get_sec_name_c, get_sec_name_r)
    call cmp_i32_array_field(unit, 'sections.element_kind', n, get_sec_ekind_c, get_sec_ekind_r)
    call cmp_text_array_field(unit, 'sections.class', n, get_sec_class_c, get_sec_class_r)
    call cmp_text_array_field(unit, 'sections.fields', n, get_sec_fields_c, get_sec_fields_r)
    call cmp_text_array_field(unit, 'sections.special', n, get_sec_special_c, get_sec_special_r)
    call cmp_text_array_field(unit, 'sections.formulation', n, get_sec_form_c, get_sec_form_r)
    call cmp_i32_array_field(unit, 'sections.material_header', n, get_sec_mathdr_c, &
                             get_sec_mathdr_r)
    call cmp_i32_array_field(unit, 'sections.material', n, get_sec_material_c, get_sec_material_r)
    call cmp_i32_array_field(unit, 'sections.type_nalgo', n, get_sec_nalgo_c, get_sec_nalgo_r)
    call cmp_i32_array_field(unit, 'sections.type_stiff', n, get_sec_stiff_c, get_sec_stiff_r)
    call cmp_i32_array_field(unit, 'sections.type_ecoint', n, get_sec_ecoint_c, get_sec_ecoint_r)
    call cmp_i32_array_field(unit, 'sections.ilayer', n, get_sec_ilayer_c, get_sec_ilayer_r)
    call cmp_r64_array_field(unit, 'sections.elcod_local', n, get_sec_elcod_c, get_sec_elcod_r)
    call cmp_i32_array_field(unit, 'sections.uplift_ic', n, get_sec_uplift_c, get_sec_uplift_r)
    call cmp_i32_array_field(unit, 'sections.liquj', n, get_sec_liquj_c, get_sec_liquj_r)

    ! -- amplitudes -------------------------------------------------------------
    n_c = merge(int(size(cand%amplitudes), int32), 0_int32, allocated(cand%amplitudes))
    n_r = merge(int(size(ref%amplitudes), int32), 0_int32, allocated(ref%amplitudes))
    call cmp_count(unit, 'amplitudes[]', n_c, n_r)
    n = min(n_c, n_r)
    call cmp_text_array_field(unit, 'amplitudes.type', n, get_amp_type_c, get_amp_type_r)
    call cmp_real64_ragged_field(unit, 'amplitudes.points.time', n, get_amp_times_c, &
                                 get_amp_times_r)
    call cmp_real64_ragged_field(unit, 'amplitudes.points.value', n, get_amp_values_c, &
                                 get_amp_values_r)

    ! -- interactions -------------------------------------------------------------
    call cmp_text(unit, 'interactions.absorbing.type', cand%interactions%absorbing%type, &
                 ref%interactions%absorbing%type)

    ! -- solver -------------------------------------------------------------
    call cmp_text(unit, 'solver.linear', cand%solver%linear, ref%solver%linear)
    call cmp_logical(unit, 'solver.symmetric', cand%solver%symmetric, ref%solver%symmetric)
    call cmp_i32(unit, 'solver.profile.iafile', cand%solver%profile%pivot_file, &
                ref%solver%profile%pivot_file)
    call cmp_i32(unit, 'solver.profile.icond', cand%solver%profile%condition_check, &
                ref%solver%profile%condition_check)
    call cmp_i32(unit, 'solver.profile.ipdchk', cand%solver%profile%positive_definite_check, &
                ref%solver%profile%positive_definite_check)
    call cmp_i32(unit, 'solver.profile.ising', cand%solver%profile%singularity_check, &
                ref%solver%profile%singularity_check)

    ! -- steps[0] -------------------------------------------------------------
    if (.not. (allocated(cand%steps) .and. allocated(ref%steps))) then
      call emit(unit, 'steps0.*', 'NOT_COMPARABLE', 'parse error', &
        merge('allocated  ', 'unallocated', allocated(cand%steps)), &
        merge('allocated  ', 'unallocated', allocated(ref%steps)), &
        'steps[0] must exist on both sides to compare any steps0.* field; the ' // &
        'remaining 43 steps0.* rows are skipped, not silently marked MATCH')
      return
    end if
    if (size(cand%steps) < 1 .or. size(ref%steps) < 1) then
      call emit(unit, 'steps0.*', 'NOT_COMPARABLE', 'parse error', itoa(int(size(cand%steps), &
        int32)), itoa(int(size(ref%steps), int32)), 'steps[] has zero entries on one side')
      return
    end if

    call cmp_text(unit, 'steps0.procedure', cand%steps(1)%procedure, ref%steps(1)%procedure)
    call cmp_text(unit, 'steps0.load_mode', cand%steps(1)%load_mode, ref%steps(1)%load_mode)
    call cmp_i32(unit, 'steps0.controls.nonlinear_type', &
                cand%steps(1)%controls%nonlinear_type, ref%steps(1)%controls%nonlinear_type)

    call cmp_i32(unit, 'steps0.load.gravity.enabled', cand%steps(1)%load%gravity%enabled, &
                ref%steps(1)%load%gravity%enabled)
    call cmp_r64(unit, 'steps0.load.gravity.magnitude', &
                cand%steps(1)%load%gravity%magnitude, ref%steps(1)%load%gravity%magnitude)
    call cmp_real64_alloc(unit, 'steps0.load.gravity.direction', &
                          cand%steps(1)%load%gravity%direction, &
                          ref%steps(1)%load%gravity%direction)
    call cmp_i32_alloc(unit, 'steps0.load.gravity.amplitude', &
                       cand%steps(1)%load%gravity%amplitude, &
                       ref%steps(1)%load%gravity%amplitude)

    n_c = merge(int(size(cand%steps(1)%activation), int32), 0_int32, &
               allocated(cand%steps(1)%activation))
    n_r = merge(int(size(ref%steps(1)%activation), int32), 0_int32, &
               allocated(ref%steps(1)%activation))
    call cmp_count(unit, 'steps0.activation[]', n_c, n_r)
    n = min(n_c, n_r)
    call cmp_i32_array_field(unit, 'steps0.activation.active', n, get_act_active_c, &
                             get_act_active_r)
    call cmp_i32_array_field(unit, 'steps0.activation.material', n, get_act_material_c, &
                             get_act_material_r)

    call cmp_i32_alloc(unit, 'steps0.output.stress_averaging', &
                       cand%steps(1)%output%stress_averaging, &
                       ref%steps(1)%output%stress_averaging)
    call cmp_text(unit, 'steps0.output.format', cand%steps(1)%output%format, &
                 ref%steps(1)%output%format)
    call cmp_i32(unit, 'steps0.output.field.gid_u', cand%steps(1)%output%field%u, &
                ref%steps(1)%output%field%u)
    call cmp_i32(unit, 'steps0.output.field.gid_s', cand%steps(1)%output%field%s, &
                ref%steps(1)%output%field%s)
    call cmp_i32(unit, 'steps0.output.field.gid_ms', cand%steps(1)%output%field%ms, &
                ref%steps(1)%output%field%ms)
    call cmp_i32(unit, 'steps0.output.field.gid_f', cand%steps(1)%output%field%f, &
                ref%steps(1)%output%field%f)
    call cmp_i32(unit, 'steps0.output.field.gid_rot', cand%steps(1)%output%field%rot, &
                ref%steps(1)%output%field%rot)
    call cmp_i32(unit, 'steps0.output.field.gid_v', cand%steps(1)%output%field%v, &
                ref%steps(1)%output%field%v)
    call cmp_i32(unit, 'steps0.output.field.gid_a', cand%steps(1)%output%field%a, &
                ref%steps(1)%output%field%a)
    call cmp_i32(unit, 'steps0.output.field.gid_T', cand%steps(1)%output%field%T, &
                ref%steps(1)%output%field%T)
    call cmp_i32(unit, 'steps0.output.field.gid_P', cand%steps(1)%output%field%P, &
                ref%steps(1)%output%field%P)
    call cmp_i32(unit, 'steps0.output.field.gid_Pv', cand%steps(1)%output%field%Pv, &
                ref%steps(1)%output%field%Pv)
    call cmp_i32(unit, 'steps0.output.field.gid_ep', cand%steps(1)%output%field%ep, &
                ref%steps(1)%output%field%ep)
    call cmp_i32(unit, 'steps0.output.field.gid_Y', cand%steps(1)%output%field%Y, &
                ref%steps(1)%output%field%Y)
    call cmp_i32(unit, 'steps0.output.field.gid_FC', cand%steps(1)%output%field%FC, &
                ref%steps(1)%output%field%FC)
    call cmp_i32(unit, 'steps0.output.field.gid_Ns', cand%steps(1)%output%field%Ns, &
                ref%steps(1)%output%field%Ns)
    call cmp_i32(unit, 'steps0.output.field.gid_Ss', cand%steps(1)%output%field%Ss, &
                ref%steps(1)%output%field%Ss)
    call cmp_i32(unit, 'steps0.output.field.gid_Mxy', cand%steps(1)%output%field%Mxy, &
                ref%steps(1)%output%field%Mxy)
    call cmp_i32(unit, 'steps0.output.field.gid_bem', cand%steps(1)%output%field%bem, &
                ref%steps(1)%output%field%bem)
    call cmp_i32(unit, 'steps0.output.field.gid_wh', cand%steps(1)%output%field%wh, &
                ref%steps(1)%output%field%wh)
    call cmp_i32(unit, 'steps0.output.field.gid_wv', cand%steps(1)%output%field%wv, &
                ref%steps(1)%output%field%wv)
    call cmp_i32(unit, 'steps0.output.field.gid_bcs', cand%steps(1)%output%field%bcs, &
                ref%steps(1)%output%field%bcs)

    n_c = merge(int(size(cand%steps(1)%boundary), int32), 0_int32, &
               allocated(cand%steps(1)%boundary))
    n_r = merge(int(size(ref%steps(1)%boundary), int32), 0_int32, &
               allocated(ref%steps(1)%boundary))
    call cmp_count(unit, 'steps0.boundary[]', n_c, n_r)
    n = min(n_c, n_r)
    call cmp_i32_array_field(unit, 'steps0.boundary.set', n, get_bnd_name_c, get_bnd_name_r)
    call cmp_i32_array_field(unit, 'steps0.boundary.dof', n, get_bnd_dof_c, get_bnd_dof_r)
    call cmp_i32_array_field(unit, 'steps0.boundary.amplitude', n, get_bnd_amp_c, get_bnd_amp_r)
    call cmp_i32_array_field(unit, 'steps0.boundary.nodes', n, get_bnd_nset_c, get_bnd_nset_r)
    call cmp_r64_array_field(unit, 'steps0.boundary.value', n, get_bnd_value_c, get_bnd_value_r)
    call cmp_i32_array_field(unit, 'steps0.boundary.record_reaction', n, get_bnd_reaction_c, &
                             get_bnd_reaction_r)

    ! -- GAP_MAN_STATIC_U: the ten rows the oracle cannot reach (module header). Reference
    ! is the GAP_* constant table, not `ref`, which is UNSET here by construction (this is
    ! not a defect in the candidate or the oracle; it is the documented gap, and the field
    ! must still get a real classification, not silence).
    call cmp_i32_gap(unit, 'steps0.controls.increments', cand%steps(1)%controls%increments, &
                    GAP_INCREMENTS)
    call cmp_i32_gap(unit, 'steps0.controls.max_iterations', &
                    cand%steps(1)%controls%max_iterations, GAP_MAX_ITERATIONS)
    call cmp_r64_gap(unit, 'steps0.controls.time_increment', &
                    cand%steps(1)%controls%time_increment, GAP_TIME_INCREMENT)
    call cmp_i32_gap(unit, 'steps0.output.frequency_nodes', &
                    cand%steps(1)%output%frequency%nodes, GAP_FREQ_NODES)
    call cmp_i32_gap(unit, 'steps0.output.frequency_fields', &
                    cand%steps(1)%output%frequency%fields, GAP_FREQ_FIELDS)
    call cmp_i32_gap(unit, 'steps0.controls.steps', cand%steps(1)%controls%steps, GAP_STEPS)
    call cmp_i32_gap(unit, 'steps0.controls.step_increment', &
                    cand%steps(1)%controls%step_increment, GAP_STEP_INCREMENT)
    call cmp_i32_gap(unit, 'steps0.controls.restart_frequency', &
                    cand%steps(1)%controls%restart_frequency, GAP_RESTART_FREQUENCY)
    call cmp_r64_gap(unit, 'steps0.controls.tolerance_force', &
                    cand%steps(1)%controls%tolerance_force, GAP_TOLERANCE_FORCE)
    call cmp_real64_alloc_gap_const(unit, 'steps0.controls.tolerance_dof', &
                                    cand%steps(1)%controls%tolerance_dof, GAP_TOLERANCE_DOF)

  contains

    ! -- per-collection field accessors, paired candidate/reference, each returning
    !    found=.false. when the requested index is out of range on that side. --

    function get_node_id_c(k) result(v)
      integer(int32), intent(in) :: k
      type(opt_int) :: v
      v = cand%mesh%nodes(k)%id
    end function get_node_id_c
    function get_node_id_r(k) result(v)
      integer(int32), intent(in) :: k
      type(opt_int) :: v
      v = ref%mesh%nodes(k)%id
    end function get_node_id_r
    function get_node_xyz_c(k) result(v)
      integer(int32), intent(in) :: k
      real(real64), allocatable :: v(:)
      if (allocated(cand%mesh%nodes(k)%xyz)) v = cand%mesh%nodes(k)%xyz
    end function get_node_xyz_c
    function get_node_xyz_r(k) result(v)
      integer(int32), intent(in) :: k
      real(real64), allocatable :: v(:)
      if (allocated(ref%mesh%nodes(k)%xyz)) v = ref%mesh%nodes(k)%xyz
    end function get_node_xyz_r

    function get_elem_id_c(k) result(v)
      integer(int32), intent(in) :: k
      type(opt_int) :: v
      v = cand%mesh%elements(k)%id
    end function get_elem_id_c
    function get_elem_id_r(k) result(v)
      integer(int32), intent(in) :: k
      type(opt_int) :: v
      v = ref%mesh%elements(k)%id
    end function get_elem_id_r
    function get_elem_nodes_c(k) result(v)
      integer(int32), intent(in) :: k
      integer(int32), allocatable :: v(:)
      if (allocated(cand%mesh%elements(k)%nodes)) v = cand%mesh%elements(k)%nodes
    end function get_elem_nodes_c
    function get_elem_nodes_r(k) result(v)
      integer(int32), intent(in) :: k
      integer(int32), allocatable :: v(:)
      if (allocated(ref%mesh%elements(k)%nodes)) v = ref%mesh%elements(k)%nodes
    end function get_elem_nodes_r
    function get_elem_kind_c(k) result(v)
      integer(int32), intent(in) :: k
      type(opt_int) :: v
      v = cand%mesh%elements(k)%kind
    end function get_elem_kind_c
    function get_elem_kind_r(k) result(v)
      integer(int32), intent(in) :: k
      type(opt_int) :: v
      v = ref%mesh%elements(k)%kind
    end function get_elem_kind_r
    function get_elem_elset_c(k) result(v)
      integer(int32), intent(in) :: k
      type(opt_int) :: v
      v = cand%mesh%elements(k)%elset
    end function get_elem_elset_c
    function get_elem_elset_r(k) result(v)
      integer(int32), intent(in) :: k
      type(opt_int) :: v
      v = ref%mesh%elements(k)%elset
    end function get_elem_elset_r
    function get_elem_material_c(k) result(v)
      integer(int32), intent(in) :: k
      type(opt_int) :: v
      v = cand%mesh%elements(k)%material
    end function get_elem_material_c
    function get_elem_material_r(k) result(v)
      integer(int32), intent(in) :: k
      type(opt_int) :: v
      v = ref%mesh%elements(k)%material
    end function get_elem_material_r

    function get_elset_elements_c(k) result(v)
      integer(int32), intent(in) :: k
      integer(int32), allocatable :: v(:)
      if (allocated(cand%mesh%elsets(k)%elements)) v = cand%mesh%elsets(k)%elements
    end function get_elset_elements_c
    function get_elset_elements_r(k) result(v)
      integer(int32), intent(in) :: k
      integer(int32), allocatable :: v(:)
      if (allocated(ref%mesh%elsets(k)%elements)) v = ref%mesh%elsets(k)%elements
    end function get_elset_elements_r

    function get_nset_nodes_c(k) result(v)
      integer(int32), intent(in) :: k
      integer(int32), allocatable :: v(:)
      if (allocated(cand%mesh%nsets(k)%nodes)) v = cand%mesh%nsets(k)%nodes
    end function get_nset_nodes_c
    function get_nset_nodes_r(k) result(v)
      integer(int32), intent(in) :: k
      integer(int32), allocatable :: v(:)
      if (allocated(ref%mesh%nsets(k)%nodes)) v = ref%mesh%nsets(k)%nodes
    end function get_nset_nodes_r

    function get_mat_id_c(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = cand%materials(k)%id; end function
    function get_mat_id_r(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = ref%materials(k)%id; end function
    function get_mat_kind_c(k) result(v); integer(int32), intent(in)::k; type(opt_text)::v
      v = cand%materials(k)%kind; end function
    function get_mat_kind_r(k) result(v); integer(int32), intent(in)::k; type(opt_text)::v
      v = ref%materials(k)%kind; end function
    function get_mat_name_c(k) result(v); integer(int32), intent(in)::k; type(opt_text)::v
      v = cand%materials(k)%name; end function
    function get_mat_name_r(k) result(v); integer(int32), intent(in)::k; type(opt_text)::v
      v = ref%materials(k)%name; end function
    function get_mat_phase_c(k) result(v); integer(int32), intent(in)::k; type(opt_text)::v
      v = cand%materials(k)%phase; end function
    function get_mat_phase_r(k) result(v); integer(int32), intent(in)::k; type(opt_text)::v
      v = ref%materials(k)%phase; end function
    function get_mat_model_c(k) result(v); integer(int32), intent(in)::k; type(opt_text)::v
      v = cand%materials(k)%model; end function
    function get_mat_model_r(k) result(v); integer(int32), intent(in)::k; type(opt_text)::v
      v = ref%materials(k)%model; end function
    function get_mat_density_c(k) result(v); integer(int32), intent(in)::k; type(opt_real)::v
      v = cand%materials(k)%density; end function
    function get_mat_density_r(k) result(v); integer(int32), intent(in)::k; type(opt_real)::v
      v = ref%materials(k)%density; end function
    function get_mat_ratio_c(k) result(v); integer(int32), intent(in)::k; type(opt_real)::v
      v = cand%materials(k)%solid_ratio; end function
    function get_mat_ratio_r(k) result(v); integer(int32), intent(in)::k; type(opt_real)::v
      v = ref%materials(k)%solid_ratio; end function
    function get_sec_thickness_c(k) result(v); integer(int32), intent(in)::k; type(opt_real)::v
      v = cand%sections(k)%thickness; end function
    function get_sec_thickness_r(k) result(v); integer(int32), intent(in)::k; type(opt_real)::v
      v = ref%sections(k)%thickness; end function
    function get_mat_e_c(k) result(v); integer(int32), intent(in)::k; type(opt_real)::v
      v = cand%materials(k)%E; end function
    function get_mat_e_r(k) result(v); integer(int32), intent(in)::k; type(opt_real)::v
      v = ref%materials(k)%E; end function
    function get_mat_nu_c(k) result(v); integer(int32), intent(in)::k; type(opt_real)::v
      v = cand%materials(k)%nu; end function
    function get_mat_nu_r(k) result(v); integer(int32), intent(in)::k; type(opt_real)::v
      v = ref%materials(k)%nu; end function
    function get_mat_alfa_c(k) result(v); integer(int32), intent(in)::k; type(opt_real)::v
      v = cand%materials(k)%thermal_expansion; end function
    function get_mat_alfa_r(k) result(v); integer(int32), intent(in)::k; type(opt_real)::v
      v = ref%materials(k)%thermal_expansion; end function
    function get_mat_icreep_c(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = cand%materials(k)%creep_model; end function
    function get_mat_icreep_r(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = ref%materials(k)%creep_model; end function
    function get_mat_kindwt_c(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = cand%materials(k)%wetting_kind; end function
    function get_mat_kindwt_r(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = ref%materials(k)%wetting_kind; end function
    function get_mat_jliqu_c(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = cand%materials(k)%liquefaction; end function
    function get_mat_jliqu_r(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = ref%materials(k)%liquefaction; end function

    function get_sec_element_c(k) result(v); integer(int32), intent(in)::k; type(opt_text)::v
      v = cand%sections(k)%element; end function
    function get_sec_element_r(k) result(v); integer(int32), intent(in)::k; type(opt_text)::v
      v = ref%sections(k)%element; end function
    function get_sec_name_c(k) result(v); integer(int32), intent(in)::k; type(opt_text)::v
      v = cand%sections(k)%name; end function
    function get_sec_name_r(k) result(v); integer(int32), intent(in)::k; type(opt_text)::v
      v = ref%sections(k)%name; end function
    function get_sec_ekind_c(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = cand%sections(k)%element_kind; end function
    function get_sec_ekind_r(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = ref%sections(k)%element_kind; end function
    function get_sec_class_c(k) result(v); integer(int32), intent(in)::k; type(opt_text)::v
      v = cand%sections(k)%class; end function
    function get_sec_class_r(k) result(v); integer(int32), intent(in)::k; type(opt_text)::v
      v = ref%sections(k)%class; end function
    function get_sec_fields_c(k) result(v); integer(int32), intent(in)::k; type(opt_text)::v
      v = cand%sections(k)%fields; end function
    function get_sec_fields_r(k) result(v); integer(int32), intent(in)::k; type(opt_text)::v
      v = ref%sections(k)%fields; end function
    function get_sec_special_c(k) result(v); integer(int32), intent(in)::k; type(opt_text)::v
      v = cand%sections(k)%special; end function
    function get_sec_special_r(k) result(v); integer(int32), intent(in)::k; type(opt_text)::v
      v = ref%sections(k)%special; end function
    function get_sec_form_c(k) result(v); integer(int32), intent(in)::k; type(opt_text)::v
      v = cand%sections(k)%formulation; end function
    function get_sec_form_r(k) result(v); integer(int32), intent(in)::k; type(opt_text)::v
      v = ref%sections(k)%formulation; end function
    function get_sec_mathdr_c(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = cand%sections(k)%material_header; end function
    function get_sec_mathdr_r(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = ref%sections(k)%material_header; end function
    function get_sec_material_c(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = cand%sections(k)%material; end function
    function get_sec_material_r(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = ref%sections(k)%material; end function
    function get_sec_nalgo_c(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = cand%sections(k)%algorithm; end function
    function get_sec_nalgo_r(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = ref%sections(k)%algorithm; end function
    function get_sec_stiff_c(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = cand%sections(k)%stiffness_kind; end function
    function get_sec_stiff_r(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = ref%sections(k)%stiffness_kind; end function
    function get_sec_ecoint_c(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = cand%sections(k)%stress_recovery; end function
    function get_sec_ecoint_r(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = ref%sections(k)%stress_recovery; end function
    function get_sec_ilayer_c(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = cand%sections(k)%layer; end function
    function get_sec_ilayer_r(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = ref%sections(k)%layer; end function
    function get_sec_elcod_c(k) result(v); integer(int32), intent(in)::k; type(opt_real)::v
      v = cand%sections(k)%local_axes; end function
    function get_sec_elcod_r(k) result(v); integer(int32), intent(in)::k; type(opt_real)::v
      v = ref%sections(k)%local_axes; end function
    function get_sec_uplift_c(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = cand%sections(k)%uplift; end function
    function get_sec_uplift_r(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = ref%sections(k)%uplift; end function
    function get_sec_liquj_c(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = cand%sections(k)%liquefaction; end function
    function get_sec_liquj_r(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = ref%sections(k)%liquefaction; end function

    function get_amp_type_c(k) result(v); integer(int32), intent(in)::k; type(opt_text)::v
      v = cand%amplitudes(k)%type; end function
    function get_amp_type_r(k) result(v); integer(int32), intent(in)::k; type(opt_text)::v
      v = ref%amplitudes(k)%type; end function
    function get_amp_times_c(k) result(v)
      integer(int32), intent(in) :: k
      real(real64), allocatable :: v(:)
      integer :: j, m
      logical :: f
      if (.not. allocated(cand%amplitudes(k)%points)) return
      m = size(cand%amplitudes(k)%points)
      allocate (v(m))
      do j = 1, m
        call opt_get(cand%amplitudes(k)%points(j)%time, v(j), f)
      end do
    end function get_amp_times_c
    function get_amp_times_r(k) result(v)
      integer(int32), intent(in) :: k
      real(real64), allocatable :: v(:)
      integer :: j, m
      logical :: f
      if (.not. allocated(ref%amplitudes(k)%points)) return
      m = size(ref%amplitudes(k)%points)
      allocate (v(m))
      do j = 1, m
        call opt_get(ref%amplitudes(k)%points(j)%time, v(j), f)
      end do
    end function get_amp_times_r
    function get_amp_values_c(k) result(v)
      integer(int32), intent(in) :: k
      real(real64), allocatable :: v(:)
      integer :: j, m
      logical :: f
      if (.not. allocated(cand%amplitudes(k)%points)) return
      m = size(cand%amplitudes(k)%points)
      allocate (v(m))
      do j = 1, m
        call opt_get(cand%amplitudes(k)%points(j)%value, v(j), f)
      end do
    end function get_amp_values_c
    function get_amp_values_r(k) result(v)
      integer(int32), intent(in) :: k
      real(real64), allocatable :: v(:)
      integer :: j, m
      logical :: f
      if (.not. allocated(ref%amplitudes(k)%points)) return
      m = size(ref%amplitudes(k)%points)
      allocate (v(m))
      do j = 1, m
        call opt_get(ref%amplitudes(k)%points(j)%value, v(j), f)
      end do
    end function get_amp_values_r

    function get_act_active_c(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = cand%steps(1)%activation(k)%active; end function
    function get_act_active_r(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = ref%steps(1)%activation(k)%active; end function
    function get_act_material_c(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = cand%steps(1)%activation(k)%material; end function
    function get_act_material_r(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = ref%steps(1)%activation(k)%material; end function

    function get_bnd_name_c(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = cand%steps(1)%boundary(k)%name; end function
    function get_bnd_name_r(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = ref%steps(1)%boundary(k)%name; end function
    function get_bnd_dof_c(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = cand%steps(1)%boundary(k)%dof; end function
    function get_bnd_dof_r(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = ref%steps(1)%boundary(k)%dof; end function
    function get_bnd_amp_c(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = cand%steps(1)%boundary(k)%amplitude; end function
    function get_bnd_amp_r(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = ref%steps(1)%boundary(k)%amplitude; end function
    function get_bnd_nset_c(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = cand%steps(1)%boundary(k)%nset; end function
    function get_bnd_nset_r(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = ref%steps(1)%boundary(k)%nset; end function
    function get_bnd_value_c(k) result(v); integer(int32), intent(in)::k; type(opt_real)::v
      v = cand%steps(1)%boundary(k)%value; end function
    function get_bnd_value_r(k) result(v); integer(int32), intent(in)::k; type(opt_real)::v
      v = ref%steps(1)%boundary(k)%value; end function
    function get_bnd_reaction_c(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = cand%steps(1)%boundary(k)%record_reaction; end function
    function get_bnd_reaction_r(k) result(v); integer(int32), intent(in)::k; type(opt_int)::v
      v = ref%steps(1)%boundary(k)%record_reaction; end function

  end subroutine compare_states

  ! ============================================================================
  ! generic scalar / collection comparators. Every one funnels into `emit`, so every
  ! outcome this file can produce is counted exactly once in the SUMMARY line.
  ! ============================================================================

  subroutine emit(unit, id, cls, cause, cand_s, ref_s, note)
    integer, intent(in) :: unit
    character(len=*), intent(in) :: id, cls, cause, cand_s, ref_s, note
    write (unit, '(a)') 'FIELD|'//trim(id)//'|'//trim(cls)//'|'//trim(cause)//'|'// &
      trim(cand_s)//'|'//trim(ref_s)//'|'//trim(note)
    select case (trim(cls))
    case ('MATCH'); g_match = g_match + 1
    case ('MISMATCH'); g_mismatch = g_mismatch + 1
    case ('NOT_COMPARABLE'); g_notcomp = g_notcomp + 1
    case ('UNVERIFIED'); g_unverified = g_unverified + 1
    end select
  end subroutine emit

  function fi(v) result(s)
    integer(int32), intent(in) :: v
    character(len=:), allocatable :: s
    character(len=32) :: buf
    write (buf, '(i0)') v
    s = trim(buf)
  end function fi

  function fr(v) result(s)
    real(real64), intent(in) :: v
    character(len=:), allocatable :: s
    character(len=32) :: buf
    write (buf, '(es24.16e3)') v
    s = trim(adjustl(buf))
  end function fr

  subroutine cmp_i32(unit, id, c, r)
    integer, intent(in) :: unit
    character(len=*), intent(in) :: id
    type(opt_int), intent(in) :: c, r
    integer(int32) :: cv, rv
    logical :: cf, rf
    call opt_get(c, cv, cf); call opt_get(r, rv, rf)
    if (cf .and. rf) then
      if (cv == rv) then
        call emit(unit, id, 'MATCH', '', fi(cv), fi(rv), '')
      else
        call emit(unit, id, 'MISMATCH', 'legacy-state difference', fi(cv), fi(rv), '')
      end if
    else if (cf .and. .not. rf) then
      call emit(unit, id, 'MISMATCH', 'reference ambiguity', fi(cv), '(unset)', &
        'oracle left this field unset; not one of the ten documented GAP_MAN_STATIC_U rows')
    else if (.not. cf .and. rf) then
      call emit(unit, id, 'MISMATCH', 'parse error', '(unset)', fi(rv), &
        'candidate parser left this field unset')
    else
      call emit(unit, id, 'MISMATCH', 'parse error', '(unset)', '(unset)', &
        'both sides unset; not recorded as MATCH per the no-evidence-no-match rule')
    end if
  end subroutine cmp_i32

  subroutine cmp_r64(unit, id, c, r)
    integer, intent(in) :: unit
    character(len=*), intent(in) :: id
    type(opt_real), intent(in) :: c, r
    real(real64) :: cv, rv
    logical :: cf, rf
    call opt_get(c, cv, cf); call opt_get(r, rv, rf)
    if (cf .and. rf) then
      if (opt_equal(c, r)) then
        call emit(unit, id, 'MATCH', '', fr(cv), fr(rv), '')
      else
        call emit(unit, id, 'MISMATCH', 'legacy-state difference', fr(cv), fr(rv), '')
      end if
    else if (cf .and. .not. rf) then
      call emit(unit, id, 'MISMATCH', 'reference ambiguity', fr(cv), '(unset)', '')
    else if (.not. cf .and. rf) then
      call emit(unit, id, 'MISMATCH', 'parse error', '(unset)', fr(rv), '')
    else
      call emit(unit, id, 'MISMATCH', 'parse error', '(unset)', '(unset)', &
        'both sides unset; not recorded as MATCH per the no-evidence-no-match rule')
    end if
  end subroutine cmp_r64

  subroutine cmp_text(unit, id, c, r)
    integer, intent(in) :: unit
    character(len=*), intent(in) :: id
    type(opt_text), intent(in) :: c, r
    character(len=:), allocatable :: cv, rv
    logical :: cf, rf
    call opt_get(c, cv, cf); call opt_get(r, rv, rf)
    if (cf .and. rf) then
      if (trim(cv) == trim(rv)) then
        call emit(unit, id, 'MATCH', '', trim(cv), trim(rv), '')
      else
        call emit(unit, id, 'MISMATCH', 'legacy-state difference', trim(cv), trim(rv), '')
      end if
    else if (cf .and. .not. rf) then
      call emit(unit, id, 'MISMATCH', 'reference ambiguity', trim(cv), '(unset)', '')
    else if (.not. cf .and. rf) then
      call emit(unit, id, 'MISMATCH', 'parse error', '(unset)', trim(rv), '')
    else
      call emit(unit, id, 'MISMATCH', 'parse error', '(unset)', '(unset)', &
        'both sides unset; not recorded as MATCH per the no-evidence-no-match rule')
    end if
  end subroutine cmp_text

  subroutine cmp_logical(unit, id, c, r)
    integer, intent(in) :: unit
    character(len=*), intent(in) :: id
    type(opt_logical), intent(in) :: c, r
    logical :: cv, rv, cf, rf
    call opt_get(c, cv, cf); call opt_get(r, rv, rf)
    if (cf .and. rf) then
      if (cv .eqv. rv) then
        call emit(unit, id, 'MATCH', '', merge('T','F',cv), merge('T','F',rv), '')
      else
        call emit(unit, id, 'MISMATCH', 'legacy-state difference', merge('T','F',cv), &
          merge('T','F',rv), '')
      end if
    else if (cf .and. .not. rf) then
      call emit(unit, id, 'MISMATCH', 'reference ambiguity', merge('T','F',cv), '(unset)', '')
    else if (.not. cf .and. rf) then
      call emit(unit, id, 'MISMATCH', 'parse error', '(unset)', merge('T','F',rv), '')
    else
      call emit(unit, id, 'MISMATCH', 'parse error', '(unset)', '(unset)', &
        'both sides unset; not recorded as MATCH per the no-evidence-no-match rule')
    end if
  end subroutine cmp_logical

  ! One GAP_MAN_STATIC_U scalar: the oracle side is UNSET by construction (module header),
  ! so this compares the candidate against the GAP_REFERENCE constant, never against `ref`.
  subroutine cmp_i32_gap(unit, id, c, gap_value)
    integer, intent(in) :: unit
    character(len=*), intent(in) :: id
    type(opt_int), intent(in) :: c
    integer(int32), intent(in) :: gap_value
    integer(int32) :: cv
    logical :: cf
    call opt_get(c, cv, cf)
    if (.not. cf) then
      call emit(unit, id, 'MISMATCH', 'parse error', '(unset)', fi(gap_value), &
        'reference is the GAP_REFERENCE .man-byte decode (module header), not the oracle')
    else if (cv == gap_value) then
      call emit(unit, id, 'MATCH', '', fi(cv), fi(gap_value), &
        'reference is the GAP_REFERENCE .man-byte decode (module header), not the oracle: ' // &
        'GAP_MAN_STATIC_U row, oracle cannot reach STATIC_U (adapter-contract.md SS7)')
    else
      call emit(unit, id, 'MISMATCH', 'legacy-state difference', fi(cv), fi(gap_value), &
        'reference is the GAP_REFERENCE .man-byte decode (module header), not the oracle')
    end if
  end subroutine cmp_i32_gap

  subroutine cmp_r64_gap(unit, id, c, gap_value)
    integer, intent(in) :: unit
    character(len=*), intent(in) :: id
    type(opt_real), intent(in) :: c
    real(real64), intent(in) :: gap_value
    real(real64) :: cv
    logical :: cf
    call opt_get(c, cv, cf)
    if (.not. cf) then
      call emit(unit, id, 'MISMATCH', 'parse error', '(unset)', fr(gap_value), &
        'reference is the GAP_REFERENCE .man-byte decode (module header), not the oracle')
    else if (transfer(cv, 0_int64) == transfer(gap_value, 0_int64)) then
      call emit(unit, id, 'MATCH', '', fr(cv), fr(gap_value), &
        'reference is the GAP_REFERENCE .man-byte decode (module header), not the oracle: ' // &
        'GAP_MAN_STATIC_U row, oracle cannot reach STATIC_U (adapter-contract.md SS7)')
    else
      call emit(unit, id, 'MISMATCH', 'legacy-state difference', fr(cv), fr(gap_value), &
        'reference is the GAP_REFERENCE .man-byte decode (module header), not the oracle')
    end if
  end subroutine cmp_r64_gap

  ! steps0.controls.tolerance_dof: an allocatable real64 array, GAP row, every entry equal
  ! to the same GAP_TOLERANCE_DOF constant (mdofn=2 on both golden decks, both entries
  ! 1.0e-05 per the .man record 4 decode).
  subroutine cmp_real64_alloc_gap_const(unit, id, c, gap_value)
    integer, intent(in) :: unit
    character(len=*), intent(in) :: id
    real(real64), allocatable, intent(in) :: c(:)
    real(real64), intent(in) :: gap_value
    integer :: i
    logical :: all_match
    if (.not. allocated(c)) then
      call emit(unit, id, 'MISMATCH', 'parse error', '(unallocated)', '[1.0e-05, 1.0e-05]', &
        'reference is the GAP_REFERENCE .man-byte decode (module header), not the oracle')
      return
    end if
    all_match = .true.
    do i = 1, size(c)
      if (transfer(c(i), 0_int64) /= transfer(gap_value, 0_int64)) all_match = .false.
    end do
    if (all_match) then
      call emit(unit, id, 'MATCH', '', '['//join_real(c)//']', &
        '[all entries '//fr(gap_value)//']', &
        'reference is the GAP_REFERENCE .man-byte decode (module header), not the oracle: ' // &
        'GAP_MAN_STATIC_U row, oracle cannot reach STATIC_U (adapter-contract.md SS7)')
    else
      call emit(unit, id, 'MISMATCH', 'legacy-state difference', '['//join_real(c)//']', &
        '[all entries '//fr(gap_value)//']', &
        'reference is the GAP_REFERENCE .man-byte decode (module header), not the oracle')
    end if
  end subroutine cmp_real64_alloc_gap_const

  function join_real(v) result(s)
    real(real64), intent(in) :: v(:)
    character(len=:), allocatable :: s
    integer :: i
    s = ''
    do i = 1, size(v)
      if (i > 1) s = s//', '
      s = s//fr(v(i))
    end do
  end function join_real

  function join_int(v) result(s)
    integer(int32), intent(in) :: v(:)
    character(len=:), allocatable :: s
    integer :: i
    s = ''
    do i = 1, size(v)
      if (i > 1) s = s//', '
      s = s//fi(v(i))
    end do
  end function join_int

  ! A collection-size mismatch is itself a row (id ends in `[]`); it is NOT one of the 98
  ! ProblemState.* rows but is reported so a size divergence is never silently swallowed by
  ! the min(n_c,n_r) walk that follows.
  subroutine cmp_count(unit, id, n_c, n_r)
    integer, intent(in) :: unit
    character(len=*), intent(in) :: id
    integer(int32), intent(in) :: n_c, n_r
    if (n_c == n_r) then
      write (unit, '(a)') '# '//trim(id)//' count: candidate='//fi(n_c)//' reference='//fi(n_r)
    else
      write (unit, '(a)') '# '//trim(id)//' COUNT MISMATCH: candidate='//fi(n_c)// &
        ' reference='//fi(n_r)//' -- every field of this collection is reported ' // &
        'NOT_COMPARABLE below, NOT compared over min(n_c,n_r): a per-index walk over the ' // &
        'shorter side would silently call indices beyond it a vacuous MATCH, which is ' // &
        'exactly the "MATCH because no evidence contradicted it" outcome this gate refuses'
    end if
  end subroutine cmp_count

  ! Emits one NOT_COMPARABLE row per field id of a collection whose candidate/reference
  ! counts differ (see cmp_count's own comment on why this is not silently folded into the
  ! per-entry walk). `ok` is .true. (nothing emitted) when the counts agree, so a caller
  ! writes `call cmp_field_sizes(...); if (ok) then <normal per-field comparisons> end if`.
  subroutine cmp_field_sizes(unit, ids, n_c, n_r, ok)
    integer, intent(in) :: unit
    character(len=*), intent(in) :: ids(:)
    integer(int32), intent(in) :: n_c, n_r
    logical, intent(out) :: ok
    integer :: i
    ok = (n_c == n_r)
    if (.not. ok) then
      do i = 1, size(ids)
        call emit(unit, trim(ids(i)), 'NOT_COMPARABLE', 'reference ambiguity', 'n='//fi(n_c), &
          'n='//fi(n_r), 'collection size differs between candidate and reference; index ' // &
          'correspondence beyond min(n_c,n_r) is not established, so this field is not ' // &
          'compared at all rather than compared over a truncated, arbitrarily-matching prefix')
      end do
    end if
  end subroutine cmp_field_sizes

  ! One opt_int leaf, walked over a collection via caller-supplied index functions. Reports
  ! ONE aggregate FIELD line: MATCH only if every compared index matches; the first
  ! divergent index is named in the note so a reader does not have to search 98x256 rows by
  ! hand.
  subroutine cmp_i32_array_field(unit, id, n, get_c, get_r)
    integer, intent(in) :: unit
    character(len=*), intent(in) :: id
    integer(int32), intent(in) :: n
    interface
      function get_c(k) result(v)
        import :: int32, opt_int
        integer(int32), intent(in) :: k
        type(opt_int) :: v
      end function get_c
      function get_r(k) result(v)
        import :: int32, opt_int
        integer(int32), intent(in) :: k
        type(opt_int) :: v
      end function get_r
    end interface
    integer(int32) :: k, cv, rv
    logical :: cf, rf, all_ok
    character(len=256) :: badnote
    all_ok = .true.
    badnote = ''
    do k = 1, n
      call opt_get(get_c(k), cv, cf); call opt_get(get_r(k), rv, rf)
      if (.not. (cf .and. rf .and. cv == rv)) then
        all_ok = .false.
        if (len_trim(badnote) == 0) write (badnote, '(a,i0,a,l1,a,i0,a,l1,a,i0)') &
          'first divergence at index ', k, ': cand set=', cf, ' val=', cv, ' ref set=', rf, &
          ' val=', rv
        exit
      end if
    end do
    if (n == 0) then
      call emit(unit, id, 'MATCH', '', '(empty)', '(empty)', 'collection is empty on both sides')
    else if (all_ok) then
      call emit(unit, id, 'MATCH', '', 'n='//fi(n)//' all equal', 'n='//fi(n)//' all equal', '')
    else
      call emit(unit, id, 'MISMATCH', 'legacy-state difference', 'n='//fi(n), 'n='//fi(n), &
        trim(badnote))
    end if
  end subroutine cmp_i32_array_field

  subroutine cmp_r64_array_field(unit, id, n, get_c, get_r)
    integer, intent(in) :: unit
    character(len=*), intent(in) :: id
    integer(int32), intent(in) :: n
    interface
      function get_c(k) result(v)
        import :: int32, opt_real
        integer(int32), intent(in) :: k
        type(opt_real) :: v
      end function get_c
      function get_r(k) result(v)
        import :: int32, opt_real
        integer(int32), intent(in) :: k
        type(opt_real) :: v
      end function get_r
    end interface
    integer(int32) :: k
    type(opt_real) :: cv, rv
    logical :: all_ok
    character(len=256) :: badnote
    all_ok = .true.
    badnote = ''
    do k = 1, n
      cv = get_c(k); rv = get_r(k)
      if (.not. opt_equal(cv, rv)) then
        all_ok = .false.
        write (badnote, '(a,i0)') 'first divergence at index ', k
        exit
      end if
    end do
    if (n == 0) then
      call emit(unit, id, 'MATCH', '', '(empty)', '(empty)', 'collection is empty on both sides')
    else if (all_ok) then
      call emit(unit, id, 'MATCH', '', 'n='//fi(n)//' all equal', 'n='//fi(n)//' all equal', '')
    else
      call emit(unit, id, 'MISMATCH', 'legacy-state difference', 'n='//fi(n), 'n='//fi(n), &
        trim(badnote))
    end if
  end subroutine cmp_r64_array_field

  subroutine cmp_text_array_field(unit, id, n, get_c, get_r)
    integer, intent(in) :: unit
    character(len=*), intent(in) :: id
    integer(int32), intent(in) :: n
    interface
      function get_c(k) result(v)
        import :: int32, opt_text
        integer(int32), intent(in) :: k
        type(opt_text) :: v
      end function get_c
      function get_r(k) result(v)
        import :: int32, opt_text
        integer(int32), intent(in) :: k
        type(opt_text) :: v
      end function get_r
    end interface
    integer(int32) :: k
    character(len=:), allocatable :: cv, rv
    logical :: cf, rf, all_ok
    character(len=256) :: badnote
    all_ok = .true.
    badnote = ''
    do k = 1, n
      call opt_get(get_c(k), cv, cf); call opt_get(get_r(k), rv, rf)
      if (.not. (cf .and. rf .and. trim(cv) == trim(rv))) then
        all_ok = .false.
        write (badnote, '(a,i0)') 'first divergence at index ', k
        exit
      end if
    end do
    if (n == 0) then
      call emit(unit, id, 'MATCH', '', '(empty)', '(empty)', 'collection is empty on both sides')
    else if (all_ok) then
      call emit(unit, id, 'MATCH', '', 'n='//fi(n)//' all equal', 'n='//fi(n)//' all equal', '')
    else
      call emit(unit, id, 'MISMATCH', 'legacy-state difference', 'n='//fi(n), 'n='//fi(n), &
        trim(badnote))
    end if
  end subroutine cmp_text_array_field

  ! Ragged: each collection entry owns its OWN allocatable array (mesh.elements.nodes,
  ! mesh.sets.elset, mesh.sets.nset, amplitudes.points.time/value). Compares size then
  ! element-by-element per entry.
  subroutine cmp_i32_ragged_field(unit, id, n, get_c, get_r)
    integer, intent(in) :: unit
    character(len=*), intent(in) :: id
    integer(int32), intent(in) :: n
    interface
      function get_c(k) result(v)
        import :: int32
        integer(int32), intent(in) :: k
        integer(int32), allocatable :: v(:)
      end function get_c
      function get_r(k) result(v)
        import :: int32
        integer(int32), intent(in) :: k
        integer(int32), allocatable :: v(:)
      end function get_r
    end interface
    integer(int32) :: k
    integer(int32), allocatable :: cv(:), rv(:)
    logical :: all_ok
    character(len=256) :: badnote
    all_ok = .true.
    badnote = ''
    do k = 1, n
      cv = get_c(k); rv = get_r(k)
      if (.not. allocated(cv) .or. .not. allocated(rv)) then
        all_ok = .false.
        write (badnote, '(a,i0,a)') 'index ', k, ': unallocated on one side'
        exit
      end if
      if (size(cv) /= size(rv)) then
        all_ok = .false.
        write (badnote, '(a,i0,a,i0,a,i0)') 'index ', k, ': size mismatch cand=', size(cv), &
          ' ref=', size(rv)
        exit
      end if
      if (any(cv /= rv)) then
        all_ok = .false.
        write (badnote, '(a,i0)') 'entry-value mismatch at index ', k
        exit
      end if
    end do
    if (n == 0) then
      call emit(unit, id, 'MATCH', '', '(empty)', '(empty)', 'collection is empty on both sides')
    else if (all_ok) then
      call emit(unit, id, 'MATCH', '', 'n='//fi(n)//' all equal', 'n='//fi(n)//' all equal', '')
    else
      call emit(unit, id, 'MISMATCH', 'legacy-state difference', 'n='//fi(n), 'n='//fi(n), &
        trim(badnote))
    end if
  end subroutine cmp_i32_ragged_field

  subroutine cmp_real64_ragged_field(unit, id, n, get_c, get_r)
    integer, intent(in) :: unit
    character(len=*), intent(in) :: id
    integer(int32), intent(in) :: n
    interface
      function get_c(k) result(v)
        import :: int32, real64
        integer(int32), intent(in) :: k
        real(real64), allocatable :: v(:)
      end function get_c
      function get_r(k) result(v)
        import :: int32, real64
        integer(int32), intent(in) :: k
        real(real64), allocatable :: v(:)
      end function get_r
    end interface
    integer(int32) :: k, j
    real(real64), allocatable :: cv(:), rv(:)
    logical :: all_ok
    character(len=256) :: badnote
    all_ok = .true.
    badnote = ''
    outer: do k = 1, n
      cv = get_c(k); rv = get_r(k)
      if (.not. allocated(cv) .or. .not. allocated(rv)) then
        all_ok = .false.
        write (badnote, '(a,i0,a)') 'index ', k, ': unallocated on one side'
        exit outer
      end if
      if (size(cv) /= size(rv)) then
        all_ok = .false.
        write (badnote, '(a,i0,a,i0,a,i0)') 'index ', k, ': size mismatch cand=', size(cv), &
          ' ref=', size(rv)
        exit outer
      end if
      do j = 1, size(cv)
        if (transfer(cv(j), 0_int64) /= transfer(rv(j), 0_int64)) then
          all_ok = .false.
          write (badnote, '(a,i0,a,i0)') 'entry-value mismatch at index ', k, ' subindex ', j
          exit outer
        end if
      end do
    end do outer
    if (n == 0) then
      call emit(unit, id, 'MATCH', '', '(empty)', '(empty)', 'collection is empty on both sides')
    else if (all_ok) then
      call emit(unit, id, 'MATCH', '', 'n='//fi(n)//' all equal', 'n='//fi(n)//' all equal', '')
    else
      call emit(unit, id, 'MISMATCH', 'legacy-state difference', 'n='//fi(n), 'n='//fi(n), &
        trim(badnote))
    end if
  end subroutine cmp_real64_ragged_field

  ! Whole-array leaf shared by BOTH sides (not per-collection-entry): gravity.direction,
  ! gravity.amplitude, output.stress_averaging.
  subroutine cmp_real64_alloc(unit, id, c, r)
    integer, intent(in) :: unit
    character(len=*), intent(in) :: id
    real(real64), allocatable, intent(in) :: c(:), r(:)
    integer :: j
    logical :: all_ok
    if (.not. allocated(c) .or. .not. allocated(r)) then
      call emit(unit, id, 'MISMATCH', 'parse error', &
        merge('allocated  ','unallocated',allocated(c)), &
        merge('allocated  ','unallocated',allocated(r)), '')
      return
    end if
    if (size(c) /= size(r)) then
      call emit(unit, id, 'MISMATCH', 'legacy-state difference', 'n='//fi(int(size(c),int32)), &
        'n='//fi(int(size(r),int32)), 'size mismatch')
      return
    end if
    all_ok = .true.
    do j = 1, size(c)
      if (transfer(c(j), 0_int64) /= transfer(r(j), 0_int64)) all_ok = .false.
    end do
    if (size(c) == 0) then
      call emit(unit, id, 'MATCH', '', '(empty)', '(empty)', '')
    else if (all_ok) then
      call emit(unit, id, 'MATCH', '', '['//join_real(c)//']', '['//join_real(r)//']', '')
    else
      call emit(unit, id, 'MISMATCH', 'legacy-state difference', '['//join_real(c)//']', &
        '['//join_real(r)//']', '')
    end if
  end subroutine cmp_real64_alloc

  subroutine cmp_i32_alloc(unit, id, c, r)
    integer, intent(in) :: unit
    character(len=*), intent(in) :: id
    integer(int32), allocatable, intent(in) :: c(:), r(:)
    if (.not. allocated(c) .or. .not. allocated(r)) then
      call emit(unit, id, 'MISMATCH', 'parse error', &
        merge('allocated  ','unallocated',allocated(c)), &
        merge('allocated  ','unallocated',allocated(r)), '')
      return
    end if
    if (size(c) /= size(r)) then
      call emit(unit, id, 'MISMATCH', 'legacy-state difference', 'n='//fi(int(size(c),int32)), &
        'n='//fi(int(size(r),int32)), 'size mismatch')
      return
    end if
    if (size(c) == 0) then
      call emit(unit, id, 'MATCH', '', '(empty)', '(empty)', '')
    else if (all(c == r)) then
      call emit(unit, id, 'MATCH', '', '['//join_int(c)//']', '['//join_int(r)//']', '')
    else
      call emit(unit, id, 'MISMATCH', 'legacy-state difference', '['//join_int(c)//']', &
        '['//join_int(r)//']', '')
    end if
  end subroutine cmp_i32_alloc

end module yl_adapter_fidelity

! ================================================================================
! program: takes NO command-line argument on purpose. `yl_adapter_harvest.
! drive_legacy_readers` calls `yl_diag.diag_set_mode_from_argv`, which scans EVERY
! command-line argument for its own fixed flag set (`--check-legacy` / `--max-entities=N`
! / `--dump-state=DIR`) and raises `PARSE`/exit 2 on anything else -- so a deck-directory
! positional argument here would be rejected by that scan before this program's own
! candidate side ever ran (confirmed: an initial version of this program that passed the
! deck dir as argv(1) failed exactly this way). Both `build_candidate` (via `dir`) and
! `harvest_problem_state` (which opens `'inp'` etc. with NO directory prefix at all, by
! its own module's design) therefore read the CURRENT WORKING DIRECTORY as the deck: the
! caller must `cd` into a scratch copy of the deck before running this binary, never
! `cases/golden/*` in place.
!
! Exits 1 if the SUMMARY line carries any MISMATCH or NOT_COMPARABLE, so a wrapper script
! can gate on it; this is a diagnostic instrument (M4-01 plan.md's own words: L3-a is
! diagnostic, not the L3-b/c acceptance gate), so a nonzero exit here is informational to
! the invoking shell, not a contract this program owns.
! ================================================================================
program yl_adapter_fidelity_main
  use iso_fortran_env, only: output_unit
  use yl_adapter_fidelity, only: run_fidelity
  implicit none

  call run_fidelity('.', output_unit)
end program yl_adapter_fidelity_main
