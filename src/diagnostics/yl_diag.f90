! yl_diag -- structured diagnostics, checked I/O helpers and exit protocol for
! the legacy YL solver (M1-02).
!
! Design (see docs/m1/M1-02-checked-io.md, .ccg/tasks/m1-02-checked-io/plan.md):
!   * No dependency on any legacy module (global_var etc.); only iso_fortran_env
!     and the generated yl_diag_registry (reader id/site/file/stage tables).
!   * Every fatal diagnostic is one stderr line beginning with "HSTAR_DIAG schema=1"
!     followed by key=value pairs; every text value (stage, file, unit, reader,
!     site, field, message) is double-quoted with '"' and '\' backslash-escaped
!     and newlines replaced by blanks. tools/yl_run.py / yl_probe.py parse these
!     lines with shlex, so quoting is transparent to them.
!   * Exit protocol: flush stderr/stdout then `call exit(code)` (Intel/GNU
!     extension; `stop` returns 0 and `error stop` prints extra text, see
!     experiment-ifx-io.md). Codes: EXIT_INPUT=2, EXIT_UNSUPPORTED=3, EXIT_INIT=4,
!     EXIT_SOLVE=5, EXIT_INTERNAL=6.
!   * I/O layer fails on first error (diag_check_open / diag_check_read).
!     Semantic checks (M1-03, M3) accumulate with diag_raise and finish with
!     diag_fail, which emits every entry and exits with the largest exit code.
!   * --check-legacy (first command-line argument) puts the program in check
!     mode: reads are counted per registry index and diag_summary_and_exit
!     writes HSTAR_CHECK lines to stdout and exits 0 before the solve starts.
module yl_diag
  use iso_fortran_env, only: error_unit, output_unit
  use yl_diag_registry
  implicit none
  private

  integer, parameter, public :: EXIT_OK = 0
  integer, parameter, public :: EXIT_INPUT = 2
  integer, parameter, public :: EXIT_UNSUPPORTED = 3
  integer, parameter, public :: EXIT_INIT = 4
  integer, parameter, public :: EXIT_SOLVE = 5
  integer, parameter, public :: EXIT_INTERNAL = 6

  ! Scratch status variables for wrapped `read(...,iostat=yl_ios,iomsg=yl_msg)` and
  ! `open(...)` statements so that legacy routines need no local declarations.
  integer, save, public :: yl_ios = 0
  character(len=512), save, public :: yl_msg = ''

  integer, parameter :: LEN_CODE = 16, LEN_MSG = 512
  integer, parameter :: LEN_SITE = 64, LEN_FIELD = 256
  ! file names reported by diag_check_open are actual paths (probn//'.ext'), not
  ! the registry's short extension: keep room for a full name.
  integer, parameter :: LEN_FILE = 256

  type, public :: diag_t
    character(len=LEN_CODE) :: code = ''
    integer :: exit_code = EXIT_INTERNAL
    character(len=YL_LEN_READER_STAGE) :: stage = ''
    character(len=LEN_FILE) :: file = ''
    character(len=YL_LEN_READER_UNIT) :: unit = ''
    character(len=YL_LEN_READER_ID) :: reader = ''
    character(len=LEN_SITE) :: site = ''
    integer :: seq = 0
    integer :: index = 0
    integer :: iostat = 0
    character(len=LEN_FIELD) :: field = ''
    character(len=LEN_MSG) :: message = ''
  end type diag_t

  type, public :: diag_list_t
    integer :: n = 0
    type(diag_t), allocatable :: items(:)
  end type diag_list_t

  type(diag_list_t), save :: pending
  logical, save :: check_mode = .false.
  integer, save :: reader_count(YL_NREADERS) = 0

  public :: diag_set_mode_from_argv, diag_check_mode
  public :: diag_check_open, diag_check_read
  public :: diag_raise, diag_fail, diag_internal, diag_emit
  public :: diag_summary_and_exit, diag_reader_count, diag_pending_count
  public :: diag_exit

contains

  ! ---------------------------------------------------------------- mode ----
  subroutine diag_set_mode_from_argv()
    character(len=64) :: arg
    integer :: l, st
    arg = ''
    call get_command_argument(1, arg, l, st)
    if (st == 0 .and. trim(arg) == '--check-legacy') check_mode = .true.
  end subroutine diag_set_mode_from_argv

  logical function diag_check_mode()
    diag_check_mode = check_mode
  end function diag_check_mode

  integer function diag_reader_count(idx)
    integer, intent(in) :: idx
    diag_reader_count = 0
    if (idx >= 1 .and. idx <= YL_NREADERS) diag_reader_count = reader_count(idx)
  end function diag_reader_count

  integer function diag_pending_count()
    diag_pending_count = pending%n
  end function diag_pending_count

  ! ---------------------------------------------------------- checked I/O ----
  subroutine diag_check_open(ios, iomsg, file, unit_name, site)
    integer, intent(in) :: ios
    character(len=*), intent(in) :: iomsg, file, unit_name, site
    type(diag_t) :: d
    if (ios == 0) return
    d%code = 'FILE_MISSING'
    d%exit_code = EXIT_INPUT
    d%stage = 'startup'
    d%file = file
    d%unit = unit_name
    d%site = site
    d%iostat = ios
    d%message = iomsg
    call diag_emit(d)
    call diag_exit(d%exit_code)
  end subroutine diag_check_open

  subroutine diag_check_read(ios, iomsg, idx, index)
    integer, intent(in) :: ios, idx, index
    character(len=*), intent(in) :: iomsg
    type(diag_t) :: d
    if (idx < 1 .or. idx > YL_NREADERS) then
      call diag_internal('diag_check_read: reader index out of range')
    end if
    if (ios == 0) then
      reader_count(idx) = reader_count(idx) + 1
      return
    end if
    if (ios < 0) then
      d%code = 'EOF'
    else
      d%code = 'PARSE'
    end if
    d%exit_code = EXIT_INPUT
    d%stage = YL_READER_STAGE(idx)
    d%file = YL_READER_FILE(idx)
    d%unit = YL_READER_UNIT(idx)
    d%reader = YL_READER_ID(idx)
    d%site = YL_READER_SITE(idx)
    d%seq = YL_READER_SEQ(idx)
    d%index = index
    d%iostat = ios
    d%field = YL_READER_FIELD(idx)
    d%message = iomsg
    call diag_emit(d)
    call diag_exit(d%exit_code)
  end subroutine diag_check_read

  ! ------------------------------------------------------- accumulation ----
  subroutine diag_raise(code, exit_code, stage, file, reader, site, seq, index, field, message, unit, iostat)
    character(len=*), intent(in) :: code, stage, file, reader, site, field, message
    integer, intent(in) :: exit_code, seq, index
    character(len=*), intent(in), optional :: unit
    integer, intent(in), optional :: iostat
    type(diag_t) :: d
    type(diag_t), allocatable :: tmp(:)
    d%code = code
    d%exit_code = exit_code
    d%stage = stage
    d%file = file
    d%reader = reader
    d%site = site
    d%seq = seq
    d%index = index
    d%field = field
    d%message = message
    if (present(unit)) d%unit = unit
    if (present(iostat)) d%iostat = iostat
    if (.not. allocated(pending%items)) allocate(pending%items(8))
    if (pending%n == size(pending%items)) then
      allocate(tmp(2 * size(pending%items)))
      tmp(1:pending%n) = pending%items(1:pending%n)
      call move_alloc(tmp, pending%items)
    end if
    pending%n = pending%n + 1
    pending%items(pending%n) = d
  end subroutine diag_raise

  subroutine diag_fail()
    integer :: i, code
    if (pending%n == 0) call diag_internal('diag_fail called with no pending diagnostics')
    code = 0
    do i = 1, pending%n
      call diag_emit(pending%items(i))
      code = max(code, pending%items(i)%exit_code)
    end do
    call diag_exit(code)
  end subroutine diag_fail

  subroutine diag_internal(message)
    character(len=*), intent(in) :: message
    type(diag_t) :: d
    d%code = 'INTERNAL'
    d%exit_code = EXIT_INTERNAL
    d%stage = 'internal'
    d%message = message
    call diag_emit(d)
    call diag_exit(EXIT_INTERNAL)
  end subroutine diag_internal

  ! --------------------------------------------------------- check mode ----
  subroutine diag_summary_and_exit()
    integer :: i, executed
    executed = count(reader_count /= 0)
    write (output_unit, '(a,i0,a,i0)') &
      'HSTAR_CHECK schema=1 mode=check-legacy status=OK errors=0 readers_executed=', executed, &
      ' readers_registered=', YL_NREADERS
    do i = 1, YL_NREADERS
      if (reader_count(i) /= 0) then
        write (output_unit, '(a,a,a,i0)') 'HSTAR_CHECK_READER id=', trim(YL_READER_ID(i)), ' n=', reader_count(i)
      end if
    end do
    call diag_exit(EXIT_OK)
  end subroutine diag_summary_and_exit

  ! -------------------------------------------------------- emit / exit ----
  subroutine diag_emit(d)
    type(diag_t), intent(in) :: d
    write (error_unit, '(a,a,a,i0,a,a,a,a,a,a,a,a,a,a,a,i0,a,i0,a,i0,a,a,a,a,a)') &
      'HSTAR_DIAG schema=1 code=', trim(d%code), &
      ' exit=', d%exit_code, &
      ' severity=fatal stage="', trim(quoted(trim(d%stage))), &
      '" file="', trim(quoted(trim(d%file))), &
      '" unit="', trim(quoted(trim(d%unit))), &
      '" reader="', trim(quoted(trim(d%reader))), &
      '" site="', trim(quoted(trim(d%site))), &
      '" seq=', d%seq, &
      ' index=', d%index, &
      ' iostat=', d%iostat, &
      ' field="', trim(quoted(trim(d%field))), &
      '" message="', trim(quoted(trim(adjustl(d%message)))), '"'
  end subroutine diag_emit

  ! Escape '"' and '\' with a backslash and replace CR/LF by blanks. The result
  ! is at most twice the input length.
  function quoted(s) result(q)
    character(len=*), intent(in) :: s
    character(len=2*len(s)) :: q
    integer :: i, j
    q = ''
    j = 0
    do i = 1, len(s)
      select case (s(i:i))
      case ('"', '\')
        j = j + 1; q(j:j) = '\'
        j = j + 1; q(j:j) = s(i:i)
      case (achar(10), achar(13))
        j = j + 1; q(j:j) = ' '
      case default
        j = j + 1; q(j:j) = s(i:i)
      end select
    end do
    q = q(1:j)
  end function quoted

  subroutine diag_exit(code)
    integer, intent(in) :: code
    flush (error_unit)
    flush (output_unit)
    call exit(code)
  end subroutine diag_exit

end module yl_diag
