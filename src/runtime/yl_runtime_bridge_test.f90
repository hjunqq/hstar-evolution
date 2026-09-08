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
                        nmats, nblks, restart, ttime
  use prescribed, only: prescrib, ndofix
  use applied_load, only: tcurves, ntcurve
  use meshfine, only: ice0

  use variable_types, only: ink, irk

  use yl_problem_optional, only: opt_int, opt_real, opt_set, opt_get, opt_value_or
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
  use yl_runtime_commit, only: commit_legacy_globals, commit_release, commit_owns_globals
  use yl_runtime_rules, only: build_rule_count, build_rule_id, build_rule_key

  implicit none

  integer :: n_check = 0, n_fail = 0
  type(runtime_state_t), allocatable :: rt1, rt2

  write (output_unit, '(a)') 'yl_runtime_bridge_test: M3-03 isolated bridge (commit_legacy_globals)'

  write (output_unit, '(a)') '-- 1. commit lands the values (1-element draft)'
  call build_and_commit(1, rt1)
  call check_landed(rt1)

  write (output_unit, '(a)') '-- 2. commit lands the values (2-element draft)'
  call build_and_commit(2, rt2)
  call check_landed(rt2)

  write (output_unit, '(a)') '-- 3. no partial commit'
  call group_no_partial(rt2)

  write (output_unit, '(a)') '-- 4. repeat load / ownership'
  call group_repeat_and_ownership(rt2)

  write (output_unit, '(a)') '-- 5. unregistered globals are not disturbed'
  call group_sentinels(rt2)

  write (output_unit, '(a)') '-- 6. the W4 foreign-allocation guard, one door at a time'
  call group_foreign_allocation_guard(rt2)

  call summary()

contains

  ! ==========================================================================
  ! section 1: build a draft through the real pipeline+builder, build_runtime,
  ! commit, and leave `rt` holding the runtime that was committed so later
  ! sections can re-verify against it.
  ! ==========================================================================

  subroutine build_and_commit(n_elem, rt)
    integer, intent(in) :: n_elem
    type(runtime_state_t), allocatable, intent(out) :: rt
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

    call commit_legacy_globals(rt, errors)
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

    call opt_set(sc%name, 'g1')
    call opt_set(sc%element, 'Q4')
    call opt_set(sc%element_kind, 5_int32)
    call opt_set(sc%class, 'CO')
    call opt_set(sc%fields, 'U')
    call opt_set(sc%formulation, 'PE')
    call opt_set(sc%special, 'ST')
    call opt_set(sc%material, 1_int32)
    call opt_set(sc%material_header, 1_int32)
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
    call opt_set(pt%time, 1.0_real64)
    call opt_set(pt%value, 1.0_real64)
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

    do k = 1, 2
      call opt_set(bd%name, int(k, int32))
      call opt_set(bd%nset, int(k, int32))
      call opt_set(bd%dof, int(k, int32))
      call opt_set(bd%value, 0.0_real64)
      call opt_set(bd%amplitude, 1_int32)
      call opt_set(bd%record_reaction, 0_int32)
      call builder_step_add_boundary(b, sb, bd, loc, errors)
    end do

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

  subroutine check_landed(rt)
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

    ! --- tcurves(:)%dfact ----------------------------------------------------------
    do i = 1, size(rt%amplitudes)
      call check('tcurves('//itoa(i)//')%dfact',                                                &
                tcurves(i)%dfact == real(opt_value_or(rt%amplitudes(i)%factor, 0.0_real64), irk))
    end do
  end subroutine check_landed

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

  subroutine group_no_partial(rt_good)
    type(runtime_state_t), intent(in) :: rt_good
    type(runtime_state_t) :: rt_bad     ! default-initialised: never handed to build_runtime
    type(problem_errors_t) :: errors
    integer :: bad_npoin, bad_nelem
    real(irk), allocatable :: bad_result_zero(:)

    ! rt_bad's field_status is unallocated (default init, yl_runtime_types.f90), so
    ! runtime_status_count(rt_bad) is 0 against build_rule_produced_count() > 0: the
    ! FIRST check inside verify_registered, before any staging allocation runs. This is
    ! "a runtime that was never built", the simplest of the two shapes the task allows.
    call commit_legacy_globals(rt_bad, errors)
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
    call check_landed(rt_good)
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

  subroutine group_repeat_and_ownership(rt)
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
    call commit_legacy_globals(rt, errors)
    call check('repeat commit of the same runtime is accepted', .not. errors%any())
    call check('npoin identical after a repeat commit', npoin == npoin_1)
    call check('nelem identical after a repeat commit', nelem == nelem_1)
    call check('nodfn bit-for-bit identical after a repeat commit', all(nodfn == nodfn_1))
    call check('fixed bit-for-bit identical after a repeat commit', all(fixed == fixed_1))
    call check_landed(rt)

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

    ! --- a fresh commit after release works again ---------------------------------
    call commit_legacy_globals(rt, errors)
    call check('a fresh commit after release is accepted', .not. errors%any())
    call check('commit_owns_globals is true after the fresh commit', commit_owns_globals())
    call check_landed(rt)
  end subroutine group_repeat_and_ownership

  ! ==========================================================================
  ! section 4: globals commit_legacy_globals never registers must be untouched.
  ! ==========================================================================

  subroutine group_sentinels(rt)
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

    call commit_legacy_globals(rt, errors)
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
  ! refuses to run at all when any of the six record arrays it moves is allocated while
  ! commit_owned is false. Round-2 review found this guard's own list once missed one of
  ! the six (`trans`) -- exactly the door the guard exists to close -- and NOTHING in
  ! sections 1-5 exercised it, so a sixth (or seventh) omission would have shipped silent.
  !
  ! GUARDING THE GUARD, NOT JUST THE SIX DOORS
  !   NAMES below is this test's own list of what it believes the six doors are. If that
  !   list and the guard's own list diverge -- a name added to one but not the other --
  !   the two would quietly drift apart the same way the module-under-test just did,
  !   with the coverage looking complete but not being it. So this section does not just
  !   walk NAMES: check_guard_names_match parses the actual "one of ... or ..." clause
  !   out of the guard's own rejection message and asserts it names exactly this test's
  !   six, in order. Add a seventh global to the guard without adding it to NAMES (or the
  !   reverse) and that parse -- not a maintainer's memory -- is what fails.
  ! ==========================================================================

  subroutine group_foreign_allocation_guard(good_rt)
    type(runtime_state_t), intent(in) :: good_rt
    character(len=11), parameter :: NAMES(6) =                                                  &
      ['element    ', 'group      ', 'listp_group', 'prescrib   ', 'tcurves    ', 'trans      ']
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
      call commit_legacy_globals(good_rt, errors)
      call check(trim(NAMES(k))//': a foreign allocation is refused', errors%any())
      call assert_internal_commit_total(errors, trim(NAMES(k)))
      call check(trim(NAMES(k))//': commit_owned stays false after the refusal',                &
                .not. commit_owns_globals())

      ! No OTHER global was touched: every other one of the six stays exactly what a
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

      ! Captured once: the message text is the same for every door (it names all six
      ! regardless of which one triggered it), so one capture is enough for the
      ! cross-check below.
      if (k == 1) call one_error_message(errors, 1, guard_message)

      call deallocate_foreign(trim(NAMES(k)))
    end do

    call check_guard_names_match(guard_message, NAMES)
  end subroutine group_foreign_allocation_guard

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
    call check('the guard message names this test''s six globals, in order', all_match)
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
