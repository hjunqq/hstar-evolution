! yl_runtime_build -- build_runtime: ProblemState + execution contract -> RuntimeState.
!
! Scope (.ccg/tasks/m3-03-build-runtime-commit/plan.md delivery 4)
!   ONE public entry point. It reads a finished `problem_state_t` and the compiled
!   execution contract, and produces the 46 `model_ready` `RuntimeState.*` rows of
!   docs/m2/state-field-map.toml together with the derivation manifest that records how.
!   It writes no legacy global -- that is yl_runtime_commit, the single migration-period
!   writer -- performs no I/O and never mutates its input.
!
! PRECONDITION, and why it is a precondition and not a check
!   `problem` must be the output of `prepare_problem` (yl_problem_pipeline): normalized,
!   validated and past the capability gate. The gate is what establishes that this is a
!   2-D, 4-node, single-field, two-component model with the element kind the contract
!   describes; re-deriving that here would duplicate the gate's rule set in a second
!   place, which is exactly the drift M3-02 was built to prevent. What this module DOES
!   check is the small set of properties the gate cannot see because they only exist once
!   the DOF numbering and the element geometry are known -- rules B1, B2, B3, B6, B8 of
!   yl_runtime_rules. A caller that hands over an ungated draft gets a PE_INTERNAL from
!   the INV- guards rather than undefined behaviour, but it gets no promise beyond that.
!
! THE TRANSACTION, which is the whole point of the task
!   Everything is produced into a LOCAL candidate runtime and a LOCAL manifest. Neither
!   output argument is touched until every rule has passed, every map row has been
!   recorded in the ledger and in the manifest, and the three nets have run. The publish
!   step is then two `move_alloc` calls with nothing between them that can fail. So:
!
!     * a failed build leaves `runtime` and `manifest` bit-for-bit as they were -- and if
!       they held an earlier good build, that build survives;
!     * a failed build leaks no manifest entry, because the entries were never in the
!       caller's manifest to begin with;
!     * there is no state in which some rows are published and others are not.
!
!   `fail_at` exists to make that testable rather than asserted: build_alloc_site_count()
!   numbered sites, each checked immediately before the allocations of one owner group,
!   and T01 walks all of them. It is a TEST HOOK and the only argument this module has
!   that a production caller never passes.
!
! WHAT IS PRODUCED AND WHAT IS MERELY ALLOCATED
!   The ledger `runtime%field_status` carries one entry per map row, with the value state
!   yl_runtime_types defines: DEFINED (computed, readable, comparable), RESERVED
!   (allocated for a later phase, contents undefined, MUST NOT be read) or ABSENT
!   (deliberately unallocated on this path). Fourteen rows are snapshot-excluded and the
!   ledger is what separates the three reasons; see the yl_runtime_types header.
!
! ARITHMETIC FIDELITY
!   The Gauss geometry is written as the legacy statements are written, not as a fresh
!   implementation would write them: explicit accumulation loops where Elements.f90:3245
!   accumulates in a loop, the SUM intrinsic where :1260 uses SUM, `djacb*weigp` in that
!   order at :1363. The quadrature and shape functions come from yl_runtime_contract,
!   which carries the default-real evaluation of the legacy literals. The frozen baseline
!   is compared at rtol 1e-12; none of this is stylistic.
module yl_runtime_build

  use iso_fortran_env, only: int32, int64, real64
  use yl_problem_optional, only: opt_int, opt_real, opt_get, opt_set, opt_is_set
  use yl_problem_types, only: problem_state_t
  use yl_problem_errors, only: problem_errors_t, problem_error_t, make_problem_error,           &
                               PE_DANGLING_REF, PE_DUPLICATE_REF, PE_COUNT_MISMATCH,            &
                               PE_INVALID_INPUT, PE_INTERNAL, PE_EXIT_INTERNAL
  use yl_problem_manifest, only: manifest_t, manifest_text_t, manifest_value_t,                 &
                                 manifest_reset, manifest_add_derived, manifest_add_check,      &
                                 manifest_count, manifest_is_valid, manifest_error,             &
                                 mv_none, mv_i32, mv_f64, mv_i32_list, mv_f64_list,             &
                                 MANIFEST_KIND_CHECK
  use yl_runtime_types, only: runtime_state_t, index_list_t, element_field_dofs_t,              &
                              boundary_record_t, section_node_t, section_nodes_t,               &
                              integration_rule_t, element_gauss_t, element_state_t,             &
                              runtime_status_set, runtime_status_get, runtime_status_count,     &
                              RUNTIME_VALUE_UNSET, RUNTIME_VALUE_DEFINED,                       &
                              RUNTIME_VALUE_RESERVED, RUNTIME_VALUE_ABSENT
  use yl_runtime_contract, only: CONTRACT_TAG, contract_expect_int, contract_expect_real,       &
                                 contract_expect_text, contract_expect_logical,                 &
                                 q4_stiffness_quadrature, q4_mass_quadrature, q4_shape_functions
  use yl_runtime_rules, only: build_rule_t, build_rule_row, build_rule_count, build_rule_key,   &
                              build_rule_expected_state,                                        &
                              build_rule_producer_of, build_rule_input_count_for,               &
                              build_rule_input_at, build_rule_produced_count,                   &
                              build_rule_produced_map_id, PE_STAGE_BUILD, BR_DERIVE

  implicit none
  private

  public :: build_runtime
  public :: build_alloc_site_count, build_alloc_site_id

  ! --- allocation sites -------------------------------------------------------
  ! One per owner group, in the order the build produces them. The count is derived
  ! from the last constant rather than written twice; adding a site means adding a
  ! constant and moving SITE_LAST, and T01 then walks the new site without being told.
  integer, parameter, public :: BUILD_SITE_DOF        = 1
  integer, parameter, public :: BUILD_SITE_TOPOLOGY   = 2
  integer, parameter, public :: BUILD_SITE_BOUNDARY   = 3
  integer, parameter, public :: BUILD_SITE_ACTIVATION = 4
  integer, parameter, public :: BUILD_SITE_INCREMENT  = 5
  integer, parameter, public :: BUILD_SITE_AMPLITUDES = 6
  integer, parameter, public :: BUILD_SITE_GAUSS      = 7
  integer, parameter, public :: BUILD_SITE_ELEMENT    = 8
  integer, parameter, public :: BUILD_SITE_VECTORS    = 9
  integer, parameter, public :: BUILD_SITE_CURSOR     = 10
  integer, parameter, public :: BUILD_SITE_NETS       = 11
  integer, parameter, public :: BUILD_SITE_PUBLISH    = 12
  integer, parameter :: BUILD_SITE_LAST = BUILD_SITE_PUBLISH

  ! --- the derived geometry of one gated model --------------------------------
  ! Counts and index maps derived once and passed down, so no stage re-derives one and
  ! no stage indexes a collection by an authored id. Private: it is scaffolding for the
  ! build, not part of the RuntimeState the map describes.
  type :: build_shape_t
    integer :: npoin = 0            ! count(mesh.nodes)
    integer :: nelem = 0            ! count(mesh.elements)
    integer :: ngroup = 0           ! count(sections) = count(mesh.elsets)
    integer :: ndimn = 0            ! contract element.dimension_count
    integer :: nnode = 0            ! contract element.node_count
    integer :: mdofn = 0            ! contract dof.component_count
    integer :: cdofn = 0            ! enabled components; = mdofn under ALL_ENABLED
    integer :: nrfields = 0         ! contract field.count
    integer :: nfdof = 0            ! components carried by the one field
    integer :: nevab = 0            ! nfdof * nnode
    integer :: ngaus = 0            ! stiffness rule point count
    integer :: ngaus_mass = 0       ! mass rule point count
    integer :: ntotv = 0            ! numbered (component, node) pairs
    integer :: nblks = 0            ! count(steps)
    integer(int32), allocatable :: node_of_id(:)      ! authored node id -> storage index
    integer(int32), allocatable :: elem_of_id(:)      ! authored element id -> storage index
    integer(int32), allocatable :: group_list(:,:)    ! (max nelgroup, ngroup) element indices
    integer(int32), allocatable :: nelgroup(:)        ! elements per group
    real(real64), allocatable :: coord(:,:)           ! (ndimn, npoin), metres
  end type build_shape_t

  ! --- what a net needs to know about one map row's storage ------------------
  ! `form` separates a collection from a scalar wrapper, because "allocated" and "set"
  ! are different questions and RESERVED answers them differently: a reserved ARRAY
  ! exists with a defined shape, a reserved SCALAR claims no value at all.
  integer(int32), parameter :: RS_ARRAY = 1_int32
  integer(int32), parameter :: RS_SCALAR = 2_int32

  type :: row_storage_t
    logical :: known = .false.        ! this row is wired into inspect_row at all
    integer(int32) :: form = RS_ARRAY
    logical :: present_ = .false.     ! allocated (array) or set (scalar)
    integer :: extent = 0             ! total element count; 0 when absent
    logical :: may_be_empty = .false. ! a zero extent is legitimate; the case says why
    logical :: is_f64 = .false.
    logical :: finite = .true.        ! every element equals itself; only read when DEFINED
  end type row_storage_t

