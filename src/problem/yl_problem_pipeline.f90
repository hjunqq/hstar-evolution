! yl_problem_pipeline -- the M3 input pipeline: normalize, validate, capability gate,
! finalize.
!
! Scope (.ccg/tasks/m3-02-normalize-validate-finalize/plan.md deliverable 3,
! analysis.md rulings, analysis-claude.md sections 1-4, analysis-codex.md section 2)
!   ONE public entry point, prepare_problem. The four stages are module PRIVATE, so
!   the barrier order cannot be bypassed through the public API: there is no way for a
!   caller to run the capability gate on a draft that has not been validated, or to
!   reach finalize on a draft that failed normalize.
!
!   No I/O, no parsing, no global state, no process exit. The draft arrives already
!   assembled (yl_problem_builder for the M4 adapter and the M5 reader, or a self-test)
!   and the findings leave through the caller's problem_errors_t accumulator.
!
! Stage barriers versus defect accumulation
!   BETWEEN stages the pipeline stops at the first stage that produced a finding: a
!   dangling material reference makes every capability answer about that material
!   meaningless, so running the gate anyway would report defects that are consequences
!   rather than causes. WITHIN a stage every independent defect is accumulated: a draft
!   with three missing required fields reports three findings in one pass, never one at
!   a time. The barrier is observed by counting the accumulator before and after the
!   stage, not by errors%any(), so a caller may hand in an accumulator that already
!   carries findings from the reader without the pipeline mistaking them for its own.
!
! Transaction discipline (docs/06 row T01, ADR-0002)
!   `draft` is intent(in): the pipeline physically cannot modify the caller's input, so
!   "the draft is byte-identical after a failure" is a property of the interface rather
!   than of the control flow. The two published outputs, `problem` and `manifest`, are
!   allocatable and intent(inout): every stage builds a private candidate and the pair
!   is transferred with move_alloc only after finalize has succeeded in full. A failing
!   run therefore leaves a previously published problem and its manifest exactly as they
!   were -- allocation status and every `has` flag included -- and the immediately
!   following legal draft succeeds in the same process.
!
!   The two outputs move together in adjacent statements at the end of finalize, so a
!   caller can never observe a new problem beside a stale manifest.
!
! What each stage may do
!   normalize   representation only: trim and upper-case canonical text (N1), agree the
!               elset and section arities (N4), fill the element-to-elset back reference
!               (N6). It never allocates a collection the author left unset (N5), never
!               supplies a default and never computes a count.
!   validate    semantics across objects: requiredness, dangling and duplicate
!               references, empty collections, arity agreement, physical admissibility,
!               set-key well-formedness (V24), element-set membership (V25) and the
!               declared-count agreement checks (V21, V22).
!   gate        support only: every value is read against the ONE capability table in
!               yl_problem_profile. This module holds no copy of that table; it names
!               capability items and asks the profile module for the expected value, so
!               the table exists exactly once in the repository.
!   finalize    derivation and defaults: the six ProblemState index_map rows and the
!               nstre profile default, each recorded in the manifest with its rule, its
!               inputs and its value, plus the eight declared-count comparisons recorded
!               as `check` entries so that a PASSING check stays visible as evidence.
!
! Deliberately not implemented, and why
!   Each of the following was ruled out because no counter-example can make it fire at
!   M3-02; shipping them would add a gate that cannot fail, which is the defect this
!   milestone exists to stop (plan.md, the "not implemented" list):
!     * `case.units == SI` -- units are @m5-only and unset on the legacy path.
!     * V14, the explicitly-empty gravity check -- "no gravity" is still encoded as
!       ordinal 0 in the legacy shape, so the explicit-empty state is unreachable.
!     * the restart and load_mode capability items -- no constructible counter-example,
!       and no M3-02 consumer respectively.
!     * V23 and the derived.dof.cdofn / derived.dof.lcdofn rows -- they need the DOF
!       activation table, which no ProblemState component carries.
!     * derived.counts.ndofix -- defined over the RuntimeState renumbering, so M3-03.
!     * the ten declared counts with no collection behind them (runblks, npoinb,
!       nphase, nrfields, dof_count, dof_list, nblks, nsmat, mdofn, active_flags):
!       there is nothing to derive them from, so no agreement check exists.
!   The consequence for finalize is that seven of the ten rule-derived rows are in
!   scope (six index_map plus the one legacy_default), not ten: the seventh index_map
!   row is lcdofn and the two count rows are cdofn and ndofix, all three excluded above.
!
! Declared counts
!   The eight checkable and the ten must-be-zero declared counts are deck redundancies:
!   the deck states them and the modern model derives them from objects. No component
!   of problem_state_t holds them -- correctly, since a count is never stored as a field
!   -- so they arrive through the optional `declared` argument as declared_counts_t.
!   When it is absent nothing was declared and no comparison is possible; when a member
!   of it is unset that single count was not declared and only that comparison is
!   skipped. A declared value is never copied into the model; it is only ever compared
!   against the value the objects yield.
module yl_problem_pipeline

  use iso_fortran_env, only: int32, real64
  use yl_problem_optional, only: opt_int, opt_text, opt_logical, &
                                 opt_set, opt_get, opt_clear, opt_is_set, opt_value_or
  use yl_problem_types, only: problem_state_t, elset_t, nset_t
  use yl_problem_errors, only: problem_error_t, problem_errors_t, make_problem_error, &
                               PE_MISSING_FIELD, PE_DANGLING_REF, PE_DUPLICATE_REF, &
                               PE_EMPTY_COLLECTION, PE_COUNT_MISMATCH, PE_INVALID_INPUT, &
                               PE_UNSUPPORTED, PE_INTERNAL, PE_STAGE_NORMALIZE, PE_STAGE_VALIDATE, &
                               PE_STAGE_CAPABILITY, PE_STAGE_FINALIZE
  use yl_problem_profile, only: capability_item_t, capability_count, capability_find, capability_row, &
                                capability_expect_int, capability_expect_text, &
                                capability_expect_logical, profile_lookup_int, &
                                CAPABILITY_TAG, PROFILE_ID, PROFILE_VERSION, PROFILE_TAG
  use yl_problem_manifest, only: manifest_t, manifest_reset, manifest_add_derived, manifest_add_default, &
                                 manifest_add_check, manifest_is_valid, manifest_error, &
                                 mv_i32, mv_i32_list, mt_list, &
                                 MANIFEST_RULE_INDEX_MAP

  implicit none
  private

  public :: declared_counts_t, prepare_problem
  ! Capability-row coverage, for the self-test. The unit of coverage is the capability
  ! ROW, never the rule id; see the block comment above capability_row_count.
  public :: capability_row_count, capability_row_id, capability_row_exercised
  public :: capability_first_uncovered

  ! The one element kind this build knows the connectivity length of. The value is NOT
  ! a capability constant -- the capability table says which kinds are supported, this
  ! says how many nodes a kind has -- so it is not a second copy of that table.
  integer(int32), parameter :: ELEMENT_KIND_Q4 = 5_int32
  integer(int32), parameter :: ELEMENT_NODES_Q4 = 4_int32

  ! The CAE key of the one M3-02 default profile row.
  character(len=*), parameter :: KEY_STRESS_COMPONENTS = 'plane_strain.stress_components'

  ! --- rules versus invariants ------------------------------------------------
  ! A RULE is a statement about the user's model. It is reachable by construction,
  ! it carries a counter-example in the self-test matrix, its rule id is one of
  ! N*, V*, G* or F-*, and its exit class is 2 or 3 because the model is at fault.
  !
  ! An INVARIANT is a statement about THIS CODE. It fires only if an earlier stage
  ! failed to do its job, so no draft can reach it and it has no counter-example.
  !
  ! Two kinds, and the difference matters because one of them expires. An invariant
  ! unreachable BY CONSTRUCTION stays unreachable however the supported combination
  ! grows: INV-ELSET-SET, INV-MANIFEST and INV-PROFILE-KEY are all of this kind. An
  ! invariant unreachable only BECAUSE OF A CAPABILITY LIMIT becomes reachable the day
  ! that limit is raised, and is really a deferred rule wearing an assertion's clothes:
  ! INV-EMPTY-DERIVED is the one of this kind, held partly by V24, V25 and the finalize
  ! early return, and partly by the gate allowing exactly one section. Each INV- comment
  ! below says which kind it is, so nobody has to re-derive it.
  ! Its rule id begins INV- so that a reader scanning rule ids can tell the two
  ! apart without consulting the docs, and it is excluded from the rule-coverage
  ! count. It is kept rather than deleted because the alternative to an unreachable
  ! assertion is a silent wrong answer: without INV-ELSET-SET, for instance,
  ! finalize would quietly write element kind 0 into the model if the N6 or V8
  ! invariant ever broke. An unreachable assertion is only harmful when it is
  ! mistaken for a gate that passed, which the naming and the docs prevent.
  !
  ! The internal-fault code comes from yl_problem_errors, which also maps it to exit
  ! class 6 in exit_class_for_code. Because that mapping exists, nothing here passes an
  ! exit class explicitly: every finding in this file derives its class from its code,
  ! with no exception, so there is one place the classification can be wrong.

  ! --- declared counts --------------------------------------------------------
  ! The deck's redundant count declarations, in CAE vocabulary. Every member is an
  ! explicit-absence wrapper or an allocatable array, so "the deck did not declare this
  ! count" and "the deck declared it as zero" stay distinct: the second is checkable
  ! evidence, the first is nothing at all.
  !
  ! Group one, the eight checkable counts: each has a collection behind it, so the
  ! pipeline derives the value and compares (V21, COUNT_MISMATCH on disagreement).
  !
  ! Group two, the ten counts for load and thermal kinds that this build does not carry
  ! at all: ProblemState has no collection to derive them from, so the only honest rule
  ! is that a deck on this path must declare each of them as zero (V22, UNSUPPORTED).
  type :: declared_counts_t
    ! -- checkable (8) --
    type(opt_int) :: node_count                        ! derived.counts.npoin
    type(opt_int) :: element_count                     ! derived.counts.nelem
    type(opt_int) :: material_count                    ! derived.counts.nmats
    type(opt_int) :: section_count                     ! derived.counts.ngroup
    integer(int32), allocatable :: elset_size(:)       ! sections.elset_size, one per section
    type(opt_int) :: amplitude_count                   ! derived.counts.ntcurve
    integer(int32), allocatable :: amplitude_points(:) ! amplitudes.points.count, one per amplitude
    type(opt_int) :: nset_count                        ! derived.counts.nfixsets
    ! -- must be zero (10) --
    type(opt_int) :: point_load_group_count            ! derived.counts.nplgroup
    type(opt_int) :: edge_count                        ! derived.counts.nedge
    type(opt_int) :: edge_load_group_count             ! derived.counts.edge_load_group
    type(opt_int) :: edge_load_element_group_count     ! derived.counts.delgroup
    type(opt_int) :: beam_load_count                   ! derived.counts.nbeamload
    type(opt_int) :: plate_load_count                  ! derived.counts.nplateload
    type(opt_int) :: temperature_surface_count         ! derived.counts.ntemp_surface
    type(opt_int) :: temperature_edge_count            ! derived.counts.ntedge
    type(opt_int) :: temperature_element_group_count   ! derived.counts.ntelgroup
    type(opt_int) :: pipe_count                        ! derived.counts.npipe
  end type declared_counts_t

