! yl_runtime_rules -- the walkable table of build_runtime's rules and derived quantities.
!
! Scope (see .ccg/tasks/m3-03-build-runtime-commit/plan.md delivery 3 and its
! "contract and criteria" section, analysis.md "rule set" ruling, analysis-claude.md S1, S2, S6)
!   Two read-only tables and their accessors. No I/O, no parsing, no state, no
!   dependence on runtime_state_t -- this module is pure declaration, so it can be
!   compiled and walked before build_runtime exists.
!     * BUILD_RULES        -- one row per rule condition, per derived quantity, per
!                             internal invariant and per excluded net.
!     * BUILD_RULE_INPUTS  -- a flat edge table, (rule_id, input_map_id), naming the
!                             map rows each derived quantity reads.
!
! WHY THIS MODULE EXISTS AT ALL
!   M3-02 shipped two kinds of gate. Capability rows were DATA, so a self-test could
!   walk them and fail naming any row no counter-example ever triggered. Validate
!   rules were only raise sites in executable code, so nothing could enumerate them;
!   an audit then found V1 carrying eleven conditions behind a single counter-example.
!   One decayed and the other did not, and the difference was declaration. Every build
!   rule and every derived quantity is therefore declared here, as data.
!
! WHY THE BINDING UNIT IS A QUAD AND NOT THE CAPABILITY TRIPLE
!   The capability table binds a finding to a row by (rule_id, object_path, field).
!   That triple is exactly what let V1 hide eleven conditions: a condition was not
!   part of the key, so the second and later conditions of a rule inherited the first
!   one's apparent coverage. The binding unit here is
!
!       (rule_id, condition, object_path, field)
!
!   and build_rule_key() renders the (rule_id, condition) half of it as the single
!   stable string a raise site passes as `rule_id` and a failure message prints. The
!   condition is therefore never spelled twice: it is a column, and the key is
!   computed from that column rather than stored beside it.
!
! WHY TWO TABLES
!   A derived quantity has inputs; a capability item did not. A `parameter` array
!   cannot hold an allocatable component, and a joined "a,b,c" string would need a
!   parser inside a layer with no parser. The inputs are therefore edges in a second
!   flat `parameter` table keyed by rule_id. manifest_add_derived already carries
!   `inputs` and `map_id`, so the suite compares declared edges against the manifest
!   with no new plumbing.
!
! WHY THE COUNT OF DERIVED QUANTITIES IS NOT WRITTEN DOWN HERE
!   It is not written down anywhere except the M2 map. build_rule_produced_count()
!   and build_rule_produced_map_id() expose what this table claims to produce; the
!   suite asserts a BIJECTION between that set and the map's model_ready
!   `RuntimeState.*` rows. A row added on one side and not the other fails. M3-02
!   recorded the cost of the alternative: a hard-coded 15 in a document that could
!   not be reproduced.
!
! CLASSIFICATION VOCABULARY, CARRIED FROM M3-02
!   BR_CHECK      a rule. Falsifiable: it MUST have a counter-example, and the suite
!                 fails naming any check row no counter-example ever triggered.
!   BR_DERIVE     a produced quantity. Falsifiable per row: the absence of its
!                 manifest entry, or a wrong manifest rule or input set, fails.
!   BR_INVARIANT  an `INV-` internal invariant. A firing means a MISSING UPSTREAM
!                 RULE, so it exits internal (class 6), not as an input defect.
!                 Excluded from rule coverage because nothing can make it fire --
!                 and `reach` records WHY, which is the load-bearing part:
!                   BR_UNREACHABLE_BY_CONSTRUCTION  no expiry, it is a theorem.
!                   BR_UNREACHABLE_BY_CAPABILITY    unreachable only because the
!                     capability gate is narrow today. `expires_when` carries a
!                     REVIEW DATE and the capability change that turns the row back
!                     into a rule needing a counter-example, in the form
!                     `review <yyyy-mm-dd>: <what changes>`. The date is the load-
!                     bearing half: a condition alone ("when fields widen") never
!                     comes due, so nobody ever looks again and a temporary gap
!                     becomes a permanent one silently. On the date, either the
!                     capability has widened and the row owes a counter-example, or
!                     it has not and the date moves with a reason.
!   BR_NET        a catch-all net, excluded from rule counts and counted separately,
!                 kept for the M3-02 S9 reason: a net catches a cause nobody thought
!                 of, and by definition such a cause has no counter-example.
!
! DELIBERATELY ABSENT -- READ BEFORE ADDING A ROW HERE
!   Three candidates were rejected by the team lead, each because it cannot fail:
!     * the zero-Jacobian condition (a degenerate Q4). Distinct from B3 and it
!       deserves its own row, but no counter-example is confirmed: whether collapsing
!       node 4 onto node 3 makes det J vanish AT A 2x2 GAUSS POINT is arithmetic
!       nobody has done. Write the row only after that number exists.
!     * `ntotv >= 1`. Every counter-example is blocked upstream by the capability
!       gate, which pins element.fields = U, formulation = PE and one section. That
!       is the capability-ceiling class, so it is below as INV-NTOTV-POSITIVE with an
!       expiry, not as a rule.
!     * a build-stage amplitude-reference check. Validate rule V18 already raises
!       DANGLING_REF on it, so a copy here would be a rule nothing can fail -- the
!       exact defect this milestone exists to remove.
module yl_runtime_rules

  use iso_fortran_env, only: int32
  use yl_problem_optional, only: opt_value_or
  use yl_runtime_types, only: RUNTIME_VALUE_UNSET, RUNTIME_VALUE_DEFINED,                        &
                              RUNTIME_VALUE_RESERVED, RUNTIME_VALUE_ABSENT
  use yl_problem_errors, only: problem_errors_t, problem_error_t
  use yl_runtime_types, only: RUNTIME_VALUE_UNSET, RUNTIME_VALUE_DEFINED,                        &
                              RUNTIME_VALUE_RESERVED, RUNTIME_VALUE_ABSENT
  use yl_problem_errors, only: PE_DANGLING_REF, PE_DUPLICATE_REF, PE_COUNT_MISMATCH,                                              &
                               PE_INVALID_INPUT, PE_INTERNAL
  ! The manifest vocabulary is IMPORTED, not re-spelled. A derive row declares the
  ! manifest kind and rule its entry must carry, and the suite compares the two; if
  ! the two spellings were independent string literals the comparison would be
  ! comparing this file against itself and would pass while both were wrong.
  use yl_problem_manifest, only: MANIFEST_KIND_DERIVED, MANIFEST_KIND_CHECK
  use yl_problem_manifest, only: MANIFEST_RULE_INDEX_MAP, MANIFEST_RULE_COUNT,                                                    &
                                 MANIFEST_RULE_LEGACY_DEFAULT, MANIFEST_RULE_DOF_EXPAND,                                          &
                                 MANIFEST_RULE_RENUMBER, MANIFEST_RULE_DECLARED_COUNT,                                           &
                                 MANIFEST_RULE_GEOMETRY

  implicit none
  private

  public :: build_rule_t, build_rule_input_t
  public :: build_rule_count, build_rule_row, build_rule_id, build_rule_key
  public :: build_rule_expected_state
  public :: build_rule_is_falsifiable, build_rule_falsifiable_count
  public :: build_rule_exercised, build_rule_first_uncovered
  public :: build_rule_input_count, build_rule_input_row
  public :: build_rule_input_count_for, build_rule_input_at
  public :: build_rule_produced_count, build_rule_produced_map_id, build_rule_producer_of
  public :: build_rule_row_text

  ! Fixed lengths, so that both tables can be PARAMETER arrays: a derived type with a
  ! deferred-length or allocatable component cannot be a named constant, and a named
  ! constant is what makes these tables provably read-only. Same trade the capability
  ! table makes in yl_problem_profile.
  integer, parameter :: LEN_RULE = 32
  integer, parameter :: LEN_COND = 30
  integer, parameter :: LEN_PATH = 32
  integer, parameter :: LEN_FIELD = 20
  integer, parameter :: LEN_CODE = 16
  integer, parameter :: LEN_MAP_ID = 40
  integer, parameter :: LEN_MKIND = 8
  integer, parameter :: LEN_MRULE = 16
  integer, parameter :: LEN_EXPIRY = 32

  ! --- table identity ---------------------------------------------------------
  ! Versioned like the capability table, so an exported row line carries the version
  ! of the table that produced it and a cross-check cannot silently compare two
  ! generations of the table against each other.

  character(len=*), parameter, public :: BUILD_RULES_ID = 'build-runtime'
  character(len=*), parameter, public :: BUILD_RULES_VERSION = '1'
  character(len=*), parameter, public :: BUILD_RULES_TAG = BUILD_RULES_ID//'/'//BUILD_RULES_VERSION

  ! --- the stage these rules belong to ----------------------------------------
  ! The four existing stages live in yl_problem_errors. `build` is the fifth, and it
  ! is declared here rather than spelled at each raise site for the reason the other
  ! four are declared there: a typo must not be able to invent a sixth stage.

  character(len=*), parameter, public :: PE_STAGE_BUILD = 'build'

  ! --- row kind ---------------------------------------------------------------

  integer(int32), parameter, public :: BR_CHECK = 1_int32
  integer(int32), parameter, public :: BR_DERIVE = 2_int32
  integer(int32), parameter, public :: BR_INVARIANT = 3_int32
  integer(int32), parameter, public :: BR_NET = 4_int32

  ! --- reachability -----------------------------------------------------------
  ! Only meaningful on BR_INVARIANT rows. A discriminator and not a sentinel: the
  ! suite asserts BR_UNREACHABLE_BY_CAPABILITY holds exactly when `expires_when` is
  ! non-empty, so an empty expiry can never be read as "by construction" by accident.

  integer(int32), parameter, public :: BR_REACHABLE = 0_int32
  integer(int32), parameter, public :: BR_UNREACHABLE_BY_CONSTRUCTION = 1_int32
  integer(int32), parameter, public :: BR_UNREACHABLE_BY_CAPABILITY = 2_int32

  ! --- one row ----------------------------------------------------------------
  ! `object_path` and `field` say which object the row reports on, in the same
  ! index-free spelling the capability table uses: a table path `steps[].boundary[]`
  ! matches a finding's `steps[1].boundary[2]` after both sides drop their `[...]`
  ! groups, so this table never has to know which record failed.
  !
  ! `code` is the failure code a BR_CHECK row raises, and PE_INTERNAL on the
  ! invariant and net rows because a firing there is a broken pipeline, not a bad
  ! deck. It is empty on BR_DERIVE rows: a missing derived quantity is not reported
  ! by that row, it is reported by the coverage walk and by NET-MAP-BIJECTION.
  !
  ! `map_id`, `manifest_kind` and `manifest_rule` are set on BR_DERIVE rows only.
  ! manifest_kind is `derived` for every produced quantity except
  ! RuntimeState.cursor.lineload, whose map source is two READER ids and not a
  ! `derived:` rule -- it is copied through, so its manifest entry must be a `check`
  ! against the reader value. Recording that here is what stops it being logged as a
  ! derivation it is not.

  type :: build_rule_t
    character(len=LEN_RULE) :: rule_id = ''        ! B3, D-DOF-NODFN, INV-NEVAB, NET-SNAN
    integer(int32) :: kind = BR_CHECK
    character(len=LEN_COND) :: condition = ''      ! the ONE predicate this row owns
    character(len=LEN_PATH) :: object_path = ''    ! index-free path the row reports on
    character(len=LEN_FIELD) :: field = ''         ! component, or `*` for a whole-state net
    character(len=LEN_CODE) :: code = ''           ! PE_* raised; '' on BR_DERIVE
    character(len=LEN_MAP_ID) :: map_id = ''       ! M2 map row produced; BR_DERIVE only
    character(len=LEN_MKIND) :: manifest_kind = '' ! derived | check; BR_DERIVE only
    character(len=LEN_MRULE) :: manifest_rule = '' ! index_map | count | ...; BR_DERIVE only
    integer(int32) :: reach = BR_REACHABLE         ! BR_INVARIANT only
    character(len=LEN_EXPIRY) :: expires_when = '' ! non-empty iff reach is BY_CAPABILITY
  end type build_rule_t

  ! --- one input edge ---------------------------------------------------------
  ! `rule_id` is a foreign key into BUILD_RULES; `input_map_id` is an M2 map row id,
  ! never an object path. The map id is the stable name -- a ProblemState path can be
  ! respelled without the map noticing, a map id cannot. build_runtime must pass
  ! exactly these strings as the `inputs` argument of manifest_add_derived, which is
  ! what makes the suite's comparison plain string equality.

  type :: build_rule_input_t
    character(len=LEN_RULE) :: rule_id = ''
    character(len=LEN_MAP_ID) :: input_map_id = ''
  end type build_rule_input_t

  ! --- the table --------------------------------------------------------------
  !
  ! Group 1, BR_CHECK: the five rules the plan approved. Each has ONE condition and a
  ! confirmed counter-example, a single mutation of the good draft:
  !   B1  a node carrying a constraint that no element uses, so it has no active dof.
  !       Add node 5 at (2,0), put it alone in an nset, point boundary(1) at it.
  !   B2  a boundary dof beyond the formulation's dof count. Set boundary(1)%dof = 3
  !       against the two dofs of PE.
  !   B3  clockwise connectivity, det J < 0 at all four Gauss points. Connectivity
  !       1,4,3,2 instead of 1,2,3,4.
  !   B6  the same (node, dof) prescribed twice in one step. Duplicate boundary(1) as
  !       a third record.
  !   B8  a declared ndofix disagreeing with the derived one. Declare 4 against 6.
  !
  ! Group 2, BR_DERIVE: every model_ready `RuntimeState.*` row of the M2 map, in map
  ! order. Their `condition` names the VALUE STATE the build must leave the row in, and
  ! the three spellings map one-to-one onto the three states of yl_runtime_types:
  !   built        -> RUNTIME_VALUE_DEFINED    computed, readable, comparable.
  !   reserved     -> RUNTIME_VALUE_RESERVED   storage exists with a defined shape, its
  !                                            contents are UNDEFINED at this checkpoint
  !                                            and must never be read. For a scalar row
  !                                            it means no value is claimed at all.
  !   unallocated  -> RUNTIME_VALUE_ABSENT     must stay unallocated on this path. A row
  !                                            whose correct product is "nothing" still
  !                                            needs declaring, or nothing notices when
  !                                            it starts being filled.
  !
  ! WHY EXACTLY THREE, AND WHY THEY ARE CHECKED.
  !   This column was prose until the M3-03 Round-1 review, and prose drifts: six rows
  !   were found carrying `built` (or the retired spellings `allocated-uninitialised`
  !   and `copied`) while the build published them RESERVED or ABSENT, and neither
  !   self-test nor the Python cross-check read the column at all. Collapsing the
  !   vocabulary to the ledger's own three states makes the claim expressible, and
  !   `build_rule_expected_state` below makes it CHECKABLE -- run_nets asserts, for
  !   every produced row, that the ledger state equals the state this column declares.
  !   The retired `copied` said the value was carried through from a reader; on this
  !   path nothing is, so it was an overclaim as well as a fourth spelling. That fact
  !   now lives where it belongs, in the row's `manifest_kind` = check.
  !
  ! Group 3, BR_INVARIANT and group 4, BR_NET: see the header.
  type(build_rule_t), parameter :: BUILD_RULES(*) = [                                                                             &
    build_rule_t('B1', BR_CHECK, 'node-not-attached',                                                                             &
                 'steps[].boundary[]', 'nset', PE_DANGLING_REF,                                                                   &
                 '', '', '', BR_REACHABLE, ''),                                                                                   &
    build_rule_t('B2', BR_CHECK, 'dof-out-of-range',                                                                              &
                 'steps[].boundary[]', 'dof', PE_INVALID_INPUT,                                                                   &
                 '', '', '', BR_REACHABLE, ''),                                                                                   &
    build_rule_t('B3', BR_CHECK, 'negative-jacobian',                                                                             &
                 'mesh.elements[]', 'nodes', PE_INVALID_INPUT,                                                                    &
                 '', '', '', BR_REACHABLE, ''),                                                                                   &
    build_rule_t('B6', BR_CHECK, 'duplicate-prescribed-pair',                                                                     &
                 'steps[].boundary[]', 'dof', PE_DUPLICATE_REF,                                                                   &
                 '', '', '', BR_REACHABLE, ''),                                                                                   &
    build_rule_t('B8', BR_CHECK, 'declared-count-mismatch',                                                                       &
                 'declared_counts', 'ndofix', PE_COUNT_MISMATCH,                                                                  &
                 '', '', '', BR_REACHABLE, ''),                                                                                   &
    build_rule_t('D-AMPLITUDES-DFACT', BR_DERIVE, 'built',                                                                        &
                 'runtime.amplitudes[]', 'factor', '',                                                                            &
                 'runtime.amplitudes.dfact', MANIFEST_KIND_DERIVED, MANIFEST_RULE_LEGACY_DEFAULT, BR_REACHABLE, ''),              &
    build_rule_t('D-DOF-LMDOFN', BR_DERIVE, 'built',                                                                              &
                 'runtime.dof', 'lmdofn', '',                                                                                     &
                 'runtime.dof.lmdofn', MANIFEST_KIND_DERIVED, MANIFEST_RULE_RENUMBER, BR_REACHABLE, ''),                          &
    build_rule_t('D-INCREMENT-IBLKS-AT-MODEL', BR_DERIVE, 'built',                                                                &
                 'runtime.increment', 'iblks', '',                                                                                &
                 'runtime.increment.iblks_at_model', MANIFEST_KIND_DERIVED, MANIFEST_RULE_COUNT, BR_REACHABLE, ''),               &
    build_rule_t('D-INCREMENT-LBLKS-AT-MODEL', BR_DERIVE, 'built',                                                                &
                 'runtime.increment', 'lblks', '',                                                                                &
                 'runtime.increment.lblks_at_model', MANIFEST_KIND_DERIVED, MANIFEST_RULE_COUNT, BR_REACHABLE, ''),               &
    build_rule_t('D-ACTIVATION-APPEAR', BR_DERIVE, 'built',                                                                       &
                 'runtime.activation', 'appear', '',                                                                              &
                 'runtime.activation.appear', MANIFEST_KIND_DERIVED, MANIFEST_RULE_INDEX_MAP, BR_REACHABLE, ''),                  &
    build_rule_t('D-BOUNDARY-LDOFIX', BR_DERIVE, 'built',                                                                         &
                 'runtime.boundary', 'dof_index', '',                                                                             &
                 'runtime.boundary.ldofix', MANIFEST_KIND_DERIVED, MANIFEST_RULE_DOF_EXPAND, BR_REACHABLE, ''),                   &
    build_rule_t('D-BOUNDARY-LNEFIX', BR_DERIVE, 'built',                                                                         &
                 'runtime.boundary', 'element_count', '',                                                                         &
                 'runtime.boundary.lnefix', MANIFEST_KIND_DERIVED, MANIFEST_RULE_DOF_EXPAND, BR_REACHABLE, ''),                   &
    build_rule_t('D-BOUNDARY-LELDOFIX', BR_DERIVE, 'built',                                                                       &
                 'runtime.boundary', 'leldofix', '',                                                                              &
                 'runtime.boundary.leldofix', MANIFEST_KIND_DERIVED, MANIFEST_RULE_DOF_EXPAND, BR_REACHABLE, ''),                 &
    build_rule_t('D-BOUNDARY-LEVDOFIX', BR_DERIVE, 'built',                                                                       &
                 'runtime.boundary', 'levdofix', '',                                                                              &
                 'runtime.boundary.levdofix', MANIFEST_KIND_DERIVED, MANIFEST_RULE_DOF_EXPAND, BR_REACHABLE, ''),                 &
    build_rule_t('D-BOUNDARY-LEFDOFIX', BR_DERIVE, 'built',                                                                       &
                 'runtime.boundary', 'lefdofix', '',                                                                              &
                 'runtime.boundary.lefdofix', MANIFEST_KIND_DERIVED, MANIFEST_RULE_DOF_EXPAND, BR_REACHABLE, ''),                 &
    build_rule_t('D-DOF-IFFIX', BR_DERIVE, 'built',                                                                               &
                 'runtime.dof', 'fixed_mask', '',                                                                                 &
                 'runtime.dof.iffix', MANIFEST_KIND_DERIVED, MANIFEST_RULE_DOF_EXPAND, BR_REACHABLE, ''),                         &
    build_rule_t('D-DOF-FIXED', BR_DERIVE, 'built',                                                                               &
                 'runtime.dof', 'prescribed_value', '',                                                                           &
                 'runtime.dof.fixed', MANIFEST_KIND_DERIVED, MANIFEST_RULE_DOF_EXPAND, BR_REACHABLE, ''),                         &
    build_rule_t('D-DOF-NODFN', BR_DERIVE, 'built',                                                                               &
                 'runtime.dof', 'nodfn', '',                                                                                      &
                 'runtime.dof.nodfn', MANIFEST_KIND_DERIVED, MANIFEST_RULE_RENUMBER, BR_REACHABLE, ''),                           &
    build_rule_t('D-DOF-NTOTV', BR_DERIVE, 'built',                                                                               &
                 'runtime.dof', 'ntotv', '',                                                                                      &
                 'runtime.dof.ntotv', MANIFEST_KIND_DERIVED, MANIFEST_RULE_COUNT, BR_REACHABLE, ''),                              &
    build_rule_t('D-DOF-LDOFS', BR_DERIVE, 'built',                                                                               &
                 'runtime.dof', 'ldofs', '',                                                                                      &
                 'runtime.dof.ldofs', MANIFEST_KIND_DERIVED, MANIFEST_RULE_DOF_EXPAND, BR_REACHABLE, ''),                         &
    build_rule_t('D-DOF-LDOFS-F', BR_DERIVE, 'built',                                                                             &
                 'runtime.dof', 'ldofs_f', '',                                                                                    &
                 'runtime.dof.ldofs_f', MANIFEST_KIND_DERIVED, MANIFEST_RULE_DOF_EXPAND, BR_REACHABLE, ''),                       &
    build_rule_t('D-DOF-TRANS-NINTF', BR_DERIVE, 'built',                                                                         &
                 'runtime.dof', 'interpolation_count', '',                                                                        &
                 'runtime.dof.trans_nintf', MANIFEST_KIND_DERIVED, MANIFEST_RULE_LEGACY_DEFAULT, BR_REACHABLE, ''),               &
    build_rule_t('D-TOPOLOGY-LISTP-GROUP-MGROUP', BR_DERIVE, 'built',                                                             &
                 'runtime.topology.listp_group', 'mgroup', '',                                                                    &
                 'runtime.topology.listp_group_mgroup', MANIFEST_KIND_DERIVED, MANIFEST_RULE_INDEX_MAP, BR_REACHABLE, ''),        &
    build_rule_t('D-TOPOLOGY-LISTP-GROUP-LISTG', BR_DERIVE, 'built',                                                              &
                 'runtime.topology.listp_group', 'listg', '',                                                                     &
                 'runtime.topology.listp_group_listg', MANIFEST_KIND_DERIVED, MANIFEST_RULE_INDEX_MAP, BR_REACHABLE, ''),         &
    build_rule_t('D-TOPOLOGY-LISTP-GROUP-LISTP', BR_DERIVE, 'built',                                                              &
                 'runtime.topology.listp_group', 'listp', '',                                                                     &
                 'runtime.topology.listp_group_listp', MANIFEST_KIND_DERIVED, MANIFEST_RULE_INDEX_MAP, BR_REACHABLE, ''),         &
    build_rule_t('D-TOPOLOGY-UNODE-IPOIN', BR_DERIVE, 'built',                                                                    &
                 'runtime.topology.unode', 'ipoin', '',                                                                           &
                 'runtime.topology.unode_ipoin', MANIFEST_KIND_DERIVED, MANIFEST_RULE_INDEX_MAP, BR_REACHABLE, ''),               &
    build_rule_t('D-TOPOLOGY-UNODE-NE-UNODE', BR_DERIVE, 'built',                                                                 &
                 'runtime.topology.unode', 'ne_unode', '',                                                                        &
                 'runtime.topology.unode_ne_unode', MANIFEST_KIND_DERIVED, MANIFEST_RULE_INDEX_MAP, BR_REACHABLE, ''),            &
    build_rule_t('D-TOPOLOGY-UNODE-LIST', BR_DERIVE, 'built',                                                                     &
                 'runtime.topology.unode', 'list', '',                                                                            &
                 'runtime.topology.unode_list', MANIFEST_KIND_DERIVED, MANIFEST_RULE_INDEX_MAP, BR_REACHABLE, ''),                &
    build_rule_t('D-TOPOLOGY-UNODE-NP-UNODE', BR_DERIVE, 'unallocated',                                                           &
                 'runtime.topology.unode', 'np_unode', '',                                                                        &
                 'runtime.topology.unode_np_unode', MANIFEST_KIND_DERIVED, MANIFEST_RULE_INDEX_MAP, BR_REACHABLE, ''),            &
    build_rule_t('D-TOPOLOGY-UNODE-PATCH-NOD', BR_DERIVE, 'unallocated',                                                          &
                 'runtime.topology.unode', 'patch_nod', '',                                                                       &
                 'runtime.topology.unode_patch_nod', MANIFEST_KIND_DERIVED, MANIFEST_RULE_INDEX_MAP, BR_REACHABLE, ''),           &
    build_rule_t('D-GAUSS-DJACB', BR_DERIVE, 'built',                                                                             &
                 'runtime.gauss', 'djacb', '',                                                                                    &
                 'runtime.gauss.djacb', MANIFEST_KIND_DERIVED, MANIFEST_RULE_GEOMETRY, BR_REACHABLE, ''),                         &
    build_rule_t('D-GAUSS-GPCOD', BR_DERIVE, 'built',                                                                             &
                 'runtime.gauss', 'gpcod', '',                                                                                    &
                 'runtime.gauss.gpcod', MANIFEST_KIND_DERIVED, MANIFEST_RULE_GEOMETRY, BR_REACHABLE, ''),                         &
    build_rule_t('D-GAUSS-CARTD', BR_DERIVE, 'built',                                                                             &
                 'runtime.gauss', 'cartd', '',                                                                                    &
                 'runtime.gauss.cartd', MANIFEST_KIND_DERIVED, MANIFEST_RULE_GEOMETRY, BR_REACHABLE, ''),                         &
    build_rule_t('D-GAUSS-DJACB-MASS', BR_DERIVE, 'built',                                                                        &
                 'runtime.gauss', 'djacb_mass', '',                                                                               &
                 'runtime.gauss.djacb_mass', MANIFEST_KIND_DERIVED, MANIFEST_RULE_GEOMETRY, BR_REACHABLE, ''),                    &
    build_rule_t('D-GAUSS-GPCOD-MASS', BR_DERIVE, 'built',                                                                        &
                 'runtime.gauss', 'gpcod_mass', '',                                                                               &
                 'runtime.gauss.gpcod_mass', MANIFEST_KIND_DERIVED, MANIFEST_RULE_GEOMETRY, BR_REACHABLE, ''),                    &
    build_rule_t('D-ELEMENT-ELCOD-F', BR_DERIVE, 'built',                                                                         &
                 'runtime.element', 'elcod_f', '',                                                                                &
                 'runtime.element.elcod_f', MANIFEST_KIND_DERIVED, MANIFEST_RULE_INDEX_MAP, BR_REACHABLE, ''),                    &
    build_rule_t('D-ELEMENT-TLOAD', BR_DERIVE, 'reserved',                                                         &
                 'runtime.element', 'tload', '',                                                                                  &
                 'runtime.element.tload', MANIFEST_KIND_DERIVED, MANIFEST_RULE_LEGACY_DEFAULT, BR_REACHABLE, ''),                 &
    build_rule_t('D-ELEMENT-ELOAD', BR_DERIVE, 'reserved',                                                         &
                 'runtime.element', 'eload', '',                                                                                  &
                 'runtime.element.eload', MANIFEST_KIND_DERIVED, MANIFEST_RULE_LEGACY_DEFAULT, BR_REACHABLE, ''),                 &
    build_rule_t('D-ELEMENT-RLOAD', BR_DERIVE, 'reserved',                                                         &
                 'runtime.element', 'rload', '',                                                                                  &
                 'runtime.element.rload', MANIFEST_KIND_DERIVED, MANIFEST_RULE_LEGACY_DEFAULT, BR_REACHABLE, ''),                 &
    build_rule_t('D-VECTORS-RESULT-ZERO', BR_DERIVE, 'built',                                                                     &
                 'runtime.vectors', 'result_zero', '',                                                                            &
                 'runtime.vectors.result_zero', MANIFEST_KIND_DERIVED, MANIFEST_RULE_LEGACY_DEFAULT, BR_REACHABLE, ''),           &
    build_rule_t('D-VECTORS-TOFOR', BR_DERIVE, 'built',                                                                           &
                 'runtime.vectors', 'tofor', '',                                                                                  &
                 'runtime.vectors.tofor', MANIFEST_KIND_DERIVED, MANIFEST_RULE_LEGACY_DEFAULT, BR_REACHABLE, ''),                 &
    build_rule_t('D-VECTORS-STFOR', BR_DERIVE, 'built',                                                                           &
                 'runtime.vectors', 'stfor', '',                                                                                  &
                 'runtime.vectors.stfor', MANIFEST_KIND_DERIVED, MANIFEST_RULE_LEGACY_DEFAULT, BR_REACHABLE, ''),                 &
    build_rule_t('D-VECTORS-TOFORL', BR_DERIVE, 'built',                                                                          &
                 'runtime.vectors', 'toforl', '',                                                                                 &
                 'runtime.vectors.toforl', MANIFEST_KIND_DERIVED, MANIFEST_RULE_LEGACY_DEFAULT, BR_REACHABLE, ''),                &
    build_rule_t('D-VECTORS-TOFORM', BR_DERIVE, 'built',                                                                          &
                 'runtime.vectors', 'toform', '',                                                                                 &
                 'runtime.vectors.toform', MANIFEST_KIND_DERIVED, MANIFEST_RULE_LEGACY_DEFAULT, BR_REACHABLE, ''),                &
    build_rule_t('D-VECTORS-DELITFI', BR_DERIVE, 'reserved',                                                                      &
                 'runtime.vectors', 'delitfi', '',                                                                                &
                 'runtime.vectors.delitfi', MANIFEST_KIND_DERIVED, MANIFEST_RULE_LEGACY_DEFAULT, BR_REACHABLE, ''),               &
    build_rule_t('D-VECTORS-DELTAFI', BR_DERIVE, 'reserved',                                                                      &
                 'runtime.vectors', 'deltafi', '',                                                                                &
                 'runtime.vectors.deltafi', MANIFEST_KIND_DERIVED, MANIFEST_RULE_LEGACY_DEFAULT, BR_REACHABLE, ''),               &
    build_rule_t('D-ELEMENT-ICE0', BR_DERIVE, 'built',                                                                            &
                 'runtime.element', 'ice0', '',                                                                                   &
                 'runtime.element.ice0', MANIFEST_KIND_DERIVED, MANIFEST_RULE_LEGACY_DEFAULT, BR_REACHABLE, ''),                  &
    build_rule_t('D-CURSOR-LINELOAD', BR_DERIVE, 'reserved',                                                                      &
                 'runtime.cursor', 'lineload', '',                                                                                &
                 'runtime.cursor.lineload', MANIFEST_KIND_CHECK, MANIFEST_RULE_DECLARED_COUNT, BR_REACHABLE, ''),                 &
    build_rule_t('D-CURSOR-LINE-LOAD-BLOCK', BR_DERIVE, 'reserved',                                                               &
                 'runtime.cursor', 'line_load_block', '',                                                                         &
                 'runtime.cursor.line_load_block', MANIFEST_KIND_DERIVED, MANIFEST_RULE_LEGACY_DEFAULT, BR_REACHABLE, ''),        &
    build_rule_t('D-CURSOR-LINET', BR_DERIVE, 'reserved',                                                                         &
                 'runtime.cursor', 'linet', '',                                                                                   &
                 'runtime.cursor.linet', MANIFEST_KIND_DERIVED, MANIFEST_RULE_LEGACY_DEFAULT, BR_REACHABLE, ''),                  &
    build_rule_t('D-CURSOR-LINE-TEMP-BLOCK', BR_DERIVE, 'reserved',                                                               &
                 'runtime.cursor', 'line_temp_block', '',                                                                         &
                 'runtime.cursor.line_temp_block', MANIFEST_KIND_DERIVED, MANIFEST_RULE_LEGACY_DEFAULT, BR_REACHABLE, ''),        &
    build_rule_t('INV-DOF-DENSE', BR_INVARIANT, 'nodfn-is-dense-permutation',                                                     &
                 'runtime.dof', 'nodfn', PE_INTERNAL,                                                                             &
                 '', '', '', BR_UNREACHABLE_BY_CONSTRUCTION, ''),                                                                 &
    build_rule_t('INV-NEVAB', BR_INVARIANT, 'ldofs-length-is-nnode-x-ndofn',                                                      &
                 'runtime.dof', 'ldofs', PE_INTERNAL,                                                                             &
                 '', '', '', BR_UNREACHABLE_BY_CONSTRUCTION, ''),                                                                 &
    build_rule_t('INV-NTOTV-POSITIVE', BR_INVARIANT, 'ntotv-at-least-one',                                                        &
                 'runtime.dof', 'ntotv', PE_INTERNAL,                                                                             &
                 '', '', '', BR_UNREACHABLE_BY_CAPABILITY, 'review 2026-12-31: fields widen'),                                    &
    build_rule_t('INV-COMMIT-TOTAL', BR_INVARIANT, 'registered-field-allocated',                                                  &
                 'runtime', '*', PE_INTERNAL,                                                                                     &
                 '', '', '', BR_UNREACHABLE_BY_CONSTRUCTION, ''),                                                                 &
    ! The inputs -- the gated problem AND the contract -- do not have the shape this
    ! build requires: no nodes, no elements, no sections, no step to enter, or an
    ! activation policy that enables no component. Distinct from INV-NEVAB, which is
    ! about ONE element disagreeing with the contract rather than the model as a whole.
    ! Both were raised through INV-NEVAB until M3-03 review, which made a finding's rule
    ! id say something its own condition did not.
    build_rule_t('INV-GATED-SHAPE', BR_INVARIANT, 'gated-problem-matches-contract-shape',                                        &
                 'runtime', '*', PE_INTERNAL,                                                                                    &
                 '', '', '', BR_UNREACHABLE_BY_CONSTRUCTION, ''),                                                                &
    ! The two passes of the prescribed-attachment build disagree: pass one sized the
    ! lists (Prescrib.f90:320-340) and pass two filled more entries than it allocated
    ! (:344-368). Its own row because its object is the boundary record and not the dof
    ! table, and a finding must carry the object it is actually about.
    build_rule_t('INV-BOUNDARY-ATTACH', BR_INVARIANT, 'attachment-passes-agree',                                                 &
                 'runtime.boundary', 'leldofix', PE_INTERNAL,                                                                    &
                 '', '', '', BR_UNREACHABLE_BY_CONSTRUCTION, ''),                                                                &
    build_rule_t('NET-EMPTY-RT', BR_NET, 'no-zero-length-published-array',                                                        &
                 'runtime', '*', PE_INTERNAL,                                                                                     &
                 '', '', '', BR_REACHABLE, ''),                                                                                   &
    build_rule_t('NET-MAP-BIJECTION', BR_NET, 'manifest-derive-rows-match-map',                                                   &
                 'runtime', '*', PE_INTERNAL,                                                                                     &
                 '', '', '', BR_REACHABLE, ''),                                                                                   &
    build_rule_t('NET-SNAN', BR_NET, 'f64-field-equals-itself',                                                                   &
                 'runtime', '*', PE_INTERNAL,                                                                                     &
                 '', '', '', BR_REACHABLE, '')]

  ! --- the input edge table ---------------------------------------------------
  ! Flat and keyed by rule_id, grouped by row in table order. Only BR_DERIVE rows
  ! appear; a check has no inputs to declare, it has a condition.
  type(build_rule_input_t), parameter :: BUILD_RULE_INPUTS(*) = [                                                                  &
    build_rule_input_t('D-AMPLITUDES-DFACT', 'amplitudes.points.value'),                                                          &
    build_rule_input_t('D-AMPLITUDES-DFACT', 'amplitudes.points.time'),                                                           &
    build_rule_input_t('D-DOF-LMDOFN', 'runtime.dof.nodfn'),                                                                      &
    build_rule_input_t('D-INCREMENT-IBLKS-AT-MODEL', 'runtime.dof.ntotv'),                                                        &
    build_rule_input_t('D-INCREMENT-LBLKS-AT-MODEL', 'runtime.dof.ntotv'),                                                        &
    build_rule_input_t('D-ACTIVATION-APPEAR', 'steps0.activation.active'),                                                        &
    build_rule_input_t('D-ACTIVATION-APPEAR', 'mesh.elements.id'),                                                                &
    build_rule_input_t('D-BOUNDARY-LDOFIX', 'steps0.boundary.dof'),                                                               &
    build_rule_input_t('D-BOUNDARY-LDOFIX', 'steps0.boundary.nodes'),                                                             &
    build_rule_input_t('D-BOUNDARY-LDOFIX', 'runtime.dof.nodfn'),                                                                 &
    build_rule_input_t('D-BOUNDARY-LNEFIX', 'mesh.elements.nodes'),                                                               &
    build_rule_input_t('D-BOUNDARY-LNEFIX', 'steps0.boundary.nodes'),                                                             &
    build_rule_input_t('D-BOUNDARY-LELDOFIX', 'mesh.elements.nodes'),                                                             &
    build_rule_input_t('D-BOUNDARY-LELDOFIX', 'steps0.boundary.nodes'),                                                           &
    build_rule_input_t('D-BOUNDARY-LEVDOFIX', 'mesh.elements.nodes'),                                                             &
    build_rule_input_t('D-BOUNDARY-LEVDOFIX', 'steps0.boundary.nodes'),                                                           &
    build_rule_input_t('D-BOUNDARY-LEVDOFIX', 'steps0.boundary.dof'),                                                             &
    build_rule_input_t('D-BOUNDARY-LEFDOFIX', 'mesh.elements.nodes'),                                                             &
    build_rule_input_t('D-BOUNDARY-LEFDOFIX', 'steps0.boundary.nodes'),                                                           &
    build_rule_input_t('D-BOUNDARY-LEFDOFIX', 'steps0.boundary.dof'),                                                             &
    build_rule_input_t('D-DOF-IFFIX', 'steps0.boundary.dof'),                                                                     &
    build_rule_input_t('D-DOF-IFFIX', 'steps0.boundary.nodes'),                                                                   &
    build_rule_input_t('D-DOF-IFFIX', 'runtime.dof.nodfn'),                                                                       &
    build_rule_input_t('D-DOF-FIXED', 'steps0.boundary.value'),                                                                   &
    build_rule_input_t('D-DOF-FIXED', 'steps0.boundary.dof'),                                                                     &
    build_rule_input_t('D-DOF-FIXED', 'runtime.dof.nodfn'),                                                                       &
    build_rule_input_t('D-DOF-NODFN', 'mesh.nodes.id'),                                                                           &
    build_rule_input_t('D-DOF-NODFN', 'mesh.elements.nodes'),                                                                     &
    build_rule_input_t('D-DOF-NODFN', 'sections.fields'),                                                                         &
    build_rule_input_t('D-DOF-NTOTV', 'runtime.dof.nodfn'),                                                                       &
    build_rule_input_t('D-DOF-LDOFS', 'mesh.elements.nodes'),                                                                     &
    build_rule_input_t('D-DOF-LDOFS', 'runtime.dof.nodfn'),                                                                       &
    build_rule_input_t('D-DOF-LDOFS-F', 'mesh.elements.nodes'),                                                                   &
    build_rule_input_t('D-DOF-LDOFS-F', 'runtime.dof.nodfn'),                                                                     &
    build_rule_input_t('D-TOPOLOGY-LISTP-GROUP-MGROUP', 'mesh.sets.elset'),                                                       &
    build_rule_input_t('D-TOPOLOGY-LISTP-GROUP-MGROUP', 'mesh.elements.group'),                                                   &
    build_rule_input_t('D-TOPOLOGY-LISTP-GROUP-LISTG', 'mesh.elements.group'),                                                    &
    build_rule_input_t('D-TOPOLOGY-LISTP-GROUP-LISTG', 'mesh.elements.id'),                                                       &
    build_rule_input_t('D-TOPOLOGY-LISTP-GROUP-LISTP', 'mesh.elements.nodes'),                                                    &
    build_rule_input_t('D-TOPOLOGY-LISTP-GROUP-LISTP', 'mesh.elements.group'),                                                    &
    build_rule_input_t('D-TOPOLOGY-UNODE-IPOIN', 'mesh.nodes.id'),                                                                &
    build_rule_input_t('D-TOPOLOGY-UNODE-IPOIN', 'mesh.elements.nodes'),                                                          &
    build_rule_input_t('D-TOPOLOGY-UNODE-NE-UNODE', 'mesh.elements.nodes'),                                                       &
    build_rule_input_t('D-TOPOLOGY-UNODE-LIST', 'mesh.elements.nodes'),                                                           &
    build_rule_input_t('D-TOPOLOGY-UNODE-NP-UNODE', 'mesh.elements.nodes'),                                                       &
    build_rule_input_t('D-TOPOLOGY-UNODE-PATCH-NOD', 'mesh.elements.nodes'),                                                      &
    build_rule_input_t('D-GAUSS-DJACB', 'mesh.nodes.xyz'),                                                                        &
    build_rule_input_t('D-GAUSS-DJACB', 'mesh.elements.nodes'),                                                                   &
    build_rule_input_t('D-GAUSS-GPCOD', 'mesh.nodes.xyz'),                                                                        &
    build_rule_input_t('D-GAUSS-GPCOD', 'mesh.elements.nodes'),                                                                   &
    build_rule_input_t('D-GAUSS-CARTD', 'mesh.nodes.xyz'),                                                                        &
    build_rule_input_t('D-GAUSS-CARTD', 'mesh.elements.nodes'),                                                                   &
    build_rule_input_t('D-GAUSS-DJACB-MASS', 'mesh.nodes.xyz'),                                                                   &
    build_rule_input_t('D-GAUSS-DJACB-MASS', 'mesh.elements.nodes'),                                                              &
    build_rule_input_t('D-GAUSS-GPCOD-MASS', 'mesh.nodes.xyz'),                                                                   &
    build_rule_input_t('D-GAUSS-GPCOD-MASS', 'mesh.elements.nodes'),                                                              &
    build_rule_input_t('D-ELEMENT-ELCOD-F', 'mesh.nodes.xyz'),                                                                    &
    build_rule_input_t('D-ELEMENT-ELCOD-F', 'mesh.elements.nodes'),                                                               &
    build_rule_input_t('D-ELEMENT-TLOAD', 'mesh.elements.id'),                                                                    &
    build_rule_input_t('D-ELEMENT-ELOAD', 'mesh.elements.id'),                                                                    &
    build_rule_input_t('D-ELEMENT-RLOAD', 'mesh.elements.id'),                                                                    &
    build_rule_input_t('D-VECTORS-RESULT-ZERO', 'runtime.dof.ntotv'),                                                             &
    build_rule_input_t('D-VECTORS-TOFOR', 'runtime.dof.ntotv'),                                                                   &
    build_rule_input_t('D-VECTORS-STFOR', 'runtime.dof.ntotv'),                                                                   &
    build_rule_input_t('D-VECTORS-TOFORL', 'runtime.dof.ntotv'),                                                                  &
    build_rule_input_t('D-VECTORS-TOFORM', 'runtime.dof.ntotv'),                                                                  &
    build_rule_input_t('D-VECTORS-DELITFI', 'runtime.dof.ntotv'),                                                                 &
    build_rule_input_t('D-VECTORS-DELTAFI', 'runtime.dof.ntotv'),                                                                 &
    build_rule_input_t('D-ELEMENT-ICE0', 'mesh.elements.id'),                                                                     &
    build_rule_input_t('D-CURSOR-LINELOAD', 'steps0.boundary.set')]
