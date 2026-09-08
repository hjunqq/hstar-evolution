! yl_runtime_types -- the M3-03 RuntimeState derived types.
!
! Scope (see .ccg/tasks/m3-03-build-runtime-commit/plan.md delivery 1)
!   Types ONLY. No build, no commit, no legacy write, no I/O. `build_runtime` is
!   yl_runtime_build, `commit_legacy_globals` is yl_runtime_commit and the versioned
!   execution contract that supplies the inputs ProblemState does not carry is
!   yl_runtime_contract. Nothing here reads a legacy global or a solver work array.
!
! What this object graph must hold
!   Every `RuntimeState.*` row of docs/m2/state-field-map.toml whose `checkpoint` is
!   `model_ready`. Query the map, never a number copied into prose:
!
!     python3 -c "import tomllib; d=tomllib.load(open('docs/m2/state-field-map.toml','rb')); \
!       print(sum(1 for f in d['field'] if f['owner'].startswith('RuntimeState.') \
!                 and f['checkpoint']=='model_ready'))"
!
!   Each mapped component below carries a map-provenance marker naming the map row `id`
!   it realises, so the correspondence is mechanical in both directions and a self-test
!   can assert it as a bijection rather than an audit. Harvest them with
!   `grep -o '@map: [a-z0-9_.]*'`. A component with no such marker carries an @unmapped
!   marker and a reason instead.
!
! Where the field names come from
!   The STRUCTURE is taken from the map's `owner` column, never from `id`: the owner
!   groups (dof / boundary / topology / activation / increment / amplitudes / gauss /
!   element / vectors / cursor) become the top-level components in that order.
!
!   The LEAF NAMES are not. Unlike the ProblemState half of the map, the RuntimeState
!   owner paths were never de-legacified: `dof.lmdofn`, `dof.nodfn`, `dof.ntotv`,
!   `topology.unode.ipoin`, `gauss.djacb` are still Fortran slot spellings. M3-01 set the
!   precedent that a state type contains no legacy slot name and that the deny list is
!   harvested mechanically from the map's own `legacy_symbol` leaves
!   (tools/yl_problem_check.py:638). This module therefore keeps an owner leaf only when
!   it is already CAE vocabulary (`fixed_mask`, `prescribed_value`, `dof_index`,
!   `element_count`, `interpolation_count`, `factor`) and renames every other one. So
!   this module deliberately contains no npoin, nelem, mdofn, lmdofn, cdofn, lcdofn,
!   nodfn, ntotv, iffix, ndofix, ldofs, listp_group, unode, djacb, gpcod, cartd, elcod_f,
!   tload, eload, rload, tofor, stfor, toforl, toform, delitfi, deltafi, ice0, iblks,
!   lblks, appear, lineload or linet. The legacy spelling survives only inside the
!   @map provenance comments, which is where the bridge looks it up.
!
! Absence discipline (ADR-0002), inherited verbatim from yl_problem_types
!   `unset`, an explicit zero and an empty collection stay three distinct states:
!     * scalars are the opt_int / opt_real wrappers of yl_problem_optional -- payload
!       private, default-initialised to unset, read only through opt_get / opt_value_or;
!     * collections and per-entity vectors are `allocatable`, where NOT allocated means
!       unset and allocated with size 0 means explicitly empty;
!     * no component carries an aliasing attribute, a sentinel initializer or a
!       declared extent.
!       Extents are derived, so a count is never stored as a field: the M3-02 deferred
!       row `prescribed.ndofix` is `size(runtime%boundary)` and has no component here.
!
! ALIAS-FREE BY CONSTRUCTION -- the one rule a grep gate enforces
!   Every component in this module is a value or an allocatable. None is declared with
!   Fortran's aliasing attribute, and the whole file is written so that the attribute's
!   keyword does not appear in it at all -- so the gate is the simplest possible one:
!
!     grep -ni 'point''er' src/runtime/yl_runtime_types.f90   -> must print nothing
!
!   This is not stylistic. The legacy side reaches these same leaves through aliases
!   (Global.f90:185, Elements.f90:21, Prescrib.f90:25), and codex's ownership analysis is
!   that moving an allocatable container holding such aliases transfers descriptors and
!   NOT the ownership of their targets -- which is how "load two leaks load one", and how
!   a shallow-copied alias becomes a double free. Keeping the runtime side alias-free
!   means allocation status alone is the ownership record, `runtime_free` is total, and
!   the T02 ownership properties are decidable by the compiler rather than by review.
!
! The three ignore situations, and why allocation status alone cannot express them
!   Fourteen of the model_ready rows carry `compare.rule = "ignore"`, so the frozen M2
!   baseline says nothing about their values. They are not one situation but three, and a
!   build that conflates them is claiming more than it proved:
!
!     RESERVED  allocated at this checkpoint, contents deliberately UNDEFINED -- the
!               legacy path does not write them until a later phase (element%tload /
!               eload / rload, the two increment work vectors, the per-block cursors).
!     ABSENT    must stay UNALLOCATED on the static_2d path -- reading it, or even
!               calling associated() on the legacy alias, is undefined
!               (topology.unode.patch_nod, Global.f90:1436-1439, stabpw==0 here).
!     DEFINED   computed, deterministic and fully defined, merely excluded from the
!               snapshot (the mass-rule Gauss geometry, the element coordinate copy,
!               the group patch counts).
!
!   Allocation status separates ABSENT from the other two, and it does so
!   unforgeably. It cannot separate RESERVED from DEFINED, because "these bytes are
!   meaningless" is not a structural property of an allocated array. That distinction is
!   therefore recorded explicitly, per map row, in `runtime%field_status`: a walkable
!   ledger of (map_id, state) pairs that build_runtime fills as it goes. A self-test can
!   then walk it, assert a bijection against the map's model_ready rows, and assert the
!   cross-check that only allocation status can settle -- ABSENT implies the named
!   collection is unallocated, DEFINED and RESERVED imply it is allocated. Values in a
!   RESERVED array must never be read, and the ledger is what makes that statement
!   checkable rather than a comment.
!
! Shape convention
!   As in yl_problem_types, a map `shape` with one dimension more than the owner path's
!   collection depth becomes a deferred-shape array on the entity that owns it. Where the
!   trailing shape symbol is a collection (`nelem`, `ndofix`, `ngroup`, `ntcurve`) the
!   owner group IS that collection and becomes an allocatable array of a per-entity type,
!   so `RuntimeState.element.tload` with shape ['nevab','nelem'] is
!   `runtime%element(ielem)%total_load(:)`. Ragged legacy arrays become one allocatable
!   per collection entry (index_list_t), never one flat array with a stored offset table.
module yl_runtime_types

  use iso_fortran_env, only: int32, real64
  use yl_problem_optional, only: opt_int, opt_real

  implicit none
  private

  ! Default private; every exported entity carries an explicit `public` attribute on its
  ! own declaration, so this module has exactly one place per name.

  public :: runtime_free, runtime_is_empty
  public :: runtime_status_set, runtime_status_get, runtime_status_count, runtime_status_row

  ! Fixed length for a map row id in the status ledger. The longest model_ready
  ! RuntimeState id today is `runtime.topology.listp_group_mgroup` at 36 characters; 48
  ! matches LEN_MAP_ID in yl_problem_profile so the two ledgers render alike.
  integer, parameter, public :: RUNTIME_LEN_MAP_ID = 48

  ! --- value state ------------------------------------------------------------
  ! A discriminator, never a sentinel: it says what may be done with the storage, it
  ! never encodes a value. See "The three ignore situations" above.

  !> Not produced at this checkpoint. The collection is unallocated because build did not
  !> reach it -- a defect, not a decision. Distinct from ABSENT.
  integer(int32), parameter, public :: RUNTIME_VALUE_UNSET = 0_int32
  !> Allocated and every element written by build. The only state whose contents may be
  !> read, compared against the frozen baseline, or committed as a value.
  integer(int32), parameter, public :: RUNTIME_VALUE_DEFINED = 1_int32
  !> Allocated for a later phase; contents are UNDEFINED and must not be read. The legacy
  !> path writes them after model_ready, so there is nothing to compare and nothing to
  !> assert beyond the allocation and its extents.
  integer(int32), parameter, public :: RUNTIME_VALUE_RESERVED = 2_int32
  !> Deliberately NOT allocated on this path, and that absence is the asserted property.
  integer(int32), parameter, public :: RUNTIME_VALUE_ABSENT = 3_int32

  !> One ledger entry: which map row, and what may be done with its storage.
  type, public :: runtime_field_status_t
    character(len=RUNTIME_LEN_MAP_ID) :: map_id = ''
    integer(int32) :: state = RUNTIME_VALUE_UNSET
  end type runtime_field_status_t

  ! --- shared building blocks -------------------------------------------------

  !> One ragged integer list. Unallocated means unset, allocated size 0 means explicitly
  !> empty -- the same two-state reading collections carry everywhere else.
  type, public :: index_list_t
    integer(int32), allocatable :: values(:)
  end type index_list_t

  ! --- dof --------------------------------------------------------------------
  ! RuntimeState.dof (9 mapped rows) plus the two M3-02 deferred component counts.

  !> Per-element, per-field variable indices. One list per element field; on the
  !> static_2d path there is exactly one field (Elements.f90:370), but the level exists
  !> because the map row is shaped per field and a flattened copy would lose that.
  type, public :: element_field_dofs_t
    type(index_list_t), allocatable :: fields(:)
  end type element_field_dofs_t

  type, public :: dof_t
    !> Ordered global component -> active (compressed) index; 0 where the component is
    !> not enabled. Identity on both golden cases because every flag is enabled.
    integer(int32), allocatable :: component_to_active(:)     !@map: runtime.dof.lmdofn
    !> Inverse of component_to_active over the enabled components only. M3-02 deferred
    !> this as `derived.dof.lcdofn`; the DOF table exists here, so it is filled here.
    integer(int32), allocatable :: active_to_component(:)     !@map: derived.dof.lcdofn
    !> Number of enabled global components. M3-02 deferred this as `derived.dof.cdofn`.
    !> Kept as a scalar rather than size(active_to_component) because the legacy table it
    !> mirrors is longer than its defined prefix, so the size is not the count.
    type(opt_int) :: active_component_count                   !@map: derived.dof.cdofn
    !> (active component, node) -> global variable index, 0 where the pair is untouched
    !> by any element field. Node-major numbering (Global.f90:2147-2156).
    integer(int32), allocatable :: node_variables(:,:)        !@map: runtime.dof.nodfn
    !> Total numbered (component, node) pairs; sizes every per-variable vector below.
    type(opt_int) :: variable_count                           !@map: runtime.dof.ntotv
    !> Per variable: 0 free, 1 prescribed, 5 inactive. The literals are contract entries
    !> C-CONSTRAINT-*, not magic numbers invented here.
    integer(int32), allocatable :: fixed_mask(:)              !@map: runtime.dof.iffix
    !> Per variable, in metres. All zero at model_ready; the amplitude scaling happens
    !> after increment_ready(1,1).
    real(real64), allocatable :: prescribed_value(:)          !@map: runtime.dof.fixed
    !> Per variable interpolation-source count; zero on this path, no .nrt input.
    integer(int32), allocatable :: interpolation_count(:)     !@map: runtime.dof.trans_nintf
    !> Per element: the element's ordered global variable indices.
    type(index_list_t), allocatable :: element_variables(:)   !@map: runtime.dof.ldofs
    !> Per element: the same indices split per field.
    type(element_field_dofs_t), allocatable :: element_field_variables(:) !@map: runtime.dof.ldofs_f
  end type dof_t

  ! --- boundary ---------------------------------------------------------------
  ! RuntimeState.boundary (5 mapped rows). One entry per PRESCRIBED RECORD, not per
  ! boundary set and not per unique constrained variable: the legacy loop skips a record
  ! whose resolved variable index is 0 (Prescrib.f90:256), so the record count is neither
  ! of those two. `size(runtime%boundary)` IS the M3-02 deferred `prescribed.ndofix`,
  ! which is why no count component exists.

  type, public :: boundary_record_t
    !> Global variable index this record constrains.
    type(opt_int) :: dof_index                                !@map: runtime.boundary.ldofix
    !> Number of elements attached to the constrained node that carry this component.
    !> Kept as a scalar because it is the legacy-visible extent of the three ragged lists
    !> below, and an allocated-size is not the same claim as a computed count.
    type(opt_int) :: element_count                            !@map: runtime.boundary.lnefix
    !> Attached element ids, in group x group-local-node order.
    integer(int32), allocatable :: attached_element(:)        !@map: runtime.boundary.leldofix
    !> Local variable position within each attached element, (local node - 1) * component
    !> count + component (Prescrib.f90:367).
    integer(int32), allocatable :: attached_local_position(:) !@map: runtime.boundary.levdofix
    !> Field index within each attached element.
    integer(int32), allocatable :: attached_field(:)          !@map: runtime.boundary.lefdofix
  end type boundary_record_t

  ! --- topology ---------------------------------------------------------------
  ! RuntimeState.topology (8 mapped rows across two sub-objects).

  !> Node -> owning sections. `group_count` is per node; the two lists are ragged and
  !> hold group_count entries for that node.
  type, public :: node_section_map_t
    !> Number of sections touching each node.
    integer(int32), allocatable :: group_count(:)             !@map: runtime.topology.listp_group_mgroup
    !> Per node: the section indices touching it.
    type(index_list_t), allocatable :: section_index(:)       !@map: runtime.topology.listp_group_listg
    !> Per node: its position inside each of those sections' node tables.
    type(index_list_t), allocatable :: position_in_section(:) !@map: runtime.topology.listp_group_listp
  end type node_section_map_t

  !> One section-local node.
  type, public :: section_node_t
    !> Global node id of this section-local node.
    type(opt_int) :: node_id                                  !@map: runtime.topology.unode_ipoin
    !> Number of this section's elements attached to the node.
    type(opt_int) :: element_count                            !@map: runtime.topology.unode_ne_unode
    !> Those elements' ids, ragged over section-local nodes.
    integer(int32), allocatable :: elements(:)                !@map: runtime.topology.unode_list
    !> Stabilisation patch size. Assigned only under stabpw==1 with a P or W field
    !> (Global.f90:1425-1439); on static_2d stabpw is 0, so this stays unset and the
    !> ledger records it. Snapshot-excluded either way.
    type(opt_int) :: patch_count                              !@map: runtime.topology.unode_np_unode
    !> Stabilisation patch node list. THE ONE ROW THAT MUST STAY UNALLOCATED: legacy
    !> allocates it only inside that same stabilisation branch and never nullifies it
    !> otherwise, so on this path even associated() is undefined there. Here it is an
    !> allocatable, so "not allocated" is a defined, testable state rather than an
    !> undefined association -- which is precisely what the alias-free rule buys.
    !> Its ledger state must be RUNTIME_VALUE_ABSENT, never UNSET.
    integer(int32), allocatable :: patch_nodes(:)             !@map: runtime.topology.unode_patch_nod
  end type section_node_t

  !> One section's node table, ragged over sections.
  type, public :: section_nodes_t
    type(section_node_t), allocatable :: nodes(:)
  end type section_nodes_t

  type, public :: topology_t
    type(node_section_map_t) :: node_sections
    type(section_nodes_t), allocatable :: sections(:)
  end type topology_t

  ! --- activation -------------------------------------------------------------
  ! RuntimeState.activation (1 mapped row).

  type, public :: activation_t
    !> Per section: the activation state for the current block, or -1 when the section
    !> disappears in it (Fem.f90:1714-1721).
    integer(int32), allocatable :: section_state(:)           !@map: runtime.activation.appear
  end type activation_t

  ! --- increment --------------------------------------------------------------
  ! RuntimeState.increment (2 mapped rows). Both are cold-start policy, not derived
  ! geometry: the contract's C class supplies them.

  type, public :: increment_t
    !> Block being entered at model_ready; 1 on a cold start (Fem.f90:1683).
    type(opt_int) :: current_block                            !@map: runtime.increment.iblks_at_model
    !> Blocks completed before this run; 0 on a cold start (Fem.f90:278).
    type(opt_int) :: completed_blocks                         !@map: runtime.increment.lblks_at_model
  end type increment_t

  ! --- amplitudes -------------------------------------------------------------
  ! RuntimeState.amplitudes[] (1 mapped row), one entry per authored amplitude.

  type, public :: amplitude_state_t
    !> Current scalar factor, dimensionless. Exactly zero at model_ready; first evaluated
    !> after increment_ready(1,1) (Load.f90:166, Fem.f90:3666).
    type(opt_real) :: factor                                  !@map: runtime.amplitudes.dfact
  end type amplitude_state_t

  ! --- gauss ------------------------------------------------------------------
  ! RuntimeState.gauss (5 mapped rows), one entry per element. Two integration rules per
  ! element: `stiffness` is the rule the static_2d path integrates with, `mass` is the
  ! second declared rule whose geometry legacy still evaluates but never consumes here.

  !> One integration rule's evaluated geometry for one element.
  type, public :: integration_rule_t
    !> Per point: det(J) * weight, already weighted (Elements.f90:1363). Not the bare
    !> determinant -- the name says so because the value does.
    real(real64), allocatable :: weighted_jacobian(:)
    !> (dimension, point), in metres: sum over local nodes of N_i * x_i
    !> (Elements.f90:1260).
    real(real64), allocatable :: point_coordinates(:,:)
    !> (dimension, local node, point): shape-function gradients in physical coordinates.
    !> Legacy stores this only for a rule whose name is not 'mass' (Elements.f90:1359),
    !> so on the mass rule it stays UNALLOCATED and its ledger state is ABSENT. It has no
    !> map row at all for that rule, which is why it carries an `!@unmapped:` marker
    !> there rather than a missing one.
    real(real64), allocatable :: shape_gradient(:,:,:)
  end type integration_rule_t

  type, public :: element_gauss_t
    !> The 2x2 rule actually integrated on this path.
    !> weighted_jacobian  !@map: runtime.gauss.djacb
    !> point_coordinates  !@map: runtime.gauss.gpcod
    !> shape_gradient     !@map: runtime.gauss.cartd
    type(integration_rule_t) :: stiffness
    !> The second declared rule. Deterministic and computed, but snapshot-excluded.
    !> weighted_jacobian  !@map: runtime.gauss.djacb_mass
    !> point_coordinates  !@map: runtime.gauss.gpcod_mass
    !> shape_gradient     !@unmapped: legacy never allocates cartd for the mass rule
    !>                    (Elements.f90:1232, :1359), so the map has no cartd_mass row
    !>                    and this component must stay unallocated (ledger ABSENT).
    type(integration_rule_t) :: mass
  end type element_gauss_t

  ! --- element ----------------------------------------------------------------
  ! RuntimeState.element (5 mapped rows), one entry per element.

  type, public :: element_state_t
    !> (dimension, local node), in metres: the element's own copy of its node
    !> coordinates. Computed and deterministic, snapshot-excluded.
    real(real64), allocatable :: field_coordinates(:,:)       !@map: runtime.element.elcod_f
    !> Per element variable, in newtons. RESERVED at model_ready: allocated, never
    !> written before a later phase, so its contents must not be read.
    real(real64), allocatable :: total_load(:)                !@map: runtime.element.tload
    !> Per element variable, in newtons. RESERVED at model_ready.
    real(real64), allocatable :: external_load(:)             !@map: runtime.element.eload
    !> Per element variable, in newtons. RESERVED at model_ready: legacy zeroes it inside
    !> gravity at Load.f90:1237, i.e. after increment_ready(1,1).
    real(real64), allocatable :: body_load(:)                 !@map: runtime.element.rload
    !> Refinement skip flag; 0 on this path (Fem.f90:260).
    type(opt_int) :: refinement_skip                          !@map: runtime.element.ice0
  end type element_state_t

  ! --- vectors ----------------------------------------------------------------
  ! RuntimeState.vectors (7 mapped rows), each sized by dof%variable_count.

  type, public :: vectors_t
    !> Total displacement, metres. Exactly zero at every covered checkpoint.
    real(real64), allocatable :: total_displacement(:)        !@map: runtime.vectors.result_zero
    !> Total external force, newtons. Exactly zero at model_ready.
    real(real64), allocatable :: external_force_total(:)      !@map: runtime.vectors.tofor
    !> Internal force, newtons. Exactly zero at model_ready.
    real(real64), allocatable :: internal_force(:)            !@map: runtime.vectors.stfor
    !> Load-only external force, newtons. Exactly zero at model_ready.
    real(real64), allocatable :: external_force_load(:)       !@map: runtime.vectors.toforl
    !> Mass-related external force, newtons. Exactly zero at model_ready.
    real(real64), allocatable :: external_force_mass(:)       !@map: runtime.vectors.toform
    !> Per-iteration displacement work vector, metres. RESERVED at model_ready.
    real(real64), allocatable :: iteration_displacement(:)    !@map: runtime.vectors.delitfi
    !> Per-increment displacement work vector, metres. RESERVED at model_ready.
    real(real64), allocatable :: increment_displacement(:)    !@map: runtime.vectors.deltafi
  end type vectors_t

  ! --- cursor -----------------------------------------------------------------
  ! RuntimeState.cursor (4 mapped rows). Legacy line cursors kept so a restart can
  ! re-read the load and temperature decks from the right offset. There is no restart on
  ! this path, so all four are RESERVED: allocated or set, but with no value the frozen
  ! baseline or this build can vouch for.

  type, public :: cursor_t
    type(opt_int) :: load_line                                !@map: runtime.cursor.lineload
    integer(int32), allocatable :: load_line_per_block(:)     !@map: runtime.cursor.line_load_block
    type(opt_int) :: temperature_line                         !@map: runtime.cursor.linet
    integer(int32), allocatable :: temperature_line_per_block(:) !@map: runtime.cursor.line_temp_block
  end type cursor_t

  ! --- root -------------------------------------------------------------------
  ! Owner groups in map order. Where the owner group's trailing shape symbol is a
  ! collection the component IS that collection, so `runtime%element(ielem)%total_load`
  ! reads back exactly as `RuntimeState.element.tload` with shape ['nevab','nelem'].

  type, public :: runtime_state_t
    type(dof_t) :: dof
    type(boundary_record_t), allocatable :: boundary(:)
    type(topology_t) :: topology
    type(activation_t) :: activation
    type(increment_t) :: increment
    type(amplitude_state_t), allocatable :: amplitudes(:)
    type(element_gauss_t), allocatable :: gauss(:)
    type(element_state_t), allocatable :: element(:)
    type(vectors_t) :: vectors
    type(cursor_t) :: cursor
    !> The value-state ledger. One entry per model_ready map row, filled by build as it
    !> produces each row. Unallocated means build has not run; allocated size 0 would be
    !> a build that claimed to produce nothing. See the header for why this exists.
    type(runtime_field_status_t), allocatable :: field_status(:) !@unmapped: build provenance, not a state value
  end type runtime_state_t

