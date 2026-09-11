! A throwaway driver: read a case.toml and print the flat store. Used while building the
! reader; kept because "the parser produced what I expected" is worth being able to show.
program yl_authoring_probe
  use iso_fortran_env, only: output_unit
  use yl_authoring_toml
  implicit none
  type(toml_doc_t) :: doc
  character(len=512) :: path
  integer :: i, l
  call get_command_argument(1, path, l)
  if (l <= 0) then
    write (output_unit, '(a)') 'usage: yl_authoring_probe case.toml'
    error stop 2
  end if
  call toml_read(path(1:l), doc)
  if (doc%failed) then
    write (output_unit, '(a,i0,a)') 'INVALID_INPUT at line ', doc%fail_line, ': '// &
      trim(doc%message)
    error stop 2
  end if
  write (output_unit, '(a,i0,a)') 'entries=', doc%n, ''
  do i = 1, int(doc%n)
    select case (doc%entry(i)%kind)
    case (TV_INT)
      write (output_unit, '(a,i5,a,i0)') trim(doc%entry(i)%path)//'  L', &
        doc%entry(i)%line, '  int   ', doc%entry(i)%ivalue
    case (TV_REAL)
      write (output_unit, '(a,i5,a,es14.7)') trim(doc%entry(i)%path)//'  L', &
        doc%entry(i)%line, '  real  ', doc%entry(i)%rvalue
    case (TV_STR)
      write (output_unit, '(a,i5,a)') trim(doc%entry(i)%path)//'  L', &
        doc%entry(i)%line, '  str   "'//trim(doc%entry(i)%svalue)//'"'
    case (TV_BOOL)
      write (output_unit, '(a,i5,a,l1)') trim(doc%entry(i)%path)//'  L', &
        doc%entry(i)%line, '  bool  ', doc%entry(i)%lvalue
    end select
  end do
end program yl_authoring_probe
