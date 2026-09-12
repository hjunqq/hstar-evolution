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
                              activation_t, nset_t
  use yl_problem_errors, only: problem_errors_t, problem_error_t, source_location_t,        &
                               make_problem_error, make_source_location,                     &
                               PE_INVALID_INPUT, PE_EXIT_INPUT
  use yl_problem_manifest, only: manifest_t
  use yl_problem_builder, only: problem_builder_t, step_builder_t, amplitude_builder_t,      &
                                builder_begin, builder_finish, builder_failed,               &
                                builder_set_case, builder_set_mesh_dimension,                &
                                builder_set_interactions, builder_set_solver,                &
                                builder_add_material, builder_add_section,                   &
                                builder_add_nset, builder_nsets_empty,                       &
                                builder_add_amplitude, builder_add_step,                     &
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

  character(len=*), parameter :: SITE = 'case.toml'

  public :: authoring_build_problem

contains

  !> `doc` (already validated) + the mesh files beside it -> a ProblemState.
  !> Transactional in the same sense as `adapt_legacy_deck`: on any finding, `problem` and
  !> `manifest` are left exactly as the caller passed them.
  subroutine authoring_build_problem(doc, dir, problem, manifest, errors)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: dir
    type(problem_state_t), allocatable, intent(inout) :: problem
    type(manifest_t), allocatable, intent(inout) :: manifest
    type(problem_errors_t), intent(inout) :: errors

    type(problem_builder_t) :: b
    type(step_builder_t) :: sb
    type(amplitude_builder_t) :: ab
    type(deck_context_t) :: ctx
    type(problem_state_t), allocatable :: draft
    integer :: mark0, u_cor, u_ele, ios, i, j, n
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
    integer(int32), allocatable :: ids(:)

    mark0 = errors%count()
    call builder_begin(b)
    call deck_context_reset(ctx)

    prefix = trim(dir)//'/'//text_at(doc, 'mesh.file')

    call opt_set(cs%name, text_at(doc, 'case.name'))
    ! units is @m5-only: no legacy record carries it, and ADR-0003 makes the explicit
    ! SI declaration mandatory. The modern path is the first one that can fill it.
    call opt_set(cs%units, text_at(doc, 'case.units'))
    call builder_set_case(b, cs, here(line_at(doc, 'case.name')), errors)
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
      call opt_set(mat%name, legacy_material_name(text_at(doc, 'material['//itoa(i)//'].model')))
      call opt_set(mat%density, real_at(doc, 'material['//itoa(i)//'].density'))
      call opt_set(mat%e, real_at(doc, 'material['//itoa(i)//'].E'))
      call opt_set(mat%nu, real_at(doc, 'material['//itoa(i)//'].nu'))
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

    ! --- the single step ----------------------------------------------------------
    call builder_step_begin(sb)
    call builder_step_set_procedure(b, sb, procedure_code(text_at(doc, 'step[1].procedure')), &
                                    here(line_at(doc, 'step[1].procedure')), errors)
    call builder_step_set_load_mode(b, sb, default_load_mode(), here(0_int32), errors)
    if (builder_failed(b)) return

    call default_controls(ctrl)
    call opt_set(ctrl%increments,      int_at(doc, 'step[1].controls.increments'))
    call opt_set(ctrl%max_iterations,  int_at(doc, 'step[1].controls.max_iterations'))
    call opt_set(ctrl%tolerance_force, real_at(doc, 'step[1].controls.tolerance_force'))
    ! tolerance_dof is one value PER DEGREE OF FREEDOM and gravity%amplitude one id PER
    ! SECTION: legacy stores both as arrays, and the contract lets the author write one
    ! number because "the same tolerance everywhere" is what they mean. The fan-out is
    ! here, where the counts are known, not in the input.
    if (allocated(ctrl%tolerance_dof)) deallocate (ctrl%tolerance_dof)
    allocate (ctrl%tolerance_dof(int(int_at(doc, 'mesh.dimension'))))
    ctrl%tolerance_dof = real_at(doc, 'step[1].controls.tolerance_dof')
    call builder_step_set_controls(b, sb, ctrl, here(line_at(doc, 'step[1].controls.increments')), errors)
    if (builder_failed(b)) return

    call default_load(ld)
    call opt_set(ld%gravity%enabled, 1_int32)
    call opt_set(ld%gravity%magnitude, real_at(doc, 'step[1].load.gravity.magnitude'))
    if (allocated(ld%gravity%amplitude)) deallocate (ld%gravity%amplitude)
    allocate (ld%gravity%amplitude(int(doc%count_of('section'))))
    ld%gravity%amplitude = int(amplitude_index(doc,                                           &
                               text_at(doc, 'step[1].load.gravity.amplitude')), int32)
    if (allocated(ld%gravity%direction)) deallocate (ld%gravity%direction)
    allocate (ld%gravity%direction(2))
    ld%gravity%direction(1) = real_at(doc, 'step[1].load.gravity.direction[1]')
    ld%gravity%direction(2) = real_at(doc, 'step[1].load.gravity.direction[2]')
    call builder_step_set_load(b, sb, ld, here(line_at(doc, 'step[1].load.gravity.magnitude')), errors)
    if (builder_failed(b)) return

    call default_output(outp)
    call set_stress_averaging(outp, int(doc%count_of('section')))
    call apply_output_fields(doc, outp)
    call builder_step_set_output(b, sb, outp, here(line_at(doc, 'output.format')), errors)
    if (builder_failed(b)) return

    ! Boundary: one ProblemState entry per (nset, dof) pair. legacy's `.pre` has one set per
    ! constrained direction, and the contract lets an author write `dof = [1, 2]` once --
    ! the expansion is here, not in the input, because "which directions are fixed" is the
    ! author's statement and "one record per direction" is the solver's storage.
    do i = 1, int(doc%count_of('step[1].boundary'))
      call int_list(doc, 'step[1].boundary['//itoa(i)//'].dof', ids)
      do j = 1, size(ids)
        call default_boundary(bnd)
        call opt_set(bnd%nset, int(nset_index(doc,                                            &
             text_at(doc, 'step[1].boundary['//itoa(i)//'].nset')), int32))
        call opt_set(bnd%name, int(nset_index(doc,                                            &
             text_at(doc, 'step[1].boundary['//itoa(i)//'].nset')), int32))
        call opt_set(bnd%dof, ids(j))
        call opt_set(bnd%value, real_at(doc, 'step[1].boundary['//itoa(i)//'].value'))
        call builder_step_add_boundary(b, sb, bnd,                                            &
             here(line_at(doc, 'step[1].boundary['//itoa(i)//'].nset')), errors)
        if (builder_failed(b)) return
      end do
    end do

    ! Activation: every section active. Construction staging is not on the whitelist, so
    ! this is a default with a reason, not a modelling decision left implicit.
    do i = 1, int(doc%count_of('section'))
      call default_activation(act, int(material_index(doc,                                    &
           text_at(doc, 'section['//itoa(i)//'].material')), int32))
      call builder_step_add_activation(b, sb, act, here(0_int32), errors)
      if (builder_failed(b)) return
    end do

    call builder_step_finish(b, sb, step_val, here(0_int32), errors, ok)
    if (.not. ok) return
    call builder_add_step(b, step_val, here(0_int32), errors)
    if (builder_failed(b)) return

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

    allocate (counts(max(nsec, 1)))
    counts = 0_int32
    allocate (nodes(nn))
    open (newunit=u, file=prefix//'.ele', status='old', action='read', iostat=ios)
    if (ios /= 0) then
      call fail(errors, 'mesh.file', 'cannot open '//prefix//'.ele to count sections')
      return
    end if
    do
      read (u, *, iostat=ios) id, nodes(1:nn), g
      if (ios /= 0) exit
      if (g >= 1 .and. g <= nsec) counts(g) = counts(g) + 1_int32
    end do
    close (u)

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

  pure function here(line) result(loc)
    integer(int32), intent(in) :: line
    type(source_location_t) :: loc
    loc = make_source_location(file=SITE, reader='authoring', line=line)
  end function here

  subroutine fail(errors, path, msg)
    type(problem_errors_t), intent(inout) :: errors
    character(len=*), intent(in) :: path, msg
    call errors%add(make_problem_error(code=PE_INVALID_INPUT, stage='authoring',              &
         object_path=path, message=msg, exit_class=PE_EXIT_INPUT,                             &
         source=make_source_location(file=SITE, reader='authoring')))
  end subroutine fail

  pure function itoa(v) result(out)
    integer, intent(in) :: v
    character(len=12) :: buf
    character(len=:), allocatable :: out
    write (buf, '(i0)') v
    out = trim(buf)
  end function itoa

end module yl_authoring_map
