!> Reads the four `.tem` counts legacy leaves in its globals, and refuses every deck that
!> puts anything but zero in them.
!>
!> WHY THIS FILE EXISTS AT ALL, given that nothing on the static-q4/1 path uses a
!> temperature field. Because legacy READS these records on this path, and the shadow
!> differential compares GLOBALS:
!>
!>   * `.tem` is opened unconditionally in global_data (Global.f90:661), not behind a
!>     thermal switch;
!>   * `boundt` is called unconditionally from the block loop (Fem.f90:1899);
!>   * `ntemp_surface`, `ntedge`, `ntelgroup` and `npipe` are assigned by `read`
!>     statements (Temper.f90:126, 154, 246, 310) and left in the `temperature` module.
!>
!> So these four are not "stopped at zero-initialisation": they are values the deck
!> supplied. Writing 0 into them without reading the file would be forging a read result,
!> which is the distinction docs/m4/L2c-fold-design.md 1.7.1 draws between carrying a
!> value out honestly and inventing one. They are also exactly the four rows M1's reader
!> inventory covers and the adapter did not -- closing the whole comparable-surface gap
!> that section 1.9 reported, no more and no less.
!>
!> WHAT IT PARSES. Legacy's record order in the all-zero case, which is what the
!> capability admits. Six title records and four counts, interleaved (the goldens'
!> `1.tem` is exactly these ten lines):
!>
!>   1  title                      TEM.boundt.title#1
!>   2  ntemp_surface              TEM.boundt.temp_surface_count
!>   3  title                      TEM.boundt.title#2
!>   4  ntedge                     TEM.boundt.temp_edge_count
!>   5  title                      TEM.boundt.label11_title   (reached by `goto 11` when
!>                                                             ntedge == 0)
!>   6  title                      TEM.boundt.title#3
!>   7  ntelgroup                  TEM.boundt.temp_elgroup_count
!>   8  title                      TEM.boundt.title#4         (reached by `goto 22` when
!>                                                             ntelgroup == 0)
!>   9  title                      TEM.boundt.title#5
!>  10  npipe, algo_pipe           TEM.boundt.pipe_count
!>
!> THE TWO LABELLED READS ARE GOTO TARGETS, and that is why this parser mirrors legacy's
!> ZERO path specifically rather than "the file format". When a count is non-zero legacy
!> takes a different route through the file and consumes records this module never reads;
!> refusing a non-zero count is therefore not a convenience, it is the condition under
!> which the record sequence above is the right one.
!>
!> `algo_pipe` shares record 10 with `npipe` and is read only to consume it. It is not a
!> map row and is not carried anywhere.
module yl_adapter_temper

  use iso_fortran_env, only: int32
  use yl_problem_optional, only: opt_set
  use yl_problem_errors, only: problem_errors_t, source_location_t, make_source_location,     &
                               make_problem_error, PE_INVALID_INPUT, PE_STAGE_ADAPT
  use yl_problem_deck_residue, only: deck_residue_t
  use yl_adapter_parts, only: reject_dialect

  implicit none
  private

  public :: parse_tem

  character(len=*), parameter :: SRC_TEM = 'Temper.f90'
  character(len=*), parameter :: OBJ = 'derived.counts'

