! yl_problem_profile -- the versioned default profile and the capability table.
!
! Scope (see .ccg/tasks/m3-02-normalize-validate-finalize/plan.md delivery 2,
! analysis.md "capability table" ruling, analysis-codex.md S5, analysis-claude.md S3)
!   Two read-only tables and their accessors. No I/O, no parsing, no state.
!     * DEFAULTS      -- values the pipeline may supply when the author did not,
!                        each stamped with the profile version that supplied it.
!     * CAPABILITIES  -- the single model combination this build can run, one row
!                        per checked item, each carrying the gate rule that owns it.
!
! Why Fortran constants and not a TOML file
!   Layer 3 of the target architecture has no I/O and no parser, so a table read at
!   run time would have to open a file from inside the pipeline. The tables are
!   therefore compiled in, and the ONE copy is exported for cross-checking rather
!   than transcribed: capability_row_text() renders a row in a stable, parseable
!   form, the self-test prints those rows, and the Python side compares them
!   against the map. There is deliberately no second table in Python to drift.
!
! Versioning
!   A default is only meaningful together with the profile that produced it, so
!   PROFILE_ID / PROFILE_VERSION are public and profile_lookup_* hands back the row
!   index that supplied the value. finalize records `key`, `map_id`, `rule_id` and
!   the profile tag in the manifest for every default it applies, which is what
!   makes a defaulted value auditable rather than indistinguishable from an
!   authored one.
!
! Vocabulary
!   Keys are CAE vocabulary, never Fortran slot names: the stress-component count
!   is `plane_strain.stress_components`, and the legacy map row it corresponds to
!   travels alongside in `map_id` as provenance only. This mirrors the rule that
!   keeps yl_problem_types.f90 free of legacy spellings.
!
! Scale
!   M3-02 has exactly ONE default row. The table, the typed payload discriminator
!   and the lookup are built for the sixteen further legacy_default rows that
!   M3-03 adds, so that growth is a table edit rather than a redesign.
!
! Deliberately absent from the capability table
!   `restart` and `steps[].load_mode`. The team lead ruled both out for M3-02:
!   neither has a constructible counter-example on the two golden decks at this
!   stage (the draft cannot express restart at all, and no M3-02 consumer reads
!   load_mode), and a gate item that cannot fail is exactly the defect this
!   milestone exists to stop shipping. Both return when a fixture can falsify them.
module yl_problem_profile

  use iso_fortran_env, only: int32

  implicit none
  private

  public :: profile_default_t, capability_item_t
  public :: profile_default_count, profile_default_row, profile_lookup_int, profile_lookup_text
  public :: capability_count, capability_row, capability_find, capability_row_text
  public :: capability_expect_int, capability_expect_text, capability_expect_logical

  ! Fixed lengths, so that both tables can be PARAMETER arrays: a derived type with
  ! a deferred-length or allocatable component cannot be a named constant, and a
  ! named constant is what makes these tables provably read-only.
  integer, parameter :: LEN_KEY = 48
  integer, parameter :: LEN_MAP_ID = 48
  integer, parameter :: LEN_RULE = 24
  integer, parameter :: LEN_PATH = 40
  integer, parameter :: LEN_FIELD = 24
  integer, parameter :: LEN_VALUE = 32
  integer, parameter :: LEN_DTYPE = 8

  ! --- profile identity -------------------------------------------------------

  character(len=*), parameter, public :: PROFILE_ID = 'static-q4-si'
  character(len=*), parameter, public :: PROFILE_VERSION = '1'
  character(len=*), parameter, public :: PROFILE_TAG = PROFILE_ID//'/'//PROFILE_VERSION

  ! --- capability identity ----------------------------------------------------

  character(len=*), parameter, public :: CAPABILITY_ID = 'static-q4'
  character(len=*), parameter, public :: CAPABILITY_VERSION = '1'
  character(len=*), parameter, public :: CAPABILITY_TAG = CAPABILITY_ID//'/'//CAPABILITY_VERSION

  ! --- payload discriminator --------------------------------------------------
  ! Which of the three payload members of a row carries the value. A row always
  ! sets exactly one; the other two keep their default initialisers and must not
  ! be read. This is a discriminator, not a sentinel: it says WHICH member is
  ! meaningful, it never encodes absence as a magic value.

  integer(int32), parameter, public :: PROFILE_KIND_INT = 1_int32
  integer(int32), parameter, public :: PROFILE_KIND_TEXT = 2_int32
  integer(int32), parameter, public :: PROFILE_KIND_LOGICAL = 3_int32

  ! --- default profile row ----------------------------------------------------

  type :: profile_default_t
    character(len=LEN_KEY) :: key = ''          ! CAE vocabulary key, the lookup name
    character(len=LEN_MAP_ID) :: map_id = ''    ! M2 map row, provenance only
    character(len=LEN_RULE) :: rule_id = ''     ! the map `source` that justifies the default
    character(len=LEN_DTYPE) :: dtype = ''      ! map dtype of the defaulted value
    integer(int32) :: value_kind = PROFILE_KIND_INT
    integer(int32) :: int_value = 0_int32
    character(len=LEN_VALUE) :: text_value = ''
    logical :: logical_value = .false.
  end type profile_default_t

  ! The whole M3-02 default profile.
  !
  ! plane_strain.stress_components = 4: a plane-strain continuum point carries
  ! sxx, syy, szz and sxy. szz is not zero under plane strain, which is why the
  ! count is 4 and not 3, and it is a property of the formulation rather than of
  ! any authored input -- so it is a profile default, not a required field.
  type(profile_default_t), parameter :: DEFAULTS(1) = [                        &
    profile_default_t(key='plane_strain.stress_components',                    &
                      map_id='derived.counts.nstre',                           &
                      rule_id='derived:legacy_default',                        &
                      dtype='i32',                                             &
                      value_kind=PROFILE_KIND_INT,                             &
                      int_value=4_int32,                                       &
                      text_value='',                                           &
                      logical_value=.false.)]

  ! --- capability row ---------------------------------------------------------
  ! `item` is the CAE name of the checked property; `object_path` and `field` say
  ! which component of the ProblemState the gate reads, so the gate's rejection
  ! message can name the offending object without a second lookup table. A field
  ! of `size` means the check is on the cardinality of the collection named by
  ! object_path, not on a component of it.

  type :: capability_item_t
    character(len=LEN_RULE) :: rule_id = ''     ! G1..G6, the gate rule that owns the row
    character(len=LEN_KEY) :: item = ''         ! CAE vocabulary name of the property
    character(len=LEN_PATH) :: object_path = '' ! ProblemState object the value is read from
    character(len=LEN_FIELD) :: field = ''      ! component, or `size` for a cardinality
    integer(int32) :: value_kind = PROFILE_KIND_TEXT
    integer(int32) :: int_value = 0_int32
    character(len=LEN_VALUE) :: text_value = ''
    logical :: logical_value = .false.
  end type capability_item_t

  ! The one supported combination, static-q4/1. Grouped by owning gate rule:
  !   G1 element    -- what the element is
  !   G2 formulation-- what physics is being solved
  !   G3 material   -- what constitutive model
  !   G4 solver     -- which linear solver and which symmetry
  !   G5 load       -- which load kinds may appear
  !   G6 extent     -- how many sections, steps and increments
  ! Text values are the canonical upper-case spellings produced by normalize rule
  ! N1, so the gate compares canonical against canonical and never case-folds here.
  type(capability_item_t), parameter :: CAPABILITIES(15) = [                                        &
    capability_item_t('G1', 'element.type', 'sections[]', 'element',                                &
                      PROFILE_KIND_TEXT, 0_int32, 'Q4', .false.),                                   &
    capability_item_t('G1', 'element.kind_code', 'sections[]', 'element_kind',                      &
                      PROFILE_KIND_INT, 5_int32, '', .false.),                                      &
    capability_item_t('G1', 'element.class', 'sections[]', 'class',                                 &
                      PROFILE_KIND_TEXT, 0_int32, 'CO', .false.),                                   &
    capability_item_t('G1', 'element.fields', 'sections[]', 'fields',                               &
                      PROFILE_KIND_TEXT, 0_int32, 'U', .false.),                                    &
    capability_item_t('G2', 'analysis.dimension', 'mesh', 'dimension',                              &
                      PROFILE_KIND_INT, 2_int32, '', .false.),                                      &
    capability_item_t('G2', 'element.formulation', 'sections[]', 'formulation',                     &
                      PROFILE_KIND_TEXT, 0_int32, 'PE', .false.),                                   &
    capability_item_t('G2', 'analysis.procedure', 'steps[]', 'procedure',                           &
                      PROFILE_KIND_TEXT, 0_int32, 'Q', .false.),                                    &
    capability_item_t('G3', 'material.kind', 'materials[]', 'kind',                                 &
                      PROFILE_KIND_TEXT, 0_int32, 'MECHANICAL', .false.),                           &
    capability_item_t('G3', 'material.model', 'materials[]', 'model',                               &
                      PROFILE_KIND_TEXT, 0_int32, 'ELASTIC_ISOTROPIC', .false.),                    &
    capability_item_t('G4', 'solver.linear', 'solver', 'linear',                                    &
                      PROFILE_KIND_TEXT, 0_int32, 'PROFILE', .false.),                              &
    capability_item_t('G4', 'solver.symmetric', 'solver', 'symmetric',                              &
                      PROFILE_KIND_LOGICAL, 0_int32, '', .true.),                                   &
    capability_item_t('G5', 'load.gravity_enabled', 'steps[].load.gravity', 'enabled',              &
                      PROFILE_KIND_INT, 1_int32, '', .false.),                                      &
    ! READ THIS BEFORE RAISING THE SECTION COUNT.
    ! This row is load-bearing beyond the gate. finalize derives one element set
    ! per section, and a draft with two sections whose elements ALL belong to the
    ! first would make the second set an allocated zero-length set -- an explicit
    ! empty where nothing was authored, which ADR-0002 forbids. No validation rule
    ! guards that case, on purpose: while this row reads 1 the case is
    ! unreachable, and a rule that nothing can fail is the defect this milestone
    ! exists to remove. The net today is the pipeline's INV-EMPTY-DERIVED
    ! assertion, which reports the situation as an INTERNAL fault -- the wrong
    ! class for what is really an input defect, and acceptable only because it
    ! cannot fire. So raising this above 1 REQUIRES adding that validation rule
    ! first, with a counter-example draft; otherwise the first two-section model a
    ! user writes is answered with an internal fault.
    capability_item_t('G6', 'model.section_count', 'sections', 'size',                              &
                      PROFILE_KIND_INT, 1_int32, '', .false.),                                      &
    capability_item_t('G6', 'analysis.step_count', 'steps', 'size',                                 &
                      PROFILE_KIND_INT, 1_int32, '', .false.),                                      &
    capability_item_t('G6', 'analysis.increments', 'steps[].controls', 'increments',                &
                      PROFILE_KIND_INT, 1_int32, '', .false.)]

