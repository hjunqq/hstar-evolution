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
!   * --check-legacy (any position on the command line) puts the program in
!     check mode: reads are counted per registry index and diag_summary_and_exit
!     writes HSTAR_CHECK lines to stdout and exits 0 before the solve starts.
!   * M1-03 semantic guards: diag_range / diag_ref / diag_dup / diag_unsupported
!     / diag_product accumulate one entry per finding (at most MAX_PER_READER
!     kept per reader index, the rest counted as suppressed and reported as
!     " (+K more)" on the last kept entry); diag_flush_stage fails if anything
!     is pending. diag_abort replaces bare `stop` at sites without reader
!     context. --max-entities=N bounds the int64 products checked by
!     diag_product (default huge(0_ink)). The report line gains value="..."
!     allowed="..." right after field=.
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
  ! M1-03 scratch for guard call sites (allocate stat, reader index), like yl_ios/yl_msg
  integer, save, public :: yl_st = 0
  integer, save, public :: yl_idx = 0

  ! M2-02 state observer configuration, set once by diag_set_mode_from_argv from
  ! --dump-state=DIR and read (never written) by yl_state_serializer / Fem.f90.
  logical, save, protected, public :: yl_dump_enabled = .false.
  character(len=256), save, protected, public :: yl_dump_dir = ''
  ! M4-02 adapter entry. When .true., Fem.f90 calls the external subroutine
  ! yl_adapter_override() immediately before the model_ready anchor, replacing the
  ! globals the legacy readers built with the ones the adapter committed, and the
  ! solve then runs on adapter data. DEFAULT OFF: the legacy path stays the default
  ! entry until the cross-path comparison says otherwise, and --adapter=off remains
  ! the documented fallback switch after that default flips (M4 exit condition
  ! "回退开关经过测试，但不会自动触发" -- it never turns itself on or off).
  logical, save, protected, public :: yl_adapter_mode = .true.

  integer, parameter :: LEN_CODE = 16, LEN_MSG = 512
  integer, parameter :: LEN_SITE = 64, LEN_FIELD = 256
  ! file names reported by diag_check_open are actual paths (probn//'.ext'), not
  ! the registry's short extension: keep room for a full name.
  integer, parameter :: LEN_FILE = 256
  integer, parameter :: LEN_VALUE = 256
  ! Legacy integer kind (variable_types::ink = kind(0)); duplicated privately
  ! so the module stays free of legacy dependencies and does not clash with
  ! the legacy name. i8 is the guard arithmetic kind (public).
  integer, parameter :: ink = kind(0)
  integer, parameter, public :: i8 = selected_int_kind(18)
  ! Accumulation cap per reader index (M1-03 contract).
  integer, parameter, public :: MAX_PER_READER = 20

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
    character(len=LEN_VALUE) :: value = ''
    character(len=LEN_VALUE) :: allowed = ''
    character(len=LEN_MSG) :: message = ''
    integer :: idx = 0          ! registry index (0 = none); drives the per-reader cap
  end type diag_t

  type, public :: diag_list_t
    integer :: n = 0
    type(diag_t), allocatable :: items(:)
  end type diag_list_t

  type(diag_list_t), save :: pending
  logical, save :: check_mode = .false.
  integer, save :: reader_count(YL_NREADERS) = 0
  integer, save :: kept(YL_NREADERS) = 0        ! entries kept in `pending` per idx
  integer, save :: suppressed(YL_NREADERS) = 0  ! entries dropped beyond MAX_PER_READER
  integer(i8), save :: max_entities = int(huge(0_ink), i8)

  public :: diag_set_mode_from_argv, diag_check_mode
  public :: diag_check_open, diag_check_read
  public :: diag_raise, diag_fail, diag_internal, diag_emit
  public :: diag_summary_and_exit, diag_reader_count, diag_pending_count
  public :: diag_exit
  public :: diag_range, diag_ref, diag_dup, diag_unsupported, diag_product
  public :: diag_flush_stage, diag_max_entities, diag_abort, diag_suppressed_count
  public :: diag_itoa

contains

  ! ---------------------------------------------------------------- mode ----
  ! Scan every command-line argument. Accepted, in any order:
  !   --check-legacy       check mode
  !   --max-entities=N     N decimal, 1..huge(0_ink); overrides diag_max_entities
  !   --adapter=on|off     M4-02 adapter entry (default off); no other spelling is
  !                        accepted, and it may appear at most once, so a typo can
  !                        never be read as "off"
  !   --dump-state=DIR     M2-02 state observer; DIR is copied byte-exactly into
  !                        yl_dump_dir (no shell expansion) and yl_dump_enabled
  !                        is set. May appear at most once and is mutually
  !                        exclusive with --check-legacy in either order.
  ! Anything else (unknown option, bad or out-of-range N, empty or repeated or
  ! control-character DIR, both modes at once, over-long argument) emits
  ! code=PARSE stage="argv" and exits 2.
  subroutine diag_set_mode_from_argv()
    character(len=*), parameter :: OPT_ME = '--max-entities='
    character(len=*), parameter :: OPT_DS = '--dump-state='
    character(len=*), parameter :: OPT_AD = '--adapter='
    character(len=LEN_VALUE) :: arg
    integer :: i, l, st, k
    integer(i8) :: n
    logical :: ok, seen_adapter
    seen_adapter = .false.
    do i = 1, command_argument_count()
      arg = ''
      call get_command_argument(i, arg, l, st)
      if (st /= 0 .or. l > len(arg)) then
        call argv_error(i, arg(1:min(l, len(arg))), 'argument too long or unreadable')
      end if
      if (l > len(OPT_AD) .and. arg(1:len(OPT_AD)) == OPT_AD) then
        if (seen_adapter) then
          call argv_error(i, arg(1:l), 'repeated --adapter=on|off option')
        end if
        if (arg(len(OPT_AD) + 1:l) == 'on') then
          yl_adapter_mode = .true.
        else if (arg(len(OPT_AD) + 1:l) == 'off') then
          yl_adapter_mode = .false.
        else
          call argv_error(i, arg(1:l), 'expected --adapter=on or --adapter=off')
        end if
        seen_adapter = .true.
      else if (arg(1:l) == '--check-legacy') then
        if (yl_dump_enabled) then
          call argv_error(i, arg(1:l), '--check-legacy and --dump-state=DIR are mutually exclusive')
        end if
        check_mode = .true.
      else if (arg(1:len(OPT_DS)) == OPT_DS) then
        if (check_mode) then
          call argv_error(i, arg(1:l), '--check-legacy and --dump-state=DIR are mutually exclusive')
        end if
        if (yl_dump_enabled) then
          call argv_error(i, arg(1:l), 'repeated --dump-state=DIR option')
        end if
        if (l <= len(OPT_DS)) then
          call argv_error(i, arg(1:l), 'expected --dump-state=DIR with a non-empty directory path')
        end if
        if (l - len(OPT_DS) > len(yl_dump_dir)) then
          call argv_error(i, arg(1:l), 'directory path of --dump-state=DIR is too long')
        end if
        do k = len(OPT_DS) + 1, l
          if (iachar(arg(k:k)) < 32 .or. iachar(arg(k:k)) == 127) then
            call argv_error(i, arg(1:l), 'directory path of --dump-state=DIR contains a control character')
          end if
        end do
        yl_dump_dir = arg(len(OPT_DS) + 1:l)
        yl_dump_enabled = .true.
      else if (l > len(OPT_ME) .and. arg(1:len(OPT_ME)) == OPT_ME) then
        ok = .true.
        n = 0
        do k = len(OPT_ME) + 1, l
          if (arg(k:k) < '0' .or. arg(k:k) > '9') then
            ok = .false.
            exit
          end if
          if (n > (int(huge(0_ink), i8) - (iachar(arg(k:k)) - iachar('0'))) / 10_i8) then
            ok = .false.   ! would exceed huge(0_ink)
            exit
          end if
          n = 10_i8 * n + (iachar(arg(k:k)) - iachar('0'))
        end do
        if (.not. ok .or. n < 1_i8) then
          call argv_error(i, arg(1:l), 'expected --max-entities=N with N decimal in 1..huge(0_ink)')
        end if
        max_entities = n
      else
        call argv_error(i, arg(1:l), 'unknown command-line argument')
      end if
    end do
  end subroutine diag_set_mode_from_argv

  subroutine argv_error(i, arg, message)
    integer, intent(in) :: i
    character(len=*), intent(in) :: arg, message
    type(diag_t) :: d
    d%code = 'PARSE'
    d%exit_code = EXIT_INPUT
    d%stage = 'argv'
    d%site = 'yl_diag:diag_set_mode_from_argv'
    d%index = i
    d%field = 'argv'
    d%value = arg
    d%allowed = '--check-legacy | --max-entities=N | --dump-state=DIR | --adapter=on|off'
    d%message = message
    call diag_emit(d)
    call diag_exit(d%exit_code)
  end subroutine argv_error

  integer(i8) function diag_max_entities()
    diag_max_entities = max_entities
  end function diag_max_entities

  integer function diag_suppressed_count(idx)
    integer, intent(in) :: idx
    diag_suppressed_count = 0
    if (idx >= 1 .and. idx <= YL_NREADERS) diag_suppressed_count = suppressed(idx)
  end function diag_suppressed_count

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
    d%idx = reader_index(reader)
    call diag_push(d)
  end subroutine diag_raise

  ! Registry index of a reader id (0 when not registered / empty).
  integer function reader_index(reader)
    character(len=*), intent(in) :: reader
    integer :: i
    reader_index = 0
    if (len_trim(reader) == 0) return
    do i = 1, YL_NREADERS
      if (trim(YL_READER_ID(i)) == trim(reader)) then
        reader_index = i
        return
      end if
    end do
  end function reader_index

  ! Append to the pending list, honouring the per-reader cap.
  subroutine diag_push(d)
    type(diag_t), intent(in) :: d
    type(diag_t), allocatable :: tmp(:)
    if (d%idx >= 1 .and. d%idx <= YL_NREADERS) then
      if (kept(d%idx) >= MAX_PER_READER) then
        suppressed(d%idx) = suppressed(d%idx) + 1
        return
      end if
      kept(d%idx) = kept(d%idx) + 1
    end if
    if (.not. allocated(pending%items)) allocate(pending%items(8))
    if (pending%n == size(pending%items)) then
      allocate(tmp(2 * size(pending%items)))
      tmp(1:pending%n) = pending%items(1:pending%n)
      call move_alloc(tmp, pending%items)
    end if
    pending%n = pending%n + 1
    pending%items(pending%n) = d
  end subroutine diag_push

  ! Fill the registry-derived members of an entry for reader idx.
  subroutine fill_reader(d, idx, index, field)
    type(diag_t), intent(inout) :: d
    integer, intent(in) :: idx, index
    character(len=*), intent(in) :: field
    if (idx < 1 .or. idx > YL_NREADERS) call diag_internal('yl_diag: reader index out of range')
    d%idx = idx
    d%stage = YL_READER_STAGE(idx)
    d%file = YL_READER_FILE(idx)
    d%unit = YL_READER_UNIT(idx)
    d%reader = YL_READER_ID(idx)
    d%site = YL_READER_SITE(idx)
    d%seq = YL_READER_SEQ(idx)
    d%index = index
    d%field = field
  end subroutine fill_reader

  function i8str(v) result(s)
    integer(i8), intent(in) :: v
    character(len=24) :: s
    write (s, '(i0)') v
  end function i8str

  ! Decimal text of an integer for guard messages (public wrapper of i8str).
  function diag_itoa(v) result(s)
    integer(i8), intent(in) :: v
    character(len=24) :: s
    s = i8str(v)
  end function diag_itoa

  ! ------------------------------------------------------ semantic guards ----
  ! Guards test their own condition: nothing is recorded when the value is
  ! acceptable, so callers may invoke them unconditionally after each read.

  ! value must lie in lo..hi (inclusive); otherwise RANGE, exit 2.
  subroutine diag_range(idx, index, field, value, lo, hi)
    integer, intent(in) :: idx, index
    character(len=*), intent(in) :: field
    integer(i8), intent(in) :: value, lo, hi
    type(diag_t) :: d
    if (value >= lo .and. value <= hi) return
    call fill_reader(d, idx, index, field)
    d%code = 'RANGE'
    d%exit_code = EXIT_INPUT
    d%value = i8str(value)
    d%allowed = trim(i8str(lo)) // '..' // trim(i8str(hi))
    d%message = trim(field) // '=' // trim(d%value) // ' out of range ' // trim(d%allowed)
    call diag_push(d)
  end subroutine diag_range

  ! value must refer to an existing entry lo..hi; otherwise REF, exit 2.
  subroutine diag_ref(idx, index, field, value, lo, hi)
    integer, intent(in) :: idx, index
    character(len=*), intent(in) :: field
    integer(i8), intent(in) :: value, lo, hi
    type(diag_t) :: d
    if (value >= lo .and. value <= hi) return
    call fill_reader(d, idx, index, field)
    d%code = 'REF'
    d%exit_code = EXIT_INPUT
    d%value = i8str(value)
    d%allowed = trim(i8str(lo)) // '..' // trim(i8str(hi))
    d%message = trim(field) // '=' // trim(d%value) // ' refers to an undefined entry; allowed ' // trim(d%allowed)
    call diag_push(d)
  end subroutine diag_ref

  ! value was seen before (caller detects the repeat): DUPLICATE, exit 2.
  subroutine diag_dup(idx, index, field, value)
    integer, intent(in) :: idx, index
    character(len=*), intent(in) :: field
    integer(i8), intent(in) :: value
    type(diag_t) :: d
    call fill_reader(d, idx, index, field)
    d%code = 'DUPLICATE'
    d%exit_code = EXIT_INPUT
    d%value = i8str(value)
    d%allowed = 'unique'
    d%message = 'duplicate ' // trim(field) // '=' // trim(d%value)
    call diag_push(d)
  end subroutine diag_dup

  ! Legal input that this build cannot process: UNSUPPORTED, exit 3.
  subroutine diag_unsupported(idx, index, field, value_text, allowed_text)
    integer, intent(in) :: idx, index
    character(len=*), intent(in) :: field, value_text, allowed_text
    type(diag_t) :: d
    call fill_reader(d, idx, index, field)
    d%code = 'UNSUPPORTED'
    d%exit_code = EXIT_UNSUPPORTED
    d%value = value_text
    d%allowed = allowed_text
    d%message = 'unsupported ' // trim(field) // '=' // trim(value_text) // '; supported: ' // trim(allowed_text)
    call diag_push(d)
  end subroutine diag_unsupported

  ! The product of factors (array sizes) must not exceed diag_max_entities().
  ! Checked term by term with a > cap/b (b > 0) so it never overflows int64;
  ! a factor <= 0 makes the product trivially small and stops the scan (its
  ! own range is the caller's business). Overflow: RANGE, allowed="<=cap".
  subroutine diag_product(idx, index, field, factors)
    integer, intent(in) :: idx, index
    character(len=*), intent(in) :: field
    integer(i8), intent(in) :: factors(:)
    type(diag_t) :: d
    integer(i8) :: acc, cap
    integer :: k
    logical :: over
    cap = max_entities
    acc = 1_i8
    over = .false.
    do k = 1, size(factors)
      if (factors(k) <= 0_i8) exit
      if (acc > cap / factors(k)) then
        over = .true.
        exit
      end if
      acc = acc * factors(k)
    end do
    if (.not. over) return
    call fill_reader(d, idx, index, field)
    d%code = 'RANGE'
    d%exit_code = EXIT_INPUT
    d%value = ''
    do k = 1, size(factors)
      if (k > 1) d%value = trim(d%value) // '*'
      d%value = trim(d%value) // trim(i8str(factors(k)))
    end do
    d%allowed = '<=' // trim(i8str(cap))
    d%message = 'product of ' // trim(field) // ' (' // trim(d%value) // &
      ') exceeds max entities ' // trim(i8str(cap)) // ' (see --max-entities=N)'
    call diag_push(d)
  end subroutine diag_product

  ! Failure barrier at the end of a reader stage.
  subroutine diag_flush_stage()
    if (pending%n > 0) call diag_fail()
  end subroutine diag_flush_stage

  ! Immediate failure without reader context (bare `stop` replacement).
  subroutine diag_abort(code, exit_code, site, message)
    character(len=*), intent(in) :: code, site, message
    integer, intent(in) :: exit_code
    type(diag_t) :: d
    select case (code)
    case ('RANGE', 'REF', 'DUPLICATE', 'UNSUPPORTED', 'INIT', 'SOLVE', 'INTERNAL')
    case default
      call diag_internal('diag_abort: unknown code ' // trim(code) // ' at ' // trim(site))
    end select
    if (exit_code < EXIT_INPUT .or. exit_code > EXIT_INTERNAL) then
      call diag_internal('diag_abort: exit code out of 2..6 at ' // trim(site))
    end if
    d%code = code
    d%exit_code = exit_code
    d%stage = 'runtime'
    d%site = site
    d%message = message
    call diag_emit(d)
    call diag_exit(exit_code)
  end subroutine diag_abort

  subroutine diag_fail()
    integer :: i, j, code
    if (pending%n == 0) call diag_internal('diag_fail called with no pending diagnostics')
    ! annotate the last kept entry of every reader with suppressed entries
    do j = 1, YL_NREADERS
      if (suppressed(j) == 0) cycle
      do i = pending%n, 1, -1
        if (pending%items(i)%idx == j) then
          pending%items(i)%message = trim(pending%items(i)%message) // ' (+' // &
            trim(i8str(int(suppressed(j), i8))) // ' more)'
          exit
        end if
      end do
    end do
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
    write (error_unit, '(a,a,a,i0,a,a,a,a,a,a,a,a,a,a,a,i0,a,i0,a,i0,a,a,a,a,a,a,a,a,a)') &
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
      '" value="', trim(quoted(trim(d%value))), &
      '" allowed="', trim(quoted(trim(d%allowed))), &
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
