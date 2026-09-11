! yl_authoring_keys -- the declared key table, and the contract validation that walks it.
!
! WHAT IT IS
!   One parameter array describing every key `docs/m5/authoring-contract.md` admits: its
!   path pattern, its type, whether the author MUST write it, and its allowed values when
!   the contract whitelists a set. Validation is then a walk over that table plus a walk
!   over the parsed store -- not a hand-written sequence of ifs, which is how a contract
!   and its checker drift apart.
!
! THE RULE THE `required` COLUMN ENCODES
!   The contract's operational test: a field may be optional only if it is NOT a physical
!   choice -- would changing its default change the result or its physical meaning? So
!   `material[].E` is required and `output.format` is required (it selects what the user
!   gets), while everything in the contract's default table never appears here at all,
!   because the author cannot write it.
!
!   Where it is ARGUABLE, the contract says prefer explicit. `section[].formulation` could
!   have defaulted to plane_strain -- there is exactly one on the whitelist -- and it is
!   required anyway, because plane strain vs plane stress is a modelling decision and
!   guessing it for the author is precisely what this input system exists to stop.
!
! WHAT A FAILURE LOOKS LIKE
!   A `problem_errors_t` finding, the same type the legacy adapter and the pipeline raise,
!   carrying `source = (file=case.toml, line=N)`, the key path, the value read and the
!   allowed set. Reusing that type rather than inventing an authoring-specific one is
!   deliberate: two error types would be two chances to disagree about what a verdict means.
!
! VERDICTS
!   INVALID_INPUT (exit 2): syntax already handled by the reader, plus unknown key, wrong
!     type, missing required key, dangling reference, duplicate name, wrong units/version.
!   UNSUPPORTED_CAPABILITY (exit 3): every key is well formed and every reference resolves,
!     but a value is outside the whitelist -- `element = "Q8"`.
!   The split matters to an operator: the first says "your file is wrong", the second says
!   "your file is fine and this build cannot do it".
module yl_authoring_keys

  use iso_fortran_env, only: int32, real64

  use yl_problem_errors, only: problem_errors_t, make_problem_error, make_source_location,   &
                               PE_INVALID_INPUT, PE_UNSUPPORTED, PE_MISSING_FIELD,           &
                               PE_DANGLING_REF, PE_DUPLICATE_REF,                            &
                               PE_EXIT_INPUT, PE_EXIT_UNSUPPORTED
  use yl_authoring_toml, only: toml_doc_t, TV_INT, TV_REAL, TV_STR, TV_BOOL, TOML_LEN_PATH

  implicit none
  private

  integer, parameter :: LEN_PAT = 48
  integer, parameter :: LEN_ALLOW = 120

  type :: key_t
    character(len=LEN_PAT) :: pattern = ''
    integer(int32) :: kind = 0_int32
    logical :: required = .false.
    !> `|`-separated whitelist, empty when the contract does not restrict the value.
    character(len=LEN_ALLOW) :: allowed = ''
  end type key_t

  ! The table. `[]` stands for any index. Order is the contract's order, so the two can be
  ! read side by side.
  type(key_t), parameter :: KEYS(*) = [                                                      &
    key_t('version',                       TV_INT,  .true.,  '1'),                           &
    key_t('case.name',                     TV_STR,  .true.,  ''),                            &
    key_t('case.units',                    TV_STR,  .true.,  'SI'),                          &
    key_t('case.description',              TV_STR,  .false., ''),                            &
    key_t('mesh.file',                     TV_STR,  .true.,  ''),                            &
    key_t('mesh.format',                   TV_STR,  .true.,  'hstar-legacy-cor-ele'),        &
    key_t('mesh.dimension',                TV_INT,  .true.,  '2'),                           &
    key_t('elset[].name',                  TV_STR,  .true.,  ''),                            &
    key_t('elset[].mesh_group',            TV_INT,  .true.,  ''),                            &
    key_t('nset[].name',                   TV_STR,  .true.,  ''),                            &
    key_t('nset[].nodes[]',                TV_INT,  .false., ''),                            &
    key_t('nset[].nodes.count',            TV_INT,  .true.,  ''),                            &
    key_t('material[].name',               TV_STR,  .true.,  ''),                            &
    key_t('material[].model',              TV_STR,  .true.,  'elastic_isotropic'),           &
    key_t('material[].density',            TV_REAL, .true.,  ''),                            &
    key_t('material[].E',                  TV_REAL, .true.,  ''),                            &
    key_t('material[].nu',                 TV_REAL, .true.,  ''),                            &
    key_t('section[].name',                TV_STR,  .true.,  ''),                            &
    key_t('section[].elset',               TV_STR,  .true.,  ''),                            &
    key_t('section[].element',             TV_STR,  .true.,  'Q4'),                          &
    key_t('section[].formulation',         TV_STR,  .true.,  'plane_strain'),                &
    key_t('section[].material',            TV_STR,  .true.,  ''),                            &
    key_t('amplitude[].name',              TV_STR,  .true.,  ''),                            &
    key_t('amplitude[].type',              TV_STR,  .true.,  'linear'),                      &
    key_t('amplitude[].points[][]',        TV_REAL, .false., ''),                            &
    key_t('amplitude[].points[].count',    TV_INT,  .false., ''),                            &
    key_t('amplitude[].points.count',      TV_INT,  .true.,  ''),                            &
    key_t('step[].name',                   TV_STR,  .true.,  ''),                            &
    key_t('step[].procedure',              TV_STR,  .true.,  'static'),                      &
    key_t('step[].controls.increments',    TV_INT,  .true.,  '1'),                           &
    key_t('step[].controls.max_iterations', TV_INT, .true.,  ''),                            &
    key_t('step[].controls.tolerance_force', TV_REAL, .true., ''),                           &
    key_t('step[].controls.tolerance_dof', TV_REAL, .true.,  ''),                            &
    key_t('step[].boundary[].nset',        TV_STR,  .true.,  ''),                            &
    key_t('step[].boundary[].dof[]',       TV_INT,  .false., '1|2'),                         &
    key_t('step[].boundary[].dof.count',   TV_INT,  .true.,  ''),                            &
    key_t('step[].boundary[].value',       TV_REAL, .true.,  ''),                            &
    key_t('step[].load.gravity.magnitude', TV_REAL, .true.,  ''),                            &
    key_t('step[].load.gravity.direction[]', TV_REAL, .false., ''),                          &
    key_t('step[].load.gravity.direction.count', TV_INT, .true., '2'),                       &
    key_t('step[].load.gravity.amplitude', TV_STR,  .true.,  ''),                            &
    key_t('solver.linear',                 TV_STR,  .true.,  'profile'),                     &
    key_t('output.format',                 TV_STR,  .true.,  'gid'),                         &
    key_t('output.field[]',                TV_STR,  .false., 'u|s'),                         &
    key_t('output.field.count',            TV_INT,  .true.,  '')]

  public :: authoring_validate, authoring_key_count, authoring_key_pattern

