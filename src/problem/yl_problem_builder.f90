! yl_problem_builder -- the minimal draft builder shared by the M4 legacy adapter and
! the M5 TOML reader.
!
! Scope (.ccg/tasks/m3-02-normalize-validate-finalize/plan.md, deliverable 5)
!   This module ASSEMBLES a problem_state_t draft and does nothing else. It does not
!   parse, does not perform I/O, does not validate physics, does not resolve references,
!   does not compute counts and does not apply defaults: those belong to normalize,
!   validate, the capability gate and finalize (yl_problem_pipeline). Its only checks are
!   STRUCTURAL -- adding to a collection that was already declared explicitly empty,
!   declaring empty a collection that already has entries, setting a singleton twice, and
!   using or finishing a builder that was never begun.
!
!   In particular the builder never inspects a value it is handed. A node with no
!   coordinates, a material with no modulus and a section referring to material 999 are
!   all accepted here and rejected later, by a rule that owns a negative fixture.
!
! Unknown keys are NOT this module's job
!   A closed Fortran derived type has no room for a field it does not declare, so an
!   unknown authoring key cannot reach the builder at all: by the time a reader calls
!   builder_add_material it has already chosen which component to fill. Unknown-key
!   rejection therefore happens at the READER boundary -- the M4 legacy adapter and the
!   M5 TOML reader -- not here. A reader that has rejected a key should bind that failure
!   to the draft with builder_note_failure so the draft can never be finished as if the
!   input had been clean.
!
! Three states, and how "explicitly empty" is kept unreachable by accident (ADR-0002,
! docs/06 row I04)
!   Every collection is in exactly one of three states, tracked by a private enum:
!     COLL_UNSET  -- no adder and no _empty call was ever made. The component is left
!                    UNALLOCATED in the finished draft.
!     COLL_EMPTY  -- builder_<collection>_empty was called. The component is allocated
!                    with size 0 in the finished draft.
!     COLL_FILLED -- at least one adder call succeeded. The component is allocated with
!                    the number of entries added, which is >= 1 by construction.
!   The state starts at COLL_UNSET and there is exactly ONE assignment of COLL_EMPTY per
!   collection, inside that collection's dedicated _empty subroutine. Nothing else in
!   this module can produce that state. The commit step allocates a zero-length array
!   only under `case (COLL_EMPTY)`; the COLL_FILLED branch allocates `used` entries and
!   `used` is incremented in the same statement sequence that stores the first entry, so
!   a filled collection can never commit as zero length. There is no code path that
!   reaches an allocated empty component without a caller having named it.
!   The two conflicting transitions are refused rather than silently merged: an add after
!   _empty and an _empty after an add are both errors.
!
!   The rank-1 arrays INSIDE an entity (node%xyz, element%nodes, elset%elements,
!   nset%nodes, controls%tolerance_dof, gravity%direction, gravity%amplitude,
!   output%stress_averaging) are carried through verbatim with the allocation status the
!   caller gave them, so the same three-state reading applies to them by construction.
!
! Sticky errors
!   The builder carries a `failed` flag. Every refused call sets it, records a
!   problem_error_t in the caller's accumulator and returns without changing anything
!   else. The flag is never cleared, so builder_finish always fails once any call has
!   failed, however many calls succeeded afterwards. A failed add can therefore not
!   vanish. The step and amplitude sub-builders take the parent builder as their first
!   argument for exactly this reason: a failure inside a sub-builder marks the parent
!   immediately, so it still fails even if that sub-builder is then abandoned rather than
!   finished. builder_note_failure gives a reader the same guarantee for a failure the
!   builder itself could not have seen.
!
! Transactional commit
!   builder_finish assembles a private candidate and publishes it with move_alloc only
!   after every collection has committed. On failure the caller's `draft` is not touched
!   at all, so a previously published draft survives a failed rebuild. Every call
!   carries a source_location_t so a later error can name where the value came from.
!
! Style note
!   Sub-builder routines are named builder_step_* and builder_amplitude_* so that the
!   whole public surface of this module shares one prefix.
module yl_problem_builder

  use iso_fortran_env, only: int32
  use yl_problem_optional, only: opt_int, opt_text, opt_set
  use yl_problem_types, only: problem_state_t, case_t, node_t, element_t, elset_t, &
                              nset_t, material_t, section_t, amplitude_t, &
                              amplitude_point_t, interactions_t, solver_t, step_t, &
                              controls_t, load_t, output_t, boundary_t, activation_t
  use yl_problem_errors, only: problem_error_t, problem_errors_t, source_location_t, &
                               make_problem_error, PE_INVALID_INPUT

  implicit none
  private

  public :: problem_builder_t, step_builder_t, amplitude_builder_t
  public :: builder_begin, builder_finish, builder_failed, builder_note_failure
  public :: builder_set_case, builder_set_mesh_dimension
  public :: builder_set_interactions, builder_set_solver
  public :: builder_add_node, builder_nodes_empty
  public :: builder_add_element, builder_elements_empty
  public :: builder_add_elset, builder_elsets_empty
  public :: builder_add_nset, builder_nsets_empty
  public :: builder_add_material, builder_materials_empty
  public :: builder_add_section, builder_sections_empty
  public :: builder_add_amplitude, builder_amplitudes_empty
  public :: builder_add_step, builder_steps_empty
  public :: builder_amplitude_begin, builder_amplitude_finish
  public :: builder_amplitude_set_name, builder_amplitude_set_type
  public :: builder_amplitude_add_point, builder_amplitude_points_empty
  public :: builder_step_begin, builder_step_finish
  public :: builder_step_set_procedure, builder_step_set_load_mode
  public :: builder_step_set_controls, builder_step_set_load, builder_step_set_output
  public :: builder_step_add_boundary, builder_step_boundary_empty
  public :: builder_step_add_activation, builder_step_activation_empty

  ! --- the three states -------------------------------------------------------
  ! COLL_EMPTY is assigned in exactly one place per collection: that collection's
  ! _empty subroutine. Grep for it to enumerate every way an allocated zero-length
  ! collection can be reached.
  integer(int32), parameter :: COLL_UNSET  = 0_int32
  integer(int32), parameter :: COLL_EMPTY  = 1_int32
  integer(int32), parameter :: COLL_FILLED = 2_int32

  ! Initial staging capacity, then geometric growth. Capacity is never the committed
  ! extent; the committed extent is always the `used` counter.
  integer(int32), parameter :: SEED_CAPACITY = 16_int32

  ! The builder runs at the READER boundary, before normalize; it is not one of the
  ! four pipeline stages, so it names its own stage rather than borrowing PE_STAGE_*.
  character(len=*), parameter :: STAGE = 'builder'

  ! --- builder state ----------------------------------------------------------

  type :: problem_builder_t
    private
    logical :: begun = .false.
    logical :: failed = .false.

    ! singletons
    logical :: has_case = .false.
    type(case_t) :: case
    logical :: has_dimension = .false.
    type(opt_int) :: dimension
    logical :: has_interactions = .false.
    type(interactions_t) :: interactions
    logical :: has_solver = .false.
    type(solver_t) :: solver

    ! collections: one state, one counter and one staging buffer each
    integer(int32) :: st_nodes = COLL_UNSET
    integer(int32) :: n_nodes = 0_int32
    type(node_t), allocatable :: buf_nodes(:)

    integer(int32) :: st_elements = COLL_UNSET
    integer(int32) :: n_elements = 0_int32
    type(element_t), allocatable :: buf_elements(:)

    integer(int32) :: st_elsets = COLL_UNSET
    integer(int32) :: n_elsets = 0_int32
    type(elset_t), allocatable :: buf_elsets(:)

    integer(int32) :: st_nsets = COLL_UNSET
    integer(int32) :: n_nsets = 0_int32
    type(nset_t), allocatable :: buf_nsets(:)

    integer(int32) :: st_materials = COLL_UNSET
    integer(int32) :: n_materials = 0_int32
    type(material_t), allocatable :: buf_materials(:)

    integer(int32) :: st_sections = COLL_UNSET
    integer(int32) :: n_sections = 0_int32
    type(section_t), allocatable :: buf_sections(:)

    integer(int32) :: st_amplitudes = COLL_UNSET
    integer(int32) :: n_amplitudes = 0_int32
    type(amplitude_t), allocatable :: buf_amplitudes(:)

    integer(int32) :: st_steps = COLL_UNSET
    integer(int32) :: n_steps = 0_int32
    type(step_t), allocatable :: buf_steps(:)
  end type problem_builder_t

  type :: amplitude_builder_t
    private
    logical :: begun = .false.
    logical :: has_name = .false.
    logical :: has_type = .false.
    type(opt_text) :: name
    type(opt_text) :: type
    integer(int32) :: st_points = COLL_UNSET
    integer(int32) :: n_points = 0_int32
    type(amplitude_point_t), allocatable :: buf_points(:)
  end type amplitude_builder_t

  type :: step_builder_t
    private
    logical :: begun = .false.
    logical :: has_procedure = .false.
    logical :: has_load_mode = .false.
    logical :: has_controls = .false.
    logical :: has_load = .false.
    logical :: has_output = .false.
    type(opt_text) :: procedure_name
    type(opt_text) :: load_mode
    type(controls_t) :: controls
    type(load_t) :: load
    type(output_t) :: output
    integer(int32) :: st_boundary = COLL_UNSET
    integer(int32) :: n_boundary = 0_int32
    type(boundary_t), allocatable :: buf_boundary(:)
    integer(int32) :: st_activation = COLL_UNSET
    integer(int32) :: n_activation = 0_int32
    type(activation_t), allocatable :: buf_activation(:)
  end type step_builder_t

