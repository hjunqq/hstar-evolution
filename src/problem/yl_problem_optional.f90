! yl_problem_optional -- explicit-absence scalar wrappers for the M3 ProblemState.
!
! Design (see .ccg/tasks/m3-01-problemstate-types/plan.md, analysis-codex.md S1,
! docs/decisions/0002-transactional-problem-state.md):
!   * ADR-0002 requires that "unset", an explicit numeric zero and an empty
!     collection are three different things, and forbids overloading -1 / -huge
!     as a second meaning of a value. This module supplies the first two states
!     for scalars; collections keep using allocation status (unallocated =
!     unset, allocated size 0 = explicitly empty), which needs no wrapper.
!   * One wrapper per authoring scalar kind: opt_int (int32), opt_real (real64),
!     opt_text (deferred-length character) and opt_logical. Every component is
!     PRIVATE and carries a default initializer, so a default-initialised object
!     is unambiguously unset and the presence flag can never drift out of step
!     with the payload the way an adjacent has_* logical can.
!   * The default initializers are also what makes the wrappers safe under the
!     strict build profile (-init=snan,arrays -fpe0): explicit default
!     initialization wins over -init=snan, so an unset opt_real holds 0.0_real64
!     and never a signaling NaN. Absence is represented by the flag, never by a
!     poison value.
!   * Access is through generics only: opt_set / opt_get / opt_is_set /
!     opt_clear / opt_value_or / opt_equal. There is no accessor that returns a
!     payload without either a found flag or a caller-supplied default.
!
! Unchecked reads
!   Reading the payload of an unset optional is a programming error. It is made
!   visible three ways, in decreasing strength:
!     1. The components are private, so the only way to reach a payload is
!        opt_get or opt_value_or. Direct x%value is a compile-time error outside
!        this module.
!     2. In opt_get(x, value, found) the found argument is MANDATORY, not
!        optional. A caller physically cannot write the read without declaring
!        somewhere to receive the answer, and ifx -warn all reports the variable
!        if it is then never used.
!     3. If found is nevertheless ignored, the returned value is still fully
!        defined -- 0, 0.0, '' or .false. -- never undefined memory and never a
!        NaN that would trap under -fpe0. The failure mode is a deterministic
!        neutral value, not a crash whose cause depends on the build profile.
!   opt_value_or is the only defaulting accessor and it requires the caller to
!   name the default at the call site, which keeps "I accept a substitute" and
!   "I forgot to check" textually distinct.
!
! Comparison
!   opt_equal treats two unset optionals as equal and a set/unset pair as
!   different, whatever the payloads are. For opt_real the payloads are compared
!   as IEEE bit patterns rather than with ==, so that the comparison is total
!   (two identical NaNs compare equal, +0.0 and -0.0 do not) and so that it can
!   never raise an invalid-operand trap under -fpe0. For opt_text the lengths
!   are compared before the contents, so that 'a' and 'a ' are different values
!   rather than equal under Fortran's blank-padding rule.
module yl_problem_optional

  use iso_fortran_env, only: int32, int64, real64

  implicit none
  private

  public :: opt_int, opt_real, opt_text, opt_logical
  public :: opt_set, opt_get, opt_is_set, opt_clear, opt_value_or, opt_equal

  type :: opt_int
    private
    logical :: has = .false.
    integer(int32) :: value = 0_int32
  end type opt_int

  type :: opt_real
    private
    logical :: has = .false.
    real(real64) :: value = 0.0_real64
  end type opt_real

  type :: opt_text
    private
    logical :: has = .false.
    character(len=:), allocatable :: value
  end type opt_text

  type :: opt_logical
    private
    logical :: has = .false.
    logical :: value = .false.
  end type opt_logical

  interface opt_set
    module procedure int_set, real_set, text_set, logical_set
  end interface opt_set

  interface opt_get
    module procedure int_get, real_get, text_get, logical_get
  end interface opt_get

  interface opt_is_set
    module procedure int_is_set, real_is_set, text_is_set, logical_is_set
  end interface opt_is_set

  interface opt_clear
    module procedure int_clear, real_clear, text_clear, logical_clear
  end interface opt_clear

  interface opt_value_or
    module procedure int_value_or, real_value_or, text_value_or, logical_value_or
  end interface opt_value_or

  interface opt_equal
    module procedure int_equal, real_equal, text_equal, logical_equal
  end interface opt_equal

