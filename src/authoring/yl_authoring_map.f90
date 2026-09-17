! yl_authoring_map -- authoring model -> ProblemState. The only path there is.
!
! THE RULE THIS MODULE EXISTS TO KEEP
!   The modern input reaches the solver the SAME way the legacy deck does:
!
!       case.toml -> ProblemState -> build_runtime -> commit -> solver
!
!   It writes no legacy global, allocates nothing in `global_var`, and knows nothing about
!   the commit layer. Everything downstream of `prepare_problem` is the machinery M3 and
!   M4 already built and proved; if the modern path could reach around ProblemState it
!   would also reach around every gate that guards it.
!
! WHERE EACH FIELD COMES FROM
!   Three sources, and the contract says which is which:
!     * the author            -- every physical choice (docs/m5/authoring-contract.md SS5)
!     * the contract defaults -- everything that is not a physical choice, each with its
!                                reason recorded in that same table
!     * the mesh file         -- nodes, elements, and the element/section attribution
!   A field that appears in none of the three is a defect in this module, not a default.
!
! THE MESH IS READ BY THE ADAPTER'S OWN PARSERS
!   `parse_cor`/`parse_ele` already turn a legacy `.cor`/`.ele` pair into builder calls,
!   with the positional section attribution the format requires. The contract says the
!   mesh comes from such a pair, so reusing them is the honest move: a second mesh reader
!   would be a second thing that can disagree about what a node record means.
!
!   One thing they need that only `.glb` used to supply: how many element records belong
!   to each section. That is a COUNT, not a parse, so this module makes one counting pass
!   over `.ele`'s group column and hands the result over. Counting is not reading in the
!   sense the contract cares about -- no value enters ProblemState from that pass.
module yl_authoring_map

  use iso_fortran_env, only: int32, real64

  use yl_problem_optional, only: opt_set, opt_int, opt_real, opt_text
  use yl_problem_types, only: problem_state_t, case_t, material_t, section_t, amplitude_t,  &
                              amplitude_point_t, solver_t, boundary_t, controls_t,           &
                              gravity_t, load_t, output_t, output_field_t, step_t,           &
                              surface_edge_t, pressure_t, concentrated_t,                     &
                              activation_t, nset_t
  use yl_problem_errors, only: problem_errors_t, problem_error_t, source_location_t,        &
                               make_problem_error, make_source_location,                     &
                               PE_INVALID_INPUT, PE_EXIT_INPUT,                        &
                               PE_UNSUPPORTED, PE_EXIT_UNSUPPORTED
  use yl_problem_manifest, only: manifest_t
  use yl_problem_builder, only: problem_builder_t, step_builder_t, amplitude_builder_t,      &
                                builder_begin, builder_finish, builder_failed,               &
                                builder_set_case, builder_set_mesh_dimension,                &
                                builder_set_interactions, builder_set_solver,                &
                                builder_add_material, builder_add_section,                   &
                                builder_add_nset, builder_nsets_empty,                       &
                                builder_add_amplitude, builder_add_step,                     &
                                builder_add_surface_edge, builder_surface_edges_empty,        &
                                builder_amplitude_begin, builder_amplitude_finish,           &
                                builder_amplitude_set_name, builder_amplitude_set_type,      &
                                builder_amplitude_add_point,                                 &
                                builder_step_begin, builder_step_finish,                     &
                                builder_step_set_procedure, builder_step_set_load_mode,      &
                                builder_step_set_controls, builder_step_set_load,            &
                                builder_step_set_output, builder_step_add_boundary,          &
                                builder_step_add_activation
  use yl_problem_pipeline, only: prepare_problem
  use yl_problem_profile, only: PROFILE_TAG
  use yl_adapter_parts, only: deck_context_t, deck_context_reset
  use yl_adapter_mesh, only: parse_cor, parse_ele
  use yl_authoring_toml, only: toml_doc_t, TOML_LEN_PATH
  use yl_authoring_defaults

  implicit none
  private

  !> The DISPLAY name of the file being mapped -- what an operator typed after `--input=`.
  !> Set once at the top of `authoring_build_problem` and read only by `here` / `fail` to
  !> label a finding; nothing in this module branches on it. It is module state because the
  !> alternative is threading a string through forty `here(...)` call sites for a label.
  character(len=256) :: site_file = 'case.toml'

  public :: authoring_build_problem

