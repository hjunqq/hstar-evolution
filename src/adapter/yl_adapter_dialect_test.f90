! yl_adapter_dialect_test -- the falsifiability suite for the CAP_STAGE_ADAPT partition.
!
! Scope (M4-01 L2-b; .ccg/tasks/m4-01-legacy-adapter/plan.md Layer 2)
!   One counter-example per dialect row, run through the REAL parser on a REAL deck, plus
!   the table and raiser checks that keep the mechanism honest. Exit status 0 on success,
!   1 on any failure.
!
! WHAT MAKES THIS A FALSIFIABILITY SUITE AND NOT A COVERAGE REPORT
!   Three properties, and each one closes a way the previous milestones' gates decayed:
!
!   1. EVERY ROW HAS A COUNTER-EXAMPLE. `dialect_first_uncovered` walks the whole
!      partition at the end and names the first row nothing triggered. A row that becomes
!      unreachable fails this suite instead of sitting in the table looking enforced.
!
!   2. EVERY COUNTER-EXAMPLE TRIGGERS EXACTLY ONE ROW. Checked per case, not only in
!      aggregate. Without it a deck that happens to trip an EARLIER guard would still
!      mark the suite green while the row it was written for went untested -- which is
!      exactly how M3-02's audit found six rows with no counter-example, each hiding
!      behind a rule id another row had already made look covered.
!
!   3. THE COUNTER-EXAMPLES ARE REAL DECKS. Each is the golden `cooks_membrane` legacy
!      deck with ONE record replaced. Nothing here hand-builds a finding or calls
!      reject_dialect for a row it then asserts: the parser has to reach the guard on a
!      file that is well-formed up to that point, so a guard placed after an unreachable
!      read cannot pass.
!
! WHY THE GOLDEN DECK RATHER THAN A FIXTURE OF ITS OWN
!   A hand-written minimal deck would be a second description of the legacy record shapes,
!   maintained here, free to drift from the decks the adapter is actually judged against.
!   cases/golden/** is READ-ONLY to this suite: it copies a deck to a scratch file, edits
!   the copy, and never writes into cases/.
!
! Usage
!   yl_adapter_dialect_test [DECK_DIR] [SCRATCH_DIR]
!     DECK_DIR     default cases/golden/static_2d/cooks_membrane/legacy
!     SCRATCH_DIR  default . -- variant decks are written here and removed afterwards
program yl_adapter_dialect_test

  use iso_fortran_env, only: int32, real64, output_unit, iostat_end
  use yl_problem_optional, only: opt_value_or
  use yl_problem_errors, only: problem_errors_t, problem_error_t, source_location_t,           &
                               make_source_location, PE_UNSUPPORTED, PE_INTERNAL,              &
                               PE_STAGE_ADAPT, PE_STAGE_CAPABILITY, PE_EXIT_INTERNAL,          &
                               PE_EXIT_UNSUPPORTED, make_problem_error
  use yl_problem_profile, only: capability_item_t, capability_count, capability_table_row,     &
                                CAPABILITY_ROW_TOTAL, CAP_STAGE_GATE, CAP_STAGE_ADAPT,         &
                                PROFILE_KIND_NONE, DIALECT_VERDICT,                            &
                                dialect_count, dialect_row, dialect_find, dialect_key,         &
                                dialect_row_text
  use yl_problem_builder, only: problem_builder_t, builder_begin
  use yl_adapter_parts, only: deck_context_t, deck_context_reset, step_parts_t,                &
                              step_parts_reset, solver_parts_t, solver_parts_reset,            &
                              section_parts_t, section_parts_reset, LEN_TYPE_ABC,              &
                              reject_dialect, dialect_verdict_of,                              &
                              dialect_row_exercised, dialect_first_uncovered
  use yl_adapter_fem90, only: parse_inp, parse_man
  use yl_adapter_model, only: parse_glb
  use yl_adapter_mesh, only: parse_cor, parse_ele
  use yl_adapter_material, only: parse_mat, parse_sol
  use yl_adapter_load, only: parse_loa, parse_pre
  use yl_adapter_temper, only: parse_tem
  use yl_problem_deck_residue, only: deck_residue_t

  implicit none

  integer, parameter :: LINE_LEN = 1024

  ! Findings from every case, so the closing coverage walk sees the whole run.
  type(problem_errors_t) :: all_errs
  integer :: n_checks = 0, n_failed = 0
  character(len=:), allocatable :: deck_dir, scratch_dir

  call read_arguments(deck_dir, scratch_dir)

  write (output_unit, '(a)') '== yl_adapter_dialect_test =='
  write (output_unit, '(a)') '   deck dir    : '//deck_dir
  write (output_unit, '(a)') '   scratch dir : '//scratch_dir

  call check_table_shape()
  call check_raiser()
  call check_verdict()

  write (output_unit, '(a)') '-- counter-examples, one per CAP_STAGE_ADAPT row'
    call run_case('F1', 'restart', 'inp', 2, '1  0  0  0  0  0', 'W')
    call run_case('F1', 'relis', 'inp', 2, '0  1  0  0  0  0', 'W')
    call run_case('F1', 'sysrelis', 'inp', 2, '0  0  1  0  0  0', 'W')
    call run_case('F1', 'adina', 'inp', 2, '0  0  0  1  0  0', 'W')
    call run_case('F1', 'uopt_r', 'inp', 2, '0  0  0  0  1  0', 'W')
    call run_case('F1', 'gamamax', 'inp', 2, '0  0  0  0  0  1', 'W')
    call run_case('F1', 'runblks', 'inp', 5, '2', 'W')
    call run_case('F2', 'multi-increment', 'man', 2, '  2  0  0  0', 'W')
    call run_case('F2', 'cwater', 'man', 3, '  5  1.0  1  1  1  1  1  1  0', 'W')
    call run_case('F2', 'qstatic', 'man', 3, '  5  1.0  1  1  1  1  1  0  1', 'W')
    call run_case('A-GLB', 'rmesh-nonzero', 'glb', 2, &
                  '  289  289  256  2  1  1  0  GIDR  0.0  0  0  1  0  0  99999', &
                  'W')
    call run_case('A-GLB', 'ntlink-nonzero', 'glb', 2, &
                  '  289  289  256  2  1  1  1  GIDR  0.0  0  0  0  0  0  99999', &
                  'W')
    call run_case('A-GLB', 'mat_curve-nonzero', 'glb', 2, &
                  '  289  289  256  2  1  1  0  GIDR  0.0  1  0  0  0  0  99999', &
                  'W')
    call run_case('A-GLB', 'meshc-nonzero', 'glb', 2, &
                  '  289  289  256  2  1  1  0  GIDR  0.0  0  1  0  0  0  99999', &
                  'W')
    call run_case('A-GLB', 'level_set_problem-nonzero', 'glb', 2, &
                  '  289  289  256  2  1  1  0  GIDR  0.0  0  0  0  1  0  99999', &
                  'W')
    call run_case('A-GLB', 'ljdp-nonzero', 'glb', 2, &
                  '  289  289  256  2  1  1  0  GIDR  0.0  0  0  0  0  1  99999', &
                  'W')
    call run_case('A-GLB', 'kstab-nonzero', 'glb', 2, &
                  '  289  289  256  2  1  1  0  GIDR  1.0  0  0  0  0  0  99999', &
                  'W')
    call run_case('A-GLB', 'outplot-not-gidr', 'glb', 2, &
                  '  289  289  256  2  1  1  0  GIDA  0.0  0  0  0  0  0  99999', &
                  'W')
    call run_case('A-GLB', 'stab-matde-enabled', 'glb', 2, &
                  '  289  289  256  2  1  1  0  GIDR  0.0  0  0  0  0  0  1', &
                  'W')
    call run_case('A-GLB', 'multiple-blocks', 'glb', 6, &
                  '  0  0  0  2  0  0  0  0  0  0  0  FIX  0  0  0  0  0  0  0', &
                  'W')
    call run_case('A-GLB', 'nlinks-nonzero', 'glb', 6, &
                  '  0  0  0  1  1  0  0  0  0  0  0  FIX  0  0  0  0  0  0  0', &
                  'W')
    call run_case('A-GLB', 'block_stab-nonzero', 'glb', 6, &
                  '  0  0  0  1  0  0  0  0  0  0  0  FIX  1  0  0  0  0  0  0', &
                  'W')
    call run_case('A-GLB', 'nbackf-nonzero', 'glb', 6, &
                  '  0  0  0  1  0  0  0  0  0  0  0  FIX  0  1  0  0  0  0  0', &
                  'W')
    call run_case('A-GLB', 'ebody-nonzero', 'glb', 6, &
                  '  0  0  0  1  0  0  0  0  0  0  0  FIX  0  0  0  1  0  0  0', &
                  'W')
    call run_case('A-GLB', 'ninit-nonzero', 'glb', 6, &
                  '  1  0  0  1  0  0  0  0  0  0  0  FIX  0  0  0  0  0  0  0', &
                  'W')
    call run_case('A-GLB', 'absorbing-not-fix', 'glb', 6, &
                  '  0  0  0  1  0  0  0  0  0  0  0  MIF  0  0  0  0  0  0  0', &
                  'W')
    call run_case('A-GLB', 'nlayer-nonzero', 'glb', 8, 'Q  PROFILE  LOAD  5  0  2  0  0  0  0  0', 'W')
    call run_case('A-GLB', 'state_change-nonzero', 'glb', 8, 'Q  PROFILE  LOAD  5  0  0  0  1  0  0  0', 'W')
    call run_case('A-GLB', 'Bparameter-nonzero', 'glb', 8, 'Q  PROFILE  LOAD  5  0  0  0  0  1  0  0', 'W')
    call run_case('A-GLB', 'nonlinear-type-not-5', 'glb', 8, 'Q  PROFILE  LOAD  4  0  0  0  0  0  0  0', 'W')
    call run_case('A-GLB', 'mdofn-mismatch', 'glb', 16, '  3', 'W')
    ! The extra trailing 1 is listglocbeam(1): with nlocalbeam=1 the record's io-list grows
    ! by one item, and a counter-example that omitted it was caught by the malformed-record
    ! guard BEFORE the whitelist guard it was written for. That is what the "fires that row
    ! ALONE" check is for, and it is how this case was found wrong on the first run.
    call run_case('A-GLB', 'crack-beam-nonzero', 'glb', 40, &
                  '       1.500E+06  1.0e6  0  2  1.0e8  1.0e8  1  0  1', &
                  'W')
    call run_case('A-GLB', 'ntrans-nonzero', 'glb', 42, '  1  0  1.0e0  0.02  2  1980.0  25.0', 'W')
    call run_case('A-GLB', 'uinitial-nonzero', 'glb', 50, '  1', 'W')
    call run_case('A-COR', 'dimension', 'cor', 0, '', 'DIM3')
    call run_case('A-ELE', 'element-kind', 'ele', 0, '', 'KIND7')
    call run_case('A-MAT', 'curve-count', 'mat', 2, '  1', 'W')
    call run_case('A-MAT', 'property', 'mat', 17, '          THERMAL           SOLID     1', 'W')
    call run_case('A-MAT', 'phase-count', 'mat', 18, '  2', 'W')
    call run_case('A-MAT', 'phase', 'mat', 19, '               FLUID', 'W')
    call run_case('A-MAT', 'creep', 'mat', 20, &
                  'ELASTIC_ISOTROPIC       2.400E+03       1.000E+00       1.000E+00       2.500E+10       '//   &
                  '2.000E-01       1.000E-05  1  0  0', &
                  'W')
    call run_case('A-MAT', 'wetting', 'mat', 20, &
                  'ELASTIC_ISOTROPIC       2.400E+03       1.000E+00       1.000E+00       2.500E+10       '//   &
                  '2.000E-01       1.000E-05  0  1  0', &
                  'W')
    call run_case('A-MAT', 'liquefaction', 'mat', 20, &
                  'ELASTIC_ISOTROPIC       2.400E+03       1.000E+00       1.000E+00       2.500E+10       '//   &
                  '2.000E-01       1.000E-05  0  0  1', &
                  'W')
    call run_case('A-MAT', 'contact-material', 'mat', 17, '          MECHANICAL           CONTACT     1', 'W')
    call run_case('A-MAT', 'nonlinear-normal-stiffness', 'mat', 17, &
                  '          MECHANICAL           NOLINORMK     1', &
                  'W')
    call run_case('A-MAT', 'model', 'mat', 20, &
                  'MOHR_COULOMB       2.400E+03       1.000E+00       1.000E+00       2.500E+10       2.000'//   &
                  'E-01       1.000E-05  0  0  0', &
                  'W')
    call run_case('A-SOL', 'pivot-file', 'sol', 2, '  1  0  1  1', 'W')
    call run_case('A1', 'stochastic-curve-modifier-unsupported', 'loa', 3, '  2  LINEAR  1  2', 'W')
    call run_case('A2', 'curve-type-unsupported', 'loa', 3, '  2  HARMONIC  0  2', 'W')
    call run_case('A3', 'point-load-unsupported', 'loa', 7, '  1  0', 'W')
    call run_case('A4', 'edge-definition-unsupported', 'loa', 9, '  1', 'W')
    call run_case('A5', 'pressure-load-unsupported', 'loa', 12, '  1  0', 'W')
    call run_case('A6', 'beam-load-unsupported', 'loa', 18, '  1', 'W')
    call run_case('A7', 'plate-load-unsupported', 'loa', 20, '  1', 'W')
    ! The four `.tem` counts (M4-01 step 4b). Line numbers are the golden 1.tem's, which
    ! is ten records: title, count, title, count, title, title, count, title, title,
    ! count. Each case must fire its own row ALONE, and for these that is the load-bearing
    ! half -- the counts are read in sequence, so a case whose line number had drifted
    ! onto a neighbouring count would still be refused, just by the wrong rule.
    call run_case('A12', 'temp-surface-unsupported', 'tem', 2, '  1', 'W')
    call run_case('A13', 'temp-edge-unsupported', 'tem', 4, '  1', 'W')
    call run_case('A14', 'temp-elgroup-unsupported', 'tem', 7, '  1', 'W')
    call run_case('A15', 'pipe-cooling-unsupported', 'tem', 10, '  1  3', 'W')
    call run_case('A8', 'restart-linked-boundary-unsupported', 'pre', 0, '', 'BACKDT2')
    call run_case('A9', 'mif-boundary-unsupported', 'pre', 0, '', 'MIF')
    call run_case('A10', 'extrapolation-record-unsupported', 'pre', 3, &
                  '         1        17         0         0         1         0   0.000E+00         1', &
                  'W')
    call run_case('A11', 'mif-coordinate-record-unsupported', 'pre', 0, '', 'NTRANS1')

  call check_coverage()

  write (output_unit, '(a,i0,a,i0,a)') '-- ', n_checks - n_failed, '/', n_checks, ' checks passed'
  if (n_failed > 0) then
    write (output_unit, '(a,i0,a)') '== FAIL (', n_failed, ' checks failed) =='
    stop 1
  end if
  write (output_unit, '(a)') '== PASS =='

contains

  ! ==========================================================================
  ! 1. the table's own shape
  ! ==========================================================================

  ! The partition invariant every accessor in yl_problem_profile assumes but none can
  ! demonstrate: gate rows first, dialect rows after, nothing interleaved. Asserted here
  ! because capability_table_row is the one accessor that crosses the boundary.
  subroutine check_table_shape()
    type(capability_item_t) :: row, other
    logical :: found, found2
    integer :: i, j

    write (output_unit, '(a)') '-- table shape'

    call check('T1  the gate partition still has the M3-02 row count',                        &
               capability_count() == 15)
    call check('T2  every table row is accounted for by exactly one partition',               &
               capability_count() + dialect_count() == CAPABILITY_ROW_TOTAL)
    call check('T3  the adapter declares at least one dialect', dialect_count() > 0)

    ! T4 is the contiguity itself. A row out of place here would make capability_row()
    ! hand the gate a dialect row, or hide a dialect row from dialect_row().
    do i = 1, CAPABILITY_ROW_TOTAL
      call capability_table_row(i, row, found)
      if (.not. found) then
        call check('T4  capability_table_row answers for every index in range', .false.)
        cycle
      end if
      if (i <= capability_count()) then
        if (row%stage /= CAP_STAGE_GATE) then
          call check('T4  row '//itoa(i)//' ('//trim(row%item)//') is in the gate '//         &
                     'partition but is not stamped CAP_STAGE_GATE', .false.)
        end if
      else
        if (row%stage /= CAP_STAGE_ADAPT) then
          call check('T4  row '//itoa(i)//' ('//trim(row%item)//') is past the gate '//       &
                     'partition but is not stamped CAP_STAGE_ADAPT', .false.)
        end if
      end if
    end do
    call check('T4  the two partitions are contiguous and gate-first', .true.)

    ! T5/T6/T7 are per-dialect-row well-formedness. Every one of them is a way a row can
    ! be added that compiles, walks and never says anything useful.
    do i = 1, dialect_count()
      call dialect_row(i, row, found)
      if (.not. found) then
        call check('T5  dialect_row answers for index '//itoa(i), .false.)
        cycle
      end if
      call check('T5  '//dialect_key(i)//' carries a rule id, a condition, a deck symbol, ' //&
                 'an object path and a message',                                              &
                 len_trim(row%rule_id) > 0 .and. len_trim(row%condition) > 0 .and.            &
                 len_trim(row%item) > 0 .and. len_trim(row%object_path) > 0 .and.             &
                 len_trim(row%message) > 0)
      ! A component filled to its declared length was probably truncated on the way in.
      call check('T6  '//dialect_key(i)//' is not truncated by LEN_COND / LEN_MESSAGE / '//   &
                 'LEN_PATH / LEN_KEY',                                                        &
                 len_trim(row%condition) < len(row%condition) .and.                           &
                 len_trim(row%message) < len(row%message) .and.                               &
                 len_trim(row%object_path) < len(row%object_path) .and.                       &
                 len_trim(row%item) < len(row%item))
      call check('T7  '//dialect_key(i)//' carries no payload (PROFILE_KIND_NONE)',           &
                 row%stage == CAP_STAGE_ADAPT .and. row%value_kind == PROFILE_KIND_NONE)
    end do

    ! T8: the composed key is unique. This is the property that lets a finding be bound
    ! back to exactly one row, and it is the reason `condition` is a column at all --
    ! A-MAT/contact-material and A-MAT/nonlinear-normal-stiffness share every other
    ! binding component.
    do i = 1, dialect_count()
      do j = i + 1, dialect_count()
        if (dialect_key(i) == dialect_key(j)) then
          call check('T8  dialect keys are unique: '//dialect_key(i)//' appears twice',       &
                     .false.)
        end if
      end do
    end do
    call check('T8  every dialect key is unique across the partition', .true.)

    ! T9: dialect_find round-trips. A row the finder cannot reach is a row no raise site
    ! can name, which would surface at run time as an INTERNAL fault rather than here.
    do i = 1, dialect_count()
      call dialect_row(i, row, found)
      if (.not. found) cycle
      j = dialect_find(trim(row%rule_id), trim(row%condition))
      if (j /= i) then
        call check('T9  dialect_find round-trips for '//dialect_key(i), .false.)
      end if
    end do
    call check('T9  dialect_find round-trips for every row', .true.)

    ! T10: the export line is non-empty in range and empty out of range, and it carries
    ! the outward verdict name -- the single spelling docs/02-migration-plan.md M4 asks for.
    call check('T10 dialect_row_text is empty out of range',                                  &
               dialect_row_text(0) == '' .and. dialect_row_text(dialect_count() + 1) == '')
    call check('T10 dialect_row_text names the outward verdict',                              &
               index(dialect_row_text(1), DIALECT_VERDICT) == 1)

    ! T11: no dialect row shadows a gate item name. capability_find searches the gate
    ! partition only, so a collision would not break it today -- but it would make two
    ! rows answer to one name for a reader, which is how the two tables start to merge.
    do i = 1, dialect_count()
      call dialect_row(i, row, found)
      if (.not. found) cycle
      do j = 1, capability_count()
        call capability_table_row(j, other, found2)
        if (.not. found2) cycle
        if (trim(other%item) == trim(row%item)) then
          call check('T11 dialect item '//trim(row%item)//' collides with a gate item',       &
                     .false.)
        end if
      end do
    end do
    call check('T11 no dialect deck symbol collides with a gate item name', .true.)
  end subroutine check_table_shape

  ! ==========================================================================
  ! 2. the raiser
  ! ==========================================================================

  subroutine check_raiser()
    type(problem_errors_t) :: errs
    type(problem_error_t) :: f
    type(capability_item_t) :: row
    type(source_location_t) :: loc
    logical :: found

    write (output_unit, '(a)') '-- the raiser'
    loc = make_source_location(file='(test)', reader='check_raiser', line=1_int32)

    ! R1: a declared row produces the row's own identity, not the caller's words.
    call dialect_row(1, row, found)
    call reject_dialect(errs, trim(row%rule_id), trim(row%condition), loc, actual='7',        &
                        expected='0')
    call check('R1  a declared dialect raises exactly one finding', errs%count() == 1)
    call errs%get(1, f, found)
    call check('R1  the finding carries PE_UNSUPPORTED',                                      &
               opt_value_or(f%code, '') == PE_UNSUPPORTED)
    call check('R1  the finding carries PE_STAGE_ADAPT',                                      &
               opt_value_or(f%stage, '') == PE_STAGE_ADAPT)
    call check('R1  the finding carries the COMPOSED key, not the bare rule id',              &
               opt_value_or(f%rule_id, '') == dialect_key(1) .and.                            &
               opt_value_or(f%rule_id, '') /= trim(row%rule_id))
    call check('R1  the object path and message come from the row',                           &
               opt_value_or(f%object_path, '') == trim(row%object_path) .and.                 &
               opt_value_or(f%message, '') == trim(row%message))
    call check('R1  the value the parser read travels as `actual`',                           &
               opt_value_or(f%actual, '') == '7')
    call check('R1  the exit class is the UNSUPPORTED class, not the input one',              &
               f%exit_class == PE_EXIT_UNSUPPORTED)
    call check('R1  the row is reported as exercised', dialect_row_exercised(errs, 1))

    ! R2: an UNDECLARED key is an internal fault, not a quiet UNSUPPORTED. This is the
    ! guard that stops a typo from producing a finding no coverage walk can ever match.
    call errs%clear()
    call reject_dialect(errs, 'A-GLB', 'no-such-condition', loc)
    call check('R2  an undeclared dialect raises exactly one finding', errs%count() == 1)
    call errs%get(1, f, found)
    call check('R2  an undeclared dialect is PE_INTERNAL, never PE_UNSUPPORTED',              &
               opt_value_or(f%code, '') == PE_INTERNAL)
    call check('R2  an undeclared dialect exits at the internal class',                       &
               f%exit_class == PE_EXIT_INTERNAL)
    call check('R2  an undeclared dialect exercises no row',                                  &
               dialect_first_uncovered(errs) == 1)

    ! R3: half a key is not a key. Passing the joined string as the rule id -- the exact
    ! mistake this project shipped once -- must not silently resolve.
    call errs%clear()
    call dialect_row(1, row, found)
    call reject_dialect(errs, dialect_key(1), '', loc)
    call errs%get(1, f, found)
    call check('R3  a pre-joined key passed as the rule id does NOT resolve to its row',      &
               opt_value_or(f%code, '') == PE_INTERNAL)
  end subroutine check_raiser

  ! ==========================================================================
  ! 3. the outward verdict
  ! ==========================================================================

  subroutine check_verdict()
    type(problem_errors_t) :: errs
    type(capability_item_t) :: row
    type(source_location_t) :: loc
    logical :: found

    write (output_unit, '(a)') '-- the outward verdict'
    loc = make_source_location(file='(test)', reader='check_verdict', line=1_int32)

    call check('V1  an empty accumulator carries no verdict', dialect_verdict_of(errs) == '')

    ! V2: a PE_UNSUPPORTED raised by the CAPABILITY GATE is not a legacy-dialect verdict.
    ! The code alone cannot tell them apart, which is why the predicate reads the stage.
    call errs%add(make_problem_error(code=PE_UNSUPPORTED, stage=PE_STAGE_CAPABILITY,          &
                  rule_id='G1', object_path='sections[]', field='element'))
    call check('V2  the capability gate''s own PE_UNSUPPORTED is not a dialect verdict',      &
               dialect_verdict_of(errs) == '')

    call dialect_row(1, row, found)
    call reject_dialect(errs, trim(row%rule_id), trim(row%condition), loc, actual='7')
    call check('V3  one dialect finding raises the verdict',                                  &
               dialect_verdict_of(errs) == DIALECT_VERDICT)
    call check('V3  the verdict is the migration plan''s spelling',                           &
               DIALECT_VERDICT == 'UNSUPPORTED_LEGACY_DIALECT')
  end subroutine check_verdict

  ! ==========================================================================
  ! 4. one counter-example per row
  ! ==========================================================================

  !> Build the variant deck, run the parser that owns it, and assert that the run
  !> triggered the intended row AND NOTHING ELSE in the partition.
  !>
  !> `lineno == 0` means the golden deck is used unchanged: four rows are reached through
  !> `deck_context_t` (a fact `.glb` established) rather than through a record of the file
  !> being parsed, and editing that file would test the wrong thing.
  subroutine run_case(rule_id, condition, deck, lineno, newtext, variant)
    character(len=*), intent(in) :: rule_id, condition, deck, newtext, variant
    integer, intent(in) :: lineno

    type(problem_errors_t) :: errs
    type(problem_error_t) :: f
    type(deck_context_t) :: ctx
    type(problem_builder_t) :: b
    type(step_parts_t) :: parts
    type(solver_parts_t) :: sparts
    type(section_parts_t) :: secparts
    character(len=:), allocatable :: src, dst, key
    integer :: unit, ios, j, target_row, hits, first_hit
    logical :: found
    type(deck_residue_t) :: residue

    key = trim(rule_id)//'/'//trim(condition)
    target_row = dialect_find(rule_id, condition)
    if (target_row == 0) then
      call check('C   '//key//' is a declared dialect row', .false.)
      return
    end if

    src = deck_dir//'/'//deck_file(deck)
    dst = scratch_dir//'/dialect-variant.'//deck
    if (lineno == 0) then
      call copy_deck(src, dst, 0, '')
    else
      call copy_deck(src, dst, lineno, newtext)
    end if

    open (newunit=unit, file=dst, status='old', action='read', iostat=ios)
    if (ios /= 0) then
      call check('C   '//key//': the variant deck '//dst//' could not be opened', .false.)
      return
    end if

    call make_context(ctx, variant)
    call builder_begin(b)
    call step_parts_reset(parts)
    call solver_parts_reset(sparts)
    call section_parts_reset(secparts)

    select case (deck)
    case ('inp'); call parse_inp(unit, ctx, b, residue, errs)
    case ('man'); call parse_man(unit, ctx, b, parts, errs)
    case ('glb'); call parse_glb(unit, ctx, b, parts, sparts, secparts, residue, errs)
    case ('cor'); call parse_cor(unit, ctx, b, errs)
    case ('ele'); call parse_ele(unit, ctx, b, errs)
    case ('mat'); call parse_mat(unit, ctx, b, secparts, errs)
    case ('sol'); call parse_sol(unit, ctx, b, sparts, errs)
    case ('loa'); call parse_loa(unit, ctx, b, parts, residue, errs)
    case ('pre'); call parse_pre(unit, ctx, b, parts, errs)
    case ('tem'); call parse_tem(unit, residue, errs)
    case default
      call check('C   '//key//': unknown deck kind '//deck, .false.)
    end select

    close (unit, status='delete')

    ! The row fired ...
    call check('C   '//key//' fires on its counter-example',                                  &
               dialect_row_exercised(errs, target_row))

    ! ... and it is the ONLY row that fired. Without this a case that trips an earlier
    ! guard would still look green while its own row went untested.
    hits = 0
    first_hit = 0
    do j = 1, dialect_count()
      if (.not. dialect_row_exercised(errs, j)) cycle
      hits = hits + 1
      if (first_hit == 0) first_hit = j
    end do
    if (hits /= 1 .or. first_hit /= target_row) then
      call check('C   '//key//' fires that row ALONE (it fired '//itoa(hits)//               &
                 ', first was '//trim(dialect_key(max(first_hit, 1)))//')', .false.)
    end if

    ! ... and the run's outward verdict is the unified one.
    call check('C   '//key//' makes the adapter answer '//DIALECT_VERDICT,                    &
               dialect_verdict_of(errs) == DIALECT_VERDICT)

    do j = 1, errs%count()
      call errs%get(j, f, found)
      if (found) call all_errs%add(f)
    end do
  end subroutine run_case

  ! ==========================================================================
  ! 5. the closing coverage walk
  ! ==========================================================================

  subroutine check_coverage()
    integer :: j
    write (output_unit, '(a)') '-- coverage'
    j = dialect_first_uncovered(all_errs)
    if (j /= 0) then
      call check('X1  every dialect row has a counter-example (row '//itoa(j)//', '//         &
                 dialect_key(j)//', has none)', .false.)
    else
      call check('X1  all '//itoa(dialect_count())//' dialect rows have a counter-example',   &
                 .true.)
    end if
  end subroutine check_coverage

  ! ==========================================================================
  ! plumbing
  ! ==========================================================================

  subroutine check(label, ok)
    character(len=*), intent(in) :: label
    logical, intent(in) :: ok
    n_checks = n_checks + 1
    if (ok) return
    n_failed = n_failed + 1
    write (output_unit, '(a)') '   FAIL  '//label
  end subroutine check

  !> The deck's file name inside DECK_DIR. `inp` has no prefix in legacy (Fem.f90 opens
  !> the literal name); everything else is `<prefix>.<ext>` and the golden prefix is `1`.
  pure function deck_file(deck) result(name)
    character(len=*), intent(in) :: deck
    character(len=:), allocatable :: name
    if (deck == 'inp') then
      name = 'inp'
    else
      name = '1.'//deck
    end if
  end function deck_file

  !> Copy `src` to `dst`, replacing line `lineno` with `newtext`. `lineno == 0` copies
  !> verbatim. Fails the suite (rather than aborting) if the file is shorter than lineno,
  !> because a line number that has drifted must be visible, not silently ignored.
  subroutine copy_deck(src, dst, lineno, newtext)
    character(len=*), intent(in) :: src, dst, newtext
    integer, intent(in) :: lineno
    character(len=LINE_LEN) :: buf
    integer :: uin, uout, ios, n

    open (newunit=uin, file=src, status='old', action='read', iostat=ios)
    if (ios /= 0) then
      call check('C   the golden deck '//src//' could not be opened', .false.)
      return
    end if
    open (newunit=uout, file=dst, status='replace', action='write')
    n = 0
    do
      read (uin, '(a)', iostat=ios) buf
      if (ios == iostat_end) exit
      n = n + 1
      if (n == lineno) then
        write (uout, '(a)') newtext
      else
        write (uout, '(a)') trim(buf)
      end if
    end do
    close (uin)
    close (uout)
    if (lineno > n) then
      call check('C   '//src//' has no line '//itoa(lineno)//' to replace', .false.)
    end if
  end subroutine copy_deck

  !> The `deck_context_t` a parser would have received from a successful parse_glb on the
  !> golden deck, optionally with the ONE field a ctx-driven counter-example perturbs.
  !> Kept in one place so a case says which fact it changes and nothing else.
  subroutine make_context(ctx, variant)
    type(deck_context_t), intent(out) :: ctx
    character(len=*), intent(in) :: variant

    call deck_context_reset(ctx)
    ctx%filled = .true.
    ctx%ndimn = 2_int32
    ctx%ngroup = 1_int32
    ctx%nnode = 4_int32
    ctx%element_kind = 5_int32
    allocate (ctx%nelgroup(1), ctx%group_matno(1), ctx%group_kind(1))
    ctx%nelgroup = 256_int32
    ctx%group_matno = 1_int32
    ctx%group_kind = 5_int32
    ctx%type_abc = 'FIX'
    ctx%nbackdt = 0_int32
    ctx%ntrans = 0_int32

    select case (variant)
    case ('W')        ! the whitelisted context, unchanged
    case ('DIM3');    ctx%ndimn = 3_int32
    case ('KIND7');   ctx%group_kind = 7_int32
    case ('BACKDT2'); ctx%nbackdt = 2_int32
    case ('MIF');     ctx%type_abc = 'MIF'
    case ('NTRANS1'); ctx%ntrans = 1_int32
    case default
      call check('C   unknown context variant '//variant, .false.)
    end select
  end subroutine make_context

  subroutine read_arguments(dir, scratch)
    character(len=:), allocatable, intent(out) :: dir, scratch
    character(len=4096) :: buf
    integer :: n, length
    n = command_argument_count()
    if (n >= 1) then
      call get_command_argument(1, buf, length)
      dir = buf(1:length)
    else
      dir = 'cases/golden/static_2d/cooks_membrane/legacy'
    end if
    if (n >= 2) then
      call get_command_argument(2, buf, length)
      scratch = buf(1:length)
    else
      scratch = '.'
    end if
  end subroutine read_arguments

  pure function itoa(v) result(s)
    integer, intent(in) :: v
    character(len=:), allocatable :: s
    character(len=12) :: buf
    write (buf, '(i0)') v
    s = trim(buf)
  end function itoa

end program yl_adapter_dialect_test
