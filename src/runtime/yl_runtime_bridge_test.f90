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
                        nmats, nblks, restart, ttime,                                            &
                        uinitial, probn, outplot, type_problem, type_solver, type_load,         &
                        type_ABC, type_nl, nonsym, NGRAV, gid_u, gid_s, gid_ms, gid_f,          &
                        gid_rot, gid_v, gid_a, gid_T, gid_P, gid_Pv, gid_ep, gid_Y, gid_FC,     &
                        gid_Ns, gid_Ss, gid_Mxy, gid_bem, gid_wh, gid_wv, gid_bcs,              &
                        relis, ADINA, runblks, npoinb, nlayer, block_stab, nbackf, ebody,       &
                        ninit, state_change, Bparameter, stab_matde, nlinks, nsmat, ntrans
  use prescribed, only: prescrib, ndofix, nfixsets
  use materials, only: props
  use applied_load, only: tcurves, ntcurve, factg, tcurvegravity, gravy,                &
                          nplgroup, nedge, edge_load_group, delgroup, nbeamload,        &
                          nplateload
  use meshfine, only: ice0
  use temperature, only: ntemp_surface, ntedge, ntelgroup, npipe

  use variable_types, only: ink, irk

  use yl_problem_optional, only: opt_int, opt_real, opt_set, opt_get, opt_value_or
  use yl_problem_deck_residue, only: deck_residue_t
  use yl_problem_existence, only: deck_existence_t
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
  type(deck_existence_t) :: ex
  logical :: ok1, ok2

  write (output_unit, '(a)') 'yl_runtime_bridge_test: M3-03 isolated bridge (commit_legacy_globals)'

  write (output_unit, '(a)') '-- 1. commit lands the values (1-element draft)'
  call build_and_commit(1, rt1, pr1, rs1, ok1)
  if (ok1) then
    call check_landed(pr1, rs1, rt1)
  else
    call skip_landed('1-element draft')
  end if

  write (output_unit, '(a)') '-- 2. commit lands the values (2-element draft)'
  call build_and_commit(2, rt2, pr2, rs2, ok2)
  if (ok2) then
    call check_landed(pr2, rs2, rt2)
  else
    call skip_landed('2-element draft')
  end if

  write (output_unit, '(a)') '-- 2b. the problem and the runtime must describe one model'
  call group_extent_agreement(pr1, pr2, rs1, rt1, rt2)

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

  !> `ok` is .true. only when the globals actually carry this runtime afterwards. Every
  !> caller must consult it before reading a committed global: on any of the three early
  !> exits below -- and on a REFUSED commit, which is the interesting one -- the globals
  !> are exactly as commit found them, which on this path means unallocated. See the note
  !> above check_landed for what reading them anyway actually did.
  subroutine build_and_commit(n_elem, rt, problem_out, residue_out, ok)
    integer, intent(in) :: n_elem
    type(runtime_state_t), allocatable, intent(out) :: rt
    !> The ProblemState and the deck residue this commit was made with. Handed back
    !> because commit_legacy_globals now takes all three and the later sections re-commit
    !> the same runtime: they must re-commit it with the same inputs, not with fresh
    !> default-initialised ones, or "repeat commit is bit-for-bit identical" would be
    !> comparing two different calls.
    type(problem_state_t), allocatable, intent(out) :: problem_out
    type(deck_residue_t), intent(out) :: residue_out
    logical, intent(out) :: ok
    type(problem_state_t), allocatable :: draft, problem
    type(manifest_t), allocatable :: pmanifest, rmanifest
    type(problem_errors_t) :: errors
    logical :: built

    ! .false. until the commit has actually happened, so every `return` below leaves it
    ! saying "nothing was committed" without each one having to remember to.
    ok = .false.

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
    call residue_of(residue_out)
    ! The existence face's one row is sized by mdofn, which this fixture's draft fixes
    ! at 2 (draft_of). Sized here rather than read back from a legacy global because
    ! commit has not run yet.
    call existence_of(ex, 2)
    call commit_legacy_globals(problem_out, residue_out, ex, rt, errors)
    call check('commit_legacy_globals accepted the '//itoa(n_elem)//'-element runtime',          &
              .not. errors%any())
    built = .not. errors%any()
    if (.not. built) then
      ! ONE finding for a refusal, not two: 'commit_owns_globals is true after a
      ! successful commit' asserts a consequence of a success that did not happen, and
      ! firing it here would report the same fact a second time under a name that
      ! presupposes the opposite. That globals stay unowned after a refusal is asserted
      ! where it belongs -- group_foreign_allocation_guard, on a refusal it provoked.
      call report_errors('commit_legacy_globals', errors)
      return
    end if
    call check('commit_owns_globals is true after a successful commit', commit_owns_globals())
    ok = commit_owns_globals()
  end subroutine build_and_commit

  !> A COMPLETE deck residue, because commit refuses an incomplete one (M4-01 step 5a).
  !>
  !> This program owns no deck, so no parser can fill the carrier for it -- it authors all
  !> 27 components itself, the same way it authors every ProblemState scalar rather than
  !> letting opt_or's fallback stand in for a value. Every value here is the one the two
  !> golden decks carry, which is what makes it a fixture for this capability rather than
  !> an arbitrary filling: all zero except `runblks` (1 step), `nsmat` (1, corrected in
  !> 0646de3 against a map note that said 0), `npoinb` (= npoin) and `stab_matde`
  !> (99999, the disabling sentinel both decks use).
  !>
  !> It is deliberately NOT derived from the type: a loop that set every component to 0
  !> would pass verify_residue_inputs while saying nothing, and the three non-zero values
  !> are exactly the ones such a loop would get wrong.
  !> A COMPLETE existence face (ADR-0009), for the same reason residue_of exists: commit
  !> refuses an unallocated component, and an empty array would read like a deck record
  !> nobody wrote. mdofn in this fixture is what build_and_commit uses.
  subroutine existence_of(e, mdofn)
    type(deck_existence_t), intent(out) :: e
    integer, intent(in) :: mdofn
    allocate (e%order_time_mdofn(mdofn))
    e%order_time_mdofn = 0
  end subroutine existence_of

  subroutine residue_of(r)
    type(deck_residue_t), intent(out) :: r
    call opt_set(r%restart, 0_int32)
    call opt_set(r%relis, 0_int32)
    call opt_set(r%adina, 0_int32)
    call opt_set(r%runblks, 1_int32)
    call opt_set(r%ninit, 0_int32)
    call opt_set(r%nlinks, 0_int32)
    call opt_set(r%block_stab, 0_int32)
    call opt_set(r%nbackf, 0_int32)
    call opt_set(r%ebody, 0_int32)
    call opt_set(r%nlayer, 0_int32)
    call opt_set(r%state_change, 0_int32)
    call opt_set(r%bparameter, 0_int32)
    call opt_set(r%ntrans, 0_int32)
    call opt_set(r%stab_matde, 99999_int32)
    call opt_set(r%npoinb, 0_int32)
    call opt_set(r%nsmat, 1_int32)
    call opt_set(r%nplgroup, 0_int32)
    call opt_set(r%nedge, 0_int32)
    call opt_set(r%edge_load_group, 0_int32)
    call opt_set(r%delgroup, 0_int32)
    call opt_set(r%nbeamload, 0_int32)
    call opt_set(r%nplateload, 0_int32)
    call opt_set(r%ntemp_surface, 0_int32)
    call opt_set(r%ntedge, 0_int32)
    call opt_set(r%ntelgroup, 0_int32)
    call opt_set(r%npipe, 0_int32)
    if (allocated(r%uinitial)) deallocate (r%uinitial)
    allocate (r%uinitial(1))
    r%uinitial = 0_int32
  end subroutine residue_of

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
  subroutine draft_of(n_elem, draft, two_amplitudes, spare_nodes, two_sections)
    integer, intent(in) :: n_elem
    type(problem_state_t), allocatable, intent(out) :: draft
    !> Keep the 6-node mesh but author only ONE element, leaving nodes 5 and 6 attached to
    !> nothing. Same node count as the 2-element draft, different element count -- which is
    !> what makes the ELEMENTS arm of the agreement gate reachable at all: the 1- and
    !> 2-element drafts differ in BOTH counts, so pairing them fires the nodes arm first and
    !> the elements arm is never the thing under test. Only n_elem == 1 uses it.
    logical, intent(in), optional :: spare_nodes
    !> Split the 2-element mesh across TWO element sets and two sections instead of one.
    !> Same nodes, same elements, different section count -- the SECTIONS arm, isolated the
    !> same way. Only n_elem == 2 uses it.
    logical, intent(in), optional :: two_sections
    !> Add a SECOND amplitude, changing nothing else. It exists so a problem can disagree
    !> with a runtime on the amplitude count while agreeing on every mesh extent -- which
    !> is what makes the amplitude arm of the agreement gate separately falsifiable from
    !> the node and element arms.
    logical, intent(in), optional :: two_amplitudes
    logical :: want_two, want_spare, want_split

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
    want_spare = .false.
    if (present(spare_nodes)) want_spare = spare_nodes
    want_split = .false.
    if (present(two_sections)) want_split = two_sections

    if (n_elem == 1 .and. want_spare) then
      ! The 2-element mesh's NODES with the 1-element mesh's elements. Nodes 5 and 6 belong
      ! to no element; nothing prescribes them (the boundary records name nodes 4 and 1,
      ! both corners of element 1) and no rule requires a node to be used.
      n_node = 6
      allocate (xs(6), ys(6))
      xs = [0.0_real64, 1.0_real64, 1.0_real64, 0.0_real64, 2.0_real64, 2.0_real64]
      ys = [0.0_real64, 0.0_real64, 1.0_real64, 1.0_real64, 0.0_real64, 1.0_real64]
    else if (n_elem == 1) then
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
      call builder_add_elset(b, es, loc, errors)
    else if (want_split) then
      allocate (es%elements(1)); es%elements = [1_int32]
      call builder_add_elset(b, es, loc, errors)
      deallocate (es%elements)
      allocate (es%elements(1)); es%elements = [2_int32]
      call builder_add_elset(b, es, loc, errors)
    else
      allocate (es%elements(2)); es%elements = [1_int32, 2_int32]
      call builder_add_elset(b, es, loc, errors)
    end if

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
    if (want_split) then
      ! A second section over the second element set. Identical in every authored field
      ! except its name, because the point of this draft is that ONLY the section count
      ! differs from the single-section 2-element draft.
      call opt_set(sc%name, 'g2')
      call builder_add_section(b, sc, loc, errors)
    end if

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

    want_two = .false.
    if (present(two_amplitudes)) want_two = two_amplitudes
    if (want_two) then
      call builder_amplitude_begin(ab)
      call builder_amplitude_set_name(b, ab, 'a2', loc, errors)
      call builder_amplitude_set_type(b, ab, 'LINEAR', loc, errors)
      call opt_set(pt%time, 0.0_real64)
      call opt_set(pt%value, 1.0_real64)
      call builder_amplitude_add_point(b, ab, pt, loc, errors)
      call opt_set(pt%time, 1.0_real64)
      call opt_set(pt%value, 3.5_real64)
      call builder_amplitude_add_point(b, ab, pt, loc, errors)
      call builder_amplitude_finish(b, ab, am, loc, errors)
      call builder_add_amplitude(b, am, loc, errors)
    end if

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
    ! One entry PER SECTION, not per element: the split draft has two sections over the
    ! same two elements, and the pipeline rejects a short list outright.
    if (allocated(ld%gravity%amplitude)) deallocate (ld%gravity%amplitude)
    if (want_split) then
      allocate (ld%gravity%amplitude(2)); ld%gravity%amplitude = [1_int32, 1_int32]
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
    ! Per section as well, for the same reason.
    if (allocated(ou%stress_averaging)) deallocate (ou%stress_averaging)
    if (want_split) then
      allocate (ou%stress_averaging(2)); ou%stress_averaging = [2_int32, 2_int32]
    else
      allocate (ou%stress_averaging(1)); ou%stress_averaging = [2_int32]
    end if
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
    ! One activation entry PER SECTION: build_boundary indexes activation by section, so a
    ! second section with no entry would read as inactive and free no variable.
    if (want_split) call builder_step_add_activation(b, sb, ac, loc, errors)

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

  ! NOTHING BELOW IS DEFINED AFTER A REFUSED COMMIT, and that is not a theoretical worry.
  ! commit_legacy_globals leaves every global exactly as it found it, which on this path
  ! means unallocated -- so a value walk dereferences unallocated allocatables. It did.
  ! The SAME source and the SAME negative control (drop one boundary record so the
  ! alignment precondition refuses) behaved two different ways in two build trees: one
  ! segfaulted at the first element assertion, the other ran on into an unallocated
  ! `prescrib` and printed 17 "failures". Neither number was evidence -- the 17 were
  ! simply the reads that happened not to fault, and the run that crashed never reached
  ! the assertions someone then reported as "not failing".
  !
  ! So a refusal must produce ONE finding, the refusal, and no value walk at all. This is
  ! the same shape as the five `n == 0` rows in L2c-fold-design.md 2 -- a failure mode
  ! that is itself irreproducible -- except here it was in the harness rather than the
  ! dump, which is why the harness is where it is fixed.
  subroutine check_landed_guarded(problem, residue, rt, site)
    type(problem_state_t), intent(in) :: problem
    type(deck_residue_t), intent(in) :: residue
    type(runtime_state_t), intent(in) :: rt
    character(len=*), intent(in) :: site
    if (.not. commit_owns_globals()) then
      call skip_landed(site)
      return
    end if
    call check_landed(problem, residue, rt)
  end subroutine check_landed_guarded

  !> Visible, and deliberately NOT a check: a skipped walk must not read as a passing one.
  !> The suite's total falls, which is the signal that something was not examined.
  subroutine skip_landed(site)
    character(len=*), intent(in) :: site
    write (output_unit, '(a)') '  SKIP check_landed ('//site//'): the commit was refused, '//   &
      'so no committed global is defined to read'
  end subroutine skip_landed

  subroutine check_landed(problem, residue, rt)
    type(problem_state_t), intent(in) :: problem
    type(deck_residue_t), intent(in) :: residue
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
    ! The last two element rows (step 4). Asserted separately from matno and from each
    ! other: all three are small integers in one record, so a source mix-up between them is
    ! a value swap. The fixture keeps them apart -- kind is 5 (Q4) and elset is 1 or 2 --
    ! and the two-section draft below makes elset actually vary.
    ok_all = .true.
    do ie = 1, size(problem%mesh%elements)
      if (element(ie)%index /= int(opt_value_or(problem%mesh%elements(ie)%kind, 0_int32), ink)) &
        ok_all = .false.
    end do
    call check('element(:)%index matches mesh.elements[].kind', ok_all)
    ok_all = .true.
    do ie = 1, size(problem%mesh%elements)
      if (element(ie)%group /= int(opt_value_or(problem%mesh%elements(ie)%elset, 0_int32), ink))&
        ok_all = .false.
    end do
    call check('element(:)%group matches mesh.elements[].elset', ok_all)
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
    ! --- step 4 (group): the four derived section rows ------------------------------
    ok_all = .true.
    do ig = 1, size(problem%sections)
      ! nrfields against the runtime it is read from, not against a literal.
      if (group(ig)%nrfields /= int(size(rt%dof%element_field_variables(                        &
            int(problem%mesh%elsets(ig)%elements(1)))%fields), ink)) ok_all = .false.
    end do
    call check('group(:)%nrfields is the runtime field count', ok_all)
    ok_all = .true.
    do ig = 1, size(problem%sections)
      ! nfdof recomputed from the same two runtime extents the commit used. This restates
      ! the derivation rather than the answer on purpose: a fixture where nevab/nnode
      ! happens to equal something else would otherwise pass.
      if (group(ig)%dof(1)%nfdof /=                                                             &
          int(size(rt%dof%element_variables(1)%values) /                                        &
              size(rt%element(1)%field_coordinates, 2), ink)) ok_all = .false.
      if (size(group(ig)%dof) /= int(group(ig)%nrfields)) ok_all = .false.
    end do
    call check('group(:)%dof is nrfields long and each nfdof is nevab/nnode', ok_all)
    ok_all = .true.
    do ig = 1, size(problem%sections)
      if (.not. associated(group(ig)%dof(1)%listdof_f)) then
        ok_all = .false.
      else if (size(group(ig)%dof(1)%listdof_f) /= int(group(ig)%dof(1)%nfdof)) then
        ok_all = .false.
      else if (any(group(ig)%dof(1)%listdof_f /=                                                &
                   int(rt%dof%active_to_component(1:group(ig)%dof(1)%nfdof), ink))) then
        ok_all = .false.
      end if
    end do
    call check('group(:)%dof(:)%listdof_f is the runtime component list', ok_all)
    ! nstre by legacy's own rule, restated here from the same three inputs. Q4/CO in 2-D
    ! gives 4 -- NOT the 3 that 3*(ndimn-1) alone would give, which is the whole reason
    ! the overwrite at Global.f90:1287 has to be transcribed in order.
    ok_all = .true.
    do ig = 1, size(problem%sections)
      if (group(ig)%nstre /= 4_ink) ok_all = .false.
    end do
    call check('group(:)%nstre is 4 for a 2-D non-beam section', ok_all)
    ! matno is the EFFECTIVE material and material_header the pre-overwrite one. Asserted
    ! as a PAIR against their two different ProblemState fields, because they are equal on
    ! the golden decks and a swap would be invisible to either check alone.
    call check('group(:)%matno is sections[].material, not .material_header',                   &
              all([(group(ig)%matno ==                                                          &
                    int(opt_value_or(problem%sections(ig)%material, 0_int32), ink),             &
                    ig=1, size(problem%sections))]))

    ! --- step 5b: the C2 scalars and the residue's 27 -------------------------------
    ! Characters compared trim()ed on both sides: legacy's slots are short (outplot is
    ! character(20), type_* character(50), probn character(200)) and a longer value is
    ! truncated silently on assignment, which the staging poison cannot see.
    call check('probn is case.name', trim(probn) == trim(opt_value_or(problem%case%name, '')))
    call check('outplot is steps[0].output.format',                                             &
              trim(outplot) == trim(opt_value_or(problem%steps(1)%output%format, '')))
    call check('type_problem is steps[0].procedure',                                            &
              trim(type_problem) == trim(opt_value_or(problem%steps(1)%procedure, '')))
    call check('type_solver is solver.linear',                                                  &
              trim(type_solver) == trim(opt_value_or(problem%solver%linear, '')))
    call check('type_load is steps[0].load_mode',                                               &
              trim(type_load) == trim(opt_value_or(problem%steps(1)%load_mode, '')))
    call check('type_ABC is interactions.absorbing.type',                                       &
              trim(type_ABC) == trim(opt_value_or(problem%interactions%absorbing%type, '')))
    call check('type_nl is steps[0].controls.nonlinear_type',                                   &
              type_nl == int(opt_value_or(problem%steps(1)%controls%nonlinear_type, 0_int32), ink))
    call check('NGRAV is steps[0].load.gravity.enabled',                                        &
              NGRAV == int(opt_value_or(problem%steps(1)%load%gravity%enabled, 0_int32), ink))
    call check('gravy is steps[0].load.gravity.magnitude',                                      &
              gravy == real(opt_value_or(problem%steps(1)%load%gravity%magnitude, 0.0_real64), irk))
    ! THE INVERSION, asserted as an inversion: the fixture authors symmetric = .true., so
    ! nonsym must be 0 and a bridge that forgot to invert would write 1.
    call check('nonsym is the INVERSE of solver.symmetric',                                     &
              nonsym == merge(0_ink, 1_ink, opt_value_or(problem%solver%symmetric, .false.)))
    ! The three derived counts, against the cardinalities they are derived from.
    call check('nmats is count(materials)', nmats == int(size(problem%materials), ink))
    call check('nblks is count(steps)', nblks == int(size(problem%steps), ink))
    call check('nfixsets is count(mesh.nsets)', nfixsets == int(size(problem%mesh%nsets), ink))
    ! The 20 GiD switches, one assertion each. A single all() over an array would pass on a
    ! transposition, which is the only error shape that matters here: they are all 0 or 1.
    ok_all = .true.
    if (gid_u /= int(opt_value_or(problem%steps(1)%output%field%u, 0_int32), ink)) ok_all = .false.
    if (gid_s /= int(opt_value_or(problem%steps(1)%output%field%s, 0_int32), ink)) ok_all = .false.
    if (gid_ms /= int(opt_value_or(problem%steps(1)%output%field%ms, 0_int32), ink)) ok_all = .false.
    if (gid_f /= int(opt_value_or(problem%steps(1)%output%field%f, 0_int32), ink)) ok_all = .false.
    if (gid_rot /= int(opt_value_or(problem%steps(1)%output%field%rot, 0_int32), ink)) ok_all = .false.
    if (gid_v /= int(opt_value_or(problem%steps(1)%output%field%v, 0_int32), ink)) ok_all = .false.
    if (gid_a /= int(opt_value_or(problem%steps(1)%output%field%a, 0_int32), ink)) ok_all = .false.
    if (gid_T /= int(opt_value_or(problem%steps(1)%output%field%T, 0_int32), ink)) ok_all = .false.
    if (gid_P /= int(opt_value_or(problem%steps(1)%output%field%P, 0_int32), ink)) ok_all = .false.
    if (gid_Pv /= int(opt_value_or(problem%steps(1)%output%field%Pv, 0_int32), ink)) ok_all = .false.
    if (gid_ep /= int(opt_value_or(problem%steps(1)%output%field%ep, 0_int32), ink)) ok_all = .false.
    if (gid_Y /= int(opt_value_or(problem%steps(1)%output%field%Y, 0_int32), ink)) ok_all = .false.
    if (gid_FC /= int(opt_value_or(problem%steps(1)%output%field%FC, 0_int32), ink)) ok_all = .false.
    if (gid_Ns /= int(opt_value_or(problem%steps(1)%output%field%Ns, 0_int32), ink)) ok_all = .false.
    if (gid_Ss /= int(opt_value_or(problem%steps(1)%output%field%Ss, 0_int32), ink)) ok_all = .false.
    if (gid_Mxy /= int(opt_value_or(problem%steps(1)%output%field%Mxy, 0_int32), ink)) ok_all = .false.
    if (gid_bem /= int(opt_value_or(problem%steps(1)%output%field%bem, 0_int32), ink)) ok_all = .false.
    if (gid_wh /= int(opt_value_or(problem%steps(1)%output%field%wh, 0_int32), ink)) ok_all = .false.
    if (gid_wv /= int(opt_value_or(problem%steps(1)%output%field%wv, 0_int32), ink)) ok_all = .false.
    if (gid_bcs /= int(opt_value_or(problem%steps(1)%output%field%bcs, 0_int32), ink)) ok_all = .false.
    call check('the 20 gid_* switches match steps[0].output.field[] one for one', ok_all)
    ! The residue's 27, each against the carrier it came from.
    ok_all = .true.
    if (restart /= int(opt_value_or(residue%restart, 0_int32), ink)) ok_all = .false.
    if (relis /= int(opt_value_or(residue%relis, 0_int32), ink)) ok_all = .false.
    if (ADINA /= int(opt_value_or(residue%adina, 0_int32), ink)) ok_all = .false.
    if (runblks /= int(opt_value_or(residue%runblks, 0_int32), ink)) ok_all = .false.
    if (npoinb /= int(opt_value_or(residue%npoinb, 0_int32), ink)) ok_all = .false.
    if (nlayer /= int(opt_value_or(residue%nlayer, 0_int32), ink)) ok_all = .false.
    if (block_stab /= int(opt_value_or(residue%block_stab, 0_int32), ink)) ok_all = .false.
    if (nbackf /= int(opt_value_or(residue%nbackf, 0_int32), ink)) ok_all = .false.
    if (ebody /= int(opt_value_or(residue%ebody, 0_int32), ink)) ok_all = .false.
    if (ninit /= int(opt_value_or(residue%ninit, 0_int32), ink)) ok_all = .false.
    if (state_change /= int(opt_value_or(residue%state_change, 0_int32), ink)) ok_all = .false.
    if (Bparameter /= int(opt_value_or(residue%bparameter, 0_int32), ink)) ok_all = .false.
    if (stab_matde /= int(opt_value_or(residue%stab_matde, 0_int32), ink)) ok_all = .false.
    if (nlinks /= int(opt_value_or(residue%nlinks, 0_int32), ink)) ok_all = .false.
    if (nsmat /= int(opt_value_or(residue%nsmat, 0_int32), ink)) ok_all = .false.
    if (ntrans /= int(opt_value_or(residue%ntrans, 0_int32), ink)) ok_all = .false.
    if (nplgroup /= int(opt_value_or(residue%nplgroup, 0_int32), ink)) ok_all = .false.
    if (nedge /= int(opt_value_or(residue%nedge, 0_int32), ink)) ok_all = .false.
    if (edge_load_group /= int(opt_value_or(residue%edge_load_group, 0_int32), ink)) ok_all = .false.
    if (delgroup /= int(opt_value_or(residue%delgroup, 0_int32), ink)) ok_all = .false.
    if (nbeamload /= int(opt_value_or(residue%nbeamload, 0_int32), ink)) ok_all = .false.
    if (nplateload /= int(opt_value_or(residue%nplateload, 0_int32), ink)) ok_all = .false.
    if (ntemp_surface /= int(opt_value_or(residue%ntemp_surface, 0_int32), ink)) ok_all = .false.
    if (ntedge /= int(opt_value_or(residue%ntedge, 0_int32), ink)) ok_all = .false.
    if (ntelgroup /= int(opt_value_or(residue%ntelgroup, 0_int32), ink)) ok_all = .false.
    if (npipe /= int(opt_value_or(residue%npipe, 0_int32), ink)) ok_all = .false.
    call check('the 26 residue scalars reach their globals', ok_all)
    call check('uinitial is allocated at nblks and carries the residue values',                 &
              allocated(uinitial) .and. size(uinitial) == size(residue%uinitial) .and.          &
              all(uinitial == int(residue%uinitial, ink)))

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

  ! ==========================================================================
  ! section 2b: the agreement gate, FIRED rather than merely asserted
  !
  ! commit refuses a `problem` and a `runtime` that do not describe the same model. Until
  ! this section existed, two of those five refusals had never once been executed -- they
  ! were asserted, and an assertion that has never fired is evidence of nothing, the same
  ! way an assertion whose fixture cannot make its distinction is (docs/04, the test-side
  ! subspecies). Both arms below therefore check the MESSAGE, not just that something was
  ! refused: refusing for the wrong reason would otherwise look identical.
  !
  ! Each arm also pins what must stay SILENT. The arms are ordered inside commit -- nodes,
  ! elements, sections, amplitudes, boundary records -- and the first to fail returns, so
  ! an arm can only be shown to work if the arms before it agree. That is why the amplitude
  ! arm uses a draft that differs ONLY in amplitude count: every mesh extent matches, so
  ! nothing earlier can fire and the amplitude message is the only one that can appear.
  ! ==========================================================================

  subroutine group_extent_agreement(problem_1, problem_2, residue, rt_1, rt_2)
    type(problem_state_t), intent(in) :: problem_1, problem_2
    type(deck_residue_t), intent(in) :: residue
    type(runtime_state_t), intent(in) :: rt_1, rt_2

    type(problem_state_t), allocatable :: draft2, problem_2amp, problem_spare, problem_split
    type(manifest_t), allocatable :: pmanifest
    type(problem_errors_t) :: errors
    character(len=:), allocatable :: message
    logical :: owned_before

    ! --- arm 1: a runtime built from a LARGER mesh --------------------------
    ! The 1-element problem (4 nodes, 1 element) against the 2-element runtime (6 nodes,
    ! 2 elements). Before the agreement gate was hoisted above the staging loops this was
    ! not a reportable disagreement at all: the element loop indexes
    ! problem%mesh%elements(ie) with ie running to the RUNTIME's count, so it read past
    ! the end of a 1-element collection before any check was reached.
    owned_before = commit_owns_globals()
    call errors%clear()
    call commit_legacy_globals(problem_1, residue, ex, rt_2, errors)
    call check('a runtime from a larger mesh is refused', errors%any())
    ! UNCHANGED, not false. A refusal touches nothing, so it leaves ownership exactly as it
    ! found it -- and section 2 committed successfully, so what it finds here is `true`.
    ! The first version of this line asserted `.not. commit_owns_globals()`, copied from
    ! the foreign-allocation guard where the preceding commit_release really had left it
    ! false. Comparing against what was observed a statement earlier cannot be wrong in
    ! that way.
    call check('the mesh disagreement leaves commit ownership as it found it',                  &
              commit_owns_globals() .eqv. owned_before)
    if (errors%any()) then
      call one_error_message(errors, 1, message)
      ! The NODES arm, and specifically not the elements arm: nodes are checked first, so
      ! naming elements here would mean the order changed under us.
      call check('the mesh disagreement names the node counts',                                 &
                index(message, '4 nodes and the runtime numbers 6') > 0)
      call check('the mesh disagreement is not reported as a boundary-record skip',             &
                index(message, 'cannot recover which record was') == 0)
    end if

    ! --- arm 2: a problem with an extra AMPLITUDE ---------------------------
    ! Same mesh, same sections, same boundary records: only the amplitude count differs,
    ! so every arm before amplitudes must stay silent and this message is the only one
    ! that can appear.
    call draft_of(1, draft2, two_amplitudes=.true.)
    ! CLEAR FIRST. Without this, `errors` still holds arm 1's refusal and prepare_problem
    ! is reported as having failed with a message about node counts that it never
    ! produced -- which is exactly what the first run of this section printed.
    call errors%clear()
    call prepare_problem(draft2, PROFILE_TAG, problem_2amp, pmanifest, errors)
    call check('prepare_problem accepted the two-amplitude draft', .not. errors%any())
    if (errors%any()) then
      call report_errors('prepare_problem (two amplitudes)', errors)
      return
    end if

    call errors%clear()
    call commit_legacy_globals(problem_2amp, residue, ex, rt_1, errors)
    call check('a problem with an extra amplitude is refused', errors%any())
    if (errors%any()) then
      call one_error_message(errors, 1, message)
      call check('the amplitude disagreement names the amplitude counts',                       &
                index(message, '2 amplitudes and the runtime numbers 1') > 0)
      ! The mesh extents all agree here, so no earlier arm may claim this failure.
      call check('the amplitude disagreement is not reported as a node or element count',       &
                index(message, 'nodes and the runtime numbers') == 0 .and.                      &
                index(message, 'elements and the runtime numbers') == 0)
    end if

    ! --- arm 3: same nodes, FEWER elements ----------------------------------
    ! The elements arm cannot be reached by pairing the 1- and 2-element drafts: those
    ! differ in node count too, so the nodes arm fires first and the elements arm is never
    ! the thing under test. This draft carries the 2-element mesh's six nodes and only one
    ! element, so the nodes arm must agree and stay silent.
    call errors%clear()
    call draft_of(1, draft2, spare_nodes=.true.)
    call prepare_problem(draft2, PROFILE_TAG, problem_spare, pmanifest, errors)
    call check('prepare_problem accepted the spare-node draft', .not. errors%any())
    if (errors%any()) then
      call report_errors('prepare_problem (spare nodes)', errors)
      return
    end if
    call errors%clear()
    call commit_legacy_globals(problem_spare, residue, ex, rt_2, errors)
    call check('a problem with fewer elements than the runtime is refused', errors%any())
    if (errors%any()) then
      call one_error_message(errors, 1, message)
      call check('the element disagreement names the element counts',                           &
                index(message, '1 elements and the runtime numbers 2') > 0)
      ! The whole point of the spare-node mesh: node counts agree, so the arm that runs
      ! BEFORE this one must not be what fired.
      call check('the element disagreement is not reported as a node count',                    &
                index(message, 'nodes and the runtime numbers') == 0)
    end if

    ! --- arm 4: the sections arm is UNREACHABLE, and this is what says so -----
    ! The sections arm of the agreement gate cannot be fired: to reach it a problem must
    ! carry a section count the runtime does not, and the capability gate admits exactly
    ! ONE section ("sections.size: 2 is not in {1} for build capability static-q4/1"). No
    ! admissible problem has two sections, so no admissible pair can disagree about the
    ! count.
    !
    ! That is a claim about the GATE, so it is asserted against the gate rather than
    ! written in a comment that would quietly stop being true: the draft below really does
    ! carry two sections and prepare_problem really does refuse it, so the check goes red
    ! the moment that refusal stops happening.
    !
    ! STRUCTURALLY SOUND, NOT EMPIRICALLY VERIFIED -- and the difference is recorded here
    ! rather than rounded up. The team lead tried to confirm "widen the gate and this goes
    ! red" by setting model.section_count to 2. That control was INVALID: the capability
    ! table matches by EXACT EQUALITY, so the edit did not widen the gate to allow two, it
    ! required two, and what went red was the single-section baseline draft instead
    ! (docs/07, failure for the wrong reason). Widening is not a one-value edit under the
    ! current table -- it needs the entry's shape changed from equality to a set or range.
    ! So: the mechanism is sound by construction and the "it will go red" claim is not yet
    ! measured. Whoever widens the capability should confirm it then, when it costs a line.
    call errors%clear()
    call draft_of(2, draft2, two_sections=.true.)
    call prepare_problem(draft2, PROFILE_TAG, problem_split, pmanifest, errors)
    call check('a two-section draft is refused by the capability gate', errors%any())
    if (errors%any()) then
      ! render(), not the message alone: `sections.size` is the error's LOCATION and the
      ! message is only "2 is not in {1} for build capability ...". Checking the message
      ! for it failed, which is how this line came to be right -- and why the check below
      ! about {1} is kept separate from the one that names WHICH capability.
      message = errors%render(1)
      call check('the two-section refusal names the section-count capability',                  &
                index(message, 'sections.size') > 0)
      ! WHEN THIS GOES RED, the capability now admits more than one section and the
      ! sections arm of the agreement gate has become reachable and must be fired here.
      call check('while sections.size is capped at 1 the sections arm cannot be fired',         &
                index(message, 'is not in {1}') > 0)
    end if

    ! The globals must be exactly as section 2 left them: a refusal writes nothing. That
    ! state is the 2-ELEMENT commit, so this compares against problem_2/rt_2 -- comparing
    ! against the 1-element pair the arms above used would assert the wrong model and fail
    ! for a reason that has nothing to do with the refusals.
    call check_landed_guarded(problem_2, residue, rt_2, 'after the agreement refusals')
  end subroutine group_extent_agreement

  subroutine group_no_partial(problem, residue, rt_good)
    type(problem_state_t), intent(in) :: problem
    type(deck_residue_t), intent(in) :: residue
    type(runtime_state_t), intent(in) :: rt_good
    type(runtime_state_t) :: rt_bad     ! default-initialised: never handed to build_runtime
    type(problem_errors_t) :: errors
    integer :: bad_npoin, bad_nelem
    real(irk), allocatable :: bad_result_zero(:)

    ! This section's whole method is "compare the globals before and after a rejected
    ! commit", which presupposes an EARLIER commit succeeded and left them defined. If it
    ! did not, `result_zero` below is an unallocated allocatable and size() on it is
    ! undefined -- the same fault this file's check_landed note describes, reached by a
    ! different road.
    if (.not. commit_owns_globals()) then
      call skip_landed('no-partial-commit section')
      return
    end if

    ! rt_bad's field_status is unallocated (default init, yl_runtime_types.f90), so
    ! runtime_status_count(rt_bad) is 0 against build_rule_produced_count() > 0: the
    ! FIRST check inside verify_registered, before any staging allocation runs. This is
    ! "a runtime that was never built", the simplest of the two shapes the task allows.
    call commit_legacy_globals(problem, residue, ex, rt_bad, errors)
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
    call check_landed_guarded(problem, residue, rt_good, 'after the rejected commit')
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
    call commit_legacy_globals(problem, residue, ex, rt, errors)
    call check('repeat commit of the same runtime is accepted', .not. errors%any())
    if (errors%any()) then
      call skip_landed('repeat commit')
      return
    end if
    call check('npoin identical after a repeat commit', npoin == npoin_1)
    call check('nelem identical after a repeat commit', nelem == nelem_1)
    call check('nodfn bit-for-bit identical after a repeat commit', all(nodfn == nodfn_1))
    call check('fixed bit-for-bit identical after a repeat commit', all(fixed == fixed_1))
    call check_landed_guarded(problem, residue, rt, 'after a recommit')

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
                     allocated(factg) .or. allocated(tcurvegravity) .or.            &
                     allocated(uinitial)))

    ! --- a fresh commit after release works again ---------------------------------
    call commit_legacy_globals(problem, residue, ex, rt, errors)
    call check('a fresh commit after release is accepted', .not. errors%any())
    if (errors%any()) then
      call skip_landed('fresh commit after release')
      return
    end if
    call check('commit_owns_globals is true after the fresh commit', commit_owns_globals())
    call check_landed_guarded(problem, residue, rt, 'after a recommit')
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

    ! FLIPPED IN M4-01 STEP 5b, BY DESIGN (L2c-fold-design.md 5.2b point 1 predicted it).
    ! Three of these four were "commit never writes them" scalars; step 5b writes all
    ! three, so the assertions below now demand the COMMITTED value where they used to
    ! demand the sentinel. `ttime` is the one that does not move: it is not a model_ready
    ! row and nothing in the fold touches it, so it stays the control that says this
    ! section still detects an accidental write at all.
    !
    ! The sentinels earn their keep twice over. Seeding out-of-range values is what made
    ! step 5b's first attempt visible: `nmats = s_nmats` in the write phase assigned a
    ! LOCAL of that name inside commit_legacy_globals -- shadowing the use-associated
    ! global -- so nmats and nblks kept their sentinels while restart did not. Two of
    ! three assertions passing was the shape of the finding.
    nmats = SENTINEL_NMATS
    nblks = SENTINEL_NBLKS
    restart = SENTINEL_RESTART
    ttime = SENTINEL_TTIME

    call commit_legacy_globals(problem, residue, ex, rt, errors)
    call check('commit for the sentinel check is accepted', .not. errors%any())
    if (errors%any()) then
      call skip_landed('sentinel check')
      return
    end if

    ! Written now, and against their sources rather than against a literal.
    call check('nmats is the ProblemState material count after commit',                        &
              nmats == int(size(problem%materials), ink))
    call check('nblks is the ProblemState step count after commit',                            &
              nblks == int(size(problem%steps), ink))
    call check('restart is the residue value after commit',                                    &
              restart == int(opt_value_or(residue%restart, 0_int32), ink))
    ! Still untouched, and still the reason this section can tell "written" from "not".
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
      call commit_legacy_globals(problem, residue, ex, good_rt, errors)
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
    call commit_legacy_globals(problem, residue, ex, rt, errors)
    call check('a fresh commit for the blind-spot trials is accepted', .not. errors%any())
    if (errors%any()) then
      call skip_landed('blind-spot trials')
      return
    end if
    call check('the blind-spot guards pass on a fresh commit',                                  &
              unode_np_unode_all_zero() .and. unode_patch_pointers_all_null() .and.             &
              lineload == 0_ink .and. linet == 0_ink)

    ! --- runtime.topology.unode_np_unode -----------------------------------
    group(1)%unode(1)%np_unode = POISON
    call check('unode np_unode guard FAILS on a poisoned value',                                &
              .not. unode_np_unode_all_zero())
    call errors%clear()
    call commit_legacy_globals(problem, residue, ex, rt, errors)
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
    call commit_legacy_globals(problem, residue, ex, rt, errors)
    call check('the recommit for the cursors is accepted', .not. errors%any())
    call check('lineload is restored to 0 by a recommit', lineload == 0_ink)
    call check('linet is restored to 0 by a recommit', linet == 0_ink)

    ! Nothing above may have disturbed the rows the other sections assert: the
    ! full landing check runs once more as this section's own exit condition.
    call check_landed_guarded(problem, residue, rt, 'after a recommit')
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

    ! THE PRECONDITION, ASSERTED. Everything below parses `message` as the seven-doors
    ! guard's rejection -- but that message is only what the FIRST error carries when no
    ! earlier check refused the commit, and verify_registered (which runs verify_problem_
    ! inputs and verify_residue_inputs) is called BEFORE the foreign-allocation guard. So
    ! an unset ProblemState field or an unfilled residue component pre-empts this entirely
    ! and hands the parser an input error to pick names out of.
    !
    ! Measured, not supposed: leaving one residue component unfilled produced TWO failures
    ! here -- 'names exactly 7 globals' and 'names them in order' -- neither of which is
    ! about the seven doors. A pre-empted check must not read as a failing one, exactly as
    ! skip_landed exists so a skipped walk does not read as a passing one. So the
    ! precondition gets ONE named finding and the parse does not run.
    n = 0
    p1 = index(message, 'one of ')
    p2 = index(message, ' is already allocated')
    if (p1 <= 0 .or. p2 <= p1) then
      call check('the seven-doors guard was not pre-empted by an earlier input refusal',      &
                .false.)
      return
    end if
    ! Straight-line from here: the precondition above returned if the message was not the
    ! seven-doors one, so this no longer re-tests a condition that cannot be false.
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
