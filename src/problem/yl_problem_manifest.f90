! yl_problem_manifest -- the derivation manifest of the M3 problem pipeline.
!
! Why this module exists
!   docs/01 section 6 and the M3 exit condition of docs/02 require that "every
!   derived value and every default is traceable". A value that finalize
!   computes, or that a default profile supplies, must be able to answer four
!   questions after the fact: what object and field received it, which rule
!   produced it, which input fields it was read from, and -- for a default --
!   which versioned profile decided it. This module is the record of those
!   answers. It is written by finalize and read by the self-test and by a
!   Python-side check; it is never read by the solver.
!
! Scope (see .ccg/tasks/m3-02-normalize-validate-finalize/plan.md deliverable 4,
! analysis-codex.md section 4, analysis-claude.md sections 4 and 5)
!   This module knows NOTHING about normalize / validate / capability gate /
!   finalize. It has no dependency on yl_problem_types and no notion of a draft.
!   It records what it is told, in the order it is told, and renders that record
!   as text. Keeping it ignorant is what lets the pipeline module own the rules
!   and this module own the evidence format, with no cycle between them.
!
!   In scope for M3-02 there are ten rule-derived rows (seven index_map, two
!   count, one legacy_default) plus the eight checkable declared-count
!   comparisons of analysis-claude.md section 4b. M3-03 adds roughly forty-five
!   more rows, including the dof_expand, renumber and geometry rule kinds. All
!   three are in the accepted rule vocabulary below, so M3-03 adds entries, not
!   a new record format. The vocabulary is not open, though: it must track the
!   derive-rule set of docs/m2/state-field-map.toml, which is six kinds today
!   and grew by one (geometry) during M3-03. See the comment on the
!   MANIFEST_RULE_* constants for the three places that set is restated.
!
! In memory first, file second (Q2)
!   The accumulator is a plain in-memory container and the writer is a separate,
!   optional call. Three reasons, in order of weight:
!     1. The pipeline must not do I/O. A finalize that wrote to a file as it
!        derived values would couple a semantic failure to a half-written file
!        and would make the transactional discipline of ADR-0002 (build a
!        candidate, move_alloc on success) meaningless for the evidence.
!     2. The self-test asserts on the manifest directly -- entry count, rule,
!        object, inputs, rendered value -- with no file system in the loop and
!        no parser to trust. manifest_record renders the exact line that the
!        writer would emit, so an in-memory assertion and the on-disk bytes
!        cannot drift apart.
!     3. A failed derivation still leaves a complete manifest of what HAD been
!        derived, which is exactly the evidence needed to diagnose it. A
!        streaming writer would have flushed a prefix and lost the rest.
!
! Failure policy -- and how it differs from yl_state_io
!   The style is yl_state_io: a writer that carries its own iostat and iomsg
!   (never the shared legacy yl_ios / yl_msg), line-oriented ASCII, checked
!   writes, a fail-closed close, and a trailer that repeats the entry count so a
!   truncated file can never be mistaken for a complete one. The failure POLICY
!   is deliberately different. yl_state_io aborts the process, which is right
!   for an observer that has already lost the snapshot it was asked to take.
!   Here a bad add is a programming error inside a pipeline that owns a
!   structured error list, so:
!     * add_* never aborts and never stops the pipeline. A malformed entry sets
!       a sticky bad flag with a reason and is not stored.
!     * The writer refuses, fail-closed, to write a manifest whose sticky flag
!       is set, and reports why through stat / errmsg.
!     * Every entry point that can fail has an optional stat; none of them
!       reaches yl_diag.
!
! Wire format (ASCII, LF terminated)
!     HSTAR_MANIFEST schema=1 entries=<n>
!     entry=<i> kind=<k> rule=<r> object=<p> field=<f> map=<id> dtype=<t>
!       value=<v> expected=<v> verdict=<w> inputs=[<p>,<p>] profile=<id>
!       profile_version=<v>
!     HSTAR_MANIFEST_END entries=<n>
!   (one record per line; the wrap above is only in this comment). Every record
!   carries all thirteen keys in that fixed order, always, so a consumer splits
!   on single blanks and then on the first '='. Unused keys carry the empty
!   string: expected and verdict on a derived or default row, profile and
!   profile_version on anything but a default.
!
!   Value encoding follows the M2 conventions so that a value round-trips
!   exactly: i32 as I0 decimal, f64 as exactly 16 uppercase hex digits of the
!   IEEE binary64 bit pattern (Z16.16 of transfer(v, 0_int64)), bool as 0 / 1,
!   str as its trimmed bytes, and a list as [v,v,...] of the element encoding
!   ([] when empty). dtype names the encoding, so a consumer never has to guess.
!
!   Text escaping. Field values are separated by single blanks, so any byte
!   outside printable non-blank ASCII, plus the backslash itself, is written as
!   \xHH (uppercase hex). An object path, a rule id and a decimal number are
!   therefore literal; a legacy GBK byte or an embedded blank survives without
!   breaking the tokenisation, and the encoding is total and reversible.
!
! Determinism
!   Entries are emitted in insertion order, the key order is fixed, no floating
!   point is formatted in decimal, and no allocatable component is left in an
!   undefined state (every character component is assigned before use). The same
!   pipeline over the same draft therefore produces byte-identical bytes.
module yl_problem_manifest

  use iso_fortran_env, only: int32, int64, real64

  implicit none
  private

  integer, parameter, public :: MANIFEST_SCHEMA = 1

  ! Entry kinds.
  character(len=*), parameter, public :: MANIFEST_KIND_DERIVED = 'derived'
  character(len=*), parameter, public :: MANIFEST_KIND_DEFAULT = 'default'
  character(len=*), parameter, public :: MANIFEST_KIND_CHECK = 'check'

  ! Rule vocabulary.
  !
  ! The first six MUST be exactly the derive-rule kinds of the `source =
  ! ["derived:<kind>"]` column of docs/m2/state-field-map.toml. That set is
  ! closed and it is currently SIX: index_map, count, legacy_default,
  ! dof_expand, renumber, geometry. Three of them are exercised by M3-02
  ! (index_map, count, legacy_default); dof_expand and renumber arrive with the
  ! M3-03 RuntimeState rows; geometry was added during M3-03 for the three
  ! Gauss-point rows (runtime.gauss.djacb / gpcod / cartd), which had been
  ! misclassified as legacy_default although they are the weighted Jacobian,
  ! the Gauss-point coordinates and the Cartesian shape-function derivatives,
  ! COMPUTED per element from the mesh geometry and the quadrature rule rather
  ! than looked up.
  !
  ! declared_count is the seventh and is NOT a map kind: it is the deck-count
  ! agreement check of V21 (plan section "规则集"), whose passing verdict must
  ! stay visible in the evidence.
  !
  ! Keeping the set closed is the point -- an unknown rule is rejected, so a
  ! typo cannot enter the evidence as a new rule kind. The cost is that the
  ! vocabulary is now restated in three places, and all three must be updated
  ! together when a kind is added:
  !   1. docs/m2/state-field-map.toml   -- the prose header, which defines it;
  !   2. tools/yl_state_map.py          -- DERIVED_RULES, enforcement on the map side;
  !   3. this list and known_rule below -- enforcement on the Fortran side.
  ! The proposal on the table is to have tools/yl_problem_check.py, which
  ! already cross-checks the map against the Fortran types fail-closed, also
  ! compare DERIVED_RULES against the MANIFEST_RULE_* constants parsed out of
  ! this file. That turns a divergence into a build failure instead of a
  ! manifest entry silently refused at run time.
  character(len=*), parameter, public :: MANIFEST_RULE_INDEX_MAP = 'index_map'
  character(len=*), parameter, public :: MANIFEST_RULE_COUNT = 'count'
  character(len=*), parameter, public :: MANIFEST_RULE_LEGACY_DEFAULT = 'legacy_default'
  character(len=*), parameter, public :: MANIFEST_RULE_DOF_EXPAND = 'dof_expand'
  character(len=*), parameter, public :: MANIFEST_RULE_RENUMBER = 'renumber'
  character(len=*), parameter, public :: MANIFEST_RULE_GEOMETRY = 'geometry'
  character(len=*), parameter, public :: MANIFEST_RULE_DECLARED_COUNT = 'declared_count'

  ! Verdicts of a declared_count entry.
  character(len=*), parameter, public :: MANIFEST_VERDICT_MATCH = 'match'
  character(len=*), parameter, public :: MANIFEST_VERDICT_MISMATCH = 'mismatch'

  ! Value encodings.
  character(len=*), parameter, public :: MANIFEST_DTYPE_NONE = 'none'
  character(len=*), parameter, public :: MANIFEST_DTYPE_I32 = 'i32'
  character(len=*), parameter, public :: MANIFEST_DTYPE_F64 = 'f64'
  character(len=*), parameter, public :: MANIFEST_DTYPE_BOOL = 'bool'
  character(len=*), parameter, public :: MANIFEST_DTYPE_STR = 'str'
  character(len=*), parameter, public :: MANIFEST_DTYPE_I32_LIST = 'i32[]'
  character(len=*), parameter, public :: MANIFEST_DTYPE_F64_LIST = 'f64[]'
  character(len=*), parameter, public :: MANIFEST_DTYPE_STR_LIST = 'str[]'

  integer, parameter :: LEN_MANIFEST_IOMSG = 512
  integer, parameter :: MANIFEST_FIRST_CAPACITY = 16

  ! One input path. A deferred-length component in a derived type is the only
  ! way to hold a ragged list of paths without a fixed width that would silently
  ! truncate a long one.
  type, public :: manifest_text_t
    character(len=:), allocatable :: s
  end type manifest_text_t

  ! A rendered value: its encoding and its exact text. The two are set together
  ! by the mv_* constructors and never separately, so a value can never carry a
  ! dtype that disagrees with how its text was produced.
  type, public :: manifest_value_t
    character(len=:), allocatable :: dtype
    character(len=:), allocatable :: text
  end type manifest_value_t

  type, public :: manifest_entry_t
    character(len=:), allocatable :: kind             ! derived / default / check
    character(len=:), allocatable :: rule             ! MANIFEST_RULE_*
    character(len=:), allocatable :: object           ! target object path
    character(len=:), allocatable :: field            ! target field on that object
    character(len=:), allocatable :: map_id           ! state-field-map row id, or ''
    type(manifest_value_t) :: value                   ! the produced / derived value
    type(manifest_value_t) :: expected                ! declared value (check only)
    character(len=:), allocatable :: verdict          ! match / mismatch, or ''
    type(manifest_text_t), allocatable :: inputs(:)   ! input fields actually read
    character(len=:), allocatable :: profile          ! default profile id, or ''
    character(len=:), allocatable :: profile_version  ! its version, or ''
  end type manifest_entry_t

  type, public :: manifest_t
    integer :: schema = MANIFEST_SCHEMA
    integer :: n = 0                                  ! entries in use
    logical :: bad = .false.                          ! sticky malformed-entry flag
    character(len=:), allocatable :: bad_reason
    type(manifest_entry_t), allocatable :: entries(:) ! size() is capacity, not count
  end type manifest_t

  ! Accumulator.
  public :: manifest_reset, manifest_free
  public :: manifest_add_derived, manifest_add_default, manifest_add_check
  public :: manifest_count, manifest_get, manifest_find
  public :: manifest_is_valid, manifest_error

  ! Value and input-list constructors.
  public :: mv_none, mv_i32, mv_f64, mv_bool, mv_str, mv_i32_list, mv_f64_list
  public :: mt_list, mt_none

  ! Rendering and the optional writer.
  public :: manifest_header, manifest_record, manifest_trailer
  public :: manifest_write, manifest_write_unit

