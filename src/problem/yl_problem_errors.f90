! yl_problem_errors -- pure in-memory error accumulator for the M3 problem pipeline.
!
! Scope (see .ccg/tasks/m3-02-normalize-validate-finalize/plan.md delivery 1,
! analysis.md "error accumulator" ruling, analysis-codex.md S1)
!   A findings container and a renderer. No I/O, no global state, no process exit.
!   The pipeline stages (M3-02 Layer 2) accumulate findings here and the CALLER
!   decides how to print them and which exit status to take.
!
! Why this is not yl_diag
!   src/diagnostics/yl_diag.f90 is the reader-side diagnostic channel. It keeps a
!   module-level `pending` list, a per-reader accumulation cap and a set of
!   procedures (diag_raise / diag_flush_stage / diag_exit) that terminate the
!   process. That is correct for a one-shot legacy reader and wrong here: the
!   M3-02 acceptance criterion T01 requires that a draft which fails validation
!   leaves no residue and that a legal draft submitted IMMEDIATELY AFTERWARDS, in
!   the SAME process, succeeds. A global pending list and a process exit make that
!   untestable. So this module calls nothing in yl_diag; it borrows only the code
!   vocabulary and the exit classification, which are duplicated as parameters
!   below in the same way yl_diag duplicates the legacy `ink` kind privately.
!   The three exit classes used here keep the numeric values of yl_diag's
!   EXIT_INPUT, EXIT_UNSUPPORTED and EXIT_INTERNAL, so a caller can pass
!   `exit_code()` straight to `stop`.
!
! Absence discipline (ADR-0002)
!   Every text member and every source-location member is an opt_* wrapper from
!   yl_problem_optional, so "this finding carries no column number" and "this
!   finding is at column 0" stay distinct, and a renderer can tell whether to emit
!   a component at all. `exit_class` is the one plain integer: every finding has
!   one, and it is defaulted to the input class rather than left absent.
!
! Message shape
!   render() produces the fixed form used by the M2 comparator style
!   (analysis-claude.md S2):
!
!       <CODE> <object path>[<index>].<field>: <reason>
!
!   Components that are unset are omitted together with their separator, so a
!   finding that names no field renders as `<CODE> <object path>: <reason>` and a
!   finding that names no object at all renders as `<CODE>: <reason>`. `reason` is
!   the message when one was supplied, otherwise it is synthesised from the
!   expected/actual pair, so that a caller can never produce a finding that
!   renders as a bare code with no explanation.
!
! Ordering and capacity
!   Findings are kept in insertion order and none is ever dropped: unlike the
!   reader channel there is no per-source cap, because a rule sweep is expected to
!   report every independent defect in one pass. Storage grows geometrically and
!   the growth copies the live prefix, so no entry is lost across a reallocation.
module yl_problem_errors

  use iso_fortran_env, only: int32
  use yl_problem_optional, only: opt_int, opt_text, opt_set, opt_is_set, opt_value_or

  implicit none
  private

  public :: source_location_t, problem_error_t, problem_errors_t
  public :: make_source_location, make_problem_error, render_error
  public :: exit_class_for_code, code_is_model_finding

  ! --- codes ------------------------------------------------------------------
  ! Two disjoint sets, and the split is deliberate.
  !
  ! MODEL codes are findings ABOUT THE USER'S MODEL. MISSING_FIELD / DANGLING_REF
  ! / DUPLICATE_REF / EMPTY_COLLECTION / COUNT_MISMATCH / INVALID_INPUT are input
  ! defects; UNSUPPORTED is the capability gate's verdict on a well-formed model
  ! this build cannot run. Every one of them tells the author something they can
  ! act on by editing their input.
  !
  ! INTERNAL is NOT such a finding. It reports that the pipeline broke one of its
  ! own invariants, which says nothing about the input and gives the author
  ! nothing to fix. It lives here only so that the code vocabulary and the
  ! code-to-exit mapping exist in exactly one place, which is what stopped the
  ! pipeline from declaring its own copies. It is kept OUT of the model set by
  ! code_is_model_finding, so that any caller presenting a user-facing list can
  ! filter it rather than having to know the code names -- see that function.

  character(len=*), parameter, public :: PE_MISSING_FIELD = 'MISSING_FIELD'
  character(len=*), parameter, public :: PE_DANGLING_REF = 'DANGLING_REF'
  character(len=*), parameter, public :: PE_DUPLICATE_REF = 'DUPLICATE_REF'
  character(len=*), parameter, public :: PE_EMPTY_COLLECTION = 'EMPTY_COLLECTION'
  character(len=*), parameter, public :: PE_COUNT_MISMATCH = 'COUNT_MISMATCH'
  character(len=*), parameter, public :: PE_INVALID_INPUT = 'INVALID_INPUT'
  character(len=*), parameter, public :: PE_UNSUPPORTED = 'UNSUPPORTED'

  ! Not a model finding. See the note above and code_is_model_finding.
  character(len=*), parameter, public :: PE_INTERNAL = 'INTERNAL'

  ! --- exit classes -----------------------------------------------------------
  ! Numerically equal to yl_diag's EXIT_INPUT / EXIT_UNSUPPORTED / EXIT_INTERNAL.
  ! Duplicated, not imported, so that this module has no dependency on the
  ! diagnostics channel; the numbers are the repository exit protocol and a
  ! reader should not have to learn a second scheme.

  integer(int32), parameter, public :: PE_EXIT_INPUT = 2_int32
  integer(int32), parameter, public :: PE_EXIT_UNSUPPORTED = 3_int32
  integer(int32), parameter, public :: PE_EXIT_INTERNAL = 6_int32

  ! --- stage names ------------------------------------------------------------
  ! The four pipeline stages, so that a stage string is never spelled by hand at a
  ! call site and a typo cannot silently create a fifth stage.

  character(len=*), parameter, public :: PE_STAGE_NORMALIZE = 'normalize'
  character(len=*), parameter, public :: PE_STAGE_VALIDATE = 'validate'
  character(len=*), parameter, public :: PE_STAGE_CAPABILITY = 'capability'
  character(len=*), parameter, public :: PE_STAGE_FINALIZE = 'finalize'

  ! The legacy adapter's stage, which runs BEFORE all four of the above: it is what
  ! produces the draft they then judge. Named here rather than in the adapter for
  ! the reason the four above are named here at all -- eight adapter modules each
  ! carried their own `character(len=*), parameter :: STAGE_ADAPT = 'adapt'`
  ! stand-in, which is eight places for the spelling to drift. Added by M4-01 L2-b,
  ! which docs/m4/adapter-contract.md SS4 makes responsible for it.
  character(len=*), parameter, public :: PE_STAGE_ADAPT = 'adapt'

  integer, parameter :: INITIAL_CAPACITY = 8

  ! --- source location --------------------------------------------------------
  ! Where the offending value entered the process. Every member is optional: a
  ! finding raised on a draft built in memory by a self-test has none of them, a
  ! finding traced back through a legacy reader has all five.

  type :: source_location_t
    type(opt_text) :: file
    type(opt_text) :: reader
    type(opt_int) :: line
    type(opt_int) :: column
    type(opt_int) :: record
  end type source_location_t

  ! --- one finding ------------------------------------------------------------
  ! `object_path` and `index` and `field` locate the defect; `code` classifies it;
  ! `rule_id` names the rule that fired (N1, V7, G3, ...) so that the negative
  ! fixture matrix can assert coverage rule by rule; `actual` and `expected` carry
  ! the compared values as text so that the renderer needs no type knowledge.

  type :: problem_error_t
    type(opt_text) :: code
    type(opt_text) :: stage
    type(opt_text) :: rule_id
    type(opt_text) :: object_path
    type(opt_int) :: index
    type(opt_text) :: field
    type(opt_text) :: message
    type(opt_text) :: actual
    type(opt_text) :: expected
    integer(int32) :: exit_class = PE_EXIT_INPUT
    type(source_location_t) :: source
  end type problem_error_t

  ! --- the accumulator --------------------------------------------------------
  ! Storage is PRIVATE: `used` and `entries` can only ever move together, so the
  ! count can never disagree with the contents. Reading is through get(), which
  ! returns a copy and a found flag, in the same spirit as opt_get.

  type :: problem_errors_t
    private
    type(problem_error_t), allocatable :: entries(:)
    integer :: used = 0
  contains
    procedure :: add => errors_add
    procedure :: any => errors_any
    procedure :: count => errors_count
    procedure :: get => errors_get
    procedure :: clear => errors_clear
    procedure :: render => errors_render
    procedure :: exit_code => errors_exit_code
    procedure :: is_model_finding => errors_is_model_finding
  end type problem_errors_t

