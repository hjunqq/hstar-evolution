! yl_state_io -- state snapshot writer for the M2-02 observer.
!
! Design (see .ccg/tasks/m2-02-state-serializer/plan-fortran.md sections 3 and 6):
!   * Handwritten; depends only on iso_fortran_env, variable_types (ink/irk) and
!     yl_diag (structured diagnostics + exit protocol). It never uses a legacy
!     data module, and it never touches the shared scratch yl_ios / yl_msg: the
!     writer carries its own iostat/iomsg so that an observer I/O error can
!     never be confused with a legacy reader error.
!   * One file per checkpoint: <dump dir>/<sanitized checkpoint>/state.txt.
!     The directory is created by the runner; a missing directory is a
!     structured failure (state_fail -> HSTAR_DIAG + exit 6), never a silent
!     skip and never a half-written snapshot that looks valid.
!   * Wire format (ASCII, LF terminated, no trailing blanks):
!       HSTAR_STATE schema=1 checkpoint=<id> fields=<n>
!       field=<id> key=[<k1>,<k2>] shape=[<s1>,<s2>] dtype=<t> values=[v,v,...]
!       HSTAR_STATE_END fields=<n>
!     <n> counts distinct logical field ids, not records. Keys are 1-based
!     positive outer-index tuples; a dense field uses key=[]. A scalar uses
!     shape=[] (exactly one value). An empty list uses shape=[0].
!     Value encoding: i32 -> I0 decimal; f64 -> exactly 16 hex digits of the
!     IEEE binary64 bit pattern (Z16.16 of transfer(v, 0_int64)), so no decimal
!     rounding is involved; str -> 'x' followed by Z2.2 per byte up to len_trim
!     ('x' alone for the empty string), which preserves non-ASCII (GBK/latin-1)
!     bytes without any decoding.
!   * The file is opened with access='stream', form='formatted'. Records can be
!     millions of characters long (dense npoin / unode lists) and formatted
!     stream has no RECL limit, unlike sequential formatted output whose Intel
!     default record length would truncate them. Stream also fixes the record
!     terminator at a single LF on every platform.
!   * Every write is non-advancing with a checked iostat; separators between
!     values are emitted by the writer, never by the caller.
!   * Kind assertions run once at state_open: ink must be a 32-bit integer and
!     irk must be IEEE binary64, otherwise the value encodings above are wrong.
module yl_state_io

  use iso_fortran_env, only: int64
  use variable_types, only: ink, irk
  use yl_diag, only: diag_abort, EXIT_INTERNAL

  implicit none
  private

  integer, parameter, public :: LEN_STATE_ID = 96
  integer, parameter, public :: LEN_STATE_CP = 64
  integer, parameter, public :: LEN_STATE_PATH = 512
  integer, parameter :: LEN_STATE_IOMSG = 512

  ! Empty key of a dense field / empty shape of a scalar field. Both are the
  ! same zero-sized constant; two names keep the call sites readable.
  integer(int64), parameter, public :: NO_KEY(0) = [integer(int64) ::]
  integer(int64), parameter, public :: SCALAR_SHAPE(0) = [integer(int64) ::]

  type, public :: state_writer_t
    integer :: unit = -1                                ! newunit= of the open file
    logical :: is_open = .false.
    logical :: in_field = .false.
    character(len=LEN_STATE_CP) :: checkpoint = ''      ! checkpoint id as given
    character(len=LEN_STATE_PATH) :: path = ''          ! full state.txt path
    character(len=LEN_STATE_ID) :: field_id = ''        ! field currently open
    character(len=LEN_STATE_ID) :: last_id = ''         ! last id seen (distinct count)
    integer(int64) :: nvalues = 0_int64                 ! values written in this record
    integer(int64) :: nexpect = 0_int64                 ! product(shape) of this record
    integer :: nfields = 0                              ! distinct ids written so far
    integer :: nfields_declared = 0                     ! header count
    integer :: ios = 0                                  ! private iostat (never yl_ios)
    character(len=LEN_STATE_IOMSG) :: iomsg = ''        ! private iomsg (never yl_msg)
  end type state_writer_t

  public :: state_open, state_close
  public :: begin_field, end_field
  public :: put_i32, put_f64, put_str
  public :: state_fail, state_checkpoint_dir