contains

  ! --- row accessors ----------------------------------------------------------

  ! How many rows the table declares, of every kind. Evidence records coverage
  ! against build_rule_falsifiable_count(), not against this.
  pure integer function build_rule_count() result(n)
    n = size(BUILD_RULES)
  end function build_rule_count

  ! Copy out row `i`. `found` is mandatory, as in opt_get, capability_row and
  ! problem_errors_t%get: an out-of-range index is answered, never assumed away.
  pure subroutine build_rule_row(i, row, found)
    integer, intent(in) :: i
    type(build_rule_t), intent(out) :: row
    logical, intent(out) :: found
    found = .false.
    if (i < 1) return
    if (i > size(BUILD_RULES)) return
    row = BUILD_RULES(i)
    found = .true.
  end subroutine build_rule_row

  ! The rule FAMILY of row `i`, e.g. 'B3'. Several rows may share it once a rule
  ! grows a second condition; that is exactly why it is not the row identity.
  ! Empty for an out-of-range index: this is a reporting path and must not abort.
  pure function build_rule_id(i) result(id)
    integer, intent(in) :: i
    character(len=:), allocatable :: id
    id = ''
    if (i < 1 .or. i > size(BUILD_RULES)) return
    id = trim(BUILD_RULES(i)%rule_id)
  end function build_rule_id

  ! The ROW identity of row `i`: '<rule_id>/<condition>'.
  !
  ! This is the string a raise site passes as the finding's `rule_id`, and the string
  ! a coverage failure prints. It is COMPUTED from the two columns rather than stored
  ! as a third, so a row can never carry a key that disagrees with its own condition.
  ! Binding findings to this key, and not to the family, is the whole M3-02 fix: when
  ! B3 grows a second condition tomorrow the new row starts life UNCOVERED instead of
  ! inheriting the first condition's counter-example.
  pure function build_rule_key(i) result(key)
    integer, intent(in) :: i
    character(len=:), allocatable :: key
    key = ''
    if (i < 1 .or. i > size(BUILD_RULES)) return
    key = trim(BUILD_RULES(i)%rule_id)//'/'//trim(BUILD_RULES(i)%condition)
  end function build_rule_key

  ! The ledger value state row `i`'s `condition` declares, or RUNTIME_VALUE_UNSET when
  ! the row is not a BR_DERIVE row or its condition is not one of the three spellings.
  !
  ! This is the single place the condition vocabulary is interpreted. run_nets asserts
  ! the built runtime's ledger against it for every produced row, which is what turns
  ! the column from a comment into a claim that fails loudly when it stops being true.
  ! An unrecognised condition answers UNSET, and UNSET is never a legal committed state,
  ! so a typo in the table surfaces as a failing build rather than as a skipped check.
  pure integer(int32) function build_rule_expected_state(i) result(state)
    integer, intent(in) :: i
    state = RUNTIME_VALUE_UNSET
    if (i < 1 .or. i > size(BUILD_RULES)) return
    if (BUILD_RULES(i)%kind /= BR_DERIVE) return
    select case (trim(BUILD_RULES(i)%condition))
    case ('built');       state = RUNTIME_VALUE_DEFINED
    case ('reserved');    state = RUNTIME_VALUE_RESERVED
    case ('unallocated'); state = RUNTIME_VALUE_ABSENT
    end select
  end function build_rule_expected_state

  ! Is row `i` required to have a counter-example?
  !
  ! Derived from the kind rather than stored, so the two can never disagree. Checks
  ! and derived quantities are falsifiable; invariants and nets are not, and the
  ! header says why for each. An out-of-range index is not falsifiable, which keeps
  ! the coverage loop total.
  pure logical function build_rule_is_falsifiable(i) result(yes)
    integer, intent(in) :: i
    yes = .false.
    if (i < 1 .or. i > size(BUILD_RULES)) return
    yes = (BUILD_RULES(i)%kind == BR_CHECK) .or. (BUILD_RULES(i)%kind == BR_DERIVE)
  end function build_rule_is_falsifiable

  ! How many rows the coverage walk must account for. The suite prints
  ! "covered: n/build_rule_falsifiable_count()", so adding a rule immediately moves
  ! the denominator and the suite goes red until a counter-example exists.
  pure integer function build_rule_falsifiable_count() result(n)
    integer :: k
    n = 0
    do k = 1, size(BUILD_RULES)
      if (build_rule_is_falsifiable(k)) n = n + 1
    end do
  end function build_rule_falsifiable_count

  ! --- coverage ---------------------------------------------------------------
  !
  ! WHY THE MATCH LIVES HERE AND NOT IN THE SELF-TEST.
  !   Binding a finding to a row means knowing how a raise site spells that row's
  !   object path: the table says `steps[].boundary[]` and the finding says
  !   `steps[1].boundary[3]`, and the index is chosen by build_runtime. A copy of
  !   that knowledge in the test would be a second place to update. The test asks the
  !   question; the declaration answers it. Same division as capability_row_exercised.
  !
  ! WHAT THIS MEASURES.
  !   Rows a finding actually came FROM, read out of the accumulator -- not rows
  !   build_runtime merely evaluated. A row that is evaluated but that no
  !   counter-example can make fire reads as UNCOVERED here, which is the point.

  ! Did any finding in `errors` come from row `i`?
  !
  ! A finding matches when its rule_id is this row's KEY -- the (rule_id, condition)
  ! half of the binding quad -- and its field and index-stripped object path are the
  ! row's. That is the full quad, and it is what separates two conditions of one rule.
  !
  ! Only BR_CHECK rows can be exercised this way. A BR_DERIVE row is covered by the
  ! manifest of a SUCCESSFUL run, which this module cannot see: the suite marks those
  ! by looking build_rule_produced_map_id() up in the manifest and comparing the
  ! entry's kind, rule and input set against this table. Returning .false. here for a
  ! derive row is therefore correct and not a gap -- it is a different evidence path.
  pure logical function build_rule_exercised(errors, i) result(hit)
    type(problem_errors_t), intent(in) :: errors
    integer, intent(in) :: i
    type(build_rule_t) :: row
    type(problem_error_t) :: finding
    logical :: found
    integer :: k

    hit = .false.
    call build_rule_row(i, row, found)
    if (.not. found) return
    if (row%kind /= BR_CHECK .and. row%kind /= BR_INVARIANT .and. row%kind /= BR_NET) return

    do k = 1, errors%count()
      call errors%get(k, finding, found)
      if (.not. found) cycle
      if (opt_value_or(finding%rule_id, '') /= build_rule_key(i)) cycle
      if (opt_value_or(finding%field, '') /= trim(row%field)) cycle
      if (strip_index(opt_value_or(finding%object_path, '')) /= strip_index(trim(row%object_path))) cycle
      hit = .true.
      return
    end do
  end function build_rule_exercised

  ! The first FALSIFIABLE row that no finding in `errors` exercised, or 0 when every
  ! one is covered.
  !
  ! An INDEX and not a logical, deliberately, and for the reason
  ! capability_first_uncovered gives: a suite failing with "row 7, B2/dof-out-of-range,
  ! has no counter-example" is actionable, one failing with "coverage incomplete" is
  ! not. Derive rows are skipped here because their evidence is the manifest, not the
  ! accumulator; the suite ORs its own derive-hit array into this walk.
  pure integer function build_rule_first_uncovered(errors) result(i)
    type(problem_errors_t), intent(in) :: errors
    integer :: k
    i = 0
    do k = 1, size(BUILD_RULES)
      if (BUILD_RULES(k)%kind /= BR_CHECK) cycle
      if (build_rule_exercised(errors, k)) cycle
      i = k
      return
    end do
  end function build_rule_first_uncovered

  ! --- input edges ------------------------------------------------------------

  pure integer function build_rule_input_count() result(n)
    n = size(BUILD_RULE_INPUTS)
  end function build_rule_input_count

  pure subroutine build_rule_input_row(j, edge, found)
    integer, intent(in) :: j
    type(build_rule_input_t), intent(out) :: edge
    logical, intent(out) :: found
    found = .false.
    if (j < 1) return
    if (j > size(BUILD_RULE_INPUTS)) return
    edge = BUILD_RULE_INPUTS(j)
    found = .true.
  end subroutine build_rule_input_row

  ! How many input edges row `i` declares. Zero is a legitimate answer and is not the
  ! same as "unknown": a legacy_default row such as RuntimeState.cursor.linet is a
  ! constant with no inputs, and declaring zero edges for it says so.
  pure integer function build_rule_input_count_for(i) result(n)
    integer, intent(in) :: i
    integer :: j
    n = 0
    if (i < 1 .or. i > size(BUILD_RULES)) return
    do j = 1, size(BUILD_RULE_INPUTS)
      if (trim(BUILD_RULE_INPUTS(j)%rule_id) == trim(BUILD_RULES(i)%rule_id)) n = n + 1
    end do
  end function build_rule_input_count_for

  ! The `n`-th input map id of row `i`, in table order, or '' when there is none.
  ! Order is stable and is the order build_runtime must pass to manifest_add_derived,
  ! so the suite can compare the two lists element by element rather than as sets.
  pure function build_rule_input_at(i, n) result(map_id)
    integer, intent(in) :: i
    integer, intent(in) :: n
    character(len=:), allocatable :: map_id
    integer :: j, seen
    map_id = ''
    if (i < 1 .or. i > size(BUILD_RULES)) return
    if (n < 1) return
    seen = 0
    do j = 1, size(BUILD_RULE_INPUTS)
      if (trim(BUILD_RULE_INPUTS(j)%rule_id) /= trim(BUILD_RULES(i)%rule_id)) cycle
      seen = seen + 1
      if (seen == n) then
        map_id = trim(BUILD_RULE_INPUTS(j)%input_map_id)
        return
      end if
    end do
  end function build_rule_input_at

  ! --- the bijection ----------------------------------------------------------
  !
  ! HOW THE SUITE USES THESE THREE.
  !   The acceptance criterion is that this table's produced set and the M2 map's
  !   model_ready `RuntimeState.*` set are the SAME set, asserted in both directions
  !   so that neither a table row without a map row nor a map row without a table row
  !   can pass:
  !
  !     forward   for n = 1 .. build_rule_produced_count():
  !                 build_rule_produced_map_id(n) must be a model_ready RuntimeState
  !                 row of the map, and appear there exactly once.
  !     backward  for every model_ready RuntimeState row of the map:
  !                 build_rule_producer_of(id) must be non-zero.
  !     injective build_rule_producer_of(build_rule_produced_map_id(n)) is the row
  !                 that produced it, so no two rows may claim the same map id.
  !
  !   The count itself is never written down. It lives in the map, and this table is
  !   checked against it. That is the whole point: M3-02's "15" was transcribed into
  !   a document, the document was then wrong, and nothing could tell.

  ! How many rows produce a map field. Producing rows are exactly the BR_DERIVE rows,
  ! including the `copied` and `unallocated` ones -- a row whose correct product is
  ! "nothing allocated" still produces that map field's state and must be in the
  ! bijection, or the map row it covers would look unclaimed.
  pure integer function build_rule_produced_count() result(n)
    integer :: k
    n = 0
    do k = 1, size(BUILD_RULES)
      if (BUILD_RULES(k)%kind == BR_DERIVE) n = n + 1
    end do
  end function build_rule_produced_count

  ! The `n`-th produced map id, in table order, or '' when out of range.
  pure function build_rule_produced_map_id(n) result(map_id)
    integer, intent(in) :: n
    character(len=:), allocatable :: map_id
    integer :: k, seen
    map_id = ''
    if (n < 1) return
    seen = 0
    do k = 1, size(BUILD_RULES)
      if (BUILD_RULES(k)%kind /= BR_DERIVE) cycle
      seen = seen + 1
      if (seen == n) then
        map_id = trim(BUILD_RULES(k)%map_id)
        return
      end if
    end do
  end function build_rule_produced_map_id

  ! Index of the row that produces `map_id`, 0 when none does. An index and not a
  ! logical, so a backward-direction failure can name the row rather than report that
  ! some map row is unclaimed.
  pure integer function build_rule_producer_of(map_id) result(i)
    character(len=*), intent(in) :: map_id
    integer :: k
    i = 0
    do k = 1, size(BUILD_RULES)
      if (BUILD_RULES(k)%kind /= BR_DERIVE) cycle
      if (trim(BUILD_RULES(k)%map_id) /= map_id) cycle
      i = k
      return
    end do
  end function build_rule_producer_of

  ! --- export -----------------------------------------------------------------

  ! One row as a single stable line:
  !
  !   <tag>|<key>|<kind>|<object_path>|<field>|<code>|<map_id>|<manifest_kind>
  !        |<manifest_rule>|<reach>|<expires_when>|<input_map_id>,...
  !
  ! This is the export path, and it exists for the reason capability_row_text does:
  ! the self-test prints every row through it and the Python cross-check parses those
  ! lines, so the rule table exists exactly ONCE in the repository and there is no
  ! second copy in Python to drift. An out-of-range index renders as the empty string;
  ! export is a reporting path and must not abort.
  pure function build_rule_row_text(i) result(text)
    integer, intent(in) :: i
    character(len=:), allocatable :: text
    integer :: n, j

    text = ''
    if (i < 1 .or. i > size(BUILD_RULES)) return

    text = BUILD_RULES_TAG//'|'//build_rule_key(i)//'|'//kind_text(BUILD_RULES(i)%kind)//               &
           '|'//trim(BUILD_RULES(i)%object_path)//'|'//trim(BUILD_RULES(i)%field)//                     &
           '|'//trim(BUILD_RULES(i)%code)//'|'//trim(BUILD_RULES(i)%map_id)//                           &
           '|'//trim(BUILD_RULES(i)%manifest_kind)//'|'//trim(BUILD_RULES(i)%manifest_rule)//           &
           '|'//reach_text(BUILD_RULES(i)%reach)//'|'//trim(BUILD_RULES(i)%expires_when)//'|'

    n = build_rule_input_count_for(i)
    do j = 1, n
      if (j > 1) text = text//','
      text = text//build_rule_input_at(i, j)
    end do
  end function build_rule_row_text

  ! --- private helpers --------------------------------------------------------

  pure function kind_text(kind) result(t)
    integer(int32), intent(in) :: kind
    character(len=:), allocatable :: t
    select case (kind)
    case (BR_CHECK)
      t = 'check'
    case (BR_DERIVE)
      t = 'derive'
    case (BR_INVARIANT)
      t = 'invariant'
    case (BR_NET)
      t = 'net'
    case default
      t = 'unknown'
    end select
  end function kind_text

  pure function reach_text(reach) result(t)
    integer(int32), intent(in) :: reach
    character(len=:), allocatable :: t
    select case (reach)
    case (BR_REACHABLE)
      t = 'reachable'
    case (BR_UNREACHABLE_BY_CONSTRUCTION)
      t = 'by-construction'
    case (BR_UNREACHABLE_BY_CAPABILITY)
      t = 'by-capability'
    case default
      t = 'unknown'
    end select
  end function reach_text

  ! Delete every `[...]` group, so an object path carrying a collection index compares
  ! equal to the table's index-free spelling of the same path. A local copy of the
  ! helper yl_problem_pipeline uses privately; sharing it would mean exporting a string
  ! utility from the pipeline module, which is a wider change than this task allows.
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

end module yl_runtime_rules