contains

  !> `doc` (already validated) + the mesh files beside it -> a ProblemState.
  !> Transactional in the same sense as `adapt_legacy_deck`: on any finding, `problem` and
  !> `manifest` are left exactly as the caller passed them.
  subroutine authoring_build_problem(doc, dir, problem, manifest, errors, file)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: dir
    !> Display name for the findings; defaults to `case.toml` for callers that have none.
    character(len=*), intent(in), optional :: file
    type(problem_state_t), allocatable, intent(inout) :: problem
    type(manifest_t), allocatable, intent(inout) :: manifest
    type(problem_errors_t), intent(inout) :: errors

    type(problem_builder_t) :: b
    type(step_builder_t) :: sb
    type(amplitude_builder_t) :: ab
    type(deck_context_t) :: ctx
    type(problem_state_t), allocatable :: draft
    integer :: mark0, u_cor, u_ele, ios, i, j, k, n, iset, st, ie, ip, e1, e2
    logical :: ok
    character(len=:), allocatable :: prefix
    type(case_t) :: cs
    type(material_t) :: mat
    type(section_t) :: sec
    type(amplitude_t) :: amp
    type(amplitude_point_t) :: pt
    type(solver_t) :: sol
    type(boundary_t) :: bnd
    type(controls_t) :: ctrl
    type(load_t) :: ld
    type(output_t) :: outp
    type(step_t) :: step_val
    type(activation_t) :: act
    type(nset_t) :: ns
    integer(int32), allocatable :: ids(:), nodes(:)
    character(len=TOML_LEN_PATH) :: gp, lp
    type(surface_edge_t) :: sedge
    type(pressure_t), allocatable :: prs(:)
    type(concentrated_t), allocatable :: cfs(:)

    site_file = 'case.toml'
    if (present(file)) site_file = file

    mark0 = errors%count()
    call builder_begin(b)
    call deck_context_reset(ctx)

    prefix = trim(dir)//'/'//text_at(doc, 'mesh.file')

    ! ProblemState.case.name IS legacy's `probn` -- the problem name every input and output
    ! file is prefixed with -- so it takes mesh.file, not the author's `case.name`, which is
    ! a human label with no legacy counterpart. Mapping the label here would rename the
    ! solver's own output files.
    call opt_set(cs%name, text_at(doc, 'mesh.file'))
    ! units is @m5-only: no legacy record carries it, and ADR-0003 makes the explicit
    ! SI declaration mandatory. The modern path is the first one that can fill it.
    call opt_set(cs%units, text_at(doc, 'case.units'))
    call builder_set_case(b, cs, here(line_at(doc, 'mesh.file')), errors)
    call builder_set_mesh_dimension(b, int_at(doc, 'mesh.dimension'),                        &
                                    here(line_at(doc, 'mesh.dimension')), errors)
    ! interactions: the contract whitelists none, and the absence is the asserted value.
    call builder_set_interactions(b, default_interactions(), here(0_int32), errors)
    if (builder_failed(b)) return

    ! --- the context the mesh parsers need ----------------------------------------
    call fill_context(doc, prefix, ctx, errors)
    if (errors%count() > mark0) return

    open (newunit=u_cor, file=prefix//'.cor', status='old', action='read', iostat=ios)
    if (ios /= 0) then
      call fail(errors, 'mesh.file', 'cannot open '//prefix//'.cor')
      return
    end if
    call parse_cor(u_cor, ctx, b, errors)
    close (u_cor)
    if (errors%count() > mark0) return

    open (newunit=u_ele, file=prefix//'.ele', status='old', action='read', iostat=ios)
    if (ios /= 0) then
      call fail(errors, 'mesh.file', 'cannot open '//prefix//'.ele')
      return
    end if
    call parse_ele(u_ele, ctx, b, errors)
    close (u_ele)
    if (errors%count() > mark0) return

    ! --- node sets ----------------------------------------------------------------
    n = int(doc%count_of('nset'))
    if (n == 0) then
      call builder_nsets_empty(b, here(0_int32), errors)
    else
      do i = 1, n
        call int_list(doc, 'nset['//itoa(i)//'].nodes', ids)
        if (allocated(ns%nodes)) deallocate (ns%nodes)
        allocate (ns%nodes(size(ids)))
        ns%nodes = ids
        call builder_add_nset(b, ns, here(line_at(doc, 'nset['//itoa(i)//'].name')), errors)
        if (builder_failed(b)) return
      end do
    end if

    ! --- materials ----------------------------------------------------------------
    do i = 1, int(doc%count_of('material'))
      call default_material(mat)
      call opt_set(mat%id, int(i, int32))
      call opt_set(mat%model, legacy_material_name(text_at(doc, 'material['//itoa(i)//'].model')))
      call opt_set(mat%density, real_at(doc, 'material['//itoa(i)//'].density'))
      call opt_set(mat%e, real_at(doc, 'material['//itoa(i)//'].E'))
      call opt_set(mat%nu, real_at(doc, 'material['//itoa(i)//'].nu'))
      call opt_set(mat%thermal_expansion,                                                     &
           real_at(doc, 'material['//itoa(i)//'].thermal_expansion'))
      ! The per-model block, set only for the model that has one. `criterion` being set is
      ! what makes the commit allocate legacy's ClassicalEP record, so the whole block is
      ! written together or not at all -- the validator has already refused a half of it.
      if (doc%find('material['//itoa(i)//'].criterion') /= 0_int32) then
        call opt_set(mat%plasticity%criterion,                                                &
             criterion_code(text_at(doc, 'material['//itoa(i)//'].criterion')))
        call opt_set(mat%plasticity%yield_stress, real_at(doc, 'material['//itoa(i)//'].cohesion'))
        call opt_set(mat%plasticity%hardening_modulus,                                        &
             real_at(doc, 'material['//itoa(i)//'].hardening'))
        call opt_set(mat%plasticity%friction_angle,                                           &
             real_at(doc, 'material['//itoa(i)//'].friction_angle'))
        call opt_set(mat%plasticity%dilation_angle,                                           &
             real_at(doc, 'material['//itoa(i)//'].dilation_angle'))
        ! Curve indices: the contract does not admit material property curves at all
        ! (nscurve must be 0), so "no curve" is the only representable answer and 0 is
        ! not a hidden physical choice.
        call opt_set(mat%plasticity%yield_stress_curve, 0_int32)
        call opt_set(mat%plasticity%friction_angle_curve, 0_int32)
        call opt_set(mat%plasticity%dilation_angle_curve, 0_int32)
      end if
      call builder_add_material(b, mat, here(line_at(doc, 'material['//itoa(i)//'].name')), errors)
      if (builder_failed(b)) return
    end do

    ! --- sections -----------------------------------------------------------------
    do i = 1, int(doc%count_of('section'))
      call default_section(sec)
      call opt_set(sec%name, text_at(doc, 'section['//itoa(i)//'].name'))
      call opt_set(sec%element, text_at(doc, 'section['//itoa(i)//'].element'))
      call opt_set(sec%element_kind, element_kind_of(text_at(doc, 'section['//itoa(i)//'].element')))
      call opt_set(sec%formulation, formulation_code(text_at(doc, 'section['//itoa(i)//'].formulation')))
      j = material_index(doc, text_at(doc, 'section['//itoa(i)//'].material'))
      call opt_set(sec%material, int(j, int32))
      call opt_set(sec%material_header, int(j, int32))
      call builder_add_section(b, sec, here(line_at(doc, 'section['//itoa(i)//'].name')), errors)
      if (builder_failed(b)) return
    end do

    ! --- amplitudes ---------------------------------------------------------------
    do i = 1, int(doc%count_of('amplitude'))
      call builder_amplitude_begin(ab)
      call builder_amplitude_set_name(b, ab, text_at(doc, 'amplitude['//itoa(i)//'].name'),  &
                                      here(line_at(doc, 'amplitude['//itoa(i)//'].name')), errors)
      call builder_amplitude_set_type(b, ab, amplitude_code(text_at(doc,                     &
                                      'amplitude['//itoa(i)//'].type')),                     &
                                      here(line_at(doc, 'amplitude['//itoa(i)//'].type')), errors)
      do j = 1, int(int_at(doc, 'amplitude['//itoa(i)//'].points.count'))
        call opt_set(pt%time,  real_at(doc, 'amplitude['//itoa(i)//'].points['//itoa(j)//'][1]'))
        call opt_set(pt%value, real_at(doc, 'amplitude['//itoa(i)//'].points['//itoa(j)//'][2]'))
        call builder_amplitude_add_point(b, ab, pt, here(0_int32), errors)
        if (builder_failed(b)) return
      end do
      call builder_amplitude_finish(b, ab, amp, here(0_int32), errors, ok)
      if (.not. ok) return
      call builder_add_amplitude(b, amp, here(0_int32), errors)
      if (builder_failed(b)) return
    end do

    ! --- what this build can actually execute -------------------------------------
    ! The contract admits a sequence of steps and a list of load objects per step
    ! (authoring-contract section 2.1 / 8.3); the executable slice is narrower, and the
    ! refusal lives HERE rather than in the validator because it is a statement about
    ! this binary, not about the input language. Silently running step 1 and ignoring
    ! step 2 is the failure mode this exists to prevent.
    call executable_shape(doc, errors)
    if (errors%count() > mark0) return

    ! --- the named faces, flattened -------------------------------------------------
    ! Declaration order IS legacy's edge numbering, which is what makes a named face
    ! exactly one contiguous begin_edge..end_edge range (authoring-contract section 8.1).
    ! Nothing here computes: the element on each row is the author's, because it is
    ! legacy's (Load.f90 writes it down too).
    n = 0
    do i = 1, int(doc%count_of('surface'))
      n = n + int(int_at(doc, 'surface['//itoa(i)//'].edges.count'))
    end do
    if (n == 0) then
      call builder_surface_edges_empty(b, here(0_int32), errors)
    else
      do i = 1, int(doc%count_of('surface'))
        do ie = 1, int(int_at(doc, 'surface['//itoa(i)//'].edges.count'))
          lp = 'surface['//itoa(i)//'].edges['//itoa(ie)//']'
          call default_surface_edge(sedge)
          if (allocated(sedge%nodes)) deallocate (sedge%nodes)
          allocate (sedge%nodes(2))
          sedge%nodes(1) = int_at(doc, trim(lp)//'[1]')
          sedge%nodes(2) = int_at(doc, trim(lp)//'[2]')
          call opt_set(sedge%element, int_at(doc, trim(lp)//'[3]'))
          ! `index` and `vdimn` are fixed by `kind`: "edge2" is legacy's 2-node edge on
          ! element class 1 with no flattened coordinate. The whitelist admits one kind,
          ! so this is the encoding of that one choice, not a hidden default.
          call opt_set(sedge%element_class, 1_int32)
          call opt_set(sedge%projection_axis, 0_int32)
          call builder_add_surface_edge(b, sedge, here(line_at(doc, trim(lp)//'[1]')), errors)
          if (builder_failed(b)) return
        end do
      end do
    end if

    ! --- the steps ------------------------------------------------------------------
    ! One `[[step]]` is one legacy BLOCK (authoring-contract section 2.1: legacy nblks =
    ! count(step)). Everything in this loop used to read `step[1]` because the whitelist
    ! admitted exactly one; the loop is the whole difference.
    do st = 1, int(doc%count_of('step'))
        ! --- the single step ----------------------------------------------------------
        call builder_step_begin(sb)
        call builder_step_set_procedure(b, sb, procedure_code(text_at(doc, 'step['//itoa(st)//'].procedure')), &
                                        here(line_at(doc, 'step['//itoa(st)//'].procedure')), errors)
        call builder_step_set_load_mode(b, sb, load_mode_code(text_at(doc, 'step['//itoa(st)//'].load_mode')), &
                                        here(line_at(doc, 'step['//itoa(st)//'].load_mode')), errors)
        if (builder_failed(b)) return

        call default_controls(ctrl)
        call opt_set(ctrl%increments,      int_at(doc, 'step['//itoa(st)//'].controls.increments'))
        call opt_set(ctrl%max_iterations,  int_at(doc, 'step['//itoa(st)//'].controls.max_iterations'))
        call opt_set(ctrl%nonlinear_type,                                                         &
             stiffness_update_code(text_at(doc, 'step['//itoa(st)//'].controls.stiffness_update')))
        call opt_set(ctrl%substeps,       int_at(doc, 'step['//itoa(st)//'].controls.substeps'))
        call opt_set(ctrl%time_increment, real_at(doc, 'step['//itoa(st)//'].controls.time_increment'))
        call opt_set(ctrl%tolerance_force, real_at(doc, 'step['//itoa(st)//'].controls.tolerance_force'))
        ! tolerance_dof is one value PER DEGREE OF FREEDOM and gravity%amplitude one id PER
        ! SECTION: legacy stores both as arrays, and the contract lets the author write one
        ! number because "the same tolerance everywhere" is what they mean. The fan-out is
        ! here, where the counts are known, not in the input.
        if (allocated(ctrl%tolerance_dof)) deallocate (ctrl%tolerance_dof)
        allocate (ctrl%tolerance_dof(int(int_at(doc, 'mesh.dimension'))))
        ctrl%tolerance_dof = real_at(doc, 'step['//itoa(st)//'].controls.tolerance_dof')
        call builder_step_set_controls(b, sb, ctrl, here(line_at(doc, 'step['//itoa(st)//'].controls.increments')), errors)
        if (builder_failed(b)) return

        call default_load(ld)
        call opt_set(ld%gravity%recompute_every, 1_int32)
        ! 0 unless the author named a curve: legacy's own "no strength reduction". The
        ! validator has already refused a curve that names nothing, and a name on a plain
        ! gravity run.
        call opt_set(ld%strength_reduction,                                                       &
             int(amplitude_index(doc, text_at(doc, 'step['//itoa(st)//'].strength_reduction.amplitude')),      &
                 int32))
        ! The load array is the author's shape; ProblemState still holds ONE gravity object,
        ! so the one gravity load is located by type. `executable_shape` has already refused
        ! anything this cannot carry -- a second gravity load, or a pressure load.
        gp = load_of_type(doc, int(st, int32), 'gravity')
        call opt_set(ld%gravity%magnitude, real_at(doc, trim(gp)//'.magnitude'))
        if (allocated(ld%gravity%amplitude)) deallocate (ld%gravity%amplitude)
        allocate (ld%gravity%amplitude(int(doc%count_of('section'))))
        ld%gravity%amplitude = int(amplitude_index(doc,                                           &
                                   text_at(doc, trim(gp)//'.amplitude')), int32)
        if (allocated(ld%gravity%direction)) deallocate (ld%gravity%direction)
        allocate (ld%gravity%direction(2))
        ld%gravity%direction(1) = real_at(doc, trim(gp)//'.direction[1]')
        ld%gravity%direction(2) = real_at(doc, trim(gp)//'.direction[2]')
        ! The pressure loads of this step, in declaration order. Each names a face; the
        ! face's edges are one contiguous range of the flattened table, and the range is
        ! what legacy's edge-load card carries.
        n = 0
        do i = 1, int(doc%count_of('step['//itoa(st)//'].load'))
          if (text_at(doc, 'step['//itoa(st)//'].load['//itoa(i)//'].type') == 'pressure') n = n + 1
        end do
        if (allocated(prs)) deallocate (prs)
        allocate (prs(n))
        ip = 0
        do i = 1, int(doc%count_of('step['//itoa(st)//'].load'))
          lp = 'step['//itoa(st)//'].load['//itoa(i)//']'
          if (text_at(doc, trim(lp)//'.type') /= 'pressure') cycle
          ip = ip + 1
          call surface_range(doc, text_at(doc, trim(lp)//'.surface'), e1, e2)
          call opt_set(prs(ip)%first_edge, int(e1, int32))
          call opt_set(prs(ip)%last_edge, int(e2, int32))
          call opt_set(prs(ip)%amplitude,                                                          &
               int(amplitude_index(doc, text_at(doc, trim(lp)//'.amplitude')), int32))
          ! legacy `water`: the axis, with the sign saying which way the head deepens.
          ! The whitelist admits "y" measured downward from at[1], i.e. +2.
          call opt_set(prs(ip)%distribution_axis, 2_int32)
          if (allocated(prs(ip)%at)) deallocate (prs(ip)%at)
          if (allocated(prs(ip)%value)) deallocate (prs(ip)%value)
          allocate (prs(ip)%at(2), prs(ip)%value(2))
          prs(ip)%at(1) = real_at(doc, trim(lp)//'.distribution.at[1]')
          prs(ip)%at(2) = real_at(doc, trim(lp)//'.distribution.at[2]')
          prs(ip)%value(1) = real_at(doc, trim(lp)//'.distribution.value[1]')
          prs(ip)%value(2) = real_at(doc, trim(lp)//'.distribution.value[2]')
          call opt_set(prs(ip)%scale, real_at(doc, trim(lp)//'.distribution.scale'))
        end do
        if (allocated(ld%pressure)) deallocate (ld%pressure)
        call move_alloc(prs, ld%pressure)

        ! The concentrated forces of this step, in declaration order -- which is the order
        ! legacy reads its point-load groups. The node list comes from the named nset, so
        ! the author never writes node numbers into a load.
        n = 0
        do i = 1, int(doc%count_of('step['//itoa(st)//'].load'))
          if (text_at(doc, 'step['//itoa(st)//'].load['//itoa(i)//'].type') == 'concentrated') &
            n = n + 1
        end do
        if (allocated(cfs)) deallocate (cfs)
        allocate (cfs(n))
        ip = 0
        do i = 1, int(doc%count_of('step['//itoa(st)//'].load'))
          lp = 'step['//itoa(st)//'].load['//itoa(i)//']'
          if (text_at(doc, trim(lp)//'.type') /= 'concentrated') cycle
          ip = ip + 1
          call opt_set(cfs(ip)%amplitude,                                                     &
               int(amplitude_index(doc, text_at(doc, trim(lp)//'.amplitude')), int32))
          if (allocated(cfs(ip)%value)) deallocate (cfs(ip)%value)
          allocate (cfs(ip)%value(2))
          cfs(ip)%value(1) = real_at(doc, trim(lp)//'.value[1]')
          cfs(ip)%value(2) = real_at(doc, trim(lp)//'.value[2]')
          iset = nset_index(doc, text_at(doc, trim(lp)//'.nset'))
          call int_list(doc, 'nset['//itoa(iset)//'].nodes', nodes)
          if (allocated(cfs(ip)%nodes)) deallocate (cfs(ip)%nodes)
          allocate (cfs(ip)%nodes(size(nodes)))
          cfs(ip)%nodes = nodes
        end do
        if (allocated(ld%concentrated)) deallocate (ld%concentrated)
        call move_alloc(cfs, ld%concentrated)

        call builder_step_set_load(b, sb, ld, here(line_at(doc, trim(gp)//'.magnitude')), errors)
        if (builder_failed(b)) return

        call default_output(outp)
        call set_stress_averaging(outp, int(doc%count_of('section')),                             &
                                  stress_averaging_code(text_at(doc, 'output.stress_averaging')))
        call apply_output_fields(doc, outp)
        call builder_step_set_output(b, sb, outp, here(line_at(doc, 'output.format')), errors)
        if (builder_failed(b)) return

        ! Boundary: one ProblemState entry per (set, dof, node) triple -- that is the solver's
        ! storage (prescrib%ifixset / %ifixvar / %nodfix), not the author's statement. The
        ! contract lets an author name a node set once and write `dof = [1, 2]` once, so both
        ! expansions happen here. dof is the outer loop because legacy's `.pre` groups one set
        ! per constrained direction, and that grouping is what the frozen reference records.
        ! boundary_t's component names read backwards against this: %name carries the set
        ! ordinal, %nset carries the node number (see yl_runtime_commit.f90:1052-1061).
        do i = 1, int(doc%count_of('step['//itoa(st)//'].boundary'))
          call int_list(doc, 'step['//itoa(st)//'].boundary['//itoa(i)//'].dof', ids)
          iset = nset_index(doc, text_at(doc, 'step['//itoa(st)//'].boundary['//itoa(i)//'].nset'))
          call int_list(doc, 'nset['//itoa(iset)//'].nodes', nodes)
          do j = 1, size(ids)
            do k = 1, size(nodes)
              call default_boundary(bnd)
              call opt_set(bnd%name, int(iset, int32))
              call opt_set(bnd%nset, nodes(k))
              call opt_set(bnd%dof, ids(j))
              call opt_set(bnd%value, real_at(doc, 'step['//itoa(st)//'].boundary['//itoa(i)//'].value'))
              call builder_step_add_boundary(b, sb, bnd,                                          &
                   here(line_at(doc, 'step['//itoa(st)//'].boundary['//itoa(i)//'].nset')), errors)
              if (builder_failed(b)) return
            end do
          end do
        end do

        ! Activation: one entry per SECTION (= legacy element group), carrying whether
        ! this step contains it and which material it uses. `active_elsets` is the
        ! author's statement; this is its expansion into legacy's (group, block) matrix,
        ! which is a table lookup and not a derivation.
        do i = 1, int(doc%count_of('section'))
          call default_activation(act, int(material_index(doc,                                    &
               text_at(doc, 'section['//itoa(i)//'].material')), int32))
          call opt_set(act%active, merge(1_int32, 0_int32,                                        &
               elset_is_active(doc, st, text_at(doc, 'section['//itoa(i)//'].elset'))))
          call builder_step_add_activation(b, sb, act, here(0_int32), errors)
          if (builder_failed(b)) return
        end do

        call builder_step_finish(b, sb, step_val, here(0_int32), errors, ok)
        if (.not. ok) return
        call builder_add_step(b, step_val, here(0_int32), errors)
        if (builder_failed(b)) return
    end do


    ! --- solver -------------------------------------------------------------------
    call default_solver(sol)
    call opt_set(sol%linear, solver_code(text_at(doc, 'solver.linear')))
    call builder_set_solver(b, sol, here(line_at(doc, 'solver.linear')), errors)
    if (builder_failed(b)) return

    if (errors%count() > mark0) return
    call builder_finish(b, draft, errors, ok)
    if (.not. ok .or. .not. allocated(draft)) return
    call prepare_problem(draft, PROFILE_TAG, problem, manifest, errors)
  end subroutine authoring_build_problem

  ! ------------------------------------------------------------------ context ----

  !> `.ele` carries a group column; the parsers need the per-section RECORD COUNT because
  !> legacy attributes elements positionally. One counting pass, no value kept.
  subroutine fill_context(doc, prefix, ctx, errors)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: prefix
    type(deck_context_t), intent(inout) :: ctx
    type(problem_errors_t), intent(inout) :: errors
    integer :: u, ios, i, g, nsec, nn
    integer(int32) :: id
    integer(int32), allocatable :: nodes(:), counts(:)

    nsec = int(doc%count_of('section'))
    ctx%filled = .true.
    ctx%ndimn = int_at(doc, 'mesh.dimension')
    ctx%ngroup = int(nsec, int32)
    ctx%nnode = nodes_per_element(text_at(doc, 'section[1].element'))
    ctx%element_kind = element_kind_of(text_at(doc, 'section[1].element'))
    ctx%type_abc = 'FIX'
    ctx%nbackdt = 0_int32
    nn = int(ctx%nnode)

    ! Element-to-section membership is POSITIONAL, which is legacy's own rule: read_element
    ! walks the file group by group, taking nelgroup elements for each. Some `.ele` files
    ! carry a trailing group column and some do not (lame_cylinder does, mini_mc does not),
    ! and legacy ignores it either way -- so the modern path cannot read membership out of
    ! the mesh file. The author states it, one count per element set, and this routine only
    ! checks that the counts add up to the file.
    ! Indexed by SECTION, not by elset ordinal: a section names its elset, and the two
    ! collections are not required to be in the same order.
    allocate (counts(max(nsec, 1)))
    counts = 0_int32
    do i = 1, nsec
      g = int(collection_index(doc, 'elset', text_at(doc, 'section['//itoa(i)//'].elset')), int32)
      if (g == 0_int32) return        ! a dangling elset reference is the validator's finding
      counts(i) = int_at(doc, 'elset['//itoa(int(g))//'].element_count')
    end do

    allocate (nodes(nn))
    open (newunit=u, file=prefix//'.ele', status='old', action='read', iostat=ios)
    if (ios /= 0) then
      call fail(errors, 'mesh.file', 'cannot open '//prefix//'.ele')
      return
    end if
    g = 0_int32
    do
      read (u, *, iostat=ios) id, nodes(1:nn)
      if (ios /= 0) exit
      g = g + 1_int32
    end do
    close (u)

    if (g /= sum(counts(1:nsec))) then
      call fail(errors, 'elset[].element_count',                                              &
                'the element counts add up to '//itoa(int(sum(counts(1:nsec))))//             &
                ' but '//prefix//'.ele holds '//itoa(int(g))//' elements')
      return
    end if

    if (allocated(ctx%nelgroup)) deallocate (ctx%nelgroup)
    if (allocated(ctx%group_matno)) deallocate (ctx%group_matno)
    if (allocated(ctx%group_kind)) deallocate (ctx%group_kind)
    allocate (ctx%nelgroup(nsec), ctx%group_matno(nsec), ctx%group_kind(nsec))
    do i = 1, nsec
      ctx%nelgroup(i) = counts(i)
      ctx%group_matno(i) = int(material_index(doc,                                            &
                               text_at(doc, 'section['//itoa(i)//'].material')), int32)
      ctx%group_kind(i) = element_kind_of(text_at(doc, 'section['//itoa(i)//'].element'))
      if (counts(i) == 0_int32) then
        call fail(errors, 'section['//itoa(i)//'].elset',                                     &
                  'the mesh file has no element in this section''s group')
      end if
    end do
  end subroutine fill_context

  ! ------------------------------------------------------------------ lookups ----

  pure function text_at(doc, path) result(v)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: path
    character(len=:), allocatable :: v
    integer(int32) :: k
    k = doc%find(path)
    if (k == 0_int32) then
      v = ''
    else
      v = trim(doc%entry(k)%svalue)
    end if
  end function text_at

  pure integer(int32) function int_at(doc, path) result(v)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: path
    integer(int32) :: k
    k = doc%find(path)
    v = 0_int32
    if (k /= 0_int32) v = doc%entry(k)%ivalue
  end function int_at

  pure real(real64) function real_at(doc, path) result(v)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: path
    integer(int32) :: k
    k = doc%find(path)
    v = 0.0_real64
    if (k /= 0_int32) v = doc%entry(k)%rvalue
  end function real_at

  pure integer(int32) function line_at(doc, path) result(v)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: path
    integer(int32) :: k
    k = doc%find(path)
    v = 0_int32
    if (k /= 0_int32) v = doc%entry(k)%line
  end function line_at

  subroutine int_list(doc, base, out)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: base
    integer(int32), allocatable, intent(out) :: out(:)
    integer(int32) :: n, i
    n = int_at(doc, base//'.count')
    allocate (out(max(int(n), 0)))
    do i = 1_int32, n
      out(i) = int_at(doc, base//'['//itoa(int(i))//']')
    end do
  end subroutine int_list

  !> 1-based position of a named entry in a collection, or 0. Names are the contract's
  !> only reference mechanism; the integer never appears in the input.
  pure integer function collection_index(doc, collection, want) result(k)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: collection, want
    integer(int32) :: n, a, e
    k = 0
    n = doc%count_of(collection)
    do a = 1_int32, n
      e = doc%find(trim(collection)//'['//itoa(int(a))//'].name')
      if (e == 0_int32) cycle
      if (trim(doc%entry(e)%svalue) == trim(want)) then
        k = int(a)
        return
      end if
    end do
  end function collection_index

  pure integer function material_index(doc, want) result(k)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: want
    k = collection_index(doc, 'material', want)
  end function material_index

  pure integer function nset_index(doc, want) result(k)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: want
    k = collection_index(doc, 'nset', want)
  end function nset_index

  pure integer function amplitude_index(doc, want) result(k)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: want
    k = collection_index(doc, 'amplitude', want)
  end function amplitude_index

  subroutine apply_output_fields(doc, outp)
    type(toml_doc_t), intent(in) :: doc
    type(output_t), intent(inout) :: outp
    integer(int32) :: n, i, k
    n = int_at(doc, 'output.field.count')
    do i = 1_int32, n
      k = doc%find('output.field['//itoa(int(i))//']')
      if (k == 0_int32) cycle
      call enable_output_field(outp, trim(doc%entry(k)%svalue))
    end do
  end subroutine apply_output_fields

  ! ------------------------------------------------------------------ helpers ----

  function here(line) result(loc)
    integer(int32), intent(in) :: line
    type(source_location_t) :: loc
    loc = make_source_location(file=trim(site_file), reader='authoring', line=line)
  end function here

  !> Refuse the shapes the contract can describe and this build cannot run.
  subroutine executable_shape(doc, errors)
    type(toml_doc_t), intent(in) :: doc
    type(problem_errors_t), intent(inout) :: errors
    integer(int32) :: a, b_, ngrav, npres, k

    if (doc%count_of('step') < 1_int32) then
      call refuse(errors, 'step', 'an analysis needs at least one step', '0', 'one or more')
      return
    end if
    npres = 0_int32
    do a = 1_int32, doc%count_of('step')
      do b_ = 1_int32, doc%count_of('step['//itoa(int(a))//'].load')
        k = doc%find('step['//itoa(int(a))//'].load['//itoa(int(b_))//'].type')
        if (k == 0_int32) cycle
        if (trim(doc%entry(k)%svalue) == 'pressure') npres = npres + 1_int32
      end do
    end do
    ! One gravity object per step, still: ProblemState holds ONE gravity record per step
    ! (legacy's gravy / factg / tcurvegravity), so two of them cannot both be carried.
    ! Counted per step rather than over the whole file -- the old count was a file-wide
    ! sum that happened to equal the per-step count while only one step was allowed.
    do a = 1_int32, doc%count_of('step')
      ngrav = 0_int32
      do b_ = 1_int32, doc%count_of('step['//itoa(int(a))//'].load')
        k = doc%find('step['//itoa(int(a))//'].load['//itoa(int(b_))//'].type')
        if (k == 0_int32) cycle
        if (trim(doc%entry(k)%svalue) == 'gravity') ngrav = ngrav + 1_int32
      end do
      if (ngrav /= 1_int32) then
        call refuse(errors, 'step['//itoa(int(a))//'].load',                                   &
                    'this build carries exactly one gravity load per step',                    &
                    itoa(int(ngrav)), '1')
        return
      end if
    end do
    if (npres > 0_int32 .and. doc%count_of('surface') == 0_int32) then
      call refuse(errors, 'step[].load', 'a pressure load names a face and this file '//      &
                  'declares none', '0', 'at least one [[surface]]')
    end if
  end subroutine executable_shape

  !> The path of the `which`-typed load in step `st`, or the first load if none matches --
  !> `executable_shape` has already refused the latter case.
  function load_of_type(doc, st, which) result(path)
    type(toml_doc_t), intent(in) :: doc
    integer(int32), intent(in) :: st
    character(len=*), intent(in) :: which
    character(len=TOML_LEN_PATH) :: path
    integer(int32) :: b, k
    path = 'step['//itoa(int(st))//'].load[1]'
    do b = 1_int32, doc%count_of('step['//itoa(int(st))//'].load')
      k = doc%find('step['//itoa(int(st))//'].load['//itoa(int(b))//'].type')
      if (k == 0_int32) cycle
      if (trim(doc%entry(k)%svalue) == trim(which)) then
        path = 'step['//itoa(int(st))//'].load['//itoa(int(b))//']'
        return
      end if
    end do
  end function load_of_type

  subroutine refuse(errors, path, msg, actual, expected)
    type(problem_errors_t), intent(inout) :: errors
    character(len=*), intent(in) :: path, msg, actual, expected
    call errors%add(make_problem_error(code=PE_UNSUPPORTED, stage='authoring',                &
         object_path=path, message=msg, actual=actual, expected=expected,                     &
         exit_class=PE_EXIT_UNSUPPORTED,                                                      &
         source=make_source_location(file=trim(site_file), reader='authoring')))
  end subroutine refuse

  !> Is this elset part of the model in step `st`? A membership test over the author's
  !> own list, nothing more. A name that matches no elset is the validator's finding.
  logical function elset_is_active(doc, st, name) result(active)
    type(toml_doc_t), intent(in) :: doc
    integer, intent(in) :: st
    character(len=*), intent(in) :: name
    integer :: i, n
    active = .false.
    n = int(int_at(doc, 'step['//itoa(st)//'].active_elsets.count'))
    do i = 1, n
      if (text_at(doc, 'step['//itoa(st)//'].active_elsets['//itoa(i)//']') == trim(name)) then
        active = .true.
        return
      end if
    end do
  end function elset_is_active

  !> The edge range a named face occupies in the flattened table. Declaration order is
  !> the numbering, so this is a running count, not a search over geometry.
  subroutine surface_range(doc, name, first, last)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: name
    integer, intent(out) :: first, last
    integer :: i, n, at
    at = 0
    first = 0
    last = -1
    do i = 1, int(doc%count_of('surface'))
      n = int(int_at(doc, 'surface['//itoa(i)//'].edges.count'))
      if (text_at(doc, 'surface['//itoa(i)//'].name') == trim(name)) then
        first = at + 1
        last = at + n
        return
      end if
      at = at + n
    end do
  end subroutine surface_range

  subroutine fail(errors, path, msg)
    type(problem_errors_t), intent(inout) :: errors
    character(len=*), intent(in) :: path, msg
    call errors%add(make_problem_error(code=PE_INVALID_INPUT, stage='authoring',              &
         object_path=path, message=msg, exit_class=PE_EXIT_INPUT,                             &
         source=make_source_location(file=trim(site_file), reader='authoring')))
  end subroutine fail

  pure function itoa(v) result(out)
    integer, intent(in) :: v
    character(len=12) :: buf
    character(len=:), allocatable :: out
    write (buf, '(i0)') v
    out = trim(buf)
  end function itoa

end module yl_authoring_map