contains

  ! --- opt_int ----------------------------------------------------------------

  pure subroutine int_set(x, value)
    type(opt_int), intent(inout) :: x
    integer(int32), intent(in) :: value
    x%value = value
    x%has = .true.
  end subroutine int_set

  pure subroutine int_get(x, value, found)
    type(opt_int), intent(in) :: x
    integer(int32), intent(out) :: value
    logical, intent(out) :: found
    found = x%has
    if (x%has) then
      value = x%value
    else
      value = 0_int32
    end if
  end subroutine int_get

  pure logical function int_is_set(x) result(is_set)
    type(opt_int), intent(in) :: x
    is_set = x%has
  end function int_is_set

  pure subroutine int_clear(x)
    type(opt_int), intent(inout) :: x
    x%has = .false.
    x%value = 0_int32
  end subroutine int_clear

  pure integer(int32) function int_value_or(x, default) result(value)
    type(opt_int), intent(in) :: x
    integer(int32), intent(in) :: default
    if (x%has) then
      value = x%value
    else
      value = default
    end if
  end function int_value_or

  pure logical function int_equal(a, b) result(equal)
    type(opt_int), intent(in) :: a, b
    equal = (a%has .eqv. b%has)
    if (equal .and. a%has) equal = (a%value == b%value)
  end function int_equal

  ! --- opt_real ---------------------------------------------------------------

  pure subroutine real_set(x, value)
    type(opt_real), intent(inout) :: x
    real(real64), intent(in) :: value
    x%value = value
    x%has = .true.
  end subroutine real_set

  pure subroutine real_get(x, value, found)
    type(opt_real), intent(in) :: x
    real(real64), intent(out) :: value
    logical, intent(out) :: found
    found = x%has
    if (x%has) then
      value = x%value
    else
      value = 0.0_real64
    end if
  end subroutine real_get

  pure logical function real_is_set(x) result(is_set)
    type(opt_real), intent(in) :: x
    is_set = x%has
  end function real_is_set

  pure subroutine real_clear(x)
    type(opt_real), intent(inout) :: x
    x%has = .false.
    x%value = 0.0_real64
  end subroutine real_clear

  pure real(real64) function real_value_or(x, default) result(value)
    type(opt_real), intent(in) :: x
    real(real64), intent(in) :: default
    if (x%has) then
      value = x%value
    else
      value = default
    end if
  end function real_value_or

  ! Total, trap-free payload identity: compare the IEEE binary64 bit patterns
  ! instead of the values (see the module header).
  pure logical function real_equal(a, b) result(equal)
    type(opt_real), intent(in) :: a, b
    equal = (a%has .eqv. b%has)
    if (equal .and. a%has) equal = (transfer(a%value, 0_int64) == transfer(b%value, 0_int64))
  end function real_equal

  ! --- opt_text ---------------------------------------------------------------

  pure subroutine text_set(x, value)
    type(opt_text), intent(inout) :: x
    character(len=*), intent(in) :: value
    x%value = value
    x%has = .true.
  end subroutine text_set

  pure subroutine text_get(x, value, found)
    type(opt_text), intent(in) :: x
    character(len=:), allocatable, intent(out) :: value
    logical, intent(out) :: found
    found = x%has
    if (x%has) then
      ! A set opt_text always has an allocated payload; text_set assigns it.
      value = x%value
    else
      value = ''
    end if
  end subroutine text_get

  pure logical function text_is_set(x) result(is_set)
    type(opt_text), intent(in) :: x
    is_set = x%has
  end function text_is_set

  pure subroutine text_clear(x)
    type(opt_text), intent(inout) :: x
    x%has = .false.
    if (allocated(x%value)) deallocate (x%value)
  end subroutine text_clear

  pure function text_value_or(x, default) result(value)
    type(opt_text), intent(in) :: x
    character(len=*), intent(in) :: default
    character(len=:), allocatable :: value
    if (x%has) then
      value = x%value
    else
      value = default
    end if
  end function text_value_or

  pure logical function text_equal(a, b) result(equal)
    type(opt_text), intent(in) :: a, b
    equal = (a%has .eqv. b%has)
    if (equal .and. a%has) then
      equal = (len(a%value) == len(b%value))
      if (equal) equal = (a%value == b%value)
    end if
  end function text_equal

  ! --- opt_logical ------------------------------------------------------------

  pure subroutine logical_set(x, value)
    type(opt_logical), intent(inout) :: x
    logical, intent(in) :: value
    x%value = value
    x%has = .true.
  end subroutine logical_set

  pure subroutine logical_get(x, value, found)
    type(opt_logical), intent(in) :: x
    logical, intent(out) :: value
    logical, intent(out) :: found
    found = x%has
    if (x%has) then
      value = x%value
    else
      value = .false.
    end if
  end subroutine logical_get

  pure logical function logical_is_set(x) result(is_set)
    type(opt_logical), intent(in) :: x
    is_set = x%has
  end function logical_is_set

  pure subroutine logical_clear(x)
    type(opt_logical), intent(inout) :: x
    x%has = .false.
    x%value = .false.
  end subroutine logical_clear

  pure logical function logical_value_or(x, default) result(value)
    type(opt_logical), intent(in) :: x
    logical, intent(in) :: default
    if (x%has) then
      value = x%value
    else
      value = default
    end if
  end function logical_value_or

  pure logical function logical_equal(a, b) result(equal)
    type(opt_logical), intent(in) :: a, b
    equal = (a%has .eqv. b%has)
    if (equal .and. a%has) equal = (a%value .eqv. b%value)
  end function logical_equal

end module yl_problem_optional