contains

  ! ==========================================================================
  ! error emission and structural guards
  ! ==========================================================================

  ! The single place where a problem_error_t is constructed. If the shape of
  ! yl_problem_errors turns out to differ from the API this module was written
  ! against, this is the only routine that has to change.
  ! The single place where a structural problem_error_t is constructed. `field`,
  ! `expected` and `actual` are passed as strings for call-site brevity and an EMPTY
  ! string means "not applicable": the component is then left UNSET rather than set to
  ! an empty text, because under ADR-0002 those are different statements.
  subroutine emit(errors, rule_id, object_path, field, message, expected, actual, loc, &
                  index)
    type(problem_errors_t), intent(inout) :: errors
    character(len=*), intent(in) :: rule_id, object_path, field, message
    character(len=*), intent(in) :: expected, actual
    type(source_location_t), intent(in) :: loc
    integer(int32), intent(in), optional :: index
    type(problem_error_t) :: err
    err = make_problem_error(code=PE_INVALID_INPUT, stage=STAGE, rule_id=rule_id, &
                             object_path=object_path, message=message, source=loc)
    if (present(index)) call opt_set(err%index, index)
    if (len(field) > 0) call opt_set(err%field, field)
    if (len(expected) > 0) call opt_set(err%expected, expected)
    if (len(actual) > 0) call opt_set(err%actual, actual)
    call errors%add(err)
  end subroutine emit

  ! Marks the builder failed and records why. The flag is never cleared.
  subroutine fail(b, errors, rule_id, object_path, field, message, expected, actual, &
                  loc, index)
    type(problem_builder_t), intent(inout) :: b
    type(problem_errors_t), intent(inout) :: errors
    character(len=*), intent(in) :: rule_id, object_path, field, message
    character(len=*), intent(in) :: expected, actual
    type(source_location_t), intent(in) :: loc
    integer(int32), intent(in), optional :: index
    b%failed = .true.
    call emit(errors, rule_id, object_path, field, message, expected, actual, loc, index)
  end subroutine fail

  ! Guard for an adder. Refuses on a builder that was never begun and on a
  ! collection already declared explicitly empty.
  function allow_add(b, state, object_path, ordinal, loc, errors) result(ok)
    type(problem_builder_t), intent(inout) :: b
    integer(int32), intent(in) :: state
    character(len=*), intent(in) :: object_path
    integer(int32), intent(in) :: ordinal
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    logical :: ok
    ok = .false.
    if (.not. b%begun) then
      call fail(b, errors, 'builder.not_begun', object_path, '', &
                'the builder was not begun; call builder_begin before adding', &
                'a begun builder', 'an unbegun builder', loc, index=ordinal)
      return
    end if
    if (state == COLL_EMPTY) then
      call fail(b, errors, 'builder.add_after_empty', object_path, '', &
                'this collection was already declared explicitly empty; it cannot ' // &
                'also receive entries', 'no entry', 'an added entry', loc, index=ordinal)
      return
    end if
    ok = .true.
  end function allow_add

  ! Guard for a _empty declaration. Refuses on a builder that was never begun and
  ! on a collection that already has entries.
  function allow_empty(b, state, object_path, loc, errors) result(ok)
    type(problem_builder_t), intent(inout) :: b
    integer(int32), intent(in) :: state
    character(len=*), intent(in) :: object_path
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    logical :: ok
    ok = .false.
    if (.not. b%begun) then
      call fail(b, errors, 'builder.not_begun', object_path, '', &
                'the builder was not begun; call builder_begin before declaring ' // &
                'a collection empty', 'a begun builder', 'an unbegun builder', loc)
      return
    end if
    if (state == COLL_FILLED) then
      call fail(b, errors, 'builder.empty_after_add', object_path, '', &
                'this collection already has entries and cannot be declared ' // &
                'explicitly empty', 'no entry', 'at least one entry', loc)
      return
    end if
    ok = .true.
  end function allow_empty

  ! Guard for a singleton setter. A singleton may be set once.
  function allow_set(b, has, object_path, field, loc, errors) result(ok)
    type(problem_builder_t), intent(inout) :: b
    logical, intent(in) :: has
    character(len=*), intent(in) :: object_path, field
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    logical :: ok
    ok = .false.
    if (.not. b%begun) then
      call fail(b, errors, 'builder.not_begun', object_path, field, &
                'the builder was not begun; call builder_begin before setting a value', &
                'a begun builder', 'an unbegun builder', loc)
      return
    end if
    if (has) then
      call fail(b, errors, 'builder.duplicate_singleton', object_path, field, &
                'this singleton was already set; the input declares it twice', &
                'one declaration', 'a second declaration', loc)
      return
    end if
    ok = .true.
  end function allow_set

  ! Guard for a sub-builder operation. Marks the PARENT builder failed so that an
  ! abandoned sub-builder still cannot be silently dropped.
  function allow_sub(b, begun, object_path, loc, errors) result(ok)
    type(problem_builder_t), intent(inout) :: b
    logical, intent(in) :: begun
    character(len=*), intent(in) :: object_path
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    logical :: ok
    ok = .false.
    if (.not. b%begun) then
      call fail(b, errors, 'builder.not_begun', object_path, '', &
                'the parent builder was not begun', 'a begun builder', &
                'an unbegun builder', loc)
      return
    end if
    if (.not. begun) then
      call fail(b, errors, 'builder.sub_not_begun', object_path, '', &
                'this sub-builder was not begun', 'a begun sub-builder', &
                'an unbegun sub-builder', loc)
      return
    end if
    ok = .true.
  end function allow_sub

  ! ==========================================================================
  ! lifecycle
  ! ==========================================================================

  ! Starts a fresh draft. Every collection begins UNSET and every singleton unset.
  subroutine builder_begin(b)
    type(problem_builder_t), intent(out) :: b
    b%begun = .true.
  end subroutine builder_begin

  ! .true. once any call on this builder has been refused. Never returns to .false.
  pure function builder_failed(b) result(res)
    type(problem_builder_t), intent(in) :: b
    logical :: res
    res = b%failed
  end function builder_failed

  ! Binds a failure the builder could not have seen itself -- an unknown authoring
  ! key, a malformed record, a reader-level refusal -- to this draft, so that
  ! builder_finish fails even though every builder call succeeded.
  subroutine builder_note_failure(b, code, rule_id, object_path, field, message, &
                                  loc, errors)
    type(problem_builder_t), intent(inout) :: b
    character(len=*), intent(in) :: code, rule_id, object_path, field, message
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    type(problem_error_t) :: err
    b%failed = .true.
    err = make_problem_error(code=code, stage=STAGE, rule_id=rule_id, &
                             object_path=object_path, message=message, source=loc)
    if (len(field) > 0) call opt_set(err%field, field)
    call errors%add(err)
  end subroutine builder_note_failure

  ! Commits the draft. `draft` is only written on success, and then in one
  ! move_alloc, so a previously published draft survives a failed rebuild.
  ! The builder is reset afterwards either way: it cannot be finished twice.
  subroutine builder_finish(b, draft, errors, ok)
    type(problem_builder_t), intent(inout) :: b
    type(problem_state_t), allocatable, intent(inout) :: draft
    type(problem_errors_t), intent(inout) :: errors
    logical, intent(out), optional :: ok
    type(problem_state_t), allocatable :: candidate
    type(source_location_t) :: here
    logical :: good

    good = .true.
    if (.not. b%begun) then
      call fail(b, errors, 'builder.not_begun', '', '', &
                'builder_finish was called on a builder that was never begun', &
                'a begun builder', 'an unbegun builder', here)
      good = .false.
    else if (b%failed) then
      ! The refusals are already in `errors`. Only add a note if they somehow are
      ! not, so that a sticky failure can never be silent.
      if (.not. errors%any()) then
        call emit(errors, 'builder.finish_aborted', '', '', &
                  'the builder recorded a failure but the accumulator is empty', &
                  'no prior failure', 'a prior failure', here)
      end if
      good = .false.
    end if

    if (good) then
      allocate(candidate)
      candidate%case = b%case
      candidate%mesh%dimension = b%dimension
      candidate%interactions = b%interactions
      candidate%solver = b%solver

      select case (b%st_nodes)
      case (COLL_EMPTY);  allocate(candidate%mesh%nodes(0))
      case (COLL_FILLED); allocate(candidate%mesh%nodes(b%n_nodes))
                          candidate%mesh%nodes(:) = b%buf_nodes(1:b%n_nodes)
      end select

      select case (b%st_elements)
      case (COLL_EMPTY);  allocate(candidate%mesh%elements(0))
      case (COLL_FILLED); allocate(candidate%mesh%elements(b%n_elements))
                          candidate%mesh%elements(:) = b%buf_elements(1:b%n_elements)
      end select

      select case (b%st_elsets)
      case (COLL_EMPTY);  allocate(candidate%mesh%elsets(0))
      case (COLL_FILLED); allocate(candidate%mesh%elsets(b%n_elsets))
                          candidate%mesh%elsets(:) = b%buf_elsets(1:b%n_elsets)
      end select

      select case (b%st_nsets)
      case (COLL_EMPTY);  allocate(candidate%mesh%nsets(0))
      case (COLL_FILLED); allocate(candidate%mesh%nsets(b%n_nsets))
                          candidate%mesh%nsets(:) = b%buf_nsets(1:b%n_nsets)
      end select

      select case (b%st_materials)
      case (COLL_EMPTY);  allocate(candidate%materials(0))
      case (COLL_FILLED); allocate(candidate%materials(b%n_materials))
                          candidate%materials(:) = b%buf_materials(1:b%n_materials)
      end select

      select case (b%st_sections)
      case (COLL_EMPTY);  allocate(candidate%sections(0))
      case (COLL_FILLED); allocate(candidate%sections(b%n_sections))
                          candidate%sections(:) = b%buf_sections(1:b%n_sections)
      end select

      select case (b%st_amplitudes)
      case (COLL_EMPTY);  allocate(candidate%amplitudes(0))
      case (COLL_FILLED); allocate(candidate%amplitudes(b%n_amplitudes))
                          candidate%amplitudes(:) = b%buf_amplitudes(1:b%n_amplitudes)
      end select

      select case (b%st_steps)
      case (COLL_EMPTY);  allocate(candidate%steps(0))
      case (COLL_FILLED); allocate(candidate%steps(b%n_steps))
                          candidate%steps(:) = b%buf_steps(1:b%n_steps)
      end select

      call move_alloc(candidate, draft)
    end if

    if (present(ok)) ok = good
    call builder_reset(b)
  end subroutine builder_finish

  ! Returns the builder to its pre-begin state and releases the staging buffers.
  subroutine builder_reset(b)
    type(problem_builder_t), intent(out) :: b
    b%begun = .false.
  end subroutine builder_reset

  ! ==========================================================================
  ! singleton setters
  ! ==========================================================================

  subroutine builder_set_case(b, value, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(case_t), intent(in) :: value
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    if (.not. allow_set(b, b%has_case, 'case', '', loc, errors)) return
    b%case = value
    b%has_case = .true.
  end subroutine builder_set_case

  subroutine builder_set_mesh_dimension(b, value, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    integer(int32), intent(in) :: value
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    if (.not. allow_set(b, b%has_dimension, 'mesh', 'dimension', loc, errors)) return
    call opt_set(b%dimension, value)
    b%has_dimension = .true.
  end subroutine builder_set_mesh_dimension

  subroutine builder_set_interactions(b, value, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(interactions_t), intent(in) :: value
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    if (.not. allow_set(b, b%has_interactions, 'interactions', '', loc, errors)) return
    b%interactions = value
    b%has_interactions = .true.
  end subroutine builder_set_interactions

  subroutine builder_set_solver(b, value, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(solver_t), intent(in) :: value
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    if (.not. allow_set(b, b%has_solver, 'solver', '', loc, errors)) return
    b%solver = value
    b%has_solver = .true.
  end subroutine builder_set_solver

  ! ==========================================================================
  ! mesh.nodes
  ! ==========================================================================

  subroutine builder_add_node(b, value, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(node_t), intent(in) :: value
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    type(node_t), allocatable :: tmp(:)
    if (.not. allow_add(b, b%st_nodes, 'mesh.nodes', b%n_nodes + 1_int32, &
                        loc, errors)) return
    if (.not. allocated(b%buf_nodes)) then
      allocate(b%buf_nodes(SEED_CAPACITY))
    else if (b%n_nodes >= int(size(b%buf_nodes), int32)) then
      allocate(tmp(2 * size(b%buf_nodes)))
      tmp(1:b%n_nodes) = b%buf_nodes(1:b%n_nodes)
      call move_alloc(tmp, b%buf_nodes)
    end if
    b%n_nodes = b%n_nodes + 1_int32
    b%buf_nodes(b%n_nodes) = value
    b%st_nodes = COLL_FILLED
  end subroutine builder_add_node

  subroutine builder_nodes_empty(b, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    if (.not. allow_empty(b, b%st_nodes, 'mesh.nodes', loc, errors)) return
    b%st_nodes = COLL_EMPTY
  end subroutine builder_nodes_empty

  ! ==========================================================================
  ! mesh.elements
  ! ==========================================================================

  subroutine builder_add_element(b, value, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(element_t), intent(in) :: value
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    type(element_t), allocatable :: tmp(:)
    if (.not. allow_add(b, b%st_elements, 'mesh.elements', b%n_elements + 1_int32, &
                        loc, errors)) return
    if (.not. allocated(b%buf_elements)) then
      allocate(b%buf_elements(SEED_CAPACITY))
    else if (b%n_elements >= int(size(b%buf_elements), int32)) then
      allocate(tmp(2 * size(b%buf_elements)))
      tmp(1:b%n_elements) = b%buf_elements(1:b%n_elements)
      call move_alloc(tmp, b%buf_elements)
    end if
    b%n_elements = b%n_elements + 1_int32
    b%buf_elements(b%n_elements) = value
    b%st_elements = COLL_FILLED
  end subroutine builder_add_element

  subroutine builder_elements_empty(b, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    if (.not. allow_empty(b, b%st_elements, 'mesh.elements', loc, errors)) return
    b%st_elements = COLL_EMPTY
  end subroutine builder_elements_empty

  ! ==========================================================================
  ! mesh.elsets
  ! ==========================================================================

  subroutine builder_add_elset(b, value, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(elset_t), intent(in) :: value
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    type(elset_t), allocatable :: tmp(:)
    if (.not. allow_add(b, b%st_elsets, 'mesh.elsets', b%n_elsets + 1_int32, &
                        loc, errors)) return
    if (.not. allocated(b%buf_elsets)) then
      allocate(b%buf_elsets(SEED_CAPACITY))
    else if (b%n_elsets >= int(size(b%buf_elsets), int32)) then
      allocate(tmp(2 * size(b%buf_elsets)))
      tmp(1:b%n_elsets) = b%buf_elsets(1:b%n_elsets)
      call move_alloc(tmp, b%buf_elsets)
    end if
    b%n_elsets = b%n_elsets + 1_int32
    b%buf_elsets(b%n_elsets) = value
    b%st_elsets = COLL_FILLED
  end subroutine builder_add_elset

  subroutine builder_elsets_empty(b, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    if (.not. allow_empty(b, b%st_elsets, 'mesh.elsets', loc, errors)) return
    b%st_elsets = COLL_EMPTY
  end subroutine builder_elsets_empty

  ! ==========================================================================
  ! mesh.nsets
  ! ==========================================================================

  subroutine builder_add_nset(b, value, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(nset_t), intent(in) :: value
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    type(nset_t), allocatable :: tmp(:)
    if (.not. allow_add(b, b%st_nsets, 'mesh.nsets', b%n_nsets + 1_int32, &
                        loc, errors)) return
    if (.not. allocated(b%buf_nsets)) then
      allocate(b%buf_nsets(SEED_CAPACITY))
    else if (b%n_nsets >= int(size(b%buf_nsets), int32)) then
      allocate(tmp(2 * size(b%buf_nsets)))
      tmp(1:b%n_nsets) = b%buf_nsets(1:b%n_nsets)
      call move_alloc(tmp, b%buf_nsets)
    end if
    b%n_nsets = b%n_nsets + 1_int32
    b%buf_nsets(b%n_nsets) = value
    b%st_nsets = COLL_FILLED
  end subroutine builder_add_nset

  subroutine builder_nsets_empty(b, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    if (.not. allow_empty(b, b%st_nsets, 'mesh.nsets', loc, errors)) return
    b%st_nsets = COLL_EMPTY
  end subroutine builder_nsets_empty

  ! ==========================================================================
  ! materials
  ! ==========================================================================

  subroutine builder_add_material(b, value, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(material_t), intent(in) :: value
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    type(material_t), allocatable :: tmp(:)
    if (.not. allow_add(b, b%st_materials, 'materials', b%n_materials + 1_int32, &
                        loc, errors)) return
    if (.not. allocated(b%buf_materials)) then
      allocate(b%buf_materials(SEED_CAPACITY))
    else if (b%n_materials >= int(size(b%buf_materials), int32)) then
      allocate(tmp(2 * size(b%buf_materials)))
      tmp(1:b%n_materials) = b%buf_materials(1:b%n_materials)
      call move_alloc(tmp, b%buf_materials)
    end if
    b%n_materials = b%n_materials + 1_int32
    b%buf_materials(b%n_materials) = value
    b%st_materials = COLL_FILLED
  end subroutine builder_add_material

  subroutine builder_materials_empty(b, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    if (.not. allow_empty(b, b%st_materials, 'materials', loc, errors)) return
    b%st_materials = COLL_EMPTY
  end subroutine builder_materials_empty

  ! ==========================================================================
  ! sections
  ! ==========================================================================

  subroutine builder_add_section(b, value, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(section_t), intent(in) :: value
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    type(section_t), allocatable :: tmp(:)
    if (.not. allow_add(b, b%st_sections, 'sections', b%n_sections + 1_int32, &
                        loc, errors)) return
    if (.not. allocated(b%buf_sections)) then
      allocate(b%buf_sections(SEED_CAPACITY))
    else if (b%n_sections >= int(size(b%buf_sections), int32)) then
      allocate(tmp(2 * size(b%buf_sections)))
      tmp(1:b%n_sections) = b%buf_sections(1:b%n_sections)
      call move_alloc(tmp, b%buf_sections)
    end if
    b%n_sections = b%n_sections + 1_int32
    b%buf_sections(b%n_sections) = value
    b%st_sections = COLL_FILLED
  end subroutine builder_add_section

  subroutine builder_sections_empty(b, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    if (.not. allow_empty(b, b%st_sections, 'sections', loc, errors)) return
    b%st_sections = COLL_EMPTY
  end subroutine builder_sections_empty

  ! ==========================================================================
  ! amplitudes
  ! ==========================================================================

  subroutine builder_add_amplitude(b, value, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(amplitude_t), intent(in) :: value
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    type(amplitude_t), allocatable :: tmp(:)
    if (.not. allow_add(b, b%st_amplitudes, &
                        'amplitudes', b%n_amplitudes + 1_int32, loc, errors)) return
    if (.not. allocated(b%buf_amplitudes)) then
      allocate(b%buf_amplitudes(SEED_CAPACITY))
    else if (b%n_amplitudes >= int(size(b%buf_amplitudes), int32)) then
      allocate(tmp(2 * size(b%buf_amplitudes)))
      tmp(1:b%n_amplitudes) = b%buf_amplitudes(1:b%n_amplitudes)
      call move_alloc(tmp, b%buf_amplitudes)
    end if
    b%n_amplitudes = b%n_amplitudes + 1_int32
    b%buf_amplitudes(b%n_amplitudes) = value
    b%st_amplitudes = COLL_FILLED
  end subroutine builder_add_amplitude

  subroutine builder_amplitudes_empty(b, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    if (.not. allow_empty(b, b%st_amplitudes, 'amplitudes', loc, errors)) return
    b%st_amplitudes = COLL_EMPTY
  end subroutine builder_amplitudes_empty

  ! ==========================================================================
  ! steps
  ! ==========================================================================

  subroutine builder_add_step(b, value, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(step_t), intent(in) :: value
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    type(step_t), allocatable :: tmp(:)
    if (.not. allow_add(b, b%st_steps, 'steps', b%n_steps + 1_int32, &
                        loc, errors)) return
    if (.not. allocated(b%buf_steps)) then
      allocate(b%buf_steps(SEED_CAPACITY))
    else if (b%n_steps >= int(size(b%buf_steps), int32)) then
      allocate(tmp(2 * size(b%buf_steps)))
      tmp(1:b%n_steps) = b%buf_steps(1:b%n_steps)
      call move_alloc(tmp, b%buf_steps)
    end if
    b%n_steps = b%n_steps + 1_int32
    b%buf_steps(b%n_steps) = value
    b%st_steps = COLL_FILLED
  end subroutine builder_add_step

  subroutine builder_steps_empty(b, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    if (.not. allow_empty(b, b%st_steps, 'steps', loc, errors)) return
    b%st_steps = COLL_EMPTY
  end subroutine builder_steps_empty

  ! ==========================================================================
  ! amplitude sub-builder
  ! ==========================================================================

  subroutine builder_amplitude_begin(ab)
    type(amplitude_builder_t), intent(out) :: ab
    ab%begun = .true.
  end subroutine builder_amplitude_begin

  subroutine builder_amplitude_set_name(b, ab, value, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(amplitude_builder_t), intent(inout) :: ab
    character(len=*), intent(in) :: value
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    if (.not. allow_sub(b, ab%begun, 'amplitudes[]', loc, errors)) return
    if (ab%has_name) then
      call fail(b, errors, 'builder.duplicate_singleton', 'amplitudes[]', 'name', &
                'this amplitude already has a name', 'one declaration', &
                'a second declaration', loc)
      return
    end if
    call opt_set(ab%name, value)
    ab%has_name = .true.
  end subroutine builder_amplitude_set_name

  subroutine builder_amplitude_set_type(b, ab, value, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(amplitude_builder_t), intent(inout) :: ab
    character(len=*), intent(in) :: value
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    if (.not. allow_sub(b, ab%begun, 'amplitudes[]', loc, errors)) return
    if (ab%has_type) then
      call fail(b, errors, 'builder.duplicate_singleton', 'amplitudes[]', 'type', &
                'this amplitude already has a type', 'one declaration', &
                'a second declaration', loc)
      return
    end if
    call opt_set(ab%type, value)
    ab%has_type = .true.
  end subroutine builder_amplitude_set_type

  subroutine builder_amplitude_add_point(b, ab, value, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(amplitude_builder_t), intent(inout) :: ab
    type(amplitude_point_t), intent(in) :: value
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    type(amplitude_point_t), allocatable :: tmp(:)
    if (.not. allow_sub(b, ab%begun, 'amplitudes[].points', loc, errors)) return
    if (ab%st_points == COLL_EMPTY) then
      call fail(b, errors, 'builder.add_after_empty', 'amplitudes[].points', '', &
                'this collection was already declared explicitly empty; it cannot ' // &
                'also receive entries', 'no entry', 'an added entry', loc)
      return
    end if
    if (.not. allocated(ab%buf_points)) then
      allocate(ab%buf_points(SEED_CAPACITY))
    else if (ab%n_points >= int(size(ab%buf_points), int32)) then
      allocate(tmp(2 * size(ab%buf_points)))
      tmp(1:ab%n_points) = ab%buf_points(1:ab%n_points)
      call move_alloc(tmp, ab%buf_points)
    end if
    ab%n_points = ab%n_points + 1_int32
    ab%buf_points(ab%n_points) = value
    ab%st_points = COLL_FILLED
  end subroutine builder_amplitude_add_point

  subroutine builder_amplitude_points_empty(b, ab, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(amplitude_builder_t), intent(inout) :: ab
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    if (.not. allow_sub(b, ab%begun, 'amplitudes[].points', loc, errors)) return
    if (ab%st_points == COLL_FILLED) then
      call fail(b, errors, 'builder.empty_after_add', 'amplitudes[].points', '', &
                'this collection already has entries and cannot be declared ' // &
                'explicitly empty', 'no entry', 'at least one entry', loc)
      return
    end if
    ab%st_points = COLL_EMPTY
  end subroutine builder_amplitude_points_empty

  ! Materialises the amplitude value. `value` is only written on success. The
  ! sub-builder is reset either way.
  subroutine builder_amplitude_finish(b, ab, value, loc, errors, ok)
    type(problem_builder_t), intent(inout) :: b
    type(amplitude_builder_t), intent(inout) :: ab
    type(amplitude_t), intent(inout) :: value
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    logical, intent(out), optional :: ok
    type(amplitude_t) :: candidate
    logical :: good

    good = allow_sub(b, ab%begun, 'amplitudes[]', loc, errors)
    if (good) then
      candidate%name = ab%name
      candidate%type = ab%type
      select case (ab%st_points)
      case (COLL_EMPTY);  allocate(candidate%points(0))
      case (COLL_FILLED); allocate(candidate%points(ab%n_points))
                          candidate%points(:) = ab%buf_points(1:ab%n_points)
      end select
      value = candidate
    end if
    if (present(ok)) ok = good
    call amplitude_reset(ab)
  end subroutine builder_amplitude_finish

  subroutine amplitude_reset(ab)
    type(amplitude_builder_t), intent(out) :: ab
    ab%begun = .false.
  end subroutine amplitude_reset

  ! ==========================================================================
  ! step sub-builder
  ! ==========================================================================

  subroutine builder_step_begin(sb)
    type(step_builder_t), intent(out) :: sb
    sb%begun = .true.
  end subroutine builder_step_begin

  subroutine builder_step_set_procedure(b, sb, value, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(step_builder_t), intent(inout) :: sb
    character(len=*), intent(in) :: value
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    if (.not. allow_sub(b, sb%begun, 'steps[]', loc, errors)) return
    if (sb%has_procedure) then
      call fail(b, errors, 'builder.duplicate_singleton', 'steps[]', 'procedure', &
                'this step already has a procedure', 'one declaration', &
                'a second declaration', loc)
      return
    end if
    call opt_set(sb%procedure_name, value)
    sb%has_procedure = .true.
  end subroutine builder_step_set_procedure

  subroutine builder_step_set_load_mode(b, sb, value, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(step_builder_t), intent(inout) :: sb
    character(len=*), intent(in) :: value
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    if (.not. allow_sub(b, sb%begun, 'steps[]', loc, errors)) return
    if (sb%has_load_mode) then
      call fail(b, errors, 'builder.duplicate_singleton', 'steps[]', 'load_mode', &
                'this step already has a load mode', 'one declaration', &
                'a second declaration', loc)
      return
    end if
    call opt_set(sb%load_mode, value)
    sb%has_load_mode = .true.
  end subroutine builder_step_set_load_mode

  subroutine builder_step_set_controls(b, sb, value, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(step_builder_t), intent(inout) :: sb
    type(controls_t), intent(in) :: value
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    if (.not. allow_sub(b, sb%begun, 'steps[].controls', loc, errors)) return
    if (sb%has_controls) then
      call fail(b, errors, 'builder.duplicate_singleton', 'steps[].controls', '', &
                'this step already has controls', 'one declaration', &
                'a second declaration', loc)
      return
    end if
    sb%controls = value
    sb%has_controls = .true.
  end subroutine builder_step_set_controls

  subroutine builder_step_set_load(b, sb, value, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(step_builder_t), intent(inout) :: sb
    type(load_t), intent(in) :: value
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    if (.not. allow_sub(b, sb%begun, 'steps[].load', loc, errors)) return
    if (sb%has_load) then
      call fail(b, errors, 'builder.duplicate_singleton', 'steps[].load', '', &
                'this step already has a load', 'one declaration', &
                'a second declaration', loc)
      return
    end if
    sb%load = value
    sb%has_load = .true.
  end subroutine builder_step_set_load

  subroutine builder_step_set_output(b, sb, value, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(step_builder_t), intent(inout) :: sb
    type(output_t), intent(in) :: value
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    if (.not. allow_sub(b, sb%begun, 'steps[].output', loc, errors)) return
    if (sb%has_output) then
      call fail(b, errors, 'builder.duplicate_singleton', 'steps[].output', '', &
                'this step already has an output request', 'one declaration', &
                'a second declaration', loc)
      return
    end if
    sb%output = value
    sb%has_output = .true.
  end subroutine builder_step_set_output

  subroutine builder_step_add_boundary(b, sb, value, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(step_builder_t), intent(inout) :: sb
    type(boundary_t), intent(in) :: value
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    type(boundary_t), allocatable :: tmp(:)
    if (.not. allow_sub(b, sb%begun, 'steps[].boundary', loc, errors)) return
    if (sb%st_boundary == COLL_EMPTY) then
      call fail(b, errors, 'builder.add_after_empty', 'steps[].boundary', '', &
                'this collection was already declared explicitly empty; it cannot ' // &
                'also receive entries', 'no entry', 'an added entry', loc)
      return
    end if
    if (.not. allocated(sb%buf_boundary)) then
      allocate(sb%buf_boundary(SEED_CAPACITY))
    else if (sb%n_boundary >= int(size(sb%buf_boundary), int32)) then
      allocate(tmp(2 * size(sb%buf_boundary)))
      tmp(1:sb%n_boundary) = sb%buf_boundary(1:sb%n_boundary)
      call move_alloc(tmp, sb%buf_boundary)
    end if
    sb%n_boundary = sb%n_boundary + 1_int32
    sb%buf_boundary(sb%n_boundary) = value
    sb%st_boundary = COLL_FILLED
  end subroutine builder_step_add_boundary

  subroutine builder_step_boundary_empty(b, sb, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(step_builder_t), intent(inout) :: sb
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    if (.not. allow_sub(b, sb%begun, 'steps[].boundary', loc, errors)) return
    if (sb%st_boundary == COLL_FILLED) then
      call fail(b, errors, 'builder.empty_after_add', 'steps[].boundary', '', &
                'this collection already has entries and cannot be declared ' // &
                'explicitly empty', 'no entry', 'at least one entry', loc)
      return
    end if
    sb%st_boundary = COLL_EMPTY
  end subroutine builder_step_boundary_empty

  subroutine builder_step_add_activation(b, sb, value, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(step_builder_t), intent(inout) :: sb
    type(activation_t), intent(in) :: value
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    type(activation_t), allocatable :: tmp(:)
    if (.not. allow_sub(b, sb%begun, 'steps[].activation', loc, errors)) return
    if (sb%st_activation == COLL_EMPTY) then
      call fail(b, errors, 'builder.add_after_empty', 'steps[].activation', '', &
                'this collection was already declared explicitly empty; it cannot ' // &
                'also receive entries', 'no entry', 'an added entry', loc)
      return
    end if
    if (.not. allocated(sb%buf_activation)) then
      allocate(sb%buf_activation(SEED_CAPACITY))
    else if (sb%n_activation >= int(size(sb%buf_activation), int32)) then
      allocate(tmp(2 * size(sb%buf_activation)))
      tmp(1:sb%n_activation) = sb%buf_activation(1:sb%n_activation)
      call move_alloc(tmp, sb%buf_activation)
    end if
    sb%n_activation = sb%n_activation + 1_int32
    sb%buf_activation(sb%n_activation) = value
    sb%st_activation = COLL_FILLED
  end subroutine builder_step_add_activation

  subroutine builder_step_activation_empty(b, sb, loc, errors)
    type(problem_builder_t), intent(inout) :: b
    type(step_builder_t), intent(inout) :: sb
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    if (.not. allow_sub(b, sb%begun, 'steps[].activation', loc, errors)) return
    if (sb%st_activation == COLL_FILLED) then
      call fail(b, errors, 'builder.empty_after_add', 'steps[].activation', '', &
                'this collection already has entries and cannot be declared ' // &
                'explicitly empty', 'no entry', 'at least one entry', loc)
      return
    end if
    sb%st_activation = COLL_EMPTY
  end subroutine builder_step_activation_empty

  ! Materialises the step value. `value` is only written on success. The
  ! sub-builder is reset either way.
  subroutine builder_step_finish(b, sb, value, loc, errors, ok)
    type(problem_builder_t), intent(inout) :: b
    type(step_builder_t), intent(inout) :: sb
    type(step_t), intent(inout) :: value
    type(source_location_t), intent(in) :: loc
    type(problem_errors_t), intent(inout) :: errors
    logical, intent(out), optional :: ok
    type(step_t) :: candidate
    logical :: good

    good = allow_sub(b, sb%begun, 'steps[]', loc, errors)
    if (good) then
      candidate%procedure = sb%procedure_name
      candidate%load_mode = sb%load_mode
      candidate%controls = sb%controls
      candidate%load = sb%load
      candidate%output = sb%output
      select case (sb%st_boundary)
      case (COLL_EMPTY);  allocate(candidate%boundary(0))
      case (COLL_FILLED); allocate(candidate%boundary(sb%n_boundary))
                          candidate%boundary(:) = sb%buf_boundary(1:sb%n_boundary)
      end select
      select case (sb%st_activation)
      case (COLL_EMPTY);  allocate(candidate%activation(0))
      case (COLL_FILLED); allocate(candidate%activation(sb%n_activation))
                          candidate%activation(:) = sb%buf_activation(1:sb%n_activation)
      end select
      value = candidate
    end if
    if (present(ok)) ok = good
    call step_reset(sb)
  end subroutine builder_step_finish

  subroutine step_reset(sb)
    type(step_builder_t), intent(out) :: sb
    sb%begun = .false.
  end subroutine step_reset

end module yl_problem_builder
