! yl_authoring_report -- render an authoring finding the way the contract promises.
!
! `problem_errors_t%render` gives `<CODE> <path>: <reason>`, which is right for the places
! it already serves and is missing the one thing `docs/m5/authoring-contract.md` makes a
! judgement criterion: WHERE in case.toml. Rather than widen that renderer -- every
! existing consumer's output would change, and several suites match on it -- the authoring
! CLI renders its own line from the SAME structured finding:
!
!   case.toml:26: INVALID_INPUT material[1].density: wrong type
!                 got "heavy", expected real
!
! The location is not duplicated into the message text: it comes from the finding's
! `source`, which the validator already fills. One fact, one place.
module yl_authoring_report

  use iso_fortran_env, only: int32

  use yl_problem_optional, only: opt_value_or, opt_is_set, opt_get, opt_text
  use yl_problem_errors, only: problem_errors_t, problem_error_t

  implicit none
  private

  public :: authoring_render, authoring_render_unreadable

contains

  !> Finding `i` as one or two lines of operator-facing text.
  function authoring_render(errors, i) result(text)
    type(problem_errors_t), intent(in) :: errors
    integer, intent(in) :: i
    character(len=:), allocatable :: text
    type(problem_error_t) :: e
    logical :: found
    character(len=:), allocatable :: where_, got, want

    call errors%get(i, e, found)
    if (.not. found) then
      text = ''
      return
    end if

    where_ = text_or(e%source%file, 'case.toml')
    if (opt_is_set(e%source%line)) then
      where_ = where_//':'//itoa(opt_value_or(e%source%line, 0_int32))
    end if

    text = where_//': '//text_or(e%code, '?')//' '//                                         &
           text_or(e%object_path, '')//': '//text_or(e%message, '')

    got = text_or(e%actual, '')
    want = text_or(e%expected, '')
    if (len(got) > 0 .or. len(want) > 0) then
      text = text//new_line('a')//'    '
      if (len(got) > 0) text = text//'got '//got
      if (len(got) > 0 .and. len(want) > 0) text = text//', '
      if (len(want) > 0) text = text//'expected '//want
    end if
  end function authoring_render

  !> The one-line verdict for a file the reader could not read at all -- missing, or not
  !> the contract's TOML subset. Same shape as `authoring_render`, so an operator sees one
  !> form of message whichever half of the path rejected the file. `line == 0` is the
  !> reader's "no line to point at" (the open failed), and printing `:0:` would be a
  !> location that does not exist.
  pure function authoring_render_unreadable(file, line, message) result(text)
    character(len=*), intent(in) :: file, message
    integer(int32), intent(in) :: line
    character(len=:), allocatable :: text
    text = trim(file)
    if (line > 0_int32) text = text//':'//itoa(line)
    text = text//': INVALID_INPUT: '//trim(message)
  end function authoring_render_unreadable

  !> An opt_text's value, or `fallback` when unset. opt_value_or needs a same-kind
  !> default and this reads better at four call sites than four inline opt_get pairs.
  pure function text_or(x, fallback) result(v)
    type(opt_text), intent(in) :: x
    character(len=*), intent(in) :: fallback
    character(len=:), allocatable :: v
    logical :: found
    call opt_get(x, v, found)
    if (.not. found) v = fallback
    v = trim(v)
  end function text_or

  pure function itoa(v) result(out)
    integer(int32), intent(in) :: v
    character(len=12) :: buf
    character(len=:), allocatable :: out
    write (buf, '(i0)') v
    out = trim(buf)
  end function itoa

end module yl_authoring_report