contains

  ! --- default profile accessors ----------------------------------------------

  pure integer function profile_default_count() result(n)
    n = size(DEFAULTS)
  end function profile_default_count

  ! Copy out default row `i`. `found` is mandatory, as in opt_get and
  ! problem_errors_t%get: an out-of-range index is answered, never assumed away.
  pure subroutine profile_default_row(i, row, found)
    integer, intent(in) :: i
    type(profile_default_t), intent(out) :: row
    logical, intent(out) :: found
    found = .false.
    if (i < 1) return
    if (i > size(DEFAULTS)) return
    row = DEFAULTS(i)
    found = .true.
  end subroutine profile_default_row

  ! Look up an integer-valued default by CAE key. `row_index` is returned so that
  ! finalize can record WHICH profile row supplied the value, together with its
  ! map_id and rule_id, in the manifest. A key that exists but holds a different
  ! payload kind is reported as not found rather than coerced: a type confusion in
  ! the table must surface as a missing default, not as a plausible wrong number.
  pure subroutine profile_lookup_int(key, value, found, row_index)
    character(len=*), intent(in) :: key
    integer(int32), intent(out) :: value
    logical, intent(out) :: found
    integer, intent(out) :: row_index
    integer :: i
    value = 0_int32
    found = .false.
    row_index = 0
    do i = 1, size(DEFAULTS)
      if (trim(DEFAULTS(i)%key) == key) then
        if (DEFAULTS(i)%value_kind == PROFILE_KIND_INT) then
          value = DEFAULTS(i)%int_value
          found = .true.
          row_index = i
        end if
        return
      end if
    end do
  end subroutine profile_lookup_int

  ! Text counterpart of profile_lookup_int. No M3-02 row uses it; it exists so the
  ! M3-03 rows that default a text value need no new mechanism.
  pure subroutine profile_lookup_text(key, value, found, row_index)
    character(len=*), intent(in) :: key
    character(len=:), allocatable, intent(out) :: value
    logical, intent(out) :: found
    integer, intent(out) :: row_index
    integer :: i
    value = ''
    found = .false.
    row_index = 0
    do i = 1, size(DEFAULTS)
      if (trim(DEFAULTS(i)%key) == key) then
        if (DEFAULTS(i)%value_kind == PROFILE_KIND_TEXT) then
          value = trim(DEFAULTS(i)%text_value)
          found = .true.
          row_index = i
        end if
        return
      end if
    end do
  end subroutine profile_lookup_text

  ! --- capability accessors ---------------------------------------------------

  pure integer function capability_count() result(n)
    n = size(CAPABILITIES)
  end function capability_count

  pure subroutine capability_row(i, row, found)
    integer, intent(in) :: i
    type(capability_item_t), intent(out) :: row
    logical, intent(out) :: found
    found = .false.
    if (i < 1) return
    if (i > size(CAPABILITIES)) return
    row = CAPABILITIES(i)
    found = .true.
  end subroutine capability_row

  ! Index of the capability row for a CAE item name, 0 when there is none. The
  ! gate uses this to fetch the rule id and the expected value for the item it is
  ! about to check, so the expected value is never spelled twice.
  pure integer function capability_find(item) result(row_index)
    character(len=*), intent(in) :: item
    integer :: i
    row_index = 0
    do i = 1, size(CAPABILITIES)
      if (trim(CAPABILITIES(i)%item) == item) then
        row_index = i
        return
      end if
    end do
  end function capability_find

  ! Expected integer for a capability item. As with profile_lookup_int, a payload
  ! kind mismatch reports not-found rather than returning a coerced value.
  pure subroutine capability_expect_int(item, value, found)
    character(len=*), intent(in) :: item
    integer(int32), intent(out) :: value
    logical, intent(out) :: found
    integer :: i
    value = 0_int32
    found = .false.
    i = capability_find(item)
    if (i == 0) return
    if (CAPABILITIES(i)%value_kind /= PROFILE_KIND_INT) return
    value = CAPABILITIES(i)%int_value
    found = .true.
  end subroutine capability_expect_int

  pure subroutine capability_expect_text(item, value, found)
    character(len=*), intent(in) :: item
    character(len=:), allocatable, intent(out) :: value
    logical, intent(out) :: found
    integer :: i
    value = ''
    found = .false.
    i = capability_find(item)
    if (i == 0) return
    if (CAPABILITIES(i)%value_kind /= PROFILE_KIND_TEXT) return
    value = trim(CAPABILITIES(i)%text_value)
    found = .true.
  end subroutine capability_expect_text

  pure subroutine capability_expect_logical(item, value, found)
    character(len=*), intent(in) :: item
    logical, intent(out) :: value
    logical, intent(out) :: found
    integer :: i
    value = .false.
    found = .false.
    i = capability_find(item)
    if (i == 0) return
    if (CAPABILITIES(i)%value_kind /= PROFILE_KIND_LOGICAL) return
    value = CAPABILITIES(i)%logical_value
    found = .true.
  end subroutine capability_expect_logical

  ! One capability row as a single stable line:
  !
  !   <tag>|<rule_id>|<item>|<object_path>|<field>|<kind>|<value>
  !
  ! kind is one of i32/text/bool and value is the decimal integer, the canonical
  ! text, or true/false. This is the export path: the self-test prints every row
  ! through this function and the Python cross-check parses those lines, so the
  ! capability table exists exactly once in the repository. An out-of-range index
  ! renders as the empty string; export is a reporting path and must not abort.
  pure function capability_row_text(i) result(text)
    integer, intent(in) :: i
    character(len=:), allocatable :: text
    character(len=12) :: buffer

    if (i < 1 .or. i > size(CAPABILITIES)) then
      text = ''
      return
    end if

    text = CAPABILITY_TAG//'|'//trim(CAPABILITIES(i)%rule_id)//'|'//trim(CAPABILITIES(i)%item)//   &
           '|'//trim(CAPABILITIES(i)%object_path)//'|'//trim(CAPABILITIES(i)%field)//'|'

    select case (CAPABILITIES(i)%value_kind)
    case (PROFILE_KIND_INT)
      write (buffer, '(i0)') CAPABILITIES(i)%int_value
      text = text//'i32|'//trim(buffer)
    case (PROFILE_KIND_TEXT)
      text = text//'text|'//trim(CAPABILITIES(i)%text_value)
    case (PROFILE_KIND_LOGICAL)
      if (CAPABILITIES(i)%logical_value) then
        text = text//'bool|true'
      else
        text = text//'bool|false'
      end if
    case default
      text = text//'unknown|'
    end select
  end function capability_row_text

end module yl_problem_profile