contains

  ! ============================================================== rendering ==

  ! Decimal text of an int64, no blanks.
  pure function itoa(v) result(s)
    integer(int64), intent(in) :: v
    character(len=:), allocatable :: s
    character(len=24) :: buf
    write (buf, '(i0)') v
    s = trim(buf)
  end function itoa

  ! Escape one text field so that it contains no blank and no backslash: any
  ! byte outside printable non-blank ASCII (33..126), and the backslash itself,
  ! becomes \xHH. Trailing blanks are not part of the value and are dropped
  ! first, matching the trimmed-bytes convention of yl_state_io.
  pure function esc(raw) result(s)
    character(len=*), intent(in) :: raw
    character(len=:), allocatable :: s
    character(len=2) :: hex
    integer :: i, n, b, out, need

    n = len_trim(raw)
    need = 0
    do i = 1, n
      b = iachar(raw(i:i))
      if (b < 33 .or. b > 126 .or. b == 92) then
        need = need + 4
      else
        need = need + 1
      end if
    end do

    allocate (character(len=need) :: s)
    out = 0
    do i = 1, n
      b = iachar(raw(i:i))
      if (b < 33 .or. b > 126 .or. b == 92) then
        write (hex, '(z2.2)') b
        s(out + 1:out + 4) = '\x' // hex
        out = out + 4
      else
        out = out + 1
        s(out:out) = raw(i:i)
      end if
    end do
  end function esc

  ! One `key=value` token of a record.
  pure function kv(key, raw) result(s)
    character(len=*), intent(in) :: key, raw
    character(len=:), allocatable :: s
    s = key // '=' // esc(raw)
  end function kv

  ! Text of a character component that may be unallocated (an entry built by
  ! hand rather than by add_*). An unallocated component renders as empty
  ! rather than crashing the writer.
  pure function safe(s) result(t)
    character(len=:), allocatable, intent(in) :: s
    character(len=:), allocatable :: t
    if (allocated(s)) then
      t = s
    else
      t = ''
    end if
  end function safe

  ! ============================================== value / input constructors ==

  pure function mv_none() result(v)
    type(manifest_value_t) :: v
    v%dtype = MANIFEST_DTYPE_NONE
    v%text = ''
  end function mv_none

  pure function mv_i32(x) result(v)
    integer(int32), intent(in) :: x
    type(manifest_value_t) :: v
    v%dtype = MANIFEST_DTYPE_I32
    v%text = itoa(int(x, int64))
  end function mv_i32

  ! Exactly 16 hex digits of the IEEE binary64 bit pattern: no decimal rounding
  ! is involved, so the value round-trips bit for bit, and no floating-point
  ! operation is performed that could trap under -fpe0.
  pure function mv_f64(x) result(v)
    real(real64), intent(in) :: x
    type(manifest_value_t) :: v
    character(len=16) :: buf
    write (buf, '(z16.16)') transfer(x, 0_int64)
    v%dtype = MANIFEST_DTYPE_F64
    v%text = buf
  end function mv_f64

  pure function mv_bool(x) result(v)
    logical, intent(in) :: x
    type(manifest_value_t) :: v
    v%dtype = MANIFEST_DTYPE_BOOL
    if (x) then
      v%text = '1'
    else
      v%text = '0'
    end if
  end function mv_bool

  pure function mv_str(x) result(v)
    character(len=*), intent(in) :: x
    type(manifest_value_t) :: v
    v%dtype = MANIFEST_DTYPE_STR
    v%text = trim(x)
  end function mv_str

  ! An index map is a list, and at M3-02 sizes it is written out in full: a
  ! digest would make the entry unfalsifiable, which is the failure mode the
  ! plan's rule set is built to avoid.
  pure function mv_i32_list(x) result(v)
    integer(int32), intent(in) :: x(:)
    type(manifest_value_t) :: v
    character(len=:), allocatable :: body
    integer :: i
    body = ''
    do i = 1, size(x)
      if (i > 1) body = body // ','
      body = body // itoa(int(x(i), int64))
    end do
    v%dtype = MANIFEST_DTYPE_I32_LIST
    v%text = '[' // body // ']'
  end function mv_i32_list

  pure function mv_f64_list(x) result(v)
    real(real64), intent(in) :: x(:)
    type(manifest_value_t) :: v
    type(manifest_value_t) :: one
    character(len=:), allocatable :: body
    integer :: i
    body = ''
    do i = 1, size(x)
      if (i > 1) body = body // ','
      one = mv_f64(x(i))
      body = body // one%text
    end do
    v%dtype = MANIFEST_DTYPE_F64_LIST
    v%text = '[' // body // ']'
  end function mv_f64_list

  ! The empty input list: a derived value that reads nothing (a pure default).
  pure function mt_none() result(t)
    type(manifest_text_t), allocatable :: t(:)
    allocate (t(0))
  end function mt_none

  ! Input-path list built at the call site without a temporary array of a
  ! common length: mt_list('mesh.elements[].nodes', 'mesh.sets.elset').
  pure function mt_list(a, b, c, d, e, f, g, h) result(t)
    character(len=*), intent(in) :: a
    character(len=*), intent(in), optional :: b, c, d, e, f, g, h
    type(manifest_text_t), allocatable :: t(:)
    type(manifest_text_t) :: buf(8)
    integer :: n
    n = 1
    buf(1)%s = trim(a)
    if (present(b)) then
      n = n + 1
      buf(n)%s = trim(b)
    end if
    if (present(c)) then
      n = n + 1
      buf(n)%s = trim(c)
    end if
    if (present(d)) then
      n = n + 1
      buf(n)%s = trim(d)
    end if
    if (present(e)) then
      n = n + 1
      buf(n)%s = trim(e)
    end if
    if (present(f)) then
      n = n + 1
      buf(n)%s = trim(f)
    end if
    if (present(g)) then
      n = n + 1
      buf(n)%s = trim(g)
    end if
    if (present(h)) then
      n = n + 1
      buf(n)%s = trim(h)
    end if
    allocate (t(n))
    t(1:n) = buf(1:n)
  end function mt_list

  ! ============================================================ accumulator ==

  ! Drop every entry and clear the sticky flag. Safe on a fresh object.
  subroutine manifest_reset(m)
    type(manifest_t), intent(inout) :: m
    m%schema = MANIFEST_SCHEMA
    m%n = 0
    m%bad = .false.
    m%bad_reason = ''
    if (allocated(m%entries)) deallocate (m%entries)
  end subroutine manifest_reset

  subroutine manifest_free(m)
    type(manifest_t), intent(inout) :: m
    call manifest_reset(m)
  end subroutine manifest_free

  pure function manifest_count(m) result(n)
    type(manifest_t), intent(in) :: m
    integer :: n
    n = m%n
  end function manifest_count

  ! A manifest is valid while no add_* has been rejected. The writer refuses an
  ! invalid manifest rather than emitting evidence with a hole in it.
  pure function manifest_is_valid(m) result(ok)
    type(manifest_t), intent(in) :: m
    logical :: ok
    ok = .not. m%bad
  end function manifest_is_valid

  pure function manifest_error(m) result(s)
    type(manifest_t), intent(in) :: m
    character(len=:), allocatable :: s
    s = safe(m%bad_reason)
  end function manifest_error

  ! Copy out entry i. `found` is mandatory, following the opt_get discipline of
  ! yl_problem_optional: a caller cannot read an entry without declaring
  ! somewhere to receive the answer, and a miss yields a fully defined empty
  ! entry rather than undefined memory.
  subroutine manifest_get(m, i, entry, found)
    type(manifest_t), intent(in) :: m
    integer, intent(in) :: i
    type(manifest_entry_t), intent(out) :: entry
    logical, intent(out) :: found
    found = (i >= 1 .and. i <= m%n .and. allocated(m%entries))
    if (found) then
      entry = m%entries(i)
    else
      call blank_entry(entry)
    end if
  end subroutine manifest_get

  ! Index of the first entry targeting object/field, 0 when there is none.
  ! The self-test uses it to assert on a specific derived row without depending
  ! on the order in which finalize happens to emit rows.
  pure function manifest_find(m, object, field) result(i)
    type(manifest_t), intent(in) :: m
    character(len=*), intent(in) :: object, field
    integer :: i, k
    i = 0
    if (.not. allocated(m%entries)) return
    do k = 1, m%n
      if (safe(m%entries(k)%object) == trim(object) .and. &
          safe(m%entries(k)%field) == trim(field)) then
        i = k
        return
      end if
    end do
  end function manifest_find

  subroutine blank_entry(e)
    type(manifest_entry_t), intent(out) :: e
    e%kind = ''
    e%rule = ''
    e%object = ''
    e%field = ''
    e%map_id = ''
    e%value = mv_none()
    e%expected = mv_none()
    e%verdict = ''
    e%profile = ''
    e%profile_version = ''
    allocate (e%inputs(0))
  end subroutine blank_entry

  ! Grow to hold at least `want` entries, preserving the ones in use.
  subroutine ensure_capacity(m, want)
    type(manifest_t), intent(inout) :: m
    integer, intent(in) :: want
    type(manifest_entry_t), allocatable :: bigger(:)
    integer :: cap
    if (.not. allocated(m%entries)) then
      allocate (m%entries(max(MANIFEST_FIRST_CAPACITY, want)))
      return
    end if
    if (want <= size(m%entries)) return
    cap = max(2 * size(m%entries), want)
    allocate (bigger(cap))
    if (m%n > 0) bigger(1:m%n) = m%entries(1:m%n)
    call move_alloc(bigger, m%entries)
  end subroutine ensure_capacity

  pure function known_rule(rule) result(ok)
    character(len=*), intent(in) :: rule
    logical :: ok
    select case (trim(rule))
    ! The six map kinds plus declared_count. Adding a kind here means adding it
    ! to docs/m2/state-field-map.toml and to DERIVED_RULES in
    ! tools/yl_state_map.py in the same change.
    case (MANIFEST_RULE_INDEX_MAP, MANIFEST_RULE_COUNT, MANIFEST_RULE_LEGACY_DEFAULT, &
          MANIFEST_RULE_DOF_EXPAND, MANIFEST_RULE_RENUMBER, MANIFEST_RULE_GEOMETRY, &
          MANIFEST_RULE_DECLARED_COUNT)
      ok = .true.
    case default
      ok = .false.
    end select
  end function known_rule

  pure function known_dtype(dtype) result(ok)
    character(len=*), intent(in) :: dtype
    logical :: ok
    select case (trim(dtype))
    case (MANIFEST_DTYPE_NONE, MANIFEST_DTYPE_I32, MANIFEST_DTYPE_F64, MANIFEST_DTYPE_BOOL, &
          MANIFEST_DTYPE_STR, MANIFEST_DTYPE_I32_LIST, MANIFEST_DTYPE_F64_LIST, &
          MANIFEST_DTYPE_STR_LIST)
      ok = .true.
    case default
      ok = .false.
    end select
  end function known_dtype

  ! Record a rejected entry: sticky, first reason wins, nothing is stored.
  subroutine reject(m, why, stat)
    type(manifest_t), intent(inout) :: m
    character(len=*), intent(in) :: why
    integer, intent(out), optional :: stat
    if (.not. m%bad) then
      m%bad = .true.
      m%bad_reason = trim(why)
    end if
    if (present(stat)) stat = 1
  end subroutine reject

  ! Common part of every add_*: validate, grow, fill the shared columns.
  ! Returns the index of the new entry, or 0 when the entry was rejected.
  subroutine start_entry(m, kind, rule, object, field, value, inputs, map_id, idx, stat)
    type(manifest_t), intent(inout) :: m
    character(len=*), intent(in) :: kind, rule, object, field
    type(manifest_value_t), intent(in) :: value
    type(manifest_text_t), intent(in), optional :: inputs(:)
    character(len=*), intent(in), optional :: map_id
    integer, intent(out) :: idx
    integer, intent(out), optional :: stat
    integer :: k

    idx = 0
    if (present(stat)) stat = 0
    if (len_trim(object) == 0) then
      call reject(m, 'manifest entry with an empty object path (field "' // trim(field) // '")', stat)
      return
    end if
    if (len_trim(field) == 0) then
      call reject(m, 'manifest entry with an empty field name (object "' // trim(object) // '")', stat)
      return
    end if
    if (.not. known_rule(rule)) then
      call reject(m, 'unknown manifest rule "' // trim(rule) // '" for ' // &
                  trim(object) // '.' // trim(field), stat)
      return
    end if
    if (.not. allocated(value%dtype) .or. .not. allocated(value%text)) then
      call reject(m, 'manifest value of ' // trim(object) // '.' // trim(field) // &
                  ' was not built by an mv_* constructor', stat)
      return
    end if
    if (.not. known_dtype(value%dtype)) then
      call reject(m, 'unknown manifest dtype "' // value%dtype // '" for ' // &
                  trim(object) // '.' // trim(field), stat)
      return
    end if

    call ensure_capacity(m, m%n + 1)
    m%n = m%n + 1
    idx = m%n
    call blank_entry(m%entries(idx))
    m%entries(idx)%kind = trim(kind)
    m%entries(idx)%rule = trim(rule)
    m%entries(idx)%object = trim(object)
    m%entries(idx)%field = trim(field)
    m%entries(idx)%value = value
    if (present(map_id)) m%entries(idx)%map_id = trim(map_id)
    if (present(inputs)) then
      if (allocated(m%entries(idx)%inputs)) deallocate (m%entries(idx)%inputs)
      allocate (m%entries(idx)%inputs(size(inputs)))
      do k = 1, size(inputs)
        if (allocated(inputs(k)%s)) then
          m%entries(idx)%inputs(k)%s = trim(inputs(k)%s)
        else
          m%entries(idx)%inputs(k)%s = ''
        end if
      end do
    end if
  end subroutine start_entry

  ! A value produced by a derivation rule (index_map, count, dof_expand,
  ! renumber). `inputs` are the input FIELDS actually read to compute it, which
  ! is what makes the entry checkable: perturb one input and both the value and
  ! this line must change.
  subroutine manifest_add_derived(m, rule, object, field, value, inputs, map_id, stat)
    type(manifest_t), intent(inout) :: m
    character(len=*), intent(in) :: rule, object, field
    type(manifest_value_t), intent(in) :: value
    type(manifest_text_t), intent(in), optional :: inputs(:)
    character(len=*), intent(in), optional :: map_id
    integer, intent(out), optional :: stat
    integer :: idx
    call start_entry(m, MANIFEST_KIND_DERIVED, rule, object, field, value, inputs, map_id, idx, stat)
  end subroutine manifest_add_derived

  ! A value supplied by a versioned default profile. The profile id and version
  ! are mandatory: a default whose source cannot be named is exactly the
  ! untraceable magic number this manifest exists to eliminate. `rule` defaults
  ! to legacy_default and is an argument only so that M3-03 can record a default
  ! that a different rule kind supplied.
  subroutine manifest_add_default(m, object, field, value, profile, profile_version, &
                                  inputs, map_id, rule, stat)
    type(manifest_t), intent(inout) :: m
    character(len=*), intent(in) :: object, field
    type(manifest_value_t), intent(in) :: value
    character(len=*), intent(in) :: profile, profile_version
    type(manifest_text_t), intent(in), optional :: inputs(:)
    character(len=*), intent(in), optional :: map_id, rule
    integer, intent(out), optional :: stat
    character(len=:), allocatable :: use_rule
    integer :: idx

    if (present(stat)) stat = 0
    if (len_trim(profile) == 0 .or. len_trim(profile_version) == 0) then
      call reject(m, 'default for ' // trim(object) // '.' // trim(field) // &
                  ' carries no profile id or version', stat)
      return
    end if
    use_rule = MANIFEST_RULE_LEGACY_DEFAULT
    if (present(rule)) use_rule = trim(rule)

    call start_entry(m, MANIFEST_KIND_DEFAULT, use_rule, object, field, value, inputs, map_id, idx, stat)
    if (idx == 0) return
    m%entries(idx)%profile = trim(profile)
    m%entries(idx)%profile_version = trim(profile_version)
  end subroutine manifest_add_default

  ! A declared-count agreement check (V21): the deck declared `declared`, the
  ! objects yield `derived`. Both values and the verdict are recorded, so a
  ! PASSING check is still visible evidence -- a manifest that only showed
  ! failures could not distinguish "checked and agreed" from "never checked".
  ! The verdict is a comparison of the rendered encodings, so it is exact for
  ! f64 as well and cannot raise a trap under -fpe0.
  subroutine manifest_add_check(m, object, field, derived, declared, inputs, map_id, stat)
    type(manifest_t), intent(inout) :: m
    character(len=*), intent(in) :: object, field
    type(manifest_value_t), intent(in) :: derived, declared
    type(manifest_text_t), intent(in), optional :: inputs(:)
    character(len=*), intent(in), optional :: map_id
    integer, intent(out), optional :: stat
    integer :: idx

    if (present(stat)) stat = 0
    if (.not. allocated(declared%dtype) .or. .not. allocated(declared%text)) then
      call reject(m, 'declared value of the check on ' // trim(object) // '.' // trim(field) // &
                  ' was not built by an mv_* constructor', stat)
      return
    end if
    if (.not. known_dtype(declared%dtype)) then
      call reject(m, 'unknown manifest dtype "' // declared%dtype // '" for the declared value of ' // &
                  trim(object) // '.' // trim(field), stat)
      return
    end if

    call start_entry(m, MANIFEST_KIND_CHECK, MANIFEST_RULE_DECLARED_COUNT, object, field, &
                     derived, inputs, map_id, idx, stat)
    if (idx == 0) return
    m%entries(idx)%expected = declared
    if (declared%dtype == derived%dtype .and. declared%text == derived%text) then
      m%entries(idx)%verdict = MANIFEST_VERDICT_MATCH
    else
      m%entries(idx)%verdict = MANIFEST_VERDICT_MISMATCH
    end if
  end subroutine manifest_add_check

  ! ============================================================== rendering ==

  pure function manifest_header(m) result(line)
    type(manifest_t), intent(in) :: m
    character(len=:), allocatable :: line
    line = 'HSTAR_MANIFEST schema=' // itoa(int(m%schema, int64)) // &
           ' entries=' // itoa(int(m%n, int64))
  end function manifest_header

  pure function manifest_trailer(m) result(line)
    type(manifest_t), intent(in) :: m
    character(len=:), allocatable :: line
    line = 'HSTAR_MANIFEST_END entries=' // itoa(int(m%n, int64))
  end function manifest_trailer

  ! The exact bytes of one record. The writer emits nothing else, so the
  ! self-test can assert on a line without opening a file.
  pure function manifest_record(e, index) result(line)
    type(manifest_entry_t), intent(in) :: e
    integer, intent(in) :: index
    character(len=:), allocatable :: line, inputs
    integer :: k

    inputs = '['
    if (allocated(e%inputs)) then
      do k = 1, size(e%inputs)
        if (k > 1) inputs = inputs // ','
        inputs = inputs // esc(safe(e%inputs(k)%s))
      end do
    end if
    inputs = inputs // ']'

    line = 'entry=' // itoa(int(index, int64)) // &
           ' ' // kv('kind', safe(e%kind)) // &
           ' ' // kv('rule', safe(e%rule)) // &
           ' ' // kv('object', safe(e%object)) // &
           ' ' // kv('field', safe(e%field)) // &
           ' ' // kv('map', safe(e%map_id)) // &
           ' ' // kv('dtype', safe(e%value%dtype)) // &
           ' ' // kv('value', safe(e%value%text)) // &
           ' ' // kv('expected', safe(e%expected%text)) // &
           ' ' // kv('verdict', safe(e%verdict)) // &
           ' inputs=' // inputs // &
           ' ' // kv('profile', safe(e%profile)) // &
           ' ' // kv('profile_version', safe(e%profile_version))
  end function manifest_record

  ! ================================================================= writer ==

  ! Emit header, records and trailer on an already-open formatted unit. Every
  ! write is checked; the first failure stops the emission and reports through
  ! stat / errmsg, leaving the file without its trailer so it can never be read
  ! as complete.
  subroutine manifest_write_unit(m, unit, stat, errmsg)
    type(manifest_t), intent(in) :: m
    integer, intent(in) :: unit
    integer, intent(out) :: stat
    character(len=:), allocatable, intent(out), optional :: errmsg
    character(len=LEN_MANIFEST_IOMSG) :: iomsg
    integer :: ios, i

    stat = 0
    if (present(errmsg)) errmsg = ''
    if (m%bad) then
      stat = 2
      if (present(errmsg)) errmsg = 'refusing to write an invalid manifest: ' // manifest_error(m)
      return
    end if

    iomsg = ''
    write (unit, '(a)', iostat=ios, iomsg=iomsg) manifest_header(m)
    if (ios /= 0) then
      stat = 1
      if (present(errmsg)) errmsg = 'manifest header write failed: ' // trim(iomsg)
      return
    end if

    do i = 1, m%n
      write (unit, '(a)', iostat=ios, iomsg=iomsg) manifest_record(m%entries(i), i)
      if (ios /= 0) then
        stat = 1
        if (present(errmsg)) errmsg = 'manifest record ' // itoa(int(i, int64)) // &
                                      ' write failed: ' // trim(iomsg)
        return
      end if
    end do

    write (unit, '(a)', iostat=ios, iomsg=iomsg) manifest_trailer(m)
    if (ios /= 0) then
      stat = 1
      if (present(errmsg)) errmsg = 'manifest trailer write failed: ' // trim(iomsg)
    end if
  end subroutine manifest_write_unit

  ! Write the whole manifest to `path`, replacing it. Optional by construction:
  ! nothing in the pipeline calls this, and a manifest is fully usable without
  ! it. Opened access='stream', form='formatted' for the same two reasons as
  ! yl_state_io -- an index-map record has no RECL ceiling, and the record
  ! terminator is a single LF on every platform. Close is checked and the unit
  ! is always released, including on the failure path.
  subroutine manifest_write(m, path, stat, errmsg)
    type(manifest_t), intent(in) :: m
    character(len=*), intent(in) :: path
    integer, intent(out) :: stat
    character(len=:), allocatable, intent(out), optional :: errmsg
    character(len=LEN_MANIFEST_IOMSG) :: iomsg
    character(len=:), allocatable :: inner
    integer :: unit, ios

    stat = 0
    if (present(errmsg)) errmsg = ''
    if (len_trim(path) == 0) then
      stat = 3
      if (present(errmsg)) errmsg = 'empty manifest path'
      return
    end if
    if (m%bad) then
      stat = 2
      if (present(errmsg)) errmsg = 'refusing to write an invalid manifest: ' // manifest_error(m)
      return
    end if

    iomsg = ''
    open (newunit=unit, file=trim(path), status='replace', action='write', &
          access='stream', form='formatted', iostat=ios, iomsg=iomsg)
    if (ios /= 0) then
      stat = 1
      if (present(errmsg)) errmsg = 'cannot open the manifest file "' // trim(path) // '": ' // trim(iomsg)
      return
    end if

    call manifest_write_unit(m, unit, stat, inner)
    if (stat /= 0) then
      close (unit, iostat=ios)
      if (present(errmsg)) errmsg = inner
      return
    end if

    flush (unit, iostat=ios, iomsg=iomsg)
    if (ios /= 0) then
      stat = 1
      if (present(errmsg)) errmsg = 'manifest flush failed: ' // trim(iomsg)
      close (unit, iostat=ios)
      return
    end if

    close (unit, iostat=ios, iomsg=iomsg)
    if (ios /= 0) then
      stat = 1
      if (present(errmsg)) errmsg = 'manifest close failed: ' // trim(iomsg)
    end if
  end subroutine manifest_write

end module yl_problem_manifest
