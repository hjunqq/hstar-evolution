! yl_runtime_selftest -- the acceptance instrument for build_runtime (M3-03).
!
! Scope (.ccg/tasks/m3-03-build-runtime-commit/plan.md test matrix rows B-ok / B-neg /
! B-cov / T01 / T02)
!   This program is the falsifiability gate for yl_runtime_build, on the model of
!   src/problem/yl_problem_pipeline_selftest.f90: every implemented build rule gets a
!   counter-example that makes exactly that rule fire and no other, every produced
!   quantity is walked against the rule table's declared bijection with the M2 map, and
!   the transaction and idempotence properties are exercised rather than assumed.
!
!   OUT OF SCOPE, deliberately: comparison against the frozen M2 baseline
!   (cases/golden/*/reference/frozen.json). No deck-to-ProblemState reader exists yet
!   (that is M4-01), so this program never reads frozen.json and never hand-transcribes
!   a golden value. Where a check needs an expected number, it is computed from the same
!   accessors build_runtime itself calls (q4_shape_functions, q4_stiffness_quadrature,
!   build_rule_*), never typed in as a literal copied from a document.
!
! Method
!   make_finalized() builds, through yl_problem_builder and prepare_problem, a draft
!   structurally equivalent to yl_problem_pipeline_selftest's cooks-equivalent good_draft
!   (same supported combination: 2-D, Q4 / kind 5 / class CO / field U / formulation PE,
!   one section, one material, one step, one LINEAR amplitude, gravity, PROFILE
!   symmetric solver) but with two prescribed NODES on the left edge (ids 1 and 4) each
!   constrained in both global components -- four boundary records, not two, so B6 and
!   B8 have something to duplicate and miscount. Two mesh sizes are built from the same
!   recipe (one Q4 and two Q4s sharing an edge) so B-ok's "structurally equivalent"
!   requirement is exercised on more than one shape.
!
!   Every B-neg counter-example is a MUTATION OF THE FINALIZED PROBLEM, not a second
!   draft pushed back through prepare_problem. Two of the five conditions this module
!   checks (B2's dof range, B3's orientation) are conditions the M3-02 pipeline's own
!   validate stage (V17) or capability gate would refuse first on the way in -- the
!   finalized model's dof range is narrower than the deck's raw range (see
!   yl_runtime_contract's D-class comment: 2 enabled globally vs 3 the element
!   declares), so mutating post-finalize is the only way to hand build_runtime a defect
!   the gate never gets to see. The same route is used for all five so the fixture
!   discipline is uniform rather than split across two techniques.
!
! Output
!   One `ok` / `BAD` line per check, `RULE|...` export lines (one per BUILD_RULES row,
!   via build_rule_row_text -- the prefix is `RULE|` because BUILD_RULES_TAG is embedded
!   in the line itself and no exporter of this kind exists yet for tools/yl_problem_check.py
!   to match against; see the report at the end of this task), and a final `PASS: n/n` or
!   `FAIL: n/m`. Exits 1 on any failure. Build and run under BOTH profiles, as
!   yl_problem_pipeline_selftest does.
program yl_runtime_selftest

  use iso_fortran_env, only: int32, int64, real64, output_unit
  use yl_problem_optional, only: opt_int, opt_real, opt_set, opt_get, opt_is_set, opt_value_or
  use yl_problem_types, only: problem_state_t, case_t, node_t, element_t, elset_t, nset_t,      &
                             material_t, section_t, amplitude_t, amplitude_point_t,             &
                             interactions_t, solver_t, controls_t, load_t, output_t,             &
                             boundary_t, activation_t, step_t
  use yl_problem_errors, only: problem_error_t, problem_errors_t, source_location_t,             &
                               PE_DANGLING_REF, PE_DUPLICATE_REF, PE_COUNT_MISMATCH,            &
                               PE_INVALID_INPUT
  use yl_problem_manifest, only: manifest_t, manifest_entry_t, manifest_count, manifest_get,     &
                                 manifest_record, manifest_is_valid
  use yl_problem_profile, only: PROFILE_TAG
  use yl_problem_builder
  use yl_problem_pipeline, only: prepare_problem
  use yl_runtime_types, only: runtime_state_t, index_list_t, section_nodes_t,                   &
                             runtime_field_status_t, runtime_free, runtime_is_empty,            &
                             runtime_status_count, runtime_status_row
  use yl_runtime_contract, only: CONTRACT_TAG, q4_stiffness_quadrature, q4_shape_functions
  use yl_runtime_build
  use yl_runtime_rules

  implicit none

  integer :: n_check = 0
  integer :: n_fail = 0

  ! Per-row coverage flag over BUILD_RULES, the build-rule analogue of
  ! yl_problem_pipeline_selftest's `cap_hit`. Only BR_CHECK rows can ever be marked here
  ! (build_rule_exercised answers .false. for every other kind by construction); BR_DERIVE
  ! coverage is a separate walk against the B-ok manifest, done in section_b_cov.
  logical, allocatable :: br_hit(:)

  type(problem_state_t), allocatable :: good1   ! finalized, one Q4 element
  type(problem_state_t), allocatable :: good2   ! finalized, two Q4 elements sharing an edge

  write (output_unit, '(a)') 'yl_runtime_selftest: M3-03 build_runtime falsifiability matrix'

  allocate (br_hit(build_rule_count()))
  br_hit = .false.

  call make_finalized(1, good1)
  call make_finalized(2, good2)

  call export_rule_table()

  call section_b_ok()
  call section_b_neg()
  call section_b_cov()
  call section_t01()
  call section_t02()

  call summary()

contains

  ! ==========================================================================
  ! fixtures
  ! ==========================================================================

  ! A finalized problem with `nel` Q4 elements (1 or 2), structurally equivalent to
  ! yl_problem_pipeline_selftest's cooks-equivalent good_draft: same section, material,
  ! solver, step, load and output declarations, differing only in mesh size and in
  ! carrying FOUR boundary records (nodes 1 and 4, both global components) instead of
  ! two, so B6 (duplicate pair) and B8 (declared-count mismatch) have a derived count
  ! bigger than one to disagree with.
  !
  ! Built through the real builder and prepare_problem, never by hand-allocating a
  ! problem_state_t or a runtime_state_t: the three-state (opt_int) discipline and the
  ! capability gate are the builder's and the pipeline's, not a shortcut taken here.
  subroutine make_finalized(nel, out)
    integer, intent(in) :: nel
    type(problem_state_t), allocatable, intent(out) :: out

    type(problem_state_t), allocatable :: draft, problem
    type(manifest_t), allocatable :: man
    type(problem_errors_t) :: errors
    type(problem_builder_t) :: b
    type(step_builder_t) :: sb
    type(amplitude_builder_t) :: ab
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
    integer :: k, npoin, i
    logical :: ok
    real(real64), allocatable :: xs(:), ys(:)
    integer(int32), allocatable :: e1(:), e2(:), eset(:)

    call builder_begin(b)

    call opt_set(kase%name, 'runtime-selftest')
    call builder_set_case(b, kase, loc, errors)
    call builder_set_mesh_dimension(b, 2_int32, loc, errors)

    ! Node layout: a unit square (nel=1), or that square plus a second unit square to
    ! its right sharing the edge {node 2, node 3} (nel=2). Both are counter-clockwise
    ! under the contract's node order (yl_runtime_contract:q4_shape_functions header).
    if (nel == 1) then
      npoin = 4
      allocate (xs(4), ys(4))
      xs = [0.0_real64, 1.0_real64, 1.0_real64, 0.0_real64]
      ys = [0.0_real64, 0.0_real64, 1.0_real64, 1.0_real64]
      allocate (e1(4)); e1 = [1_int32, 2_int32, 3_int32, 4_int32]
      allocate (eset(1)); eset = [1_int32]
    else
      npoin = 6
      allocate (xs(6), ys(6))
      xs = [0.0_real64, 1.0_real64, 1.0_real64, 0.0_real64, 2.0_real64, 2.0_real64]
      ys = [0.0_real64, 0.0_real64, 1.0_real64, 1.0_real64, 0.0_real64, 1.0_real64]
      allocate (e1(4)); e1 = [1_int32, 2_int32, 3_int32, 4_int32]
      allocate (e2(4)); e2 = [2_int32, 5_int32, 6_int32, 3_int32]
      allocate (eset(2)); eset = [1_int32, 2_int32]
    end if

    do k = 1, npoin
      call opt_set(nd%id, int(k, int32))
      if (allocated(nd%xyz)) deallocate (nd%xyz)
      allocate (nd%xyz(2))
      nd%xyz = [xs(k), ys(k)]
      call builder_add_node(b, nd, loc, errors)
    end do

    ! kind, material and elset are left UNSET on every element: finalize derives them,
    ! same as yl_problem_pipeline_selftest's good_draft.
    call opt_set(el%id, 1_int32)
    if (allocated(el%nodes)) deallocate (el%nodes)
    allocate (el%nodes(4)); el%nodes = e1
    call builder_add_element(b, el, loc, errors)
    if (nel == 2) then
      call opt_set(el%id, 2_int32)
      if (allocated(el%nodes)) deallocate (el%nodes)
      allocate (el%nodes(4)); el%nodes = e2
      call builder_add_element(b, el, loc, errors)
    end if

    if (allocated(es%elements)) deallocate (es%elements)
    allocate (es%elements(size(eset))); es%elements = eset
    call builder_add_elset(b, es, loc, errors)

    ! A structural nset; derive_node_sets (yl_problem_pipeline) overwrites mesh.nsets
    ! from the boundary records' own (name, nset) pairs once any boundary record
    ! exists, so this seed's content is not what ends up constrained -- only its
    ! presence matters, the same convention good_draft follows.
    if (allocated(ns%nodes)) deallocate (ns%nodes)
    allocate (ns%nodes(2)); ns%nodes = [1_int32, 4_int32]
    call builder_add_nset(b, ns, loc, errors)

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
    allocate (ct%tolerance_dof(2)); ct%tolerance_dof = [1.0e-5_real64, 1.0e-5_real64]
    call builder_step_set_controls(b, sb, ct, loc, errors)

    call opt_set(ld%gravity%enabled, 1_int32)
    call opt_set(ld%gravity%magnitude, 9.81_real64)
    if (allocated(ld%gravity%direction)) deallocate (ld%gravity%direction)
    allocate (ld%gravity%direction(2)); ld%gravity%direction = [0.0_real64, -1.0_real64]
    if (allocated(ld%gravity%amplitude)) deallocate (ld%gravity%amplitude)
    allocate (ld%gravity%amplitude(1)); ld%gravity%amplitude = 1_int32
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
    allocate (ou%stress_averaging(1)); ou%stress_averaging = 2_int32
    call builder_step_set_output(b, sb, ou, loc, errors)

    ! Four node-level prescribed records: nodes {1, 4} (the left edge on both mesh
    ! sizes), both global components. `name` is a distinct grouping ordinal per record
    ! -- derive_node_sets only uses it to group records into an nset, and build_runtime
    ! never reads it, so grouping one node per name changes nothing this module checks.
    do k = 1, 4
      call opt_set(bd%name, int(k, int32))
      if (k <= 2) then
        call opt_set(bd%nset, 1_int32)
      else
        call opt_set(bd%nset, 4_int32)
      end if
      if (mod(k, 2) == 1) then
        call opt_set(bd%dof, 1_int32)
      else
        call opt_set(bd%dof, 2_int32)
      end if
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
      write (output_unit, '(a)') 'FATAL: the fixture draft did not build'
      stop 1
    end if

    call prepare_problem(draft, PROFILE_TAG, problem, man, errors)
    if (errors%any() .or. .not. allocated(problem)) then
      write (output_unit, '(a)') 'FATAL: the fixture draft did not clear prepare_problem'
      do i = 1, errors%count()
        write (output_unit, '(a)') '        finding: '//errors%render(i)
      end do
      stop 1
    end if
    call move_alloc(problem, out)
  end subroutine make_finalized

  ! ==========================================================================
  ! B-ok -- the positive path, two structurally-equivalent problems
  ! ==========================================================================

  subroutine section_b_ok()
    write (output_unit, '(a)') '-- 1. B-ok (positive path, two mesh sizes)'
    call check_good_build('B-ok[1]', good1)
    call check_good_build('B-ok[2]', good2)
    call check_tiny_mesh_values()
    call check_gauss_geometry()
  end subroutine section_b_ok

  ! The structural half of B-ok: no findings, both outputs allocated, and the ledger
  ! and manifest each hold exactly the produced-row count the rule table declares --
  ! never a number written down here, always build_rule_produced_count().
  subroutine check_good_build(label, problem)
    character(len=*), intent(in) :: label
    type(problem_state_t), intent(in) :: problem
    type(runtime_state_t), allocatable :: rt
    type(manifest_t), allocatable :: man
    type(problem_errors_t) :: errors

    call build_runtime(problem, CONTRACT_TAG, rt, man, errors)
    call check(label//' no findings', .not. errors%any())
    call check(label//' runtime allocated', allocated(rt))
    call check(label//' manifest allocated', allocated(man))
    if (.not. (allocated(rt) .and. allocated(man))) return
    call check(label//' manifest is internally valid', manifest_is_valid(man))
    call check(label//' ledger holds exactly the produced-row count', &
               runtime_status_count(rt) == build_rule_produced_count())
    call check(label//' manifest holds exactly the produced-row count', &
               manifest_count(man) == build_rule_produced_count())
  end subroutine check_good_build

  ! Values computable by hand for the ONE-element unit-square mesh: ntotv, the
  ! node-major dense numbering, element 1's ldofs, the iffix pattern (one active
  ! section, so every variable is free or prescribed, never inactive) and the five
  ! zero vectors plus the amplitude factor.
  subroutine check_tiny_mesh_values()
    type(runtime_state_t), allocatable :: rt
    type(manifest_t), allocatable :: man
    type(problem_errors_t) :: errors
    integer :: ipoin, icomp, expect, cdofn
    integer(int32), allocatable :: expect_ldofs(:)
    integer(int32), allocatable :: expect_iffix(:)
    logical :: dense_ok, ldofs_ok, iffix_ok, zero_ok

    call build_runtime(good1, CONTRACT_TAG, rt, man, errors)
    if (errors%any() .or. .not. allocated(rt)) then
      call check('B-ok[1] tiny-mesh spot check: build succeeded', .false.)
      return
    end if

    call check('B-ok[1] ntotv = 2*npoin', opt_value_or(rt%dof%variable_count, -1_int32) == 8_int32)

    ! Node-major dense numbering: cdofn is runtime.dof's own compressed component
    ! count (derived.dof.cdofn), read back rather than assumed to be 2, so a future
    ! contract change that disables a component would move this check instead of
    ! silently invalidating it.
    cdofn = opt_value_or(rt%dof%active_component_count, 0_int32)
    dense_ok = .true.
    do ipoin = 1, 4
      do icomp = 1, cdofn
        expect = (ipoin - 1)*cdofn + icomp
        if (int(rt%dof%node_variables(icomp, ipoin)) /= expect) dense_ok = .false.
      end do
    end do
    call check('B-ok[1] nodfn is the node-major dense permutation 1..ntotv', dense_ok)

    ! Element 1's ldofs: FIELD_NODE_COMPONENT order (yl_runtime_contract's D class),
    ! and node storage index equals authored id here because the fixture assigns ids
    ! 1..4 in mesh order -- the formula is the general one, this fixture just makes it
    ! easy to state by hand.
    allocate (expect_ldofs(8))
    do ipoin = 1, 4
      do icomp = 1, cdofn
        expect_ldofs((ipoin - 1)*cdofn + icomp) = int((ipoin - 1)*cdofn + icomp, int32)
      end do
    end do
    ldofs_ok = allocated(rt%dof%element_variables(1)%values) .and. &
               size(rt%dof%element_variables(1)%values) == 8 .and. &
               all(rt%dof%element_variables(1)%values == expect_ldofs)
    call check('B-ok[1] element 1 ldofs is the FIELD_NODE_COMPONENT gather', ldofs_ok)

    ! iffix: one section, one active group covering every node, so no variable is
    ! ever the C-CONSTRAINT-INACTIVE mask (5) here -- only free (0) or prescribed
    ! (the C-CONSTRAINT-PRESCRIBED-BASE mask, 1). Nodes 1 and 4 are prescribed in both
    ! components; nodes 2 and 3 are free in both.
    allocate (expect_iffix(8))
    expect_iffix = 0_int32
    expect_iffix((1 - 1)*cdofn + 1) = 1_int32
    expect_iffix((1 - 1)*cdofn + 2) = 1_int32
    expect_iffix((4 - 1)*cdofn + 1) = 1_int32
    expect_iffix((4 - 1)*cdofn + 2) = 1_int32
    iffix_ok = allocated(rt%dof%fixed_mask) .and. size(rt%dof%fixed_mask) == 8 .and. &
               all(rt%dof%fixed_mask == expect_iffix) .and. all(rt%dof%fixed_mask /= 5_int32)
    call check('B-ok[1] iffix is 0 (free) or 1 (prescribed), never 5 (inactive) here', iffix_ok)

    ! The five zero vectors and the amplitude factor: exactly 0.0, not merely close.
    zero_ok = all(rt%vectors%total_displacement == 0.0_real64) .and. &
              all(rt%vectors%external_force_total == 0.0_real64) .and. &
              all(rt%vectors%internal_force == 0.0_real64) .and. &
              all(rt%vectors%external_force_load == 0.0_real64) .and. &
              all(rt%vectors%external_force_mass == 0.0_real64)
    call check('B-ok[1] the five model_ready vectors are exactly zero', zero_ok)
    call check('B-ok[1] every amplitude factor is exactly zero', &
               allocated(rt%amplitudes) .and. size(rt%amplitudes) == 1 .and. &
               opt_value_or(rt%amplitudes(1)%factor, -1.0_real64) == 0.0_real64)
    call check('B-ok[1] dof.fixed (prescribed value) is exactly zero', &
               all(rt%dof%prescribed_value == 0.0_real64))
  end subroutine check_tiny_mesh_values

  ! The Gauss geometry of the unit-square element, checked against the SAME
  ! accessors build_runtime calls (q4_shape_functions, q4_stiffness_quadrature) rather
  ! than against a transcribed decimal -- the scope note at the top of this file.
  !
  ! For a unit square the mapping from natural [-1,1]^2 to physical [0,1]^2 is affine
  ! with a constant Jacobian of 0.25 (each physical unit spans two natural units in
  ! both directions, so det J = 0.5*0.5); this is a property of the fixture's shape,
  ! not a number carried in from anywhere else.
  subroutine check_gauss_geometry()
    type(runtime_state_t), allocatable :: rt
    type(manifest_t), allocatable :: man
    type(problem_errors_t) :: errors
    real(real64) :: points(2, 4), weights(4)
    real(real64) :: values(4), gradients(2, 4)
    real(real64) :: elcod(2, 4), expect_point(2)
    logical :: djacb_ok, gpcod_ok
    integer :: igaus, id

    call build_runtime(good1, CONTRACT_TAG, rt, man, errors)
    if (errors%any() .or. .not. allocated(rt)) then
      call check('B-ok[1] gauss geometry: build succeeded', .false.)
      return
    end if

    call q4_stiffness_quadrature(points, weights)
    elcod(:, 1) = [0.0_real64, 0.0_real64]
    elcod(:, 2) = [1.0_real64, 0.0_real64]
    elcod(:, 3) = [1.0_real64, 1.0_real64]
    elcod(:, 4) = [0.0_real64, 1.0_real64]

    djacb_ok = .true.
    gpcod_ok = .true.
    do igaus = 1, 4
      if (rt%gauss(1)%stiffness%weighted_jacobian(igaus) /= 0.25_real64) djacb_ok = .false.
      call q4_shape_functions(points(1, igaus), points(2, igaus), values, gradients)
      do id = 1, 2
        expect_point(id) = sum(elcod(id, :)*values(:))
        if (rt%gauss(1)%stiffness%point_coordinates(id, igaus) /= expect_point(id)) gpcod_ok = .false.
      end do
    end do
    call check('B-ok[1] every weighted_jacobian on the unit square is exactly 0.25', djacb_ok)
    call check('B-ok[1] gpcod matches q4_shape_functions mapped through elcod_f', gpcod_ok)
  end subroutine check_gauss_geometry

  ! ==========================================================================
  ! B-neg -- one counter-example per implemented check rule
  ! ==========================================================================

  ! Each case starts from a deep copy of `good1` (intrinsic assignment on a
  ! problem_state_t with no aliasing component deep-copies every allocatable, the same
  ! guarantee runtime_free relies on in yl_runtime_types) and applies exactly ONE
  ! mutation, so what makes the rule fire is that mutation and nothing else.
  !
  ! B2 (dof out of range) and B3 (clockwise connectivity) are conditions the M3-02
  ! pipeline's own gate would refuse on the way in -- V17 checks dof against the mesh
  ! dimension (2) and would reject exactly the same range build_runtime's B2 refuses,
  ! and a folded element never survives finalize's own geometry expectations. Mutating
  ! the FINALIZED problem, as this subroutine does uniformly for all five, is what
  ! lets build_runtime see a defect the gate never had the chance to see. B1, B6 and
  ! B8 are attackable at the draft stage in principle, but are built the same way here
  ! for a single, auditable fixture discipline instead of two.
  subroutine section_b_neg()
    write (output_unit, '(a)') '-- 2. B-neg (one counter-example per rule)'
    call check_b1()
    call check_b2()
    call check_b3()
    call check_b6()
    call check_b8()
  end subroutine section_b_neg

  ! Survivor discipline shared by every B-neg case: build a known-good runtime and
  ! manifest first, snapshot them, run the bad fixture into the SAME variables, and
  ! assert both that the bad run failed with the right rule and that the survivor is
  ! untouched. This is the "runtime and manifest left bit-for-bit as they were" half
  ! of build_runtime's transaction contract (see its header), exercised per rule
  ! rather than once, because a rule that raised AFTER a partial write would defeat it
  ! silently on exactly the case that matters.
  ! `rule` is the composed key build_rule_key() renders ('B1/node-not-attached', not
  ! bare 'B1') and `object` is the table's index-free spelling ('steps[].boundary[]'),
  ! because that is what raise_row now puts on a finding -- the record or element
  ! that actually failed lives in `finding%index`, not in the object path, so
  ! `expected_idx` asserts THAT when the caller supplies one.
  subroutine expect_build_rule(label, rule, code, object, field, bad_problem, declared_ndofix, &
                               expected_idx)
    character(len=*), intent(in) :: label, rule, code, object, field
    type(problem_state_t), intent(in) :: bad_problem
    type(opt_int), intent(in), optional :: declared_ndofix
    integer, intent(in), optional :: expected_idx

    type(runtime_state_t), allocatable :: rt
    type(manifest_t), allocatable :: man
    type(problem_errors_t) :: good_errors, bad_errors
    type(problem_error_t) :: finding
    integer :: before_ledger, before_manifest, before_ntotv
    integer(int64) :: before_nodfn, before_djacb
    logical :: found, survivor_ok
    integer :: i

    call build_runtime(good1, CONTRACT_TAG, rt, man, good_errors)
    if (good_errors%any() .or. .not. allocated(rt)) then
      call check(label//' -- the survivor build itself succeeded', .false.)
      return
    end if
    before_ledger = runtime_status_count(rt)
    before_manifest = manifest_count(man)
    before_ntotv = opt_value_or(rt%dof%variable_count, -1_int32)
    before_nodfn = checksum_i32_2d(rt%dof%node_variables)
    before_djacb = checksum_gauss_djacb(rt)

    if (present(declared_ndofix)) then
      call build_runtime(bad_problem, CONTRACT_TAG, rt, man, bad_errors, &
                         declared_ndofix=declared_ndofix)
    else
      call build_runtime(bad_problem, CONTRACT_TAG, rt, man, bad_errors)
    end if

    call check(label//' -- the run fails', bad_errors%any())

    found = .false.
    do i = 1, bad_errors%count()
      call bad_errors%get(i, finding, found)
      if (.not. found) cycle
      if (opt_value_or(finding%rule_id, '') == rule) exit
      found = .false.
    end do
    call check(label//' -- rule '//rule//' fired', found)
    if (found) then
      call check(label//' -- code is '//code, opt_value_or(finding%code, '') == code)
      call check(label//' -- object path is "'//object//'"', &
                 opt_value_or(finding%object_path, '') == object)
      call check(label//' -- field is "'//field//'"', &
                 opt_value_or(finding%field, '') == field)
      if (present(expected_idx)) then
        call check(label//' -- finding%index names the actual record/element', &
                   opt_value_or(finding%index, -1_int32) == int(expected_idx, int32))
      end if
    else
      write (output_unit, '(a)') '        rules that fired: '//rules_of(bad_errors)
      call check(label//' -- code is '//code, .false.)
      call check(label//' -- object path is "'//object//'"', .false.)
      call check(label//' -- field is "'//field//'"', .false.)
      if (present(expected_idx)) then
        call check(label//' -- finding%index names the actual record/element', .false.)
      end if
    end if

    survivor_ok = runtime_status_count(rt) == before_ledger .and. &
                  manifest_count(man) == before_manifest .and. &
                  opt_value_or(rt%dof%variable_count, -2_int32) == before_ntotv .and. &
                  checksum_i32_2d(rt%dof%node_variables) == before_nodfn .and. &
                  checksum_gauss_djacb(rt) == before_djacb
    call check(label//' -- the earlier good runtime survives bit-for-bit', survivor_ok)
    call check(label//' -- the manifest gained no entry', manifest_count(man) == before_manifest)

    ! Coverage evidence for section_b_cov: OR this run's hits into the persistent
    ! per-row flag array, exactly as yl_problem_pipeline_selftest's
    ! record_capability_hits does for the capability table.
    do i = 1, build_rule_count()
      if (build_rule_exercised(bad_errors, i)) br_hit(i) = .true.
    end do
  end subroutine expect_build_rule

  ! B1 -- a node the mesh carries but no element touches. Node 5 is appended to the
  ! mesh at a point no element references, and the first boundary record is
  ! repointed at it (its dof stays valid, so B2 cannot fire first).
  subroutine check_b1()
    type(problem_state_t) :: bad
    type(node_t), allocatable :: grown(:)
    integer :: n
    bad = good1
    n = size(bad%mesh%nodes)
    allocate (grown(n + 1))
    grown(1:n) = bad%mesh%nodes
    call opt_set(grown(n + 1)%id, 5_int32)
    if (allocated(grown(n + 1)%xyz)) deallocate (grown(n + 1)%xyz)
    allocate (grown(n + 1)%xyz(2))
    grown(n + 1)%xyz = [5.0_real64, 5.0_real64]
    call move_alloc(grown, bad%mesh%nodes)
    call opt_set(bad%steps(1)%boundary(1)%nset, 5_int32)
    call expect_build_rule('B1', 'B1/node-not-attached', PE_DANGLING_REF, &
                           'steps[].boundary[]', 'nset', bad, expected_idx=1)
  end subroutine check_b1

  ! B2 -- a prescribed component outside 1..dof.component_count (2 here). The M3-02
  ! gate cannot see this: V17 checks against the mesh dimension, which is also 2 on
  ! this path, so the two rules happen to share a bound today and only a
  ! post-finalize mutation isolates build_runtime's own check.
  subroutine check_b2()
    type(problem_state_t) :: bad
    bad = good1
    call opt_set(bad%steps(1)%boundary(1)%dof, 3_int32)
    call expect_build_rule('B2', 'B2/dof-out-of-range', PE_INVALID_INPUT, &
                           'steps[].boundary[]', 'dof', bad, expected_idx=1)
  end subroutine check_b2

  ! B3 -- clockwise connectivity. Reversing element 1's node order under the
  ! contract's counter-clockwise convention (yl_runtime_contract:q4_shape_functions)
  ! makes det J negative at every Gauss point of the unit square.
  subroutine check_b3()
    type(problem_state_t) :: bad
    bad = good1
    bad%mesh%elements(1)%nodes = [1_int32, 4_int32, 3_int32, 2_int32]
    call expect_build_rule('B3', 'B3/negative-jacobian', PE_INVALID_INPUT, &
                           'mesh.elements[]', 'nodes', bad, expected_idx=1)
  end subroutine check_b3

  ! B6 -- the same (node, component) prescribed twice. Record 5 duplicates record 1
  ! exactly; the loop finds the earlier record at j=1 when it reaches i=5.
  subroutine check_b6()
    type(problem_state_t) :: bad
    type(boundary_t), allocatable :: grown(:)
    integer :: n
    bad = good1
    n = size(bad%steps(1)%boundary)
    allocate (grown(n + 1))
    grown(1:n) = bad%steps(1)%boundary
    grown(n + 1) = bad%steps(1)%boundary(1)
    call move_alloc(grown, bad%steps(1)%boundary)
    ! The duplicate is appended as record n+1 = 5 (good1 derives 4 records); the loop
    ! finds the earlier match at j=1 when it reaches i=5, so the finding names record 5,
    ! the one that duplicates, not record 1, the one duplicated.
    call expect_build_rule('B6', 'B6/duplicate-prescribed-pair', PE_DUPLICATE_REF, &
                           'steps[].boundary[]', 'dof', bad, expected_idx=5)
  end subroutine check_b6

  ! B8 -- the deck's declared prescribed-record count disagreeing with the derived
  ! one. No mutation of the problem itself: `good1` derives exactly 4 records, and
  ! `declared_ndofix` here claims 3.
  subroutine check_b8()
    type(opt_int) :: declared
    call opt_set(declared, 3_int32)
    ! No expected_idx: raise_row's B8 call carries no `idx` (there is no single record
    ! this defect points at, it is a whole-count disagreement).
    call expect_build_rule('B8', 'B8/declared-count-mismatch', PE_COUNT_MISMATCH, &
                           'declared_counts', 'ndofix', good1, declared_ndofix=declared)
  end subroutine check_b8

  ! ==========================================================================
  ! B-cov -- the rule-table coverage guard and the bijection
  ! ==========================================================================

  subroutine section_b_cov()
    integer :: k, first_uncovered, n_falsifiable, n_covered
    type(build_rule_t) :: row
    logical :: found
    type(problem_errors_t) :: no_findings

    write (output_unit, '(a)') '-- 3. B-cov (rule-table coverage guard and bijection)'

    ! Every FALSIFIABLE row (BR_CHECK, since none of this suite's counter-examples can
    ! target a BR_DERIVE row through the accumulator -- see the header of
    ! build_rule_exercised) must have fired at least once across the B-neg matrix.
    n_falsifiable = 0
    n_covered = 0
    do k = 1, build_rule_count()
      if (.not. build_rule_is_falsifiable(k)) cycle
      call build_rule_row(k, row, found)
      if (.not. found) cycle
      if (row%kind /= BR_CHECK) cycle   ! BR_DERIVE coverage is the manifest walk below
      n_falsifiable = n_falsifiable + 1
      if (br_hit(k)) n_covered = n_covered + 1
    end do
    write (output_unit, '(a,i0,a,i0)') '        BR_CHECK rows covered: ', n_covered, '/', n_falsifiable

    first_uncovered = build_rule_first_uncovered(no_findings)
    ! `no_findings` is deliberately empty here; the real walk is against `br_hit`,
    ! which this loop built from every B-neg run's own errors accumulator. Naming the
    ! first uncovered BR_CHECK row directly, rather than re-deriving it from an
    ! accumulator this program does not keep pooled, keeps the failure message
    ! actionable per the header of build_rule_first_uncovered.
    block
      logical :: all_hit
      integer :: bad_row
      all_hit = .true.
      bad_row = 0
      do k = 1, build_rule_count()
        call build_rule_row(k, row, found)
        if (.not. found) cycle
        if (row%kind /= BR_CHECK) cycle
        if (br_hit(k)) cycle
        all_hit = .false.
        bad_row = k
        exit
      end do
      call check('B-cov every BR_CHECK row was exercised by the counter-example matrix', all_hit)
      if (.not. all_hit) then
        write (output_unit, '(a)') '        UNCOVERED: '//build_rule_row_text(bad_row)
      end if
    end block

    call check_bijection()
  end subroutine section_b_cov

  ! The half of the derive <-> map bijection Fortran can check without reading the
  ! .toml: the FORWARD direction (every produced map id has a producer row -- true by
  ! construction of build_rule_produced_map_id/build_rule_producer_of, but asserted
  ! rather than assumed, the same discipline as an assertion that cannot fail being
  ! worse than none) and INJECTIVITY (no two rows claim the same map id).
  !
  ! The BACKWARD direction -- every model_ready RuntimeState.* row of
  ! docs/m2/state-field-map.toml has a producing rule row here -- is NOT checked in
  ! this subroutine and cannot be: Fortran has no .toml reader in this module's
  ! dependency graph. It is the Python cross-check's job, against the `RULE|` /
  ! `RULES|` lines export_rule_table prints, the same split yl_runtime_rules's own
  ! header describes for this exact bijection.
  subroutine check_bijection()
    integer :: n, i, j
    logical :: forward_ok, injective_ok
    character(len=:), allocatable :: map_id

    n = build_rule_produced_count()
    forward_ok = .true.
    do i = 1, n
      map_id = build_rule_produced_map_id(i)
      if (len_trim(map_id) == 0) then
        forward_ok = .false.
        cycle
      end if
      if (build_rule_producer_of(map_id) == 0) forward_ok = .false.
    end do
    call check('B-cov every produced map id has a producer row', forward_ok)

    injective_ok = .true.
    do i = 1, n
      do j = i + 1, n
        if (build_rule_produced_map_id(i) == build_rule_produced_map_id(j)) injective_ok = .false.
      end do
    end do
    call check('B-cov no two rows claim the same produced map id', injective_ok)
  end subroutine check_bijection

  ! ==========================================================================
  ! T01 -- no partial commit under allocation failure
  ! ==========================================================================

  subroutine section_t01()
    type(runtime_state_t), allocatable :: rt
    type(manifest_t), allocatable :: man
    type(problem_errors_t) :: errors
    integer :: site, before_ledger, before_manifest, before_ntotv
    integer(int64) :: before_nodfn, before_djacb
    logical :: survivor_ok

    write (output_unit, '(a)') '-- 4. T01 (no partial commit under allocation failure)'

    call build_runtime(good1, CONTRACT_TAG, rt, man, errors)
    call check('T01 the survivor build itself succeeds', .not. errors%any() .and. allocated(rt))
    if (errors%any() .or. .not. allocated(rt)) return

    do site = 1, build_alloc_site_count()
      before_ledger = runtime_status_count(rt)
      before_manifest = manifest_count(man)
      before_ntotv = opt_value_or(rt%dof%variable_count, -1_int32)
      before_nodfn = checksum_i32_2d(rt%dof%node_variables)
      before_djacb = checksum_gauss_djacb(rt)

      block
        type(problem_errors_t) :: site_errors
        call build_runtime(good1, CONTRACT_TAG, rt, man, site_errors, fail_at=site)
        call check('T01 site '//build_alloc_site_id(site)//' the injected call fails', &
                   site_errors%any())

        survivor_ok = runtime_status_count(rt) == before_ledger .and. &
                      manifest_count(man) == before_manifest .and. &
                      opt_value_or(rt%dof%variable_count, -2_int32) == before_ntotv .and. &
                      checksum_i32_2d(rt%dof%node_variables) == before_nodfn .and. &
                      checksum_gauss_djacb(rt) == before_djacb
        call check('T01 site '//build_alloc_site_id(site)//' the survivor is bit-for-bit intact', &
                   survivor_ok)
        call check('T01 site '//build_alloc_site_id(site)//' the manifest gained no entry', &
                   manifest_count(man) == before_manifest)
      end block
    end do

    block
      type(runtime_state_t), allocatable :: rt2
      type(manifest_t), allocatable :: man2
      type(problem_errors_t) :: final_errors
      call build_runtime(good1, CONTRACT_TAG, rt2, man2, final_errors)
      call check('T01 a subsequent legal build still succeeds after every injection', &
                 .not. final_errors%any() .and. allocated(rt2) .and. allocated(man2))
    end block
  end subroutine section_t01

  ! ==========================================================================
  ! T02 -- repeat load: four properties
  ! ==========================================================================

  ! The alias-free grep gate (`grep -ni 'point''er' src/runtime/yl_runtime_types.f90`
  ! must print nothing) is a shell check over yl_runtime_types.f90, a file this task
  ! does not own and cannot re-run a shell gate against from inside a Fortran program;
  ! it is not attempted here and is left to the build script / CI, per the task's own
  ! scope note.
  subroutine section_t02()
    type(runtime_state_t), allocatable :: rt_a, rt_b
    type(manifest_t), allocatable :: man_a, man_b
    type(problem_errors_t) :: errors
    logical :: equal_ok

    write (output_unit, '(a)') '-- 5. T02 (repeat load: equality, idempotent free, correct reload)'

    call build_runtime(good1, CONTRACT_TAG, rt_a, man_a, errors)
    call check('T02 first build succeeds', .not. errors%any() .and. allocated(rt_a))
    call errors%clear()
    call build_runtime(good1, CONTRACT_TAG, rt_b, man_b, errors)
    call check('T02 second build succeeds', .not. errors%any() .and. allocated(rt_b))
    if (.not. (allocated(rt_a) .and. allocated(rt_b))) return

    equal_ok = runtimes_equal(rt_a, rt_b) .and. manifests_equal(man_a, man_b)
    call check('T02 two builds of the same problem are bit-for-bit equal', equal_ok)

    call runtime_free(rt_a)
    call check('T02 runtime_free empties the runtime', runtime_is_empty(rt_a))
    call runtime_free(rt_a)
    call check('T02 a second runtime_free is a no-op (still empty)', runtime_is_empty(rt_a))

    call errors%clear()
    call build_runtime(good1, CONTRACT_TAG, rt_a, man_a, errors)
    call check('T02 rebuild after free succeeds', .not. errors%any() .and. allocated(rt_a))
    if (allocated(rt_a)) then
      call check('T02 the rebuilt runtime matches the untouched one again', &
                 runtimes_equal(rt_a, rt_b) .and. manifests_equal(man_a, man_b))
    end if
  end subroutine section_t02

  ! ==========================================================================
  ! export
  ! ==========================================================================

  ! Print a `RULES|` header (the table's identity and the three counts a Python
  ! reader needs to know it parsed every row) followed by one `RULE|` line per
  ! BUILD_RULES row via build_rule_row_text, in table order. This is an EXPORT, not
  ! an assertion -- it lives outside the PASS/FAIL accounting entirely (no `check`
  ! call in this subroutine) -- for the same reason capability_row_text's export
  ! exists on the M3-02 side: the rule table then exists exactly ONCE in the
  ! repository, as this Fortran parameter array, and a Python cross-check parses
  ! these lines instead of keeping a second copy that can drift against it.
  subroutine export_rule_table()
    integer :: i
    character(len=32) :: rows, produced, falsifiable
    write (rows, '(i0)') build_rule_count()
    write (produced, '(i0)') build_rule_produced_count()
    write (falsifiable, '(i0)') build_rule_falsifiable_count()
    write (output_unit, '(a)') 'RULES|tag='//BUILD_RULES_TAG//'|rows='//trim(adjustl(rows))// &
      '|produced='//trim(adjustl(produced))//'|falsifiable='//trim(adjustl(falsifiable))
    do i = 1, build_rule_count()
      write (output_unit, '(a)') 'RULE|'//build_rule_row_text(i)
    end do
  end subroutine export_rule_table

  ! ==========================================================================
  ! comparison helpers
  ! ==========================================================================

  ! A position-weighted sum, sensitive to a permutation and not just to a total --
  ! "hash-like" in the sense the task asks for, not a cryptographic one. int64
  ! throughout so ntotv*ntotv-scale sums on this fixture cannot wrap.
  pure function checksum_i32_2d(a) result(c)
    integer(int32), intent(in) :: a(:,:)
    integer(int64) :: c
    integer :: i, j, k
    c = 0_int64
    k = 0
    do j = 1, size(a, 2)
      do i = 1, size(a, 1)
        k = k + 1
        c = c + int(a(i, j), int64)*int(k, int64)
      end do
    end do
  end function checksum_i32_2d

  ! The Gauss weighted-jacobian checksum T01 uses to prove the survivor's element
  ! geometry, and not merely its dof numbering, is untouched by an injected failure.
  pure function checksum_gauss_djacb(rt) result(c)
    type(runtime_state_t), intent(in) :: rt
    integer(int64) :: c
    integer :: ie, ig, k
    c = 0_int64
    k = 0
    if (.not. allocated(rt%gauss)) return
    do ie = 1, size(rt%gauss)
      if (.not. allocated(rt%gauss(ie)%stiffness%weighted_jacobian)) cycle
      do ig = 1, size(rt%gauss(ie)%stiffness%weighted_jacobian)
        k = k + 1
        c = c + int(transfer(rt%gauss(ie)%stiffness%weighted_jacobian(ig), 0_int64))*int(k, int64)
      end do
    end do
  end function checksum_gauss_djacb

  ! Elementwise equality of two allocatable arrays: both unallocated is equal, one
  ! allocated and not the other is not, different extents is not.
  pure logical function i32_1d_equal(a, b) result(same)
    integer(int32), allocatable, intent(in) :: a(:), b(:)
    same = allocated(a) .eqv. allocated(b)
    if (.not. same) return
    if (.not. allocated(a)) return
    same = size(a) == size(b)
    if (.not. same) return
    same = all(a == b)
  end function i32_1d_equal

  pure logical function i32_2d_equal(a, b) result(same)
    integer(int32), allocatable, intent(in) :: a(:,:), b(:,:)
    same = allocated(a) .eqv. allocated(b)
    if (.not. same) return
    if (.not. allocated(a)) return
    same = all(shape(a) == shape(b))
    if (.not. same) return
    same = all(a == b)
  end function i32_2d_equal

  pure logical function f64_1d_equal(a, b) result(same)
    real(real64), allocatable, intent(in) :: a(:), b(:)
    same = allocated(a) .eqv. allocated(b)
    if (.not. same) return
    if (.not. allocated(a)) return
    same = size(a) == size(b)
    if (.not. same) return
    same = all(a == b)
  end function f64_1d_equal

  pure logical function f64_2d_equal(a, b) result(same)
    real(real64), allocatable, intent(in) :: a(:,:), b(:,:)
    same = allocated(a) .eqv. allocated(b)
    if (.not. same) return
    if (.not. allocated(a)) return
    same = all(shape(a) == shape(b))
    if (.not. same) return
    same = all(a == b)
  end function f64_2d_equal

  pure logical function f64_3d_equal(a, b) result(same)
    real(real64), allocatable, intent(in) :: a(:,:,:), b(:,:,:)
    same = allocated(a) .eqv. allocated(b)
    if (.not. same) return
    if (.not. allocated(a)) return
    same = all(shape(a) == shape(b))
    if (.not. same) return
    same = all(a == b)
  end function f64_3d_equal

  pure logical function index_lists_equal(a, b) result(same)
    type(index_list_t), intent(in) :: a(:), b(:)
    integer :: i
    same = size(a) == size(b)
    if (.not. same) return
    do i = 1, size(a)
      if (.not. i32_1d_equal(a(i)%values, b(i)%values)) then
        same = .false.
        return
      end if
    end do
  end function index_lists_equal

  ! Every mapped array of the two runtimes, elementwise -- and every ledger entry, in
  ! order (build_runtime publishes rows in a fixed sequence, so a stable order between
  ! two builds of the same input is itself part of what "the same" means here).
  ! RESERVED components (element.tload/eload/rload, vectors.delitfi/deltafi, every
  ! cursor field) are never read: the ledger forbids it, so this comparator honours
  ! that rather than working around it.
  logical function runtimes_equal(a, b) result(same)
    type(runtime_state_t), intent(in) :: a, b
    integer :: i, n

    same = .true.
    if (.not. i32_1d_equal(a%dof%component_to_active, b%dof%component_to_active)) same = .false.
    if (.not. i32_1d_equal(a%dof%active_to_component, b%dof%active_to_component)) same = .false.
    if (opt_value_or(a%dof%active_component_count, -1_int32) /= &
        opt_value_or(b%dof%active_component_count, -2_int32)) same = .false.
    if (.not. i32_2d_equal(a%dof%node_variables, b%dof%node_variables)) same = .false.
    if (opt_value_or(a%dof%variable_count, -1_int32) /= &
        opt_value_or(b%dof%variable_count, -2_int32)) same = .false.
    if (.not. i32_1d_equal(a%dof%fixed_mask, b%dof%fixed_mask)) same = .false.
    if (.not. f64_1d_equal(a%dof%prescribed_value, b%dof%prescribed_value)) same = .false.
    if (.not. i32_1d_equal(a%dof%interpolation_count, b%dof%interpolation_count)) same = .false.

    if (allocated(a%dof%element_variables) .neqv. allocated(b%dof%element_variables)) then
      same = .false.
    else if (allocated(a%dof%element_variables)) then
      if (.not. index_lists_equal(a%dof%element_variables, b%dof%element_variables)) same = .false.
      n = min(size(a%dof%element_field_variables), size(b%dof%element_field_variables))
      if (size(a%dof%element_field_variables) /= size(b%dof%element_field_variables)) same = .false.
      do i = 1, n
        if (.not. index_lists_equal(a%dof%element_field_variables(i)%fields, &
                                    b%dof%element_field_variables(i)%fields)) same = .false.
      end do
    end if

    if (allocated(a%boundary) .neqv. allocated(b%boundary)) then
      same = .false.
    else if (allocated(a%boundary)) then
      if (size(a%boundary) /= size(b%boundary)) then
        same = .false.
      else
        do i = 1, size(a%boundary)
          if (opt_value_or(a%boundary(i)%dof_index, -1_int32) /= &
              opt_value_or(b%boundary(i)%dof_index, -2_int32)) same = .false.
          if (opt_value_or(a%boundary(i)%element_count, -1_int32) /= &
              opt_value_or(b%boundary(i)%element_count, -2_int32)) same = .false.
          if (.not. i32_1d_equal(a%boundary(i)%attached_element, b%boundary(i)%attached_element)) &
            same = .false.
          if (.not. i32_1d_equal(a%boundary(i)%attached_local_position, &
                                 b%boundary(i)%attached_local_position)) same = .false.
          if (.not. i32_1d_equal(a%boundary(i)%attached_field, b%boundary(i)%attached_field)) &
            same = .false.
        end do
      end if
    end if

    if (.not. i32_1d_equal(a%topology%node_sections%group_count, &
                           b%topology%node_sections%group_count)) same = .false.
    if (allocated(a%topology%node_sections%section_index)) then
      if (.not. index_lists_equal(a%topology%node_sections%section_index, &
                                  b%topology%node_sections%section_index)) same = .false.
      if (.not. index_lists_equal(a%topology%node_sections%position_in_section, &
                                  b%topology%node_sections%position_in_section)) same = .false.
    end if
    if (allocated(a%topology%sections) .neqv. allocated(b%topology%sections)) then
      same = .false.
    else if (allocated(a%topology%sections)) then
      if (size(a%topology%sections) /= size(b%topology%sections)) then
        same = .false.
      else
        do i = 1, size(a%topology%sections)
          if (.not. section_nodes_equal(a%topology%sections(i), b%topology%sections(i))) &
            same = .false.
        end do
      end if
    end if

    if (.not. i32_1d_equal(a%activation%section_state, b%activation%section_state)) same = .false.
    if (opt_value_or(a%increment%current_block, -1_int32) /= &
        opt_value_or(b%increment%current_block, -2_int32)) same = .false.
    if (opt_value_or(a%increment%completed_blocks, -1_int32) /= &
        opt_value_or(b%increment%completed_blocks, -2_int32)) same = .false.

    if (allocated(a%amplitudes) .neqv. allocated(b%amplitudes)) then
      same = .false.
    else if (allocated(a%amplitudes)) then
      if (size(a%amplitudes) /= size(b%amplitudes)) then
        same = .false.
      else
        do i = 1, size(a%amplitudes)
          if (opt_value_or(a%amplitudes(i)%factor, -1.0_real64) /= &
              opt_value_or(b%amplitudes(i)%factor, -2.0_real64)) same = .false.
        end do
      end if
    end if

    if (allocated(a%gauss) .neqv. allocated(b%gauss)) then
      same = .false.
    else if (allocated(a%gauss)) then
      if (size(a%gauss) /= size(b%gauss)) then
        same = .false.
      else
        do i = 1, size(a%gauss)
          if (.not. f64_1d_equal(a%gauss(i)%stiffness%weighted_jacobian, &
                                 b%gauss(i)%stiffness%weighted_jacobian)) same = .false.
          if (.not. f64_2d_equal(a%gauss(i)%stiffness%point_coordinates, &
                                 b%gauss(i)%stiffness%point_coordinates)) same = .false.
          if (.not. f64_3d_equal(a%gauss(i)%stiffness%shape_gradient, &
                                 b%gauss(i)%stiffness%shape_gradient)) same = .false.
          if (.not. f64_1d_equal(a%gauss(i)%mass%weighted_jacobian, &
                                 b%gauss(i)%mass%weighted_jacobian)) same = .false.
          if (.not. f64_2d_equal(a%gauss(i)%mass%point_coordinates, &
                                 b%gauss(i)%mass%point_coordinates)) same = .false.
        end do
      end if
    end if

    if (allocated(a%element) .neqv. allocated(b%element)) then
      same = .false.
    else if (allocated(a%element)) then
      if (size(a%element) /= size(b%element)) then
        same = .false.
      else
        do i = 1, size(a%element)
          if (.not. f64_2d_equal(a%element(i)%field_coordinates, b%element(i)%field_coordinates)) &
            same = .false.
          if (opt_value_or(a%element(i)%refinement_skip, -1_int32) /= &
              opt_value_or(b%element(i)%refinement_skip, -2_int32)) same = .false.
        end do
      end if
    end if

    if (.not. f64_1d_equal(a%vectors%total_displacement, b%vectors%total_displacement)) same = .false.
    if (.not. f64_1d_equal(a%vectors%external_force_total, b%vectors%external_force_total)) &
      same = .false.
    if (.not. f64_1d_equal(a%vectors%internal_force, b%vectors%internal_force)) same = .false.
    if (.not. f64_1d_equal(a%vectors%external_force_load, b%vectors%external_force_load)) &
      same = .false.
    if (.not. f64_1d_equal(a%vectors%external_force_mass, b%vectors%external_force_mass)) &
      same = .false.

    if (runtime_status_count(a) /= runtime_status_count(b)) then
      same = .false.
    else
      do i = 1, runtime_status_count(a)
        block
          type(runtime_field_status_t) :: ra, rb
          logical :: fa, fb
          call runtime_status_row(a, i, ra, fa)
          call runtime_status_row(b, i, rb, fb)
          if (.not. (fa .and. fb)) then
            same = .false.
          else if (trim(ra%map_id) /= trim(rb%map_id) .or. ra%state /= rb%state) then
            same = .false.
          end if
        end block
      end do
    end if
  end function runtimes_equal

  pure logical function section_nodes_equal(a, b) result(same)
    type(section_nodes_t), intent(in) :: a, b
    integer :: i
    same = allocated(a%nodes) .eqv. allocated(b%nodes)
    if (.not. same) return
    if (.not. allocated(a%nodes)) return
    same = size(a%nodes) == size(b%nodes)
    if (.not. same) return
    do i = 1, size(a%nodes)
      if (opt_value_or(a%nodes(i)%node_id, -1_int32) /= opt_value_or(b%nodes(i)%node_id, -2_int32)) then
        same = .false.
        return
      end if
      if (opt_value_or(a%nodes(i)%element_count, -1_int32) /= &
          opt_value_or(b%nodes(i)%element_count, -2_int32)) then
        same = .false.
        return
      end if
      if (.not. i32_1d_equal(a%nodes(i)%elements, b%nodes(i)%elements)) then
        same = .false.
        return
      end if
      ! patch_count / patch_nodes: both ABSENT on this path (see yl_runtime_types'
      ! header, "the one row that must stay unallocated"); an allocation-status
      ! mismatch here would itself be the defect NET-EMPTY-RT and the invariants
      ! exist to catch, so it is checked, not skipped.
      if (opt_is_set(a%nodes(i)%patch_count) .or. opt_is_set(b%nodes(i)%patch_count)) then
        same = .false.
        return
      end if
      if (allocated(a%nodes(i)%patch_nodes) .or. allocated(b%nodes(i)%patch_nodes)) then
        same = .false.
        return
      end if
    end do
  end function section_nodes_equal

  ! Manifest equality via manifest_record's stable per-entry text (the same rendering
  ! the manifest's own writer emits), rather than field-by-field comparison of
  ! manifest_entry_t -- one comparison instead of eleven, and it is the exact text a
  ! reader of the manifest file would see disagree.
  logical function manifests_equal(a, b) result(same)
    type(manifest_t), intent(in) :: a, b
    type(manifest_entry_t) :: ea, eb
    logical :: fa, fb
    integer :: i

    same = manifest_count(a) == manifest_count(b)
    if (.not. same) return
    do i = 1, manifest_count(a)
      call manifest_get(a, i, ea, fa)
      call manifest_get(b, i, eb, fb)
      if (.not. (fa .and. fb)) then
        same = .false.
        return
      end if
      if (manifest_record(ea, i) /= manifest_record(eb, i)) then
        same = .false.
        return
      end if
    end do
  end function manifests_equal

  ! The rule ids that actually fired, for a diagnostic line when the expected one did
  ! not -- the same shape as yl_problem_pipeline_selftest's rules_of.
  function rules_of(errs) result(text)
    type(problem_errors_t), intent(in) :: errs
    character(len=:), allocatable :: text
    type(problem_error_t) :: e
    logical :: found
    integer :: i
    text = ''
    do i = 1, errs%count()
      call errs%get(i, e, found)
      if (.not. found) cycle
      if (i > 1) text = text//', '
      text = text//opt_value_or(e%rule_id, '<unset>')
    end do
    if (len(text) == 0) text = '(none)'
  end function rules_of

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

  subroutine summary()
    character(len=32) :: a, b
    write (a, '(i0)') n_check - n_fail
    write (b, '(i0)') n_check
    if (n_fail == 0) then
      write (output_unit, '(a)') 'PASS: '//trim(a)//'/'//trim(b)
    else
      write (output_unit, '(a)') 'FAIL: '//trim(a)//'/'//trim(b)
      stop 1
    end if
  end subroutine summary

end program yl_runtime_selftest
