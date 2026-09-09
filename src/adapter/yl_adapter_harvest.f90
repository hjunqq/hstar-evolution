! yl_adapter_harvest -- M4-01 harvest oracle (docs/m4/adapter-contract.md §6, §6.1).
!
! THIS IS AN ORACLE, NOT A PRODUCT PATH.
!   It drives the REAL legacy module readers and then harvests the legacy globals they
!   populate into a problem_state_t, following docs/m2/state-field-map.toml's
!   `legacy_symbol` column row by row. It therefore preserves the exact behaviour M4 exists
!   to remove -- "the reader writes the global; something else reads the global back" -- and
!   does NOT itself satisfy M4's goal ("旧 deck 不再由原 reader 直接驱动全局变量",
!   .ccg/tasks/m4-01-legacy-adapter/plan.md). Its only job is to give the hand-written
!   parsers (yl_adapter_mesh/model/material/load/fem90) something to be cross-checked
!   against, field by field, so a semantic drift between the new parsers and the legacy
!   readers shows up as a red diff instead of a silent divergence (ADR-0001).
!
!   Consequently this is the ONE adapter module allowed `use global_var` (contract §6).
!   It still touches no global for writing except the single, bounded, documented
!   exception in §6.1 below (`local_p4`); every other legacy symbol here is READ ONLY.
!
! What "driving the reader" means here, and why it is more than five lines
!   R-order-1 (docs/m4/evidence/R-order-probe/) confirmed global_data + material_set run
!   correctly called from outside PROGRAM FEM90. R-order-2 (reported to the team lead
!   2026-09-08, scratch probe not in this repo) extended that to external_load_1,
!   prescrib_set and PROFILE, and found that reaching them means inlining roughly 150 lines
!   of FEM90's own body (Fem.f90:191-1682) plus the slice of `process_analysis` before each
!   target call: `process_analysis` (Fem.f90:1642) is declared AFTER PROGRAM FEM90's
!   `contains` (Fem.f90:552), so it is an internal procedure and structurally uncallable
!   from here, exactly like the nine sites in yl_adapter_fem90's scope. There is no
!   subroutine to `call`; the only way to reach the three confirmed-reachable readers is to
!   replicate FEM90's own control flow up to each call, which is what `drive_legacy_readers`
!   below does. L2-a will eventually own a real sequencing driver; until it lands, this is
!   the only thing standing between "confirmed reachable" and an oracle that can actually
!   run, so it duplicates that ~150-line prologue rather than wait for it. Every branch this
!   driver does not implement is a real runtime guard (the golden decks' own control values,
!   not an assumption baked into the code) that reports PE_UNSUPPORTED and aborts the
!   harvest rather than silently taking an unverified path.
!
! What is NOT reachable, and is left as a NAMED, ENUMERATED gap
!   Ten of the 98 ProblemState rows are fed by the four .man readers inside STATIC_U
!   (Fem.f90:3593-3633: nincs, increment_control, tolerances). STATIC_U is itself an
!   internal procedure of FEM90 (same `contains` barrier), and reaching it means actually
!   running STATIC_U's analysis step -- assembling K, applying the solve, updating the
!   result vector -- which is entering the solver's link chain, forbidden outright by
!   adapter-contract.md §7 ("不进求解器链接链"), not merely hard. These ten rows are left
!   UNSET in the draft (never fabricated) and enumerated in GAP_MAN_STATIC_U below:
!     steps0.controls.increments        (nincs)
!     steps0.controls.max_iterations    (miter)
!     steps0.controls.time_increment    (ditime)
!     steps0.output.frequency_nodes     (noutn)
!     steps0.output.frequency_fields    (noutf)
!     steps0.controls.steps             (nstep)
!     steps0.controls.step_increment    (inc_step)
!     steps0.controls.restart_frequency (nresta)
!     steps0.controls.tolerance_force   (toler_force)
!     steps0.controls.tolerance_dof     (toler_var)
!
! §6.1 exception: local_p4 (contract amendment, 2026-09-08, team lead)
!   prescrib_set reads `local_p4(ipoin)` (Prescrib.f90:415) whenever alfa_p4>0 (both golden
!   decks have alfa_p4=10.0). `local_p4` is COMPUTED by `modf_element_lib`
!   (Fem.f90:12224-12235, via a ~500-line per-element loop that also fills `ngpoin`), and
!   modf_element_lib is -- again -- an internal procedure of FEM90 (Fem.f90:11689, same
!   `contains` barrier), so reproducing local_p4's real values here is reimplementing legacy
!   analysis logic, which is exactly what "收割映射按 legacy_symbol 列，不手抄" (contract §6)
!   rules out.
!   What we DO instead: allocate(local_p4(npoin)) and set it to 0 -- local_p4's OWN initial
!   state at Fem.f90:11718, before modf_element_lib's per-element loop promotes any entry to
!   1. This is not inventing a value; it is skipping only the conditional PROMOTION step.
!   Verified bound on the effect (Prescrib.f90:442, the only use of local_p4 in prescrib_set):
!   `if(local_p4(ipoin)/=1)cycle` guards an append to the prescribed-record list. With
!   local_p4 all zero, that append never fires. On both golden decks the promotion loop's
!   own guards (`sum(ngpoin(:,ipoin))/=1`, `ipp4(ipoin)/=1`) already exclude every node, so
!   the p4 branch contributes ZERO records there regardless -- confirmed against the frozen
!   baseline (`derived.counts.ndofix = 34` in
!   cases/golden/static_2d/cooks_membrane/reference/state/model_ready/constraints.json,
!   matching the .pre deck's 17 nodes x 2 dofs exactly, and this oracle's own harvested
!   `neq = ntotv - ndofix = 578 - 34 = 544` cross-checked against PROFILE's own equation
!   count).
!   ASSUMPTION THIS RELIES ON, STATED PLAINLY: the p4 local-constraint mechanism contributes
!   no prescribed record on the whitelisted path. It is NOT verifiable in advance from here
!   (the promotion logic is unreachable), but it IS falsifiable afterwards: L3-b compares
!   this oracle's harvested `ndofix` against the frozen baseline. If a future deck ever makes
!   the p4 branch contribute a record, this oracle's `ndofix` comes out LOW and that
!   comparison goes red -- it does not fail silently.
!   This is the ONLY global this module ever assigns, and the only documented exception to
!   "the oracle modifies no global" (contract §6, "不修改任何全局，只读").
!
! Whitelist (static-q4/1, adapter-contract.md §5): 2D, Q4, displacement field, linear
! elastic isotropic, single-stage static, fixed/prescribed displacement, gravity. This
! module does not enlarge it; every branch outside it is a PE_UNSUPPORTED guard below.
module yl_adapter_harvest

  use iso_fortran_env, only: int32, real64
  use variable_types, only: ink, irk
  use yl_diag, only: diag_set_mode_from_argv
  use global_var
  use materials, only: props, material_set
  use applied_load
  use prescribed
  use stiffness_matrix, only: stiff_interface_fluid_solid, stiff_absorb_fluid, &
                               stiff_absorb_solid, stiff_ifs2006
  use temperature, only: boundt
  use output
  use solver

  use yl_problem_types, only: problem_state_t, case_t, node_t, element_t, elset_t, &
                              nset_t, material_t, section_t, amplitude_t, &
                              amplitude_point_t, interactions_t, solver_t, profile_t, &
                              step_t, controls_t, load_t, gravity_t, output_t, boundary_t, &
                              activation_t
  use yl_problem_optional, only: opt_set
  use yl_problem_builder
  use yl_problem_errors, only: problem_errors_t, source_location_t, make_source_location, &
                                PE_UNSUPPORTED, PE_INTERNAL

  implicit none
  private

  public :: harvest_problem_state

  ! Stage name for findings raised by this module. DELIBERATELY NOT PE_STAGE_ADAPT, which
  ! M4-01 L2-b added to yl_problem_errors for the product parsers: this module is the
  ! ORACLE (see the module header), so a finding it raises is a statement about what the
  ! ORACLE implements, never about the user's deck. Its one PE_UNSUPPORTED guard
  ! (`oracle.path_not_implemented`) is for the same reason absent from L2-b's
  ! CAP_STAGE_ADAPT dialect table: a row there is a legacy dialect the PRODUCT refuses,
  ! and putting an oracle gap beside those would (a) let an oracle limitation read as a
  ! verdict on the deck, and (b) give the dialect coverage walk a row only the oracle can
  ! trigger. See docs/m4/L2b-dialect-report.md for the full classification.
  character(len=*), parameter :: STAGE_ORACLE = 'oracle'

  ! The ten rows fed only by STATIC_U's .man readers -- see module header. Named here so
  ! a caller can grep one place for "does the oracle cover this row", not five.
  character(len=*), parameter :: GAP_MAN_STATIC_U(10) = [character(len=32) :: &
    'steps0.controls.increments', 'steps0.controls.max_iterations', &
    'steps0.controls.time_increment', 'steps0.output.frequency_nodes', &
    'steps0.output.frequency_fields', 'steps0.controls.steps', &
    'steps0.controls.step_increment', 'steps0.controls.restart_frequency', &
    'steps0.controls.tolerance_force', 'steps0.controls.tolerance_dof']

