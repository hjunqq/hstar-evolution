! yl_runtime_contract -- the versioned execution contract for build_runtime.
!
! Scope (see .ccg/tasks/m3-03-build-runtime-commit/plan.md delivery 2 and
! analysis-codex.md S1)
!   Read-only tables and pure accessors. No state, no I/O, no parsing, no allocation of
!   anything the caller keeps. This module answers ONE question: what does build_runtime
!   need to know that a finalized ProblemState does not tell it?
!
! Why this module exists at all
!   The M3-03 claim "all 32 exported model_ready rows are derivable without reading a
!   live legacy global" is TRUE, and it is also incomplete as stated. It holds for
!   ProblemState PLUS a set of premises that ProblemState deliberately does not carry.
!   Writing those premises down, versioned, is the difference between a build that is
!   auditable and a build that has assumptions baked into its control flow where nobody
!   can find them. codex labelled the premises D, C and G:
!
!     D  Ordered field degrees of freedom, field-to-node membership, and the global
!        activation policy. The legacy source is the `.glb` deck's activation flags and
!        the per-group ordered dof lists; ProblemState has neither. Reconstructible for
!        the supported Q4/U/PE combination, and only for it.
!     C  Cold-start and path policy. Restart counters, previous activation, `.nrt`
!        interpolation and refinement state are ABSENT from ProblemState by design --
!        the M3-02 capability gate does not admit restart. Supported-path constants stand
!        in for them. Arbitrary historical values cannot be recovered, and nothing here
!        pretends otherwise.
!     G  Q4 quadrature points, order and weights, and the shape-function rules. Not
!        modelled anywhere in ProblemState, but fully available in the legacy source, so
!        no physical input is missing -- only its transcription.
!
!   A premise that is not in this table is not a premise build_runtime is allowed to
!   have. That is the point: `contract_entry_count` / `contract_entry` make the whole set
!   walkable, so a self-test can enumerate it, and every entry names its class, so a
!   reader can tell a physical rule (G) from a path assumption (C) at a glance. Only the
!   C rows expire when restart arrives; the G rows are properties of the element.
!
! Structure, mirrored from yl_problem_profile
!   PARAMETER tables plus pure accessors, for the same reason: Layer 3 has no I/O, so a
!   table read at run time would have to open a file from inside the pipeline. Fixed-
!   length character components, because a derived type with a deferred-length or
!   allocatable component cannot be a named constant -- and a named constant is what
!   makes the table provably read-only. `contract_entry_text` is the single export path,
!   so the table exists exactly once in the repository and cannot drift against a copy.
!
! Provenance
!   Every value below was READ OUT of the legacy source at the cited line, never inferred
!   and never rounded to something that looked nicer. Read those files with
!   `grep -a` / `sed -n`; they are latin-1, not UTF-8.
!
! The one thing a reader must not skip: literal precision
!   The legacy build passes no `-r8` (tools/build.sh:107-111), so a Fortran literal
!   written without a kind suffix is DEFAULT REAL -- four bytes. The Q4 abscissa is
!   `cnst3 = 1./3.**0.5` (Elements.f90:2352) assigned into a real(real64) array, so the
!   stored value is a single-precision 1/sqrt(3) widened to double, not the double
!   1/sqrt(3). The two differ at about 1e-8 relative. The frozen baseline compares the
!   Gauss geometry at rtol 1e-12 (docs/m2/state-field-map.toml, runtime.gauss.*), so a
!   modern build that computes the abscissa honestly in real64 misses by four orders of
!   magnitude. The quadrature accessors below therefore reproduce the legacy expression
!   in default-real arithmetic and widen the result, and `quadrature.literal_precision`
!   records that as a contract entry rather than as a comment somebody can delete. The
!   same applies to the four-point Gauss-Legendre constants of the mass rule
!   (Elements.f90:2381-2382, :2396-2397), which also carry no kind suffix.
!
!   The SHAPE functions are not affected: their literals are mixed with real64 `s` and
!   `t`, so the arithmetic promotes to real64 (Elements.f90:2924-2935).
module yl_runtime_contract

  use iso_fortran_env, only: int32, real64

  implicit none
  private

  public :: runtime_contract_entry_t
  public :: contract_entry_count, contract_entry, contract_find, contract_entry_text
  public :: contract_expect_int, contract_expect_real, contract_expect_text, contract_expect_logical
  public :: q4_stiffness_quadrature, q4_mass_quadrature, q4_shape_functions

  integer, parameter :: LEN_CLASS = 1
  integer, parameter :: LEN_KEY = 48
  integer, parameter :: LEN_ORIGIN = 28
  integer, parameter :: LEN_VALUE = 48

  ! --- contract identity ------------------------------------------------------
  ! Bumped whenever any entry's value, class or origin changes. A runtime built under one
  ! contract version and compared against a baseline taken under another is comparing two
  ! different claims, so the tag travels in the build manifest.

  character(len=*), parameter, public :: CONTRACT_ID = 'static-q4-si'
  character(len=*), parameter, public :: CONTRACT_VERSION = '1'
  character(len=*), parameter, public :: CONTRACT_TAG = CONTRACT_ID//'/'//CONTRACT_VERSION

  ! --- premise classes --------------------------------------------------------
  ! Single characters so they fit a PARAMETER row, and so `contract_entry_text` renders a
  ! stable column. The distinction is not cosmetic: a C row is a statement about the path
  ! this build supports and stops being true the moment restart is admitted, while a G
  ! row is a statement about the Q4 element and does not.

  character(len=*), parameter, public :: CONTRACT_CLASS_DOF = 'D'
  character(len=*), parameter, public :: CONTRACT_CLASS_PATH = 'C'
  character(len=*), parameter, public :: CONTRACT_CLASS_GEOMETRY = 'G'

  ! --- payload discriminator --------------------------------------------------
  ! Which of the four payload members carries the value. A row sets exactly one; the
  ! other three keep their default initialisers and must not be read. A discriminator,
  ! never a sentinel.

  integer(int32), parameter, public :: CONTRACT_KIND_INT = 1_int32
  integer(int32), parameter, public :: CONTRACT_KIND_REAL = 2_int32
  integer(int32), parameter, public :: CONTRACT_KIND_TEXT = 3_int32
  integer(int32), parameter, public :: CONTRACT_KIND_LOGICAL = 4_int32

  !> One contract entry. `origin` is the legacy file and line the value was read from and
  !> is provenance only -- it is never parsed and never used to locate anything at run
  !> time. `class_id` is one of the three constants above, and is spelled `class_id`
  !> rather than `class` so it cannot be confused with Fortran's CLASS keyword.
  type :: runtime_contract_entry_t
    character(len=LEN_CLASS) :: class_id = ''
    character(len=LEN_KEY) :: key = ''
    character(len=LEN_ORIGIN) :: origin = ''
    integer(int32) :: value_kind = CONTRACT_KIND_INT
    integer(int32) :: int_value = 0_int32
    real(real64) :: real_value = 0.0_real64
    character(len=LEN_VALUE) :: text_value = ''
    logical :: logical_value = .false.
  end type runtime_contract_entry_t

  ! The whole contract, static-q4-si/1. Grouped by class, D then C then G.
  !
  ! D -- ordered field dofs, field-node membership, activation policy
  !   The Q4 element declares one field of four local nodes carrying three global
  !   variables, of which the `.glb` deck enables two on this path. `dof.component_count`
  !   is 2 and NOT 3 for exactly that reason: the element's declared capacity and the
  !   model's enabled set are different numbers and the build must not conflate them.
  !   `dof.component_vocabulary` is the ordered CAE spelling of those two; the legacy
  !   deck expresses the same thing as a flag vector, which is why the origin is the read
  !   statement and not a literal.
  !
  ! C -- cold-start and path policy
  !   Every one of these is a consequence of `restart == 0`. They are listed separately
  !   rather than folded into one `cold_start` flag so that admitting restart later
  !   forces a row-by-row re-decision instead of flipping a single boolean and silently
  !   keeping ten stale assumptions.
  !
  ! G -- Q4 quadrature and shape functions
  !   Scalars only. The point coordinates and weights themselves are not table rows,
  !   because reproducing the legacy arithmetic bit-for-bit matters more than storing a
  !   transcribed decimal: they come from `q4_stiffness_quadrature` and
  !   `q4_mass_quadrature`, and the table records the family, the abscissa expression and
  !   the literal precision that make those accessors auditable.
  ! Implied-shape (F2008): the entry count is never written down, so it cannot be
  ! transcribed wrongly. `contract_entry_count()` is the one place it is computed.
  type(runtime_contract_entry_t), parameter :: ENTRIES(*) = [                                      &
    runtime_contract_entry_t('D', 'field.count', 'Elements.f90:370',                                &
                             CONTRACT_KIND_INT, 1_int32, 0.0_real64, '', .false.),                  &
    runtime_contract_entry_t('D', 'field.local_node_count', 'Elements.f90:374',                     &
                             CONTRACT_KIND_INT, 4_int32, 0.0_real64, '', .false.),                  &
    runtime_contract_entry_t('D', 'field.declared_variable_count', 'Elements.f90:375',              &
                             CONTRACT_KIND_INT, 3_int32, 0.0_real64, '', .false.),                  &
    runtime_contract_entry_t('D', 'dof.component_vocabulary', 'Global.f90:955',                     &
                             CONTRACT_KIND_TEXT, 0_int32, 0.0_real64, 'X,Y', .false.),              &
    runtime_contract_entry_t('D', 'dof.component_count', 'Global.f90:955',                          &
                             CONTRACT_KIND_INT, 2_int32, 0.0_real64, '', .false.),                  &
    runtime_contract_entry_t('D', 'dof.activation_policy', 'Global.f90:1119-1125',                  &
                             CONTRACT_KIND_TEXT, 0_int32, 0.0_real64, 'ALL_ENABLED', .false.),      &
    runtime_contract_entry_t('D', 'dof.numbering_order', 'Global.f90:2147-2156',                    &
                             CONTRACT_KIND_TEXT, 0_int32, 0.0_real64, 'NODE_MAJOR', .false.),       &
    runtime_contract_entry_t('D', 'dof.element_variable_order', 'Global.f90:2161-2199',             &
                             CONTRACT_KIND_TEXT, 0_int32, 0.0_real64,                               &
                             'FIELD_NODE_COMPONENT', .false.),                                      &
    runtime_contract_entry_t('D', 'boundary.attachment_order', 'Prescrib.f90:320-368',              &
                             CONTRACT_KIND_TEXT, 0_int32, 0.0_real64,                               &
                             'SECTION_NODE_ELEMENT', .false.),                                      &
    runtime_contract_entry_t('D', 'boundary.local_position_rule', 'Prescrib.f90:367',               &
                             CONTRACT_KIND_TEXT, 0_int32, 0.0_real64,                               &
                             '(LOCAL_NODE-1)*COMPONENT_COUNT+COMPONENT', .false.),                  &
    runtime_contract_entry_t('D', 'boundary.skip_unnumbered_record', 'Prescrib.f90:256',            &
                             CONTRACT_KIND_LOGICAL, 0_int32, 0.0_real64, '', .true.),               &
    runtime_contract_entry_t('C', 'restart.enabled', 'Fem.f90:277',                                 &
                             CONTRACT_KIND_LOGICAL, 0_int32, 0.0_real64, '', .false.),              &
    runtime_contract_entry_t('C', 'restart.completed_blocks', 'Fem.f90:278',                        &
                             CONTRACT_KIND_INT, 0_int32, 0.0_real64, '', .false.),                  &
    runtime_contract_entry_t('C', 'block.first_index', 'Fem.f90:1683',                              &
                             CONTRACT_KIND_INT, 1_int32, 0.0_real64, '', .false.),                  &
    runtime_contract_entry_t('C', 'constraint.mask_inactive', 'Prescrib.f90:62',                    &
                             CONTRACT_KIND_INT, 5_int32, 0.0_real64, '', .false.),                  &
    runtime_contract_entry_t('C', 'constraint.mask_free', 'Prescrib.f90:72',                        &
                             CONTRACT_KIND_INT, 0_int32, 0.0_real64, '', .false.),                  &
    runtime_contract_entry_t('C', 'constraint.mask_prescribed_base', 'Prescrib.f90:258',            &
                             CONTRACT_KIND_INT, 1_int32, 0.0_real64, '', .false.),                  &
    runtime_contract_entry_t('C', 'constraint.value_at_model_ready', 'Prescrib.f90:63',             &
                             CONTRACT_KIND_REAL, 0_int32, 0.0_real64, '', .false.),                 &
    runtime_contract_entry_t('C', 'amplitude.factor_at_model_ready', 'Load.f90:166',                &
                             CONTRACT_KIND_REAL, 0_int32, 0.0_real64, '', .false.),                 &
    runtime_contract_entry_t('C', 'vector.value_at_model_ready', 'Fem.f90:219',                     &
                             CONTRACT_KIND_REAL, 0_int32, 0.0_real64, '', .false.),                 &
    runtime_contract_entry_t('C', 'element.refinement_skip_default', 'Fem.f90:260',                 &
                             CONTRACT_KIND_INT, 0_int32, 0.0_real64, '', .false.),                  &
    runtime_contract_entry_t('C', 'dof.interpolation_count_default', 'Global.f90:1489',             &
                             CONTRACT_KIND_INT, 0_int32, 0.0_real64, '', .false.),                  &
    runtime_contract_entry_t('C', 'element.load_defined_at_model_ready', 'Load.f90:1237',           &
                             CONTRACT_KIND_LOGICAL, 0_int32, 0.0_real64, '', .false.),              &
    runtime_contract_entry_t('G', 'element.kind_index', 'Elements.f90:367',                         &
                             CONTRACT_KIND_INT, 5_int32, 0.0_real64, '', .false.),                  &
    runtime_contract_entry_t('G', 'element.node_count', 'Elements.f90:368',                         &
                             CONTRACT_KIND_INT, 4_int32, 0.0_real64, '', .false.),                  &
    runtime_contract_entry_t('G', 'element.dimension_count', 'Elements.f90:369',                    &
                             CONTRACT_KIND_INT, 2_int32, 0.0_real64, '', .false.),                  &
    runtime_contract_entry_t('G', 'element.integration_rule_count', 'Elements.f90:371',             &
                             CONTRACT_KIND_INT, 2_int32, 0.0_real64, '', .false.),                  &
    runtime_contract_entry_t('G', 'integration.stiffness.name', 'Elements.f90:379',                 &
                             CONTRACT_KIND_TEXT, 0_int32, 0.0_real64, 'stiff', .false.),            &
    runtime_contract_entry_t('G', 'integration.stiffness.point_count', 'Elements.f90:380',          &
                             CONTRACT_KIND_INT, 4_int32, 0.0_real64, '', .false.),                  &
    runtime_contract_entry_t('G', 'integration.stiffness.node_count', 'Elements.f90:381',           &
                             CONTRACT_KIND_INT, 4_int32, 0.0_real64, '', .false.),                  &
    runtime_contract_entry_t('G', 'integration.mass.name', 'Elements.f90:383',                      &
                             CONTRACT_KIND_TEXT, 0_int32, 0.0_real64, 'mass', .false.),             &
    runtime_contract_entry_t('G', 'integration.mass.point_count', 'Elements.f90:384',               &
                             CONTRACT_KIND_INT, 16_int32, 0.0_real64, '', .false.),                 &
    runtime_contract_entry_t('G', 'integration.mass.node_count', 'Elements.f90:385',                &
                             CONTRACT_KIND_INT, 4_int32, 0.0_real64, '', .false.),                  &
    runtime_contract_entry_t('G', 'integration.field_rule_order', 'Elements.f90:377',               &
                             CONTRACT_KIND_TEXT, 0_int32, 0.0_real64, '1,1', .false.),              &
    runtime_contract_entry_t('G', 'quadrature.stiffness.family', 'Elements.f90:2351-2363',          &
                             CONTRACT_KIND_TEXT, 0_int32, 0.0_real64,                               &
                             'GAUSS_LEGENDRE_2X2', .false.),                                        &
    runtime_contract_entry_t('G', 'quadrature.stiffness.abscissa_rule', 'Elements.f90:2352',        &
                             CONTRACT_KIND_TEXT, 0_int32, 0.0_real64, '1/3**0.5', .false.),         &
    runtime_contract_entry_t('G', 'quadrature.stiffness.weight', 'Elements.f90:2362',               &
                             CONTRACT_KIND_REAL, 0_int32, 1.0_real64, '', .false.),                 &
    runtime_contract_entry_t('G', 'quadrature.mass.family', 'Elements.f90:2380-2401',               &
                             CONTRACT_KIND_TEXT, 0_int32, 0.0_real64,                               &
                             'GAUSS_LEGENDRE_4X4', .false.),                                        &
    runtime_contract_entry_t('G', 'quadrature.literal_precision', 'Elements.f90:2352',              &
                             CONTRACT_KIND_TEXT, 0_int32, 0.0_real64, 'DEFAULT_REAL', .false.),     &
    runtime_contract_entry_t('G', 'shape.family', 'Elements.f90:2923-2927',                         &
                             CONTRACT_KIND_TEXT, 0_int32, 0.0_real64, 'BILINEAR_Q4', .false.),      &
    runtime_contract_entry_t('G', 'shape.gradient_form', 'Elements.f90:2928-2935',                  &
                             CONTRACT_KIND_TEXT, 0_int32, 0.0_real64,                               &
                             'ANALYTIC_NATURAL', .false.),                                          &
    runtime_contract_entry_t('G', 'geometry.point_coordinate_rule', 'Elements.f90:1260',            &
                             CONTRACT_KIND_TEXT, 0_int32, 0.0_real64,                               &
                             'SUM_SHAPE_TIMES_NODE_COORDINATE', .false.),                           &
    runtime_contract_entry_t('G', 'geometry.weighted_jacobian_rule', 'Elements.f90:1363',           &
                             CONTRACT_KIND_TEXT, 0_int32, 0.0_real64,                               &
                             'DET_J_TIMES_WEIGHT', .false.),                                        &
    runtime_contract_entry_t('G', 'geometry.shape_gradient_rules', 'Elements.f90:1359',             &
                             CONTRACT_KIND_TEXT, 0_int32, 0.0_real64,                               &
                             'STIFFNESS_ONLY', .false.)]

