! yl_authoring_toml -- a strict reader for the TOML subset the authoring contract uses.
!
! WHY A SUBSET, AND WHY STRICT
!   `docs/m5/authoring-contract.md` defines the whole input surface, so the reader only has
!   to accept what that surface uses: comments, `key = value`, `[table]`, `[table.sub]`,
!   `[[array of tables]]`, and values that are integers, reals, quoted strings, booleans,
!   flat arrays of those, or arrays of flat arrays (the amplitude points). Everything else
!   -- inline tables, multi-line strings, dates, dotted keys on the left of `=` -- is
!   REJECTED with a line number rather than half-understood. A reader that silently accepts
!   more than the contract describes turns the contract into a suggestion.
!
! WHAT IT PRODUCES
!   A flat store of (key path, value, line). Paths are exactly what the contract's tables
!   read as: `case.name`, `material[2].E`, `step[1].controls.increments`,
!   `step[1].boundary[2].dof[1]`. Flat, because the consumer is a validator that walks a
!   declared key table (yl_authoring_keys) rather than a tree walker: a flat store makes
!   "every key present was declared" and "every required key is present" two set
!   comparisons instead of two recursions.
!
! WHERE THE LINE NUMBERS GO
!   Every entry keeps the line it came from, and every diagnostic carries it. The contract
!   makes that a judgement criterion, not a nicety: an error without a line number is
!   already unreadable in a 50-line file.
!
! WHAT IT DOES NOT DO
!   No validation of NAMES or TYPES against the contract -- that is yl_authoring_keys, and
!   the split is deliberate: this module can be wrong about TOML, or the key table can be
!   wrong about the contract, and keeping them apart means a test can tell which.
module yl_authoring_toml

  use iso_fortran_env, only: int32, real64

  implicit none
  private

  integer, parameter, public :: TOML_LEN_PATH = 96
  integer, parameter, public :: TOML_LEN_TEXT = 256

  !> What a value is. `TV_ARRAY` entries are expanded into one entry per element, with the
  !> index in the path, so the store holds only scalars.
  integer(int32), parameter, public :: TV_INT = 1_int32
  integer(int32), parameter, public :: TV_REAL = 2_int32
  integer(int32), parameter, public :: TV_STR = 3_int32
  integer(int32), parameter, public :: TV_BOOL = 4_int32

  type, public :: toml_entry_t
    character(len=TOML_LEN_PATH) :: path = ''
    integer(int32) :: kind = 0_int32
    integer(int32) :: line = 0_int32
    integer(int32) :: ivalue = 0_int32
    real(real64) :: rvalue = 0.0_real64
    logical :: lvalue = .false.
    character(len=TOML_LEN_TEXT) :: svalue = ''
  end type toml_entry_t

  type, public :: toml_doc_t
    type(toml_entry_t), allocatable :: entry(:)
    integer(int32) :: n = 0_int32
    !> Set when the file could not be read as the contract's subset. `line` and `message`
    !> are the diagnostic; nothing else is meaningful.
    logical :: failed = .false.
    integer(int32) :: fail_line = 0_int32
    character(len=TOML_LEN_TEXT) :: message = ''
  contains
    procedure :: find => doc_find
    procedure :: count_of => doc_count_of
  end type toml_doc_t

  public :: toml_read

