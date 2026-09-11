! yl_authoring_test -- the contract validator's counter-examples, one per check.
!
! Shape borrowed from the M4 dialect suite, and for the same reason: a validator is only
! worth what its counter-examples are worth. Each case takes a REAL golden case.toml,
! changes one line, and asserts three things -- the verdict, the exit class, and that the
! finding names the line and the key. The third is not decoration: `docs/m5/authoring-
! contract.md` makes "carries the line and the key path" part of the acceptance criterion,
! so a check that fires with a vague message has not passed.
!
! It also asserts that the UNCHANGED deck validates clean. A suite that only ever sees bad
! input cannot tell a working validator from one that rejects everything.
program yl_authoring_test

  use iso_fortran_env, only: int32, output_unit, error_unit

  use yl_problem_errors, only: problem_errors_t
  use yl_authoring_toml, only: toml_doc_t, toml_read
  use yl_authoring_keys, only: authoring_validate
  use yl_authoring_report, only: authoring_render

  implicit none

  integer :: pass, fail
  character(len=512) :: deck, scratch, mode
  logical :: clean_only

  pass = 0
  fail = 0
  call read_arguments(deck, scratch, mode)
  ! --clean-only: for a deck that cannot carry every counter-example. cooks_membrane has
  ! one nset, so no single-line mutation can produce a duplicate NAME within a collection;
  ! running the full suite there would need a conditional skip, and a skipped check that
  ! still prints is how a suite quietly stops testing something.
  clean_only = (trim(mode) == '--clean-only')

  write (output_unit, '(a)') '== yl_authoring_test =='
  write (output_unit, '(a)') '   deck    : '//trim(deck)
  write (output_unit, '(a)') '   scratch : '//trim(scratch)

  write (output_unit, '(a)') '-- the unchanged deck validates clean'
  call expect_clean(deck)

  if (clean_only) then
    write (output_unit, '(a)') '-- counter-examples: not on this deck (--clean-only)'
    write (output_unit, '(a)') ''
    write (output_unit, '(a,i0,a,i0,a)') '-- ', pass, '/', pass + fail, ' checks passed'
    if (fail > 0) then
      write (output_unit, '(a,i0,a)') '== FAIL (', fail, ' checks failed) =='
      error stop 1
    end if
    write (output_unit, '(a)') '== PASS =='
    stop
  end if

  write (output_unit, '(a)') '-- counter-examples, one per check'
  ! unknown key
  call expect_bad('unknown key', 'nu      =', 'nu_typo = 0.2', 'INVALID_INPUT', 2, 'nu_typo')
  ! wrong type
  call expect_bad('wrong type', 'density = 2400.0', 'density = "heavy"', 'INVALID_INPUT', 2, 'density')
  ! missing required (a physical choice)
  call expect_bad('missing physical choice', 'E       = 2.5e10', '# E removed', &
                  'MISSING_FIELD', 2, 'E')
  ! outside the whitelist -> capability, not malformed
  call expect_bad('outside whitelist', 'element     = "Q4"', 'element     = "Q8"', &
                  'UNSUPPORTED', 3, 'element')
  ! dangling reference
  call expect_bad('dangling reference', 'material    = "concrete"', 'material    = "steel"', &
                  'DANGLING_REF', 2, 'material')
  ! duplicate name WITHIN one collection -- the suite deck must have two nsets, which is
  ! why the build target runs it on lame_cylinder.
  call expect_bad('duplicate name', 'name  = "sym_x0"', 'name  = "sym_y0"', &
                  'DUPLICATE_REF', 2, 'nset[2].name')
  ! units must be SI, and it is a whitelist so the verdict is capability
  call expect_bad('non-SI units', 'units       = "SI"', 'units       = "imperial"', &
                  'UNSUPPORTED', 3, 'units')
  ! a value the reader itself cannot read
  call expect_bad('unreadable value', 'increments      = 1', 'increments      = @@@', &
                  'INVALID_INPUT', 2, 'increments')

  write (output_unit, '(a)') ''
  write (output_unit, '(a,i0,a,i0,a)') '-- ', pass, '/', pass + fail, ' checks passed'
  if (fail > 0) then
    write (output_unit, '(a,i0,a)') '== FAIL (', fail, ' checks failed) =='
    error stop 1
  end if
  write (output_unit, '(a)') '== PASS =='

