! yl_runtime_bridge_test -- the isolated bridge program (M3-03 test matrix row Bridge).
!
! Scope (.ccg/tasks/m3-03-build-runtime-commit/plan.md, delivery 7)
!   The ONLY program in the repository that links the real legacy modules alongside
!   src/state, src/problem and src/runtime INCLUDING yl_runtime_commit.f90. Its one job
!   is to exercise `commit_legacy_globals` against the ACTUAL `global_var`, `prescribed`,
!   `applied_load` and `meshfine` globals -- not a fixture, not a copy -- and read them
!   straight back to see whether the values, extents and kinds the runtime carried
!   actually landed. tools/build.sh runtime-bridge compiles and links this file last,
!   after the same legacy source list the solver builds from, minus Fem.f90.
!
! WHY THIS DOES NOT CALL yl_state_dump
!   state_dump('model_ready') (src/state/yl_state_dump.f90) exports 162 fields, most of
!   them ProblemState-owned globals (coord, props, matno_process, group%name, solver
!   controls, ...) that commit_legacy_globals deliberately never writes (see that
!   module's header, "WHAT IS WRITTEN"). Calling it after a runtime-only commit would
!   read an unallocated global and abort inside state_fail before this program produced
!   one line of its own evidence. So every comparison below reads the legacy globals
!   DIRECTLY -- this program USEs global_var/prescribed/applied_load/meshfine itself --
!   and compares them field by field against the runtime that was staged for commit.
!   That is the honest form of the check available until M4-01 folds ProblemState's
!   half into the same staging pass; do not "fix" this by wiring the observer back in.
!
! WHAT THIS PROVES, AND WHAT IT DOES NOT (see yl_runtime_commit's header, "WHAT
! COMMITTING PROVES")
!   That the values reach the real globals with the right extents and the right kinds,
!   that a failed commit touches nothing, that a repeat commit is bit-for-bit idempotent
!   in its effect, that release is total and its second call is a no-op, and that commit
!   does not disturb globals it never registers. It does NOT run a solver consumer, does
!   NOT prove the absence of a use-after-free or a leak (a process cannot observe its own
!   leaks -- see commit's header), and does NOT compare against the frozen M2 baseline:
!   there is no deck-to-ProblemState reader yet (M4-01), so nothing here reads
!   cases/golden/*/reference/frozen.json or hand-transcribes a golden value. The final
!   verdict this program prints is explicitly labelled PARTIAL for exactly these reasons.
program yl_runtime_bridge_test

  use iso_fortran_env, only: int32, real64, output_unit

  ! --- the real legacy globals: the module this program exists to exercise -------
  use global_var, only: element, group, listp_group, trans, appear,                             &
                        lmdofn, lcdofn, nodfn, iffix, fixed,                                    &
                        result_zero, tofor, stfor, toforl, toform, delitfi, deltafi,            &
                        line_load_block, line_temp_block,                                       &
                        npoin, nelem, ngroup, ndimn, mdofn, cdofn, ntotv, iblks, lblks,         &
                        lineload, linet,                                                        &
                        coord, appear_process, matno_process, average_appear,                   &
                        nmats, nblks, restart, ttime
  use prescribed, only: prescrib, ndofix
  use materials, only: props
  use applied_load, only: tcurves, ntcurve, factg, tcurvegravity
  use meshfine, only: ice0

  use variable_types, only: ink, irk

  use yl_problem_optional, only: opt_int, opt_real, opt_set, opt_get, opt_value_or
  use yl_problem_deck_residue, only: deck_residue_t
  use yl_problem_types, only: problem_state_t, case_t, node_t, element_t, elset_t, nset_t,       &
                              material_t, section_t, amplitude_t, amplitude_point_t,             &
                              interactions_t, solver_t, step_t, controls_t, load_t, output_t,    &
                              boundary_t, activation_t
  use yl_problem_errors, only: problem_errors_t, source_location_t
  use yl_problem_manifest, only: manifest_t
  use yl_problem_profile, only: PROFILE_TAG
  use yl_problem_builder
  use yl_problem_pipeline, only: prepare_problem

  use yl_runtime_types, only: runtime_state_t
  use yl_runtime_contract, only: CONTRACT_TAG
  use yl_runtime_build, only: build_runtime
  use yl_runtime_commit, only: commit_legacy_globals, commit_release, commit_owns_globals,   &
                               commit_provenance_export
  use yl_runtime_rules, only: build_rule_count, build_rule_id, build_rule_key

  implicit none

  integer :: n_check = 0, n_fail = 0
  type(runtime_state_t), allocatable :: rt1, rt2
  type(problem_state_t), allocatable :: pr1, pr2
  type(deck_residue_t) :: rs1, rs2

  write (output_unit, '(a)') 'yl_runtime_bridge_test: M3-03 isolated bridge (commit_legacy_globals)'

  write (output_unit, '(a)') '-- 1. commit lands the values (1-element draft)'
  call build_and_commit(1, rt1, pr1, rs1)
  call check_landed(pr1, rt1)

  write (output_unit, '(a)') '-- 2. commit lands the values (2-element draft)'
  call build_and_commit(2, rt2, pr2, rs2)
  call check_landed(pr2, rt2)

  write (output_unit, '(a)') '-- 3. no partial commit'
  call group_no_partial(pr2, rs2, rt2)

  write (output_unit, '(a)') '-- 4. repeat load / ownership'
  call group_repeat_and_ownership(pr2, rs2, rt2)

  write (output_unit, '(a)') '-- 5. unregistered globals are not disturbed'
  call group_sentinels(pr2, rs2, rt2)

  write (output_unit, '(a)') '-- 6. the W4 foreign-allocation guard, one door at a time'
  call group_foreign_allocation_guard(pr2, rs2, rt2)

  write (output_unit, '(a)') '-- 7. the snapshot blind spots, and how far their guards reach'
  call group_blind_spot_falsifiability(pr2, rs2, rt2)

  ! The provenance ledger, exported for the Python cross-check (yl_runtime_commit's
  ! ledger header). Deliberately printed AFTER the suite and outside the PASS/FAIL
  ! accounting: it asserts nothing, it hands tools/yl_state_map.py the one copy of the
  ! table so no second copy has to exist. Same arrangement as yl_runtime_selftest's
  ! export_rule_table.
  call commit_provenance_export(output_unit)

  call summary()

contains

  ! ==========================================================================
  ! section 1: build a draft through the real pipeline+builder, build_runtime,
  ! commit, and leave `rt` holding the runtime that was committed so later
  ! sections can re-verify against it.
  ! ==========================================================================

  subroutine build_and_commit(n_elem, rt, problem_out, residue_out)
    integer, intent(in) :: n_elem
    type(runtime_state_t), allocatable, intent(out) :: rt
    !> The ProblemState and the deck residue this commit was made with. Handed back
    !> because commit_legacy_globals now takes all three and the later sections re-commit
    !> the same runtime: they must re-commit it with the same inputs, not with fresh
    !> default-initialised ones, or "repeat commit is bit-for-bit identical" would be
    !> comparing two different calls.
    type(problem_state_t), allocatable, intent(out) :: problem_out
    type(deck_residue_t), intent(out) :: residue_out
    type(problem_state_t), allocatable :: draft, problem
    type(manifest_t), allocatable :: pmanifest, rmanifest
    type(problem_errors_t) :: errors
    logical :: built

    call draft_of(n_elem, draft)

    call prepare_problem(draft, PROFILE_TAG, problem, pmanifest, errors)
    call check('prepare_problem accepted the '//itoa(n_elem)//'-element draft', .not. errors%any())
    if (errors%any()) then
      call report_errors('prepare_problem', errors)
      return
    end if

    call build_runtime(problem, CONTRACT_TAG, rt, rmanifest, errors)
    call check('build_runtime produced a runtime for the '//itoa(n_elem)//'-element draft',      &
              .not. errors%any() .and. allocated(rt))
    if (errors%any() .or. .not. allocated(rt)) then
      call report_errors('build_runtime', errors)
      return
    end if

    ! The residue is default-initialised: every component unset. That is honest at this
    ! step -- no parser fills it yet (M4-01 step 5) and commit reads nothing out of it.
    call move_alloc(problem, problem_out)
    call commit_legacy_globals(problem_out, residue_out, rt, errors)
    call check('commit_legacy_globals accepted the '//itoa(n_elem)//'-element runtime',          &
              .not. errors%any())
    built = .not. errors%any()
    call check('commit_owns_globals is true after a successful commit', commit_owns_globals())
    if (.not. built) call report_errors('commit_legacy_globals', errors)
  end subroutine build_and_commit

  ! A draft structurally like yl_problem_pipeline_selftest's cooks-equivalent good_draft
  ! (same supported combination: 2-D Q4 kind 5 class CO field U formulation PE, ELASTIC_
  ! ISOTROPIC MECHANICAL, symmetric PROFILE solver, procedure Q load mode LOAD, gravity,
  ! one section, one material, one step, one LINEAR amplitude, two prescribed sets) --
  ! this program owns no other file, so it builds its own draft through the same public
  ! builder API rather than reaching into a fixture another file owns.
  !
  ! n_elem selects between the two shapes the bridge is asked to cover: a single unit
  ! square (4 nodes) and two unit squares sharing an edge (6 nodes, CCW node order in
  ! both elements). Only the mesh is parameterised; every other authored field is the
  ! same combination in both cases.
  subroutine draft_of(n_elem, draft)
    integer, intent(in) :: n_elem
    type(problem_state_t), allocatable, intent(out) :: draft

    type(problem_builder_t) :: b
    type(step_builder_t) :: sb
    type(amplitude_builder_t) :: ab
    type(problem_errors_t) :: errors
    type(source_location_t) :: loc
    type(case_t) :: kase
    type(node_t) :: nd
    type(element_t) :: el
    type(elset_t) :: es
    type(nset_t) :: ns
    type(material_t) :: mt
    type(section_t) :: sc
    type(amplitude_t) :: am
    type(amplitude_point_t) :: pt
    type(interactions_t) :: it
    type(solver_t) :: sv
    type(controls_t) :: ct
    type(load_t) :: ld
    type(output_t) :: ou
    type(boundary_t) :: bd
    type(activation_t) :: ac
    type(step_t) :: st
    integer :: k, n_node
    logical :: ok
    real(real64), allocatable :: xs(:), ys(:)

    call builder_begin(b)

    call opt_set(kase%name, 'bridge_'//itoa(n_elem)//'e')
    call builder_set_case(b, kase, loc, errors)
    call builder_set_mesh_dimension(b, 2_int32, loc, errors)

    ! Two adjoining unit squares, CCW in both elements: (0,0)-(1,0)-(1,1)-(0,1) and, for
    ! the 2-element case, (1,0)-(2,0)-(2,1)-(1,1) sharing edge {2,3}.
    if (n_elem == 1) then
      n_node = 4
      allocate (xs(4), ys(4))
      xs = [0.0_real64, 1.0_real64, 1.0_real64, 0.0_real64]
      ys = [0.0_real64, 0.0_real64, 1.0_real64, 1.0_real64]
    else
      n_node = 6
      allocate (xs(6), ys(6))
      xs = [0.0_real64, 1.0_real64, 1.0_real64, 0.0_real64, 2.0_real64, 2.0_real64]
      ys = [0.0_real64, 0.0_real64, 1.0_real64, 1.0_real64, 0.0_real64, 1.0_real64]
    end if
    do k = 1, n_node
      call opt_set(nd%id, int(k, int32))
      if (allocated(nd%xyz)) deallocate (nd%xyz)
      allocate (nd%xyz(2))
      nd%xyz = [xs(k), ys(k)]
      call builder_add_node(b, nd, loc, errors)
    end do

    ! material is authored because commit now REFUSES an unset one rather than
    ! publishing a 0 (verify_problem_inputs). The fixture left it unset until M4-01 step
    ! 3b, which made element%matno 0 through opt_or's fallback and sections.material_header
    ! -- reconstructed from it -- silently wrong.
    ! elements[].material IS the header value: both map rows resolve to element%matno.
    call opt_set(el%material, 2_int32)
    call opt_set(el%id, 1_int32)
    if (allocated(el%nodes)) deallocate (el%nodes)
    allocate (el%nodes(4))
    el%nodes = [1_int32, 2_int32, 3_int32, 4_int32]
    call builder_add_element(b, el, loc, errors)
    if (n_elem == 2) then
      call opt_set(el%id, 2_int32)
      deallocate (el%nodes)
      allocate (el%nodes(4))
      el%nodes = [2_int32, 5_int32, 6_int32, 3_int32]
      call builder_add_element(b, el, loc, errors)
    end if

    if (allocated(es%elements)) deallocate (es%elements)
    if (n_elem == 1) then
      allocate (es%elements(1)); es%elements = [1_int32]
    else
      allocate (es%elements(2)); es%elements = [1_int32, 2_int32]
    end if
    call builder_add_elset(b, es, loc, errors)

    ! Two prescribed sets over the left edge {1,4}, as in good_draft -- present and
    ! non-empty in both mesh sizes, which is the "at least one prescribed record"
    ! requirement of the Bridge row.
    do k = 1, 2
      if (allocated(ns%nodes)) deallocate (ns%nodes)
      allocate (ns%nodes(2))
      ns%nodes = [1_int32, 4_int32]
      call builder_add_nset(b, ns, loc, errors)
    end do

    call opt_set(mt%id, 1_int32)
    call opt_set(mt%name, 'concrete')
    call opt_set(mt%kind, 'MECHANICAL')
    call opt_set(mt%phase, 'SOLID')
    call opt_set(mt%model, 'ELASTIC_ISOTROPIC')
    call opt_set(mt%E, 2.5e10_real64)
    call opt_set(mt%nu, 0.2_real64)
    call opt_set(mt%density, 2.4e3_real64)
    call opt_set(mt%thermal_expansion, 1.0e-5_real64)
    call opt_set(mt%solid_ratio, 1.0_real64)
    call opt_set(mt%creep_model, 0_int32)
    call opt_set(mt%liquefaction, 0_int32)
    call opt_set(mt%wetting_kind, 0_int32)
    call builder_add_material(b, mt, loc, errors)
    ! A SECOND material exists only so sections[].material and sections[].material_header
    ! can hold DIFFERENT values. They are equal on both golden decks (the map says so), and
    ! that equality made the fixture unable to tell the two apart: swapping commit's source
    ! for group%matno from .material to .material_header left the suite at rc=0 with zero
    ! failures. A fixture whose job is to catch a source swap must therefore differ where
    ! the real decks agree.
    call opt_set(mt%id, 2_int32)
    call opt_set(mt%name, 'concrete2')
    call builder_add_material(b, mt, loc, errors)

    call opt_set(sc%name, 'g1')
    call opt_set(sc%element, 'Q4')
    call opt_set(sc%element_kind, 5_int32)
    call opt_set(sc%class, 'CO')
    call opt_set(sc%fields, 'U')
    call opt_set(sc%formulation, 'PE')
    call opt_set(sc%special, 'ST')
    ! DIFFERENT ON PURPOSE. sections[].material is the EFFECTIVE material (legacy
    ! overwrites the .glb header slot in place at Fem.f90:1717); sections[].material_header
    ! is the value as READ, and it is what element%matno carries. Keeping them equal --
    ! which is what the golden decks happen to do -- makes a swap between them invisible.
    call opt_set(sc%material, 1_int32)
    call opt_set(sc%material_header, 2_int32)
    ! thickness likewise: unset until M4-01 step 3b's verify_problem_inputs made an
    ! unauthored ProblemState scalar a rejection instead of a published 0.0. The value is
    ! the one the .mat elastic_isotropic record supplies on a real deck.
    call opt_set(sc%thickness, 1.0_real64)
    call opt_set(sc%algorithm, 0_int32)
    call opt_set(sc%stiffness_kind, 1_int32)
    call opt_set(sc%stress_recovery, 1_int32)
    call opt_set(sc%layer, 1_int32)
    call opt_set(sc%liquefaction, 0_int32)
    call opt_set(sc%uplift, 0_int32)
    call opt_set(sc%local_axes, 0.0_real64)
    call builder_add_section(b, sc, loc, errors)

    ! One LINEAR curve, points (0, 1) and (1, 1) -- the "at least one amplitude" leg of
    ! the Bridge row, and what makes tcurves non-empty after commit.
    call builder_amplitude_begin(ab)
    call builder_amplitude_set_name(b, ab, 'a1', loc, errors)
    call builder_amplitude_set_type(b, ab, 'LINEAR', loc, errors)
    call opt_set(pt%time, 0.0_real64)
    call opt_set(pt%value, 1.0_real64)
    call builder_amplitude_add_point(b, ab, pt, loc, errors)
    ! 2.5, not 1.0. time and value land in two different pointer arrays of the same
    ! record (ttime_curve, dfact_curve), both real, both ntime long -- so a swap between
    ! their sources is invisible wherever the two happen to be equal. Point 1 already
    ! separates them (0.0 vs 1.0); giving point 2 a distinct value means the swap fails at
    ! BOTH points rather than relying on one. V16 constrains only that times increase.
    call opt_set(pt%time, 1.0_real64)
    call opt_set(pt%value, 2.5_real64)
    call builder_amplitude_add_point(b, ab, pt, loc, errors)
    call builder_amplitude_finish(b, ab, am, loc, errors)
    call builder_add_amplitude(b, am, loc, errors)

    call opt_set(sv%linear, 'PROFILE')
    call opt_set(sv%symmetric, .true.)
    call opt_set(sv%profile%singularity_check, 0_int32)
    call opt_set(sv%profile%condition_check, 0_int32)
    call opt_set(sv%profile%positive_definite_check, 0_int32)
    call opt_set(sv%profile%pivot_file, 0_int32)
    call builder_set_solver(b, sv, loc, errors)

    call opt_set(it%absorbing%type, 'FIX')
    call builder_set_interactions(b, it, loc, errors)

    call builder_step_begin(sb)
    call builder_step_set_procedure(b, sb, 'Q', loc, errors)
    call builder_step_set_load_mode(b, sb, 'LOAD', loc, errors)

    call opt_set(ct%nonlinear_type, 5_int32)
    call opt_set(ct%increments, 1_int32)
    call opt_set(ct%max_iterations, 1_int32)
    call opt_set(ct%steps, 1_int32)
    call opt_set(ct%step_increment, 1_int32)
    call opt_set(ct%restart_frequency, 0_int32)
    call opt_set(ct%time_increment, 1.0_real64)
    call opt_set(ct%tolerance_force, 1.0e-5_real64)
    if (allocated(ct%tolerance_dof)) deallocate (ct%tolerance_dof)
    allocate (ct%tolerance_dof(2))
    ct%tolerance_dof = [1.0e-5_real64, 1.0e-5_real64]
    call builder_step_set_controls(b, sb, ct, loc, errors)

    call opt_set(ld%gravity%enabled, 1_int32)
    call opt_set(ld%gravity%magnitude, 9.81_real64)
    if (allocated(ld%gravity%direction)) deallocate (ld%gravity%direction)
    allocate (ld%gravity%direction(2))
    ld%gravity%direction = [0.0_real64, -1.0_real64]
    if (allocated(ld%gravity%amplitude)) deallocate (ld%gravity%amplitude)
    if (n_elem == 1) then
      allocate (ld%gravity%amplitude(1)); ld%gravity%amplitude = [1_int32]
    else
      allocate (ld%gravity%amplitude(1)); ld%gravity%amplitude = [1_int32]
    end if
    call builder_step_set_load(b, sb, ld, loc, errors)

    call opt_set(ou%format, 'GIDR')
    call opt_set(ou%field%u, 1_int32)
    call opt_set(ou%field%v, 0_int32)
    call opt_set(ou%field%a, 0_int32)
    call opt_set(ou%field%s, 1_int32)
    call opt_set(ou%field%ms, 0_int32)
    call opt_set(ou%field%f, 0_int32)
    call opt_set(ou%field%rot, 0_int32)
    call opt_set(ou%field%T, 0_int32)
    call opt_set(ou%field%P, 0_int32)
    call opt_set(ou%field%Pv, 0_int32)
    call opt_set(ou%field%ep, 0_int32)
    call opt_set(ou%field%Y, 0_int32)
    call opt_set(ou%field%FC, 0_int32)
    call opt_set(ou%field%Ns, 0_int32)
    call opt_set(ou%field%Ss, 0_int32)
    call opt_set(ou%field%Mxy, 0_int32)
    call opt_set(ou%field%bem, 0_int32)
    call opt_set(ou%field%wh, 0_int32)
    call opt_set(ou%field%wv, 0_int32)
    call opt_set(ou%field%bcs, 0_int32)
    call opt_set(ou%frequency%nodes, 1_int32)
    call opt_set(ou%frequency%fields, 1_int32)
    if (allocated(ou%stress_averaging)) deallocate (ou%stress_averaging)
    allocate (ou%stress_averaging(1))
    ou%stress_averaging = [2_int32]
    call builder_step_set_output(b, sb, ou, loc, errors)

    ! SIX FIELDS THAT MUST BE ABLE TO TELL EACH OTHER APART. Every one of these lands in a
    ! different scalar of the same `prescrib` record, and five of the six are small
    ! integers, so commit reading the wrong one is a value swap rather than a type error.
    ! The fixture used to set name = nset = dof = k and amplitude = 1, record_reaction = 0
    ! for both records; under that fixture a swap of name against nset, or of nset against
    ! dof, changed nothing at all and every assertion below would have passed. That is the
    ! defect docs/04-quality-gates.md records as the test-side subspecies -- an assertion
    ! whose name claims a discrimination its fixture cannot make -- and the fix belongs
    ! here, in the fixture, not in the assertions.
    !
    ! The values are chosen so that for EVERY pair of these fields at least one record
    ! gives them different values, which is what makes a swap of that pair observable:
    !
    !   record 1: name 1, nset 4, dof 2, value  0.25, amplitude 0, record_reaction 1
    !   record 2: name 2, nset 1, dof 1, value -0.50, amplitude 1, record_reaction 0
    !
    ! (name vs record_reaction is the only pair that agrees in record 1; record 2 separates
    ! them.) Every value is inside the gates: V24 needs the set ordinals to run 1..n with no
    ! gap, V17 needs dof in 1..ndimn, V18 needs amplitude in 0..n_amplitudes with 0 meaning
    ! "no curve", and B1/B6 need each node to be attached to an element and each
    ! (node, component) pair to appear once. Nodes 1 and 4 are corners of element 1 in both
    ! mesh sizes. `value` is non-zero on purpose: 0.0 is what both golden decks carry, so a
    ! zero here would make an unwritten vdofix indistinguishable from a written one.
    call opt_set(bd%name, 1_int32)
    call opt_set(bd%nset, 4_int32)
    call opt_set(bd%dof, 2_int32)
    call opt_set(bd%value, 0.25_real64)
    call opt_set(bd%amplitude, 0_int32)
    call opt_set(bd%record_reaction, 1_int32)
    call builder_step_add_boundary(b, sb, bd, loc, errors)
    call opt_set(bd%name, 2_int32)
    call opt_set(bd%nset, 1_int32)
    call opt_set(bd%dof, 1_int32)
    call opt_set(bd%value, -0.5_real64)
    call opt_set(bd%amplitude, 1_int32)
    call opt_set(bd%record_reaction, 0_int32)
    call builder_step_add_boundary(b, sb, bd, loc, errors)

    call opt_set(ac%material, 1_int32)
    call opt_set(ac%active, 1_int32)
    call builder_step_add_activation(b, sb, ac, loc, errors)

    call builder_step_finish(b, sb, st, loc, errors)
    call builder_add_step(b, st, loc, errors)

    call builder_finish(b, draft, errors, ok)
    if (.not. ok) then
      write (output_unit, '(a)') 'FATAL: the bridge draft ('//itoa(n_elem)//' elements) did not build'
      call report_errors('builder_finish', errors)
      stop 1
    end if
  end subroutine draft_of

  ! ==========================================================================
  ! section 1 (continued): every committed quantity, read from the REAL legacy
  ! globals, against the runtime that was staged for it.
  ! ==========================================================================

  subroutine check_landed(problem, rt)
    type(problem_state_t), intent(in) :: problem
    logical :: ok_all
    type(runtime_state_t), intent(in) :: rt
    integer :: ie, ig, i, n, ntv, iblk_v, lblk_v
    logical :: found

    ! --- scalars, each derived from the runtime's own shape, never a literal ---------
    call check('npoin', npoin == int(size(rt%dof%node_variables, 2), ink))
    call check('nelem', nelem == int(size(rt%element), ink))
    call check('ngroup', ngroup == int(size(rt%activation%section_state), ink))
    call check('ndimn', ndimn == int(size(rt%element(1)%field_coordinates, 1), ink))
    call check('mdofn', mdofn == int(size(rt%dof%component_to_active), ink))
    call check('cdofn', cdofn == int(size(rt%dof%node_variables, 1), ink))
    ntv = size(rt%dof%fixed_mask)
    call check('ntotv', ntotv == int(ntv, ink))
    call check('ndofix', ndofix == size(rt%boundary))
    call check('ntcurve', ntcurve == size(rt%amplitudes))
    call opt_get(rt%increment%current_block, iblk_v, found)
    call check('iblks', found .and. iblks == int(iblk_v, ink))
    call opt_get(rt%increment%completed_blocks, lblk_v, found)
    call check('lblks', found .and. lblks == int(lblk_v, ink))

    ! --- plain arrays -----------------------------------------------------------
    call check('lmdofn', all(lmdofn == int(rt%dof%component_to_active, ink)))
    call check('lcdofn', all(lcdofn == int(rt%dof%active_to_component, ink)))
    call check('nodfn', all(nodfn == int(rt%dof%node_variables, ink)))
    call check('iffix', all(iffix == int(rt%dof%fixed_mask, ink)))
    call check('fixed', all(fixed == real(rt%dof%prescribed_value, irk)))
    call check('appear', all(appear == int(rt%activation%section_state, ink)))
    call check('result_zero', all(result_zero == real(rt%vectors%total_displacement, irk)))
    call check('tofor', all(tofor == real(rt%vectors%external_force_total, irk)))
    call check('stfor', all(stfor == real(rt%vectors%internal_force, irk)))
    call check('toforl', all(toforl == real(rt%vectors%external_force_load, irk)))
    call check('toform', all(toform == real(rt%vectors%external_force_mass, irk)))
    call check('ice0', size(ice0) == size(rt%element) .and.                                     &
              all([(int_or_zero_ie(rt, ie) == int(ice0(ie), int32), ie=1, size(ice0))]))
    call check('line_load_block extent',                                                        &
              size(line_load_block) == size(rt%cursor%load_line_per_block))
    call check('line_temp_block extent',                                                        &
              size(line_temp_block) == size(rt%cursor%temperature_line_per_block))

    ! RESERVED rows: allocation and extent only. Their contents are undefined by the
    ! ledger (RUNTIME_VALUE_RESERVED under the strict profile they hold signalling NaN),
    ! so reading a value out of them is exactly what the ledger forbids -- this program
    ! asserts they exist at the right length and stops there.
    call check('delitfi is allocated at ntotv', allocated(delitfi) .and. size(delitfi) == ntv)
    call check('deltafi is allocated at ntotv', allocated(deltafi) .and. size(deltafi) == ntv)

    ! --- element records ---------------------------------------------------------
    do ie = 1, size(rt%element)
      call check('element('//itoa(ie)//')%ldofs',                                               &
                all(element(ie)%ldofs == int(rt%dof%element_variables(ie)%values, ink)))
      call check('element('//itoa(ie)//')%field(1)%ldofs_f',                                     &
                all(element(ie)%field(1)%ldofs_f ==                                             &
                    int(rt%dof%element_field_variables(ie)%fields(1)%values, ink)))
      call check('element('//itoa(ie)//')%field(1)%elcod_f',                                     &
                all(element(ie)%field(1)%elcod_f == real(rt%element(ie)%field_coordinates, irk)))
      call check('element('//itoa(ie)//')%egaus(1)%djacb',                                       &
                all(element(ie)%egaus(1)%djacb == real(rt%gauss(ie)%stiffness%weighted_jacobian, irk)))
      call check('element('//itoa(ie)//')%egaus(1)%gpcod',                                       &
                all(element(ie)%egaus(1)%gpcod == real(rt%gauss(ie)%stiffness%point_coordinates, irk)))
      call check('element('//itoa(ie)//')%egaus(1)%cartd',                                       &
                all(element(ie)%egaus(1)%cartd == real(rt%gauss(ie)%stiffness%shape_gradient, irk)))
      call check('element('//itoa(ie)//')%egaus(2)%djacb',                                       &
                all(element(ie)%egaus(2)%djacb == real(rt%gauss(ie)%mass%weighted_jacobian, irk)))
      call check('element('//itoa(ie)//')%egaus(2)%gpcod',                                       &
                all(element(ie)%egaus(2)%gpcod == real(rt%gauss(ie)%mass%point_coordinates, irk)))
      ! The mass rule never gets a shape-gradient allocation in legacy (Elements.f90:1232:
      ! cartd is stored only for a rule whose name is not 'mass'); an associated pointer
      ! here would be exactly the shape the solver never sees and commit_release could
      ! not account for.
      call check('element('//itoa(ie)//')%egaus(2)%cartd is UNASSOCIATED',                       &
                .not. associated(element(ie)%egaus(2)%cartd))
      ! RESERVED per-element vectors: allocation and extent only, values not read.
      n = size(rt%dof%element_variables(ie)%values)
      call check('element('//itoa(ie)//')%field(1)%tload is allocated at nevab',                 &
                associated(element(ie)%field(1)%tload) .and. size(element(ie)%field(1)%tload) == n)
      call check('element('//itoa(ie)//')%field(1)%eload is allocated at nevab',                 &
                associated(element(ie)%field(1)%eload) .and. size(element(ie)%field(1)%eload) == n)
      call check('element('//itoa(ie)//')%field(1)%rload is allocated at nevab',                 &
                associated(element(ie)%field(1)%rload) .and. size(element(ie)%field(1)%rload) == n)
    end do

    ! --- trans(:)%nintf ------------------------------------------------------------
    call check('trans(:)%nintf', all([(trans(i)%nintf == int(rt%dof%interpolation_count(i), ink), &
                                       i=1, ntv)]))

    ! --- group / unode -------------------------------------------------------------
    do ig = 1, size(rt%topology%sections)
      call check('group('//itoa(ig)//')%np_unode',                                              &
                group(ig)%np_unode == int(size(rt%topology%sections(ig)%nodes), ink))
      do i = 1, size(rt%topology%sections(ig)%nodes)
        call check('group('//itoa(ig)//')%unode('//itoa(i)//')%ipoin',                          &
                  group(ig)%unode(i)%ipoin ==                                                    &
                  int(opt_value_or(rt%topology%sections(ig)%nodes(i)%node_id, 0_int32), ink))
        call check('group('//itoa(ig)//')%unode('//itoa(i)//')%ne_unode',                        &
                  group(ig)%unode(i)%ne_unode ==                                                 &
                  int(opt_value_or(rt%topology%sections(ig)%nodes(i)%element_count, 0_int32), ink))
        call check('group('//itoa(ig)//')%unode('//itoa(i)//')%list',                            &
                  all(group(ig)%unode(i)%list ==                                                &
                      int(rt%topology%sections(ig)%nodes(i)%elements, ink)))
      end do
    end do

    ! --- listp_group -----------------------------------------------------------
    do i = 1, npoin
      call check('listp_group('//itoa(i)//')%mgroup',                                           &
                listp_group(i)%mgroup == int(rt%topology%node_sections%group_count(i), ink))
      n = int(rt%topology%node_sections%group_count(i))
      if (n > 0) then
        call check('listp_group('//itoa(i)//')%listg',                                          &
                  all(listp_group(i)%listg ==                                                   &
                      int(rt%topology%node_sections%section_index(i)%values, ink)))
        call check('listp_group('//itoa(i)//')%listp',                                          &
                  all(listp_group(i)%listp ==                                                   &
                      int(rt%topology%node_sections%position_in_section(i)%values, ink)))
      end if
    end do

    ! --- prescrib ----------------------------------------------------------------
    do i = 1, size(rt%boundary)
      call check('prescrib('//itoa(i)//')%ldofix',                                              &
                prescrib(i)%ldofix == int(opt_value_or(rt%boundary(i)%dof_index, 0_int32), ink))
      call check('prescrib('//itoa(i)//')%lnefix',                                              &
                prescrib(i)%lnefix ==                                                            &
                int(opt_value_or(rt%boundary(i)%element_count, 0_int32), ink))
      call check('prescrib('//itoa(i)//')%leldofix',                                            &
                all(prescrib(i)%leldofix == int(rt%boundary(i)%attached_element, ink)))
      call check('prescrib('//itoa(i)//')%levdofix',                                            &
                all(prescrib(i)%levdofix == int(rt%boundary(i)%attached_local_position, ink)))
      call check('prescrib('//itoa(i)//')%lefdofix',                                            &
                all(prescrib(i)%lefdofix == int(rt%boundary(i)%attached_field, ink)))
    end do

    ! --- step 4 (prescrib): the six ProblemState-owned constraint fields --------------
    ! The precondition first, because every comparison after it is positional and means
    ! nothing if the two collections are not aligned. commit REFUSES a misalignment rather
    ! than guessing; asserting it here says the fixture is on the supported side of that
    ! refusal, so a failure below is a wrong value and not a wrong row.
    call check('prescrib(:) and steps[0].boundary[] are aligned one-to-one',                    &
              size(problem%steps(1)%boundary) == size(rt%boundary))
    ! Field by field, against a fixture built so that no two of these six hold the same
    ! value in every record (see the note beside the fixture's boundary records). A swap of
    ! any pair therefore fails at least one of these, which is the property the earlier
    ! all-equal fixture did not have.
    do i = 1, min(size(rt%boundary), size(problem%steps(1)%boundary))
      call check('prescrib('//itoa(i)//')%ifixset is steps[0].boundary[].name',                 &
                prescrib(i)%ifixset ==                                                          &
                int(opt_value_or(problem%steps(1)%boundary(i)%name, 0_int32), ink))
      call check('prescrib('//itoa(i)//')%nodfix is steps[0].boundary[].nset',                  &
                prescrib(i)%nodfix ==                                                           &
                int(opt_value_or(problem%steps(1)%boundary(i)%nset, 0_int32), ink))
      call check('prescrib('//itoa(i)//')%ifixvar is steps[0].boundary[].dof',                  &
                prescrib(i)%ifixvar ==                                                          &
                int(opt_value_or(problem%steps(1)%boundary(i)%dof, 0_int32), ink))
      call check('prescrib('//itoa(i)//')%itcurve is steps[0].boundary[].amplitude',            &
                prescrib(i)%itcurve ==                                                          &
                int(opt_value_or(problem%steps(1)%boundary(i)%amplitude, 0_int32), ink))
      call check('prescrib('//itoa(i)//')%outfix is steps[0].boundary[].record_reaction',       &
                prescrib(i)%outfix ==                                                           &
                int(opt_value_or(problem%steps(1)%boundary(i)%record_reaction, 0_int32), ink))
      call check('prescrib('//itoa(i)//')%vdofix is steps[0].boundary[].value',                 &
                prescrib(i)%vdofix ==                                                           &
                real(opt_value_or(problem%steps(1)%boundary(i)%value, 0.0_real64), irk))
    end do

    ! --- tcurves(:)%dfact ----------------------------------------------------------
    do i = 1, size(rt%amplitudes)
      call check('tcurves('//itoa(i)//')%dfact',                                                &
                tcurves(i)%dfact == real(opt_value_or(rt%amplitudes(i)%factor, 0.0_real64), irk))
    end do

    ! --- step 4 (tcurves): the three ProblemState-sourced amplitude fields ------------
    call check('tcurves(:) and amplitudes[] are the same length',                               &
              size(problem%amplitudes) == size(rt%amplitudes))
    do i = 1, min(size(rt%amplitudes), size(problem%amplitudes))
      ! trim() on both sides: type_curve is character(20) and a longer ProblemState value
      ! would be truncated silently on assignment, which the poison cannot see.
      call check('tcurves('//itoa(i)//')%type_curve is amplitudes[].type',                      &
                trim(tcurves(i)%type_curve) ==                                                  &
                trim(opt_value_or(problem%amplitudes(i)%type, '')))
      call check('tcurves('//itoa(i)//')%ntime is count(amplitudes[].points)',                  &
                tcurves(i)%ntime == int(size(problem%amplitudes(i)%points), ink))
      ! The two pointer targets: associated, right length, right values -- and asserted
      ! separately, because the fixture gives time and value different numbers at every
      ! point so that a swap between the two sources cannot pass either one.
      call check('tcurves('//itoa(i)//')%ttime_curve is allocated at ntime',                    &
                associated(tcurves(i)%ttime_curve) .and.                                        &
                size(tcurves(i)%ttime_curve) == size(problem%amplitudes(i)%points))
      call check('tcurves('//itoa(i)//')%dfact_curve is allocated at ntime',                    &
                associated(tcurves(i)%dfact_curve) .and.                                        &
                size(tcurves(i)%dfact_curve) == size(problem%amplitudes(i)%points))
      ok_all = .true.
      do n = 1, size(problem%amplitudes(i)%points)
        if (tcurves(i)%ttime_curve(n) /=                                                        &
            real(opt_value_or(problem%amplitudes(i)%points(n)%time, 0.0_real64), irk))          &
          ok_all = .false.
      end do
      call check('tcurves('//itoa(i)//')%ttime_curve is amplitudes[].points[].time', ok_all)
      ok_all = .true.
      do n = 1, size(problem%amplitudes(i)%points)
        if (tcurves(i)%dfact_curve(n) /=                                                        &
            real(opt_value_or(problem%amplitudes(i)%points(n)%value, 0.0_real64), irk))         &
          ok_all = .false.
      end do
      call check('tcurves('//itoa(i)//')%dfact_curve is amplitudes[].points[].value', ok_all)
    end do

    ! --- THE SNAPSHOT BLIND SPOTS --------------------------------------------------
    ! Four model_ready rows that commit_legacy_globals WRITES and that no snapshot can
    ! ever see: runtime.topology.unode_{np_unode,patch_nod} and runtime.cursor.{lineload,
    ! linet} carry `emit = "none"` in docs/m2/state-field-map.toml, so yl_state_dump never
    ! emits them and tools/yl_shadow_diff.py is structurally blind to them. Until this
    ! block existed, NOTHING asserted them either:
    !
    !   * `group(ig)%np_unode` IS asserted above -- but that is group_of_elements's own
    !     np_unode (Global.f90:236), a DIFFERENT COMPONENT that merely shares the name
    !     with unode_elements%np_unode (Global.f90:265-267);
    !   * `verify_registered` (yl_runtime_commit.f90) rejects a runtime that allocated
    !     `patch_nodes` -- but that is the RUNTIME side; it says nothing about what commit
    !     put into `group%unode%patch_nod`;
    !   * `yl_adapter_bridge_test.f90`'s check_ledger asserts the LEDGER entry, not the
    !     committed global.
    !
    ! So an M4-01 fold that rewrites the s_group/unode staging loop and drops
    ! `call null_unode(...)` leaves patch_nod an UNINITIALISED POINTER in a real legacy
    ! global -- where any `associated()` is undefined behaviour, which is precisely the
    ! hazard null_group's own comment names -- while this program, yl_runtime_selftest,
    ! the shadow diff and L3-b all stay green. That is the `trans` defect again: a guard
    ! whose object is not the object it appears to guard.
    !
    ! These four close the "wrote the WRONG value" half only. The np_unode and
    ! patch_* guards cannot see a write that was deleted outright: commit
    ! reallocates their storage, so the poison is erased and undefined memory
    ! reads back as 0. Measured under three profiles -- see section 7's header.
    ! The staging-poison mechanism that closes that half belongs to
    ! yl_runtime_commit (docs/m4/L2c-fold-design.md §5.5), not to this program.
    call check('unode(:)%np_unode is 0 on every section node', unode_np_unode_all_zero())
    call check('unode(:)%patch_nod/patch_sta/patch_load are all UNASSOCIATED',                   &
              unode_patch_pointers_all_null())
    call check('lineload is 0 (RESERVED: no file offset is claimed)', lineload == 0_ink)
    call check('linet is 0 (RESERVED: no file offset is claimed)', linet == 0_ink)

    ! --- THE ProblemState HALF (M4-01 step 3) --------------------------------------
    ! Compared against `problem`, not against the runtime: these are the first rows whose
    ! value this module takes from the ProblemState side, and asserting them against the
    ! runtime would be asserting nothing (the runtime does not carry them).
    call check('coord extents', allocated(coord) .and. size(coord, 1) == int(ndimn) .and.       &
              size(coord, 2) == int(npoin))
    if (allocated(coord)) then
      ok_all = .true.
      do i = 1, size(problem%mesh%nodes)
        if (.not. all(coord(:, i) == real(problem%mesh%nodes(i)%xyz, irk))) ok_all = .false.
      end do
      call check('coord matches ProblemState mesh.nodes[].xyz', ok_all)
    end if

    ! Column 0 is the initial state and is part of the compared value; a 1-based
    ! allocation would shift every column and still look well formed.
    call check('appear_process lower bound of dim 2 is 0',                                      &
              allocated(appear_process) .and. lbound(appear_process, 2) == 0)
    call check('appear_process column 0 is zeroed',                                             &
              allocated(appear_process) .and. all(appear_process(:, 0) == 0_ink))
    call check('appear_process column 1 matches steps[0].activation[].active',                  &
              allocated(appear_process) .and.                                                   &
              all([(appear_process(ig, 1) ==                                                    &
                    int(opt_value_or(problem%steps(1)%activation(ig)%active, 0_int32), ink),    &
                    ig=1, size(problem%steps(1)%activation))]))
    call check('matno_process matches steps[0].activation[].material',                          &
              allocated(matno_process) .and.                                                    &
              all([(matno_process(ig, 1) ==                                                     &
                    int(opt_value_or(problem%steps(1)%activation(ig)%material, 0_int32), ink),  &
                    ig=1, size(problem%steps(1)%activation))]))
    call check('average_appear matches steps[0].output.stress_averaging',                       &
              allocated(average_appear) .and.                                                   &
              all(average_appear == int(problem%steps(1)%output%stress_averaging, ink)))
    call check('factg matches steps[0].load.gravity.direction',                                 &
              allocated(factg) .and.                                                            &
              all(factg == real(problem%steps(1)%load%gravity%direction, irk)))
    call check('tcurvegravity matches steps[0].load.gravity.amplitude',                          &
              allocated(tcurvegravity) .and.                                                     &
              all(tcurvegravity == int(problem%steps(1)%load%gravity%amplitude, ink)))

    ! --- step 3b: the two rows whose absence aborts the dump outright -------------
    ok_all = .true.
    do i = 1, size(problem%mesh%elements)
      if (.not. associated(element(i)%field(1)%lnods_f)) then
        ok_all = .false.
      else if (.not. all(element(i)%field(1)%lnods_f ==                                         &
                         int(problem%mesh%elements(i)%nodes, ink))) then
        ok_all = .false.
      end if
    end do
    call check('element(:)%field(1)%lnods_f matches mesh.elements[].nodes', ok_all)
    ok_all = .true.
    do i = 1, size(problem%mesh%elements)
      if (element(i)%matno /=                                                                   &
          int(opt_value_or(problem%mesh%elements(i)%material, 0_int32), ink)) ok_all = .false.
    end do
    call check('element(:)%matno matches mesh.elements[].material', ok_all)
    ok_all = .true.
    do ig = 1, size(problem%mesh%elsets)
      if (group(ig)%nelgroup /= int(size(problem%mesh%elsets(ig)%elements), ink)) ok_all = .false.
      if (.not. associated(group(ig)%list)) then
        ok_all = .false.
      else if (.not. all(group(ig)%list == int(problem%mesh%elsets(ig)%elements, ink))) then
        ok_all = .false.
      end if
    end do
    call check('group(:)%nelgroup and %list match mesh.elsets[].elements', ok_all)
    ! sections.material_header is reconstructed by the dump as element(group(g)%list(1))%matno.
    ! Asserted along that exact path rather than against the section, because a group%list
    ! that pointed at the wrong element would still give a plausible material id.
    ok_all = .true.
    do ig = 1, size(problem%mesh%elsets)
      if (.not. associated(group(ig)%list)) cycle
      if (size(group(ig)%list) < 1) cycle
      if (element(group(ig)%list(1))%matno /=                                                   &
          int(opt_value_or(problem%sections(ig)%material_header, 0_int32), ink)) ok_all = .false.
    end do
    call check('element(group(:)%list(1))%matno reconstructs sections[].material_header', ok_all)

    ! --- step 4 (group): the 15 section header fields ------------------------------
    ! trim() on BOTH sides. Legacy's slots are short -- class is character(2), fieldid
    ! character(5) -- and a longer ProblemState value is truncated silently on assignment.
    ! The staging poison cannot see that (a truncated string IS a written value), so this
    ! comparison is the only thing standing between a too-long section name and a
    ! plausible-looking prefix in the snapshot.
    ok_all = .true.
    do ig = 1, size(problem%sections)
      if (trim(group(ig)%kname) /= trim(opt_value_or(problem%sections(ig)%name, ''))) ok_all = .false.
      if (trim(group(ig)%name) /= trim(opt_value_or(problem%sections(ig)%element, ''))) ok_all = .false.
      if (trim(group(ig)%class) /= trim(opt_value_or(problem%sections(ig)%class, ''))) ok_all = .false.
      if (trim(group(ig)%fieldid) /= trim(opt_value_or(problem%sections(ig)%fields, ''))) ok_all = .false.
      if (trim(group(ig)%sptype) /= trim(opt_value_or(problem%sections(ig)%formulation, ''))) ok_all = .false.
      if (trim(group(ig)%special) /= trim(opt_value_or(problem%sections(ig)%special, ''))) ok_all = .false.
    end do
    call check('group(:) character fields match sections[] without truncation', ok_all)
    ok_all = .true.
    do ig = 1, size(problem%sections)
      if (group(ig)%index /= int(opt_value_or(problem%sections(ig)%element_kind, 0_int32), ink)) ok_all = .false.
      if (group(ig)%matno /= int(opt_value_or(problem%sections(ig)%material, 0_int32), ink)) ok_all = .false.
      if (group(ig)%ilayer /= int(opt_value_or(problem%sections(ig)%layer, 0_int32), ink)) ok_all = .false.
      if (group(ig)%liquj /= int(opt_value_or(problem%sections(ig)%liquefaction, 0_int32), ink)) ok_all = .false.
      if (group(ig)%uplift_ic /= int(opt_value_or(problem%sections(ig)%uplift, 0_int32), ink)) ok_all = .false.
      if (group(ig)%type_nalgo /= int(opt_value_or(problem%sections(ig)%algorithm, 0_int32), ink)) ok_all = .false.
      if (group(ig)%type_stiff /= int(opt_value_or(problem%sections(ig)%stiffness_kind, 0_int32), ink)) ok_all = .false.
      if (group(ig)%type_ecoint /= int(opt_value_or(problem%sections(ig)%stress_recovery, 0_int32), ink)) ok_all = .false.
      if (group(ig)%elcod_local /= real(opt_value_or(problem%sections(ig)%local_axes, 0.0_real64), irk)) ok_all = .false.
    end do
    call check('group(:) numeric header fields match sections[]', ok_all)
    ! matno is the EFFECTIVE material and material_header the pre-overwrite one. Asserted
    ! as a PAIR against their two different ProblemState fields, because they are equal on
    ! the golden decks and a swap would be invisible to either check alone.
    call check('group(:)%matno is sections[].material, not .material_header',                   &
              all([(group(ig)%matno ==                                                          &
                    int(opt_value_or(problem%sections(ig)%material, 0_int32), ink),             &
                    ig=1, size(problem%sections))]))

    call check('props extent', allocated(props) .and. size(props) == size(problem%materials))
    if (allocated(props)) then
      ok_all = .true.
      do i = 1, size(props)
        if (.not. associated(props(i)%mechanical)) ok_all = .false.
        if (.not. associated(props(i)%mechanical)) cycle
        if (.not. associated(props(i)%mechanical%solid)) ok_all = .false.
      end do
      ! Both levels of the chain: yl_state_dump guards each separately, and an
      ! unassociated %solid under an associated %mechanical would abort the dump at a
      ! different row than an unassociated %mechanical.
      call check('props(:)%mechanical and %mechanical%solid are both associated', ok_all)
      ok_all = .true.
      do i = 1, size(props)
        if (props(i)%mechanical%solid%e /=                                                      &
            real(opt_value_or(problem%materials(i)%E, 0.0_real64), irk)) ok_all = .false.
        if (props(i)%mechanical%solid%nu /=                                                     &
            real(opt_value_or(problem%materials(i)%nu, 0.0_real64), irk)) ok_all = .false.
        if (props(i)%mechanical%solid%density /=                                                &
            real(opt_value_or(problem%materials(i)%density, 0.0_real64), irk)) ok_all = .false.
      end do
      call check('props(:)%mechanical%solid E/nu/density match ProblemState', ok_all)
      ! thickness is assigned in the SECOND pass (section -> material). Asserted apart
      ! from the first-pass scalars because a bug that skipped that pass would leave the
      ! sentinel here and nowhere else.
      call check('props(1)%mechanical%solid%thickness came from the section',                   &
                props(1)%mechanical%solid%thickness ==                                          &
                real(opt_value_or(problem%sections(1)%thickness, 0.0_real64), irk))
    end if
  end subroutine check_landed

  ! --- blind-spot predicates ------------------------------------------------------
  ! Read the REAL globals, never the runtime. Both are written so that an unallocated
  ! `group` answers .false. rather than crashing: a predicate that cannot be evaluated
  ! must not report success.

  logical function unode_np_unode_all_zero() result(ok)
    integer :: ig, i
    ok = .false.
    if (.not. allocated(group)) return
    do ig = 1, size(group)
      if (.not. associated(group(ig)%unode)) return
      do i = 1, size(group(ig)%unode)
        if (group(ig)%unode(i)%np_unode /= 0_ink) return
      end do
    end do
    ok = .true.
  end function unode_np_unode_all_zero

  logical function unode_patch_pointers_all_null() result(ok)
    integer :: ig, i
    ok = .false.
    if (.not. allocated(group)) return
    do ig = 1, size(group)
      if (.not. associated(group(ig)%unode)) return
      do i = 1, size(group(ig)%unode)
        if (associated(group(ig)%unode(i)%patch_nod)) return
        if (associated(group(ig)%unode(i)%patch_sta)) return
        if (associated(group(ig)%unode(i)%patch_load)) return
      end do
    end do
    ok = .true.
  end function unode_patch_pointers_all_null

  ! ice0(ie): int(opt_or(rt%element(ie)%refinement_skip), ink) -- opt_or's fallback (0)
  ! matches commit's own; since verify_registered already accepted this runtime the
  ! field is set on every legal draft, so this helper only spells out the read.
  integer(int32) function int_or_zero_ie(rt, ie) result(v)
    type(runtime_state_t), intent(in) :: rt
    integer, intent(in) :: ie
    logical :: found
    call opt_get(rt%element(ie)%refinement_skip, v, found)
    if (.not. found) v = 0_int32
  end function int_or_zero_ie

  ! ==========================================================================
  ! section 2: a commit that must fail in VERIFY must not touch a single global.
  ! ==========================================================================

  subroutine group_no_partial(problem, residue, rt_good)
    type(problem_state_t), intent(in) :: problem
    type(deck_residue_t), intent(in) :: residue
    type(runtime_state_t), intent(in) :: rt_good
    type(runtime_state_t) :: rt_bad     ! default-initialised: never handed to build_runtime
    type(problem_errors_t) :: errors
    integer :: bad_npoin, bad_nelem
    real(irk), allocatable :: bad_result_zero(:)

    ! rt_bad's field_status is unallocated (default init, yl_runtime_types.f90), so
    ! runtime_status_count(rt_bad) is 0 against build_rule_produced_count() > 0: the
    ! FIRST check inside verify_registered, before any staging allocation runs. This is
    ! "a runtime that was never built", the simplest of the two shapes the task allows.
    call commit_legacy_globals(problem, residue, rt_bad, errors)
    call check('commit of an unbuilt runtime is rejected', errors%any())
    if (errors%any()) call assert_internal_commit_total(errors)

    ! Every global must still read exactly as check_landed found it for rt_good --
    ! snapshotting the whole state and re-diffing it would just repeat check_landed, so
    ! the two scalars and one array below are load-bearing spot checks: npoin/nelem are
    ! the extents every other read in check_landed depends on, and result_zero is the
    ! one array staged furthest from the failing check (verify_registered fails before
    ! ANY staging local is even allocated, so if this one array survived, all of them did).
    bad_npoin = npoin; bad_nelem = nelem
    allocate (bad_result_zero(size(result_zero))); bad_result_zero = result_zero
    call check('npoin unchanged after the rejected commit', bad_npoin == npoin)
    call check('nelem unchanged after the rejected commit', bad_nelem == nelem)
    call check('result_zero unchanged after the rejected commit', all(bad_result_zero == result_zero))
    call check_landed(problem, rt_good)
  end subroutine group_no_partial

  subroutine assert_internal_commit_total(errors, tag)
    type(problem_errors_t), intent(inout) :: errors
    character(len=*), intent(in), optional :: tag
    integer :: i, row
    logical :: found_it
    character(len=:), allocatable :: code, rule, expected_key, prefix

    ! yl_runtime_commit's own `fail()` helper raises PE_INTERNAL under the INV-COMMIT-
    ! TOTAL row's KEY, not its bare rule id: a raise site's rule_id is bound to
    ! '<rule_id>/<condition>' (build_rule_key), so the expected string is DERIVED from
    ! the rule table here rather than hand-transcribed -- a future rename or a second
    ! condition added under INV-COMMIT-TOTAL changes the table and this assertion
    ! together, instead of silently rotting the way the hardcoded string just did.
    expected_key = ''
    do row = 1, build_rule_count()
      if (build_rule_id(row) == 'INV-COMMIT-TOTAL') then
        expected_key = build_rule_key(row)
        exit
      end if
    end do
    call check('the rule table carries an INV-COMMIT-TOTAL row', len(expected_key) > 0)

    found_it = .false.
    do i = 1, errors%count()
      call one_error_ids(errors, i, code, rule)
      if (code == 'INTERNAL' .and. rule == expected_key) found_it = .true.
    end do
    prefix = ''
    if (present(tag)) prefix = tag//': '
    call check(prefix//'the rejection is PE_INTERNAL / '//expected_key, found_it)
  end subroutine assert_internal_commit_total

  ! ==========================================================================
  ! section 3: repeat commit, release, and the ownership flag.
  ! ==========================================================================

  subroutine group_repeat_and_ownership(problem, residue, rt)
    type(problem_state_t), intent(in) :: problem
    type(deck_residue_t), intent(in) :: residue
    type(runtime_state_t), intent(in) :: rt
    type(problem_errors_t) :: errors
    integer(ink) :: npoin_1, nelem_1
    integer(ink), allocatable :: nodfn_1(:,:)
    real(irk), allocatable :: fixed_1(:)

    ! --- first snapshot: the state left by section 1's commit of rt --------------
    npoin_1 = npoin; nelem_1 = nelem
    allocate (nodfn_1(size(nodfn, 1), size(nodfn, 2))); nodfn_1 = nodfn
    allocate (fixed_1(size(fixed))); fixed_1 = fixed

    ! --- repeat commit of the SAME runtime: bit-for-bit identical effect ---------
    call commit_legacy_globals(problem, residue, rt, errors)
    call check('repeat commit of the same runtime is accepted', .not. errors%any())
    call check('npoin identical after a repeat commit', npoin == npoin_1)
    call check('nelem identical after a repeat commit', nelem == nelem_1)
    call check('nodfn bit-for-bit identical after a repeat commit', all(nodfn == nodfn_1))
    call check('fixed bit-for-bit identical after a repeat commit', all(fixed == fixed_1))
    call check_landed(problem, rt)

    ! --- release: total, and idempotent -------------------------------------------
    call check('commit_owns_globals is true before release', commit_owns_globals())
    call commit_release()
    call check('commit_owns_globals is false after release', .not. commit_owns_globals())
    call check('element is deallocated after release', .not. allocated(element))
    call check('group is deallocated after release', .not. allocated(group))
    call check('listp_group is deallocated after release', .not. allocated(listp_group))
    call check('prescrib is deallocated after release', .not. allocated(prescrib))
    call check('tcurves is deallocated after release', .not. allocated(tcurves))
    call check('nodfn is deallocated after release', .not. allocated(nodfn))
    call check('ice0 is deallocated after release', .not. allocated(ice0))

    ! A second release must be a no-op, not a double free. This process cannot observe a
    ! double free directly (that is exactly the class of defect a process cannot see in
    ! itself, per commit's header); what IS observable and asserted here is that the
    ! second call does not crash and leaves the ownership flag and the allocations
    ! exactly as the first release left them.
    call commit_release()
    call check('a second release does not crash and stays not-owned', .not. commit_owns_globals())
    call check('element stays deallocated after a second release', .not. allocated(element))

    ! --- RELEASE TOTALITY (docs/m4/L2c-fold-design.md §5.1.3) -----------------------
    ! Every global this module publishes must be unallocated after a release. The point is
    ! NOT leak detection -- a process cannot observe its own leaks, and commit's header
    ! says so. The point is the one release-path defect that IS observable from in here:
    ! a global added to the staging and the write phase and FORGOTTEN in commit_release
    ! stays allocated, and until this check existed every test passed in that case
    ! (§5.1.2 point 3). It grows with the write phase or it stops meaning anything.
    call check('release is total: no published global is still allocated',                      &
              .not. (allocated(element) .or. allocated(group) .or. allocated(listp_group) .or.  &
                     allocated(prescrib) .or. allocated(tcurves) .or. allocated(trans) .or.     &
                     allocated(props) .or. allocated(lmdofn) .or. allocated(lcdofn) .or.        &
                     allocated(nodfn) .or. allocated(iffix) .or. allocated(fixed) .or.          &
                     allocated(appear) .or. allocated(result_zero) .or. allocated(tofor) .or.   &
                     allocated(stfor) .or. allocated(toforl) .or. allocated(toform) .or.        &
                     allocated(delitfi) .or. allocated(deltafi) .or. allocated(ice0) .or.       &
                     allocated(line_load_block) .or. allocated(line_temp_block) .or.            &
                     allocated(coord) .or. allocated(appear_process) .or.                       &
                     allocated(matno_process) .or. allocated(average_appear) .or.               &
                     allocated(factg) .or. allocated(tcurvegravity)))

    ! --- a fresh commit after release works again ---------------------------------
    call commit_legacy_globals(problem, residue, rt, errors)
    call check('a fresh commit after release is accepted', .not. errors%any())
    call check('commit_owns_globals is true after the fresh commit', commit_owns_globals())
    call check_landed(problem, rt)
  end subroutine group_repeat_and_ownership

  ! ==========================================================================
  ! section 4: globals commit_legacy_globals never registers must be untouched.
  ! ==========================================================================

  subroutine group_sentinels(problem, residue, rt)
    type(problem_state_t), intent(in) :: problem
    type(deck_residue_t), intent(in) :: residue
    type(runtime_state_t), intent(in) :: rt
    integer(ink), parameter :: SENTINEL_NMATS = 987_ink, SENTINEL_NBLKS = 654_ink
    integer(ink), parameter :: SENTINEL_RESTART = 321_ink
    real(irk), parameter :: SENTINEL_TTIME = 1.234567e8_irk
    type(problem_errors_t) :: errors

    ! nmats, nblks, restart, ttime (Global.f90:153-184) are plain global_var scalars
    ! commit_legacy_globals's own "WHAT IS WRITTEN" list never names: they belong to the
    ! ProblemState half (material count, block count, restart flag, elapsed time) that
    ! is out of scope until M4-01. Recognisable, out-of-range values make an accidental
    ! write (or an accidental read that then gets clobbered by something else in this
    ! program) visible rather than silently matching a real value by coincidence.
    nmats = SENTINEL_NMATS
    nblks = SENTINEL_NBLKS
    restart = SENTINEL_RESTART
    ttime = SENTINEL_TTIME

    call commit_legacy_globals(problem, residue, rt, errors)
    call check('commit for the sentinel check is accepted', .not. errors%any())

    call check('nmats is undisturbed by commit', nmats == SENTINEL_NMATS)
    call check('nblks is undisturbed by commit', nblks == SENTINEL_NBLKS)
    call check('restart is undisturbed by commit', restart == SENTINEL_RESTART)
    call check('ttime is undisturbed by commit', ttime == SENTINEL_TTIME)
  end subroutine group_sentinels

  ! ==========================================================================
  ! section 6: the W4 guard (yl_runtime_commit.f90, "OWNERSHIP, AND WHY A REPEAT
  ! COMMIT DOES NOT LEAK") -- move_alloc onto an already-allocated record array would
  ! silently leak whatever POINTER targets hang off the storage it replaces, so commit
  ! refuses to run at all when any of the seven record arrays it moves is allocated while
  ! commit_owned is false. Round-2 review found this guard's own list once missed one of
  ! the six (`trans`) -- exactly the door the guard exists to close -- and NOTHING in
  ! sections 1-5 exercised it, so a sixth (or seventh) omission would have shipped silent.
  !
  ! GUARDING THE GUARD, NOT JUST THE SEVEN DOORS
  !   NAMES below is this test's own list of what it believes the seven doors are. If that
  !   list and the guard's own list diverge -- a name added to one but not the other --
  !   the two would quietly drift apart the same way the module-under-test just did,
  !   with the coverage looking complete but not being it. So this section does not just
  !   walk NAMES: check_guard_names_match parses the actual "one of ... or ..." clause
  !   out of the guard's own rejection message and asserts it names exactly this test's
  !   seven, in order. Add an eighth global to the guard without adding it to NAMES (or the
  !   reverse) and that parse -- not a maintainer's memory -- is what fails.
  ! ==========================================================================

  subroutine group_foreign_allocation_guard(problem, residue, good_rt)
    type(problem_state_t), intent(in) :: problem
    type(deck_residue_t), intent(in) :: residue
    type(runtime_state_t), intent(in) :: good_rt
    character(len=11), parameter :: NAMES(7) =                                                  &
      ['element    ', 'group      ', 'listp_group', 'prescrib   ', 'tcurves    ',               &
       'trans      ', 'props      ']
    type(problem_errors_t) :: errors
    character(len=:), allocatable :: guard_message
    integer :: k, j

    do k = 1, size(NAMES)
      ! Start every door's trial from a clean released state, so "the other five are
      ! deallocated" below is a claim about THIS trial and not a leftover from the last.
      call commit_release()
      call check(trim(NAMES(k))//': released before the trial', .not. commit_owns_globals())

      call allocate_foreign(trim(NAMES(k)))

      call errors%clear()
      call commit_legacy_globals(problem, residue, good_rt, errors)
      call check(trim(NAMES(k))//': a foreign allocation is refused', errors%any())
      call assert_internal_commit_total(errors, trim(NAMES(k)))
      call check(trim(NAMES(k))//': commit_owned stays false after the refusal',                &
                .not. commit_owns_globals())

      ! No OTHER global was touched: every other one of the seven stays exactly what a
      ! released state left it -- deallocated -- and the one this trial allocated is
      ! still the size-1 foreign allocation this test made, not something move_alloc
      ! swapped in. If the guard fired too late (after staging began, say), one of the
      ! five would already be allocated too, or the trial one would carry the runtime's
      ! real extent instead of 1; either shows up here.
      do j = 1, size(NAMES)
        if (j == k) then
          call check(trim(NAMES(k))//': its own foreign allocation is untouched (still size 1)', &
                    allocated_of(trim(NAMES(j))) .and. size_of(trim(NAMES(j))) == 1)
        else
          call check(trim(NAMES(k))//': '//trim(NAMES(j))//' stays deallocated',                &
                    .not. allocated_of(trim(NAMES(j))))
        end if
      end do

      ! Captured once: the message text is the same for every door (it names all seven
      ! regardless of which one triggered it), so one capture is enough for the
      ! cross-check below.
      if (k == 1) call one_error_message(errors, 1, guard_message)

      call deallocate_foreign(trim(NAMES(k)))
    end do

    call check_guard_names_match(guard_message, NAMES)
  end subroutine group_foreign_allocation_guard

  ! ==========================================================================
  ! section 7: the four snapshot blind spots, and exactly how far their guards
  ! reach.
  !
  ! check_landed asserts them, but an assertion that cannot fail is worse than
  ! none (the same reasoning yl_runtime_selftest's check_bijection states for the
  ! forward half of its bijection). So each guard is shown to be FALSIFIABLE
  ! here: poison the real global, assert the predicate says .false., restore.
  !
  ! WHAT THESE GUARDS PROVE, AND WHAT THEY DO NOT. Read this before trusting
  ! them; the two halves are not the same strength, and the difference is the
  ! storage form, not the care taken writing them.
  !
  !   lineload / linet are PERSISTENT SCALAR globals. A poison stays where it was
  !   put, so "poison, commit again, the value must be back" is a real property:
  !   deleting commit's write of them makes this section go red. These two guards
  !   DO cover a missing write.
  !
  !   unode%np_unode is a component of a derived-type array that commit
  !   REALLOCATES on every commit: move_alloc swaps in a brand-new s_group, and
  !   the reallocation itself erases the poison. unode_elements
  !   (Global.f90:263-271) has no default initialisation, so undefined memory
  !   reads back as 0 and the restore check passes with NO WRITE AT ALL.
  !   Measured, not reasoned: deleting `s_group(ig)%unode(i)%np_unode = 0_ink`
  !   from yl_runtime_commit leaves this whole suite green at 720/720 -- under
  !   release, under `strict` (-init=snan,arrays only touches reals), and even
  !   under `sanitize` (-check uninit / MemorySanitizer, run with
  !   KMP_AFFINITY=disabled to get past a libiomp false positive). Writing the
  !   WRONG value is caught; writing NOTHING is not.
  !
  !   patch_nod / patch_sta / patch_load are worse still: once null_unode is
  !   dropped, associated() on them is undefined behaviour, so the predicate
  !   cannot even be evaluated safely and neither answer is evidence.
  !
  ! So: these guards turn "wrote the wrong value" from silent into red. They do
  ! NOT turn "never wrote it" from silent into red, and the M4-01 fold's dominant
  ! failure mode is the second one. The mechanism that closes it is poisoning the
  ! STAGING buffer at allocation (docs/m4/L2c-fold-design.md §5.5) -- that belongs
  ! to yl_runtime_commit, not here. Do not read this section as covering it.
  !
  ! For patch_nod the recommit property is deliberately NOT asserted, and the
  ! reason is itself a finding: commit_release (yl_runtime_commit.f90) frees only
  ! `unode%list`, never `patch_nod`, so re-committing over an ASSOCIATED
  ! patch_nod would move_alloc the group array away and leak the target this test
  ! allocated. The poison is therefore released here by hand. That gap in the
  ! release path is real; it is out of this program's scope to fix, and this
  ! comment is here so the next reader finds it deliberate rather than missed.
  ! ==========================================================================

  subroutine group_blind_spot_falsifiability(problem, residue, rt)
    type(problem_state_t), intent(in) :: problem
    type(deck_residue_t), intent(in) :: residue
    type(runtime_state_t), intent(in) :: rt
    type(problem_errors_t) :: errors
    integer(ink), parameter :: POISON = 7_ink

    ! Section 6 ends with every global released and commit_owned false, so this
    ! section establishes its own committed state before it poisons anything.
    call errors%clear()
    call commit_legacy_globals(problem, residue, rt, errors)
    call check('a fresh commit for the blind-spot trials is accepted', .not. errors%any())
    call check('the blind-spot guards pass on a fresh commit',                                  &
              unode_np_unode_all_zero() .and. unode_patch_pointers_all_null() .and.             &
              lineload == 0_ink .and. linet == 0_ink)

    ! --- runtime.topology.unode_np_unode -----------------------------------
    group(1)%unode(1)%np_unode = POISON
    call check('unode np_unode guard FAILS on a poisoned value',                                &
              .not. unode_np_unode_all_zero())
    call errors%clear()
    call commit_legacy_globals(problem, residue, rt, errors)
    call check('the recommit for np_unode is accepted', .not. errors%any())
    call check('unode np_unode is restored to 0 by a recommit', unode_np_unode_all_zero())

    ! --- runtime.topology.unode_patch_nod ----------------------------------
    ! One door at a time, as in section 6: patch_sta and patch_load are the same
    ! hazard through different components, and a predicate that only looked at
    ! patch_nod would be the "covers less than it says" defect all over again.
    allocate (group(1)%unode(1)%patch_nod(1))
    call check('unode patch guard FAILS on an associated patch_nod',                            &
              .not. unode_patch_pointers_all_null())
    deallocate (group(1)%unode(1)%patch_nod)
    nullify (group(1)%unode(1)%patch_nod)
    call check('unode patch guard passes again once patch_nod is released',                     &
              unode_patch_pointers_all_null())

    allocate (group(1)%unode(1)%patch_sta(1, 1))
    call check('unode patch guard FAILS on an associated patch_sta',                            &
              .not. unode_patch_pointers_all_null())
    deallocate (group(1)%unode(1)%patch_sta)
    nullify (group(1)%unode(1)%patch_sta)

    allocate (group(1)%unode(1)%patch_load(1))
    call check('unode patch guard FAILS on an associated patch_load',                           &
              .not. unode_patch_pointers_all_null())
    deallocate (group(1)%unode(1)%patch_load)
    nullify (group(1)%unode(1)%patch_load)
    call check('unode patch guard passes again once all three are released',                    &
              unode_patch_pointers_all_null())

    ! --- runtime.cursor.lineload / runtime.cursor.linet ---------------------
    lineload = POISON
    linet = POISON
    call check('the lineload guard FAILS on a poisoned value', .not. (lineload == 0_ink))
    call check('the linet guard FAILS on a poisoned value', .not. (linet == 0_ink))
    call errors%clear()
    call commit_legacy_globals(problem, residue, rt, errors)
    call check('the recommit for the cursors is accepted', .not. errors%any())
    call check('lineload is restored to 0 by a recommit', lineload == 0_ink)
    call check('linet is restored to 0 by a recommit', linet == 0_ink)

    ! Nothing above may have disturbed the rows the other sections assert: the
    ! full landing check runs once more as this section's own exit condition.
    call check_landed(problem, rt)
  end subroutine group_blind_spot_falsifiability

  ! Allocate a single-element "foreign" instance of the named record array and null
  ! exactly the pointer components yl_runtime_commit.f90 itself nulls before staging one
  ! (its null_element / null_group / null_prescrib / null_tcurve, and the inline
  ! nullify for trans in build_dof) -- the same scope, because this test never reads any
  ! OTHER component of the fake record and a full field-by-field null of, say,
  ! element_lib's dozen unrelated pointers would be scaffolding with no observable
  ! purpose here.
  subroutine allocate_foreign(name)
    character(len=*), intent(in) :: name
    select case (name)
    case ('element')
      allocate (element(1))
      nullify (element(1)%ldofs, element(1)%field, element(1)%egaus)
    case ('group')
      allocate (group(1))
      nullify (group(1)%unode)
      group(1)%np_unode = 0_ink
    case ('listp_group')
      allocate (listp_group(1))
      nullify (listp_group(1)%listg, listp_group(1)%listp)
    case ('prescrib')
      allocate (prescrib(1))
      nullify (prescrib(1)%leldofix, prescrib(1)%levdofix, prescrib(1)%lefdofix,                &
               prescrib(1)%listep, prescrib(1)%value_ext, prescrib(1)%ldofixb,                  &
               prescrib(1)%lnofixb, prescrib(1)%mlist, prescrib(1)%rintf)
    case ('tcurves')
      allocate (tcurves(1))
      nullify (tcurves(1)%dtrec, tcurves(1)%dtend, tcurves(1)%dtbegin, tcurves(1)%ample,        &
               tcurves(1)%ttime_curve, tcurves(1)%dfact_curve, tcurves(1)%time_begin,           &
               tcurves(1)%detal, tcurves(1)%fact_inc, tcurves(1)%a0sin, tcurves(1)%asin,        &
               tcurves(1)%wsin, tcurves(1)%w0sin, tcurves(1)%dx, tcurves(1)%Ca,                 &
               tcurves(1)%AI, tcurves(1)%omega, tcurves(1)%nalgo, tcurves(1)%ncdis,             &
               tcurves(1)%piter, tcurves(1)%giter, tcurves(1)%Nextr, tcurves(1)%NFS,            &
               tcurves(1)%order_stoch_parameter)
    case ('trans')
      allocate (trans(1))
      nullify (trans(1)%listf, trans(1)%rintf)
    case ('props')
      allocate (props(1))
      nullify (props(1)%mechanical, props(1)%heat, props(1)%geometry)
    end select
  end subroutine allocate_foreign

  ! The matching cleanup: a plain deallocate of the outer array. Safe without walking the
  ! pointer components above -- none of them was ever associated, so nothing hangs off
  ! this allocation for `deallocate` to leak.
  subroutine deallocate_foreign(name)
    character(len=*), intent(in) :: name
    select case (name)
    case ('element');     deallocate (element)
    case ('group');       deallocate (group)
    case ('listp_group'); deallocate (listp_group)
    case ('prescrib');    deallocate (prescrib)
    case ('tcurves');     deallocate (tcurves)
    case ('trans');       deallocate (trans)
    case ('props');       deallocate (props)
    end select
  end subroutine deallocate_foreign

  pure logical function allocated_of(name) result(v)
    character(len=*), intent(in) :: name
    select case (name)
    case ('element');     v = allocated(element)
    case ('group');       v = allocated(group)
    case ('listp_group'); v = allocated(listp_group)
    case ('prescrib');    v = allocated(prescrib)
    case ('tcurves');     v = allocated(tcurves)
    case ('trans');       v = allocated(trans)
    case ('props');       v = allocated(props)
    case default;         v = .false.
    end select
  end function allocated_of

  pure integer function size_of(name) result(n)
    character(len=*), intent(in) :: name
    select case (name)
    case ('element');     n = size(element)
    case ('group');       n = size(group)
    case ('listp_group'); n = size(listp_group)
    case ('prescrib');    n = size(prescrib)
    case ('tcurves');     n = size(tcurves)
    case ('trans');       n = size(trans)
    case ('props');       n = size(props)
    case default;         n = -1
    end select
  end function size_of

  ! Parse the guard's own "one of A, B, ..., Y or Z is already allocated" clause out of
  ! its rejection message and assert it names exactly `expected`, in order. This is what
  ! makes a divergence between the guard's list and this test's NAMES fail HERE instead
  ! of passing silently the way the missing `trans` did before Round-2 review.
  subroutine check_guard_names_match(message, expected)
    character(len=*), intent(in) :: message
    character(len=*), intent(in) :: expected(:)
    character(len=32) :: found(size(expected) + 4)   ! slack: a real divergence must show up
    integer :: n, p1, p2, orpos, pos
    character(len=:), allocatable :: body, tmp
    logical :: all_match

    n = 0
    p1 = index(message, 'one of ')
    p2 = index(message, ' is already allocated')
    if (p1 > 0 .and. p2 > p1) then
      body = message(p1 + 7:p2 - 1)
      orpos = index(body, ' or ')
      if (orpos > 0) body = body(1:orpos - 1)//', '//body(orpos + 4:)
      tmp = body
      do while (len_trim(tmp) > 0 .and. n < size(found))
        pos = index(tmp, ', ')
        n = n + 1
        if (pos > 0) then
          found(n) = adjustl(tmp(1:pos - 1))
          tmp = tmp(pos + 2:)
        else
          found(n) = adjustl(tmp)
          tmp = ''
        end if
      end do
    end if

    call check('the guard message names exactly '//itoa(size(expected))//' globals', &
              n == size(expected))
    all_match = (n == size(expected))
    if (all_match) then
      do pos = 1, n
        if (trim(found(pos)) /= trim(expected(pos))) all_match = .false.
      end do
    end if
    ! The count is derived from `expected`, not written out, for the reason this whole
    ! file keeps running into: a label that says "six" while checking seven is a small
    ! version of the same defect as a guard that covers less than it claims. It said
    ! "six" until the seventh door (props) arrived in M4-01 step 3.
    !
    ! TWO ASSERTIONS, NOT ONE, and which one fires tells you what kind of divergence it
    ! is. Measured on both variants (2026-09-09), after the same control produced 2 for
    ! one reviewer and 1 for the other and neither had said which divergence they made:
    !   * a name changed, count preserved (trans -> TRANSPOSED)  -> only the order check
    !   * a name removed, count changed   (trans dropped)        -> both checks
    ! Predicting "the guard-names check fires" is therefore not a prediction of a NUMBER
    ! until the kind of divergence is stated too.
    call check('the guard message names this test''s '//itoa(size(expected))//               &
              ' globals, in order', all_match)
  end subroutine check_guard_names_match

  subroutine one_error_message(errors, i, message)
    type(problem_errors_t), intent(inout) :: errors
    integer, intent(in) :: i
    character(len=:), allocatable, intent(out) :: message
    ! Same wrapper shape as one_error_ids, for the one field it does not already expose.
    block
      use yl_problem_errors, only: problem_error_t
      type(problem_error_t) :: e
      logical :: found
      call errors%get(i, e, found)
      if (.not. found) then
        message = ''
      else
        message = opt_value_or(e%message, '')
      end if
    end block
  end subroutine one_error_message

  ! ==========================================================================
  ! harness
  ! ==========================================================================

  subroutine check(label, condition)
    character(len=*), intent(in) :: label
    logical, intent(in) :: condition
    n_check = n_check + 1
    if (condition) then
      write (output_unit, '(a)') '  ok   '//label
    else
      n_fail = n_fail + 1
      write (output_unit, '(a)') '  BAD  '//label
    end if
  end subroutine check

  subroutine one_error_ids(errors, i, code, rule)
    type(problem_errors_t), intent(inout) :: errors
    integer, intent(in) :: i
    character(len=:), allocatable, intent(out) :: code, rule
    ! problem_errors_t stores problem_error_t privately; %get(i, e, found) is its only
    ! reader (yl_problem_errors.f90). This wrapper exists because a local
    ! type(problem_error_t) can't be declared without importing more of that module's
    ! private-implementation-adjacent surface than this test needs.
    block
      use yl_problem_errors, only: problem_error_t
      type(problem_error_t) :: e
      logical :: found
      call errors%get(i, e, found)
      if (.not. found) then
        code = ''; rule = ''
      else
        code = opt_value_or(e%code, '')
        rule = opt_value_or(e%rule_id, '')
      end if
    end block
  end subroutine one_error_ids

  subroutine report_errors(where, errors)
    character(len=*), intent(in) :: where
    type(problem_errors_t), intent(inout) :: errors
    integer :: i
    do i = 1, errors%count()
      write (output_unit, '(a)') '    '//where//': '//errors%render(i)
    end do
  end subroutine report_errors

  pure function itoa(v) result(s)
    integer, intent(in) :: v
    character(len=:), allocatable :: s
    character(len=24) :: buf
    write (buf, '(i0)') v
    s = trim(buf)
  end function itoa

  subroutine summary()
    character(len=32) :: a, c
    write (output_unit, '(a)') ''
    write (output_unit, '(a)') 'CONCLUSION: PARTIAL. This binary shows that ' //                &
      'commit_legacy_globals lands the model_ready RuntimeState rows in the real ' //           &
      'legacy globals with the right extents and kinds, that a rejected commit ' //             &
      'touches nothing, that a repeat commit and a release/recommit cycle are ' //              &
      'bit-for-bit stable in their effect, and that globals outside the commit ' //             &
      'contract are undisturbed. It does NOT run any solver consumer, does NOT ' //             &
      'compare against the frozen M2 baseline (no deck-to-ProblemState reader exists ' //       &
      'yet -- M4-01), and CANNOT show the absence of a leak or a use-after-free from ' //       &
      'inside this process.'
    write (a, '(i0)') n_check - n_fail
    write (c, '(i0)') n_check
    if (n_fail == 0) then
      write (output_unit, '(a)') 'PASS: '//trim(a)//'/'//trim(c)
    else
      write (output_unit, '(a)') 'FAIL: '//trim(a)//'/'//trim(c)
      stop 1
    end if
  end subroutine summary

end program yl_runtime_bridge_test