contains

  pure integer function authoring_key_count() result(n)
    n = size(KEYS)
  end function authoring_key_count

  pure function authoring_key_pattern(i) result(p)
    integer, intent(in) :: i
    character(len=LEN_PAT) :: p
    p = KEYS(i)%pattern
  end function authoring_key_pattern

  !> Validate `doc` against the contract. Every finding carries the line it came from.
  subroutine authoring_validate(doc, file, errors)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: file
    type(problem_errors_t), intent(inout) :: errors

    integer(int32) :: i
    integer :: k
    character(len=TOML_LEN_PATH) :: np

    ! --- every key present was declared, and has the declared type -----------------
    do i = 1_int32, doc%n
      np = normalise(doc%entry(i)%path)
      k = slot(np)
      if (k == 0) then
        call raise(errors, PE_INVALID_INPUT, PE_EXIT_INPUT, file, doc%entry(i)%line,        &
                   trim(doc%entry(i)%path), 'unknown key; the authoring contract admits '//  &
                   'no such field', '', '')
        cycle
      end if
      if (doc%entry(i)%kind /= KEYS(k)%kind) then
        call raise(errors, PE_INVALID_INPUT, PE_EXIT_INPUT, file, doc%entry(i)%line,        &
                   trim(doc%entry(i)%path), 'wrong type', kind_name(doc%entry(i)%kind),      &
                   kind_name(KEYS(k)%kind))
        cycle
      end if
      if (len_trim(KEYS(k)%allowed) > 0) then
        call check_allowed(doc, i, KEYS(k), file, errors)
      end if
    end do

    ! --- every required key is present, per collection element ---------------------
    do k = 1, size(KEYS)
      if (.not. KEYS(k)%required) cycle
      call require_all(doc, KEYS(k)%pattern, file, errors)
    end do

    ! --- names unique, references resolve -----------------------------------------
    call unique_names(doc, 'elset', file, errors)
    call unique_names(doc, 'nset', file, errors)
    call unique_names(doc, 'material', file, errors)
    call unique_names(doc, 'section', file, errors)
    call unique_names(doc, 'amplitude', file, errors)
    call unique_names(doc, 'step', file, errors)

    call resolve(doc, 'section', 'elset', 'elset', file, errors)
    call resolve(doc, 'section', 'material', 'material', file, errors)
    call resolve_nested(doc, 'step', 'boundary', 'nset', 'nset', file, errors)
    call resolve_step_amplitude(doc, file, errors)

    ! --- the one arity the contract fixes -----------------------------------------
    if (doc%count_of('step') /= 1_int32) then
      call raise(errors, PE_UNSUPPORTED, PE_EXIT_UNSUPPORTED, file, 0_int32, 'step',         &
                 'this build supports exactly one analysis step', itoa(doc%count_of('step')), &
                 '1')
    end if
  end subroutine authoring_validate

  ! ------------------------------------------------------------------ checks ----

  subroutine check_allowed(doc, i, key, file, errors)
    type(toml_doc_t), intent(in) :: doc
    integer(int32), intent(in) :: i
    type(key_t), intent(in) :: key
    character(len=*), intent(in) :: file
    type(problem_errors_t), intent(inout) :: errors
    character(len=LEN_ALLOW) :: got
    select case (doc%entry(i)%kind)
    case (TV_STR);  got = doc%entry(i)%svalue
    case (TV_INT);  got = itoa(doc%entry(i)%ivalue)
    case default;   return   ! the contract whitelists only strings and small integers
    end select
    if (in_list(trim(got), trim(key%allowed))) return
    ! A well-formed value outside the whitelist is a CAPABILITY verdict, not a malformed
    ! file: the operator's file is fine and this build cannot do what it asks.
    call raise(errors, PE_UNSUPPORTED, PE_EXIT_UNSUPPORTED, file, doc%entry(i)%line,         &
               trim(doc%entry(i)%path), 'value is outside this build''s whitelist',          &
               trim(got), trim(key%allowed))
  end subroutine check_allowed

  !> Require `pattern` for every concrete index combination the document actually has.
  subroutine require_all(doc, pattern, file, errors)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: pattern
    character(len=*), intent(in) :: file
    type(problem_errors_t), intent(inout) :: errors
    integer(int32) :: n1, n2, a, b
    character(len=TOML_LEN_PATH) :: p1, p2
    character(len=LEN_PAT) :: head

    if (index(pattern, '[]') == 0) then
      if (doc%find(pattern) == 0_int32) then
        call missing(errors, file, pattern)
      end if
      return
    end if

    head = pattern(1:index(pattern, '[]') - 1)
    n1 = doc%count_of(trim(head))
    if (n1 == 0_int32) then
      ! An absent collection is only a defect when the contract requires the collection
      ! itself; `step` is checked by its own arity rule, the rest may legitimately be
      ! empty and the mapping layer will say so if it needs one.
      return
    end if
    do a = 1_int32, n1
      p1 = subst_first(pattern, a)
      if (index(p1, '[]') == 0) then
        if (doc%find(trim(p1)) == 0_int32) call missing(errors, file, trim(p1))
        cycle
      end if
      head = p1(1:index(p1, '[]') - 1)
      n2 = doc%count_of(trim(head))
      do b = 1_int32, n2
        p2 = subst_first(trim(p1), b)
        if (index(p2, '[]') /= 0) cycle   ! three index levels: not in this contract
        if (doc%find(trim(p2)) == 0_int32) call missing(errors, file, trim(p2))
      end do
    end do
  end subroutine require_all

  subroutine unique_names(doc, collection, file, errors)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: collection, file
    type(problem_errors_t), intent(inout) :: errors
    integer(int32) :: n, a, b, ka, kb
    n = doc%count_of(collection)
    do a = 1_int32, n
      ka = doc%find(trim(collection)//'['//trim(itoa(a))//'].name')
      if (ka == 0_int32) cycle
      do b = a + 1_int32, n
        kb = doc%find(trim(collection)//'['//trim(itoa(b))//'].name')
        if (kb == 0_int32) cycle
        if (trim(doc%entry(ka)%svalue) == trim(doc%entry(kb)%svalue)) then
          call raise(errors, PE_DUPLICATE_REF, PE_EXIT_INPUT, file, doc%entry(kb)%line,      &
                     trim(collection)//'['//trim(itoa(b))//'].name',                         &
                     'duplicate name in this collection; references are by name, so two '//  &
                     'entries with one name have no meaning',                                &
                     trim(doc%entry(kb)%svalue), 'a name not already used')
        end if
      end do
    end do
  end subroutine unique_names

  subroutine resolve(doc, from, field, to, file, errors)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: from, field, to, file
    type(problem_errors_t), intent(inout) :: errors
    integer(int32) :: n, a, k
    n = doc%count_of(from)
    do a = 1_int32, n
      k = doc%find(trim(from)//'['//trim(itoa(a))//'].'//trim(field))
      if (k == 0_int32) cycle
      if (.not. name_exists(doc, to, trim(doc%entry(k)%svalue))) then
        call raise(errors, PE_DANGLING_REF, PE_EXIT_INPUT, file, doc%entry(k)%line,         &
                   trim(from)//'['//trim(itoa(a))//'].'//trim(field),                        &
                   'refers to a '//trim(to)//' that this file does not define',              &
                   trim(doc%entry(k)%svalue), 'a declared [['//trim(to)//']] name')
      end if
    end do
  end subroutine resolve

  subroutine resolve_nested(doc, outer, inner, field, to, file, errors)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: outer, inner, field, to, file
    type(problem_errors_t), intent(inout) :: errors
    integer(int32) :: no, ni, a, b, k
    character(len=TOML_LEN_PATH) :: base
    no = doc%count_of(outer)
    do a = 1_int32, no
      base = trim(outer)//'['//trim(itoa(a))//'].'//trim(inner)
      ni = doc%count_of(trim(base))
      do b = 1_int32, ni
        k = doc%find(trim(base)//'['//trim(itoa(b))//'].'//trim(field))
        if (k == 0_int32) cycle
        if (.not. name_exists(doc, to, trim(doc%entry(k)%svalue))) then
          call raise(errors, PE_DANGLING_REF, PE_EXIT_INPUT, file, doc%entry(k)%line,       &
                     trim(base)//'['//trim(itoa(b))//'].'//trim(field),                      &
                     'refers to a '//trim(to)//' that this file does not define',            &
                     trim(doc%entry(k)%svalue), 'a declared [['//trim(to)//']] name')
        end if
      end do
    end do
  end subroutine resolve_nested

  subroutine resolve_step_amplitude(doc, file, errors)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: file
    type(problem_errors_t), intent(inout) :: errors
    integer(int32) :: n, a, k
    n = doc%count_of('step')
    do a = 1_int32, n
      k = doc%find('step['//trim(itoa(a))//'].load.gravity.amplitude')
      if (k == 0_int32) cycle
      if (.not. name_exists(doc, 'amplitude', trim(doc%entry(k)%svalue))) then
        call raise(errors, PE_DANGLING_REF, PE_EXIT_INPUT, file, doc%entry(k)%line,         &
                   'step['//trim(itoa(a))//'].load.gravity.amplitude',                       &
                   'refers to an amplitude that this file does not define',                  &
                   trim(doc%entry(k)%svalue), 'a declared [[amplitude]] name')
      end if
    end do
  end subroutine resolve_step_amplitude

  ! ------------------------------------------------------------------ helpers ----

  pure logical function name_exists(doc, collection, want) result(found)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: collection, want
    integer(int32) :: n, a, k
    found = .false.
    n = doc%count_of(collection)
    do a = 1_int32, n
      k = doc%find(trim(collection)//'['//trim(itoa(a))//'].name')
      if (k == 0_int32) cycle
      if (trim(doc%entry(k)%svalue) == trim(want)) then
        found = .true.
        return
      end if
    end do
  end function name_exists

  subroutine missing(errors, file, path)
    type(problem_errors_t), intent(inout) :: errors
    character(len=*), intent(in) :: file, path
    call raise(errors, PE_MISSING_FIELD, PE_EXIT_INPUT, file, 0_int32, path,                 &
               'required by the authoring contract and not present. It is required '//       &
               'because it is a physical choice: this build will not guess it', '', '')
  end subroutine missing

  subroutine raise(errors, code, exit_class, file, line, path, msg, actual, expected)
    type(problem_errors_t), intent(inout) :: errors
    character(len=*), intent(in) :: code, file, path, msg, actual, expected
    integer(int32), intent(in) :: exit_class, line
    if (line > 0_int32) then
      call errors%add(make_problem_error(code=code, stage='authoring',                       &
           object_path=path, message=msg, actual=actual, expected=expected,                  &
           exit_class=exit_class,                                                            &
           source=make_source_location(file=file, reader='case.toml', line=line)))
    else
      call errors%add(make_problem_error(code=code, stage='authoring',                       &
           object_path=path, message=msg, actual=actual, expected=expected,                  &
           exit_class=exit_class, source=make_source_location(file=file, reader='case.toml')))
    end if
  end subroutine raise

  !> `material[2].E` -> `material[].E`; indices are positions, not identity.
  pure function normalise(path) result(out)
    character(len=*), intent(in) :: path
    character(len=TOML_LEN_PATH) :: out
    integer :: i
    logical :: skipping
    out = ''
    skipping = .false.
    do i = 1, len_trim(path)
      if (path(i:i) == '[') then
        skipping = .true.
        out = trim(out)//'[]'
        cycle
      end if
      if (path(i:i) == ']') then
        skipping = .false.
        cycle
      end if
      if (.not. skipping) out = trim(out)//path(i:i)
    end do
  end function normalise

  pure integer function slot(np) result(k)
    character(len=*), intent(in) :: np
    integer :: i
    k = 0
    do i = 1, size(KEYS)
      if (trim(KEYS(i)%pattern) == trim(np)) then
        k = i
        return
      end if
    end do
  end function slot

  pure function subst_first(pattern, idx) result(out)
    character(len=*), intent(in) :: pattern
    integer(int32), intent(in) :: idx
    character(len=TOML_LEN_PATH) :: out
    integer :: p
    p = index(pattern, '[]')
    out = pattern(1:p - 1)//'['//trim(itoa(idx))//']'//trim(pattern(p + 2:))
  end function subst_first

  pure logical function in_list(want, list) result(found)
    character(len=*), intent(in) :: want, list
    integer :: p, q
    found = .false.
    p = 1
    do
      q = index(list(p:), '|')
      if (q == 0) then
        found = (trim(list(p:)) == trim(want))
        return
      end if
      if (trim(list(p:p + q - 2)) == trim(want)) then
        found = .true.
        return
      end if
      p = p + q
    end do
  end function in_list

  pure function kind_name(k) result(s)
    integer(int32), intent(in) :: k
    character(len=:), allocatable :: s
    select case (k)
    case (TV_INT);  s = 'integer'
    case (TV_REAL); s = 'real'
    case (TV_STR);  s = 'string'
    case (TV_BOOL); s = 'boolean'
    case default;   s = 'unknown'
    end select
  end function kind_name

  pure function itoa(v) result(out)
    integer(int32), intent(in) :: v
    character(len=12) :: buf
    character(len=:), allocatable :: out
    write (buf, '(i0)') v
    out = trim(buf)
  end function itoa

end module yl_authoring_keys