contains

  ! ==========================================================================
  ! the public entry point
  ! ==========================================================================

  !> Build the RuntimeState of a gated problem under a named execution contract.
  !>
  !>   problem       the finished ProblemState. intent(in): never modified.
  !>   contract_in   the requested contract tag, e.g. 'static-q4-si/1'. Checked against
  !>                 the compiled contract for the same reason prepare_problem checks
  !>                 its profile tag: a caller asking for a contract this build does not
  !>                 carry must be told so, not silently handed another one's premises.
  !>   runtime       the finished runtime. Untouched unless the whole build succeeds.
  !>   manifest      the derivation manifest. Moves in the same breath as `runtime`.
  !>   errors        findings are APPENDED; earlier findings are preserved.
  !>   declared_ndofix  the deck's declared prescribed-record count, when the reader
  !>                 captured one. Present enables rule B8; absent disables only B8.
  !>   fail_at       TEST HOOK: fail at allocation site `fail_at` (1 .. site count).
  !>
  !> On success both outputs are allocated and no finding was added. On failure neither
  !> output was touched and at least one finding was added.
  subroutine build_runtime(problem, contract_in, runtime, manifest, errors, &
                           declared_ndofix, fail_at)
    type(problem_state_t), intent(in) :: problem
    character(len=*), intent(in) :: contract_in
    type(runtime_state_t), allocatable, intent(inout) :: runtime
    type(manifest_t), allocatable, intent(inout) :: manifest
    type(problem_errors_t), intent(inout) :: errors
    type(opt_int), intent(in), optional :: declared_ndofix
    integer, intent(in), optional :: fail_at

    type(runtime_state_t), allocatable :: cand
    type(manifest_t), allocatable :: record
    type(build_shape_t) :: shape
    integer :: mark

    if (trim(contract_in) /= CONTRACT_TAG) then
      call raise_precondition(errors, PE_INVALID_INPUT, 'B0', 'contract', 'id',                              &
                 'requested contract "'//trim(contract_in)//                                    &
                 '" is not the contract compiled into this build',                              &
                 actual=trim(contract_in), expected=CONTRACT_TAG)
      return
    end if

    mark = errors%count()

    allocate (cand)
    allocate (record)
    call manifest_reset(record)

    call derive_shape(problem, shape, errors)
    if (errors%count() > mark) return

    call build_dof(problem, shape, cand, record, errors, fail_at)
    if (errors%count() > mark) return

    call build_topology(problem, shape, cand, record, errors, fail_at)
    if (errors%count() > mark) return

    call build_boundary(problem, shape, cand, record, errors, declared_ndofix, fail_at)
    if (errors%count() > mark) return

    call build_activation(problem, shape, cand, record, errors, fail_at)
    if (errors%count() > mark) return

    call build_increment(shape, cand, record, errors, fail_at)
    if (errors%count() > mark) return

    call build_amplitudes(problem, cand, record, errors, fail_at)
    if (errors%count() > mark) return

    call build_geometry(problem, shape, cand, record, errors, fail_at)
    if (errors%count() > mark) return

    call build_vectors(shape, cand, record, errors, fail_at)
    if (errors%count() > mark) return

    call build_cursor(shape, cand, record, errors, fail_at)
    if (errors%count() > mark) return

    call run_nets(shape, cand, record, errors, fail_at)
    if (errors%count() > mark) return

    ! --- publish ------------------------------------------------------------
    ! Past this point nothing may fail. The site check and the manifest health check
    ! are BEFORE the first move_alloc, so a failure here still leaves both outputs as
    ! they were; after it, the two moves are unconditional and cannot raise.
    if (injected(fail_at, BUILD_SITE_PUBLISH)) then
      call raise_injected(errors, BUILD_SITE_PUBLISH)
      return
    end if
    if (.not. manifest_is_valid(record)) then
            call raise_row(errors, 'NET-MAP-BIJECTION', 'manifest-derive-rows-match-map',              &
                      'the derivation manifest is malformed: '//manifest_error(record))
      return
    end if
    call move_alloc(cand, runtime)
    call move_alloc(record, manifest)
  end subroutine build_runtime

  !> How many allocation sites the build has. T01 walks 1 .. this.
  pure integer function build_alloc_site_count() result(n)
    n = BUILD_SITE_LAST
  end function build_alloc_site_count

  !> A stable name for site `i`, so a T01 failure names the group rather than a number.
  pure function build_alloc_site_id(i) result(id)
    integer, intent(in) :: i
    character(len=:), allocatable :: id
    select case (i)
    case (BUILD_SITE_DOF);        id = 'dof'
    case (BUILD_SITE_TOPOLOGY);   id = 'topology'
    case (BUILD_SITE_BOUNDARY);   id = 'boundary'
    case (BUILD_SITE_ACTIVATION); id = 'activation'
    case (BUILD_SITE_INCREMENT);  id = 'increment'
    case (BUILD_SITE_AMPLITUDES); id = 'amplitudes'
    case (BUILD_SITE_GAUSS);      id = 'gauss'
    case (BUILD_SITE_ELEMENT);    id = 'element'
    case (BUILD_SITE_VECTORS);    id = 'vectors'
    case (BUILD_SITE_CURSOR);     id = 'cursor'
    case (BUILD_SITE_NETS);       id = 'nets'
    case (BUILD_SITE_PUBLISH);    id = 'publish'
    case default;                 id = ''
    end select
  end function build_alloc_site_id

  ! ==========================================================================
  ! shape derivation
  ! ==========================================================================

  ! Counts, id maps and the coordinate table, derived once.
  !
  ! The id maps are the reason this stage exists. Legacy indexes `coord`, `element` and
  ! `nodfn` by the authored number because its readers write straight into those slots;
  ! ProblemState keeps collections in authoring order and carries the number as data.
  ! Building explicit maps here is what lets every later stage index by STORAGE position
  ! while still resolving an authored reference, without either half assuming the two
  ! coincide -- they do on both golden cases, and that coincidence is not a contract.
  subroutine derive_shape(problem, shape, errors)
    type(problem_state_t), intent(in) :: problem
    type(build_shape_t), intent(out) :: shape
    type(problem_errors_t), intent(inout) :: errors

    integer :: i, j, k, n, max_id, max_group, eid
    integer(int32) :: value
    logical :: found

    call contract_expect_int('element.dimension_count', value, found)
    if (found) shape%ndimn = int(value)
    call contract_expect_int('element.node_count', value, found)
    if (found) shape%nnode = int(value)
    call contract_expect_int('dof.component_count', value, found)
    if (found) shape%mdofn = int(value)
    call contract_expect_int('field.count', value, found)
    if (found) shape%nrfields = int(value)
    call contract_expect_int('integration.stiffness.point_count', value, found)
    if (found) shape%ngaus = int(value)
    call contract_expect_int('integration.mass.point_count', value, found)
    if (found) shape%ngaus_mass = int(value)

    ! The one field carries every enabled global component on this path
    ! (Elements.f90:370-375 declares the field, Global.f90:955 the enabled set).
    shape%nfdof = shape%mdofn
    shape%nevab = shape%nfdof*shape%nnode

    if (allocated(problem%mesh%nodes))    shape%npoin  = size(problem%mesh%nodes)
    if (allocated(problem%mesh%elements)) shape%nelem  = size(problem%mesh%elements)
    if (allocated(problem%mesh%elsets))   shape%ngroup = size(problem%mesh%elsets)
    if (allocated(problem%steps))         shape%nblks  = size(problem%steps)

    if (shape%npoin < 1 .or. shape%nelem < 1 .or. shape%ngroup < 1) then
            call raise_row(errors, 'INV-GATED-SHAPE', 'gated-problem-matches-contract-shape',          &
                      'the gated problem carries no nodes, no elements or no sections')
      return
    end if

    ! authored id -> storage index, for nodes and for elements.
    max_id = 0
    do i = 1, shape%npoin
      call opt_get(problem%mesh%nodes(i)%id, value, found)
      if (found .and. int(value) > max_id) max_id = int(value)
    end do
    allocate (shape%node_of_id(max(max_id, 1)))
    shape%node_of_id = 0_int32
    do i = 1, shape%npoin
      call opt_get(problem%mesh%nodes(i)%id, value, found)
      if (found) shape%node_of_id(int(value)) = int(i, int32)
    end do

    max_id = 0
    do i = 1, shape%nelem
      call opt_get(problem%mesh%elements(i)%id, value, found)
      if (found .and. int(value) > max_id) max_id = int(value)
    end do
    allocate (shape%elem_of_id(max(max_id, 1)))
    shape%elem_of_id = 0_int32
    do i = 1, shape%nelem
      call opt_get(problem%mesh%elements(i)%id, value, found)
      if (found) shape%elem_of_id(int(value)) = int(i, int32)
    end do

    ! Coordinates in storage order. mesh.nodes[].xyz is metres (ADR-0003).
    allocate (shape%coord(shape%ndimn, shape%npoin))
    shape%coord = 0.0_real64
    do i = 1, shape%npoin
      if (.not. allocated(problem%mesh%nodes(i)%xyz)) cycle
      n = min(shape%ndimn, size(problem%mesh%nodes(i)%xyz))
      shape%coord(1:n, i) = problem%mesh%nodes(i)%xyz(1:n)
    end do

    ! group(igroup)%list: the section's elements as STORAGE indices, in authored order
    ! (Global.f90:1361 assigns group%list in exactly that order).
    allocate (shape%nelgroup(shape%ngroup))
    shape%nelgroup = 0_int32
    max_group = 1
    do j = 1, shape%ngroup
      if (.not. allocated(problem%mesh%elsets(j)%elements)) cycle
      n = size(problem%mesh%elsets(j)%elements)
      shape%nelgroup(j) = int(n, int32)
      if (n > max_group) max_group = n
    end do
    allocate (shape%group_list(max_group, shape%ngroup))
    shape%group_list = 0_int32
    do j = 1, shape%ngroup
      if (.not. allocated(problem%mesh%elsets(j)%elements)) cycle
      do k = 1, size(problem%mesh%elsets(j)%elements)
        eid = int(problem%mesh%elsets(j)%elements(k))
        if (eid >= 1 .and. eid <= size(shape%elem_of_id)) then
          shape%group_list(k, j) = shape%elem_of_id(eid)
        end if
      end do
    end do

    ! INV-NEVAB, the precondition guard: every element must carry exactly the node
    ! count the contract declares, or `nevab` is not nnode*nfdof and every per-element
    ! vector below is the wrong length. Unreachable through the capability gate; this
    ! is the answer a caller gets who skipped it.
    do i = 1, shape%nelem
      n = 0
      if (allocated(problem%mesh%elements(i)%nodes)) n = size(problem%mesh%elements(i)%nodes)
      if (n /= shape%nnode) then
                call raise_row(errors, 'INV-NEVAB', 'ldofs-length-is-nnode-x-ndofn',                     &
                        'element carries a node count the contract does not declare',            &
                        actual=itoa(n), expected=itoa(shape%nnode), idx=i)
        return
      end if
    end do
  end subroutine derive_shape

  ! ==========================================================================
  ! dof
  ! ==========================================================================

  ! RuntimeState.dof: the component compression, the node numbering and the per-element
  ! variable lists. Reproduces Global.f90:1119-1125 (compression), :2096-2117 (incidence),
  ! :2147-2156 (numbering) and :2161-2199 (element gather).
  subroutine build_dof(problem, shape, cand, record, errors, fail_at)
    type(problem_state_t), intent(in) :: problem
    type(build_shape_t), intent(inout) :: shape
    type(runtime_state_t), intent(inout) :: cand
    type(manifest_t), intent(inout) :: record
    type(problem_errors_t), intent(inout) :: errors
    integer, intent(in), optional :: fail_at

    integer(int32), allocatable :: flat(:)
    integer :: ig, il, ie, inode, idofn, ipoin, kpoin, idofs, ntotv, n
    character(len=:), allocatable :: policy
    logical :: found

    if (injected(fail_at, BUILD_SITE_DOF)) then
      call raise_injected(errors, BUILD_SITE_DOF)
      return
    end if

    ! --- lmdofn / cdofn / lcdofn (Global.f90:1119-1125) ---------------------
    ! The compression is in place: an enabled component keeps its ordinal among the
    ! enabled ones, a disabled component stays 0. The contract's activation policy is
    ! what says which are enabled; ALL_ENABLED makes the map the identity, and the loop
    ! is written out anyway so that admitting a partially enabled deck later is a
    ! contract change and not a code change.
    call contract_expect_text('dof.activation_policy', policy, found)
    if (.not. found) policy = ''
    allocate (cand%dof%component_to_active(shape%mdofn))
    allocate (cand%dof%active_to_component(shape%mdofn))
    cand%dof%component_to_active = 0_int32
    cand%dof%active_to_component = 0_int32
    shape%cdofn = 0
    do idofn = 1, shape%mdofn
      if (trim(policy) /= 'ALL_ENABLED') cycle
      shape%cdofn = shape%cdofn + 1
      cand%dof%component_to_active(idofn) = int(shape%cdofn, int32)
      cand%dof%active_to_component(shape%cdofn) = int(idofn, int32)
    end do
    if (shape%cdofn < 1) then
            call raise_row(errors, 'INV-GATED-SHAPE', 'gated-problem-matches-contract-shape',          &
                      'the contract enables no global component under policy "'//            trim(policy)//'"')
      return
    end if
    call opt_set(cand%dof%active_component_count, int(shape%cdofn, int32))

    ! --- nodfn incidence and numbering (Global.f90:2096-2156) ---------------
    allocate (cand%dof%node_variables(shape%cdofn, shape%npoin))
    cand%dof%node_variables = 0_int32
    do ig = 1, shape%ngroup
      do il = 1, int(shape%nelgroup(ig))
        ie = int(shape%group_list(il, ig))
        if (ie < 1) cycle
        do inode = 1, shape%nnode
          kpoin = node_index(shape, problem%mesh%elements(ie)%nodes(inode))
          if (kpoin < 1) cycle
          do idofn = 1, shape%nfdof
            cand%dof%node_variables(int(cand%dof%component_to_active(idofn)), kpoin) = 1_int32
          end do
        end do
      end do
    end do

    ntotv = 0
    do ipoin = 1, shape%npoin
      do idofn = 1, shape%cdofn
        if (cand%dof%node_variables(idofn, ipoin) == 1_int32) then
          ntotv = ntotv + 1
          cand%dof%node_variables(idofn, ipoin) = int(ntotv, int32)
        end if
      end do
    end do
    shape%ntotv = ntotv
    if (ntotv < 1) then
            call raise_row(errors, 'INV-NTOTV-POSITIVE', 'ntotv-at-least-one',                         &
                      'the numbering produced no variables')
      return
    end if
    call opt_set(cand%dof%variable_count, int(ntotv, int32))

    ! INV-DOF-DENSE: the non-zero entries of nodfn are exactly 1 .. ntotv, each once.
    ! True by construction of the loop above; asserted because every consumer -- every
    ! per-variable vector, iffix, the commit -- indexes by it.
    if (.not. is_dense_permutation(cand%dof%node_variables, ntotv)) then
            call raise_row(errors, 'INV-DOF-DENSE', 'nodfn-is-dense-permutation',                      &
                      'the node numbering is not a dense permutation of 1..ntotv')
      return
    end if

    ! --- element variable lists (Global.f90:2161-2199) ----------------------
    allocate (cand%dof%element_variables(shape%nelem))
    allocate (cand%dof%element_field_variables(shape%nelem))
    do ie = 1, shape%nelem
      allocate (cand%dof%element_variables(ie)%values(shape%nevab))
      cand%dof%element_variables(ie)%values = 0_int32
      allocate (cand%dof%element_field_variables(ie)%fields(shape%nrfields))
      allocate (cand%dof%element_field_variables(ie)%fields(1)%values(shape%nevab))
      cand%dof%element_field_variables(ie)%fields(1)%values = 0_int32
    end do
    do ig = 1, shape%ngroup
      do il = 1, int(shape%nelgroup(ig))
        ie = int(shape%group_list(il, ig))
        if (ie < 1) cycle
        idofs = 0
        do inode = 1, shape%nnode
          kpoin = node_index(shape, problem%mesh%elements(ie)%nodes(inode))
          if (kpoin < 1) cycle
          do idofn = 1, shape%nfdof
            if (cand%dof%node_variables(int(cand%dof%component_to_active(idofn)), kpoin)        &
                /= 0_int32) then
              idofs = idofs + 1
              cand%dof%element_field_variables(ie)%fields(1)%values(idofs) =                    &
                cand%dof%node_variables(int(cand%dof%component_to_active(idofn)), kpoin)
            end if
          end do
        end do
        cand%dof%element_variables(ie)%values(1:shape%nevab) =                                  &
          cand%dof%element_field_variables(ie)%fields(1)%values(1:shape%nevab)
      end do
    end do

    ! --- trans%nintf: no .nrt input on this path (Global.f90:1489) ----------
    allocate (cand%dof%interpolation_count(ntotv))
    cand%dof%interpolation_count = 0_int32

    ! iffix / fixed are sized here and filled by build_boundary, which is where the
    ! prescriptions are known. They are recorded there, not here.
    allocate (cand%dof%fixed_mask(ntotv))
    allocate (cand%dof%prescribed_value(ntotv))

    ! --- record -------------------------------------------------------------
    call publish_i32_list(cand, record, 'runtime.dof.lmdofn', cand%dof%component_to_active,     &
                          RUNTIME_VALUE_DEFINED, errors)
    call publish_i32_list(cand, record, 'runtime.dof.nodfn',                                    &
                          reshape(cand%dof%node_variables, [shape%cdofn*shape%npoin]),          &
                          RUNTIME_VALUE_DEFINED, errors)
    call publish_i32(cand, record, 'runtime.dof.ntotv', int(ntotv, int32),                      &
                     RUNTIME_VALUE_DEFINED, errors)
    n = shape%nevab*shape%nelem
    allocate (flat(n))
    do ie = 1, shape%nelem
      flat((ie - 1)*shape%nevab + 1:ie*shape%nevab) = cand%dof%element_variables(ie)%values
    end do
    call publish_i32_list(cand, record, 'runtime.dof.ldofs', flat, RUNTIME_VALUE_DEFINED, errors)
    do ie = 1, shape%nelem
      flat((ie - 1)*shape%nevab + 1:ie*shape%nevab) =                                           &
        cand%dof%element_field_variables(ie)%fields(1)%values
    end do
    call publish_i32_list(cand, record, 'runtime.dof.ldofs_f', flat, RUNTIME_VALUE_DEFINED, errors)
    deallocate (flat)
    call publish_i32_list(cand, record, 'runtime.dof.trans_nintf', cand%dof%interpolation_count, &
                          RUNTIME_VALUE_DEFINED, errors)
  end subroutine build_dof

  ! ==========================================================================
  ! topology
  ! ==========================================================================

  ! RuntimeState.topology: the per-section node tables and the node -> section index.
  ! Reproduces Global.f90:1370-1421 (unode) and :1464-1478 (listp_group).
  !
  ! Two ordering facts are load-bearing and are why this is written as three passes
  ! rather than one: `unode` runs in ASCENDING GLOBAL NODE ORDER inside a section
  ! (:1383, :1395), while each node's element list runs in the section's ELEMENT
  ! OCCURRENCE ORDER (:1408). A single pass would have to pick one of the two.
  subroutine build_topology(problem, shape, cand, record, errors, fail_at)
    type(problem_state_t), intent(in) :: problem
    type(build_shape_t), intent(in) :: shape
    type(runtime_state_t), intent(inout) :: cand
    type(manifest_t), intent(inout) :: record
    type(problem_errors_t), intent(inout) :: errors
    integer, intent(in), optional :: fail_at

    integer(int32), allocatable :: appear_node(:), corsp(:), listx(:), flat(:)
    integer :: ig, il, ie, inode, ipoin, np_unode, kpoin, i, n, total

    if (injected(fail_at, BUILD_SITE_TOPOLOGY)) then
      call raise_injected(errors, BUILD_SITE_TOPOLOGY)
      return
    end if

    allocate (cand%topology%node_sections%group_count(shape%npoin))
    cand%topology%node_sections%group_count = 0_int32
    allocate (cand%topology%sections(shape%ngroup))
    allocate (appear_node(shape%npoin), corsp(shape%npoin), listx(shape%npoin))

    do ig = 1, shape%ngroup
      appear_node = 0_int32
      corsp = 0_int32
      do il = 1, int(shape%nelgroup(ig))
        ie = int(shape%group_list(il, ig))
        if (ie < 1) cycle
        do inode = 1, shape%nnode
          kpoin = node_index(shape, problem%mesh%elements(ie)%nodes(inode))
          if (kpoin < 1) cycle
          appear_node(kpoin) = appear_node(kpoin) + 1_int32
        end do
      end do

      np_unode = 0
      do ipoin = 1, shape%npoin
        if (appear_node(ipoin) /= 0_int32) then
          np_unode = np_unode + 1
          corsp(ipoin) = int(np_unode, int32)
          cand%topology%node_sections%group_count(ipoin) =                                      &
            cand%topology%node_sections%group_count(ipoin) + 1_int32
        end if
      end do

      allocate (cand%topology%sections(ig)%nodes(np_unode))
      np_unode = 0
      do ipoin = 1, shape%npoin
        if (appear_node(ipoin) == 0_int32) cycle
        np_unode = np_unode + 1
        call opt_set(cand%topology%sections(ig)%nodes(np_unode)%node_id, int(ipoin, int32))
        call opt_set(cand%topology%sections(ig)%nodes(np_unode)%element_count, appear_node(ipoin))
        allocate (cand%topology%sections(ig)%nodes(np_unode)%elements(appear_node(ipoin)))
        cand%topology%sections(ig)%nodes(np_unode)%elements = 0_int32
        ! patch_count stays unset and patch_nodes stays UNALLOCATED: the stabilisation
        ! branch at Global.f90:1425-1439 is not taken on this path (stabpw == 0), and
        ! reading either there is undefined. The ledger records that as ABSENT.
      end do

      listx = 0_int32
      do il = 1, int(shape%nelgroup(ig))
        ie = int(shape%group_list(il, ig))
        if (ie < 1) cycle
        do inode = 1, shape%nnode
          kpoin = node_index(shape, problem%mesh%elements(ie)%nodes(inode))
          if (kpoin < 1) cycle
          listx(kpoin) = listx(kpoin) + 1_int32
          cand%topology%sections(ig)%nodes(int(corsp(kpoin)))%elements(int(listx(kpoin))) =     &
            int(ie, int32)
        end do
      end do
    end do

    ! listp_group: one (section, position) pair per section touching the node, filled in
    ! ascending section order (Global.f90:1470-1477).
    allocate (cand%topology%node_sections%section_index(shape%npoin))
    allocate (cand%topology%node_sections%position_in_section(shape%npoin))
    do ipoin = 1, shape%npoin
      n = int(cand%topology%node_sections%group_count(ipoin))
      allocate (cand%topology%node_sections%section_index(ipoin)%values(n))
      allocate (cand%topology%node_sections%position_in_section(ipoin)%values(n))
      cand%topology%node_sections%section_index(ipoin)%values = 0_int32
      cand%topology%node_sections%position_in_section(ipoin)%values = 0_int32
    end do
    listx = 0_int32
    do ig = 1, shape%ngroup
      do i = 1, size(cand%topology%sections(ig)%nodes)
        ipoin = int(int_or_zero(cand%topology%sections(ig)%nodes(i)%node_id))
        if (ipoin < 1) cycle
        listx(ipoin) = listx(ipoin) + 1_int32
        cand%topology%node_sections%section_index(ipoin)%values(int(listx(ipoin))) =            &
          int(ig, int32)
        cand%topology%node_sections%position_in_section(ipoin)%values(int(listx(ipoin))) =      &
          int(i, int32)
      end do
    end do
    deallocate (appear_node, corsp, listx)

    ! --- record -------------------------------------------------------------
    call publish_i32_list(cand, record, 'runtime.topology.listp_group_mgroup',                  &
                          cand%topology%node_sections%group_count, RUNTIME_VALUE_DEFINED, errors)
    call publish_ragged(cand, record, 'runtime.topology.listp_group_listg',                     &
                        cand%topology%node_sections%section_index, RUNTIME_VALUE_DEFINED, errors)
    call publish_ragged(cand, record, 'runtime.topology.listp_group_listp',                     &
                        cand%topology%node_sections%position_in_section,                        &
                        RUNTIME_VALUE_DEFINED, errors)

    total = 0
    do ig = 1, shape%ngroup
      total = total + size(cand%topology%sections(ig)%nodes)
    end do
    allocate (flat(total))
    n = 0
    do ig = 1, shape%ngroup
      do i = 1, size(cand%topology%sections(ig)%nodes)
        n = n + 1
        flat(n) = int_or_zero(cand%topology%sections(ig)%nodes(i)%node_id)
      end do
    end do
    call publish_i32_list(cand, record, 'runtime.topology.unode_ipoin', flat,                   &
                          RUNTIME_VALUE_DEFINED, errors)
    n = 0
    do ig = 1, shape%ngroup
      do i = 1, size(cand%topology%sections(ig)%nodes)
        n = n + 1
        flat(n) = int_or_zero(cand%topology%sections(ig)%nodes(i)%element_count)
      end do
    end do
    call publish_i32_list(cand, record, 'runtime.topology.unode_ne_unode', flat,                &
                          RUNTIME_VALUE_DEFINED, errors)
    deallocate (flat)

    total = 0
    do ig = 1, shape%ngroup
      do i = 1, size(cand%topology%sections(ig)%nodes)
        total = total + size(cand%topology%sections(ig)%nodes(i)%elements)
      end do
    end do
    allocate (flat(total))
    n = 0
    do ig = 1, shape%ngroup
      do i = 1, size(cand%topology%sections(ig)%nodes)
        do il = 1, size(cand%topology%sections(ig)%nodes(i)%elements)
          n = n + 1
          flat(n) = cand%topology%sections(ig)%nodes(i)%elements(il)
        end do
      end do
    end do
    call publish_i32_list(cand, record, 'runtime.topology.unode_list', flat,                    &
                          RUNTIME_VALUE_DEFINED, errors)
    deallocate (flat)

    ! The two stabilisation rows. np_unode is not assigned on this path and patch_nod is
    ! not allocated; both are recorded as produced-with-nothing, which is a claim the
    ! ledger can check (ABSENT implies unallocated) rather than a silence.
    call publish_absent(cand, record, 'runtime.topology.unode_np_unode', errors)
    call publish_absent(cand, record, 'runtime.topology.unode_patch_nod', errors)
  end subroutine build_topology

  ! ==========================================================================
  ! boundary and the constraint mask
  ! ==========================================================================

  ! RuntimeState.boundary and RuntimeState.dof.{iffix,fixed}.
  ! Reproduces Prescrib.f90:59-76 (mask initialisation), :253-262 (record admission and
  ! the prescribed mark) and :320-368 (the attachment lists).
  !
  ! ONE ENTRY PER RECORD, not per boundary set and not per constrained variable. That is
  ! what `ndofix` counts (Prescrib.f90:257), and it is why `size(runtime%boundary)` is
  ! the answer to the M3-02 deferred `prescribed.ndofix` and no count is stored.
  !
  ! WHERE THIS IS DELIBERATELY STRICTER THAN LEGACY
  !   Legacy skips a record whose resolved variable index is 0 and carries on
  !   (`if (idofn==0) goto 1`, recorded as the contract entry
  !   `boundary.skip_unnumbered_record`). That silence hides two very different things:
  !   a component the model does not carry at that node -- ordinary, and skipped here
  !   too -- and a constrained node that no element touches at all, which is a deck
  !   defect whose only symptom under legacy is a constraint that quietly does nothing.
  !   Rule B1 separates them and refuses the second. On a deck legacy accepts the two
  !   builds agree; on a deck with a dangling constrained node they differ, and that
  !   difference is intended and is stated here rather than discovered later.
  subroutine build_boundary(problem, shape, cand, record, errors, declared_ndofix, fail_at)
    type(problem_state_t), intent(in) :: problem
    type(build_shape_t), intent(in) :: shape
    type(runtime_state_t), intent(inout) :: cand
    type(manifest_t), intent(inout) :: record
    type(problem_errors_t), intent(inout) :: errors
    type(opt_int), intent(in), optional :: declared_ndofix
    integer, intent(in), optional :: fail_at

    type(boundary_record_t), allocatable :: recs(:)
    integer(int32), allocatable :: flat(:), touched(:)
    integer(int32) :: mask_inactive, mask_free, mask_prescribed, comp, node_id, declared
    real(real64) :: value_at_model
    integer :: nrec, i, j, k, ig, il, ie, inode, ipoin, kpoin, idofn, nd, lnefix, pos
    integer :: active, total
    logical :: found, in_group

    if (injected(fail_at, BUILD_SITE_BOUNDARY)) then
      call raise_injected(errors, BUILD_SITE_BOUNDARY)
      return
    end if

    call contract_expect_int('constraint.mask_inactive', mask_inactive, found)
    if (.not. found) mask_inactive = 5_int32
    call contract_expect_int('constraint.mask_free', mask_free, found)
    if (.not. found) mask_free = 0_int32
    call contract_expect_int('constraint.mask_prescribed_base', mask_prescribed, found)
    if (.not. found) mask_prescribed = 1_int32
    call contract_expect_real('constraint.value_at_model_ready', value_at_model, found)
    if (.not. found) value_at_model = 0.0_real64

    ! --- iffix (Prescrib.f90:59-76) ----------------------------------------
    ! Everything inactive, then freed variable by variable for the elements of an
    ! ACTIVE section that refinement did not skip. `ice0` is zero everywhere on this
    ! path (Fem.f90:260), so the second condition never excludes an element here; the
    ! loop is written with it anyway because the value is a contract entry, not a
    ! constant this module gets to assume away.
    cand%dof%fixed_mask = mask_inactive
    cand%dof%prescribed_value = value_at_model
    do ig = 1, shape%ngroup
      active = 0
      if (allocated(problem%steps)) then
        if (size(problem%steps) >= 1) then
          if (allocated(problem%steps(1)%activation)) then
            if (ig <= size(problem%steps(1)%activation)) then
              active = int(int_or_zero(problem%steps(1)%activation(ig)%active))
            end if
          end if
        end if
      end if
      if (active <= 0) cycle
      do il = 1, int(shape%nelgroup(ig))
        ie = int(shape%group_list(il, ig))
        if (ie < 1) cycle
        do k = 1, shape%nevab
          idofn = int(cand%dof%element_variables(ie)%values(k))
          if (idofn >= 1) cand%dof%fixed_mask(idofn) = mask_free
        end do
      end do
    end do

    ! --- which nodes any element touches, for B1 ----------------------------
    allocate (touched(shape%npoin))
    touched = 0_int32
    do ie = 1, shape%nelem
      do inode = 1, shape%nnode
        kpoin = node_index(shape, problem%mesh%elements(ie)%nodes(inode))
        if (kpoin >= 1) touched(kpoin) = 1_int32
      end do
    end do

    ! --- the records --------------------------------------------------------
    nrec = 0
    if (allocated(problem%steps)) then
      if (size(problem%steps) >= 1) then
        if (allocated(problem%steps(1)%boundary)) nrec = size(problem%steps(1)%boundary)
      end if
    end if
    allocate (recs(nrec))
    nd = 0

    do i = 1, nrec
      node_id = int_or_zero(problem%steps(1)%boundary(i)%nset)
      comp = int_or_zero(problem%steps(1)%boundary(i)%dof)

      ! B2 -- the component must exist in the compression table at all.
      if (comp < 1_int32 .or. int(comp) > shape%mdofn) then
                call raise_row(errors, 'B2', 'dof-out-of-range',                                         &
                        'prescribed component is outside the model''s global component range',   &
                        actual=itoa(int(comp)), expected='1..'//itoa(shape%mdofn), idx=i)
        return
      end if

      ipoin = node_index(shape, node_id)
      if (ipoin < 1) then
                call raise_row(errors, 'B1', 'node-not-attached',                                        &
                        'prescribed node is not a node of this mesh', actual=itoa(int(node_id)), &
                        idx=i)
        return
      end if

      ! B1 -- a constrained node no element touches. See the header note above.
      if (touched(ipoin) == 0_int32) then
                call raise_row(errors, 'B1', 'node-not-attached',                                        &
                        'prescribed node is attached to no element, so the constraint '//             'would silently do nothing',&
                        actual=itoa(int(node_id)), idx=i)
        return
      end if

      ! B6 -- the same (node, component) prescribed twice. Legacy would write the second
      ! record's mask over the first and keep both in `prescrib`, so the deck would run
      ! with a constraint the author cannot see in the output.
      do j = 1, i - 1
        if (int_or_zero(problem%steps(1)%boundary(j)%nset) == node_id .and.                     &
            int_or_zero(problem%steps(1)%boundary(j)%dof) == comp) then
                    call raise_row(errors, 'B6', 'duplicate-prescribed-pair',                              &
                          'this (node, component) pair is already prescribed by an earlier record',&
                          actual='node '//itoa(int(node_id))//' component '//itoa(int(comp)),    &
                          idx=i)
          return
        end if
      end do

      idofn = int(cand%dof%node_variables(int(cand%dof%component_to_active(int(comp))), ipoin))
      if (idofn == 0) cycle          ! contract boundary.skip_unnumbered_record

      nd = nd + 1
      call opt_set(recs(nd)%dof_index, int(idofn, int32))
      cand%dof%fixed_mask(idofn) = mask_prescribed

      ! lnefix, pass one (Prescrib.f90:320-340): the ALLOCATED length, counted per
      ! section that touches the node, once per field component equal to the prescribed
      ! one. Pass two below fills the arrays over the distinct attached elements.
      lnefix = 0
      do ig = 1, shape%ngroup
        in_group = .false.
        pos = 0
        do k = 1, int(cand%topology%node_sections%group_count(ipoin))
          if (int(cand%topology%node_sections%section_index(ipoin)%values(k)) == ig) then
            in_group = .true.
            pos = int(cand%topology%node_sections%position_in_section(ipoin)%values(k))
            exit
          end if
        end do
        if (.not. in_group) cycle
        do idofn = 1, shape%nfdof
          if (idofn == int(comp)) then
            lnefix = lnefix + int(int_or_zero(cand%topology%sections(ig)%nodes(pos)%element_count))
          end if
        end do
      end do
      call opt_set(recs(nd)%element_count, int(lnefix, int32))
      allocate (recs(nd)%attached_element(lnefix))
      allocate (recs(nd)%attached_local_position(lnefix))
      allocate (recs(nd)%attached_field(lnefix))
      recs(nd)%attached_element = 0_int32
      recs(nd)%attached_local_position = 0_int32
      recs(nd)%attached_field = 0_int32

      ! pass two (Prescrib.f90:344-368): distinct elements in section-node order, local
      ! position (local node - 1) * component count + component.
      lnefix = 0
      do ig = 1, shape%ngroup
        in_group = .false.
        pos = 0
        do k = 1, int(cand%topology%node_sections%group_count(ipoin))
          if (int(cand%topology%node_sections%section_index(ipoin)%values(k)) == ig) then
            in_group = .true.
            pos = int(cand%topology%node_sections%position_in_section(ipoin)%values(k))
            exit
          end if
        end do
        if (.not. in_group) cycle
        do il = 1, size(cand%topology%sections(ig)%nodes(pos)%elements)
          ie = int(cand%topology%sections(ig)%nodes(pos)%elements(il))
          if (ie < 1) cycle
          if (seen_before(cand%topology%sections(ig)%nodes(pos)%elements, il, int(ie, int32))) cycle
          do inode = 1, shape%nnode
            kpoin = node_index(shape, problem%mesh%elements(ie)%nodes(inode))
            if (kpoin /= ipoin) cycle
            do idofn = 1, shape%nfdof
              if (idofn /= int(comp)) cycle
              lnefix = lnefix + 1
              if (lnefix > size(recs(nd)%attached_element)) then
                call raise_row(errors, 'INV-BOUNDARY-ATTACH', 'attachment-passes-agree',       &
                               'the attachment count of pass two exceeds the length pass '//    &
                               'one allocated', idx=i)
                return
              end if
              recs(nd)%attached_element(lnefix) = int(ie, int32)
              recs(nd)%attached_local_position(lnefix) =                                        &
                int((inode - 1)*shape%nfdof + idofn, int32)
              recs(nd)%attached_field(lnefix) = 1_int32
            end do
          end do
        end do
      end do

      ! The symmetric half of the over-fill guard above. Pass one SIZED these lists and
      ! pass two FILLED them; if pass two stops short, the tail keeps the zeros the
      ! allocation was initialised with and the record silently claims attachments that
      ! do not exist. Legacy has the same two-pass structure (Prescrib.f90:320-340 then
      ! :344-368) and the same exposure -- it stores pass one's count as `lnefix` and
      ! never checks that pass two reached it. Checking is cheap and the failure is
      ! otherwise invisible until a solver reads element 0.
      if (lnefix /= size(recs(nd)%attached_element)) then
        call raise_row(errors, 'INV-BOUNDARY-ATTACH', 'attachment-passes-agree',                &
                       'pass two filled fewer attachments than pass one allocated',             &
                       actual=itoa(lnefix), expected=itoa(size(recs(nd)%attached_element)),     &
                       idx=i)
        return
      end if
    end do

    ! Trim to the admitted records: `nd` is ndofix, and a boundary array longer than it
    ! would publish records the build did not admit.
    if (nd == nrec) then
      call move_alloc(recs, cand%boundary)
    else
      allocate (cand%boundary(nd))
      do i = 1, nd
        cand%boundary(i) = recs(i)
      end do
      deallocate (recs)
    end if
    deallocate (touched)

    ! B8 -- the deck's declared prescribed-record count against the derived one.
    if (present(declared_ndofix)) then
      call opt_get(declared_ndofix, declared, found)
      if (found .and. int(declared) /= nd) then
                call raise_row(errors, 'B8', 'declared-count-mismatch',                                  &
                        'the declared prescribed-record count disagrees with the derived one',   &
                        actual=itoa(nd), expected=itoa(int(declared)))
        return
      end if
    end if

    ! --- record -------------------------------------------------------------
    allocate (flat(nd))
    do i = 1, nd
      flat(i) = int_or_zero(cand%boundary(i)%dof_index)
    end do
    call publish_i32_list(cand, record, 'runtime.boundary.ldofix', flat,                        &
                          RUNTIME_VALUE_DEFINED, errors)
    do i = 1, nd
      flat(i) = int_or_zero(cand%boundary(i)%element_count)
    end do
    call publish_i32_list(cand, record, 'runtime.boundary.lnefix', flat,                        &
                          RUNTIME_VALUE_DEFINED, errors)
    deallocate (flat)

    total = 0
    do i = 1, nd
      total = total + size(cand%boundary(i)%attached_element)
    end do
    allocate (flat(total))
    k = 0
    do i = 1, nd
      do j = 1, size(cand%boundary(i)%attached_element)
        k = k + 1
        flat(k) = cand%boundary(i)%attached_element(j)
      end do
    end do
    call publish_i32_list(cand, record, 'runtime.boundary.leldofix', flat,                      &
                          RUNTIME_VALUE_DEFINED, errors)
    k = 0
    do i = 1, nd
      do j = 1, size(cand%boundary(i)%attached_local_position)
        k = k + 1
        flat(k) = cand%boundary(i)%attached_local_position(j)
      end do
    end do
    call publish_i32_list(cand, record, 'runtime.boundary.levdofix', flat,                      &
                          RUNTIME_VALUE_DEFINED, errors)
    k = 0
    do i = 1, nd
      do j = 1, size(cand%boundary(i)%attached_field)
        k = k + 1
        flat(k) = cand%boundary(i)%attached_field(j)
      end do
    end do
    call publish_i32_list(cand, record, 'runtime.boundary.lefdofix', flat,                      &
                          RUNTIME_VALUE_DEFINED, errors)
    deallocate (flat)

    call publish_i32_list(cand, record, 'runtime.dof.iffix', cand%dof%fixed_mask,               &
                          RUNTIME_VALUE_DEFINED, errors)
    call publish_f64_list(cand, record, 'runtime.dof.fixed', cand%dof%prescribed_value,         &
                          RUNTIME_VALUE_DEFINED, errors)
  end subroutine build_boundary

  ! ==========================================================================
  ! activation, increment, amplitudes
  ! ==========================================================================

  ! RuntimeState.activation.appear: the per-section activation of the block being
  ! entered (Fem.f90:1714-1721). A section the step does not mention is -1, which is the
  ! legacy spelling of "this section disappears in this block" and is NOT the same as 0.
  subroutine build_activation(problem, shape, cand, record, errors, fail_at)
    type(problem_state_t), intent(in) :: problem
    type(build_shape_t), intent(in) :: shape
    type(runtime_state_t), intent(inout) :: cand
    type(manifest_t), intent(inout) :: record
    type(problem_errors_t), intent(inout) :: errors
    integer, intent(in), optional :: fail_at
    integer :: ig

    if (injected(fail_at, BUILD_SITE_ACTIVATION)) then
      call raise_injected(errors, BUILD_SITE_ACTIVATION)
      return
    end if

    allocate (cand%activation%section_state(shape%ngroup))
    cand%activation%section_state = -1_int32
    if (allocated(problem%steps)) then
      if (size(problem%steps) >= 1) then
        if (allocated(problem%steps(1)%activation)) then
          do ig = 1, min(shape%ngroup, size(problem%steps(1)%activation))
            if (opt_is_set(problem%steps(1)%activation(ig)%active)) then
              cand%activation%section_state(ig) =                                               &
                int_or_zero(problem%steps(1)%activation(ig)%active)
            end if
          end do
        end if
      end if
    end if

    call publish_i32_list(cand, record, 'runtime.activation.appear',                            &
                          cand%activation%section_state, RUNTIME_VALUE_DEFINED, errors)
  end subroutine build_activation

  ! RuntimeState.increment: the two cold-start block counters. Both come from the
  ! contract's C class and neither is derived from the model, which is why they are
  ! recorded with the contract's origin as their only input.
  subroutine build_increment(shape, cand, record, errors, fail_at)
    type(build_shape_t), intent(in) :: shape
    type(runtime_state_t), intent(inout) :: cand
    type(manifest_t), intent(inout) :: record
    type(problem_errors_t), intent(inout) :: errors
    integer, intent(in), optional :: fail_at
    integer(int32) :: first_block, completed
    logical :: found

    if (injected(fail_at, BUILD_SITE_INCREMENT)) then
      call raise_injected(errors, BUILD_SITE_INCREMENT)
      return
    end if

    call contract_expect_int('block.first_index', first_block, found)
    if (.not. found) first_block = 1_int32
    call contract_expect_int('restart.completed_blocks', completed, found)
    if (.not. found) completed = 0_int32
    if (shape%nblks < 1) then
            call raise_row(errors, 'INV-GATED-SHAPE', 'gated-problem-matches-contract-shape',          &
                      'the gated problem declares no step, so there is no block to enter')
      return
    end if

    call opt_set(cand%increment%current_block, first_block)
    call opt_set(cand%increment%completed_blocks, completed)
    call publish_i32(cand, record, 'runtime.increment.iblks_at_model', first_block,             &
                     RUNTIME_VALUE_DEFINED, errors)
    call publish_i32(cand, record, 'runtime.increment.lblks_at_model', completed,               &
                     RUNTIME_VALUE_DEFINED, errors)
  end subroutine build_increment

  ! RuntimeState.amplitudes[].factor: exactly zero at model_ready. The curve is not
  ! evaluated until after increment_ready(1,1) (Load.f90:166, Fem.f90:3666), so this is
  ! the cold-start value and not a sample of the authored curve.
  subroutine build_amplitudes(problem, cand, record, errors, fail_at)
    type(problem_state_t), intent(in) :: problem
    type(runtime_state_t), intent(inout) :: cand
    type(manifest_t), intent(inout) :: record
    type(problem_errors_t), intent(inout) :: errors
    integer, intent(in), optional :: fail_at
    real(real64), allocatable :: flat(:)
    real(real64) :: factor
    integer :: n, i
    logical :: found

    if (injected(fail_at, BUILD_SITE_AMPLITUDES)) then
      call raise_injected(errors, BUILD_SITE_AMPLITUDES)
      return
    end if

    call contract_expect_real('amplitude.factor_at_model_ready', factor, found)
    if (.not. found) factor = 0.0_real64
    n = 0
    if (allocated(problem%amplitudes)) n = size(problem%amplitudes)
    allocate (cand%amplitudes(n))
    allocate (flat(n))
    do i = 1, n
      call opt_set(cand%amplitudes(i)%factor, factor)
      flat(i) = factor
    end do
    call publish_f64_list(cand, record, 'runtime.amplitudes.dfact', flat,                       &
                          RUNTIME_VALUE_DEFINED, errors)
  end subroutine build_amplitudes

  ! ==========================================================================
  ! element geometry: the Gauss rules and the element coordinate copy
  ! ==========================================================================

  ! RuntimeState.gauss and RuntimeState.element.
  ! Reproduces Elements.f90:1206-1214 (elcod_f), :1244-1367 (the point loop) and
  ! :3245-3319 (jacob), for both declared integration rules.
  !
  ! The mass rule is evaluated even though the static_2d path never consumes it
  ! (`order_intrules = (/1,1/)`, Elements.f90:377): read_element evaluates the geometry
  ! of every declared rule, so a RuntimeState that omitted it would not be the state the
  ! legacy solver has at model_ready. Its shape gradients are the exception -- legacy
  ! allocates `cartd` only for a rule whose name is not 'mass' (:1232), so that component
  ! stays unallocated and has no map row at all.
  subroutine build_geometry(problem, shape, cand, record, errors, fail_at)
    type(problem_state_t), intent(in) :: problem
    type(build_shape_t), intent(in) :: shape
    type(runtime_state_t), intent(inout) :: cand
    type(manifest_t), intent(inout) :: record
    type(problem_errors_t), intent(inout) :: errors
    integer, intent(in), optional :: fail_at

    real(real64), allocatable :: elcod(:,:), flat(:)
    real(real64) :: stiff_points(2, 4), stiff_weights(4)
    real(real64) :: mass_points(2, 16), mass_weights(16)
    integer(int32) :: skip
    integer :: ie, inode, kpoin, n
    logical :: found, ok

    if (injected(fail_at, BUILD_SITE_GAUSS)) then
      call raise_injected(errors, BUILD_SITE_GAUSS)
      return
    end if

    call q4_stiffness_quadrature(stiff_points, stiff_weights)
    call q4_mass_quadrature(mass_points, mass_weights)

    allocate (cand%gauss(shape%nelem))
    allocate (elcod(shape%ndimn, shape%nnode))

    do ie = 1, shape%nelem
      do inode = 1, shape%nnode
        kpoin = node_index(shape, problem%mesh%elements(ie)%nodes(inode))
        if (kpoin < 1) then
                    call raise_row(errors, 'INV-GATED-SHAPE', 'gated-problem-matches-contract-shape',      &
                          'element references a node that is not in the mesh', idx=ie)
          return
        end if
        elcod(:, inode) = shape%coord(:, kpoin)
      end do

      call evaluate_rule(shape, elcod, stiff_points(:, 1:shape%ngaus),                          &
                         stiff_weights(1:shape%ngaus), .true., cand%gauss(ie)%stiffness,        &
                         ie, errors, ok)
      if (.not. ok) return
      call evaluate_rule(shape, elcod, mass_points(:, 1:shape%ngaus_mass),                      &
                         mass_weights(1:shape%ngaus_mass), .false., cand%gauss(ie)%mass,        &
                         ie, errors, ok)
      if (.not. ok) return
    end do

    ! --- record the Gauss rows ---------------------------------------------
    allocate (flat(shape%ngaus*shape%nelem))
    do ie = 1, shape%nelem
      flat((ie - 1)*shape%ngaus + 1:ie*shape%ngaus) = cand%gauss(ie)%stiffness%weighted_jacobian
    end do
    call publish_f64_list(cand, record, 'runtime.gauss.djacb', flat, RUNTIME_VALUE_DEFINED, errors)
    deallocate (flat)

    n = shape%ndimn*shape%ngaus
    allocate (flat(n*shape%nelem))
    do ie = 1, shape%nelem
      flat((ie - 1)*n + 1:ie*n) = reshape(cand%gauss(ie)%stiffness%point_coordinates, [n])
    end do
    call publish_f64_list(cand, record, 'runtime.gauss.gpcod', flat, RUNTIME_VALUE_DEFINED, errors)
    deallocate (flat)

    n = shape%ndimn*shape%nnode*shape%ngaus
    allocate (flat(n*shape%nelem))
    do ie = 1, shape%nelem
      flat((ie - 1)*n + 1:ie*n) = reshape(cand%gauss(ie)%stiffness%shape_gradient, [n])
    end do
    call publish_f64_list(cand, record, 'runtime.gauss.cartd', flat, RUNTIME_VALUE_DEFINED, errors)
    deallocate (flat)

    allocate (flat(shape%ngaus_mass*shape%nelem))
    do ie = 1, shape%nelem
      flat((ie - 1)*shape%ngaus_mass + 1:ie*shape%ngaus_mass) =                                 &
        cand%gauss(ie)%mass%weighted_jacobian
    end do
    call publish_f64_list(cand, record, 'runtime.gauss.djacb_mass', flat,                       &
                          RUNTIME_VALUE_DEFINED, errors)
    deallocate (flat)

    n = shape%ndimn*shape%ngaus_mass
    allocate (flat(n*shape%nelem))
    do ie = 1, shape%nelem
      flat((ie - 1)*n + 1:ie*n) = reshape(cand%gauss(ie)%mass%point_coordinates, [n])
    end do
    call publish_f64_list(cand, record, 'runtime.gauss.gpcod_mass', flat,                       &
                          RUNTIME_VALUE_DEFINED, errors)
    deallocate (flat)

    ! --- RuntimeState.element ----------------------------------------------
    if (injected(fail_at, BUILD_SITE_ELEMENT)) then
      call raise_injected(errors, BUILD_SITE_ELEMENT)
      return
    end if

    call contract_expect_int('element.refinement_skip_default', skip, found)
    if (.not. found) skip = 0_int32

    allocate (cand%element(shape%nelem))
    do ie = 1, shape%nelem
      allocate (cand%element(ie)%field_coordinates(shape%ndimn, shape%nnode))
      do inode = 1, shape%nnode
        kpoin = node_index(shape, problem%mesh%elements(ie)%nodes(inode))
        cand%element(ie)%field_coordinates(:, inode) = shape%coord(:, kpoin)
      end do
      ! RESERVED: allocated at model_ready, written no earlier than Load.f90:1237.
      ! Nothing here writes them and nothing may read them; the ledger says so.
      allocate (cand%element(ie)%total_load(shape%nevab))
      allocate (cand%element(ie)%external_load(shape%nevab))
      allocate (cand%element(ie)%body_load(shape%nevab))
      call opt_set(cand%element(ie)%refinement_skip, skip)
    end do

    n = shape%ndimn*shape%nnode
    allocate (flat(n*shape%nelem))
    do ie = 1, shape%nelem
      flat((ie - 1)*n + 1:ie*n) = reshape(cand%element(ie)%field_coordinates, [n])
    end do
    call publish_f64_list(cand, record, 'runtime.element.elcod_f', flat,                        &
                          RUNTIME_VALUE_DEFINED, errors)
    deallocate (flat)

    call publish_reserved(cand, record, 'runtime.element.tload', errors)
    call publish_reserved(cand, record, 'runtime.element.eload', errors)
    call publish_reserved(cand, record, 'runtime.element.rload', errors)

    block
      integer(int32), allocatable :: ice(:)
      allocate (ice(shape%nelem))
      do ie = 1, shape%nelem
        ice(ie) = int_or_zero(cand%element(ie)%refinement_skip)
      end do
      call publish_i32_list(cand, record, 'runtime.element.ice0', ice,                          &
                            RUNTIME_VALUE_DEFINED, errors)
    end block
  end subroutine build_geometry

  ! One integration rule's geometry for one element.
  !
  ! `with_gradients` is .false. for the mass rule, where legacy allocates no `cartd`
  ! (Elements.f90:1232) -- the component then stays unallocated, which is the ABSENT
  ! state and not an omission.
  !
  ! The Jacobian is accumulated in explicit loops rather than with MATMUL, and the
  ! Gauss-point coordinate uses SUM, because that is what Elements.f90:3245-3253 and
  ! :1260 do and the two disagree in the last bits.
  subroutine evaluate_rule(shape, elcod, points, weights, with_gradients, rule, ie, errors, ok)
    type(build_shape_t), intent(in) :: shape
    real(real64), intent(in) :: elcod(:,:)
    real(real64), intent(in) :: points(:,:)
    real(real64), intent(in) :: weights(:)
    logical, intent(in) :: with_gradients
    type(integration_rule_t), intent(inout) :: rule
    integer, intent(in) :: ie
    type(problem_errors_t), intent(inout) :: errors
    logical, intent(out) :: ok

    real(real64) :: values(4), gradients(2, 4), xjacm(2, 2), xjaci(2, 2)
    real(real64) :: djacb, acc
    integer :: ngaus, igaus, id, jd, inode

    ok = .false.
    ngaus = size(weights)
    allocate (rule%weighted_jacobian(ngaus))
    allocate (rule%point_coordinates(shape%ndimn, ngaus))
    if (with_gradients) allocate (rule%shape_gradient(shape%ndimn, shape%nnode, ngaus))

    do igaus = 1, ngaus
      call q4_shape_functions(points(1, igaus), points(2, igaus), values, gradients)

      do id = 1, shape%ndimn                                   ! Elements.f90:1259-1261
        rule%point_coordinates(id, igaus) =                                                     &
          sum(elcod(id, 1:shape%nnode)*values(1:shape%nnode))
      end do

      do id = 1, shape%ndimn                                   ! Elements.f90:3245-3253
        do jd = 1, shape%ndimn
          acc = 0.0_real64
          do inode = 1, shape%nnode
            acc = acc + gradients(id, inode)*elcod(jd, inode)
          end do
          xjacm(id, jd) = acc
        end do
      end do

      djacb = xjacm(1, 1)*xjacm(2, 2) - xjacm(1, 2)*xjacm(2, 1)   ! Elements.f90:3263

      ! B3 -- legacy prints a warning here and integrates anyway (Elements.f90:3264-3271).
      ! A non-positive determinant means the connectivity is not counter-clockwise under
      ! the contract's node order, and every quantity derived from this element is then
      ! meaningless; refusing is the whole point of having the rule.
      if (djacb <= 0.0_real64) then
        call raise_row(errors, 'B3', 'negative-jacobian',                                        &
                       'the Jacobian determinant is not positive at a Gauss point: the '//       &
                       'connectivity is not counter-clockwise under the contract node order',    &
                       actual=ftoa(djacb), expected='> 0', idx=ie)
        return
      end if

      xjaci(1, 1) = xjacm(2, 2)/djacb                          ! Elements.f90:3272-3275
      xjaci(2, 2) = xjacm(1, 1)/djacb
      xjaci(1, 2) = -xjacm(1, 2)/djacb
      xjaci(2, 1) = -xjacm(2, 1)/djacb

      if (with_gradients) then                                 ! Elements.f90:3310-3318
        do id = 1, shape%ndimn
          do inode = 1, shape%nnode
            acc = 0.0_real64
            do jd = 1, shape%ndimn
              acc = acc + xjaci(id, jd)*gradients(jd, inode)
            end do
            rule%shape_gradient(id, inode, igaus) = acc
          end do
        end do
      end if

      rule%weighted_jacobian(igaus) = djacb*weights(igaus)     ! Elements.f90:1363
    end do
    ok = .true.
  end subroutine evaluate_rule

  ! ==========================================================================
  ! vectors and cursors
  ! ==========================================================================

  ! RuntimeState.vectors: seven per-variable vectors. Five are exactly zero at
  ! model_ready (Fem.f90:219) and are compared against the frozen baseline; the two
  ! iteration work vectors are RESERVED -- allocated to their final length, written no
  ! earlier than the first increment, and excluded from the snapshot for that reason.
  subroutine build_vectors(shape, cand, record, errors, fail_at)
    type(build_shape_t), intent(in) :: shape
    type(runtime_state_t), intent(inout) :: cand
    type(manifest_t), intent(inout) :: record
    type(problem_errors_t), intent(inout) :: errors
    integer, intent(in), optional :: fail_at
    real(real64) :: zero
    logical :: found

    if (injected(fail_at, BUILD_SITE_VECTORS)) then
      call raise_injected(errors, BUILD_SITE_VECTORS)
      return
    end if

    call contract_expect_real('vector.value_at_model_ready', zero, found)
    if (.not. found) zero = 0.0_real64

    allocate (cand%vectors%total_displacement(shape%ntotv))
    allocate (cand%vectors%external_force_total(shape%ntotv))
    allocate (cand%vectors%internal_force(shape%ntotv))
    allocate (cand%vectors%external_force_load(shape%ntotv))
    allocate (cand%vectors%external_force_mass(shape%ntotv))
    cand%vectors%total_displacement = zero
    cand%vectors%external_force_total = zero
    cand%vectors%internal_force = zero
    cand%vectors%external_force_load = zero
    cand%vectors%external_force_mass = zero

    allocate (cand%vectors%iteration_displacement(shape%ntotv))
    allocate (cand%vectors%increment_displacement(shape%ntotv))

    call publish_f64_list(cand, record, 'runtime.vectors.result_zero',                          &
                          cand%vectors%total_displacement, RUNTIME_VALUE_DEFINED, errors)
    call publish_f64_list(cand, record, 'runtime.vectors.tofor',                                &
                          cand%vectors%external_force_total, RUNTIME_VALUE_DEFINED, errors)
    call publish_f64_list(cand, record, 'runtime.vectors.stfor',                                &
                          cand%vectors%internal_force, RUNTIME_VALUE_DEFINED, errors)
    call publish_f64_list(cand, record, 'runtime.vectors.toforl',                               &
                          cand%vectors%external_force_load, RUNTIME_VALUE_DEFINED, errors)
    call publish_f64_list(cand, record, 'runtime.vectors.toform',                               &
                          cand%vectors%external_force_mass, RUNTIME_VALUE_DEFINED, errors)
    call publish_reserved(cand, record, 'runtime.vectors.delitfi', errors)
    call publish_reserved(cand, record, 'runtime.vectors.deltafi', errors)
  end subroutine build_vectors

  ! RuntimeState.cursor: the four legacy line cursors into the load and temperature
  ! decks. All four are RESERVED.
  !
  ! `lineload` is the one map row on this path whose source is a pair of READER ids and
  ! not a `derived:` rule -- legacy copies it through from the deck offsets. ProblemState
  ! carries no reader line offset, by design: it is a representation of the model, not of
  ! the file it was read from. So there is nothing to copy and nothing to check, and this
  ! build records that as a check with no value on either side rather than inventing a
  ! number that would then look verified. The restart that would consume it does not
  ! exist on this path (contract `restart.enabled` is false); if restart is ever admitted,
  ! this row needs a real source and this entry must stop being vacuous.
  subroutine build_cursor(shape, cand, record, errors, fail_at)
    type(build_shape_t), intent(in) :: shape
    type(runtime_state_t), intent(inout) :: cand
    type(manifest_t), intent(inout) :: record
    type(problem_errors_t), intent(inout) :: errors
    integer, intent(in), optional :: fail_at

    if (injected(fail_at, BUILD_SITE_CURSOR)) then
      call raise_injected(errors, BUILD_SITE_CURSOR)
      return
    end if

    allocate (cand%cursor%load_line_per_block(shape%nblks))
    allocate (cand%cursor%temperature_line_per_block(shape%nblks))

    call publish_check_vacuous(cand, record, 'runtime.cursor.lineload', errors)
    call publish_reserved(cand, record, 'runtime.cursor.line_load_block', errors)
    call publish_reserved(cand, record, 'runtime.cursor.linet', errors)
    call publish_reserved(cand, record, 'runtime.cursor.line_temp_block', errors)
  end subroutine build_cursor

  ! ==========================================================================
  ! the nets
  ! ==========================================================================

  ! The three catch-alls of yl_runtime_rules, run once over the finished candidate.
  ! They exist for the reason the M3-02 nets exist: a rule set is a list of the mistakes
  ! that were anticipated, and a net is what catches the rest. A net firing is always a
  ! broken build, never a bad deck, so all three raise PE_INTERNAL.
  ! The catch-alls of yl_runtime_rules, run once over the finished candidate.
  ! They exist for the reason the M3-02 nets exist: a rule set is a list of the mistakes
  ! that were anticipated, and a net is what catches the rest. A net firing is always a
  ! broken build, never a bad deck, so all three raise PE_INTERNAL.
  !
  ! ALL THREE ARE TOTAL, AND THAT IS THE POINT OF THIS ROUTINE'S SHAPE.
  !   The first M3-03 draft named four arrays for NET-EMPTY-RT and four rows for
  !   NET-SNAN while their comments claimed to cover every published array and every
  !   DEFINED f64 row. Nine of the thirteen DEFINED f64 rows were in fact unchecked, and
  !   the T02 bit-for-bit property could not compensate: it compares two builds against
  !   each other, so the same uninitialised garbage in both reads as "equal".
  !
  !   So the nets now WALK THE LEDGER instead of naming rows. Every row the rule table
  !   produces is visited, its storage facts are read out of `inspect_row`, and a row
  !   that `inspect_row` does not know about fails the walk. That last part is what keeps
  !   this honest as the map grows: adding a map row without wiring it into the inspector
  !   is a failing build, not a silently unchecked row.
  subroutine run_nets(shape, cand, record, errors, fail_at)
    type(build_shape_t), intent(in) :: shape
    type(runtime_state_t), intent(inout) :: cand
    type(manifest_t), intent(inout) :: record
    type(problem_errors_t), intent(inout) :: errors
    integer, intent(in), optional :: fail_at

    type(row_storage_t) :: st
    integer :: i, produced
    integer(int32) :: state, declared
    logical :: found
    character(len=:), allocatable :: map_id

    if (injected(fail_at, BUILD_SITE_NETS)) then
      call raise_injected(errors, BUILD_SITE_NETS)
      return
    end if

    produced = build_rule_produced_count()

    ! NET-MAP-BIJECTION, the half that is checkable from inside a build: every produced
    ! row has a ledger entry and the ledger holds nothing else. The map side is asserted
    ! by tools/yl_state_map.py runtime-rules against the self-test's export, because
    ! Fortran cannot read the .toml.
    if (runtime_status_count(cand) /= produced) then
      call raise_row(errors, 'NET-MAP-BIJECTION', 'manifest-derive-rows-match-map',              &
                     'the ledger holds a row the rule table does not produce',                   &
                     actual=itoa(runtime_status_count(cand)), expected=itoa(produced))
      return
    end if
    if (manifest_count(record) /= produced) then
      call raise_row(errors, 'NET-MAP-BIJECTION', 'manifest-derive-rows-match-map',              &
                     'the manifest entry count disagrees with the produced-row count',           &
                     actual=itoa(manifest_count(record)), expected=itoa(produced))
      return
    end if

    do i = 1, build_rule_count()
      if (build_rule_expected_state(i) == RUNTIME_VALUE_UNSET) cycle    ! not a produced row
      map_id = trim(build_rule_produced_map_id_of(i))
      declared = build_rule_expected_state(i)

      call runtime_status_get(cand, map_id, state, found)
      if (.not. found) then
        call raise_row(errors, 'NET-MAP-BIJECTION', 'manifest-derive-rows-match-map',            &
                       'the build produced no ledger entry for map row '//map_id)
        return
      end if

      ! The rule table's `condition` column, checked rather than believed. Six rows were
      ! found drifted at M3-03 review; this is what stops that happening silently again.
      if (state /= declared) then
        call raise_row(errors, 'NET-MAP-BIJECTION', 'manifest-derive-rows-match-map',            &
                       'the ledger state of '//map_id//' disagrees with the value state its '//  &
                       'rule row declares', actual=state_name(state), expected=state_name(declared))
        return
      end if

      call inspect_row(cand, map_id, state, st)
      if (.not. st%known) then
        call raise_row(errors, 'NET-MAP-BIJECTION', 'manifest-derive-rows-match-map',            &
                       'map row '//map_id//' is produced but is not wired into inspect_row, '//  &
                       'so the nets cannot see its storage')
        return
      end if

      select case (state)
      case (RUNTIME_VALUE_DEFINED, RUNTIME_VALUE_RESERVED)
        ! NET-EMPTY-RT. A DEFINED or RESERVED row must have storage. For a collection the
        ! extent must also be non-zero, EXCEPT where the row is sized by a collection the
        ! model may legitimately have none of -- each such row says so at its case in
        ! inspect_row, with its reason. A reserved SCALAR claims no value, so there is
        ! nothing to size and nothing to check.
        if (.not. st%present_) then
          if (.not. (st%form == RS_SCALAR .and. state == RUNTIME_VALUE_RESERVED)) then
            call raise_row(errors, 'NET-EMPTY-RT', 'no-zero-length-published-array',             &
                           'the build published '//map_id//' with no storage at all')
            return
          end if
        else if (st%form == RS_ARRAY .and. st%extent == 0 .and. .not. st%may_be_empty) then
          call raise_row(errors, 'NET-EMPTY-RT', 'no-zero-length-published-array',               &
                         'the build published a zero-length array: '//map_id)
          return
        end if

        ! NET-SNAN. Only a DEFINED f64 row is read: under the strict profile an
        ! allocatable that was allocated and never written holds a signalling NaN, so a
        ! row the ledger calls DEFINED but the build forgot to fill is caught here rather
        ! than three stages later. A RESERVED row is deliberately NOT read -- reading it
        ! is the thing the ledger forbids -- which is why inspect_row is told the state.
        if (state == RUNTIME_VALUE_DEFINED .and. st%is_f64 .and. .not. st%finite) then
          call raise_row(errors, 'NET-SNAN', 'f64-field-equals-itself',                          &
                         'a row the ledger calls DEFINED holds a value that is not a '//         &
                         'number: '//map_id)
          return
        end if

      case (RUNTIME_VALUE_ABSENT)
        ! The absence IS the asserted property, so it is checked over every entity and
        ! not sampled at index 1.
        if (st%present_) then
          call raise_row(errors, 'NET-EMPTY-RT', 'no-zero-length-published-array',               &
                         'the ledger records '//map_id//' as ABSENT but its storage exists')
          return
        end if
      end select
    end do

    if (shape%ntotv < 1) then
      call raise_row(errors, 'INV-NTOTV-POSITIVE', 'ntotv-at-least-one',                         &
                     'the finished runtime carries no variables')
    end if
  end subroutine run_nets

  ! A readable name for a ledger state, for a failure message only.
  pure function state_name(state) result(t)
    integer(int32), intent(in) :: state
    character(len=:), allocatable :: t
    select case (state)
    case (RUNTIME_VALUE_DEFINED);  t = 'built/DEFINED'
    case (RUNTIME_VALUE_RESERVED); t = 'reserved/RESERVED'
    case (RUNTIME_VALUE_ABSENT);   t = 'unallocated/ABSENT'
    case default;                  t = 'UNSET'
    end select
  end function state_name

  ! The map id row `i` produces. A thin wrapper so the nets can walk the rule table by
  ! index and still ask for the id, without the caller re-deriving the derive-row order.
  pure function build_rule_produced_map_id_of(i) result(map_id)
    integer, intent(in) :: i
    character(len=:), allocatable :: map_id
    type(build_rule_t) :: row
    logical :: found
    map_id = ''
    call build_rule_row(i, row, found)
    if (found) map_id = trim(row%map_id)
  end function build_rule_produced_map_id_of

  ! --- per-row storage facts --------------------------------------------------
  !
  ! THE one place that knows where each of the 46 model_ready rows physically lives.
  !
  ! `state` is an INPUT because it decides what may be READ. A RESERVED row's contents
  ! are undefined and touching them is precisely the violation the ledger exists to
  ! forbid, so `finite` is computed only for a DEFINED f64 row. A net that had to read a
  ! value to find out whether it was allowed to read it would be self-defeating.
  !
  ! A row this routine does not recognise leaves `known` .false. and run_nets fails the
  ! build on it. So the cost of adding a map row without wiring it in here is a RED
  ! BUILD, not a quietly unchecked row -- which is exactly the failure mode the named-row
  ! nets had before the M3-03 Round-1 review.
  subroutine inspect_row(cand, map_id, state, st)
    type(runtime_state_t), intent(in) :: cand
    character(len=*), intent(in) :: map_id
    integer(int32), intent(in) :: state
    type(row_storage_t), intent(out) :: st

    logical :: read_values, ok
    real(real64) :: rv
    integer :: i, j, n

    st%known = .true.
    read_values = (state == RUNTIME_VALUE_DEFINED)

    select case (map_id)

    ! --- dof ----------------------------------------------------------------
    case ('runtime.dof.lmdofn');       call rs_i32_1(st, cand%dof%component_to_active)
    case ('runtime.dof.nodfn');        call rs_i32_2(st, cand%dof%node_variables)
    case ('runtime.dof.iffix');        call rs_i32_1(st, cand%dof%fixed_mask)
    case ('runtime.dof.trans_nintf');  call rs_i32_1(st, cand%dof%interpolation_count)
    case ('runtime.dof.fixed');        call rs_f64_1(st, cand%dof%prescribed_value, read_values)
    case ('runtime.dof.ntotv');        call rs_scalar_int(st, cand%dof%variable_count)
    case ('runtime.dof.ldofs')
      st%form = RS_ARRAY
      st%present_ = allocated(cand%dof%element_variables)
      if (st%present_) then
        do i = 1, size(cand%dof%element_variables)
          if (allocated(cand%dof%element_variables(i)%values))                                  &
            st%extent = st%extent + size(cand%dof%element_variables(i)%values)
        end do
      end if
    case ('runtime.dof.ldofs_f')
      st%form = RS_ARRAY
      st%present_ = allocated(cand%dof%element_field_variables)
      if (st%present_) then
        do i = 1, size(cand%dof%element_field_variables)
          if (.not. allocated(cand%dof%element_field_variables(i)%fields)) cycle
          do j = 1, size(cand%dof%element_field_variables(i)%fields)
            if (allocated(cand%dof%element_field_variables(i)%fields(j)%values))                 &
              st%extent = st%extent + size(cand%dof%element_field_variables(i)%fields(j)%values)
          end do
        end do
      end if

    ! --- boundary -----------------------------------------------------------
    ! may_be_empty: `ndofix` counts prescribed RECORDS, and nothing in the capability
    ! gate requires a model to carry one. An empty boundary collection is a model with
    ! no prescribed dof -- degenerate for a static analysis, but the solver's complaint
    ! to make, not this net's.
    case ('runtime.boundary.ldofix', 'runtime.boundary.lnefix')
      st%form = RS_ARRAY
      st%may_be_empty = .true.
      st%present_ = allocated(cand%boundary)
      if (st%present_) st%extent = size(cand%boundary)
    case ('runtime.boundary.leldofix', 'runtime.boundary.levdofix', 'runtime.boundary.lefdofix')
      st%form = RS_ARRAY
      st%may_be_empty = .true.
      st%present_ = allocated(cand%boundary)
      if (st%present_) then
        do i = 1, size(cand%boundary)
          select case (map_id)
          case ('runtime.boundary.leldofix')
            if (allocated(cand%boundary(i)%attached_element))                                   &
              st%extent = st%extent + size(cand%boundary(i)%attached_element)
          case ('runtime.boundary.levdofix')
            if (allocated(cand%boundary(i)%attached_local_position))                            &
              st%extent = st%extent + size(cand%boundary(i)%attached_local_position)
          case default
            if (allocated(cand%boundary(i)%attached_field))                                     &
              st%extent = st%extent + size(cand%boundary(i)%attached_field)
          end select
        end do
      end if

    ! --- topology -----------------------------------------------------------
    case ('runtime.topology.listp_group_mgroup')
      call rs_i32_1(st, cand%topology%node_sections%group_count)
    case ('runtime.topology.listp_group_listg')
      call rs_ragged(st, cand%topology%node_sections%section_index)
    case ('runtime.topology.listp_group_listp')
      call rs_ragged(st, cand%topology%node_sections%position_in_section)
    case ('runtime.topology.unode_ipoin', 'runtime.topology.unode_ne_unode')
      st%form = RS_ARRAY
      st%present_ = allocated(cand%topology%sections)
      if (st%present_) then
        do i = 1, size(cand%topology%sections)
          if (allocated(cand%topology%sections(i)%nodes))                                       &
            st%extent = st%extent + size(cand%topology%sections(i)%nodes)
        end do
      end if
    case ('runtime.topology.unode_list')
      st%form = RS_ARRAY
      st%present_ = allocated(cand%topology%sections)
      if (st%present_) then
        do i = 1, size(cand%topology%sections)
          if (.not. allocated(cand%topology%sections(i)%nodes)) cycle
          do j = 1, size(cand%topology%sections(i)%nodes)
            if (allocated(cand%topology%sections(i)%nodes(j)%elements))                         &
              st%extent = st%extent + size(cand%topology%sections(i)%nodes(j)%elements)
          end do
        end do
      end if
    ! The two stabilisation rows. ABSENT is the asserted property, so `present_` must be
    ! true if ANY section-local node carries the storage -- checked over every section
    ! and every node, never sampled, because a loop-index bug that regresses on entity 2
    ! is exactly what a sample cannot see.
    case ('runtime.topology.unode_np_unode')
      st%form = RS_SCALAR
      if (allocated(cand%topology%sections)) then
        outer_np: do i = 1, size(cand%topology%sections)
          if (.not. allocated(cand%topology%sections(i)%nodes)) cycle
          do j = 1, size(cand%topology%sections(i)%nodes)
            if (opt_is_set(cand%topology%sections(i)%nodes(j)%patch_count)) then
              st%present_ = .true.
              exit outer_np
            end if
          end do
        end do outer_np
      end if
    case ('runtime.topology.unode_patch_nod')
      st%form = RS_ARRAY
      if (allocated(cand%topology%sections)) then
        outer_pn: do i = 1, size(cand%topology%sections)
          if (.not. allocated(cand%topology%sections(i)%nodes)) cycle
          do j = 1, size(cand%topology%sections(i)%nodes)
            if (allocated(cand%topology%sections(i)%nodes(j)%patch_nodes)) then
              st%present_ = .true.
              exit outer_pn
            end if
          end do
        end do outer_pn
      end if

    ! --- gauss --------------------------------------------------------------
    case ('runtime.gauss.djacb', 'runtime.gauss.gpcod', 'runtime.gauss.cartd',                   &
          'runtime.gauss.djacb_mass', 'runtime.gauss.gpcod_mass')
      st%form = RS_ARRAY
      st%is_f64 = .true.
      st%present_ = allocated(cand%gauss)
      if (st%present_) then
        do i = 1, size(cand%gauss)
          select case (map_id)
          case ('runtime.gauss.djacb')
            call rs_add_f64_1(st, cand%gauss(i)%stiffness%weighted_jacobian, read_values)
          case ('runtime.gauss.gpcod')
            call rs_add_f64_2(st, cand%gauss(i)%stiffness%point_coordinates, read_values)
          case ('runtime.gauss.cartd')
            call rs_add_f64_3(st, cand%gauss(i)%stiffness%shape_gradient, read_values)
          case ('runtime.gauss.djacb_mass')
            call rs_add_f64_1(st, cand%gauss(i)%mass%weighted_jacobian, read_values)
          case default
            call rs_add_f64_2(st, cand%gauss(i)%mass%point_coordinates, read_values)
          end select
        end do
      end if

    ! --- element ------------------------------------------------------------
    case ('runtime.element.elcod_f', 'runtime.element.tload', 'runtime.element.eload',           &
          'runtime.element.rload')
      st%form = RS_ARRAY
      st%is_f64 = .true.
      st%present_ = allocated(cand%element)
      if (st%present_) then
        do i = 1, size(cand%element)
          select case (map_id)
          case ('runtime.element.elcod_f')
            call rs_add_f64_2(st, cand%element(i)%field_coordinates, read_values)
          case ('runtime.element.tload')
            call rs_add_f64_1(st, cand%element(i)%total_load, read_values)
          case ('runtime.element.eload')
            call rs_add_f64_1(st, cand%element(i)%external_load, read_values)
          case default
            call rs_add_f64_1(st, cand%element(i)%body_load, read_values)
          end select
        end do
      end if
    case ('runtime.element.ice0')
      st%form = RS_ARRAY
      st%present_ = allocated(cand%element)
      if (st%present_) then
        n = 0
        do i = 1, size(cand%element)
          if (opt_is_set(cand%element(i)%refinement_skip)) n = n + 1
        end do
        st%extent = n
      end if

    ! --- vectors ------------------------------------------------------------
    case ('runtime.vectors.result_zero')
      call rs_f64_1(st, cand%vectors%total_displacement, read_values)
    case ('runtime.vectors.tofor')
      call rs_f64_1(st, cand%vectors%external_force_total, read_values)
    case ('runtime.vectors.stfor')
      call rs_f64_1(st, cand%vectors%internal_force, read_values)
    case ('runtime.vectors.toforl')
      call rs_f64_1(st, cand%vectors%external_force_load, read_values)
    case ('runtime.vectors.toform')
      call rs_f64_1(st, cand%vectors%external_force_mass, read_values)
    case ('runtime.vectors.delitfi')
      call rs_f64_1(st, cand%vectors%iteration_displacement, read_values)
    case ('runtime.vectors.deltafi')
      call rs_f64_1(st, cand%vectors%increment_displacement, read_values)

    ! --- increment / activation / amplitudes --------------------------------
    case ('runtime.increment.iblks_at_model')
      call rs_scalar_int(st, cand%increment%current_block)
    case ('runtime.increment.lblks_at_model')
      call rs_scalar_int(st, cand%increment%completed_blocks)
    case ('runtime.activation.appear')
      call rs_i32_1(st, cand%activation%section_state)
    ! may_be_empty: ntcurve counts authored amplitude curves and a model may declare none.
    case ('runtime.amplitudes.dfact')
      st%form = RS_ARRAY
      st%is_f64 = .true.
      st%may_be_empty = .true.
      st%present_ = allocated(cand%amplitudes)
      if (st%present_) then
        n = 0
        do i = 1, size(cand%amplitudes)
          if (opt_is_set(cand%amplitudes(i)%factor)) n = n + 1
        end do
        st%extent = n
        if (read_values) then
          do i = 1, size(cand%amplitudes)
            call opt_get(cand%amplitudes(i)%factor, rv, ok)
            if (ok) then
              if (rv /= rv) st%finite = .false.
            end if
          end do
        end if
      end if

    ! --- cursor -------------------------------------------------------------
    case ('runtime.cursor.lineload')
      call rs_scalar_int(st, cand%cursor%load_line)
    case ('runtime.cursor.linet')
      call rs_scalar_int(st, cand%cursor%temperature_line)
    case ('runtime.cursor.line_load_block')
      call rs_i32_1(st, cand%cursor%load_line_per_block)
    case ('runtime.cursor.line_temp_block')
      call rs_i32_1(st, cand%cursor%temperature_line_per_block)

    case default
      st%known = .false.
    end select
  end subroutine inspect_row

  ! --- storage-fact fillers ---------------------------------------------------
  ! Small and boring on purpose: inspect_row is a table of WHERE each row lives, and
  ! these are the only places that know HOW to measure one. `rs_add_*` accumulate, so a
  ! row that is ragged over elements is measured by the same rule as a flat one.

  pure subroutine rs_i32_1(st, a)
    type(row_storage_t), intent(inout) :: st
    integer(int32), allocatable, intent(in) :: a(:)
    st%form = RS_ARRAY
    st%present_ = allocated(a)
    if (st%present_) st%extent = size(a)
  end subroutine rs_i32_1

  pure subroutine rs_i32_2(st, a)
    type(row_storage_t), intent(inout) :: st
    integer(int32), allocatable, intent(in) :: a(:,:)
    st%form = RS_ARRAY
    st%present_ = allocated(a)
    if (st%present_) st%extent = size(a)
  end subroutine rs_i32_2

  pure subroutine rs_f64_1(st, a, read_values)
    type(row_storage_t), intent(inout) :: st
    real(real64), allocatable, intent(in) :: a(:)
    logical, intent(in) :: read_values
    st%form = RS_ARRAY
    st%is_f64 = .true.
    st%present_ = allocated(a)
    if (.not. st%present_) return
    st%extent = size(a)
    if (read_values) st%finite = st%finite .and. all_finite_1(a)
  end subroutine rs_f64_1

  pure subroutine rs_add_f64_1(st, a, read_values)
    type(row_storage_t), intent(inout) :: st
    real(real64), allocatable, intent(in) :: a(:)
    logical, intent(in) :: read_values
    if (.not. allocated(a)) return
    st%extent = st%extent + size(a)
    if (read_values) st%finite = st%finite .and. all_finite_1(a)
  end subroutine rs_add_f64_1

  pure subroutine rs_add_f64_2(st, a, read_values)
    type(row_storage_t), intent(inout) :: st
    real(real64), allocatable, intent(in) :: a(:,:)
    logical, intent(in) :: read_values
    if (.not. allocated(a)) return
    st%extent = st%extent + size(a)
    if (read_values) st%finite = st%finite .and. all_finite_1(reshape(a, [size(a)]))
  end subroutine rs_add_f64_2

  pure subroutine rs_add_f64_3(st, a, read_values)
    type(row_storage_t), intent(inout) :: st
    real(real64), allocatable, intent(in) :: a(:,:,:)
    logical, intent(in) :: read_values
    if (.not. allocated(a)) return
    st%extent = st%extent + size(a)
    if (read_values) st%finite = st%finite .and. all_finite_1(reshape(a, [size(a)]))
  end subroutine rs_add_f64_3

  pure subroutine rs_ragged(st, lists)
    type(row_storage_t), intent(inout) :: st
    type(index_list_t), allocatable, intent(in) :: lists(:)
    integer :: i
    st%form = RS_ARRAY
    st%present_ = allocated(lists)
    if (.not. st%present_) return
    do i = 1, size(lists)
      if (allocated(lists(i)%values)) st%extent = st%extent + size(lists(i)%values)
    end do
  end subroutine rs_ragged

  pure subroutine rs_scalar_int(st, x)
    type(row_storage_t), intent(inout) :: st
    type(opt_int), intent(in) :: x
    st%form = RS_SCALAR
    st%present_ = opt_is_set(x)
    if (st%present_) st%extent = 1
  end subroutine rs_scalar_int

  ! WHAT THIS CATCHES, AND HOW IT FAILS -- stated exactly, because the answer differs
  ! by build profile and an earlier draft of this comment got it wrong.
  !
  !   release (-O2)     an allocated-but-unwritten array holds whatever was on the heap.
  !                     `a(i) /= a(i)` is true only if that happens to be a NaN, so here
  !                     the net is a WEAK check: it catches the common case and misses
  !                     garbage that looks like a number.
  !   strict            -init=snan,arrays fills it with a SIGNALLING NaN, and under
  !                     -fpe0 a signalling NaN as an operand of any comparison raises
  !                     invalid-operation. So this loop does not return .false. there --
  !                     the process TRAPS at the first unwritten element. That is still a
  !                     loud, located failure and not a silent pass, but it is an abort
  !                     rather than a finding, and a caller must not expect to see
  !                     NET-SNAN in `errors` under that profile.
  !
  ! Neither mode is silent, which is what the net is for. Nothing here makes an
  ! unwritten DEFINED row survive to the baseline comparison unnoticed.
  pure logical function all_finite_1(a) result(ok)
    real(real64), intent(in) :: a(:)
    integer :: i
    ok = .true.
    do i = 1, size(a)
      if (a(i) /= a(i)) then
        ok = .false.
        return
      end if
    end do
  end function all_finite_1

  ! ==========================================================================
  ! publication helpers
  ! ==========================================================================
  !
  ! Every map row leaves this module through one of these. Each looks its row up in
  ! yl_runtime_rules by map id and takes the object path, the field, the manifest kind,
  ! the manifest rule and the input list FROM THE TABLE, so a manifest entry cannot
  ! disagree with the rule that claims to have produced it and the two can never drift.
  ! The ledger entry and the manifest entry are written together, which is what makes
  ! NET-MAP-BIJECTION a real check rather than a restatement.

  subroutine publish_i32(cand, record, map_id, value, state, errors)
    type(runtime_state_t), intent(inout) :: cand
    type(manifest_t), intent(inout) :: record
    character(len=*), intent(in) :: map_id
    integer(int32), intent(in) :: value
    integer(int32), intent(in) :: state
    type(problem_errors_t), intent(inout) :: errors
    call publish_value(cand, record, map_id, mv_i32(value), state, errors)
  end subroutine publish_i32

  subroutine publish_i32_list(cand, record, map_id, values, state, errors)
    type(runtime_state_t), intent(inout) :: cand
    type(manifest_t), intent(inout) :: record
    character(len=*), intent(in) :: map_id
    integer(int32), intent(in) :: values(:)
    integer(int32), intent(in) :: state
    type(problem_errors_t), intent(inout) :: errors
    call publish_value(cand, record, map_id, mv_i32_list(values), state, errors)
  end subroutine publish_i32_list

  subroutine publish_f64_list(cand, record, map_id, values, state, errors)
    type(runtime_state_t), intent(inout) :: cand
    type(manifest_t), intent(inout) :: record
    character(len=*), intent(in) :: map_id
    real(real64), intent(in) :: values(:)
    integer(int32), intent(in) :: state
    type(problem_errors_t), intent(inout) :: errors
    call publish_value(cand, record, map_id, mv_f64_list(values), state, errors)
  end subroutine publish_f64_list

  subroutine publish_ragged(cand, record, map_id, lists, state, errors)
    type(runtime_state_t), intent(inout) :: cand
    type(manifest_t), intent(inout) :: record
    character(len=*), intent(in) :: map_id
    type(index_list_t), intent(in) :: lists(:)
    integer(int32), intent(in) :: state
    type(problem_errors_t), intent(inout) :: errors
    integer(int32), allocatable :: flat(:)
    integer :: i, j, n
    n = 0
    do i = 1, size(lists)
      if (allocated(lists(i)%values)) n = n + size(lists(i)%values)
    end do
    allocate (flat(n))
    n = 0
    do i = 1, size(lists)
      if (.not. allocated(lists(i)%values)) cycle
      do j = 1, size(lists(i)%values)
        n = n + 1
        flat(n) = lists(i)%values(j)
      end do
    end do
    call publish_value(cand, record, map_id, mv_i32_list(flat), state, errors)
  end subroutine publish_ragged

  ! A row that is allocated for a later phase. Its VALUE is not recorded, because there
  ! is no value: recording the uninitialised bytes would be a claim, and reading them is
  ! what the RESERVED state exists to forbid.
  subroutine publish_reserved(cand, record, map_id, errors)
    type(runtime_state_t), intent(inout) :: cand
    type(manifest_t), intent(inout) :: record
    character(len=*), intent(in) :: map_id
    type(problem_errors_t), intent(inout) :: errors
    call publish_value(cand, record, map_id, mv_none(), RUNTIME_VALUE_RESERVED, errors)
  end subroutine publish_reserved

  ! A row that must stay unallocated on this path. The absence is the asserted property,
  ! so it is recorded as one rather than left as a silence the ledger cannot distinguish
  ! from a build that never reached the row.
  subroutine publish_absent(cand, record, map_id, errors)
    type(runtime_state_t), intent(inout) :: cand
    type(manifest_t), intent(inout) :: record
    character(len=*), intent(in) :: map_id
    type(problem_errors_t), intent(inout) :: errors
    call publish_value(cand, record, map_id, mv_none(), RUNTIME_VALUE_ABSENT, errors)
  end subroutine publish_absent

  ! The one `check` row (RuntimeState.cursor.lineload). Both sides are the no-value
  ! encoding, so the verdict is `match` and says exactly what was established: nothing
  ! was claimed and nothing disagreed. See build_cursor for why.
  subroutine publish_check_vacuous(cand, record, map_id, errors)
    type(runtime_state_t), intent(inout) :: cand
    type(manifest_t), intent(inout) :: record
    character(len=*), intent(in) :: map_id
    type(problem_errors_t), intent(inout) :: errors
    call publish_value(cand, record, map_id, mv_none(), RUNTIME_VALUE_RESERVED, errors)
  end subroutine publish_check_vacuous

  ! The single place a map row becomes a ledger entry and a manifest entry.
  subroutine publish_value(cand, record, map_id, value, state, errors)
    type(runtime_state_t), intent(inout) :: cand
    type(manifest_t), intent(inout) :: record
    character(len=*), intent(in) :: map_id
    type(manifest_value_t), intent(in) :: value
    integer(int32), intent(in) :: state
    type(problem_errors_t), intent(inout) :: errors

    type(build_rule_t) :: row
    type(manifest_text_t), allocatable :: inputs(:)
    integer :: i, n, k, stat
    logical :: found, ok

    i = build_rule_producer_of(map_id)
    if (i == 0) then
            call raise_row(errors, 'NET-MAP-BIJECTION', 'manifest-derive-rows-match-map',              &
                      'the build produced map row '//map_id//                                ' which no rule-table row claims')
      return
    end if
    call build_rule_row(i, row, found)
    if (.not. found) then
            call raise_row(errors, 'NET-MAP-BIJECTION', 'manifest-derive-rows-match-map',              &
                      'the rule table lost the row that produces '//map_id)
      return
    end if

    n = build_rule_input_count_for(i)
    allocate (inputs(n))
    do k = 1, n
      inputs(k)%s = build_rule_input_at(i, k)
    end do

    if (trim(row%manifest_kind) == MANIFEST_KIND_CHECK) then
      call manifest_add_check(record, trim(row%object_path), trim(row%field), value, value,     &
                              inputs, trim(row%map_id), stat)
    else
      call manifest_add_derived(record, trim(row%manifest_rule), trim(row%object_path),         &
                                trim(row%field), value, inputs, trim(row%map_id), stat)
    end if
    if (stat /= 0) then
            call raise_row(errors, 'NET-MAP-BIJECTION', 'manifest-derive-rows-match-map',              &
                      'the manifest refused the entry for '//map_id//': '//                  manifest_error(record))
      return
    end if

    call runtime_status_set(cand, map_id, state, ok)
    if (.not. ok) then
            call raise_row(errors, 'NET-MAP-BIJECTION', 'manifest-derive-rows-match-map',              &
                      'the value-state ledger refused the entry for '//map_id)
      return
    end if
  end subroutine publish_value

  ! ==========================================================================
  ! small helpers
  ! ==========================================================================

  ! Storage index of an authored node id, 0 when the id is not a node of this mesh.
  pure integer function node_index(shape, node_id) result(i)
    type(build_shape_t), intent(in) :: shape
    integer(int32), intent(in) :: node_id
    i = 0
    if (node_id < 1_int32) return
    if (int(node_id) > size(shape%node_of_id)) return
    i = int(shape%node_of_id(int(node_id)))
  end function node_index

  ! True when `list(k)` already appeared earlier in the list. This is the legacy
  ! duplicate skip of Prescrib.f90:347-350, kept because a node can appear twice in the
  ! same element's connectivity in a degenerate mesh and legacy counts it once.
  pure logical function seen_before(list, k, value) result(seen)
    integer(int32), intent(in) :: list(:)
    integer, intent(in) :: k
    integer(int32), intent(in) :: value
    integer :: j
    seen = .false.
    do j = 1, k - 1
      if (list(j) == value) then
        seen = .true.
        return
      end if
    end do
  end function seen_before

  ! The non-zero entries of `table` are exactly 1 .. n, each exactly once.
  pure logical function is_dense_permutation(table, n) result(dense)
    integer(int32), intent(in) :: table(:,:)
    integer, intent(in) :: n
    logical, allocatable :: hit(:)
    integer :: i, j, v
    dense = .false.
    allocate (hit(n))
    hit = .false.
    do j = 1, size(table, 2)
      do i = 1, size(table, 1)
        v = int(table(i, j))
        if (v == 0) cycle
        if (v < 1 .or. v > n) return
        if (hit(v)) return
        hit(v) = .true.
      end do
    end do
    dense = all(hit)
  end function is_dense_permutation

  pure integer(int32) function int_or_zero(x) result(v)
    type(opt_int), intent(in) :: x
    logical :: found
    call opt_get(x, v, found)
    if (.not. found) v = 0_int32
  end function int_or_zero

  pure integer function size_or_zero_1d(x) result(n)
    real(real64), allocatable, intent(in) :: x(:)
    n = 0
    if (allocated(x)) n = size(x)
  end function size_or_zero_1d

  pure integer function size_or_zero_i32_1d(x) result(n)
    integer(int32), allocatable, intent(in) :: x(:)
    n = 0
    if (allocated(x)) n = size(x)
  end function size_or_zero_i32_1d

  pure integer function size_or_zero_2d(x) result(n)
    integer(int32), allocatable, intent(in) :: x(:,:)
    n = 0
    if (allocated(x)) n = size(x)
  end function size_or_zero_2d

  pure integer function size_or_zero_gauss(cand) result(n)
    type(runtime_state_t), intent(in) :: cand
    n = 0
    if (.not. allocated(cand%gauss)) return
    if (size(cand%gauss) < 1) return
    if (.not. allocated(cand%gauss(1)%stiffness%weighted_jacobian)) return
    n = size(cand%gauss(1)%stiffness%weighted_jacobian)
  end function size_or_zero_gauss

  ! True when the test hook asked this site to fail.
  pure logical function injected(fail_at, site) result(yes)
    integer, intent(in), optional :: fail_at
    integer, intent(in) :: site
    yes = .false.
    if (.not. present(fail_at)) return
    yes = (fail_at == site)
  end function injected

  ! An INJECTED allocation failure (the T01 hook). It deliberately does NOT borrow a
  ! rule row's identity: a synthetic fault that reported itself as INV-COMMIT-TOTAL
  ! would mark that row as exercised, and the coverage walk would then vouch for a rule
  ! no real counter-example ever fired. The `INJECTED/` prefix is not in the rule table
  ! and is not meant to be.
  subroutine raise_injected(errors, site)
    type(problem_errors_t), intent(inout) :: errors
    integer, intent(in) :: site
    type(problem_error_t) :: finding
    finding = make_problem_error(PE_INTERNAL, PE_STAGE_BUILD, 'INJECTED/build-site',            &
                                 'runtime', int(site, int32), '*',                              &
                                 'injected allocation failure at build site "'//                &
                                 build_alloc_site_id(site)//'"',                                &
                                 exit_class=PE_EXIT_INTERNAL)
    call errors%add(finding)
  end subroutine raise_injected

  ! The ONE way this module reports a rule of yl_runtime_rules firing.
  !
  ! Everything that IDENTIFIES the row -- the composed key `<rule_id>/<condition>`, the
  ! object path, the field and the failure code -- is read out of the rule table. A call
  ! site supplies only what it alone knows: what went wrong, and where. It cannot spell
  ! the quad, so it cannot spell it differently from the table.
  !
  ! WHY THIS IS NOT TIDINESS.
  !   M3-02's postmortem was that a finding bound to a rule FAMILY rather than to a
  !   (rule, condition) ROW let one counter-example vouch for eleven conditions. The
  !   first M3-03 draft of this module reintroduced the identical class from the other
  !   side: every raise site spelled the bare family id ('B1'), while
  !   build_rule_exercised matches on the composed key ('B1/node-not-attached'). Every
  !   counter-example fired correctly and the coverage walk still reported 0 of 5 rows
  !   covered -- a guard that could not see its own evidence, which reads as a hole in
  !   the tests rather than as the binding defect it was. Two raise sites had also
  !   overwritten object_path/field with the location of the defect, so those findings
  !   no longer carried the identity of the row that produced them.
  !
  !   Reading the quad from the table makes both unrepresentable. The location survives
  !   in `message`, `actual` and `index`, which is where a location belongs.
  subroutine raise_row(errors, rule_id, condition, message, actual, expected, idx)
    type(problem_errors_t), intent(inout) :: errors
    character(len=*), intent(in) :: rule_id, condition, message
    character(len=*), intent(in), optional :: actual, expected
    integer, intent(in), optional :: idx

    type(problem_error_t) :: finding
    type(build_rule_t) :: row
    integer :: i
    logical :: found

    i = row_of(rule_id, condition)
    if (i == 0) then
      ! A raise site naming a row the table does not have. Reported rather than
      ! silently downgraded, because the alternative is a finding whose rule id no
      ! coverage walk will ever match -- exactly the failure this helper exists to
      ! prevent, reappearing as a typo.
      finding = make_problem_error(PE_INTERNAL, PE_STAGE_BUILD,                                 &
                                   trim(rule_id)//'/'//trim(condition), 'runtime', field='*',   &
                                   message='the build raised a rule the table does not '//      &
                                   'declare: '//trim(rule_id)//'/'//trim(condition),            &
                                   exit_class=PE_EXIT_INTERNAL)
      call errors%add(finding)
      return
    end if
    call build_rule_row(i, row, found)

    ! The code comes from the row too. A BR_CHECK row carries the PE_* it raises; the
    ! invariant and net rows all carry PE_INTERNAL, and exit_class_for_code maps that to
    ! the internal exit class on its own, so this routine never names an exit class.
    if (present(idx)) then
      finding = make_problem_error(trim(row%code), PE_STAGE_BUILD, build_rule_key(i),           &
                                   trim(row%object_path), int(idx, int32), trim(row%field),     &
                                   message, actual, expected)
    else
      finding = make_problem_error(trim(row%code), PE_STAGE_BUILD, build_rule_key(i),           &
                                   trim(row%object_path), field=trim(row%field),                &
                                   message=message, actual=actual, expected=expected)
    end if
    call errors%add(finding)
  end subroutine raise_row

  ! Index of the row with this (rule_id, condition), 0 when the table has none.
  pure integer function row_of(rule_id, condition) result(i)
    character(len=*), intent(in) :: rule_id, condition
    type(build_rule_t) :: row
    logical :: found
    integer :: k
    i = 0
    do k = 1, build_rule_count()
      call build_rule_row(k, row, found)
      if (.not. found) cycle
      if (trim(row%rule_id) /= trim(rule_id)) cycle
      if (trim(row%condition) /= trim(condition)) cycle
      i = k
      return
    end do
  end function row_of

  ! The contract-tag precondition (B0). It is deliberately NOT a rule-table row and not
  ! raised through raise_row: it fires before any row of the table is reachable, exactly
  ! as the pipeline's profile check (P0) sits outside the capability table. Keeping it
  ! out means the coverage walk is never asked to account for a row that guards the
  ! table's own applicability.
  subroutine raise_precondition(errors, code, rule, object, field, message, actual, expected)
    type(problem_errors_t), intent(inout) :: errors
    character(len=*), intent(in) :: code, rule, object, field, message
    character(len=*), intent(in), optional :: actual, expected
    type(problem_error_t) :: finding
    finding = make_problem_error(code, PE_STAGE_BUILD, rule, object, field=field,               &
                                 message=message, actual=actual, expected=expected)
    call errors%add(finding)
  end subroutine raise_precondition

  pure function itoa(v) result(s)
    integer, intent(in) :: v
    character(len=:), allocatable :: s
    character(len=24) :: buf
    write (buf, '(i0)') v
    s = trim(buf)
  end function itoa

  ! A real rendered for a MESSAGE, never for a comparison: the exact-value encoding is
  ! mv_f64's hex, and this is only ever read by a person.
  pure function ftoa(v) result(s)
    real(real64), intent(in) :: v
    character(len=:), allocatable :: s
    character(len=32) :: buf
    write (buf, '(es16.8e2)') v
    s = trim(adjustl(buf))
  end function ftoa

end module yl_runtime_build