contains

  ! ==========================================================================
  ! the public entry point
  ! ==========================================================================

  ! Run the four stages in their fixed order over `draft` and publish the finished
  ! problem and its derivation manifest.
  !
  !   draft      the assembled input. intent(in): the pipeline cannot modify it.
  !   profile_in the requested default-profile tag, e.g. 'static-q4-si/1'. It is
  !              checked against the compiled profile so that a caller asking for a
  !              profile this build does not carry is told so, rather than silently
  !              receiving another profile's defaults.
  !   problem    the finished problem. Untouched unless the whole run succeeds.
  !   manifest   the derivation manifest. Moves in the same breath as `problem`.
  !   errors     findings are APPENDED; the caller's earlier findings are preserved and
  !              are not mistaken for this run's.
  !   declared   the deck's redundant count declarations, when the reader captured any.
  !
  ! On success `problem` and `manifest` are both allocated and no finding was added.
  ! On failure neither output was touched and at least one finding was added.
  subroutine prepare_problem(draft, profile_in, problem, manifest, errors, declared)
    type(problem_state_t), intent(in) :: draft
    character(len=*), intent(in) :: profile_in
    type(problem_state_t), allocatable, intent(inout) :: problem
    type(manifest_t), allocatable, intent(inout) :: manifest
    type(problem_errors_t), intent(inout) :: errors
    type(declared_counts_t), intent(in), optional :: declared

    type(problem_state_t), allocatable :: normalized
    integer :: mark

    ! The profile selector is a precondition of the whole run, not of one stage: a
    ! wrong tag would make every default and every gate answer belong to a profile the
    ! caller did not ask for.
    if (trim(profile_in) /= PROFILE_TAG) then
      call raise(errors, PE_INVALID_INPUT, PE_STAGE_NORMALIZE, 'P0', 'profile', &
                 message='requested profile "'//trim(profile_in)// &
                 '" is not the profile compiled into this build', &
                 field='id', actual=trim(profile_in), expected=PROFILE_TAG)
      return
    end if

    mark = errors%count()
    call normalize_problem(draft, normalized, errors)
    if (errors%count() > mark) return
    if (.not. allocated(normalized)) return

    mark = errors%count()
    call validate_problem(normalized, declared, errors)
    if (errors%count() > mark) return

    mark = errors%count()
    call capability_gate(normalized, errors)
    if (errors%count() > mark) return

    call finalize_problem(normalized, declared, problem, manifest, errors)
  end subroutine prepare_problem

  ! ==========================================================================
  ! stage 1 -- normalize
  ! ==========================================================================

  ! Representation canonicalisation on a private candidate.
  !
  !   N1 trim every set text and upper-case the enum-valued ones.
  !   N4 the elset collection and the section collection must have equal length when
  !      both are allocated; a set per section is what the positional keying means.
  !   N5 a collection the author left unset stays unset. This is a PROHIBITION: there
  !      is no allocate in this stage, which is what the self-test observes.
  !   N6 an element whose owning set was not stated is filled from elset membership.
  !      Membership in two sets is a defect, and so is membership in none once the sets
  !      exist: the back reference was asked for and is not derivable.
  !
  ! The candidate is published only when the stage adds no finding, so a draft that
  ! fails N4 leaves the caller with no normalized state at all rather than a partly
  ! canonicalised one.
  subroutine normalize_problem(draft, normalized, errors)
    type(problem_state_t), intent(in) :: draft
    type(problem_state_t), allocatable, intent(inout) :: normalized
    type(problem_errors_t), intent(inout) :: errors

    type(problem_state_t), allocatable :: candidate
    integer :: mark

    mark = errors%count()
    allocate (candidate, source=draft)

    call canonicalize_text(candidate)
    call check_set_arity(candidate, errors)
    call fill_element_set_reference(candidate, errors)

    if (errors%count() > mark) return
    call move_alloc(candidate, normalized)
  end subroutine normalize_problem

  ! N1. Trim is applied to every set text; upper-casing only to the enum-valued fields
  ! listed in analysis-claude.md section 1, so that an authored NAME keeps its case and
  ! an authored KEYWORD is compared canonical against canonical by the gate.
  subroutine canonicalize_text(state)
    type(problem_state_t), intent(inout) :: state
    integer :: i

    call canon(state%case%name, .false.)
    call canon(state%case%units, .true.)
    call canon(state%interactions%absorbing%type, .false.)
    call canon(state%solver%linear, .true.)

    if (allocated(state%materials)) then
      do i = 1, size(state%materials)
        call canon(state%materials(i)%name, .false.)
        call canon(state%materials(i)%phase, .false.)
        call canon(state%materials(i)%kind, .true.)
        call canon(state%materials(i)%model, .true.)
      end do
    end if

    if (allocated(state%sections)) then
      do i = 1, size(state%sections)
        call canon(state%sections(i)%name, .false.)
        call canon(state%sections(i)%element, .true.)
        call canon(state%sections(i)%class, .true.)
        call canon(state%sections(i)%fields, .true.)
        call canon(state%sections(i)%formulation, .true.)
        call canon(state%sections(i)%special, .true.)
      end do
    end if

    if (allocated(state%amplitudes)) then
      do i = 1, size(state%amplitudes)
        call canon(state%amplitudes(i)%name, .false.)
        call canon(state%amplitudes(i)%type, .false.)
      end do
    end if

    if (allocated(state%steps)) then
      do i = 1, size(state%steps)
        call canon(state%steps(i)%procedure, .true.)
        call canon(state%steps(i)%load_mode, .true.)
        call canon(state%steps(i)%output%format, .true.)
      end do
    end if
  end subroutine canonicalize_text

  ! N4. Sets are keyed positionally by section, so two collections of different length
  ! cannot both be right and there is no rule that says which one to believe.
  subroutine check_set_arity(state, errors)
    type(problem_state_t), intent(in) :: state
    type(problem_errors_t), intent(inout) :: errors

    if (.not. allocated(state%mesh%elsets)) return
    if (.not. allocated(state%sections)) return
    if (size(state%mesh%elsets) == size(state%sections)) return

    call raise(errors, PE_INVALID_INPUT, PE_STAGE_NORMALIZE, 'N4', 'mesh.elsets', &
               message=itoa(size(state%mesh%elsets))//' element sets for '// &
               itoa(size(state%sections))//' sections; sets are keyed by section', &
               actual=itoa(size(state%mesh%elsets)), expected=itoa(size(state%sections)))
  end subroutine check_set_arity

  ! N6. The inverse of the mesh.elements.group index map: given the sets, say which set
  ! each element belongs to. Only elements whose owning set is unset are touched, so a
  ! reader that already knows the answer is never overruled.
  subroutine fill_element_set_reference(state, errors)
    type(problem_state_t), intent(inout) :: state
    type(problem_errors_t), intent(inout) :: errors

    integer :: e, s, k, first, second, hits
    integer(int32) :: eid
    logical :: found

    if (.not. allocated(state%mesh%elements)) return
    if (.not. allocated(state%mesh%elsets)) return

    do e = 1, size(state%mesh%elements)
      if (opt_is_set(state%mesh%elements(e)%elset)) cycle
      call opt_get(state%mesh%elements(e)%id, eid, found)
      if (.not. found) cycle          ! a missing element id is V1's finding, not N6's

      hits = 0
      first = 0
      second = 0
      do s = 1, size(state%mesh%elsets)
        if (.not. allocated(state%mesh%elsets(s)%elements)) cycle
        do k = 1, size(state%mesh%elsets(s)%elements)
          if (state%mesh%elsets(s)%elements(k) /= eid) cycle
          hits = hits + 1
          if (hits == 1) then
            first = s
          else if (hits == 2) then
            second = s
          end if
          exit
        end do
      end do

      if (hits == 1) then
        call opt_set(state%mesh%elements(e)%elset, int(first, int32))
      else if (hits >= 2) then
        call raise(errors, PE_INVALID_INPUT, PE_STAGE_NORMALIZE, 'N6', 'mesh.elements', &
                   idx=int(e, int32), field='elset', &
                   message='element '//itoa(int(eid))//' is in element sets '//itoa(first)// &
                   ' and '//itoa(second)//'; an element belongs to exactly one set', &
                   actual=itoa(hits)//' sets', expected='1 set')
      else
        call raise(errors, PE_INVALID_INPUT, PE_STAGE_NORMALIZE, 'N6', 'mesh.elements', &
                   idx=int(e, int32), field='elset', &
                   message='element '//itoa(int(eid))//' is in no element set, so its owning '// &
                   'set cannot be derived', &
                   actual='0 sets', expected='1 set')
      end if
    end do
  end subroutine fill_element_set_reference

  ! ==========================================================================
  ! stage 2 -- validate
  ! ==========================================================================

  ! Every independent defect in one pass. The sub-passes are ordered so that a rule
  ! reading a reference only runs where the reference exists; an unresolved reference
  ! suppresses the checks that DEPEND on it and nothing else.
  subroutine validate_problem(state, declared, errors)
    type(problem_state_t), intent(in) :: state
    type(declared_counts_t), intent(in), optional :: declared
    type(problem_errors_t), intent(inout) :: errors

    call validate_required(state, errors)             ! V1
    call validate_references(state, errors)           ! V2 V3 V4 V5 V18
    call validate_duplicates(state, errors)           ! V6 V7
    call validate_presence(state, errors)             ! V8 V9 V20
    call validate_arities(state, errors)              ! V10 V11 V12 V13
    call validate_semantics(state, errors)            ! V16 V17 V19
    call validate_set_keys(state, errors)             ! V24
    call validate_elset_members(state, errors)        ! V25
    call validate_declared(state, declared, errors)   ! V21 V22
  end subroutine validate_problem

  ! V1. The fields without which no later rule can say anything. Identity fields are
  ! part of the set because V2 and V4 to V7 are all reference or uniqueness rules over
  ! them: an unset id is not a value they can compare.
  subroutine validate_required(state, errors)
    type(problem_state_t), intent(in) :: state
    type(problem_errors_t), intent(inout) :: errors
    integer :: i

    call need(errors, opt_is_set(state%mesh%dimension), 'V1', 'mesh', 'dimension')
    call need(errors, opt_is_set(state%solver%linear), 'V1', 'solver', 'linear')

    if (allocated(state%mesh%nodes)) then
      do i = 1, size(state%mesh%nodes)
        call need(errors, opt_is_set(state%mesh%nodes(i)%id), 'V1', 'mesh.nodes', 'id', i)
      end do
    end if

    if (allocated(state%mesh%elements)) then
      do i = 1, size(state%mesh%elements)
        call need(errors, opt_is_set(state%mesh%elements(i)%id), 'V1', 'mesh.elements', 'id', i)
      end do
    end if

    if (allocated(state%materials)) then
      do i = 1, size(state%materials)
        call need(errors, opt_is_set(state%materials(i)%id), 'V1', 'materials', 'id', i)
        call need(errors, opt_is_set(state%materials(i)%E), 'V1', 'materials', 'E', i)
        call need(errors, opt_is_set(state%materials(i)%nu), 'V1', 'materials', 'nu', i)
      end do
    end if

    if (allocated(state%sections)) then
      do i = 1, size(state%sections)
        call need(errors, opt_is_set(state%sections(i)%element_kind), 'V1', 'sections', 'element_kind', i)
        call need(errors, opt_is_set(state%sections(i)%formulation), 'V1', 'sections', 'formulation', i)
      end do
    end if

    if (allocated(state%steps)) then
      do i = 1, size(state%steps)
        call need(errors, opt_is_set(state%steps(i)%procedure), 'V1', 'steps', 'procedure', i)
        call need(errors, opt_is_set(state%steps(i)%controls%increments), 'V1', &
                  'steps['//itoa(i)//'].controls', 'increments')
      end do
    end if
  end subroutine validate_required

  ! V2, V3, V4, V5, V18: every reference must name something that exists. Ordinal
  ! references (an amplitude position) are checked against the collection length; id
  ! references (a material id, a node id) are checked against the ids themselves.
  subroutine validate_references(state, errors)
    type(problem_state_t), intent(in) :: state
    type(problem_errors_t), intent(inout) :: errors

    integer(int32), allocatable :: node_ids(:), material_ids(:)
    integer :: i, k, n_amp
    integer(int32) :: v
    logical :: found

    call collect_node_ids(state, node_ids)
    call collect_material_ids(state, material_ids)
    n_amp = 0
    if (allocated(state%amplitudes)) n_amp = size(state%amplitudes)

    ! V2 -- section to material
    if (allocated(state%sections) .and. allocated(material_ids)) then
      do i = 1, size(state%sections)
        call opt_get(state%sections(i)%material, v, found)
        if (.not. found) cycle
        if (in_list(material_ids, v)) cycle
        call raise(errors, PE_DANGLING_REF, PE_STAGE_VALIDATE, 'V2', 'sections', &
                   idx=int(i, int32), field='material', &
                   message='material '//itoa(int(v))//' is not an id in materials[]', &
                   actual=itoa(int(v)), expected='an id in materials[]')
      end do
    end if

    ! V3 -- gravity amplitude ordinals. Ordinal 0 is the legacy "no gravity in this
    ! group" spelling; it is out of ADR-0002 compliance and is recorded as a known gap
    ! in the docs, but it is an accepted input here rather than a dangling reference.
    if (allocated(state%steps)) then
      do i = 1, size(state%steps)
        if (.not. allocated(state%steps(i)%load%gravity%amplitude)) cycle
        do k = 1, size(state%steps(i)%load%gravity%amplitude)
          v = state%steps(i)%load%gravity%amplitude(k)
          if (v >= 0_int32 .and. v <= int(n_amp, int32)) cycle
          call raise(errors, PE_DANGLING_REF, PE_STAGE_VALIDATE, 'V3', &
                     'steps['//itoa(i)//'].load.gravity', field='amplitude['//itoa(k)//']', &
                     message='amplitude '//itoa(int(v))//' is not one of the '//itoa(n_amp)// &
                     ' entries of amplitudes[]', &
                     actual=itoa(int(v)), expected='0..'//itoa(n_amp))
        end do
      end do
    end if

    ! V4 -- node set membership
    if (allocated(state%mesh%nsets) .and. allocated(node_ids)) then
      do i = 1, size(state%mesh%nsets)
        if (.not. allocated(state%mesh%nsets(i)%nodes)) cycle
        do k = 1, size(state%mesh%nsets(i)%nodes)
          v = state%mesh%nsets(i)%nodes(k)
          if (in_list(node_ids, v)) cycle
          call raise(errors, PE_DANGLING_REF, PE_STAGE_VALIDATE, 'V4', 'mesh.nsets', &
                     idx=int(i, int32), field='nodes['//itoa(k)//']', &
                     message='node '//itoa(int(v))//' is not an id in mesh.nodes[]', &
                     actual=itoa(int(v)), expected='an id in mesh.nodes[]')
        end do
      end do
    end if

    ! V5 -- connectivity
    if (allocated(state%mesh%elements) .and. allocated(node_ids)) then
      do i = 1, size(state%mesh%elements)
        if (.not. allocated(state%mesh%elements(i)%nodes)) cycle
        do k = 1, size(state%mesh%elements(i)%nodes)
          v = state%mesh%elements(i)%nodes(k)
          if (in_list(node_ids, v)) cycle
          call raise(errors, PE_DANGLING_REF, PE_STAGE_VALIDATE, 'V5', 'mesh.elements', &
                     idx=int(i, int32), field='nodes['//itoa(k)//']', &
                     message='node '//itoa(int(v))//' is not an id in mesh.nodes[]', &
                     actual=itoa(int(v)), expected='an id in mesh.nodes[]')
        end do
      end do
    end if

    ! V18 -- boundary to amplitude ordinal
    if (allocated(state%steps)) then
      do i = 1, size(state%steps)
        if (.not. allocated(state%steps(i)%boundary)) cycle
        do k = 1, size(state%steps(i)%boundary)
          call opt_get(state%steps(i)%boundary(k)%amplitude, v, found)
          if (.not. found) cycle
          if (v >= 0_int32 .and. v <= int(n_amp, int32)) cycle
          call raise(errors, PE_DANGLING_REF, PE_STAGE_VALIDATE, 'V18', &
                     'steps['//itoa(i)//'].boundary', idx=int(k, int32), field='amplitude', &
                     message='amplitude '//itoa(int(v))//' is not one of the '//itoa(n_amp)// &
                     ' entries of amplitudes[]', &
                     actual=itoa(int(v)), expected='0..'//itoa(n_amp))
        end do
      end do
    end if
  end subroutine validate_references

  ! V6 duplicate identity, V7 duplicate set membership.
  subroutine validate_duplicates(state, errors)
    type(problem_state_t), intent(in) :: state
    type(problem_errors_t), intent(inout) :: errors

    integer :: i, j, s, t, k, m
    integer(int32) :: a, b
    logical :: fa, fb
    character(len=:), allocatable :: na, nb

    if (allocated(state%mesh%nodes)) then
      do i = 2, size(state%mesh%nodes)
        call opt_get(state%mesh%nodes(i)%id, a, fa)
        if (.not. fa) cycle
        do j = 1, i - 1
          call opt_get(state%mesh%nodes(j)%id, b, fb)
          if (.not. fb) cycle
          if (a /= b) cycle
          call raise(errors, PE_DUPLICATE_REF, PE_STAGE_VALIDATE, 'V6', 'mesh.nodes', &
                     idx=int(i, int32), field='id', &
                     message='id '//itoa(int(a))//' is already used by mesh.nodes['//itoa(j)//']', &
                     actual=itoa(int(a)), expected='an unused id')
          exit
        end do
      end do
    end if

    if (allocated(state%mesh%elements)) then
      do i = 2, size(state%mesh%elements)
        call opt_get(state%mesh%elements(i)%id, a, fa)
        if (.not. fa) cycle
        do j = 1, i - 1
          call opt_get(state%mesh%elements(j)%id, b, fb)
          if (.not. fb) cycle
          if (a /= b) cycle
          call raise(errors, PE_DUPLICATE_REF, PE_STAGE_VALIDATE, 'V6', 'mesh.elements', &
                     idx=int(i, int32), field='id', &
                     message='id '//itoa(int(a))//' is already used by mesh.elements['//itoa(j)//']', &
                     actual=itoa(int(a)), expected='an unused id')
          exit
        end do
      end do
    end if

    if (allocated(state%materials)) then
      do i = 2, size(state%materials)
        call opt_get(state%materials(i)%id, a, fa)
        if (.not. fa) cycle
        do j = 1, i - 1
          call opt_get(state%materials(j)%id, b, fb)
          if (.not. fb) cycle
          if (a /= b) cycle
          call raise(errors, PE_DUPLICATE_REF, PE_STAGE_VALIDATE, 'V6', 'materials', &
                     idx=int(i, int32), field='id', &
                     message='id '//itoa(int(a))//' is already used by materials['//itoa(j)//']', &
                     actual=itoa(int(a)), expected='an unused id')
          exit
        end do
      end do
    end if

    if (allocated(state%sections)) then
      do i = 2, size(state%sections)
        if (.not. opt_is_set(state%sections(i)%name)) cycle
        na = opt_value_or(state%sections(i)%name, '')
        do j = 1, i - 1
          if (.not. opt_is_set(state%sections(j)%name)) cycle
          nb = opt_value_or(state%sections(j)%name, '')
          if (na /= nb) cycle
          call raise(errors, PE_DUPLICATE_REF, PE_STAGE_VALIDATE, 'V6', 'sections', &
                     idx=int(i, int32), field='name', &
                     message='name "'//na//'" is already used by sections['//itoa(j)//']', &
                     actual=na, expected='an unused name')
          exit
        end do
      end do
    end if

    ! V7 -- an element listed by two element sets
    if (allocated(state%mesh%elsets)) then
      do s = 2, size(state%mesh%elsets)
        if (.not. allocated(state%mesh%elsets(s)%elements)) cycle
        do k = 1, size(state%mesh%elsets(s)%elements)
          a = state%mesh%elsets(s)%elements(k)
          do t = 1, s - 1
            if (.not. allocated(state%mesh%elsets(t)%elements)) cycle
            do m = 1, size(state%mesh%elsets(t)%elements)
              if (state%mesh%elsets(t)%elements(m) /= a) cycle
              call raise(errors, PE_DUPLICATE_REF, PE_STAGE_VALIDATE, 'V7', 'mesh.elsets', &
                         idx=int(s, int32), field='elements['//itoa(k)//']', &
                         message='element '//itoa(int(a))//' is already in mesh.elsets['//itoa(t)//']', &
                         actual=itoa(int(a)), expected='an element in no other set')
              exit
            end do
          end do
        end do
      end do
    end if
  end subroutine validate_duplicates

  ! V8 unset where an explicit empty would have been a statement, V9 an element set with
  ! no elements, V20 an analysis with no step.
  subroutine validate_presence(state, errors)
    type(problem_state_t), intent(in) :: state
    type(problem_errors_t), intent(inout) :: errors
    integer :: i

    ! V8. A section is a formulation applied to a set of elements; sections without the
    ! sets is the three-state confusion the row exists to catch. An explicitly empty
    ! collection (allocated, size 0) is a different statement and reaches V9 or N4.
    if (allocated(state%sections)) then
      if (size(state%sections) > 0 .and. .not. allocated(state%mesh%elsets)) then
        call raise(errors, PE_MISSING_FIELD, PE_STAGE_VALIDATE, 'V8', 'mesh.elsets', &
                   message='unset while sections[] has '//itoa(size(state%sections))// &
                   ' entries; an explicitly empty collection is size 0, not unset', &
                   actual='unset', expected=itoa(size(state%sections))//' element sets')
      end if
    end if

    ! V9
    if (allocated(state%mesh%elsets)) then
      do i = 1, size(state%mesh%elsets)
        if (.not. allocated(state%mesh%elsets(i)%elements)) cycle
        if (size(state%mesh%elsets(i)%elements) > 0) cycle
        call raise(errors, PE_EMPTY_COLLECTION, PE_STAGE_VALIDATE, 'V9', 'mesh.elsets', &
                   idx=int(i, int32), field='elements', &
                   message='the element set of section '//itoa(i)//' has no elements', &
                   actual='0 elements', expected='at least 1 element')
      end do
    end if

    ! V20
    if (.not. allocated(state%steps)) then
      call raise(errors, PE_MISSING_FIELD, PE_STAGE_VALIDATE, 'V20', 'steps', &
                 message='unset; an analysis needs at least one step', &
                 actual='unset', expected='at least 1 step')
    else if (size(state%steps) == 0) then
      call raise(errors, PE_EMPTY_COLLECTION, PE_STAGE_VALIDATE, 'V20', 'steps', &
                 message='an analysis needs at least one step', &
                 actual='0 steps', expected='at least 1 step')
    end if
  end subroutine validate_presence

  ! V10 to V13: a vector's length is a statement about the model and must agree with the
  ! object that fixes it -- the spatial dimension, the section count, the element kind.
  subroutine validate_arities(state, errors)
    type(problem_state_t), intent(in) :: state
    type(problem_errors_t), intent(inout) :: errors

    integer :: i, n_sections, want_nodes
    integer(int32) :: ndim, kind_code
    logical :: has_dim, known

    call opt_get(state%mesh%dimension, ndim, has_dim)
    n_sections = 0
    if (allocated(state%sections)) n_sections = size(state%sections)

    ! V10
    if (has_dim .and. allocated(state%mesh%nodes)) then
      do i = 1, size(state%mesh%nodes)
        if (.not. allocated(state%mesh%nodes(i)%xyz)) cycle
        if (size(state%mesh%nodes(i)%xyz) == int(ndim)) cycle
        call raise(errors, PE_COUNT_MISMATCH, PE_STAGE_VALIDATE, 'V10', 'mesh.nodes', &
                   idx=int(i, int32), field='xyz', &
                   message=itoa(size(state%mesh%nodes(i)%xyz))//' coordinates for a mesh of '// &
                   'dimension '//itoa(int(ndim)), &
                   actual=itoa(size(state%mesh%nodes(i)%xyz)), expected=itoa(int(ndim)))
      end do
    end if

    if (allocated(state%steps)) then
      do i = 1, size(state%steps)
        ! V11 -- direction over the spatial dimensions
        if (has_dim .and. allocated(state%steps(i)%load%gravity%direction)) then
          if (size(state%steps(i)%load%gravity%direction) /= int(ndim)) then
            call raise(errors, PE_COUNT_MISMATCH, PE_STAGE_VALIDATE, 'V11', &
                       'steps['//itoa(i)//'].load.gravity', field='direction', &
                       message=itoa(size(state%steps(i)%load%gravity%direction))// &
                       ' components for a mesh of dimension '//itoa(int(ndim)), &
                       actual=itoa(size(state%steps(i)%load%gravity%direction)), &
                       expected=itoa(int(ndim)))
          end if
        end if
        ! V11 -- one amplitude reference per section
        if (allocated(state%steps(i)%load%gravity%amplitude) .and. n_sections > 0) then
          if (size(state%steps(i)%load%gravity%amplitude) /= n_sections) then
            call raise(errors, PE_COUNT_MISMATCH, PE_STAGE_VALIDATE, 'V11', &
                       'steps['//itoa(i)//'].load.gravity', field='amplitude', &
                       message=itoa(size(state%steps(i)%load%gravity%amplitude))// &
                       ' entries for '//itoa(n_sections)//' sections', &
                       actual=itoa(size(state%steps(i)%load%gravity%amplitude)), &
                       expected=itoa(n_sections))
          end if
        end if
        ! V12 -- one stress-averaging request per section
        if (allocated(state%steps(i)%output%stress_averaging) .and. n_sections > 0) then
          if (size(state%steps(i)%output%stress_averaging) /= n_sections) then
            call raise(errors, PE_COUNT_MISMATCH, PE_STAGE_VALIDATE, 'V12', &
                       'steps['//itoa(i)//'].output', field='stress_averaging', &
                       message=itoa(size(state%steps(i)%output%stress_averaging))// &
                       ' entries for '//itoa(n_sections)//' sections', &
                       actual=itoa(size(state%steps(i)%output%stress_averaging)), &
                       expected=itoa(n_sections))
          end if
        end if
      end do
    end if

    ! V13 -- connectivity length against the element kind. The kind is read from the
    ! element when it carries one and from its section otherwise, because the element's
    ! own kind is a finalize derivation and is normally still unset here.
    if (allocated(state%mesh%elements)) then
      do i = 1, size(state%mesh%elements)
        if (.not. allocated(state%mesh%elements(i)%nodes)) cycle
        call effective_element_kind(state, i, kind_code, known)
        if (.not. known) cycle
        call nodes_of_kind(kind_code, want_nodes, known)
        if (.not. known) cycle          ! an unsupported kind is the gate's finding
        if (size(state%mesh%elements(i)%nodes) == want_nodes) cycle
        call raise(errors, PE_COUNT_MISMATCH, PE_STAGE_VALIDATE, 'V13', 'mesh.elements', &
                   idx=int(i, int32), field='nodes', &
                   message=itoa(size(state%mesh%elements(i)%nodes))//' nodes for element kind '// &
                   itoa(int(kind_code))//', which has '//itoa(want_nodes), &
                   actual=itoa(size(state%mesh%elements(i)%nodes)), expected=itoa(want_nodes))
      end do
    end if
  end subroutine validate_arities

  ! V16 amplitude ordering, V17 boundary degree of freedom in range, V19 material
  ! physics. V15 has no code by construction: an authored zero must PASS every rule
  ! here, and the self-test proves it by submitting magnitude = 0 and expecting success.
  subroutine validate_semantics(state, errors)
    type(problem_state_t), intent(in) :: state
    type(problem_errors_t), intent(inout) :: errors

    integer :: i, k
    integer(int32) :: ndim, dof
    real(real64) :: t_prev, t_here, e_mod, nu, rho
    logical :: has_dim, f1, f2

    ! V16
    if (allocated(state%amplitudes)) then
      do i = 1, size(state%amplitudes)
        if (.not. allocated(state%amplitudes(i)%points)) cycle
        do k = 2, size(state%amplitudes(i)%points)
          call opt_get(state%amplitudes(i)%points(k - 1)%time, t_prev, f1)
          call opt_get(state%amplitudes(i)%points(k)%time, t_here, f2)
          if (.not. (f1 .and. f2)) cycle
          if (t_here > t_prev) cycle
          call raise(errors, PE_INVALID_INPUT, PE_STAGE_VALIDATE, 'V16', &
                     'amplitudes['//itoa(i)//'].points', idx=int(k, int32), field='time', &
                     message=rtoa(t_here)//' is not strictly after points['//itoa(k - 1)// &
                     '].time = '//rtoa(t_prev), &
                     actual=rtoa(t_here), expected='a time after '//rtoa(t_prev))
        end do
      end do
    end if

    ! V17
    call opt_get(state%mesh%dimension, ndim, has_dim)
    if (has_dim .and. allocated(state%steps)) then
      do i = 1, size(state%steps)
        if (.not. allocated(state%steps(i)%boundary)) cycle
        do k = 1, size(state%steps(i)%boundary)
          call opt_get(state%steps(i)%boundary(k)%dof, dof, f1)
          if (.not. f1) cycle
          if (dof >= 1_int32 .and. dof <= ndim) cycle
          call raise(errors, PE_INVALID_INPUT, PE_STAGE_VALIDATE, 'V17', &
                     'steps['//itoa(i)//'].boundary', idx=int(k, int32), field='dof', &
                     message='degree of freedom '//itoa(int(dof))//' is outside 1..'//itoa(int(ndim)), &
                     actual=itoa(int(dof)), expected='1..'//itoa(int(ndim)))
        end do
      end do
    end if

    ! V19
    if (allocated(state%materials)) then
      do i = 1, size(state%materials)
        call opt_get(state%materials(i)%E, e_mod, f1)
        if (f1) then
          if (.not. (e_mod > 0.0_real64)) then
            call raise(errors, PE_INVALID_INPUT, PE_STAGE_VALIDATE, 'V19', 'materials', &
                       idx=int(i, int32), field='E', &
                       message=rtoa(e_mod)//' is not a positive Young modulus', &
                       actual=rtoa(e_mod), expected='> 0')
          end if
        end if
        call opt_get(state%materials(i)%nu, nu, f1)
        if (f1) then
          if (.not. (nu > -1.0_real64 .and. nu < 0.5_real64)) then
            call raise(errors, PE_INVALID_INPUT, PE_STAGE_VALIDATE, 'V19', 'materials', &
                       idx=int(i, int32), field='nu', &
                       message=rtoa(nu)//' is outside the admissible range (-1, 0.5)', &
                       actual=rtoa(nu), expected='(-1, 0.5)')
          end if
        end if
        call opt_get(state%materials(i)%density, rho, f1)
        if (f1) then
          if (rho < 0.0_real64) then
            call raise(errors, PE_INVALID_INPUT, PE_STAGE_VALIDATE, 'V19', 'materials', &
                       idx=int(i, int32), field='density', &
                       message=rtoa(rho)//' is a negative density', &
                       actual=rtoa(rho), expected='>= 0')
          end if
        end if
      end do
    end if
  end subroutine validate_semantics

  ! V25. An element set names elements by id, so every id it names must exist.
  !
  ! Found while checking that INV-EMPTY-DERIVED was genuinely unreachable, and it was
  ! not: an authored element set listing an id that no element carries passed every
  ! other rule, then derived to an empty set at finalize. V4 and V5 do this job for node
  ! ids in node sets and in connectivity; nothing did it for element ids in element
  ! sets, so a set could reference elements that were never declared and the defect only
  ! surfaced as a manufactured empty collection two stages later.
  subroutine validate_elset_members(state, errors)
    type(problem_state_t), intent(in) :: state
    type(problem_errors_t), intent(inout) :: errors

    integer(int32), allocatable :: element_ids(:)
    integer :: i, k
    integer(int32) :: v

    if (.not. allocated(state%mesh%elsets)) return
    call collect_element_ids(state, element_ids)
    if (.not. allocated(element_ids)) return

    do i = 1, size(state%mesh%elsets)
      if (.not. allocated(state%mesh%elsets(i)%elements)) cycle
      do k = 1, size(state%mesh%elsets(i)%elements)
        v = state%mesh%elsets(i)%elements(k)
        if (in_list(element_ids, v)) cycle
        call raise(errors, PE_DANGLING_REF, PE_STAGE_VALIDATE, 'V25', 'mesh.elsets', &
                   idx=int(i, int32), field='elements['//itoa(k)//']', &
                   message='element '//itoa(int(v))//' is not an id in mesh.elements[]', &
                   actual=itoa(int(v)), expected='an id in mesh.elements[]')
      end do
    end do
  end subroutine validate_elset_members

  ! V24. A boundary record's set ordinal is a KEY: finalize turns the distinct ordinals
  ! of a step into that step's node sets, positionally. So the ordinals must be exactly
  ! 1..n with no gap and no value below 1.
  !
  ! This rule exists because of a real defect, not a hypothetical one. Without it,
  ! finalize sized the node-set collection by the MAXIMUM ordinal, so ordinals {2,3}
  ! produced three sets of which the first was allocated with length zero. That is an
  ! I04 breach of the worst kind: an allocated zero-length collection means "the author
  ! explicitly declared this empty", a state the builder makes reachable only through a
  ! dedicated _empty routine, and finalize was manufacturing it by arithmetic. It also
  ! falsified V21, which checks the declared set count against the AUTHORED sets during
  ! validate, so a deck declaring two sets passed while the published model carried
  ! three.
  !
  ! Rejecting is right rather than renumbering silently: a gap means the draft lost a
  ! set somewhere upstream, and papering over it would publish a model whose set keys no
  ! longer mean what the deck said they meant. Note V23 is deliberately absent; it was
  ! removed as unfalsifiable and its number is not reused.
  subroutine validate_set_keys(state, errors)
    type(problem_state_t), intent(in) :: state
    type(problem_errors_t), intent(inout) :: errors

    integer :: i, k, top, want
    integer(int32) :: ordinal
    logical :: found, seen

    if (.not. allocated(state%steps)) return

    do i = 1, size(state%steps)
      if (.not. allocated(state%steps(i)%boundary)) cycle
      if (size(state%steps(i)%boundary) == 0) cycle

      ! An ordinal below 1 is not a key at all; report each offending record.
      top = 0
      do k = 1, size(state%steps(i)%boundary)
        call opt_get(state%steps(i)%boundary(k)%name, ordinal, found)
        if (.not. found) cycle
        if (ordinal < 1_int32) then
          call raise(errors, PE_INVALID_INPUT, PE_STAGE_VALIDATE, 'V24', &
                     'steps['//itoa(i)//'].boundary', idx=int(k, int32), field='name', &
                     message='set ordinal '//itoa(int(ordinal))//' is not a set key; '// &
                     'ordinals start at 1', &
                     actual=itoa(int(ordinal)), expected='>= 1')
          cycle
        end if
        if (int(ordinal) > top) top = int(ordinal)
      end do
      if (top == 0) cycle

      ! Every ordinal from 1 to the largest must be used by some record. Report the
      ! FIRST gap only: the rest are the same defect seen again, and one finding that
      ! names the missing key is what a reader needs.
      do want = 1, top
        seen = .false.
        do k = 1, size(state%steps(i)%boundary)
          call opt_get(state%steps(i)%boundary(k)%name, ordinal, found)
          if (.not. found) cycle
          if (int(ordinal) == want) then
            seen = .true.
            exit
          end if
        end do
        if (seen) cycle
        call raise(errors, PE_INVALID_INPUT, PE_STAGE_VALIDATE, 'V24', &
                   'steps['//itoa(i)//'].boundary', field='name', &
                   message='no record uses set ordinal '//itoa(want)//' although '// &
                   itoa(top)//' is used; set ordinals must run 1..n with no gap', &
                   actual='a gap at '//itoa(want), expected='1..'//itoa(top)//' all used')
        exit
      end do
    end do
  end subroutine validate_set_keys

  ! V21 and V22 over the deck's redundant declarations. Nothing is copied into the
  ! model: a declared count is only ever compared against what the objects yield, and
  ! the ten counts with no collection behind them are asserted to be zero because a
  ! non-zero one names a load or thermal kind this build does not carry at all.
  subroutine validate_declared(state, declared, errors)
    type(problem_state_t), intent(in) :: state
    type(declared_counts_t), intent(in), optional :: declared
    type(problem_errors_t), intent(inout) :: errors

    type(manifest_t), allocatable :: unused

    if (.not. present(declared)) return
    call compare_declared(state, declared, errors, unused, .false.)
    call assert_absent_kinds(declared, errors)
  end subroutine validate_declared

  ! V22. UNSUPPORTED, not COUNT_MISMATCH: the deck is well formed, it simply describes a
  ! model outside this build's capability, which is exit class 3.
  subroutine assert_absent_kinds(declared, errors)
    type(declared_counts_t), intent(in) :: declared
    type(problem_errors_t), intent(inout) :: errors

    call zero_only(errors, declared%point_load_group_count, 'point_load_group_count', 'point load groups')
    call zero_only(errors, declared%edge_count, 'edge_count', 'loaded edges')
    call zero_only(errors, declared%edge_load_group_count, 'edge_load_group_count', 'edge load groups')
    call zero_only(errors, declared%edge_load_element_group_count, 'edge_load_element_group_count', &
                   'edge load element groups')
    call zero_only(errors, declared%beam_load_count, 'beam_load_count', 'beam loads')
    call zero_only(errors, declared%plate_load_count, 'plate_load_count', 'plate loads')
    call zero_only(errors, declared%temperature_surface_count, 'temperature_surface_count', &
                   'temperature surfaces')
    call zero_only(errors, declared%temperature_edge_count, 'temperature_edge_count', 'temperature edges')
    call zero_only(errors, declared%temperature_element_group_count, &
                   'temperature_element_group_count', 'temperature element groups')
    call zero_only(errors, declared%pipe_count, 'pipe_count', 'pipes')
  end subroutine assert_absent_kinds

  ! `field` is the identifier the finding points at and carries no blank, so the
  ! rendered message stays tokenisable; `what` is the human phrase inside the sentence.
  subroutine zero_only(errors, value, field, what)
    type(problem_errors_t), intent(inout) :: errors
    type(opt_int), intent(in) :: value
    character(len=*), intent(in) :: field, what
    integer(int32) :: v
    logical :: found

    call opt_get(value, v, found)
    if (.not. found) return
    if (v == 0_int32) return
    call raise(errors, PE_UNSUPPORTED, PE_STAGE_VALIDATE, 'V22', 'declared_counts', &
               field=field, &
               message='the deck declares '//itoa(int(v))//' '//what//'; build capability "'// &
               CAPABILITY_TAG//'" carries gravity only', &
               actual=itoa(int(v)), expected='0')
  end subroutine zero_only

  ! ==========================================================================
  ! stage 3 -- capability gate
  ! ==========================================================================

  ! G1 to G6. Every expected value comes from the capability table of
  ! yl_problem_profile through capability_expect_*; nothing is spelled here twice. The
  ! rule id on each finding is the table's own, so a table edit moves the rule with it.
  subroutine capability_gate(state, errors)
    type(problem_state_t), intent(in) :: state
    type(problem_errors_t), intent(inout) :: errors
    integer :: i

    ! G2 -- the analysis itself
    call gate_int(errors, 'analysis.dimension', 'mesh', 'dimension', state%mesh%dimension)

    ! G4 -- the linear solver
    call gate_text(errors, 'solver.linear', 'solver', 'linear', state%solver%linear)
    call gate_logical(errors, 'solver.symmetric', 'solver', 'symmetric', state%solver%symmetric)

    ! G1, G2 -- every section
    if (allocated(state%sections)) then
      do i = 1, size(state%sections)
        call gate_text(errors, 'element.type', 'sections', 'element', state%sections(i)%element, i)
        call gate_int(errors, 'element.kind_code', 'sections', 'element_kind', &
                      state%sections(i)%element_kind, i)
        call gate_text(errors, 'element.class', 'sections', 'class', state%sections(i)%class, i)
        call gate_text(errors, 'element.fields', 'sections', 'fields', state%sections(i)%fields, i)
        call gate_text(errors, 'element.formulation', 'sections', 'formulation', &
                       state%sections(i)%formulation, i)
      end do
    end if

    ! G3 -- every material
    if (allocated(state%materials)) then
      do i = 1, size(state%materials)
        call gate_text(errors, 'material.kind', 'materials', 'kind', state%materials(i)%kind, i)
        call gate_text(errors, 'material.model', 'materials', 'model', state%materials(i)%model, i)
      end do
    end if

    ! G2, G5, G6 -- every step
    if (allocated(state%steps)) then
      do i = 1, size(state%steps)
        call gate_text(errors, 'analysis.procedure', 'steps', 'procedure', &
                       state%steps(i)%procedure, i)
        call gate_int(errors, 'load.gravity_enabled', 'steps['//itoa(i)//'].load.gravity', &
                      'enabled', state%steps(i)%load%gravity%enabled)
        call gate_int(errors, 'analysis.increments', 'steps['//itoa(i)//'].controls', &
                      'increments', state%steps(i)%controls%increments)
      end do
    end if

    ! G6 -- the extents.
    !
    ! The section count is checked UNCONDITIONALLY, unset included. No validate rule
    ! requires sections to exist at all -- V1, V8 and the arity rules are each guarded
    ! by `allocated(sections)` and say nothing when the collection is absent -- so this
    ! is the only place a model with no sections can be caught, and skipping the check
    ! when the collection is unset let such a draft through the gate and fail later in
    ! finalize with a confusing missing-elset finding instead. For a CAPABILITY count
    ! the three states collapse honestly: unset and explicitly empty both mean "not the
    ! one section this build supports", and the gate reports the count it found.
    !
    ! The step count keeps its guard because V20 already rejects an unset or empty step
    ! list during validate, so the gate is never reached with one.
    ! DEPENDENCY, and it has an expiry date. This row is the only thing preventing a
    ! draft with two sections whose elements all point at the first, which would make
    ! finalize derive an EMPTY element set for the second and manufacture the
    ! explicitly-empty state the author never declared. That is an accident of the
    ! supported combination, not a rule that intends to stop it.
    !
    ! RAISING THE SUPPORTED SECTION COUNT ABOVE ONE REQUIRES A RULE FOR THAT CASE.
    ! Until then INV-EMPTY-DERIVED in derive_element_sets is the net, and it will fire
    ! as an internal fault rather than as the input defect it really is. The capability
    ! row itself lives in yl_problem_profile.f90; this note sits at the gate that reads
    ! it because that is the code which depends on the limit.
    call gate_size(errors, 'model.section_count', 'sections', size_or_zero_sections(state))
    if (allocated(state%steps)) then
      call gate_size(errors, 'analysis.step_count', 'steps', size(state%steps))
    end if
  end subroutine capability_gate

  subroutine gate_int(errors, item, object, field, value, idx)
    type(problem_errors_t), intent(inout) :: errors
    character(len=*), intent(in) :: item, object, field
    type(opt_int), intent(in) :: value
    integer, intent(in), optional :: idx
    integer(int32) :: want, got
    logical :: found

    call capability_expect_int(item, want, found)
    if (.not. found) return
    call opt_get(value, got, found)
    if (.not. found) return             ! requiredness belongs to V1, not to the gate
    if (got == want) return
    call gate_reject(errors, item, object, field, itoa(int(got)), itoa(int(want)), idx)
  end subroutine gate_int

  subroutine gate_size(errors, item, object, actual)
    type(problem_errors_t), intent(inout) :: errors
    character(len=*), intent(in) :: item, object
    integer, intent(in) :: actual
    integer(int32) :: want
    logical :: found

    call capability_expect_int(item, want, found)
    if (.not. found) return
    if (actual == int(want)) return
    call gate_reject(errors, item, object, 'size', itoa(actual), itoa(int(want)))
  end subroutine gate_size

  subroutine gate_text(errors, item, object, field, value, idx)
    type(problem_errors_t), intent(inout) :: errors
    character(len=*), intent(in) :: item, object, field
    type(opt_text), intent(in) :: value
    integer, intent(in), optional :: idx
    character(len=:), allocatable :: want, got
    logical :: found

    call capability_expect_text(item, want, found)
    if (.not. found) return
    if (.not. opt_is_set(value)) return
    got = opt_value_or(value, '')
    if (got == want) return
    call gate_reject(errors, item, object, field, '"'//got//'"', '"'//want//'"', idx)
  end subroutine gate_text

  subroutine gate_logical(errors, item, object, field, value, idx)
    type(problem_errors_t), intent(inout) :: errors
    character(len=*), intent(in) :: item, object, field
    type(opt_logical), intent(in) :: value
    integer, intent(in), optional :: idx
    logical :: want, got, found

    call capability_expect_logical(item, want, found)
    if (.not. found) return
    call opt_get(value, got, found)
    if (.not. found) return
    if (got .eqv. want) return
    call gate_reject(errors, item, object, field, btoa(got), btoa(want), idx)
  end subroutine gate_logical

  ! One rejection message shape for every gate item, carrying the capability tag so the
  ! reader knows which build refused and the rule id so the negative fixture matrix can
  ! assert coverage row by row.
  subroutine gate_reject(errors, item, object, field, actual, expected, idx)
    type(problem_errors_t), intent(inout) :: errors
    character(len=*), intent(in) :: item, object, field, actual, expected
    integer, intent(in), optional :: idx
    type(capability_item_t) :: row
    character(len=:), allocatable :: rule
    logical :: found
    integer :: i

    rule = 'G?'
    i = capability_find(item)
    if (i /= 0) then
      call capability_row(i, row, found)
      if (found) rule = trim(row%rule_id)
    end if

    if (present(idx)) then
      call raise(errors, PE_UNSUPPORTED, PE_STAGE_CAPABILITY, rule, object, &
                 idx=int(idx, int32), field=field, &
                 message=actual//' is not in {'//expected//'} for build capability "'// &
                 CAPABILITY_TAG//'"', actual=actual, expected=expected)
    else
      call raise(errors, PE_UNSUPPORTED, PE_STAGE_CAPABILITY, rule, object, field=field, &
                 message=actual//' is not in {'//expected//'} for build capability "'// &
                 CAPABILITY_TAG//'"', actual=actual, expected=expected)
    end if
  end subroutine gate_reject

  ! ==========================================================================
  ! stage 4 -- finalize
  ! ==========================================================================

  ! The six ProblemState index_map rows, the one legacy_default row and the eight
  ! declared-count checks, written into a private candidate pair. `problem` and
  ! `manifest` are published together in the last two statements, so a caller can never
  ! see a new problem beside a stale manifest, nor either of them after a failure.
  subroutine finalize_problem(state, declared, problem, manifest, errors)
    type(problem_state_t), intent(in) :: state
    type(declared_counts_t), intent(in), optional :: declared
    type(problem_state_t), allocatable, intent(inout) :: problem
    type(manifest_t), allocatable, intent(inout) :: manifest
    type(problem_errors_t), intent(inout) :: errors

    type(problem_state_t), allocatable :: candidate
    type(manifest_t), allocatable :: record
    integer :: mark

    mark = errors%count()
    allocate (candidate, source=state)
    allocate (record)
    call manifest_reset(record)

    call derive_element_kinds(candidate, record, errors)        ! mesh.elements.kind

    ! Every later derivation reads the element-to-section map, so if that map is bad
    ! there is nothing truthful left to derive: the element sets would come out empty,
    ! the section materials unresolvable, and each would be reported as a fresh defect
    ! when there is only one. Stop here and let the caller see the cause. This is the
    ! same discipline validate uses, where an unresolved reference suppresses the checks
    ! that depend on it and nothing else.
    if (errors%count() > mark) return

    call record_element_groups(candidate, record)               ! mesh.elements.group (N6)
    call derive_element_sets(candidate, record, errors)         ! mesh.sets.elset
    call derive_node_sets(candidate, record, errors)            ! mesh.sets.nset
    call derive_section_materials(candidate, record, errors)    ! sections.material_header, .material
    call apply_stress_components(candidate, record, errors)     ! derived.counts.nstre

    if (present(declared)) call compare_declared(candidate, declared, errors, record, .true.)

    ! INVARIANT of the BY-CONSTRUCTION kind, not a rule. Every add above uses a
    ! compiled-in rule name, dtype and
    ! profile id, so the manifest can only refuse an entry if this code or the manifest
    ! module is wrong -- no draft can provoke it. Kept because evidence that is silently
    ! incomplete is worse than none: fail the stage rather than publish a short manifest.
    if (.not. manifest_is_valid(record)) then
      call raise_invariant(errors, 'INV-MANIFEST', 'manifest', &
                           message='the derivation manifest refused an entry: '// &
                           manifest_error(record), &
                           actual='incomplete', expected='complete')
    end if

    if (errors%count() > mark) return
    call move_alloc(candidate, problem)
    call move_alloc(record, manifest)
  end subroutine finalize_problem

  ! mesh.elements.kind = the element kind of the section that owns the element.
  ! derived_from sections.element_kind and the element-to-set reference.
  subroutine derive_element_kinds(state, record, errors)
    type(problem_state_t), intent(inout) :: state
    type(manifest_t), intent(inout) :: record
    type(problem_errors_t), intent(inout) :: errors

    integer(int32), allocatable :: kinds(:)
    integer(int32) :: s, k
    integer :: i
    logical :: found

    if (.not. allocated(state%mesh%elements)) return
    allocate (kinds(size(state%mesh%elements)))
    kinds = 0_int32

    do i = 1, size(state%mesh%elements)
      call opt_get(state%mesh%elements(i)%elset, s, found)
      if (.not. found) then
        ! INVARIANT of the BY-CONSTRUCTION kind, not a rule. Normalize rule N6 fills
        ! this reference or fails, and
        ! validate rule V8 rejects the one draft where N6 cannot run (element sets
        ! unset), so no input reaches finalize with it still unset. Probed and
        ! confirmed unreachable: V8 fires first. Kept because deleting it would let
        ! finalize silently write element kind 0 if either invariant ever broke.
        call raise_invariant(errors, 'INV-ELSET-SET', 'mesh.elements', &
                             idx=int(i, int32), field='elset', &
                             message='the owning element set is unset at finalize; '// &
                             'normalize rule N6 or validate rule V8 failed to enforce it', &
                             actual='unset', expected='an element set ordinal')
        cycle
      end if
      if (.not. allocated(state%sections)) cycle
      if (s < 1_int32 .or. s > int(size(state%sections), int32)) then
        call raise(errors, PE_DANGLING_REF, PE_STAGE_FINALIZE, 'F-IM2', 'mesh.elements', &
                   idx=int(i, int32), field='elset', &
                   message='element set '//itoa(int(s))//' is outside 1..'//itoa(size(state%sections)), &
                   actual=itoa(int(s)), expected='1..'//itoa(size(state%sections)))
        cycle
      end if
      call opt_get(state%sections(s)%element_kind, k, found)
      if (.not. found) cycle           ! V1 already reported the missing section kind
      call opt_set(state%mesh%elements(i)%kind, k)
      kinds(i) = k
    end do

    call manifest_add_derived(record, MANIFEST_RULE_INDEX_MAP, 'mesh.elements', 'kind', &
                              mv_i32_list(kinds), &
                              mt_list('sections[].element_kind', 'mesh.elements[].elset'), &
                              'mesh.elements.kind')
  end subroutine derive_element_kinds

  ! mesh.elements.group. The value itself was produced by normalize rule N6, which is
  ! the inverse of this index map; finalize records it rather than computing it a second
  ! time, so there is exactly one place where an element's owning set is decided.
  subroutine record_element_groups(state, record)
    type(problem_state_t), intent(in) :: state
    type(manifest_t), intent(inout) :: record

    integer(int32), allocatable :: groups(:)
    integer :: i

    if (.not. allocated(state%mesh%elements)) return
    allocate (groups(size(state%mesh%elements)))
    do i = 1, size(state%mesh%elements)
      groups(i) = opt_value_or(state%mesh%elements(i)%elset, 0_int32)
    end do

    call manifest_add_derived(record, MANIFEST_RULE_INDEX_MAP, 'mesh.elements', 'elset', &
                              mv_i32_list(groups), &
                              mt_list('mesh.elsets[].elements', 'mesh.elements[].id'), &
                              'mesh.elements.group')
  end subroutine record_element_groups

  ! mesh.sets.elset: one ordered element-id list per section, in element record order.
  ! Derived from the element-to-set reference, so moving an element between sets moves
  ! it here and changes the manifest line.
  subroutine derive_element_sets(state, record, errors)
    type(problem_state_t), intent(inout) :: state
    type(manifest_t), intent(inout) :: record
    type(problem_errors_t), intent(inout) :: errors

    type(elset_t), allocatable :: sets(:)
    integer(int32), allocatable :: buffer(:)
    integer(int32) :: s, eid
    integer :: i, j, n, n_sections
    logical :: found

    if (.not. allocated(state%sections)) return
    if (.not. allocated(state%mesh%elements)) return
    n_sections = size(state%sections)
    if (n_sections == 0) return

    allocate (sets(n_sections))
    allocate (buffer(size(state%mesh%elements)))

    do j = 1, n_sections
      n = 0
      do i = 1, size(state%mesh%elements)
        call opt_get(state%mesh%elements(i)%elset, s, found)
        if (.not. found) cycle
        if (int(s) /= j) cycle
        call opt_get(state%mesh%elements(i)%id, eid, found)
        if (.not. found) cycle
        n = n + 1
        buffer(n) = eid
      end do
      call guard_derived_not_empty(errors, n, 'mesh.elsets['//itoa(j)//']', 'elements')
      allocate (sets(j)%elements(n))
      if (n > 0) sets(j)%elements(1:n) = buffer(1:n)

      call manifest_add_derived(record, MANIFEST_RULE_INDEX_MAP, 'mesh.elsets['//itoa(j)//']', &
                                'elements', mv_i32_list(sets(j)%elements), &
                                mt_list('mesh.elements[].elset', 'mesh.elements[].id'), &
                                'mesh.sets.elset')
    end do

    call move_alloc(sets, state%mesh%elsets)
  end subroutine derive_element_sets

  ! mesh.sets.nset: one ordered node-id list per prescribed set, the distinct node ids
  ! of the boundary records that share a set ordinal, in first-occurrence order.
  ! Derived only when boundary records exist; a draft that carries node sets and no
  ! boundary records keeps the sets it was given.
  subroutine derive_node_sets(state, record, errors)
    type(problem_state_t), intent(inout) :: state
    type(manifest_t), intent(inout) :: record
    type(problem_errors_t), intent(inout) :: errors

    type(nset_t), allocatable :: sets(:)
    integer(int32), allocatable :: buffer(:)
    integer(int32) :: set_ordinal, node_id
    integer :: i, j, n, n_sets, n_records
    logical :: found, seen

    if (.not. allocated(state%steps)) return
    if (size(state%steps) < 1) return
    if (.not. allocated(state%steps(1)%boundary)) return
    n_records = size(state%steps(1)%boundary)
    if (n_records == 0) return

    ! How many sets the records name. A set ordinal below 1 is not a set key.
    n_sets = 0
    do i = 1, n_records
      call opt_get(state%steps(1)%boundary(i)%name, set_ordinal, found)
      if (.not. found) cycle
      if (int(set_ordinal) > n_sets) n_sets = int(set_ordinal)
    end do
    if (n_sets == 0) return

    allocate (sets(n_sets))
    allocate (buffer(n_records))

    do j = 1, n_sets
      n = 0
      do i = 1, n_records
        call opt_get(state%steps(1)%boundary(i)%name, set_ordinal, found)
        if (.not. found) cycle
        if (int(set_ordinal) /= j) cycle
        call opt_get(state%steps(1)%boundary(i)%nset, node_id, found)
        if (.not. found) cycle
        seen = .false.
        if (n > 0) seen = in_list(buffer(1:n), node_id)
        if (seen) cycle
        n = n + 1
        buffer(n) = node_id
      end do
      call guard_derived_not_empty(errors, n, 'mesh.nsets['//itoa(j)//']', 'nodes')
      allocate (sets(j)%nodes(n))
      if (n > 0) sets(j)%nodes(1:n) = buffer(1:n)

      call manifest_add_derived(record, MANIFEST_RULE_INDEX_MAP, 'mesh.nsets['//itoa(j)//']', &
                                'nodes', mv_i32_list(sets(j)%nodes), &
                                mt_list('steps[0].boundary[].name', 'steps[0].boundary[].nset'), &
                                'mesh.sets.nset')
    end do

    call move_alloc(sets, state%mesh%nsets)
  end subroutine derive_node_sets

  ! sections.material_header: the material stated by the group header, recovered as the
  ! material of the first element of the section's set.
  ! sections.material: the EFFECTIVE material, the step activation override when the
  ! section is active in this step, the header value otherwise. The chain stays acyclic:
  ! elements.material -> material_header -> material.
  subroutine derive_section_materials(state, record, errors)
    type(problem_state_t), intent(inout) :: state
    type(manifest_t), intent(inout) :: record
    type(problem_errors_t), intent(inout) :: errors

    integer :: j, e
    integer(int32) :: header, effective, override, active, eid
    logical :: found, have_header

    if (.not. allocated(state%sections)) return

    do j = 1, size(state%sections)
      ! -- header
      have_header = .false.
      header = 0_int32
      if (allocated(state%mesh%elsets)) then
        if (j <= size(state%mesh%elsets)) then
          if (allocated(state%mesh%elsets(j)%elements)) then
            if (size(state%mesh%elsets(j)%elements) > 0) then
              eid = state%mesh%elsets(j)%elements(1)
              e = element_index_of_id(state, eid)
              if (e > 0) call opt_get(state%mesh%elements(e)%material, header, have_header)
            end if
          end if
        end if
      end if

      if (have_header) then
        call opt_set(state%sections(j)%material_header, header)
        call manifest_add_derived(record, MANIFEST_RULE_INDEX_MAP, 'sections['//itoa(j)//']', &
                                  'material_header', mv_i32(header), &
                                  mt_list('mesh.elements[].material', 'mesh.elsets[].elements'), &
                                  'sections.material_header')
      else
        call opt_get(state%sections(j)%material_header, header, have_header)
        if (.not. have_header) then
          call raise(errors, PE_MISSING_FIELD, PE_STAGE_FINALIZE, 'F-IM5', 'sections', &
                     idx=int(j, int32), field='material_header', &
                     message='no element of this section carries a material, so the header '// &
                     'material cannot be derived and none was authored', &
                     actual='unset', expected='a material id')
          cycle
        end if
        ! The authored path, and it is the ORDINARY one on the legacy decks: the .ele
        ! records carry no material, so the group header is where the material is
        ! stated and there is nothing to recover it from. The row is recorded either
        ! way -- "every derived value is traceable" has to hold whichever way the value
        ! was obtained -- and the input list is what distinguishes the two provenances:
        ! reading `sections[].material_header` here says finalize used the as-authored
        ! header, reading the element materials says it reconstructed one.
        call manifest_add_derived(record, MANIFEST_RULE_INDEX_MAP, 'sections['//itoa(j)//']', &
                                  'material_header', mv_i32(header), &
                                  mt_list('sections[].material_header'), &
                                  'sections.material_header')
      end if

      ! -- effective material
      effective = header
      if (allocated(state%steps)) then
        if (size(state%steps) >= 1) then
          if (allocated(state%steps(1)%activation)) then
            if (j <= size(state%steps(1)%activation)) then
              call opt_get(state%steps(1)%activation(j)%active, active, found)
              if (found) then
                if (active /= 0_int32) then
                  call opt_get(state%steps(1)%activation(j)%material, override, found)
                  if (found) effective = override
                end if
              end if
            end if
          end if
        end if
      end if

      call opt_set(state%sections(j)%material, effective)
      call manifest_add_derived(record, MANIFEST_RULE_INDEX_MAP, 'sections['//itoa(j)//']', &
                                'material', mv_i32(effective), &
                                mt_list('steps[0].activation[].material', &
                                        'steps[0].activation[].active', &
                                        'sections[].material_header'), &
                                'sections.material')
    end do
  end subroutine derive_section_materials

  ! derived.counts.nstre, the one M3-02 profile default: the number of stress components
  ! a section's formulation carries. It has no ProblemState component -- a count is
  ! never stored as a field -- so it exists only as manifest evidence, stamped with the
  ! profile that supplied it.
  subroutine apply_stress_components(state, record, errors)
    type(problem_state_t), intent(in) :: state
    type(manifest_t), intent(inout) :: record
    type(problem_errors_t), intent(inout) :: errors

    integer(int32) :: value
    integer :: j, row
    logical :: found

    if (.not. allocated(state%sections)) return

    ! INVARIANT of the BY-CONSTRUCTION kind, not a rule. The key is a compiled-in
    ! constant and the profile table is
    ! a PARAMETER array that declares it with an integer payload, so the lookup can only
    ! fail if the two are edited out of step. No draft can provoke it. Kept so that such
    ! an edit surfaces as an internal fault instead of a section silently losing its
    ! stress-component default.
    call profile_lookup_int(KEY_STRESS_COMPONENTS, value, found, row)
    if (.not. found) then
      call raise_invariant(errors, 'INV-PROFILE-KEY', 'profile', &
                           field=KEY_STRESS_COMPONENTS, &
                           message='profile "'//PROFILE_TAG//'" carries no integer value '// &
                           'for this key; the key constant and the profile table disagree', &
                           actual='absent', expected='an integer default')
      return
    end if

    do j = 1, size(state%sections)
      call manifest_add_default(record, 'sections['//itoa(j)//']', 'stress_components', &
                                mv_i32(value), PROFILE_ID, PROFILE_VERSION, &
                                mt_list('mesh.dimension', 'sections[].class'), &
                                'derived.counts.nstre')
    end do
  end subroutine apply_stress_components

  ! ==========================================================================
  ! declared-count comparison, shared by V21 and the finalize evidence
  ! ==========================================================================

  ! One traversal, two uses. With `record` false it is V21 and a disagreement is a
  ! COUNT_MISMATCH finding; with `record` true it is the finalize evidence and every
  ! comparison, agreeing or not, becomes a manifest check entry -- which is what keeps a
  ! PASSING check visible instead of indistinguishable from a check never made.
  subroutine compare_declared(state, declared, errors, record, recording)
    type(problem_state_t), intent(in) :: state
    type(declared_counts_t), intent(in) :: declared
    type(problem_errors_t), intent(inout) :: errors
    type(manifest_t), allocatable, intent(inout) :: record
    logical, intent(in) :: recording

    type(opt_int) :: one
    integer :: i

    call one_count(declared%node_count, size_or_zero_nodes(state), allocated(state%mesh%nodes), &
                   'mesh.nodes', 'count', 'derived.counts.npoin', 'mesh.nodes[].id', &
                   errors, record, recording)
    call one_count(declared%element_count, size_or_zero_elements(state), &
                   allocated(state%mesh%elements), 'mesh.elements', 'count', &
                   'derived.counts.nelem', 'mesh.elements[].id', errors, record, recording)
    call one_count(declared%material_count, size_or_zero_materials(state), &
                   allocated(state%materials), 'materials', 'count', 'derived.counts.nmats', &
                   'materials[].id', errors, record, recording)
    call one_count(declared%section_count, size_or_zero_sections(state), &
                   allocated(state%sections), 'sections', 'count', 'derived.counts.ngroup', &
                   'sections[].name', errors, record, recording)
    call one_count(declared%amplitude_count, size_or_zero_amplitudes(state), &
                   allocated(state%amplitudes), 'amplitudes', 'count', 'derived.counts.ntcurve', &
                   'amplitudes[].points', errors, record, recording)
    call one_count(declared%nset_count, size_or_zero_nsets(state), &
                   allocated(state%mesh%nsets), 'mesh.nsets', 'count', 'derived.counts.nfixsets', &
                   'mesh.nsets[].nodes', errors, record, recording)

    ! sections.elset_size -- one declared length per section
    if (allocated(declared%elset_size) .and. allocated(state%mesh%elsets)) then
      do i = 1, min(size(declared%elset_size), size(state%mesh%elsets))
        if (.not. allocated(state%mesh%elsets(i)%elements)) cycle
        call opt_clear(one)
        call opt_set(one, declared%elset_size(i))
        call one_count(one, size(state%mesh%elsets(i)%elements), .true., &
                       'mesh.elsets['//itoa(i)//']', 'count', 'sections.elset_size', &
                       'mesh.elsets[].elements', errors, record, recording)
      end do
    end if

    ! amplitudes.points.count -- one declared length per amplitude
    if (allocated(declared%amplitude_points) .and. allocated(state%amplitudes)) then
      do i = 1, min(size(declared%amplitude_points), size(state%amplitudes))
        if (.not. allocated(state%amplitudes(i)%points)) cycle
        call opt_clear(one)
        call opt_set(one, declared%amplitude_points(i))
        call one_count(one, size(state%amplitudes(i)%points), .true., &
                       'amplitudes['//itoa(i)//']', 'points', 'amplitudes.points.count', &
                       'amplitudes[].points', errors, record, recording)
      end do
    end if
  end subroutine compare_declared

  ! A single declared-versus-derived comparison. An unset declaration is not a
  ! comparison at all and is skipped; so is a comparison whose collection is unset,
  ! because "no nodes were declared" and "the node collection is absent" are different
  ! statements and only the first is a count.
  subroutine one_count(declared_value, derived_value, derivable, object, field, &
                       map_id, input_path, errors, record, recording)
    type(opt_int), intent(in) :: declared_value
    integer, intent(in) :: derived_value
    logical, intent(in) :: derivable
    character(len=*), intent(in) :: object, field, map_id, input_path
    type(problem_errors_t), intent(inout) :: errors
    type(manifest_t), allocatable, intent(inout) :: record
    logical, intent(in) :: recording

    integer(int32) :: declared_int
    logical :: found

    call opt_get(declared_value, declared_int, found)
    if (.not. found) return
    if (.not. derivable) return

    if (recording) then
      if (.not. allocated(record)) return
      call manifest_add_check(record, object, field, mv_i32(int(derived_value, int32)), &
                              mv_i32(declared_int), mt_list(input_path), map_id)
    else if (int(declared_int) /= derived_value) then
      call raise(errors, PE_COUNT_MISMATCH, PE_STAGE_VALIDATE, 'V21', object, field=field, &
                 message='the deck declares '//itoa(int(declared_int))//' but the objects yield '// &
                 itoa(derived_value), &
                 actual=itoa(derived_value), expected=itoa(int(declared_int)))
    end if
  end subroutine one_count

  ! ==========================================================================
  ! capability-row coverage
  ! ==========================================================================

  ! WHY THE ROW AND NOT THE RULE ID.
  !   The capability table has fifteen rows but only six rule ids, so several rows share
  !   one id: G1 owns four, G2 three, G6 four. A self-test binding its assertions to a
  !   rule id therefore proves that ONE of that id's rows fired, never that all did, and
  !   a row added later under an existing id inherits that id's apparent coverage and
  !   ships untested. Not hypothetical: an audit found six rows with no counter-example,
  !   every one hidden behind a rule id another row already made look covered.
  !
  ! WHY THE MATCH LIVES HERE AND NOT IN THE SELF-TEST.
  !   Binding a finding to a row means knowing how the gate spells that row's object
  !   path: the table says `steps[].controls` while the finding says `steps[1].controls`,
  !   and the index is chosen in this module. A copy of that knowledge in the test would
  !   be a second place to update when the spelling changes. The test asks the question;
  !   this module, which made the choice, answers it.
  !
  ! WHAT THIS MEASURES.
  !   Rows that a finding actually came from, read out of the accumulator -- not rows the
  !   gate merely evaluated. A row the gate reads but that no counter-example can make
  !   fire is exactly the un-failable gate this milestone exists to prevent, and it reads
  !   as UNCOVERED here.

  ! How many rows the capability table declares. Evidence should record rows covered
  ! against this number, not a bare check total.
  pure integer function capability_row_count() result(n)
    n = capability_count()
  end function capability_row_count

  ! The stable identity of row `i`: its CAE item name, e.g. 'element.kind_code'. Empty
  ! for an out-of-range index, because this is a reporting path and must not abort.
  pure function capability_row_id(i) result(id)
    integer, intent(in) :: i
    character(len=:), allocatable :: id
    type(capability_item_t) :: row
    logical :: found
    id = ''
    call capability_row(i, row, found)
    if (found) id = trim(row%item)
  end function capability_row_id

  ! Did any finding in `errors` come from capability row `i`?
  !
  ! A finding matches when its rule id, field and object path are the row's, with every
  ! `[index]` group removed from both sides. That normalisation is what lets the table's
  ! `steps[].controls` match a finding's `steps[1].controls` without this code knowing
  ! which step failed. The triple is unique across all fifteen rows, including the two
  ! G6 rows that share the field `size` and are separated by their object path.
  pure logical function capability_row_exercised(errors, i) result(hit)
    type(problem_errors_t), intent(in) :: errors
    integer, intent(in) :: i
    type(capability_item_t) :: row
    type(problem_error_t) :: finding
    logical :: found
    integer :: k

    hit = .false.
    call capability_row(i, row, found)
    if (.not. found) return

    do k = 1, errors%count()
      call errors%get(k, finding, found)
      if (.not. found) cycle
      if (opt_value_or(finding%rule_id, '') /= trim(row%rule_id)) cycle
      if (opt_value_or(finding%field, '') /= trim(row%field)) cycle
      if (strip_index(opt_value_or(finding%object_path, '')) /= strip_index(trim(row%object_path))) cycle
      hit = .true.
      return
    end do
  end function capability_row_exercised

  ! The first capability row that no finding in `errors` exercised, or 0 when every row
  ! is covered. An INDEX rather than a logical, deliberately: a suite failing with
  ! "row 7, element.fields, has no counter-example" is actionable; one failing with
  ! "coverage incomplete" is not.
  pure integer function capability_first_uncovered(errors) result(i)
    type(problem_errors_t), intent(in) :: errors
    integer :: k
    i = 0
    do k = 1, capability_count()
      if (capability_row_exercised(errors, k)) cycle
      i = k
      return
    end do
  end function capability_first_uncovered

  ! Delete every `[...]` group, so an object path carrying a collection index compares
  ! equal to the table's index-free spelling of the same path.
  pure function strip_index(s) result(t)
    character(len=*), intent(in) :: s
    character(len=:), allocatable :: t
    integer :: k
    logical :: inside
    t = ''
    inside = .false.
    do k = 1, len(s)
      if (s(k:k) == '[') then
        inside = .true.
      else if (s(k:k) == ']') then
        inside = .false.
      else if (.not. inside) then
        t = t//s(k:k)
      end if
    end do
  end function strip_index

  ! ==========================================================================
  ! small shared helpers
  ! ==========================================================================

  ! One place where a finding is built, so every rule produces the same message shape
  ! and an absent optional propagates as absent rather than as an empty string.
  subroutine raise(errors, code, stage, rule, object, field, message, actual, expected, idx)
    type(problem_errors_t), intent(inout) :: errors
    character(len=*), intent(in) :: code, stage, rule, object
    character(len=*), intent(in), optional :: field, message, actual, expected
    integer(int32), intent(in), optional :: idx

    call errors%add(make_problem_error(code=code, stage=stage, rule_id=rule, &
                                       object_path=object, index=idx, field=field, &
                                       message=message, actual=actual, expected=expected))
  end subroutine raise

  ! An INTERNAL FAULT, not a statement about the user's model: the pipeline reached a
  ! state an earlier stage should have made impossible. PE_INTERNAL carries exit class 6,
  ! never 2, so a caller's exit status distinguishes "your deck is wrong" from "this
  ! program is wrong". All three call sites are in finalize, so the stage is fixed.
  subroutine raise_invariant(errors, rule, object, field, message, actual, expected, idx)
    type(problem_errors_t), intent(inout) :: errors
    character(len=*), intent(in) :: rule, object
    character(len=*), intent(in), optional :: field, message, actual, expected
    integer(int32), intent(in), optional :: idx

    call errors%add(make_problem_error(code=PE_INTERNAL, stage=PE_STAGE_FINALIZE, &
                                       rule_id=rule, object_path=object, index=idx, &
                                       field=field, message=message, actual=actual, &
                                       expected=expected))
  end subroutine raise_invariant

  ! INVARIANT, of the CAPABILITY-LIMITED kind: see the note at the model.section_count
  ! gate call. Finalize must NEVER publish an allocated zero-length collection that the
  ! author did not explicitly declare empty. An allocated empty collection is a
  ! statement -- "explicitly empty" -- that the builder makes reachable only through a
  ! dedicated _empty routine, and a derived collection that came out empty would put
  ! that statement into the model on the author's behalf.
  !
  ! Three separate things keep this unreachable, and it took a draft reaching it twice
  ! to find them all:
  !   * node sets  -- an ordinal gap sized the collection by the maximum ordinal. V24
  !                   now rejects the gap upstream.
  !   * element sets, dangling member -- an element set naming an id no element carries
  !                   derived to empty. V25 now rejects it upstream.
  !   * element sets, bad section map -- an out-of-range element%elset left section 1
  !                   with no elements. Finalize now stops after derive_element_kinds
  !                   when that map is bad, so the caller sees the DANGLING_REF cause at
  !                   exit class 2 instead of this assertion at exit class 6.
  ! A draft with two sections whose elements all point at the first would still reach
  ! here, and is stopped only by the capability gate allowing exactly one section. That
  ! is an accident, not a design, so this guard is what catches it the day the supported
  ! section count grows.
  subroutine guard_derived_not_empty(errors, n, object, field)
    type(problem_errors_t), intent(inout) :: errors
    integer, intent(in) :: n
    character(len=*), intent(in) :: object, field

    if (n > 0) return
    call raise_invariant(errors, 'INV-EMPTY-DERIVED', object, field=field, &
                         message='the derived collection is empty; publishing it would '// &
                         'assert an explicitly empty set the author never declared', &
                         actual='0 entries', expected='at least 1 entry')
  end subroutine guard_derived_not_empty

  ! V1's single shape: a required field that is unset.
  subroutine need(errors, is_set, rule, object, field, idx)
    type(problem_errors_t), intent(inout) :: errors
    logical, intent(in) :: is_set
    character(len=*), intent(in) :: rule, object, field
    integer, intent(in), optional :: idx

    if (is_set) return
    if (present(idx)) then
      call raise(errors, PE_MISSING_FIELD, PE_STAGE_VALIDATE, rule, object, &
                 idx=int(idx, int32), field=field, message='required, unset', &
                 actual='unset', expected='a value')
    else
      call raise(errors, PE_MISSING_FIELD, PE_STAGE_VALIDATE, rule, object, field=field, &
                 message='required, unset', actual='unset', expected='a value')
    end if
  end subroutine need

  ! N1's single transformation. `enum` selects upper-casing: a keyword is compared
  ! against the capability table and must be canonical, a name is identity and keeps the
  ! case the author wrote.
  subroutine canon(x, enum)
    type(opt_text), intent(inout) :: x
    logical, intent(in) :: enum
    character(len=:), allocatable :: value
    logical :: found

    call opt_get(x, value, found)
    if (.not. found) return
    value = trim(adjustl(value))
    if (enum) value = upper(value)
    call opt_set(x, value)
  end subroutine canon

  pure function upper(s) result(t)
    character(len=*), intent(in) :: s
    character(len=len(s)) :: t
    integer :: i, c
    do i = 1, len(s)
      c = iachar(s(i:i))
      if (c >= iachar('a') .and. c <= iachar('z')) then
        t(i:i) = achar(c - 32)
      else
        t(i:i) = s(i:i)
      end if
    end do
  end function upper

  pure function itoa(v) result(s)
    integer, intent(in) :: v
    character(len=:), allocatable :: s
    character(len=12) :: buffer
    write (buffer, '(i0)') v
    s = trim(buffer)
  end function itoa

  ! Reals appear in messages only, so a short general form is right: it is never parsed
  ! back and never compared. Manifest values use the exact hexadecimal encoding instead.
  pure function rtoa(v) result(s)
    real(real64), intent(in) :: v
    character(len=:), allocatable :: s
    character(len=32) :: buffer
    write (buffer, '(g0.8)') v
    s = trim(adjustl(buffer))
    ! g0 drops the integer zero of a fraction; restore it so that 0.6 does not read
    ! as `.6` in a message a person has to act on.
    if (len(s) > 0) then
      if (s(1:1) == '.') then
        s = '0'//s
      else if (len(s) > 1) then
        if (s(1:2) == '-.') s = '-0'//s(2:)
      end if
    end if
  end function rtoa

  pure function btoa(v) result(s)
    logical, intent(in) :: v
    character(len=:), allocatable :: s
    if (v) then
      s = 'true'
    else
      s = 'false'
    end if
  end function btoa

  pure logical function in_list(list, value) result(hit)
    integer(int32), intent(in) :: list(:)
    integer(int32), intent(in) :: value
    integer :: i
    hit = .false.
    do i = 1, size(list)
      if (list(i) == value) then
        hit = .true.
        return
      end if
    end do
  end function in_list

  ! The connectivity length of an element kind. `known` false means this build has no
  ! opinion, which is the capability gate's finding and not an arity defect.
  pure subroutine nodes_of_kind(kind_code, n, known)
    integer(int32), intent(in) :: kind_code
    integer, intent(out) :: n
    logical, intent(out) :: known
    if (kind_code == ELEMENT_KIND_Q4) then
      n = int(ELEMENT_NODES_Q4)
      known = .true.
    else
      n = 0
      known = .false.
    end if
  end subroutine nodes_of_kind

  ! The element kind to judge an element's connectivity by: its own when finalize has
  ! already written one, otherwise its section's.
  subroutine effective_element_kind(state, i, kind_code, known)
    type(problem_state_t), intent(in) :: state
    integer, intent(in) :: i
    integer(int32), intent(out) :: kind_code
    logical, intent(out) :: known
    integer(int32) :: s

    call opt_get(state%mesh%elements(i)%kind, kind_code, known)
    if (known) return
    call opt_get(state%mesh%elements(i)%elset, s, known)
    if (.not. known) return
    known = .false.
    if (.not. allocated(state%sections)) return
    if (s < 1_int32 .or. s > int(size(state%sections), int32)) return
    call opt_get(state%sections(s)%element_kind, kind_code, known)
  end subroutine effective_element_kind

  pure function element_index_of_id(state, eid) result(i)
    type(problem_state_t), intent(in) :: state
    integer(int32), intent(in) :: eid
    integer :: i, k
    integer(int32) :: v
    logical :: found
    i = 0
    if (.not. allocated(state%mesh%elements)) return
    do k = 1, size(state%mesh%elements)
      call opt_get(state%mesh%elements(k)%id, v, found)
      if (.not. found) cycle
      if (v /= eid) cycle
      i = k
      return
    end do
  end function element_index_of_id

  subroutine collect_node_ids(state, ids)
    type(problem_state_t), intent(in) :: state
    integer(int32), allocatable, intent(out) :: ids(:)
    integer :: i, n
    integer(int32) :: v
    logical :: found

    if (.not. allocated(state%mesh%nodes)) return
    allocate (ids(size(state%mesh%nodes)))
    n = 0
    do i = 1, size(state%mesh%nodes)
      call opt_get(state%mesh%nodes(i)%id, v, found)
      if (.not. found) cycle
      n = n + 1
      ids(n) = v
    end do
    if (n < size(ids)) ids = ids(1:n)
  end subroutine collect_node_ids

  subroutine collect_element_ids(state, ids)
    type(problem_state_t), intent(in) :: state
    integer(int32), allocatable, intent(out) :: ids(:)
    integer :: i, n
    integer(int32) :: v
    logical :: found

    if (.not. allocated(state%mesh%elements)) return
    allocate (ids(size(state%mesh%elements)))
    n = 0
    do i = 1, size(state%mesh%elements)
      call opt_get(state%mesh%elements(i)%id, v, found)
      if (.not. found) cycle
      n = n + 1
      ids(n) = v
    end do
    if (n < size(ids)) ids = ids(1:n)
  end subroutine collect_element_ids

  subroutine collect_material_ids(state, ids)
    type(problem_state_t), intent(in) :: state
    integer(int32), allocatable, intent(out) :: ids(:)
    integer :: i, n
    integer(int32) :: v
    logical :: found

    if (.not. allocated(state%materials)) return
    allocate (ids(size(state%materials)))
    n = 0
    do i = 1, size(state%materials)
      call opt_get(state%materials(i)%id, v, found)
      if (.not. found) cycle
      n = n + 1
      ids(n) = v
    end do
    if (n < size(ids)) ids = ids(1:n)
  end subroutine collect_material_ids

  pure integer function size_or_zero_nodes(state) result(n)
    type(problem_state_t), intent(in) :: state
    n = 0
    if (allocated(state%mesh%nodes)) n = size(state%mesh%nodes)
  end function size_or_zero_nodes

  pure integer function size_or_zero_elements(state) result(n)
    type(problem_state_t), intent(in) :: state
    n = 0
    if (allocated(state%mesh%elements)) n = size(state%mesh%elements)
  end function size_or_zero_elements

  pure integer function size_or_zero_materials(state) result(n)
    type(problem_state_t), intent(in) :: state
    n = 0
    if (allocated(state%materials)) n = size(state%materials)
  end function size_or_zero_materials

  pure integer function size_or_zero_sections(state) result(n)
    type(problem_state_t), intent(in) :: state
    n = 0
    if (allocated(state%sections)) n = size(state%sections)
  end function size_or_zero_sections

  pure integer function size_or_zero_amplitudes(state) result(n)
    type(problem_state_t), intent(in) :: state
    n = 0
    if (allocated(state%amplitudes)) n = size(state%amplitudes)
  end function size_or_zero_amplitudes

  pure integer function size_or_zero_nsets(state) result(n)
    type(problem_state_t), intent(in) :: state
    n = 0
    if (allocated(state%mesh%nsets)) n = size(state%mesh%nsets)
  end function size_or_zero_nsets

end module yl_problem_pipeline
