! yl_adapter_mesh -- M4-01 legacy adapter: .cor (node coordinates) and .ele (element
! connectivity), per docs/m4/adapter-contract.md §2.
!
! Scope
!   Exactly the two reader-inventory sites whose `file` is .cor or .ele:
!     COR.global_data.node_coordinates      (Global.f90:1176)
!     ELE.read_element.element_connectivity (Elements.f90:1087)
!   and nothing else. This module does not open/close/rewind `unit` (its lifecycle is
!   L2-a's, adapter-contract.md §2), does not touch a legacy global, and writes the
!   draft only through yl_problem_builder.
!
! Whitelist (static-q4/1; not enlarged here, adapter-contract.md §5): 2D, Q4.
!
!   Both numbers this module needs to shape a read -- how many coordinates per node
!   (ndimn) and how many node ids per element (nnode) -- are established by the
!   *.glb* group header BEFORE .cor/.ele are ever opened (Global.f90:694 for ndimn,
!   :1216/:1225 for the element kind that fixes nnode), and are validated there
!   (`if(ndimn/=2.and.ndimn/=3)`, `if(group(igroup)%index<1.or....>ekind)`). This
!   parser has no way to see that value: the shared parse_<kind>(unit, b, errors)
!   shape carries no side channel for it, and yl_problem_builder keeps every
!   singleton (including mesh.dimension) PRIVATE with no accessor. So NDIMN and
!   NNODE_Q4 below are not read here -- they are the ONLY values this build
!   supports, asserted as parameters. A deck outside 2D/Q4 does not fail loudly at
!   this parser; it silently misreads. Reporting, not fixing (file ownership,
!   adapter-contract.md "FILE OWNERSHIP"): L2-a's sequencing driver MUST have already
!   rejected a non-2D deck or a non-Q4 element kind from the .glb group header
!   before invoking parse_cor / parse_ele, the same way global_data's own guards run
!   before Global.f90:1176 and read_element's before Elements.f90:1087 do.
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
!   .glb (Global.f90:694, :1229) and loops that many times. That count is invisible
!   to this parser for the same reason ndimn is, so each routine reads until
!   IOSTAT_END. For a well-formed deck this is equivalent; it is the only option
!   available under the fixed parse_<kind>(unit, b, errors) shape.
module yl_adapter_mesh

  use iso_fortran_env, only: int32, real64, iostat_end
  use yl_problem_optional, only: opt_set
  use yl_problem_types, only: node_t, element_t
  use yl_problem_builder, only: problem_builder_t, builder_add_node, builder_nodes_empty, &
                                 builder_add_element, builder_elements_empty, builder_failed
  use yl_problem_errors, only: problem_errors_t, source_location_t, make_source_location, &
                                make_problem_error, PE_INVALID_INPUT

  implicit none
  private

  public :: parse_cor, parse_ele

  ! Whitelist constants (static-q4/1). Not enlarged; see the module header for why
  ! they are constants rather than something read from the deck.
  integer, parameter :: NDIMN = 2
  integer, parameter :: NNODE_Q4 = 4

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
  subroutine parse_cor(unit, b, errors)
    integer, intent(in) :: unit
    type(problem_builder_t), intent(inout) :: b
    type(problem_errors_t), intent(inout) :: errors

    integer(int32) :: i0, irec, ios
    real(real64) :: xyz(NDIMN)
    character(len=256) :: iomsg_buf
    type(node_t) :: node
    type(source_location_t) :: loc

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
      allocate (node%xyz(NDIMN))
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
  ! One record per element: `i0, lnods(1:nnode)`. Under the Q4-only whitelist nnode
  ! is fixed at NNODE_Q4 (module header); legacy loops ielem=1..nelem across all
  ! groups with nelem/nelgroup from .glb, invisible here for the same reason, so
  ! this parser also reads until end of file.
  !
  ! kind/material/elset are left UNSET on every element built here. All three are
  ! `derived_from` sections[] in docs/m2/state-field-map.toml (the .glb group
  ! header), never read from .ele itself -- filling them is whoever derives
  ! sections[] from .glb, not this parser (adapter-contract.md §2, "只通过
  ! yl_problem_builder 写 draft" does not mean guessing a field this file never
  ! carries).
  subroutine parse_ele(unit, b, errors)
    integer, intent(in) :: unit
    type(problem_builder_t), intent(inout) :: b
    type(problem_errors_t), intent(inout) :: errors

    integer(int32) :: i0, irec, ios
    integer(int32) :: lnods(NNODE_Q4)
    character(len=256) :: iomsg_buf
    type(element_t) :: element
    type(source_location_t) :: loc

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
      allocate (element%nodes(NNODE_Q4))
      element%nodes = lnods

      call builder_add_element(b, element, loc, errors)
      if (builder_failed(b)) return
    end do

    if (irec == 0_int32) then
      loc = make_source_location(file='.ele', reader='read_element', line=1087_int32)
      call builder_elements_empty(b, loc, errors)
    end if
  end subroutine parse_ele

end module yl_adapter_mesh
