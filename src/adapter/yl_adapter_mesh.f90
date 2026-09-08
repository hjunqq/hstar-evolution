! yl_adapter_mesh -- M4-01 legacy adapter: .cor (node coordinates) and .ele (element
! connectivity), per docs/m4/adapter-contract.md §2.
!
! Scope
!   Exactly the two reader-inventory sites whose `file` is .cor or .ele:
!     COR.global_data.node_coordinates      (Global.f90:1176)
!     ELE.read_element.element_connectivity (Elements.f90:1087)
!   and nothing else. This module does not open/close/rewind `unit` (its lifecycle
!   is L2-a's, adapter-contract.md §2), does not touch a legacy global, and writes
!   the draft only through yl_problem_builder.
!
! deck_context_t (adapter-contract.md §2.2)
!   Neither routine can size a read from .cor/.ele alone: how many coordinates a
!   node carries (ndimn) and how many node ids an element carries (nnode) are
!   established by the *.glb* group header BEFORE .cor/.ele are ever opened
!   (Global.f90:694 for ndimn, :1216/:1225 for the element kind that fixes nnode).
!   An earlier revision of this module hardcoded both as parameters (NDIMN=2,
!   NNODE_Q4=4); that was flagged and fixed once yl_adapter_parts.f90 landed
!   deck_context_t. `ctx` is filled by parse_glb and is READ-ONLY here; `ctx%filled`
!   is checked first in both routines because a caller invoking either before
!   parse_glb has run is this module's OWN invariant broken, not a statement about
!   the user's deck (PE_INTERNAL, not PE_UNSUPPORTED or PE_INVALID_INPUT).
!
!   Sizing every read from `ctx%ndimn` / `ctx%nnode` removes the MISPARSE risk the
!   old hardcode carried (a 3D or non-Q4 deck no longer desyncs the cursor merely by
!   being read). What is left is a WHITELIST question -- is this build allowed to
!   run a 3D deck or a non-Q4 element at all -- and that is answered two ways here:
!   element_kind is rejected immediately (PE_UNSUPPORTED, next paragraph) because
!   Q4 is the only element shape this parser was ever asked to support and there is
!   nothing to gain by deferring that to a later stage; dimension is left to the
!   capability gate's existing G2 row (analysis.dimension, yl_problem_profile.f90),
!   which already owns mesh.dimension end to end once the .glb parser sets it via
!   builder_set_mesh_dimension -- duplicating that check here would just be a
!   second, easier-to-drift copy of the same number.
!
! Node and element ids are DATA, not array indices
!   ProblemState.mesh.nodes[] / .elements[] are kept in AUTHORING order and `id` is
!   a field of each entry (yl_problem_types.f90). This parser never assumes ids are
!   dense, start at 1, or match the record's position -- M3-03 had to learn that the
!   hard way (task brief). It stores whatever `i0` a record carries, in the order
!   the records arrive. Duplicate ids across a collection are already a validate-
!   stage rule (rule V6, PE_DUPLICATE_REF, yl_problem_pipeline.f90) and are
!   deliberately NOT re-checked here: this parser only rejects what validate cannot
!   see, namely a record it cannot make sense of at all.
!
! End of file
!   Neither .cor nor .ele carries its own record count; legacy gets npoin/nelem from
!   .glb (Global.f90:694, :1229) and loops that many times. deck_context_t carries
!   ndimn/nnode but deliberately not npoin/nelem/nelgroup (those size COLLECTIONS,
!   not a single record, and are outside what makes a .cor/.ele record misparse), so
!   each routine reads until IOSTAT_END. For a well-formed deck this is equivalent;
!   verified against both golden decks (cooks_membrane: 289 nodes/256 elements;
!   lame_cylinder: 81 nodes/64 elements -- matching reader-inventory hit counts).
module yl_adapter_mesh

  use iso_fortran_env, only: int32, real64, iostat_end
  use yl_problem_optional, only: opt_set
  use yl_problem_types, only: node_t, element_t
  use yl_problem_builder, only: problem_builder_t, builder_add_node, builder_nodes_empty, &
                                 builder_add_element, builder_elements_empty, builder_failed
  use yl_problem_errors, only: problem_errors_t, source_location_t, make_source_location, &
                                make_problem_error, PE_INVALID_INPUT, PE_UNSUPPORTED, PE_INTERNAL
  use yl_problem_profile, only: capability_expect_int
  use yl_adapter_parts, only: deck_context_t

  implicit none
  private

  public :: parse_cor, parse_ele

  ! L2-b has not yet landed PE_STAGE_ADAPT (adapter-contract.md §4). This literal is
  ! this module's best guess at that constant's eventual value, spelled the same way
  ! as the four stage names already in yl_problem_errors.f90 ('normalize', 'validate',
  ! 'capability', 'finalize'). Replace with PE_STAGE_ADAPT once L2-b adds it.
  character(len=*), parameter :: STAGE_ADAPT = 'adapt'

contains

  ! RD: COR.global_data.node_coordinates (Global.f90:1176)
  ! One record per node: `i0, coord(1:ndimn,ipoin)`. Legacy loops ipoin=1..npoin with
  ! npoin from the .glb header; this parser has neither that count nor the unit's
  ! open/rewind lifecycle (module header), so it reads until end of file.
  subroutine parse_cor(unit, ctx, b, errors)
    integer, intent(in) :: unit
    type(deck_context_t), intent(in) :: ctx
    type(problem_builder_t), intent(inout) :: b
    type(problem_errors_t), intent(inout) :: errors

    integer(int32) :: i0, irec, ios
    real(real64), allocatable :: xyz(:)
    character(len=256) :: iomsg_buf
    type(node_t) :: node
    type(source_location_t) :: loc

    if (.not. ctx%filled) then
      loc = make_source_location(file='.cor', reader='global_data', line=1176_int32)
      call errors%add(make_problem_error(code=PE_INTERNAL, stage=STAGE_ADAPT, &
                      rule_id='A-COR/context-not-filled', object_path='mesh.nodes', &
                      message='parse_cor was called before parse_glb filled deck_context_t', &
                      source=loc))
      return
    end if

    if (.not. dimension_ok(errors, ctx%ndimn)) return

    allocate (xyz(ctx%ndimn))
    irec = 0_int32
    do
      read (unit, *, iostat=ios, iomsg=iomsg_buf) i0, xyz
      if (ios == iostat_end) exit
      irec = irec + 1_int32
      loc = make_source_location(file='.cor', reader='global_data', line=1176_int32, &
                                  record=irec)
      if (ios /= 0) then
        call errors%add(make_problem_error(code=PE_INVALID_INPUT, stage=STAGE_ADAPT, &
                        rule_id='A-COR/malformed-record', object_path='mesh.nodes', &
                        index=irec, &
                        message='malformed .cor record: '//trim(iomsg_buf), source=loc))
        return
      end if

      call opt_set(node%id, i0)
      if (allocated(node%xyz)) deallocate (node%xyz)
      allocate (node%xyz(ctx%ndimn))
      node%xyz = xyz

      call builder_add_node(b, node, loc, errors)
      if (builder_failed(b)) return
    end do

    ! Zero records read: an explicit empty collection, not "never mentioned" -- the
    ! .cor file was opened and read to its end, which is an authored statement in
    ! its own right (ADR-0002's three-state rule, yl_problem_builder.f90 header).
    if (irec == 0_int32) then
      loc = make_source_location(file='.cor', reader='global_data', line=1176_int32)
      call builder_nodes_empty(b, loc, errors)
    end if
  end subroutine parse_cor

  ! RD: ELE.read_element.element_connectivity (Elements.f90:1087)
  ! One record per element: `i0, lnods(1:nnode)`. Legacy loops ielem=1..nelem across
  ! all groups with nelem/nelgroup from .glb, invisible here for the reason the
  ! module header gives, so this parser also reads until end of file.
  !
  ! kind/material/elset are left UNSET on every element built here. All three are
  ! `derived_from` sections[] in docs/m2/state-field-map.toml (the .glb group
  ! header), never read from .ele itself -- filling them is whoever derives
  ! sections[] from .glb, not this parser (adapter-contract.md §2, "只通过
  ! yl_problem_builder 写 draft" does not mean guessing a field this file never
  ! carries).
  subroutine parse_ele(unit, ctx, b, errors)
    integer, intent(in) :: unit
    type(deck_context_t), intent(in) :: ctx
    type(problem_builder_t), intent(inout) :: b
    type(problem_errors_t), intent(inout) :: errors

    integer(int32) :: i0, irec, ios
    integer(int32), allocatable :: lnods(:)
    character(len=256) :: iomsg_buf
    type(element_t) :: element
    type(source_location_t) :: loc

    if (.not. ctx%filled) then
      loc = make_source_location(file='.ele', reader='read_element', line=1087_int32)
      call errors%add(make_problem_error(code=PE_INTERNAL, stage=STAGE_ADAPT, &
                      rule_id='A-ELE/context-not-filled', object_path='mesh.elements', &
                      message='parse_ele was called before parse_glb filled deck_context_t', &
                      source=loc))
      return
    end if

    if (.not. element_kind_ok(errors, ctx%element_kind)) return

    allocate (lnods(ctx%nnode))
    irec = 0_int32
    do
      read (unit, *, iostat=ios, iomsg=iomsg_buf) i0, lnods
      if (ios == iostat_end) exit
      irec = irec + 1_int32
      loc = make_source_location(file='.ele', reader='read_element', line=1087_int32, &
                                  record=irec)
      if (ios /= 0) then
        call errors%add(make_problem_error(code=PE_INVALID_INPUT, stage=STAGE_ADAPT, &
                        rule_id='A-ELE/malformed-record', object_path='mesh.elements', &
                        index=irec, &
                        message='malformed .ele record: '//trim(iomsg_buf), source=loc))
        return
      end if

      call opt_set(element%id, i0)
      if (allocated(element%nodes)) deallocate (element%nodes)
      allocate (element%nodes(ctx%nnode))
      element%nodes = lnods

      call builder_add_element(b, element, loc, errors)
      if (builder_failed(b)) return
    end do

    if (irec == 0_int32) then
      loc = make_source_location(file='.ele', reader='read_element', line=1087_int32)
      call builder_elements_empty(b, loc, errors)
    end if
  end subroutine parse_ele

  ! ============================================================================
  ! shared helpers
  ! ============================================================================

  ! G2 analysis.dimension (yl_problem_profile.f90) is the single source of truth for
  ! the whitelisted mesh dimension; this reads it rather than repeating "2" a second
  ! time. A missing row would be a defect in that table, not in this deck, but is
  ! still handled rather than asserted past: this parser degrades to accepting
  ! whatever ctx%ndimn is (the read itself is not at risk either way, see the module
  ! header) instead of crashing on a table it does not own.
  logical function dimension_ok(errors, ndimn) result(ok)
    type(problem_errors_t), intent(inout) :: errors
    integer(int32), intent(in) :: ndimn
    integer(int32) :: expected
    logical :: found
    type(source_location_t) :: loc

    call capability_expect_int('analysis.dimension', expected, found)
    ok = .true.
    if (.not. found) return
    if (ndimn == expected) return

    ok = .false.
    loc = make_source_location(file='.glb', reader='global_data', line=694_int32)
    call errors%add(make_problem_error(code=PE_UNSUPPORTED, stage=STAGE_ADAPT, &
                    rule_id='A-COR/dimension', object_path='mesh', field='dimension', &
                    message='only the capability table''s analysis.dimension is whitelisted; ' &
                    //'a different ndimn would build a draft the capability gate rejects later ' &
                    //'anyway, so this parser stops before spending the read', &
                    actual=itoa(ndimn), expected=itoa(expected), source=loc))
  end function dimension_ok

  ! G1 element.kind_code (yl_problem_profile.f90) is the single source of truth for
  ! the whitelisted element kind (5 == Q4). Checked here, unlike dimension_ok's
  ! check, because a non-Q4 kind is this parser's OWN reason for existing: it was
  ! written to shape a Q4 connectivity record and nothing else, so there is no
  ! "spend the read anyway and let a later stage catch it" option worth taking --
  ! ctx%nnode may coincidentally match some other kind's node count (e.g. legacy's
  ! H4 is also 4-node, Elements.f90) and produce a record that parses cleanly but
  ! means nothing this build understands.
  logical function element_kind_ok(errors, element_kind) result(ok)
    type(problem_errors_t), intent(inout) :: errors
    integer(int32), intent(in) :: element_kind
    integer(int32) :: expected
    logical :: found
    type(source_location_t) :: loc

    call capability_expect_int('element.kind_code', expected, found)
    ok = .true.
    if (.not. found) return
    if (element_kind == expected) return

    ok = .false.
    loc = make_source_location(file='.glb', reader='global_data', line=1216_int32)
    call errors%add(make_problem_error(code=PE_UNSUPPORTED, stage=STAGE_ADAPT, &
                    rule_id='A-ELE/element-kind', object_path='sections[]', &
                    field='element_kind', &
                    message='only the capability table''s element.kind_code (Q4) is ' &
                    //'whitelisted; this parser only knows how to shape a Q4 connectivity ' &
                    //'record', actual=itoa(element_kind), expected=itoa(expected), source=loc))
  end function element_kind_ok

  ! Minimal integer-to-text helper for `actual=`/`expected=`. Private and local, same
  ! rationale as yl_problem_errors's own itoa: no dependency pulled in for one
  ! conversion.
  pure function itoa(value) result(text)
    integer(int32), intent(in) :: value
    character(len=:), allocatable :: text
    character(len=12) :: buffer
    write (buffer, '(i0)') value
    text = trim(buffer)
  end function itoa

end module yl_adapter_mesh