contains

  ! --- lifetime ---------------------------------------------------------------

  !> Release everything the runtime owns. IDEMPOTENT: calling it twice is a no-op, not a
  !> double free, and calling it on a never-built runtime is also a no-op.
  !>
  !> The implementation is one intrinsic derived-type assignment from a default-
  !> initialised local. That is total by construction: Fortran's intrinsic assignment
  !> deallocates each allocatable component of the destination before (not) allocating it
  !> from the unallocated source, recursively, at every nesting depth. It cannot miss a
  !> component the way a hand-written deallocation walk can when a component is added
  !> later, and it cannot double-free, because deallocating an already-unallocated
  !> allocatable is what the assignment leaves behind, not something it repeats.
  !>
  !> This is only safe because no component is an alias. An aliasing component would be
  !> shallow-copied here and its target leaked; that is the whole reason for the rule.
  pure subroutine runtime_free(runtime)
    type(runtime_state_t), intent(inout) :: runtime
    type(runtime_state_t) :: fresh
    runtime = fresh
  end subroutine runtime_free

  !> True when the runtime holds nothing: no ledger and none of the top-level
  !> collections. The self-test uses it to assert that the second runtime_free changed
  !> nothing, which is a stronger statement than "it did not crash".
  pure logical function runtime_is_empty(runtime) result(is_empty)
    type(runtime_state_t), intent(in) :: runtime
    is_empty = .not. allocated(runtime%field_status) .and.       &
               .not. allocated(runtime%boundary) .and.           &
               .not. allocated(runtime%amplitudes) .and.         &
               .not. allocated(runtime%gauss) .and.              &
               .not. allocated(runtime%element) .and.            &
               .not. allocated(runtime%topology%sections) .and.  &
               .not. allocated(runtime%dof%node_variables) .and. &
               .not. allocated(runtime%vectors%total_displacement)
  end function runtime_is_empty

  ! --- value-state ledger -----------------------------------------------------

  !> Number of ledger entries; 0 when build has not run.
  pure integer function runtime_status_count(runtime) result(n)
    type(runtime_state_t), intent(in) :: runtime
    n = 0
    if (allocated(runtime%field_status)) n = size(runtime%field_status)
  end function runtime_status_count

  !> Copy out ledger entry `i`. `found` is mandatory, as in opt_get and
  !> profile_default_row: an out-of-range index is answered, never assumed away.
  pure subroutine runtime_status_row(runtime, i, row, found)
    type(runtime_state_t), intent(in) :: runtime
    integer, intent(in) :: i
    type(runtime_field_status_t), intent(out) :: row
    logical, intent(out) :: found
    found = .false.
    if (.not. allocated(runtime%field_status)) return
    if (i < 1) return
    if (i > size(runtime%field_status)) return
    row = runtime%field_status(i)
    found = .true.
  end subroutine runtime_status_row

  !> Record the value state of one map row, appending or replacing in place.
  !>
  !> `ok` is .false. when the state is not one of the four constants or when `map_id` is
  !> blank or longer than RUNTIME_LEN_MAP_ID. A silently truncated id would collide with
  !> its neighbour in the ledger and make the self-test's bijection pass on a name that
  !> does not exist, so truncation is refused rather than performed.
  pure subroutine runtime_status_set(runtime, map_id, state, ok)
    type(runtime_state_t), intent(inout) :: runtime
    character(len=*), intent(in) :: map_id
    integer(int32), intent(in) :: state
    logical, intent(out) :: ok
    type(runtime_field_status_t), allocatable :: grown(:)
    integer :: i, n

    ok = .false.
    if (len_trim(map_id) == 0) return
    if (len_trim(map_id) > RUNTIME_LEN_MAP_ID) return
    select case (state)
    case (RUNTIME_VALUE_UNSET, RUNTIME_VALUE_DEFINED, RUNTIME_VALUE_RESERVED, RUNTIME_VALUE_ABSENT)
    case default
      return
    end select

    if (.not. allocated(runtime%field_status)) allocate (runtime%field_status(0))

    n = size(runtime%field_status)
    do i = 1, n
      if (trim(runtime%field_status(i)%map_id) == trim(map_id)) then
        runtime%field_status(i)%state = state
        ok = .true.
        return
      end if
    end do

    allocate (grown(n + 1))
    if (n > 0) grown(1:n) = runtime%field_status(1:n)
    grown(n + 1)%map_id = map_id
    grown(n + 1)%state = state
    call move_alloc(grown, runtime%field_status)
    ok = .true.
  end subroutine runtime_status_set

  !> Read back the value state of one map row. `found` is .false. when the row was never
  !> recorded, which is a different answer from RUNTIME_VALUE_UNSET recorded explicitly.
  pure subroutine runtime_status_get(runtime, map_id, state, found)
    type(runtime_state_t), intent(in) :: runtime
    character(len=*), intent(in) :: map_id
    integer(int32), intent(out) :: state
    logical, intent(out) :: found
    integer :: i

    state = RUNTIME_VALUE_UNSET
    found = .false.
    if (.not. allocated(runtime%field_status)) return
    do i = 1, size(runtime%field_status)
      if (trim(runtime%field_status(i)%map_id) == trim(map_id)) then
        state = runtime%field_status(i)%state
        found = .true.
        return
      end if
    end do
  end subroutine runtime_status_get

end module yl_runtime_types