contains

  !> Fills `residue`'s four temperature counts, or reports why the deck is out of scope.
  !>
  !> Every count is carried out even though every accepted value is 0: the residue's job
  !> is to say what the deck supplied, and "0 because the file said 0" is a different fact
  !> from "0 because nobody looked". The rejection below is what makes the two the same
  !> number here, not an assumption that they must be.
  subroutine parse_tem(unit, residue, errors)
    integer, intent(in) :: unit
    type(deck_residue_t), intent(inout) :: residue
    type(problem_errors_t), intent(inout) :: errors

    character(len=200) :: text
    integer :: ios
    integer :: ntemp_surface, ntedge, ntelgroup, npipe, algo_pipe
    logical :: io_ok

    ! RD: TEM.boundt.title#1 (Temper.f90:124)
    read (unit, *, iostat=ios) text
    call check_io(errors, ios, 'TEM.boundt.title#1', 124, io_ok)
    if (.not. io_ok) return

    ! RD: TEM.boundt.temp_surface_count (Temper.f90:126)
    read (unit, *, iostat=ios) ntemp_surface
    call check_io(errors, ios, 'TEM.boundt.temp_surface_count', 126, io_ok)
    if (.not. io_ok) return
    if (ntemp_surface /= 0) then
      call refuse('A12', 'temp-surface-unsupported', 'TEM.boundt.temp_surface_count', 126,     &
                  ntemp_surface, errors)
      return
    end if

    ! RD: TEM.boundt.title#2 (Temper.f90:152)
    read (unit, *, iostat=ios) text
    call check_io(errors, ios, 'TEM.boundt.title#2', 152, io_ok)
    if (.not. io_ok) return

    ! RD: TEM.boundt.temp_edge_count (Temper.f90:154)
    read (unit, *, iostat=ios) ntedge
    call check_io(errors, ios, 'TEM.boundt.temp_edge_count', 154, io_ok)
    if (.not. io_ok) return
    if (ntedge /= 0) then
      call refuse('A13', 'temp-edge-unsupported', 'TEM.boundt.temp_edge_count', 154,           &
                  ntedge, errors)
      return
    end if

    ! RD: TEM.boundt.label11_title (Temper.f90:243) -- the `goto 11` landing, taken
    ! because ntedge is 0.
    read (unit, *, iostat=ios) text
    call check_io(errors, ios, 'TEM.boundt.label11_title', 243, io_ok)
    if (.not. io_ok) return

    ! RD: TEM.boundt.title#3 (Temper.f90:245)
    read (unit, *, iostat=ios) text
    call check_io(errors, ios, 'TEM.boundt.title#3', 245, io_ok)
    if (.not. io_ok) return

    ! RD: TEM.boundt.temp_elgroup_count (Temper.f90:247)
    read (unit, *, iostat=ios) ntelgroup
    call check_io(errors, ios, 'TEM.boundt.temp_elgroup_count', 247, io_ok)
    if (.not. io_ok) return
    if (ntelgroup /= 0) then
      call refuse('A14', 'temp-elgroup-unsupported', 'TEM.boundt.temp_elgroup_count', 247,     &
                  ntelgroup, errors)
      return
    end if

    ! RD: TEM.boundt.title#4 (Temper.f90:306) -- the `goto 22` landing.
    read (unit, *, iostat=ios) text
    call check_io(errors, ios, 'TEM.boundt.title#4', 306, io_ok)
    if (.not. io_ok) return

    ! RD: TEM.boundt.title#5 (Temper.f90:308)
    read (unit, *, iostat=ios) text
    call check_io(errors, ios, 'TEM.boundt.title#5', 308, io_ok)
    if (.not. io_ok) return

    ! RD: TEM.boundt.pipe_count (Temper.f90:311). One record, two values: `algo_pipe` is
    ! consumed and discarded, as legacy's own `print` is the only thing it reaches on a
    ! deck with no pipes.
    read (unit, *, iostat=ios) npipe, algo_pipe
    call check_io(errors, ios, 'TEM.boundt.pipe_count', 311, io_ok)
    if (.not. io_ok) return
    if (npipe /= 0) then
      call refuse('A15', 'pipe-cooling-unsupported', 'TEM.boundt.pipe_count', 311,             &
                  npipe, errors)
      return
    end if

    ! Set only after every record has been read and accepted. A partially-filled residue
    ! from a refused deck would be a value with no provenance, which is the state the
    ! whole carrier exists to avoid.
    call opt_set(residue%ntemp_surface, int(ntemp_surface, int32))
    call opt_set(residue%ntedge, int(ntedge, int32))
    call opt_set(residue%ntelgroup, int(ntelgroup, int32))
    call opt_set(residue%npipe, int(npipe, int32))
  end subroutine parse_tem

  ! ==========================================================================
  ! private helpers
  ! ==========================================================================

  !> One shape for all four refusals, so a new count cannot be rejected in a way that
  !> reports differently from the other three.
  subroutine refuse(rule_id, condition, reader_id, line, actual, errors)
    character(len=*), intent(in) :: rule_id, condition, reader_id
    integer, intent(in) :: line, actual
    type(problem_errors_t), intent(inout) :: errors
    type(source_location_t) :: loc
    loc = make_source_location(file=SRC_TEM, reader=reader_id, line=int(line, int32))
    call reject_dialect(errors, rule_id, condition, loc, actual=itoa(actual), expected='0')
  end subroutine refuse

  !> Mirrors yl_adapter_load's check_io: each parser module carries its own, because the
  !> reader id, source file and object path it reports are that module's business.
  subroutine check_io(errors, ios, reader_id, line, ok)
    type(problem_errors_t), intent(inout) :: errors
    integer, intent(in) :: ios
    character(len=*), intent(in) :: reader_id
    integer, intent(in) :: line
    logical, intent(out) :: ok
    type(source_location_t) :: loc

    ok = (ios == 0)
    if (ok) return
    loc = make_source_location(file=SRC_TEM, reader=reader_id, line=int(line, int32))
    call errors%add(make_problem_error(code=PE_INVALID_INPUT, stage=PE_STAGE_ADAPT,            &
                                       rule_id='A-IO/'//trim(reader_id), object_path=OBJ,      &
                                       message='I/O error reading '//trim(reader_id),          &
                                       source=loc))
  end subroutine check_io

  pure function itoa(v) result(s)
    integer, intent(in) :: v
    character(len=:), allocatable :: s
    character(len=24) :: buf
    write (buf, '(i0)') v
    s = trim(buf)
  end function itoa

end module yl_adapter_temper