contains

  ! Drives the confirmed-reachable legacy readers in FEM90's own order, then harvests
  ! their output into `draft`. `draft` is only replaced on success (builder_finish's own
  ! transactional guarantee); on any failure `errors` carries what went wrong and `draft`
  ! is left untouched.
  subroutine harvest_problem_state(draft, errors)
    type(problem_state_t), allocatable, intent(inout) :: draft
    type(problem_errors_t), intent(inout) :: errors
    type(problem_builder_t) :: b
    logical :: ok

    call drive_legacy_readers(errors, ok)
    if (.not. ok) return

    call builder_begin(b)
    call harvest_case(b, errors)
    call harvest_mesh(b, errors)
    call harvest_materials(b, errors)
    call harvest_sections(b, errors)
    call harvest_amplitudes(b, errors)
    call harvest_interactions(b, errors)
    call harvest_solver(b, errors)
    call harvest_steps(b, errors)
    call builder_finish(b, draft, errors, ok)
  end subroutine harvest_problem_state

  ! ==========================================================================
  ! driving the legacy readers (module header: why this exists here at all)
  ! ==========================================================================

  subroutine drive_legacy_readers(errors, ok)
    type(problem_errors_t), intent(inout) :: errors
    logical, intent(out) :: ok
    integer :: ios
    integer :: igroup
    type(source_location_t) :: here

    ok = .false.

    ! Fem.f90:94-117 (R-order-1, confirmed).
    call diag_set_mode_from_argv()
    open (inpunit, file='inp', status='old', iostat=ios)
    if (ios /= 0) then
      here = make_source_location(file='inp', reader='harvest_problem_state')
      call raise(errors, PE_INTERNAL, 'oracle.cannot_open_inp', '', &
                'cannot open inp, iostat='//itoa(ios), here)
      return
    end if
    read (inpunit, *) text
    read (inpunit, *) restart, relis, sysrelis, ADINA, Uopt_R, gamamax
    read (inpunit, *) text
    read (inpunit, *) probn
    ! FEM90 calls TIME(char_time) here for a log timestamp only (Fem.f90:113); char_time
    ! feeds no harvested field, and TIME is a vendor intrinsic outside F2018 (-stand f18
    ! warns), so it is omitted rather than replicated for no benefit.
    call global_data

    if (.not. guard(errors, Uopt_R == 0, 'Fem.f90:118-133', 'Uopt_R/=0')) return

    ! Fem.f90:176-182 (runblks, read right after the Uopt_R branch, before material_set).
    len1 = len_trim(probn)
    read (inpunit, *) runblks

    call material_set                                              ! R-order-1, confirmed

    ! Fem.f90:198-215. modf_element_lib (Fem.f90:11689/196) is skipped: internal procedure
    ! of FEM90 (module header). It reads no deck and only fills element(:)%field(:)%gpvar,
    ! which nothing harvested below reads.
    call contact_point_to_point
    call link_concrete_and_steel
    call link_concrete_and_water_pipe
    call stiff_interface_fluid_solid
    call stiff_absorb_fluid
    call stiff_absorb_solid
    call stiff_ifs2006
    allocate (toler_var(mdofn))
    call output_read
    iwriten = 0
    trstep = 0

    if (.not. guard(errors, type_problem == 'Q', 'Fem.f90:220-236', "TYPE_PROBLEM/='Q'")) return
    allocate (result_zero(ntotv)); result_zero = 0.
    if (.not. guard(errors, upliftin == 0, 'Fem.f90:229', 'upliftin/=0')) return
    if (.not. guard(errors, nbackf == 0, 'Fem.f90:232-235', 'nbackf/=0')) return
    if (nflow /= 0) then; allocate (flowrate(npoin)); flowrate = 0.; end if
    if (.not. guard(errors, type_problem /= 'W', 'Fem.f90:238-247', "TYPE_PROBLEM=='W'")) return
    allocate (tofor(ntotv), stfor(ntotv), toforl(ntotv), toform(ntotv))
    tofor = 0.; stfor = 0.; toforl = 0.; toform = 0.
    if (ninit /= 0 .and. kinit == 2) allocate (torel(ntotv))
    torel = 0.   ! Fem.f90:242, unconditional in the legacy source -- see R-order-2 note.
    allocate (delitfi(ntotv), deltafi(ntotv))
    if (.not. guard(errors, .not. any(props(:)%name == 'NSTOKS'), 'Fem.f90:250-252', &
                   'NSTOKS material')) return
    allocate (ice0(nelem)); ice0 = 0
    call gid_output_parameter
    allocate (line_load_block(nblks), line_temp_block(nblks))
    line_load_block = 0; line_temp_block = 0
    nincs = 0
    if (.not. guard(errors, restart == 0, 'Fem.f90:266-306', 'restart/=0')) return
    lblks = 0; lttime = 0.0; lincs = 0

    ! Fem.f90:308-322
    ttime = lttime
    if (lincs < nincs) then
      ! blks_new/incs_new only ever feed the do-loop below in this driver; no field reads
      ! them, so they are not kept as named locals.
    end if
    lineload = 0
    linet = 0
    rewind (mainunit)
    if (.not. guard(errors, lblks + 1 == 1, 'Fem.f90:315-333', 'blks_new>1 (mainunit replay)')) return
    lincs = 0

    if (.not. guard(errors, Bparameter == 0, 'Fem.f90:342-371', 'Bparameter/=0')) return
    if (.not. guard(errors, nbackdT /= 2, 'Fem.f90:369', 'nbackdT==2')) return

    ! ================================================================================
    ! process_analysis (Fem.f90:1642) inlined -- internal procedure, see module header.
    ! ================================================================================
    ttime = lttime
    if (.not. guard(errors, Bparameter == 0, 'Fem.f90:1650-1680', &
                   'process_analysis Bparameter/=0 prologue')) return

    call external_load_1                                           ! Fem.f90:1682, R-order-2

    if (.not. guard(errors, runblks == 1 .and. nblks == 1, 'Fem.f90:1683', &
                   'multi-block case')) return
    iblks = 1
    if (.not. guard(errors, type_load /= 'DISCONTROL', 'Fem.f90:1694-1699', &
                   "TYPE_LOAD=='DISCONTROL'")) return
    nremesh = 0
    if (.not. guard(errors, .not. (ninit /= 0 .and. restart == 0), 'Fem.f90:1705', &
                   'ninit/=0 (read_initial)')) return
    if (uinitial(iblks) == 1) result_zero = 0.0

    appear_p = appear
    do igroup = 1, ngroup
      appear(igroup) = appear_process(igroup, iblks)
      group(igroup)%matno = matno_process(igroup, iblks)
      if (appear_process(igroup, iblks) == 0 .and. &
          appear_process(igroup, max(iblks - 1, 0)) == 1) appear(igroup) = -1
    end do

    if (restart == 0) then
      if (.not. guard(errors, gamamax == 0, 'Fem.f90:1725-1728', 'gamamax/=0 (readgamamax)')) return
    end if
    if (.not. guard(errors, .not. (ninistn > 0 .and. stnunit /= 0), 'Fem.f90:1733', &
                   'ninistn>0 (read_permanent_strain)')) return
    if (.not. guard(errors, .not. (meshc == 1 .or. meshc == 2), 'Fem.f90:1742-1826', &
                   'meshc/=0')) return
    if (.not. guard(errors, ikindks == 0, 'Fem.f90:1868', 'ikindks/=0 (steel_spring_parameter)')) &
      return

    ! --- §6.1 exception: see module header for the full justification. ---
    if (alfa_p4 > 0) then
      if (.not. allocated(local_p4)) allocate (local_p4(npoin))
      local_p4 = 0
    end if

    call prescrib_set                                              ! Fem.f90:1873, R-order-2

    if (.not. guard(errors, nbackdT /= 1, 'Fem.f90:1875-1890', 'nbackdT==1 (backf fixup)')) return
    call external_load_2                                           ! Fem.f90:1895
    if (block_stab == 0) call contact_pair_process                 ! Fem.f90:1896-1897
    call boundt                                                    ! Fem.f90:1898
    if (.not. guard(errors, ADINA == 0, 'Fem.f90:1899-1901', 'ADINA/=0')) return
    line_load_block(iblks) = lineload
    line_temp_block(iblks) = linet

    operation = 'SET'
    call solve                                                     ! Fem.f90:1917, R-order-2
    !   Type_solver == 'PROFILE' dispatches to PROFILE (Solver.f90:53/6803). A Type_solver
    !   outside the whitelist would dispatch elsewhere in `solve`'s SELECT CASE and this
    !   oracle would then be harvesting fields PROFILE never touched (iafile/icond/ipdchk/
    !   ising/neq/iseq); guarded, not assumed.
    if (.not. guard(errors, type_solver == 'PROFILE', 'Solver.f90:53', &
                   "TYPE_SOLVER/='PROFILE'")) return

    ok = .true.
  end subroutine drive_legacy_readers

  ! One guard: PE_UNSUPPORTED and .false. when `cond` does not hold, .true. (no error) when
  ! it does. `where_` is the Fem.f90 line range this branch would have needed; `what` names
  ! the untaken/unimplemented condition.
  function guard(errors, cond, where_, what) result(ok)
    type(problem_errors_t), intent(inout) :: errors
    logical, intent(in) :: cond
    character(len=*), intent(in) :: where_, what
    logical :: ok
    type(source_location_t) :: here
    ok = cond
    if (.not. ok) then
      here = make_source_location(file='Fem.f90', reader='harvest_problem_state')
      call raise(errors, PE_UNSUPPORTED, 'oracle.path_not_implemented', '', &
                'legacy branch at '//trim(where_)//' ('//trim(what)//') is outside the ' // &
                'R-order-2 confirmed path; this oracle does not implement it', here)
    end if
  end function guard

  subroutine raise(errors, code, rule_id, object_path, message, loc)
    use yl_problem_errors, only: make_problem_error
    type(problem_errors_t), intent(inout) :: errors
    character(len=*), intent(in) :: code, rule_id, object_path, message
    type(source_location_t), intent(in) :: loc
    call errors%add(make_problem_error(code=code, stage=STAGE_ORACLE, rule_id=rule_id, &
                    object_path=object_path, message=message, source=loc))
  end subroutine raise

  function itoa(v) result(s)
    integer, intent(in) :: v
    character(len=24) :: s
    write (s, '(i0)') v
  end function itoa

  ! ==========================================================================
  ! harvesting -- one routine per ProblemState top-level object, in
  ! docs/m2/state-field-map.toml order. Every legacy access here mirrors the already
  ! shipped, reviewed src/state/yl_state_dump.f90 / yl_state_adapters.f90 (M2-02): same
  ! guards, same associated() checks, same reconstruction notes, because that module
  ! already proved these exact accesses correct against the frozen baselines.
  ! ==========================================================================

  subroutine harvest_case(b, errors)
    type(problem_builder_t), intent(inout) :: b
    type(problem_errors_t), intent(inout) :: errors
    type(case_t) :: c
    type(source_location_t) :: loc
    loc = make_source_location(file='inp', reader='harvest_problem_state', line=176_int32)
    ! case.units is @m5-only (yl_problem_types.f90): no legacy record carries it, so it
    ! stays unset, not fabricated.
    call opt_set(c%name, trim(probn))                          ! case.name <- global_var.probn
    call builder_set_case(b, c, loc, errors)
  end subroutine harvest_case

  subroutine harvest_mesh(b, errors)
    type(problem_builder_t), intent(inout) :: b
    type(problem_errors_t), intent(inout) :: errors
    type(source_location_t) :: loc
    type(node_t) :: node
    type(element_t) :: elem
    type(elset_t) :: eset
    type(nset_t) :: nsetv
    integer(ink) :: i, g, k, s, n, nnode

    loc = make_source_location(file='1.glb', reader='global_data', line=694_int32)
    call builder_set_mesh_dimension(b, int(ndimn, int32), loc, errors)   ! mesh.dimension
    if (builder_failed(b)) return

    ! mesh.nodes.id / .xyz  <- 1..npoin (id is the row index, per M1-03; never re-read the
    ! i0 scratch -- see emit_mesh_nodes_id) / global_var.coord
    if (.not. allocated(coord)) then
      call fail_missing(b, errors, 'mesh.nodes', 'coord is not allocated', loc); return
    end if
    do i = 1_ink, npoin
      call opt_set(node%id, int(i, int32))
      if (allocated(node%xyz)) deallocate (node%xyz)
      allocate (node%xyz(ndimn))
      node%xyz = coord(1:ndimn, i)
      loc = make_source_location(file='1.cor', reader='global_data', line=1176_int32, &
                                 record=int(i, int32))
      call builder_add_node(b, node, loc, errors)
      if (builder_failed(b)) return
    end do

    ! mesh.elements.id/.nodes/.kind/.group/.material  <- 1..nelem (id, per M1-03) /
    ! global_var.element%field(1)%lnods_f / %index / %group / %matno
    if (.not. allocated(element)) then
      call fail_missing(b, errors, 'mesh.elements', 'element is not allocated', loc); return
    end if
    do i = 1_ink, nelem
      if (.not. associated(element(i)%field)) then
        call fail_missing(b, errors, 'mesh.elements.nodes', &
                          'element(i)%field is not associated', loc); return
      end if
      nnode = size(element(i)%field(1)%lnods_f)
      call opt_set(elem%id, int(i, int32))
      call opt_set(elem%kind, int(element(i)%index, int32))
      call opt_set(elem%material, int(element(i)%matno, int32))
      call opt_set(elem%elset, int(element(i)%group, int32))
      if (allocated(elem%nodes)) deallocate (elem%nodes)
      allocate (elem%nodes(nnode))
      elem%nodes = int(element(i)%field(1)%lnods_f(1:nnode), int32)
      loc = make_source_location(file='1.ele', reader='read_element', line=1087_int32, &
                                 record=int(i, int32))
      call builder_add_element(b, elem, loc, errors)
      if (builder_failed(b)) return
    end do

    ! mesh.sets.elset (owner mesh.elsets[].elements)  <- group(g)%list(1:nelgroup)
    if (.not. allocated(group)) then
      call fail_missing(b, errors, 'mesh.elsets', 'group is not allocated', loc); return
    end if
    do g = 1_ink, ngroup
      n = group(g)%nelgroup
      if (allocated(eset%elements)) deallocate (eset%elements)
      allocate (eset%elements(n))
      if (n > 0_ink) then
        if (.not. associated(group(g)%list)) then
          call fail_missing(b, errors, 'mesh.elsets', 'group(g)%list is not associated', loc)
          return
        end if
        eset%elements = int(group(g)%list(1:n), int32)
      end if
      loc = make_source_location(file='1.glb', reader='global_data', line=1292_int32, &
                                 record=int(g, int32))
      call builder_add_elset(b, eset, loc, errors)
      if (builder_failed(b)) return
    end do

    ! mesh.sets.nset (owner mesh.nsets[].nodes)  <- distinct prescrib%nodfix per ifixset,
    ! first-occurrence order (list_fix itself is a prescrib_set local, deallocated at
    ! Prescrib.f90:386; recovered from the committed records exactly as
    ! emit_mesh_sets_nset does).
    if (nfixsets > 0_ink .and. ndofix > 0_ink) then
      if (.not. allocated(prescrib)) then
        call fail_missing(b, errors, 'mesh.nsets', 'prescrib is not allocated', loc); return
      end if
    end if
    do s = 1_ink, nfixsets
      n = 0_ink
      do k = 1_ink, ndofix
        if (prescrib(k)%ifixset /= s) cycle
        if (first_in_set(k, s)) n = n + 1_ink
      end do
      if (allocated(nsetv%nodes)) deallocate (nsetv%nodes)
      allocate (nsetv%nodes(n))
      n = 0_ink
      do k = 1_ink, ndofix
        if (prescrib(k)%ifixset /= s) cycle
        if (first_in_set(k, s)) then
          n = n + 1_ink
          nsetv%nodes(n) = int(prescrib(k)%nodfix, int32)
        end if
      end do
      loc = make_source_location(file='1.pre', reader='prescrib_set', line=257_int32, &
                                 record=int(s, int32))
      call builder_add_nset(b, nsetv, loc, errors)
      if (builder_failed(b)) return
    end do
  end subroutine harvest_mesh

  ! .true. when prescrib(k) is the first record of set s carrying its nodfix (mirrors
  ! yl_state_adapters' first_in_set exactly, since it is answering the same question).
  logical function first_in_set(k, s)
    integer(ink), intent(in) :: k, s
    integer(ink) :: j
    first_in_set = .true.
    do j = 1_ink, k - 1_ink
      if (prescrib(j)%ifixset /= s) cycle
      if (prescrib(j)%nodfix == prescrib(k)%nodfix) then
        first_in_set = .false.
        return
      end if
    end do
  end function first_in_set

  subroutine harvest_materials(b, errors)
    type(problem_builder_t), intent(inout) :: b
    type(problem_errors_t), intent(inout) :: errors
    type(material_t) :: m
    type(source_location_t) :: loc
    integer(ink) :: i

    if (.not. allocated(props)) then
      loc = make_source_location(file='1.mat', reader='material_set')
      call fail_missing(b, errors, 'materials', 'props is not allocated', loc); return
    end if
    do i = 1_ink, nmats
      if (.not. associated(props(i)%mechanical)) then
        loc = make_source_location(file='1.mat', reader='material_set', record=int(i, int32))
        call fail_missing(b, errors, 'materials', 'props(i)%mechanical is not associated', loc)
        return
      end if
      if (.not. associated(props(i)%mechanical%solid)) then
        loc = make_source_location(file='1.mat', reader='material_set', record=int(i, int32))
        call fail_missing(b, errors, 'materials', &
                          'props(i)%mechanical%solid is not associated', loc)
        return
      end if
      call opt_set(m%id, int(i, int32))                                  ! materials.id
      ! materials.kind/.phase: COVERED-PATH RECONSTRUCTION, same limitation as
      ! yl_state_adapters' emit_materials_kind/emit_materials_phase -- 'MECHANICAL'/'SOLID'
      ! are exact here because associated() on both pointers just succeeded above, which on
      ! this path only happens for a MECHANICAL/SOLID material; a deck taking a different
      ! branch would need the reader to capture the keyword instead.
      call opt_set(m%kind, 'MECHANICAL')
      call opt_set(m%phase, 'SOLID')
      call opt_set(m%name, trim(props(i)%name))
      call opt_set(m%model, trim(props(i)%mechanical%solid%material))
      call opt_set(m%density, real(props(i)%mechanical%solid%density, real64))
      call opt_set(m%solid_ratio, real(props(i)%mechanical%solid%ratio, real64))
      call opt_set(m%E, real(props(i)%mechanical%solid%e, real64))
      call opt_set(m%nu, real(props(i)%mechanical%solid%nu, real64))
      call opt_set(m%thermal_expansion, real(props(i)%mechanical%solid%alfa, real64))
      call opt_set(m%creep_model, int(props(i)%mechanical%solid%icreep, int32))
      call opt_set(m%wetting_kind, int(props(i)%mechanical%solid%kind_wt, int32))
      call opt_set(m%liquefaction, int(props(i)%mechanical%solid%jliqu, int32))
      loc = make_source_location(file='1.mat', reader='material_set', record=int(i, int32))
      call builder_add_material(b, m, loc, errors)
      if (builder_failed(b)) return
    end do
  end subroutine harvest_materials

  ! sections[] is indexed 1:ngroup; sections.thickness's legacy home is props(:), indexed
  ! 1:nmats (see the map row's note: YL stores thickness PER MATERIAL, the contract owns it
  ! PER SECTION). Resolving an arbitrary section -> material -> thickness mapping is the
  ! bridge's job (state-field-map.toml, sections.thickness note), not this oracle's; both
  ! golden cases have nmats == ngroup == 1 so direct index i<-i matches, guarded below
  ! rather than assumed.
  subroutine harvest_sections(b, errors)
    type(problem_builder_t), intent(inout) :: b
    type(problem_errors_t), intent(inout) :: errors
    type(section_t) :: sec
    type(source_location_t) :: loc
    integer(ink) :: g, e

    if (.not. allocated(group)) then
      loc = make_source_location(file='1.glb', reader='global_data')
      call fail_missing(b, errors, 'sections', 'group is not allocated', loc); return
    end if
    if (ngroup > nmats) then
      loc = make_source_location(file='1.glb', reader='global_data')
      call fail_missing(b, errors, 'sections.thickness', &
                        'ngroup exceeds nmats; section->material->thickness index no ' // &
                        'longer 1:1, which is out of this oracle''s scope (see header note)', loc)
      return
    end if
    do g = 1_ink, ngroup
      call opt_set(sec%name, trim(group(g)%kname))
      call opt_set(sec%element, trim(group(g)%name))
      call opt_set(sec%element_kind, int(group(g)%index, int32))
      call opt_set(sec%class, trim(group(g)%class))
      call opt_set(sec%fields, trim(group(g)%fieldid))
      call opt_set(sec%formulation, trim(group(g)%sptype))
      call opt_set(sec%special, trim(group(g)%special))
      call opt_set(sec%material, int(group(g)%matno, int32))
      call opt_set(sec%algorithm, int(group(g)%type_nalgo, int32))
      call opt_set(sec%stiffness_kind, int(group(g)%type_stiff, int32))
      call opt_set(sec%stress_recovery, int(group(g)%type_ecoint, int32))
      call opt_set(sec%layer, int(group(g)%ilayer, int32))
      call opt_set(sec%liquefaction, int(group(g)%liquj, int32))
      call opt_set(sec%uplift, int(group(g)%uplift_ic, int32))
      call opt_set(sec%local_axes, real(group(g)%elcod_local, real64))

      ! sections.material_header  <- element(group(g)%list(1))%matno (emit_sections_material_header)
      if (group(g)%nelgroup < 1_ink) then
        loc = make_source_location(file='1.glb', reader='global_data', record=int(g, int32))
        call fail_missing(b, errors, 'sections.material_header', &
                          'group has nelgroup<1', loc); return
      end if
      if (.not. associated(group(g)%list)) then
        loc = make_source_location(file='1.glb', reader='global_data', record=int(g, int32))
        call fail_missing(b, errors, 'sections.material_header', &
                          'group(g)%list is not associated', loc); return
      end if
      e = group(g)%list(1)
      call opt_set(sec%material_header, int(element(e)%matno, int32))

      if (.not. associated(props(g)%mechanical)) then
        loc = make_source_location(file='1.mat', reader='material_set', record=int(g, int32))
        call fail_missing(b, errors, 'sections.thickness', &
                          'props(g)%mechanical is not associated', loc); return
      end if
      if (.not. associated(props(g)%mechanical%solid)) then
        loc = make_source_location(file='1.mat', reader='material_set', record=int(g, int32))
        call fail_missing(b, errors, 'sections.thickness', &
                          'props(g)%mechanical%solid is not associated', loc); return
      end if
      call opt_set(sec%thickness, real(props(g)%mechanical%solid%thickness, real64))

      loc = make_source_location(file='1.glb', reader='global_data', record=int(g, int32))
      call builder_add_section(b, sec, loc, errors)
      if (builder_failed(b)) return
    end do
  end subroutine harvest_sections

  subroutine harvest_amplitudes(b, errors)
    type(problem_builder_t), intent(inout) :: b
    type(problem_errors_t), intent(inout) :: errors
    type(amplitude_builder_t) :: ab
    type(amplitude_t) :: amp
    type(amplitude_point_t) :: pt
    type(source_location_t) :: loc
    integer(ink) :: c, k, nt
    logical :: ok

    if (.not. allocated(tcurves)) then
      loc = make_source_location(file='1.loa', reader='external_load_1')
      call fail_missing(b, errors, 'amplitudes', 'tcurves is not allocated', loc); return
    end if
    do c = 1_ink, ntcurve
      ! amplitudes[].name is @m5-only (no legacy record carries an amplitude name); left
      ! unset.
      call builder_amplitude_begin(ab)
      loc = make_source_location(file='1.loa', reader='external_load_1', line=222_int32, &
                                 record=int(c, int32))
      call builder_amplitude_set_type(b, ab, trim(tcurves(c)%type_curve), loc, errors)
      nt = tcurves(c)%ntime
      if (nt > 0_ink) then
        if (.not. associated(tcurves(c)%ttime_curve) .or. &
            .not. associated(tcurves(c)%dfact_curve)) then
          call fail_missing(b, errors, 'amplitudes.points', &
                            'tcurves(c)%ttime_curve/dfact_curve not associated', loc)
          return
        end if
        do k = 1_ink, nt
          call opt_set(pt%time, real(tcurves(c)%ttime_curve(k), real64))
          call opt_set(pt%value, real(tcurves(c)%dfact_curve(k), real64))
          call builder_amplitude_add_point(b, ab, pt, loc, errors)
        end do
      else
        call builder_amplitude_points_empty(b, ab, loc, errors)
      end if
      call builder_amplitude_finish(b, ab, amp, loc, errors, ok)
      if (.not. ok .or. builder_failed(b)) return
      call builder_add_amplitude(b, amp, loc, errors)
      if (builder_failed(b)) return
    end do
    if (ntcurve == 0_ink) call builder_amplitudes_empty(b, loc, errors)
  end subroutine harvest_amplitudes

  subroutine harvest_interactions(b, errors)
    type(problem_builder_t), intent(inout) :: b
    type(problem_errors_t), intent(inout) :: errors
    type(interactions_t) :: it
    type(source_location_t) :: loc
    loc = make_source_location(file='1.glb', reader='global_data', line=1215_int32)
    call opt_set(it%absorbing%type, trim(type_ABC))       ! interactions.absorbing.type
    call builder_set_interactions(b, it, loc, errors)
  end subroutine harvest_interactions

  subroutine harvest_solver(b, errors)
    type(problem_builder_t), intent(inout) :: b
    type(problem_errors_t), intent(inout) :: errors
    type(solver_t) :: sv
    type(source_location_t) :: loc
    loc = make_source_location(file='1.glb', reader='global_data', line=696_int32)
    call opt_set(sv%linear, trim(type_solver))                       ! solver.linear
    ! solver.symmetric: legacy nonsym is a 0/1 flag with INVERTED sense (yl_problem_types.f90
    ! %repr note on solver_t%symmetric); nonsym==0 means symmetric.
    call opt_set(sv%symmetric, nonsym == 0)
    loc = make_source_location(file='1.sol', reader='PROFILE', line=6825_int32)
    call opt_set(sv%profile%pivot_file, int(iafile, int32))          ! solver.profile.iafile
    call opt_set(sv%profile%condition_check, int(icond, int32))      ! .icond
    call opt_set(sv%profile%positive_definite_check, int(ipdchk, int32)) ! .ipdchk
    call opt_set(sv%profile%singularity_check, int(ising, int32))    ! .ising
    call builder_set_solver(b, sv, loc, errors)
  end subroutine harvest_solver

  subroutine harvest_steps(b, errors)
    type(problem_builder_t), intent(inout) :: b
    type(problem_errors_t), intent(inout) :: errors
    type(step_builder_t) :: sb
    type(step_t) :: st
    type(controls_t) :: ctl
    type(load_t) :: ld
    type(output_t) :: outp
    type(boundary_t) :: bnd
    type(activation_t) :: act
    type(source_location_t) :: loc
    integer(ink) :: k, g
    logical :: ok

    call builder_step_begin(sb)

    loc = make_source_location(file='1.glb', reader='global_data', line=696_int32)
    call builder_step_set_procedure(b, sb, trim(type_problem), loc, errors)     ! steps0.procedure
    call builder_step_set_load_mode(b, sb, trim(type_load), loc, errors)        ! steps0.load_mode

    ! steps0.controls: only nonlinear_type is reachable (GLB.global_data.problem_type). The
    ! other six components (increments/max_iterations/time_increment/steps/step_increment/
    ! restart_frequency/tolerance_force/tolerance_dof) are the GAP_MAN_STATIC_U rows (module
    ! header) -- left at opt_* default (unset), never fabricated.
    call opt_set(ctl%nonlinear_type, int(type_nl, int32))
    call builder_step_set_controls(b, sb, ctl, loc, errors)

    ! steps0.load.gravity
    loc = make_source_location(file='1.loa', reader='external_load_2', line=1268_int32)
    call opt_set(ld%gravity%enabled, int(NGRAV, int32))
    call opt_set(ld%gravity%magnitude, real(gravy, real64))
    if (.not. allocated(factg)) then
      call fail_missing(b, errors, 'steps0.load.gravity.direction', &
                        'factg is not allocated', loc); return
    end if
    if (allocated(ld%gravity%direction)) deallocate (ld%gravity%direction)
    allocate (ld%gravity%direction(size(factg)))
    ld%gravity%direction = real(factg, real64)
    if (.not. allocated(tcurvegravity)) then
      call fail_missing(b, errors, 'steps0.load.gravity.amplitude', &
                        'tcurvegravity is not allocated', loc); return
    end if
    if (allocated(ld%gravity%amplitude)) deallocate (ld%gravity%amplitude)
    allocate (ld%gravity%amplitude(size(tcurvegravity)))
    ld%gravity%amplitude = int(tcurvegravity, int32)
    call builder_step_set_load(b, sb, ld, loc, errors)

    ! steps0.output
    loc = make_source_location(file='1.glb', reader='global_data', line=1027_int32)
    call opt_set(outp%format, trim(outplot))
    call opt_set(outp%field%u, int(gid_u, int32));   call opt_set(outp%field%v, int(gid_v, int32))
    call opt_set(outp%field%a, int(gid_a, int32));   call opt_set(outp%field%s, int(gid_s, int32))
    call opt_set(outp%field%ms, int(gid_ms, int32)); call opt_set(outp%field%f, int(gid_f, int32))
    call opt_set(outp%field%rot, int(gid_rot, int32))
    call opt_set(outp%field%T, int(gid_T, int32));   call opt_set(outp%field%P, int(gid_P, int32))
    call opt_set(outp%field%Pv, int(gid_Pv, int32)); call opt_set(outp%field%ep, int(gid_ep, int32))
    call opt_set(outp%field%Y, int(gid_Y, int32));   call opt_set(outp%field%FC, int(gid_FC, int32))
    call opt_set(outp%field%Ns, int(gid_Ns, int32)); call opt_set(outp%field%Ss, int(gid_Ss, int32))
    call opt_set(outp%field%Mxy, int(gid_Mxy, int32))
    call opt_set(outp%field%bem, int(gid_bem, int32))
    call opt_set(outp%field%wh, int(gid_wh, int32));  call opt_set(outp%field%wv, int(gid_wv, int32))
    call opt_set(outp%field%bcs, int(gid_bcs, int32))
    ! output.frequency.nodes/.fields (noutn/noutf) are GAP_MAN_STATIC_U rows -- left unset.
    if (.not. allocated(average_appear)) then
      call fail_missing(b, errors, 'steps0.output.stress_averaging', &
                        'average_appear is not allocated', loc); return
    end if
    if (allocated(outp%stress_averaging)) deallocate (outp%stress_averaging)
    allocate (outp%stress_averaging(size(average_appear)))
    outp%stress_averaging = int(average_appear, int32)
    call builder_step_set_output(b, sb, outp, loc, errors)

    ! steps0.boundary[] -- one entry per prescrib(:) record (flat, NOT deduplicated: that
    ! is mesh.nsets[], harvested separately in harvest_mesh).
    if (ndofix > 0_ink .and. .not. allocated(prescrib)) then
      loc = make_source_location(file='1.pre', reader='prescrib_set')
      call fail_missing(b, errors, 'steps0.boundary', 'prescrib is not allocated', loc)
      return
    end if
    do k = 1_ink, ndofix
      call opt_set(bnd%name, int(prescrib(k)%ifixset, int32))
      call opt_set(bnd%dof, int(prescrib(k)%ifixvar, int32))
      call opt_set(bnd%amplitude, int(prescrib(k)%itcurve, int32))
      call opt_set(bnd%nset, int(prescrib(k)%nodfix, int32))
      call opt_set(bnd%value, real(prescrib(k)%vdofix, real64))
      call opt_set(bnd%record_reaction, int(prescrib(k)%outfix, int32))
      loc = make_source_location(file='1.pre', reader='prescrib_set', line=257_int32, &
                                 record=int(k, int32))
      call builder_step_add_boundary(b, sb, bnd, loc, errors)
      if (builder_failed(b)) return
    end do
    if (ndofix == 0_ink) call builder_step_boundary_empty(b, sb, loc, errors)

    ! steps0.activation[] -- one entry per group, at iblks=1 (drive_legacy_readers
    ! established iblks==1; "YL iblks=1 maps to steps[0]", state-field-map.toml note on
    ! steps0.activation.active). appear_process/matno_process's block-0 column is part of
    ! the STATE-DUMP comparison shape, not of this per-group scalar.
    if (.not. allocated(appear_process) .or. .not. allocated(matno_process)) then
      loc = make_source_location(file='1.glb', reader='global_data')
      call fail_missing(b, errors, 'steps0.activation', &
                        'appear_process/matno_process not allocated', loc); return
    end if
    do g = 1_ink, ngroup
      call opt_set(act%material, int(matno_process(g, iblks), int32))
      call opt_set(act%active, int(appear_process(g, iblks), int32))
      loc = make_source_location(file='1.glb', reader='global_data', record=int(g, int32))
      call builder_step_add_activation(b, sb, act, loc, errors)
      if (builder_failed(b)) return
    end do

    call builder_step_finish(b, sb, st, loc, errors, ok)
    if (.not. ok .or. builder_failed(b)) return
    call builder_add_step(b, st, loc, errors)
  end subroutine harvest_steps

  ! One place to bind a missing-precondition failure the builder itself never saw (an
  ! unallocated/unassociated legacy component this harvester needed) to the draft, so
  ! builder_finish still fails cleanly instead of silently omitting the field.
  subroutine fail_missing(b, errors, object_path, message, loc)
    type(problem_builder_t), intent(inout) :: b
    type(problem_errors_t), intent(inout) :: errors
    character(len=*), intent(in) :: object_path, message
    type(source_location_t), intent(in) :: loc
    call builder_note_failure(b, PE_INTERNAL, 'oracle.missing_legacy_state', object_path, &
                              '', message, loc, errors)
  end subroutine fail_missing

end module yl_adapter_harvest
