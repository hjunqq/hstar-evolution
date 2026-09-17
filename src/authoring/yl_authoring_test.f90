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
  logical :: clean_only, plastic, loa, point

  pass = 0
  fail = 0
  call read_arguments(deck, scratch, mode)
  ! --clean-only: for a deck that cannot carry every counter-example. cooks_membrane has
  ! one nset, so no single-line mutation can produce a duplicate NAME within a collection;
  ! running the full suite there would need a conditional skip, and a skipped check that
  ! still prints is how a suite quietly stops testing something.
  clean_only = (trim(mode) == '--clean-only')
  plastic = (trim(mode) == '--plastic')
  loa = (trim(mode) == '--loa')
  point = (trim(mode) == '--point')

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

  ! --point: the counter-examples of the concentrated force. They need a deck that HAS
  ! one, and the golden point-load deck is that deck -- the same file the modern gate
  ! drives bit-exactly, so a rule that stops matching reality fails here first.
  if (point) then
    write (output_unit, '(a)') '-- counter-examples of the concentrated force'
    ! a force naming a node set this file does not define
    call expect_bad('dangling load nset', 'nset      = "top_centre"', &
                    'nset      = "midspan"', 'DANGLING_REF', 2, 'nset')
    ! the conditional requirement, forward direction
    call expect_bad('concentrated without a node set', 'nset      = "top_centre"', &
                    '# nset removed', 'MISSING_FIELD', 2, 'nset')
    call expect_bad('concentrated without a force', 'value     = [0.0, -10000.0]', &
                    '# value removed', 'MISSING_FIELD', 2, 'value')
    ! and backwards: a field belonging to another type would be read by nobody
    call expect_bad('gravity field on a concentrated load', 'nset      = "top_centre"', &
                    'apply_to  = "all"'//new_line('a')//'nset      = "top_centre"', &
                    'INVALID_INPUT', 2, 'apply_to')
    ! a force with more components than the model has degrees of freedom is a capability
    ! refusal, not a typo: legacy would read nudofn of them and this build has two
    call expect_bad('force with three components', 'value     = [0.0, -10000.0]', &
                    'value     = [0.0, -10000.0, 0.0]', 'UNSUPPORTED', 3, 'value')
    ! The relaxed zero-direction rule has no counter-example HERE, and that is the
    ! honest shape of it. What this deck proves is the ACCEPTANCE half: it carries
    ! `magnitude = 0.0` with `direction = [0, 0]` -- legacy's own gravy = 0, factg =
    ! (0,0) -- and the unchanged-deck check above passes, which is the assertion. The
    ! refusal half still has its counter-example, on lame_cylinder, where the magnitude
    ! is 9.81 and zeroing the direction is a real error. Writing a second one here would
    ! mean mutating the magnitude and then asserting a finding on the direction line,
    ! i.e. testing which of two contradicting lines the message points at rather than
    ! testing the rule.
    write (output_unit, '(a)') ''
    write (output_unit, '(a,i0,a,i0,a)') '-- ', pass, '/', pass + fail, ' checks passed'
    if (fail > 0) then
      write (output_unit, '(a,i0,a)') '== FAIL (', fail, ' checks failed) =='
      error stop 1
    end if
    write (output_unit, '(a)') '== PASS =='
    stop
  end if

  ! --loa: the counter-examples of the .loa family -- surfaces, the extended amplitudes
  ! and the load array. They need a deck that HAS a named surface and a pressure load,
  ! which none of the golden decks does; cases/authoring/wall_reservoir is that deck.
  ! It is deliberately not executable (two steps, a pressure load) -- the refusals for
  ! those two live in the mapping layer and are not this suite's business.
  if (loa) then
    write (output_unit, '(a)') '-- counter-examples of the .loa family'
    ! a load naming a surface this file does not define
    call expect_bad('dangling surface', 'surface   = "upstream_face"', &
                    'surface   = "downstream_face"', 'DANGLING_REF', 2, 'surface')
    ! a step naming an element set this file does not define. Silent in the worst way if
    ! unchecked: the set simply never appears and the analysis runs on a structure with
    ! a piece missing.
    call expect_bad('dangling active elset', 'active_elsets = ["foundation"]', &
                    'active_elsets = ["footing"]', 'DANGLING_REF', 2, 'active_elsets')
    ! y0 == y1: legacy divides by their difference (Load.f90:819)
    call expect_bad('degenerate water distribution', 'at    = [50.0, 0.0]', &
                    'at    = [50.0, 50.0]', 'INVALID_INPUT', 2, 'distribution.at')
    ! the two arrays of a distribution pair up, so they must be the same length
    call expect_bad('distribution arrays of different length', 'value = [0.0, 50.0]', &
                    'value = [0.0, 25.0, 50.0]', 'INVALID_INPUT', 2, 'distribution.value')
    ! an amplitude whose time points do not advance
    call expect_bad('non-monotonic amplitude', 'points = [[0.0, 1.0], [1.0, 1.0]]', &
                    'points = [[1.0, 1.0], [0.0, 1.0]]', 'INVALID_INPUT', 2, 'points')
    ! an edge row that is not [n1, n2, element]
    call expect_bad('edge row of the wrong arity', &
                    'edges = [[1, 7, 1], [7, 13, 6], [13, 19, 11], [19, 25, 16]]', &
                    'edges = [[1, 7, 1], [7, 13], [13, 19, 11], [19, 25, 16]]', &
                    'INVALID_INPUT', 2, 'edges[2]')
    ! a node number that no mesh can have. "node 9999 does not exist" is NOT here: this
    ! layer never opens the mesh, and claiming that check would be the more dangerous
    ! half-truth. Sign and shape are what is knowable from the file alone.
    call expect_bad('edge row with a non-positive id', &
                    'edges = [[1, 7, 1], [7, 13, 6], [13, 19, 11], [19, 25, 16]]', &
                    'edges = [[1, 7, 1], [0, 13, 6], [13, 19, 11], [19, 25, 16]]', &
                    'INVALID_INPUT', 2, 'edges[2]')
    ! an unlisted surface kind is a capability refusal
    call expect_bad('unlisted surface kind', 'kind  = "edge2"', 'kind  = "face4"', &
                    'UNSUPPORTED', 3, 'kind')
    ! the conditional requirement, forward direction: a pressure load without its scale
    call expect_bad('pressure without a scale', 'scale = 9810.0', '# scale removed', &
                    'MISSING_FIELD', 2, 'distribution.scale')
    ! and backwards: a field that belongs to the other type would be read by nobody
    call expect_bad('gravity field on a pressure load', 'surface   = "upstream_face"', &
                    'magnitude = 9.81'//new_line('a')//'surface   = "upstream_face"', &
                    'INVALID_INPUT', 2, 'magnitude')
    ! whether a step starts from zero or continues is the central question of a staged
    ! analysis, so it is required rather than defaulted
    call expect_bad('missing reset_state', 'reset_state   = false', '# removed', &
                    'MISSING_FIELD', 2, 'reset_state')
    write (output_unit, '(a)') ''
    write (output_unit, '(a,i0,a,i0,a)') '-- ', pass, '/', pass + fail, ' checks passed'
    if (fail > 0) then
      write (output_unit, '(a,i0,a)') '== FAIL (', fail, ' checks failed) =='
      error stop 1
    end if
    write (output_unit, '(a)') '== PASS =='
    stop
  end if

  ! --plastic: the counter-examples that need a deck with a PLASTICITY material. They
  ! cannot live on the elastic decks -- a criterion counter-example on a deck with no
  ! plasticity model would be testing the other direction of the same rule, which the
  ! elastic run already covers.
  if (plastic) then
    write (output_unit, '(a)') '-- counter-examples that need a plasticity deck'
    ! an unlisted yield criterion is a capability refusal, not a typo
    call expect_bad('unlisted criterion', 'criterion      = "mohr_coulomb"', &
                    'criterion      = "drucker_prager"', 'UNSUPPORTED', 3, 'criterion')
    ! the model is there, the criterion is not: a conditional requirement, both halves
    call expect_bad('plastic model without a criterion', 'criterion      = "mohr_coulomb"', &
                    '# criterion removed', 'MISSING_FIELD', 2, 'criterion')
    call expect_bad('plastic model without an angle', 'friction_angle = 30.0', &
                    '# friction_angle removed', 'MISSING_FIELD', 2, 'friction_angle')
    ! The element-count rule is NOT here: it lives in the mapping layer, which reads the
    ! mesh file, and this suite runs the validator alone. Its counter-example is N3 in
    ! tools/yl_modern_check.py, where the real binary runs against a real mesh.
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
  ! the other direction of the conditional requirement: a plasticity parameter on a
  ! material that has no plasticity model. Silently ignoring it is the failure this
  ! catches -- the author would believe a friction angle was in effect.
  call expect_bad('plasticity parameter on an elastic material', 'nu      = 0.2', &
                  'friction_angle = 30.0', 'INVALID_INPUT', 2, 'friction_angle')
  ! when the tangent is rebuilt: a whitelist, and the row that moved out of the default
  ! table because its innocence depended on the material
  call expect_bad('unlisted stiffness update', 'stiffness_update = "first_iteration"', &
                  'stiffness_update = "sometimes"', 'UNSUPPORTED', 3, 'stiffness_update')
  ! the load mode is a whitelist
  call expect_bad('unlisted load mode', 'load_mode = "load"', 'load_mode = "creep"', &
                  'UNSUPPORTED', 3, 'load_mode')
  ! a strength-reduction curve on a deck that does not reduce strength: legacy would
  ! ignore it, and the author would never learn their schedule did nothing
  call expect_bad('reduction curve without the mode', 'load_mode = "load"', &
                  'load_mode = "load"'//new_line('a')//'[step.strength_reduction]'// &
                  new_line('a')//'amplitude = "constant"', &
                  'INVALID_INPUT', 2, 'strength_reduction')
  ! the two step-count controls left the default table because a sweep needs them
  call expect_bad('missing step count', 'substeps        = 1', '# substeps removed', &
                  'MISSING_FIELD', 2, 'substeps')
  call expect_bad('missing time increment', 'time_increment  = 1.0', '# removed', &
                  'MISSING_FIELD', 2, 'time_increment')
  ! a material property that varies between real decks, so it cannot be defaulted
  call expect_bad('missing thermal expansion', 'thermal_expansion = 1.0e-5', '# removed', &
                  'MISSING_FIELD', 2, 'thermal_expansion')
  ! a load naming an amplitude this file does not define
  call expect_bad('dangling load amplitude', 'amplitude = "constant"', &
                  'amplitude = "flood"', 'DANGLING_REF', 2, 'amplitude')
  ! a gravity direction of zero length names no direction at all
  call expect_bad('zero gravity direction', 'direction = [0.0, -1.0]', &
                  'direction = [0.0, 0.0]', 'INVALID_INPUT', 2, 'direction')
  ! gravity is applied to a named element set or to everything; a set that does not
  ! exist is the same dangling reference as any other
  call expect_bad('dangling apply_to', 'apply_to  = "all"', 'apply_to  = "rock"', &
                  'DANGLING_REF', 2, 'apply_to')
  ! stress averaging is a whitelist, and it is the one row that moved OUT of the default
  ! table: it decides what the reported stresses are, so an unlisted scheme is a capability
  ! refusal rather than a silently substituted default.
  call expect_bad('unlisted stress averaging', 'stress_averaging = "direct"', &
                  'stress_averaging = "gauss"', 'UNSUPPORTED', 3, 'output.stress_averaging')

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