contains

  ! --- construction -----------------------------------------------------------

  ! Build a source location from whichever components the caller knows. Absent
  ! arguments stay unset; they are never defaulted to 0 or to an empty string,
  ! because "line 0" and "no line recorded" are different statements.
  pure function make_source_location(file, reader, line, column, record) result(loc)
    character(len=*), intent(in), optional :: file
    character(len=*), intent(in), optional :: reader
    integer(int32), intent(in), optional :: line
    integer(int32), intent(in), optional :: column
    integer(int32), intent(in), optional :: record
    type(source_location_t) :: loc
    if (present(file)) call opt_set(loc%file, file)
    if (present(reader)) call opt_set(loc%reader, reader)
    if (present(line)) call opt_set(loc%line, line)
    if (present(column)) call opt_set(loc%column, column)
    if (present(record)) call opt_set(loc%record, record)
  end function make_source_location

  ! Build one finding. `code` is mandatory; everything else is optional so that a
  ! rule supplies exactly what it knows. When `exit_class` is omitted it is
  ! derived from the code by exit_class_for_code, which is the only place the
  ! code-to-exit mapping lives.
  pure function make_problem_error(code, stage, rule_id, object_path, index, field, message,   &
                                   actual, expected, exit_class, source) result(error)
    character(len=*), intent(in) :: code
    character(len=*), intent(in), optional :: stage
    character(len=*), intent(in), optional :: rule_id
    character(len=*), intent(in), optional :: object_path
    integer(int32), intent(in), optional :: index
    character(len=*), intent(in), optional :: field
    character(len=*), intent(in), optional :: message
    character(len=*), intent(in), optional :: actual
    character(len=*), intent(in), optional :: expected
    integer(int32), intent(in), optional :: exit_class
    type(source_location_t), intent(in), optional :: source
    type(problem_error_t) :: error

    call opt_set(error%code, code)
    if (present(stage)) call opt_set(error%stage, stage)
    if (present(rule_id)) call opt_set(error%rule_id, rule_id)
    if (present(object_path)) call opt_set(error%object_path, object_path)
    if (present(index)) call opt_set(error%index, index)
    if (present(field)) call opt_set(error%field, field)
    if (present(message)) call opt_set(error%message, message)
    if (present(actual)) call opt_set(error%actual, actual)
    if (present(expected)) call opt_set(error%expected, expected)
    if (present(source)) error%source = source
    if (present(exit_class)) then
      error%exit_class = exit_class
    else
      error%exit_class = exit_class_for_code(code)
    end if
  end function make_problem_error

  ! The repository exit protocol: an input defect is class 2, a well-formed model
  ! outside this build's capability is class 3, a broken pipeline invariant is
  ! class 6. An unrecognised code is treated as an input defect rather than
  ! silently promoted, because a promotion would let a typo change the process
  ! exit status.
  !
  ! PE_INTERNAL must be named here and not only in the parameter list above. The
  ! default branch answers 2, so a caller that constructs an internal fault
  ! without passing an explicit exit_class would otherwise be handed the input
  ! class -- a wrong answer that looks right, and worse than no constant at all.
  ! The constant and its mapping therefore always travel together.
  pure integer(int32) function exit_class_for_code(code) result(exit_class)
    character(len=*), intent(in) :: code
    select case (code)
    case (PE_UNSUPPORTED)
      exit_class = PE_EXIT_UNSUPPORTED
    case (PE_INTERNAL)
      exit_class = PE_EXIT_INTERNAL
    case default
      exit_class = PE_EXIT_INPUT
    end select
  end function exit_class_for_code

  ! Is this code a finding about the user's model? True for the seven model
  ! codes, false for PE_INTERNAL and for anything unrecognised.
  !
  ! The default is false on purpose, and it is the opposite of the default in
  ! exit_class_for_code. The two functions are protecting against different
  ! mistakes. An unknown code must still produce SOME exit status, and the safe
  ! guess there is the ordinary input class. But an unknown code must never be
  ! paraded to the author as advice about their input, so the safe guess here is
  ! to withhold it. A caller rendering a user-facing list filters on this; a
  ! caller computing an exit status uses exit_code(), which counts every finding.
  pure logical function code_is_model_finding(code) result(is_model)
    character(len=*), intent(in) :: code
    select case (code)
    case (PE_MISSING_FIELD, PE_DANGLING_REF, PE_DUPLICATE_REF, PE_EMPTY_COLLECTION,             &
          PE_COUNT_MISMATCH, PE_INVALID_INPUT, PE_UNSUPPORTED)
      is_model = .true.
    case default
      is_model = .false.
    end select
  end function code_is_model_finding

  ! Does finding `i` describe the user's model? Convenience over
  ! code_is_model_finding so a caller iterating the accumulator need not first
  ! copy the entry out to inspect its code. An out-of-range index answers false.
  pure logical function errors_is_model_finding(self, i) result(is_model)
    class(problem_errors_t), intent(in) :: self
    integer, intent(in) :: i
    is_model = .false.
    if (i < 1) return
    if (i > self%used) return
    is_model = code_is_model_finding(opt_value_or(self%entries(i)%code, ''))
  end function errors_is_model_finding

  ! --- accumulator methods ----------------------------------------------------

  ! Append one finding. Capacity doubles from INITIAL_CAPACITY and the live prefix
  ! is copied element by element into the new storage before the swap, so growth
  ! never loses or reorders an entry.
  pure subroutine errors_add(self, error)
    class(problem_errors_t), intent(inout) :: self
    type(problem_error_t), intent(in) :: error
    type(problem_error_t), allocatable :: bigger(:)
    integer :: capacity, wanted, i

    capacity = 0
    if (allocated(self%entries)) capacity = size(self%entries)
    if (self%used >= capacity) then
      wanted = INITIAL_CAPACITY
      if (2 * capacity > wanted) wanted = 2 * capacity
      allocate (bigger(wanted))
      do i = 1, self%used
        bigger(i) = self%entries(i)
      end do
      call move_alloc(bigger, self%entries)
    end if
    self%used = self%used + 1
    self%entries(self%used) = error
  end subroutine errors_add

  pure logical function errors_any(self) result(present_any)
    class(problem_errors_t), intent(in) :: self
    present_any = (self%used > 0)
  end function errors_any

  pure integer function errors_count(self) result(n)
    class(problem_errors_t), intent(in) :: self
    n = self%used
  end function errors_count

  ! Copy out finding `i`. `found` is mandatory for the same reason opt_get's is:
  ! a caller cannot read an entry without declaring somewhere to learn that the
  ! index was out of range. When not found, `error` is returned default-
  ! initialised -- fully defined, never stale storage.
  pure subroutine errors_get(self, i, error, found)
    class(problem_errors_t), intent(in) :: self
    integer, intent(in) :: i
    type(problem_error_t), intent(out) :: error
    logical, intent(out) :: found
    found = .false.
    if (i < 1) return
    if (i > self%used) return
    error = self%entries(i)
    found = .true.
  end subroutine errors_get

  ! Drop every finding and release the storage, so that a reused accumulator
  ! starts from exactly the state of a freshly declared one.
  pure subroutine errors_clear(self)
    class(problem_errors_t), intent(inout) :: self
    self%used = 0
    if (allocated(self%entries)) deallocate (self%entries)
  end subroutine errors_clear

  ! Render finding `i` in the fixed message shape. An out-of-range index renders
  ! as the empty string rather than aborting: rendering is a reporting path and
  ! must not be able to take the process down.
  pure function errors_render(self, i) result(text)
    class(problem_errors_t), intent(in) :: self
    integer, intent(in) :: i
    character(len=:), allocatable :: text
    if (i < 1 .or. i > self%used) then
      text = ''
    else
      text = render_error(self%entries(i))
    end if
  end function errors_render

  ! The worst exit class among the accumulated findings, or 0 when there are
  ! none. "Worst" is the numerically largest class, matching the repository's
  ! ordering (input 2 < unsupported 3 < ... < internal 6), so a run that has both
  ! an input defect and an unsupported feature exits 3.
  pure integer(int32) function errors_exit_code(self) result(code)
    class(problem_errors_t), intent(in) :: self
    integer :: i
    code = 0_int32
    do i = 1, self%used
      if (self%entries(i)%exit_class > code) code = self%entries(i)%exit_class
    end do
  end function errors_exit_code

  ! --- rendering --------------------------------------------------------------

  ! `<CODE> <object path>[<index>].<field>: <reason>`, omitting each absent
  ! component together with the separator that would have introduced it.
  pure function render_error(error) result(text)
    type(problem_error_t), intent(in) :: error
    character(len=:), allocatable :: text
    character(len=:), allocatable :: locus, reason
    logical :: has_locus

    text = opt_value_or(error%code, '?')

    locus = opt_value_or(error%object_path, '')
    has_locus = (len(locus) > 0)
    if (opt_is_set(error%index)) then
      locus = locus//'['//itoa(opt_value_or(error%index, 0_int32))//']'
      has_locus = .true.
    end if
    if (opt_is_set(error%field)) then
      if (has_locus) then
        locus = locus//'.'//opt_value_or(error%field, '')
      else
        locus = opt_value_or(error%field, '')
      end if
      has_locus = .true.
    end if
    if (has_locus) text = text//' '//locus

    reason = reason_of(error)
    if (len(reason) > 0) text = text//': '//reason
  end function render_error

  ! The explanatory half of the message. An explicit message wins; otherwise the
  ! expected/actual pair is phrased, so a rule that supplies only the compared
  ! values still renders something a reader can act on.
  pure function reason_of(error) result(reason)
    type(problem_error_t), intent(in) :: error
    character(len=:), allocatable :: reason
    logical :: has_expected, has_actual

    if (opt_is_set(error%message)) then
      reason = opt_value_or(error%message, '')
      return
    end if

    has_expected = opt_is_set(error%expected)
    has_actual = opt_is_set(error%actual)
    if (has_expected .and. has_actual) then
      reason = 'expected '//opt_value_or(error%expected, '')//', got '//opt_value_or(error%actual, '')
    else if (has_expected) then
      reason = 'expected '//opt_value_or(error%expected, '')
    else if (has_actual) then
      reason = 'got '//opt_value_or(error%actual, '')
    else
      reason = ''
    end if
  end function reason_of

  ! Minimal integer-to-text helper. Private and local so that this module does not
  ! depend on yl_diag's diag_itoa (see the module header).
  pure function itoa(value) result(text)
    integer(int32), intent(in) :: value
    character(len=:), allocatable :: text
    character(len=12) :: buffer
    write (buffer, '(i0)') value
    text = trim(buffer)
  end function itoa

end module yl_problem_errors
