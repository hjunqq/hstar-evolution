! yl_problem_selftest -- type-level self-test for the M3-01 optional wrappers.
!
! Asserts the ADR-0002 three-state contract of yl_problem_optional: "unset", an
! explicit zero (or empty string) and an empty collection are distinct and
! cannot be confused. Prints one line per check and a final PASS/FAIL summary;
! exits 1 on any failure so a build script can gate on it. The summary goes to
! stdout; on failure `stop 1` additionally makes ifx echo "1" on stderr, so a
! caller that parses output should read stdout only.
!
! Build and run standalone (no solver objects involved):
!   source tools/env.sh
!   "$HSTAR_FC" -warn all -stand f18 -module <dir> -o <dir>/selftest \
!       src/problem/yl_problem_optional.f90 src/problem/yl_problem_selftest.f90
!   <dir>/selftest
! Also run under the strict profile flags of tools/build.sh
! (-O0 -g -traceback -check bounds,pointers -init=snan,arrays -fpe0): the
! wrappers must stay unset and trap-free when uninitialised memory is poisoned.
program yl_problem_selftest

  use iso_fortran_env, only: int32, int64, real64, output_unit
  use yl_problem_optional, only: opt_int, opt_real, opt_text, opt_logical, &
                                 opt_set, opt_get, opt_is_set, opt_clear,  &
                                 opt_value_or, opt_equal

  implicit none

  integer :: n_check = 0
  integer :: n_fail = 0

  ! Default-initialised subjects: never assigned before they are inspected, so
  ! that -init=snan,arrays has every chance to make them look set.
  type(opt_int) :: i_unset, i_zero, i_other
  type(opt_real) :: r_unset, r_zero, r_other, r_nan_a, r_nan_b
  type(opt_text) :: t_unset, t_empty, t_word
  type(opt_logical) :: l_unset, l_false, l_true
  ! Second, independently declared unset objects: opt_equal must call an unset
  ! optional equal to any other unset optional of the same kind.
  type(opt_int) :: i_unset2
  type(opt_real) :: r_unset2
  type(opt_text) :: t_unset2
  type(opt_logical) :: l_unset2

  integer(int32) :: iv
  real(real64) :: rv
  logical :: lv, found
  character(len=:), allocatable :: tv
  integer(int32), allocatable :: ids(:)
  real(real64) :: nan

  write (output_unit, '(a)') 'yl_problem_selftest: optional wrapper three-state contract'

  ! --- 1. a default-initialised optional is unset, for all four kinds ---------
  call check('int   default-initialised is unset', .not. opt_is_set(i_unset))
  call check('real  default-initialised is unset', .not. opt_is_set(r_unset))
  call check('text  default-initialised is unset', .not. opt_is_set(t_unset))
  call check('log   default-initialised is unset', .not. opt_is_set(l_unset))

  ! --- 2. an explicit zero is set, and is not the same thing as unset ---------
  call opt_set(i_zero, 0_int32)
  call opt_set(r_zero, 0.0_real64)
  call opt_set(l_false, .false.)
  call check('int   explicit zero is set', opt_is_set(i_zero))
  call check('real  explicit zero is set', opt_is_set(r_zero))
  call check('log   explicit .false. is set', opt_is_set(l_false))
  call check('int   explicit zero /= unset', .not. opt_equal(i_zero, i_unset))
  call check('real  explicit zero /= unset', .not. opt_equal(r_zero, r_unset))
  call check('log   explicit .false. /= unset', .not. opt_equal(l_false, l_unset))

  ! --- 3. opt_clear returns to unset -----------------------------------------
  call opt_clear(i_zero)
  call check('int   opt_clear returns to unset', .not. opt_is_set(i_zero) .and. opt_equal(i_zero, i_unset))
  call opt_clear(r_zero)
  call check('real  opt_clear returns to unset', .not. opt_is_set(r_zero) .and. opt_equal(r_zero, r_unset))
  call opt_set(t_word, 'plane_strain')
  call opt_clear(t_word)
  call check('text  opt_clear returns to unset', .not. opt_is_set(t_word) .and. opt_equal(t_word, t_unset))
  call opt_clear(l_false)
  call check('log   opt_clear returns to unset', .not. opt_is_set(l_false) .and. opt_equal(l_false, l_unset))

  ! --- 4. opt_get on an unset optional: not found, output still defined -------
  ! Under -init=snan,arrays -fpe0 an undefined real output would trap on use;
  ! the neutral value below must come back intact instead.
  iv = 12345_int32
  call opt_get(i_unset, iv, found)
  call check('int   opt_get unset -> not found, value 0', (.not. found) .and. iv == 0_int32)
  rv = 12345.0_real64
  call opt_get(r_unset, rv, found)
  call check('real  opt_get unset -> not found, value 0.0', (.not. found) .and. rv == 0.0_real64)
  call opt_get(t_unset, tv, found)
  call check('text  opt_get unset -> not found, allocated len 0', &
             (.not. found) .and. allocated(tv))
  if (allocated(tv)) call check('text  opt_get unset -> zero-length string', len(tv) == 0)
  lv = .true.
  call opt_get(l_unset, lv, found)
  call check('log   opt_get unset -> not found, value .false.', (.not. found) .and. (.not. lv))

  ! --- 5. opt_get on a set optional returns the payload ----------------------
  call opt_set(i_other, 7_int32)
  call opt_get(i_other, iv, found)
  call check('int   opt_get set -> found, payload 7', found .and. iv == 7_int32)
  call opt_set(r_other, -2.5_real64)
  call opt_get(r_other, rv, found)
  call check('real  opt_get set -> found, payload -2.5', found .and. rv == -2.5_real64)

  ! --- 6. opt_value_or substitutes only when unset ---------------------------
  call check('int   opt_value_or unset -> default', opt_value_or(i_unset, 99_int32) == 99_int32)
  call check('int   opt_value_or set -> payload', opt_value_or(i_other, 99_int32) == 7_int32)
  call opt_set(r_zero, 0.0_real64)
  call check('real  opt_value_or unset -> default', opt_value_or(r_unset, 9.5_real64) == 9.5_real64)
  call check('real  opt_value_or explicit zero -> 0.0 not default', opt_value_or(r_zero, 9.5_real64) == 0.0_real64)
  call check('text  opt_value_or unset -> default', opt_value_or(t_unset, 'fallback') == 'fallback')
  call check('log   opt_value_or unset -> default', opt_value_or(l_unset, .true.))
  call opt_set(l_true, .true.)
  call opt_set(l_false, .false.)
  call check('log   opt_value_or explicit .false. -> .false. not default', .not. opt_value_or(l_false, .true.))
  call check('log   opt_value_or set .true. -> .true.', opt_value_or(l_true, .false.))

  ! --- 7. opt_equal: unset/unset equal, set/unset different ------------------
  call check('int   opt_equal two unsets are equal', opt_equal(i_unset, i_unset2))
  call check('real  opt_equal two unsets are equal', opt_equal(r_unset, r_unset2))
  call check('text  opt_equal two unsets are equal', opt_equal(t_unset, t_unset2))
  call check('log   opt_equal two unsets are equal', opt_equal(l_unset, l_unset2))
  call check('int   opt_equal set vs unset differ', .not. opt_equal(i_other, i_unset))
  call check('int   opt_equal same payload equal', opt_equal(i_other, opt_int_of(7_int32)))
  call check('int   opt_equal different payload differ', .not. opt_equal(i_other, opt_int_of(8_int32)))

  ! opt_real comparison is on bit patterns: total, and safe under -fpe0.
  nan = make_nan()
  call opt_set(r_nan_a, nan)
  call opt_set(r_nan_b, nan)
  call check('real  opt_equal identical NaN payloads equal', opt_equal(r_nan_a, r_nan_b))
  call check('real  opt_equal +0.0 vs -0.0 differ', .not. opt_equal(r_zero, opt_real_of(-0.0_real64)))

  ! --- 8. opt_text: explicitly empty vs unset --------------------------------
  call opt_set(t_empty, '')
  call check('text  explicit empty string is set', opt_is_set(t_empty))
  call check('text  explicit empty /= unset', .not. opt_equal(t_empty, t_unset))
  call opt_get(t_empty, tv, found)
  call check('text  opt_get explicit empty -> found, len 0', found .and. len(tv) == 0)
  call check('text  opt_value_or explicit empty -> empty not default', len(opt_value_or(t_empty, 'fallback')) == 0)
  call opt_set(t_word, 'plane_strain')
  call check('text  opt_equal same text equal', opt_equal(t_word, opt_text_of('plane_strain')))
  call check('text  opt_equal blank padding differs', .not. opt_equal(t_word, opt_text_of('plane_strain ')))

  ! --- 9. collections: unallocated (unset) vs zero-length (explicitly empty) --
  ! Collections are not wrapped: allocation status carries the same three states.
  call check('coll  unallocated array is unset', .not. allocated(ids))
  allocate (ids(0))
  call check('coll  allocated size 0 is explicitly empty', allocated(ids))
  if (allocated(ids)) call check('coll  explicitly empty has size 0', size(ids) == 0)
  deallocate (ids)
  call check('coll  deallocate returns to unset', .not. allocated(ids))
  allocate (ids(2))
  ids = [0_int32, 0_int32]
  call check('coll  allocated size 2 of zeros is neither unset nor empty', allocated(ids))
  if (allocated(ids)) call check('coll  present zero-valued entries have size 2', size(ids) == 2)
  deallocate (ids)

  ! --- summary ---------------------------------------------------------------
  if (n_fail == 0) then
    write (output_unit, '(a,i0,a,i0)') 'PASS: ', n_check - n_fail, '/', n_check
  else
    write (output_unit, '(a,i0,a,i0,a)') 'FAIL: ', n_fail, ' of ', n_check, ' checks failed'
    stop 1
  end if

contains

  subroutine check(label, ok)
    character(len=*), intent(in) :: label
    logical, intent(in) :: ok
    n_check = n_check + 1
    if (ok) then
      write (output_unit, '(a,a)') '  ok   ', label
    else
      n_fail = n_fail + 1
      write (output_unit, '(a,a)') '  FAIL ', label
    end if
  end subroutine check

  function opt_int_of(v) result(x)
    integer(int32), intent(in) :: v
    type(opt_int) :: x
    call opt_set(x, v)
  end function opt_int_of

  function opt_real_of(v) result(x)
    real(real64), intent(in) :: v
    type(opt_real) :: x
    call opt_set(x, v)
  end function opt_real_of

  function opt_text_of(v) result(x)
    character(len=*), intent(in) :: v
    type(opt_text) :: x
    call opt_set(x, v)
  end function opt_text_of

  ! A quiet NaN built from its bit pattern, so that no floating-point operation
  ! (and therefore no -fpe0 trap) is needed to produce it.
  function make_nan() result(v)
    real(real64) :: v
    v = transfer(int(z'7FF8000000000000', int64), 0.0_real64)
  end function make_nan

end program yl_problem_selftest