contains

  ! --- walkable surface -------------------------------------------------------

  !> Number of contract entries. The self-test walks 1..contract_entry_count() and must
  !> account for every row, so an entry added without a corresponding assertion fails the
  !> suite rather than passing unnoticed.
  pure integer function contract_entry_count() result(n)
    n = size(ENTRIES)
  end function contract_entry_count

  !> Copy out entry `i`. `found` is mandatory, as in opt_get and profile_default_row: an
  !> out-of-range index is answered, never assumed away.
  pure subroutine contract_entry(i, row, found)
    integer, intent(in) :: i
    type(runtime_contract_entry_t), intent(out) :: row
    logical, intent(out) :: found
    found = .false.
    if (i < 1) return
    if (i > size(ENTRIES)) return
    row = ENTRIES(i)
    found = .true.
  end subroutine contract_entry

  !> Index of the entry with this key, 0 when there is none.
  pure integer function contract_find(key) result(row_index)
    character(len=*), intent(in) :: key
    integer :: i
    row_index = 0
    do i = 1, size(ENTRIES)
      if (trim(ENTRIES(i)%key) == key) then
        row_index = i
        return
      end if
    end do
  end function contract_find

  !> Integer premise by key. A key that exists but holds a different payload kind reports
  !> NOT FOUND rather than a coerced value: a type confusion in the table must surface as
  !> a missing premise, not as a plausible wrong number that then propagates into every
  !> derived array. Same discipline in the three accessors below.
  pure subroutine contract_expect_int(key, value, found)
    character(len=*), intent(in) :: key
    integer(int32), intent(out) :: value
    logical, intent(out) :: found
    integer :: i
    value = 0_int32
    found = .false.
    i = contract_find(key)
    if (i == 0) return
    if (ENTRIES(i)%value_kind /= CONTRACT_KIND_INT) return
    value = ENTRIES(i)%int_value
    found = .true.
  end subroutine contract_expect_int

  pure subroutine contract_expect_real(key, value, found)
    character(len=*), intent(in) :: key
    real(real64), intent(out) :: value
    logical, intent(out) :: found
    integer :: i
    value = 0.0_real64
    found = .false.
    i = contract_find(key)
    if (i == 0) return
    if (ENTRIES(i)%value_kind /= CONTRACT_KIND_REAL) return
    value = ENTRIES(i)%real_value
    found = .true.
  end subroutine contract_expect_real

  pure subroutine contract_expect_text(key, value, found)
    character(len=*), intent(in) :: key
    character(len=:), allocatable, intent(out) :: value
    logical, intent(out) :: found
    integer :: i
    value = ''
    found = .false.
    i = contract_find(key)
    if (i == 0) return
    if (ENTRIES(i)%value_kind /= CONTRACT_KIND_TEXT) return
    value = trim(ENTRIES(i)%text_value)
    found = .true.
  end subroutine contract_expect_text

  pure subroutine contract_expect_logical(key, value, found)
    character(len=*), intent(in) :: key
    logical, intent(out) :: value
    logical, intent(out) :: found
    integer :: i
    value = .false.
    found = .false.
    i = contract_find(key)
    if (i == 0) return
    if (ENTRIES(i)%value_kind /= CONTRACT_KIND_LOGICAL) return
    value = ENTRIES(i)%logical_value
    found = .true.
  end subroutine contract_expect_logical

  !> One entry as a single stable line:
  !>
  !>   <tag>|<class>|<key>|<origin>|<kind>|<value>
  !>
  !> kind is one of i32/f64/text/bool. This is the export path: the self-test prints
  !> every row through this function, so the contract exists exactly once in the
  !> repository and there is no second copy in Python to drift against. An out-of-range
  !> index renders as the empty string; export is a reporting path and must not abort.
  pure function contract_entry_text(i) result(text)
    integer, intent(in) :: i
    character(len=:), allocatable :: text
    character(len=32) :: buffer

    if (i < 1 .or. i > size(ENTRIES)) then
      text = ''
      return
    end if

    text = CONTRACT_TAG//'|'//trim(ENTRIES(i)%class_id)//'|'//trim(ENTRIES(i)%key)//  &
           '|'//trim(ENTRIES(i)%origin)//'|'

    select case (ENTRIES(i)%value_kind)
    case (CONTRACT_KIND_INT)
      write (buffer, '(i0)') ENTRIES(i)%int_value
      text = text//'i32|'//trim(buffer)
    case (CONTRACT_KIND_REAL)
      write (buffer, '(es25.17e3)') ENTRIES(i)%real_value
      text = text//'f64|'//trim(adjustl(buffer))
    case (CONTRACT_KIND_TEXT)
      text = text//'text|'//trim(ENTRIES(i)%text_value)
    case (CONTRACT_KIND_LOGICAL)
      if (ENTRIES(i)%logical_value) then
        text = text//'bool|true'
      else
        text = text//'bool|false'
      end if
    case default
      text = text//'unknown|'
    end select
  end function contract_entry_text

  ! --- Q4 quadrature ----------------------------------------------------------

  !> The 2x2 Gauss-Legendre rule the static_2d path integrates with.
  !> `points(dimension, point)` in natural coordinates, `weights(point)`.
  !>
  !> Transcribed from Elements.f90:2352-2363, including its arithmetic and its point
  !> ORDER, which runs counter-clockwise (--, +-, ++, -+) and is not the lexicographic
  !> order a fresh implementation would pick. The order is load-bearing: every per-point
  !> array in the frozen baseline is indexed by it.
  !>
  !> `abscissa` is evaluated in DEFAULT REAL and then widened, because that is what the
  !> legacy statement does under a build with no `-r8`. See the module header; do not
  !> "fix" this to real64 without also refreshing the frozen baseline.
  pure subroutine q4_stiffness_quadrature(points, weights)
    real(real64), intent(out) :: points(2, 4)
    real(real64), intent(out) :: weights(4)
    real(real64) :: abscissa

    abscissa = real(1./3.**0.5, real64)          ! Elements.f90:2352, default-real literals

    points(1, 1) = -abscissa                     ! Elements.f90:2353
    points(2, 1) = -abscissa                     ! Elements.f90:2354
    points(1, 2) = abscissa                      ! Elements.f90:2355
    points(2, 2) = -abscissa                     ! Elements.f90:2356
    points(1, 3) = abscissa                      ! Elements.f90:2357
    points(2, 3) = abscissa                      ! Elements.f90:2358
    points(1, 4) = -abscissa                     ! Elements.f90:2359
    points(2, 4) = abscissa                      ! Elements.f90:2360

    weights = 1.00_real64                        ! Elements.f90:2361-2363
  end subroutine q4_stiffness_quadrature

  !> The 4x4 Gauss-Legendre rule Q4 declares as its second ('mass') rule.
  !> `points(dimension, point)`, `weights(point)`.
  !>
  !> Transcribed from Elements.f90:2380-2401, tables LK16 / LI16 at :2213 included. The
  !> static_2d path never CONSUMES this rule -- `order_intrules=(/1,1/)` at :377 routes
  !> every consumer to the stiffness rule -- but read_element still evaluates its geometry
  !> for every element, so build_runtime must produce it to hold a complete RuntimeState.
  !> Its two map rows are snapshot-excluded, which is why their ledger state is DEFINED
  !> and not compared.
  !>
  !> The four abscissae and weights carry no kind suffix in the legacy source
  !> (:2381-2382, :2396-2397), so they too are default-real values widened to double.
  pure subroutine q4_mass_quadrature(points, weights)
    real(real64), intent(out) :: points(2, 16)
    real(real64), intent(out) :: weights(16)
    ! Elements.f90:2213 -- DATA LK16/8*-1,8*1/, LI16/-1,-1,1,1,.../
    integer(int32), parameter :: LK16(16) = [-1, -1, -1, -1, -1, -1, -1, -1, 1, 1, 1, 1, 1, 1, 1, 1]
    integer(int32), parameter :: LI16(16) = [-1, -1, 1, 1, -1, -1, 1, 1, -1, -1, 1, 1, -1, -1, 1, 1]
    real(real64) :: g1, g2, w(4)
    integer :: i, j, k

    g1 = real(0.8611363115940530, real64)        ! Elements.f90:2381
    g2 = real(0.3399810435848560, real64)        ! Elements.f90:2382

    do i = 1, 16                                 ! Elements.f90:2383-2395
      if (i <= 4 .or. i >= 13) then
        points(1, i) = g1*real(LK16(i), real64)
      else
        points(1, i) = g2*real(LK16(i), real64)
      end if
      if (i == 1 .or. i == 4 .or. i == 5 .or. i == 8 .or.                                          &
          i == 9 .or. i == 12 .or. i == 13 .or. i == 16) then
        points(2, i) = g1*real(LI16(i), real64)
      else
        points(2, i) = g2*real(LI16(i), real64)
      end if
    end do

    w(1) = real(0.3478548451374540, real64)      ! Elements.f90:2396
    w(2) = real(0.6521451548625460, real64)      ! Elements.f90:2397
    w(3) = w(2)                                  ! Elements.f90:2398
    w(4) = w(1)                                  ! Elements.f90:2399

    k = 0                                        ! Elements.f90:2400-2401 and the K loop
    do i = 1, 4
      do j = 1, 4
        k = k + 1
        weights(k) = w(i)*w(j)
      end do
    end do
  end subroutine q4_mass_quadrature

  ! --- Q4 shape functions -----------------------------------------------------

  !> Bilinear Q4 shape functions and their NATURAL-coordinate gradients at (s, t).
  !> `values(local node)`, `gradients(dimension, local node)`.
  !>
  !> Transcribed statement for statement from Elements.f90:2924-2935, with the auxiliary
  !> `st = s*t` from :2613. The expressions are kept in their legacy algebraic form --
  !> `(1-t-s+st)*0.25` rather than the factored `0.25*(1-s)*(1-t)` -- because the two are
  !> equal in exact arithmetic and NOT bitwise equal in floating point, and the frozen
  !> Gauss baseline is compared at rtol 1e-12.
  !>
  !> `s` and `t` are real64, so the unsuffixed literals promote and this routine, unlike
  !> the quadrature ones above, involves no default-real evaluation.
  !>
  !> Node order follows those expressions: node 1 at (-1,-1), 2 at (+1,-1), 3 at (+1,+1),
  !> 4 at (-1,+1) -- counter-clockwise. build_runtime must reject an element whose
  !> connectivity makes the Jacobian determinant non-positive under this order rather than
  !> silently integrating a folded element.
  !>
  !> This routine deliberately does NOT compute the physical gradients or the Jacobian:
  !> those need the element coordinates, which belong to build_runtime, not to a contract.
  pure subroutine q4_shape_functions(s, t, values, gradients)
    real(real64), intent(in) :: s, t
    real(real64), intent(out) :: values(4)
    real(real64), intent(out) :: gradients(2, 4)
    real(real64) :: st

    st = s*t                                     ! Elements.f90:2613

    values(1) = (1 - t - s + st)*0.25_real64     ! Elements.f90:2924
    values(2) = (1 - t + s - st)*0.25_real64     ! Elements.f90:2925
    values(3) = (1 + t + s + st)*0.25_real64     ! Elements.f90:2926
    values(4) = (1 + t - s - st)*0.25_real64     ! Elements.f90:2927

    gradients(1, 1) = (-1 + t)*0.25_real64       ! Elements.f90:2928
    gradients(1, 2) = (+1 - t)*0.25_real64       ! Elements.f90:2929
    gradients(1, 3) = (+1 + t)*0.25_real64       ! Elements.f90:2930
    gradients(1, 4) = (-1 - t)*0.25_real64       ! Elements.f90:2931
    gradients(2, 1) = (-1 + s)*0.25_real64       ! Elements.f90:2932
    gradients(2, 2) = (-1 - s)*0.25_real64       ! Elements.f90:2933
    gradients(2, 3) = (+1 + s)*0.25_real64       ! Elements.f90:2934
    gradients(2, 4) = (+1 - s)*0.25_real64       ! Elements.f90:2935
  end subroutine q4_shape_functions

end module yl_runtime_contract