contains

  !> Read `path` as the contract's TOML subset. Never aborts: a malformed file comes back
  !> as `doc%failed` with a line and a message, because the caller owns the verdict
  !> (INVALID_INPUT, exit 2) and the exit protocol says the diagnostic is structured.
  subroutine toml_read(path, doc)
    character(len=*), intent(in) :: path
    type(toml_doc_t), intent(out) :: doc

    integer :: u, ios, nline, i, eq, cap
    character(len=1024) :: raw
    character(len=:), allocatable :: line, key, val
    character(len=TOML_LEN_PATH) :: table
    integer(int32) :: idx(8)
    character(len=TOML_LEN_PATH) :: arr_name(8)
    integer :: n_arr

    cap = 4096
    allocate (doc%entry(cap))
    doc%n = 0_int32
    table = ''
    n_arr = 0
    idx = 0_int32
    arr_name = ''

    open (newunit=u, file=path, status='old', action='read', iostat=ios)
    if (ios /= 0) then
      call fail(doc, 0_int32, 'cannot open '//trim(path))
      return
    end if

    nline = 0
    do
      read (u, '(a)', iostat=ios) raw
      if (ios /= 0) exit
      nline = nline + 1
      line = strip_comment(trim(raw))
      line = trim(adjustl(line))
      if (len_trim(line) == 0) cycle

      if (line(1:1) == '[') then
        call parse_header(doc, line, int(nline, int32), table, arr_name, idx, n_arr)
        if (doc%failed) then
          close (u)
          return
        end if
        cycle
      end if

      eq = index(line, '=')
      if (eq <= 1) then
        call fail(doc, int(nline, int32), 'not a `key = value` line: '//trim(line))
        close (u)
        return
      end if
      key = trim(adjustl(line(1:eq - 1)))
      val = trim(adjustl(line(eq + 1:)))
      if (index(key, '.') > 0 .or. index(key, '"') > 0) then
        call fail(doc, int(nline, int32), 'dotted or quoted keys are not part of this '// &
                  'subset; use a [table] header: '//trim(key))
        close (u)
        return
      end if
      if (len_trim(val) == 0) then
        call fail(doc, int(nline, int32), 'no value after `=` for key '//trim(key))
        close (u)
        return
      end if
      call store_value(doc, prefix(table, key), val, int(nline, int32))
      if (doc%failed) then
        close (u)
        return
      end if
    end do
    close (u)

    do i = 1, int(doc%n)
      if (len_trim(doc%entry(i)%path) == 0) then
        call fail(doc, doc%entry(i)%line, 'internal: empty key path')
        return
      end if
    end do
  end subroutine toml_read

  ! ------------------------------------------------------------------ headers ----

  !> `[a.b]` sets the current table. `[[a]]` opens the next element of array-of-tables `a`
  !> and resets any deeper array counters, so `[[step.boundary]]` numbers restart per step.
  subroutine parse_header(doc, line, nline, table, arr_name, idx, n_arr)
    type(toml_doc_t), intent(inout) :: doc
    character(len=*), intent(in) :: line
    integer(int32), intent(in) :: nline
    character(len=TOML_LEN_PATH), intent(inout) :: table
    character(len=TOML_LEN_PATH), intent(inout) :: arr_name(:)
    integer(int32), intent(inout) :: idx(:)
    integer, intent(inout) :: n_arr

    logical :: is_arr
    character(len=:), allocatable :: name
    integer :: k, close_at

    is_arr = len(line) >= 2 .and. line(1:2) == '[['
    if (is_arr) then
      close_at = index(line, ']]')
      if (close_at == 0) then
        call fail(doc, nline, 'unterminated [[table]] header')
        return
      end if
      name = trim(adjustl(line(3:close_at - 1)))
    else
      close_at = index(line, ']')
      if (close_at == 0) then
        call fail(doc, nline, 'unterminated [table] header')
        return
      end if
      name = trim(adjustl(line(2:close_at - 1)))
    end if
    if (len_trim(name) == 0) then
      call fail(doc, nline, 'empty table name')
      return
    end if

    if (is_arr) then
      k = arr_slot(arr_name, n_arr, name)
      if (k == 0) then
        if (n_arr >= size(arr_name)) then
          call fail(doc, nline, 'too many distinct [[table]] names')
          return
        end if
        n_arr = n_arr + 1
        k = n_arr
        arr_name(k) = name
        idx(k) = 0_int32
      end if
      idx(k) = idx(k) + 1_int32
      ! A new element of an OUTER array invalidates the counters of its inner arrays:
      ! [[step.boundary]] must number 1,2 inside step 1 and 1,2 again inside step 2.
      call reset_inner(arr_name, idx, n_arr, name)
      table = subst_indices(name, arr_name, idx, n_arr)
    else
      table = subst_indices(name, arr_name, idx, n_arr)
    end if
  end subroutine parse_header

  pure integer function arr_slot(arr_name, n_arr, name) result(k)
    character(len=TOML_LEN_PATH), intent(in) :: arr_name(:)
    integer, intent(in) :: n_arr
    character(len=*), intent(in) :: name
    integer :: i
    k = 0
    do i = 1, n_arr
      if (trim(arr_name(i)) == trim(name)) then
        k = i
        return
      end if
    end do
  end function arr_slot

  pure subroutine reset_inner(arr_name, idx, n_arr, outer)
    character(len=TOML_LEN_PATH), intent(in) :: arr_name(:)
    integer(int32), intent(inout) :: idx(:)
    integer, intent(in) :: n_arr
    character(len=*), intent(in) :: outer
    integer :: i, n
    n = len_trim(outer)
    do i = 1, n_arr
      if (len_trim(arr_name(i)) > n) then
        if (arr_name(i) (1:n) == outer(1:n) .and. arr_name(i) (n + 1:n + 1) == '.') then
          idx(i) = 0_int32
        end if
      end if
    end do
  end subroutine reset_inner

  !> `step.boundary` -> `step[1].boundary[2]`, using the current counter of every
  !> array-of-tables prefix. A plain [table] under an array element gets the element's
  !> index too, which is what makes `[step.controls]` land inside `step[1]`.
  pure function subst_indices(name, arr_name, idx, n_arr) result(out)
    character(len=*), intent(in) :: name
    character(len=TOML_LEN_PATH), intent(in) :: arr_name(:)
    integer(int32), intent(in) :: idx(:)
    integer, intent(in) :: n_arr
    character(len=TOML_LEN_PATH) :: out
    !> `raw` accumulates the path WITHOUT indices and is what arr_name is keyed by; `acc`
    !> accumulates the path WITH them. Using one accumulator for both loses every index
    !> below the first: `step.boundary` is registered under that name, so looking it up as
    !> `step[1].boundary` finds nothing and the element index silently disappears.
    character(len=TOML_LEN_PATH) :: acc, raw
    integer :: i, j, p, k
    character(len=TOML_LEN_PATH) :: seg
    acc = ''
    raw = ''
    p = 1
    do
      j = index(name(p:), '.')
      if (j == 0) then
        seg = name(p:)
      else
        seg = name(p:p + j - 2)
      end if
      if (len_trim(raw) == 0) then
        raw = trim(seg)
        acc = trim(seg)
      else
        raw = trim(raw)//'.'//trim(seg)
        acc = trim(acc)//'.'//trim(seg)
      end if
      k = 0
      do i = 1, n_arr
        if (trim(arr_name(i)) == trim(raw)) k = i
      end do
      if (k > 0) acc = trim(acc)//'['//trim(itoa(idx(k)))//']'
      if (j == 0) exit
      p = p + j
    end do
    out = acc
  end function subst_indices

  ! ------------------------------------------------------------------- values ----

  recursive subroutine store_value(doc, path, val, nline)
    type(toml_doc_t), intent(inout) :: doc
    character(len=*), intent(in) :: path, val
    integer(int32), intent(in) :: nline
    character(len=:), allocatable :: body, item
    integer :: i, n, depth, start
    logical :: ok

    if (val(1:1) == '[') then
      if (val(len_trim(val):len_trim(val)) /= ']') then
        call fail(doc, nline, 'array not closed on one line (multi-line arrays are not '// &
                  'part of this subset): '//trim(path))
        return
      end if
      body = trim(val(2:len_trim(val) - 1))
      ! Split at top-level commas so `[[0.0, 1.0], [1.0, 1.0]]` yields two sub-arrays.
      n = 0
      depth = 0
      start = 1
      do i = 1, len_trim(body) + 1
        if (i <= len_trim(body)) then
          if (body(i:i) == '[') depth = depth + 1
          if (body(i:i) == ']') depth = depth - 1
        end if
        if (i > len_trim(body) .or. (body(i:i) == ',' .and. depth == 0)) then
          item = trim(adjustl(body(start:i - 1)))
          if (len_trim(item) > 0) then
            n = n + 1
            if (item(1:1) == '[') then
              call store_value(doc, trim(path)//'['//trim(itoa(int(n, int32)))//']', &
                               item, nline)
            else
              call put_scalar(doc, trim(path)//'['//trim(itoa(int(n, int32)))//']', &
                              item, nline, ok)
              if (.not. ok) then
                call fail(doc, nline, 'not a value this subset accepts: '//trim(item)// &
                          ' (in '//trim(path)//')')
                return
              end if
            end if
            if (doc%failed) return
          end if
          start = i + 1
        end if
      end do
      ! The count is stored so the validator can talk about lengths without rescanning.
      call put_int(doc, trim(path)//'.count', int(n, int32), nline)
      return
    end if

    call put_scalar(doc, path, val, nline, ok)
    if (.not. ok) call fail(doc, nline, 'not a value this subset accepts: '//trim(val)// &
                            ' (for '//trim(path)//')')
  end subroutine store_value

  subroutine put_scalar(doc, path, val, nline, ok)
    type(toml_doc_t), intent(inout) :: doc
    character(len=*), intent(in) :: path, val
    integer(int32), intent(in) :: nline
    logical, intent(out) :: ok
    integer(int32) :: iv
    real(real64) :: rv
    integer :: ios
    ok = .true.
    if (val(1:1) == '"') then
      if (len_trim(val) < 2 .or. val(len_trim(val):len_trim(val)) /= '"') then
        ok = .false.
        return
      end if
      call put_str(doc, path, val(2:len_trim(val) - 1), nline)
      return
    end if
    if (trim(val) == 'true' .or. trim(val) == 'false') then
      call put_bool(doc, path, trim(val) == 'true', nline)
      return
    end if
    ! Integer before real, so `1` stays an integer and `1.0` becomes a real. The contract
    ! never accepts one where it declared the other, and the key table is what says which.
    if (index(val, '.') == 0 .and. index(val, 'e') == 0 .and. index(val, 'E') == 0) then
      read (val, *, iostat=ios) iv
      if (ios == 0) then
        call put_int(doc, path, iv, nline)
        return
      end if
    end if
    read (val, *, iostat=ios) rv
    if (ios == 0) then
      call put_real(doc, path, rv, nline)
      return
    end if
    ok = .false.
  end subroutine put_scalar

  ! ------------------------------------------------------------------- store ----

  subroutine grow(doc)
    type(toml_doc_t), intent(inout) :: doc
    type(toml_entry_t), allocatable :: bigger(:)
    if (doc%n < size(doc%entry)) return
    allocate (bigger(2*size(doc%entry)))
    bigger(1:doc%n) = doc%entry(1:doc%n)
    call move_alloc(bigger, doc%entry)
  end subroutine grow

  subroutine put_int(doc, path, v, nline)
    type(toml_doc_t), intent(inout) :: doc
    character(len=*), intent(in) :: path
    integer(int32), intent(in) :: v, nline
    call grow(doc)
    doc%n = doc%n + 1_int32
    doc%entry(doc%n)%path = path
    doc%entry(doc%n)%kind = TV_INT
    doc%entry(doc%n)%ivalue = v
    doc%entry(doc%n)%rvalue = real(v, real64)
    doc%entry(doc%n)%line = nline
  end subroutine put_int

  subroutine put_real(doc, path, v, nline)
    type(toml_doc_t), intent(inout) :: doc
    character(len=*), intent(in) :: path
    real(real64), intent(in) :: v
    integer(int32), intent(in) :: nline
    call grow(doc)
    doc%n = doc%n + 1_int32
    doc%entry(doc%n)%path = path
    doc%entry(doc%n)%kind = TV_REAL
    doc%entry(doc%n)%rvalue = v
    doc%entry(doc%n)%line = nline
  end subroutine put_real

  subroutine put_str(doc, path, v, nline)
    type(toml_doc_t), intent(inout) :: doc
    character(len=*), intent(in) :: path, v
    integer(int32), intent(in) :: nline
    call grow(doc)
    doc%n = doc%n + 1_int32
    doc%entry(doc%n)%path = path
    doc%entry(doc%n)%kind = TV_STR
    doc%entry(doc%n)%svalue = v
    doc%entry(doc%n)%line = nline
  end subroutine put_str

  subroutine put_bool(doc, path, v, nline)
    type(toml_doc_t), intent(inout) :: doc
    character(len=*), intent(in) :: path
    logical, intent(in) :: v
    integer(int32), intent(in) :: nline
    call grow(doc)
    doc%n = doc%n + 1_int32
    doc%entry(doc%n)%path = path
    doc%entry(doc%n)%kind = TV_BOOL
    doc%entry(doc%n)%lvalue = v
    doc%entry(doc%n)%line = nline
  end subroutine put_bool

  !> Index of `path`, or 0. Linear: the store is a few hundred entries and a hash would be
  !> one more thing that can be wrong about a file this small.
  pure integer(int32) function doc_find(self, path) result(k)
    class(toml_doc_t), intent(in) :: self
    character(len=*), intent(in) :: path
    integer(int32) :: i
    k = 0_int32
    do i = 1_int32, self%n
      if (trim(self%entry(i)%path) == trim(path)) then
        k = i
        return
      end if
    end do
  end function doc_find

  !> How many elements the array-of-tables `name` has, by counting `name[i].` prefixes.
  pure integer(int32) function doc_count_of(self, name) result(n)
    class(toml_doc_t), intent(in) :: self
    character(len=*), intent(in) :: name
    integer(int32) :: i, j
    integer :: L
    character(len=TOML_LEN_PATH) :: p
    n = 0_int32
    L = len_trim(name)
    do i = 1_int32, self%n
      p = self%entry(i)%path
      if (len_trim(p) <= L + 2) cycle
      if (p(1:L) /= name(1:L)) cycle
      if (p(L + 1:L + 1) /= '[') cycle
      j = 0_int32
      read (p(L + 2:L + 1 + index(p(L + 2:), ']') - 1), *) j
      if (j > n) n = j
    end do
  end function doc_count_of

  ! ------------------------------------------------------------------ helpers ----

  subroutine fail(doc, nline, msg)
    type(toml_doc_t), intent(inout) :: doc
    integer(int32), intent(in) :: nline
    character(len=*), intent(in) :: msg
    doc%failed = .true.
    doc%fail_line = nline
    doc%message = msg
  end subroutine fail

  !> Drop a trailing `# comment`, but not a `#` inside a quoted string.
  pure function strip_comment(s) result(out)
    character(len=*), intent(in) :: s
    character(len=len(s)) :: out
    logical :: inq
    integer :: i
    out = ''
    inq = .false.
    do i = 1, len_trim(s)
      if (s(i:i) == '"') inq = .not. inq
      if (s(i:i) == '#' .and. .not. inq) exit
      out(i:i) = s(i:i)
    end do
  end function strip_comment

  pure function prefix(table, key) result(out)
    character(len=*), intent(in) :: table, key
    character(len=TOML_LEN_PATH) :: out
    if (len_trim(table) == 0) then
      out = trim(key)
    else
      out = trim(table)//'.'//trim(key)
    end if
  end function prefix

  pure function itoa(v) result(out)
    integer(int32), intent(in) :: v
    character(len=12) :: buf
    character(len=:), allocatable :: out
    write (buf, '(i0)') v
    out = trim(buf)
  end function itoa

end module yl_authoring_toml
