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
! End of .cor
!   .cor carries no record count of its own; legacy gets npoin from .glb
!   (Global.f90:694) and loops that many times. deck_context_t carries ndimn but
!   deliberately not npoin (that sizes a COLLECTION, not a single record, and is
!   outside what makes a .cor record misparse), so parse_cor reads until
!   IOSTAT_END. For a well-formed deck this is equivalent; verified against both
!   golden decks (cooks_membrane: 289 nodes; lame_cylinder: 81 nodes -- matching
!   reader-inventory hit counts).
!
! .ele's group attribution (adapter-contract.md §2.3, added 2026-09-08 after L2-a's
! first integration run)
!   .ele is NOT read to IOSTAT_END like .cor: legacy reads `.ele` INSIDE `.glb`'s
!   per-group header loop (Global.f90:1213-1310, `read_element` called from
!   Elements.f90:1296), so a record's owning section is decided POSITIONALLY -- the
!   first `nelgroup(1)` records belong to section 1, the next `nelgroup(2)` to
!   section 2, and so on. The .ele file itself carries no group boundary; its
!   records are just `i0, lnods(1:nnode)`. Before deck_context_t carried
!   `nelgroup(:)` / `group_matno(:)` / `group_kind(:)`, this parser had no way to
!   attribute a record to a section at all -- an earlier revision of this module
!   left `elset`/`material`/`kind` UNSET on every element and never called
!   `builder_add_elset`, on the reasoning that those are `derived_from` sections[]
!   in docs/m2/state-field-map.toml and therefore someone else's job. That
!   reasoning was correct about WHERE the values come from and wrong about WHO
!   can compute them: the .glb parser never sees an element record, so "someone
!   else" did not exist. The map's `derived_from` names the SOURCE FILE (.glb, via
!   ctx), not a different MODULE. Caught by L2-a's first integration run: normalize
!   rule N6 rejected every element on both golden decks (256 / 64 findings) because
!   `mesh.elsets[]` was empty.
!
!   Because the count now comes from `ctx` rather than being discovered by reading
!   to EOF, a mismatch between `sum(ctx%nelgroup)` and the records actually present
!   is no longer something this parser can shrug off as "however many there were" --
!   it is a genuine deck defect (PE_INVALID_INPUT, rule A-ELE/count-mismatch),
!   raised whether the file runs out early or has records left over.
module yl_adapter_mesh

  use iso_fortran_env, only: int32, real64, iostat_end
  use yl_problem_optional, only: opt_set
  use yl_problem_types, only: node_t, element_t, elset_t
  use yl_problem_builder, only: problem_builder_t, builder_add_node, builder_nodes_empty, &
                                 builder_add_element, builder_elements_empty, &
                                 builder_add_elset, builder_elsets_empty, builder_failed
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
  ! One record per element: `i0, lnods(1:nnode)`. Attribution to a section is
  ! POSITIONAL, per `ctx%nelgroup(:)` (module header, adapter-contract.md §2.3):
  ! the first `ctx%nelgroup(1)` records belong to section 1, the next
  ! `ctx%nelgroup(2)` to section 2, and so on. This parser therefore reads exactly
  ! `sum(ctx%nelgroup)` records, grouped in that order, rather than to IOSTAT_END --
  ! the count is now an input (from `ctx`) instead of something only discoverable by
  ! reading, so a mismatch is this parser's to report, not to absorb.
  !
  ! Sets `elset` = the section's 1-based position, `material` = ctx%group_matno for
  ! that section and `kind` = ctx%group_kind for that section on every element, and
  ! calls builder_add_elset once per section, in section order (rule N4 keys
  ! mesh.elsets[] to sections[] positionally, so order here is load-bearing).
  subroutine parse_ele(unit, ctx, b, errors)
    integer, intent(in) :: unit
    type(deck_context_t), intent(in) :: ctx
    type(problem_builder_t), intent(inout) :: b
    type(problem_errors_t), intent(inout) :: errors

    integer(int32) :: i0, irec, ios, igroup, k, total
    integer(int32), allocatable :: lnods(:)
    integer(int32), allocatable :: group_elements(:)
    character(len=256) :: iomsg_buf
    type(element_t) :: element
    type(elset_t) :: es
    type(source_location_t) :: loc

    if (.not. ctx%filled) then
      loc = make_source_location(file='.ele', reader='read_element', line=1087_int32)
      call errors%add(make_problem_error(code=PE_INTERNAL, stage=STAGE_ADAPT, &
                      rule_id='A-ELE/context-not-filled', object_path='mesh.elements', &
                      message='parse_ele was called before parse_glb filled deck_context_t', &
                      source=loc))
      return
    end if
    if (.not. allocated(ctx%nelgroup) .or. .not. allocated(ctx%group_matno) &
        .or. .not. allocated(ctx%group_kind)) then
      loc = make_source_location(file='.ele', reader='read_element', line=1087_int32)
      call errors%add(make_problem_error(code=PE_INTERNAL, stage=STAGE_ADAPT, &
                      rule_id='A-ELE/context-incomplete', object_path='mesh.elements', &
                      message='deck_context_t is marked filled but nelgroup/group_matno/' &
                      //'group_kind were never allocated', source=loc))
      return
    end if

    ! No groups at all: an explicitly empty mesh, both collections.
    if (size(ctx%nelgroup) == 0_int32) then
      loc = make_source_location(file='.ele', reader='read_element', line=1087_int32)
      call builder_elements_empty(b, loc, errors)
      call builder_elsets_empty(b, loc, errors)
      return
    end if

    allocate (lnods(ctx%nnode))
    irec = 0_int32
    do igroup = 1_int32, size(ctx%nelgroup)
      if (.not. element_kind_ok(errors, ctx%group_kind(igroup), igroup)) return

      allocate (group_elements(ctx%nelgroup(igroup)))
      do k = 1_int32, ctx%nelgroup(igroup)
        read (unit, *, iostat=ios, iomsg=iomsg_buf) i0, lnods
        irec = irec + 1_int32
        loc = make_source_location(file='.ele', reader='read_element', line=1087_int32, &
                                    record=irec)
        if (ios == iostat_end) then
          call count_mismatch(errors, loc, irec - 1_int32, sum(ctx%nelgroup))
          return
        end if
        if (ios /= 0) then
          call errors%add(make_problem_error(code=PE_INVALID_INPUT, stage=STAGE_ADAPT, &
                          rule_id='A-ELE/malformed-record', object_path='mesh.elements', &
                          index=irec, &
                          message='malformed .ele record: '//trim(iomsg_buf), source=loc))
          return
        end if

        call opt_set(element%id, i0)
        call opt_set(element%elset, igroup)
        call opt_set(element%material, ctx%group_matno(igroup))
        call opt_set(element%kind, ctx%group_kind(igroup))
        if (allocated(element%nodes)) deallocate (element%nodes)
        allocate (element%nodes(ctx%nnode))
        element%nodes = lnods

        call builder_add_element(b, element, loc, errors)
        if (builder_failed(b)) return
        group_elements(k) = i0
      end do

      es%elements = group_elements
      call builder_add_elset(b, es, loc, errors)
      if (builder_failed(b)) return
      deallocate (group_elements)
    end do

    ! Leftover records: try to read one more. Succeeding means the file has more
    ! than `sum(ctx%nelgroup)` records, a deck defect symmetric with running out
    ! early above -- the count is the authority either way (module header).
    total = irec
    read (unit, *, iostat=ios, iomsg=iomsg_buf) i0, lnods
    if (ios == iostat_end) return
    loc = make_source_location(file='.ele', reader='read_element', line=1087_int32, &
                                record=total + 1_int32)
    if (ios /= 0) then
      call errors%add(make_problem_error(code=PE_INVALID_INPUT, stage=STAGE_ADAPT, &
                      rule_id='A-ELE/malformed-record', object_path='mesh.elements', &
                      index=total + 1_int32, &
                      message='malformed .ele record: '//trim(iomsg_buf), source=loc))
      return
    end if
    call errors%add(make_problem_error(code=PE_INVALID_INPUT, stage=STAGE_ADAPT, &
                    rule_id='A-ELE/count-mismatch', object_path='mesh.elements', &
                    message='.ele has more records than sum(ctx%nelgroup) declares', &
                    actual='> '//itoa(total), expected=itoa(total), source=loc))
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
  ! means nothing this build understands. `igroup` is the 1-based section position
  ! (ctx%group_kind is now per-section, adapter-contract.md §2.3), reported as the
  ! index so a rejection on section 2 is not indistinguishable from one on section 1.
  logical function element_kind_ok(errors, element_kind, igroup) result(ok)
    type(problem_errors_t), intent(inout) :: errors
    integer(int32), intent(in) :: element_kind, igroup
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
                    field='element_kind', index=igroup, &
                    message='only the capability table''s element.kind_code (Q4) is ' &
                    //'whitelisted; this parser only knows how to shape a Q4 connectivity ' &
                    //'record', actual=itoa(element_kind), expected=itoa(expected), source=loc))
  end function element_kind_ok

  ! .ele ran out of records before sum(ctx%nelgroup) was consumed. The symmetric
  ! "too many" case is handled inline in parse_ele (it needs one more read attempt
  ! after the loop, which does not fit this shape).
  subroutine count_mismatch(errors, loc, actual_count, expected_count)
    type(problem_errors_t), intent(inout) :: errors
    type(source_location_t), intent(in) :: loc
    integer(int32), intent(in) :: actual_count, expected_count
    call errors%add(make_problem_error(code=PE_INVALID_INPUT, stage=STAGE_ADAPT, &
                    rule_id='A-ELE/count-mismatch', object_path='mesh.elements', &
                    message='.ele ran out of records before sum(ctx%nelgroup) was consumed', &
                    actual=itoa(actual_count), expected=itoa(expected_count), source=loc))
  end subroutine count_mismatch

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