contains

  ! ------------------------------------------------------------- failure ----
  ! An observer failure is fatal and loud: the partly written file loses its
  ! HSTAR_STATE_END trailer (so it can never be mistaken for a snapshot), one
  ! HSTAR_DIAG line goes to stderr through the M1-02 protocol, and the process
  ! exits with EXIT_INTERNAL. diag_abort does not return.
  subroutine state_fail(w, id, message)
    type(state_writer_t), intent(inout) :: w
    character(len=*), intent(in) :: id, message
    if (w%is_open) then
      close (w%unit, iostat=w%ios)
      w%is_open = .false.
      w%in_field = .false.
    end if
    call diag_abort('INTERNAL', EXIT_INTERNAL, 'yl_state_io:state_fail', &
      'state dump failed at checkpoint "' // trim(w%checkpoint) // '" field "' // &
      trim(id) // '" file "' // trim(w%path) // '": ' // trim(message))
  end subroutine state_fail

  ! -------------------------------------------------------------- helpers ----
  ! Decimal text of an int64 (no blanks).
  function itoa(v) result(s)
    integer(int64), intent(in) :: v
    character(len=24) :: s
    write (s, '(i0)') v
  end function itoa

  ! Checked non-advancing write of a text chunk.
  subroutine wr(w, text)
    type(state_writer_t), intent(inout) :: w
    character(len=*), intent(in) :: text
    if (.not. w%is_open) call state_fail(w, w%field_id, 'write on a closed state writer')
    write (w%unit, '(a)', advance='no', iostat=w%ios, iomsg=w%iomsg) text
    if (w%ios /= 0) call state_fail(w, w%field_id, 'write failed: ' // trim(w%iomsg))
  end subroutine wr

  ! Checked end of the current record (one LF).
  subroutine endline(w)
    type(state_writer_t), intent(inout) :: w
    if (.not. w%is_open) call state_fail(w, w%field_id, 'end of record on a closed state writer')
    write (w%unit, '(a)', iostat=w%ios, iomsg=w%iomsg) ''
    if (w%ios /= 0) call state_fail(w, w%field_id, 'write failed: ' // trim(w%iomsg))
  end subroutine endline

  ! Comma between two values of the same record.
  subroutine sep(w)
    type(state_writer_t), intent(inout) :: w
    if (w%nvalues > 0_int64) call wr(w, ',')
  end subroutine sep

  ! Common preamble of every put_*: the record must be open and must still have
  ! room for one more value.
  subroutine begin_value(w, dtype)
    type(state_writer_t), intent(inout) :: w
    character(len=*), intent(in) :: dtype
    if (.not. w%in_field) call state_fail(w, w%field_id, 'put_' // dtype // ' outside begin_field/end_field')
    if (w%nvalues >= w%nexpect) then
      call state_fail(w, w%field_id, 'more values than the declared shape (' // &
        trim(itoa(w%nexpect)) // ')')
    end if
    call sep(w)
  end subroutine begin_value

  ! Directory name of a checkpoint id: every character outside [A-Za-z0-9_]
  ! becomes '_', runs of '_' collapse and trailing '_' is dropped. This maps
  ! model_ready -> model_ready, phase_ready(1) -> phase_ready_1 and
  ! increment_ready(1,1) -> increment_ready_1_1.
  function state_checkpoint_dir(checkpoint) result(d)
    character(len=*), intent(in) :: checkpoint
    character(len=LEN_STATE_CP) :: d
    character(len=1) :: c
    integer :: i, j
    d = ''
    j = 0
    do i = 1, min(len_trim(checkpoint), LEN_STATE_CP)
      c = checkpoint(i:i)
      if ((c >= 'A' .and. c <= 'Z') .or. (c >= 'a' .and. c <= 'z') .or. &
          (c >= '0' .and. c <= '9') .or. c == '_') then
        j = j + 1
        d(j:j) = c
      else
        if (j > 0) then
          if (d(j:j) /= '_') then
            j = j + 1
            d(j:j) = '_'
          end if
        end if
      end if
    end do
    do while (j > 0)
      if (d(j:j) /= '_') exit
      d(j:j) = ' '
      j = j - 1
    end do
  end function state_checkpoint_dir

  ! Kind assertions: the wire encodings assume a 32-bit ink and an IEEE
  ! binary64 irk. Checked once per snapshot, before the first byte is written.
  subroutine assert_kinds(w)
    type(state_writer_t), intent(inout) :: w
    if (storage_size(0_ink) /= 32) then
      call state_fail(w, '', 'ink is not a 32-bit integer (storage_size=' // &
        trim(itoa(int(storage_size(0_ink), int64))) // '); the i32 encoding is invalid')
    end if
    if (storage_size(0.0_irk) /= 64 .or. radix(0.0_irk) /= 2 .or. &
        digits(0.0_irk) /= 53 .or. maxexponent(0.0_irk) /= 1024) then
      call state_fail(w, '', 'irk is not IEEE binary64; the f64 hex encoding is invalid')
    end if
  end subroutine assert_kinds

  ! ----------------------------------------------------------- open/close ----
  ! Open <dir>/<checkpoint dir>/state.txt and write the header. nfields is the
  ! number of distinct logical field ids this checkpoint will emit.
  subroutine state_open(w, dir, checkpoint, nfields)
    type(state_writer_t), intent(inout) :: w
    character(len=*), intent(in) :: dir, checkpoint
    integer, intent(in) :: nfields
    character(len=LEN_STATE_CP) :: cdir
    integer :: u

    if (w%is_open) call state_fail(w, '', 'state_open on a writer that is already open')
    w%checkpoint = checkpoint
    w%path = ''
    w%field_id = ''
    w%last_id = ''
    w%in_field = .false.
    w%nvalues = 0_int64
    w%nexpect = 0_int64
    w%nfields = 0
    w%nfields_declared = nfields
    w%ios = 0
    w%iomsg = ''

    call assert_kinds(w)
    if (len_trim(checkpoint) == 0) call state_fail(w, '', 'empty checkpoint id')
    if (len_trim(dir) == 0) call state_fail(w, '', 'empty state dump directory')
    if (nfields < 0) call state_fail(w, '', 'negative field count in the state header')
    cdir = state_checkpoint_dir(checkpoint)
    if (len_trim(cdir) == 0) call state_fail(w, '', 'checkpoint id "' // trim(checkpoint) // &
      '" has no usable directory name')
    if (len_trim(dir) + len_trim(cdir) + 12 > LEN_STATE_PATH) then
      call state_fail(w, '', 'state dump path longer than ' // trim(itoa(int(LEN_STATE_PATH, int64))) // ' characters')
    end if
    w%path = trim(dir) // '/' // trim(cdir) // '/state.txt'

    open (newunit=u, file=trim(w%path), status='replace', action='write', &
          access='stream', form='formatted', iostat=w%ios, iomsg=w%iomsg)
    if (w%ios /= 0) then
      call state_fail(w, '', 'cannot open the snapshot file (is the checkpoint directory missing?): ' // &
        trim(w%iomsg))
    end if
    w%unit = u
    w%is_open = .true.

    call wr(w, 'HSTAR_STATE schema=1 checkpoint=' // trim(checkpoint) // &
      ' fields=' // trim(itoa(int(nfields, int64))))
    call endline(w)
  end subroutine state_open

  ! Write the trailer, flush and close. nfields must match both the header and
  ! the number of distinct ids actually emitted.
  subroutine state_close(w, nfields)
    type(state_writer_t), intent(inout) :: w
    integer, intent(in) :: nfields
    if (.not. w%is_open) call state_fail(w, '', 'state_close on a writer that is not open')
    if (w%in_field) call state_fail(w, w%field_id, 'state_close with field ' // trim(w%field_id) // ' still open')
    if (nfields /= w%nfields_declared) then
      call state_fail(w, '', 'trailer field count ' // trim(itoa(int(nfields, int64))) // &
        ' differs from the header count ' // trim(itoa(int(w%nfields_declared, int64))))
    end if
    if (w%nfields /= nfields) then
      call state_fail(w, '', trim(itoa(int(w%nfields, int64))) // ' distinct field ids were emitted but ' // &
        trim(itoa(int(nfields, int64))) // ' were declared')
    end if
    call wr(w, 'HSTAR_STATE_END fields=' // trim(itoa(int(nfields, int64))))
    call endline(w)
    flush (w%unit, iostat=w%ios, iomsg=w%iomsg)
    if (w%ios /= 0) call state_fail(w, '', 'flush failed: ' // trim(w%iomsg))
    close (w%unit, iostat=w%ios, iomsg=w%iomsg)
    if (w%ios /= 0) then
      w%is_open = .false.
      call state_fail(w, '', 'close failed: ' // trim(w%iomsg))
    end if
    w%is_open = .false.
    w%unit = -1
  end subroutine state_close

  ! ----------------------------------------------------------- record framing ----
  ! Start one record of field `id`. `key` is the 1-based outer-index tuple
  ! (zero-sized for a dense field), `shape` the physical extents of this record
  ! (zero-sized for a scalar, [0] for an empty list), `dtype` one of i32/f64/str.
  subroutine begin_field(w, id, key, shape, dtype)
    type(state_writer_t), intent(inout) :: w
    character(len=*), intent(in) :: id
    integer(int64), intent(in) :: key(:), shape(:)
    character(len=*), intent(in) :: dtype
    integer :: k
    integer(int64) :: n

    if (.not. w%is_open) call state_fail(w, id, 'begin_field before state_open')
    if (w%in_field) call state_fail(w, id, 'begin_field while field ' // trim(w%field_id) // ' is still open')
    if (len_trim(id) == 0) call state_fail(w, id, 'empty field id')
    if (len_trim(id) > LEN_STATE_ID) call state_fail(w, id, 'field id longer than the writer allows')
    select case (dtype)
    case ('i32', 'f64', 'str')
    case default
      call state_fail(w, id, 'unknown dtype "' // trim(dtype) // '"; expected i32, f64 or str')
    end select
    do k = 1, size(key)
      if (key(k) < 1_int64) then
        call state_fail(w, id, 'key component ' // trim(itoa(int(k, int64))) // ' is ' // &
          trim(itoa(key(k))) // '; keys are 1-based positive indices')
      end if
    end do
    n = 1_int64
    do k = 1, size(shape)
      if (shape(k) < 0_int64) then
        call state_fail(w, id, 'extent ' // trim(itoa(int(k, int64))) // ' is negative (' // &
          trim(itoa(shape(k))) // ')')
      end if
      if (shape(k) > 0_int64) then
        if (n > huge(0_int64) / shape(k)) call state_fail(w, id, 'declared shape overflows a 64-bit value count')
      end if
      n = n * shape(k)
    end do

    w%field_id = id
    w%nvalues = 0_int64
    w%nexpect = n
    if (trim(id) /= trim(w%last_id)) then
      w%nfields = w%nfields + 1
      w%last_id = id
    end if

    call wr(w, 'field=' // trim(id) // ' key=[')
    do k = 1, size(key)
      if (k > 1) call wr(w, ',')
      call wr(w, trim(itoa(key(k))))
    end do
    call wr(w, '] shape=[')
    do k = 1, size(shape)
      if (k > 1) call wr(w, ',')
      call wr(w, trim(itoa(shape(k))))
    end do
    call wr(w, '] dtype=' // trim(dtype) // ' values=[')
    w%in_field = .true.
  end subroutine begin_field

  ! Close the current record; the emitted count must equal product(shape).
  subroutine end_field(w)
    type(state_writer_t), intent(inout) :: w
    if (.not. w%in_field) call state_fail(w, w%field_id, 'end_field without begin_field')
    if (w%nvalues /= w%nexpect) then
      call state_fail(w, w%field_id, trim(itoa(w%nvalues)) // ' values emitted but the declared shape needs ' // &
        trim(itoa(w%nexpect)))
    end if
    call wr(w, ']')
    call endline(w)
    w%in_field = .false.
    w%nvalues = 0_int64
    w%nexpect = 0_int64
  end subroutine end_field

  ! -------------------------------------------------------------- values ----
  subroutine put_i32(w, v)
    type(state_writer_t), intent(inout) :: w
    integer(ink), intent(in) :: v
    character(len=24) :: s
    call begin_value(w, 'i32')
    write (s, '(i0)') v
    call wr(w, trim(s))
    w%nvalues = w%nvalues + 1_int64
  end subroutine put_i32

  ! Exactly 16 hex digits of the IEEE binary64 bit pattern: lossless, and
  ! independent of the run-time rounding of decimal output.
  subroutine put_f64(w, v)
    type(state_writer_t), intent(inout) :: w
    real(irk), intent(in) :: v
    integer(int64) :: bits
    character(len=16) :: s
    call begin_value(w, 'f64')
    bits = transfer(v, 0_int64)
    write (s, '(z16.16)') bits
    call wr(w, s)
    w%nvalues = w%nvalues + 1_int64
  end subroutine put_f64

  ! 'x' followed by two hex digits per byte, up to len_trim (trailing blanks of
  ! the legacy fixed-length character components are not part of the value).
  ! The empty string is a bare 'x'. Bytes are copied, never decoded, so GBK /
  ! latin-1 content survives unchanged.
  subroutine put_str(w, s)
    type(state_writer_t), intent(inout) :: w
    character(len=*), intent(in) :: s
    character(len=2) :: h
    integer :: i, n
    call begin_value(w, 'str')
    call wr(w, 'x')
    n = len_trim(s)
    do i = 1, n
      write (h, '(z2.2)') iachar(s(i:i))
      call wr(w, h)
    end do
    w%nvalues = w%nvalues + 1_int64
  end subroutine put_str

end module yl_state_io