contains

  subroutine expect_clean(path)
    character(len=*), intent(in) :: path
    type(toml_doc_t) :: doc
    type(problem_errors_t) :: errors
    integer :: i
    call toml_read(path, doc)
    if (doc%failed) then
      call check('the unchanged deck parses', .false.)
      write (error_unit, '(a,i0,a)') '   parse failed at line ', doc%fail_line, ': '// &
        trim(doc%message)
      return
    end if
    call authoring_validate(doc, path, errors)
    call check('the unchanged deck validates clean', .not. errors%any())
    do i = 1, errors%count()
      write (error_unit, '(a)') '   unexpected: '//authoring_render(errors, i)
    end do
  end subroutine expect_clean

  !> Copy the deck, replacing the first line that contains `from` with `to`, then assert
  !> the validator's verdict. `from` must match exactly one line: a mutation that lands
  !> somewhere unintended would test something other than what its name says.
  subroutine expect_bad(what, from, to, want_code, want_exit, want_path)
    character(len=*), intent(in) :: what, from, to, want_code, want_path
    integer, intent(in) :: want_exit
    type(toml_doc_t) :: doc
    type(problem_errors_t) :: errors
    character(len=512) :: out
    integer :: hits, changed_line, i
    logical :: got_code, got_path, got_line

    out = trim(scratch)//'/case.toml'
    call mutate(deck, out, from, to, hits, changed_line)
    if (hits /= 1) then
      call check(what//': the mutation matches exactly one line', .false.)
      write (error_unit, '(a,i0,a)') '   matched ', hits, ' lines for "'//trim(from)//'"'
      return
    end if

    call toml_read(out, doc)
    if (doc%failed) then
      ! A value the reader cannot read is INVALID_INPUT too, and the reader carries the
      ! line; that is the same contract, met one layer earlier.
      call check(what//': rejected with a line', doc%fail_line == changed_line)
      if (doc%fail_line /= changed_line) then
        write (error_unit, '(a,i0,a,i0)') '   line ', doc%fail_line, ' expected ', changed_line
      end if
      return
    end if
    call authoring_validate(doc, out, errors)
    if (.not. errors%any()) then
      call check(what//': rejected', .false.)
      return
    end if

    got_code = .false.
    got_path = .false.
    got_line = .false.
    do i = 1, errors%count()
      if (index(authoring_render(errors, i), trim(want_code)) > 0) got_code = .true.
      if (index(authoring_render(errors, i), trim(want_path)) > 0) got_path = .true.
      if (index(authoring_render(errors, i), ':'//trim(itoa(changed_line))//':') > 0) &
        got_line = .true.
    end do
    call check(what//': verdict is '//trim(want_code), got_code)
    call check(what//': names the key', got_path)
    if (want_code /= 'MISSING_FIELD') then
      ! A missing key has no line of its own -- that is the honest answer, and the
      ! contract asks for the key path there instead.
      call check(what//': names the line', got_line)
    end if
    call check(what//': exit class is '//trim(itoa(want_exit)), &
               errors%exit_code() == int(want_exit, int32))
    if (errors%exit_code() /= int(want_exit, int32)) then
      do i = 1, errors%count()
        write (error_unit, '(a)') '   got: '//authoring_render(errors, i)
      end do
    end if
  end subroutine expect_bad

  subroutine mutate(src, dst, from, to, hits, changed_line)
    character(len=*), intent(in) :: src, dst, from, to
    integer, intent(out) :: hits, changed_line
    integer :: ui, uo, ios, n
    character(len=1024) :: line
    hits = 0
    changed_line = 0
    open (newunit=ui, file=src, status='old', action='read')
    open (newunit=uo, file=dst, status='replace', action='write')
    n = 0
    do
      read (ui, '(a)', iostat=ios) line
      if (ios /= 0) exit
      n = n + 1
      if (index(line, from) > 0) then
        hits = hits + 1
        if (hits == 1) then
          changed_line = n
          write (uo, '(a)') trim(to)
          cycle
        end if
      end if
      write (uo, '(a)') trim(line)
    end do
    close (ui)
    close (uo)
  end subroutine mutate

  subroutine check(what, ok)
    character(len=*), intent(in) :: what
    logical, intent(in) :: ok
    if (ok) then
      pass = pass + 1
      write (output_unit, '(a)') '   ok   '//what
    else
      fail = fail + 1
      write (output_unit, '(a)') '   FAIL '//what
    end if
  end subroutine check

  subroutine read_arguments(d, s, m)
    character(len=*), intent(out) :: d, s, m
    integer :: l
    call get_command_argument(1, d, l)
    if (l <= 0) then
      write (error_unit, '(a)') 'usage: yl_authoring_test <case.toml> <scratch> [--clean-only]'
      error stop 2
    end if
    call get_command_argument(2, s, l)
    if (l <= 0) then
      write (error_unit, '(a)') 'usage: yl_authoring_test <case.toml> <scratch> [--clean-only]'
      error stop 2
    end if
    m = ''
    call get_command_argument(3, m, l)
  end subroutine read_arguments

  pure function itoa(v) result(out)
    integer, intent(in) :: v
    character(len=12) :: buf
    character(len=:), allocatable :: out
    write (buf, '(i0)') v
    out = trim(buf)
  end function itoa

end program yl_authoring_test
