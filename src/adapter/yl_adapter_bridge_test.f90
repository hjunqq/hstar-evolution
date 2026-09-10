! yl_adapter_bridge_test -- L3-b: the deferred M3 exit condition, closed with a real deck.
!
! Scope (docs/decisions/0004-defer-m3-exit-to-m4.md; docs/m3/M3-03-runtime.md S8)
!   ADR-0004 registered that M3-03's bridge (`build_runtime` -> `commit_legacy_globals`)
!   was never compared against a single value of the frozen M2 baseline, because M3 had
!   no deck-to-ProblemState reader. M4-01 built that reader (yl_adapter_driver). This
!   program is the FULL chain the ADR promised to close:
!
!       legacy deck --adapt_legacy_deck--> problem_state_t --build_runtime-->
!       runtime_state_t --commit_legacy_globals--> real legacy globals
!       --(read back by THIS program)--> compared against
!       cases/golden/<case>/reference/state/model_ready/*.json
!
!   It is the successor to yl_runtime_bridge_test.f90 (M3-03's isolated bridge suite,
!   which built its own hand-made 1/2-element ProblemState because no adapter existed
!   yet). This program reuses that file's build/commit call shape verbatim
!   (`call build_runtime(problem, CONTRACT_TAG, rt, rmanifest, errors)` then
!   `call commit_legacy_globals(rt, errors)`) but feeds it a REAL golden deck instead.
!
! WHAT "COMPARE AGAINST THE FROZEN BASELINE" MEANS HERE
!   The 46 `model_ready` `RuntimeState.*` rows of docs/m2/state-field-map.toml are the
!   complete set commit_legacy_globals writes (see that module's header, "WHAT IS
!   WRITTEN"). Every row is read back from the REAL legacy globals this program itself
!   `use`s (global_var / prescribed / applied_load / meshfine -- not from `rt`, so the
!   check exercises the actual write-through, not just build_runtime's output) and
!   compared to the baseline JSON UNDER cases/golden/<case>/reference/state/model_ready/,
!   honouring each row's `compare.rule` from the map. The baseline is the reference; a
!   row this program cannot compare is reported UNVERIFIED or NOT_COMPARABLE, never MATCH.
!
! WHY A ROW'S "hash" RULE IS CHECKED BY ELEMENTWISE EQUALITY, NOT BY RECOMPUTING A DIGEST
!   Every `compare.rule = "hash"` row's baseline JSON carries BOTH a `sha256` digest AND
!   the full `values` array the digest was taken over (checked once per row, by hand,
!   against `docs/m2/state-field-map.toml` and a `python3 -c 'import json; ...'` dump of
!   the golden files before writing this program -- not assumed). Recomputing sha256 in
!   Fortran would need a hashing routine this repository does not have and would still
!   only prove "some bytes hash the same"; comparing every element directly proves
!   equality of the values themselves, which implies equality of any hash over them. So
!   elementwise comparison is a STRICTER check than the rule's own name promises, not a
!   weaker substitute for it.
!
! WHY THE RAGGED map ROWS (leldofix/levdofix/lefdofix, listp_group_listg/listp,
! unode_ipoin/ne_unode/list) ARE COMPARABLE AT ALL WITHOUT A JSON PARSER
!   Their baseline `values` are nested lists keyed by record (prescribed dof, node, or
!   group), and every JSON array in these files is the flattened Fortran array in
!   COLUMN-MAJOR order re-nested outer-to-inner from the LAST declared dimension to the
!   FIRST (checked against docs/m2/state-field-map.toml's `shape` column for
!   runtime.gauss.gpcod/cartd, whose nesting depth and outer/inner order matches shape
!   reversed exactly). That is precisely Fortran's own element order, so a leaf-order
!   flatten of the JSON `values` (this program's `flatten_tokens`, which walks bracket
!   nesting depth-first and does not care how deep it is) lines up index-for-index with
!   a legacy-side flatten built by looping outer collection then inner collection in the
!   same nesting order (record k=1..ndofix outer, then that record's lnefix-sized
!   sub-array; group ig outer, then its np_unode-sized unode(:), etc.). No offset table,
!   no re-keying by name, is needed on either side.
!
! WHAT THIS PROGRAM DOES NOT ESTABLISH
!   It compares state at ONE checkpoint (model_ready). It is not the shadow diff (M4-01's
!   own independent-process new-vs-old comparison) and it says nothing about numerical
!   result equivalence downstream of model_ready -- no solver consumer runs here, exactly
!   as in yl_runtime_bridge_test. It does not re-verify M3-03's own 108/108 self-test or
!   its 513/513 isolated-bridge suite; both are assumed still green (unchanged files).
!   Fourteen rows have `compare.rule = "ignore"`: they are reported NOT_COMPARABLE with
!   the reason taken from the value-state ledger (RESERVED / ABSENT / DEFINED-but-
!   unconsumed), never silently counted as MATCH.
!
! SCRATCH DISCIPLINE
!   This program never opens a file under `cases/`. Each golden deck's `legacy/`
!   directory is copied to a scratch directory under `build/l3b-scratch/<case>/` before
!   `adapt_legacy_deck` (which itself only ever opens files `status='old'`, but the
!   instruction is "never write into cases/", not "trust the adapter not to") and
!   `adapt_legacy_deck` is pointed at the copy.
!
! STOP RULE (team-lead instruction, not this program's own invention)
!   If ANY `compare.rule = "exact"` row disagrees with the baseline, this program prints
!   the row, both values, and the derivation site, then halts via `error stop` before
!   examining anything else. `hash` and `abs_tol` mismatches, if any, are reported in
!   full but do not halt the run -- the stop rule names "exact" rows specifically because
!   an exact-rule disagreement means a `build_runtime` derivation disagrees with legacy
!   on a value legacy asserts is deterministic, which is qualitatively different from a
!   tolerance or a hashed/ragged-reconstruction disagreement.
program yl_adapter_bridge_test

  use iso_fortran_env, only: int32, int64, real64, output_unit, error_unit

  use yl_problem_types, only: problem_state_t
  use yl_problem_deck_residue, only: deck_residue_t
  use yl_problem_existence, only: deck_existence_t
  use yl_problem_manifest, only: manifest_t
  use yl_problem_errors, only: problem_errors_t
  use yl_adapter_driver, only: adapt_legacy_deck

  use yl_runtime_types, only: runtime_state_t, runtime_status_get,                                &
                              RUNTIME_VALUE_DEFINED, RUNTIME_VALUE_RESERVED,                       &
                              RUNTIME_VALUE_ABSENT, RUNTIME_VALUE_UNSET
  use yl_runtime_contract, only: CONTRACT_TAG
  use yl_runtime_build, only: build_runtime
  use yl_runtime_commit, only: commit_legacy_globals

  ! The real legacy globals commit_legacy_globals writes -- read back DIRECTLY, not
  ! through `rt`, so the comparison exercises the write-through (see module header).
  use global_var, only: element, group, listp_group, trans, appear,                               &
                        lmdofn, nodfn, iffix, fixed,                                              &
                        result_zero, tofor, stfor, toforl, toform,                                &
                        npoin, nelem, ngroup, ndimn, mdofn, cdofn, ntotv, iblks, lblks
  use prescribed, only: prescrib, ndofix
  use applied_load, only: tcurves, ntcurve
  use meshfine, only: ice0

  implicit none

  integer, parameter :: N_CASES = 2
  character(len=*), parameter :: CASE_NAMES(N_CASES) = [character(len=32) :: &
    'cooks_membrane', 'lame_cylinder']
  character(len=*), parameter :: CASE_DIRS(N_CASES) = [character(len=64) :: &
    'cases/golden/static_2d/cooks_membrane', 'cases/golden/static_2d/lame_cylinder']

  integer :: n_match = 0, n_mismatch = 0, n_notcomp = 0, n_unverified = 0
  character(len=256) :: repo_root
  integer :: i, arglen, log_unit

  if (command_argument_count() >= 1) then
    call get_command_argument(1, repo_root, arglen)
  else
    repo_root = '.'
  end if

  open (newunit=log_unit, file='l3b_bridge_results.log', status='replace', action='write')
  write (log_unit, '(a)') 'case|map_id|rule|classification|detail'

  write (output_unit, '(a)') 'yl_adapter_bridge_test: L3-b adapter->runtime->commit bridge, '// &
    'compared against the frozen M2 baseline'

  do i = 1, N_CASES
    call run_case(trim(repo_root), trim(CASE_NAMES(i)), trim(CASE_DIRS(i)), log_unit)
  end do

  close (log_unit)

  write (output_unit, '(a)') ''
  write (output_unit, '(a,i0,a,i0,a,i0,a,i0)')                                                    &
    'TOTALS  MATCH=', n_match, '  MISMATCH=', n_mismatch,                                         &
    '  NOT_COMPARABLE=', n_notcomp, '  UNVERIFIED=', n_unverified
  write (output_unit, '(a)') 'Full row log: l3b_bridge_results.log'
  if (n_mismatch > 0) then
    write (output_unit, '(a)') 'CONCLUSION: DISAGREEMENT FOUND -- see mismatches above/in the log.'
  else
    write (output_unit, '(a)') 'CONCLUSION: no mismatch found in this run; see the log for '// &
      'UNVERIFIED/NOT_COMPARABLE rows -- absence of a mismatch is not the same as a full MATCH.'
  end if

contains

  ! ============================================================================
  ! one golden case: adapt -> build -> commit -> read back -> compare 46 rows
  ! ============================================================================
  subroutine run_case(root, case_name, case_dir, ulog)
    character(len=*), intent(in) :: root, case_name, case_dir
    integer, intent(in) :: ulog

    character(len=512) :: scratch, legacy_src
    character(len=2048) :: cmd   ! holds scratch+legacy_src twice over; 512 truncates on a long repo root
    integer :: rc, cs
    type(problem_state_t), allocatable :: problem
    type(deck_residue_t) :: residue
    type(deck_existence_t) :: existence
    type(manifest_t), allocatable :: pmanifest, rmanifest
    type(problem_errors_t) :: errors
    type(runtime_state_t), allocatable :: rt
    character(len=:), allocatable :: j_control, j_dof, j_mesh, j_steps, j_loads
    character(len=:), allocatable :: ref_dir

    write (output_unit, '(a)') ''
    write (output_unit, '(a)') '== case: '//case_name//' =='

    legacy_src = trim(root)//'/'//trim(case_dir)//'/legacy'
    scratch = trim(root)//'/build/l3b-scratch/'//trim(case_name)
    cmd = 'rm -rf '//trim(scratch)//' && mkdir -p '//trim(scratch)// &
          ' && cp -a '//trim(legacy_src)//'/. '//trim(scratch)//'/'
    call execute_command_line(trim(cmd), exitstat=rc, cmdstat=cs)
    if (cs /= 0 .or. rc /= 0) then
      write (output_unit, '(a)') '  ABORT: could not stage a scratch copy of the deck ('// &
        'cmdstat='//itoa(cs)//' exitstat='//itoa(rc)//'); every row for this case is UNVERIFIED.'
      call fail_all_rows(case_name, ulog, 'scratch copy of legacy/ failed before adapt_legacy_deck ran')
      return
    end if

    ! -- 1. legacy deck -> problem_state_t -----------------------------------------
    call adapt_legacy_deck(trim(scratch), problem, residue, existence, pmanifest, errors)
    if (errors%any() .or. .not. allocated(problem)) then
      write (output_unit, '(a)') '  ABORT: adapt_legacy_deck reported a finding; every row UNVERIFIED.'
      call report_errors('adapt_legacy_deck', errors)
      call fail_all_rows(case_name, ulog, 'adapt_legacy_deck raised a finding -- see stdout')
      return
    end if
    write (output_unit, '(a)') '  adapt_legacy_deck: ok'

    ! -- 2. problem_state_t -> runtime_state_t --------------------------------------
    call build_runtime(problem, CONTRACT_TAG, rt, rmanifest, errors)
    if (errors%any() .or. .not. allocated(rt)) then
      write (output_unit, '(a)') '  ABORT: build_runtime reported a finding; every row UNVERIFIED.'
      call report_errors('build_runtime', errors)
      call fail_all_rows(case_name, ulog, 'build_runtime raised a finding -- see stdout')
      return
    end if
    write (output_unit, '(a)') '  build_runtime: ok'

    ! -- 3. runtime_state_t -> real legacy globals ----------------------------------
    ! `.tem` fills four of the residue's 27 components (M4-01 step 4b); the other 23 are
    ! still unset and commit still reads none of them until step 5.
    call commit_legacy_globals(problem, residue, existence, rt, errors)
    if (errors%any()) then
      write (output_unit, '(a)') '  ABORT: commit_legacy_globals reported a finding; every row UNVERIFIED.'
      call report_errors('commit_legacy_globals', errors)
      call fail_all_rows(case_name, ulog, 'commit_legacy_globals raised a finding -- see stdout')
      return
    end if
    write (output_unit, '(a)') '  commit_legacy_globals: ok'

    ! -- 4. load the frozen baseline (one open per snapshot file this case needs) ---
    ref_dir = trim(root)//'/'//trim(case_dir)//'/reference/state/model_ready'
    j_control = read_text_file(ref_dir//'/control.json')
    j_dof = read_text_file(ref_dir//'/dof.json')
    j_mesh = read_text_file(ref_dir//'/mesh.json')
    j_steps = read_text_file(ref_dir//'/steps.json')
    j_loads = read_text_file(ref_dir//'/loads.json')

    ! -- 5. the 46 model_ready RuntimeState.* rows ----------------------------------
    call compare_all_rows(case_name, ulog, rt, j_control, j_dof, j_mesh, j_steps, j_loads)
  end subroutine run_case

  ! Every row UNVERIFIED with the same reason, used when a pipeline stage aborted
  ! before there was anything to read back. Never silently skipped -- a row this
  ! program never reached is UNVERIFIED, not absent from the report.
  subroutine fail_all_rows(case_name, ulog, reason)
    character(len=*), intent(in) :: case_name, reason
    integer, intent(in) :: ulog
    integer :: k
    character(len=48) :: ids(46)
    call all_row_ids(ids)
    do k = 1, 46
      call emit(ulog, case_name, trim(ids(k)), '(n/a)', 'UNVERIFIED', reason)
    end do
  end subroutine fail_all_rows

  subroutine all_row_ids(ids)
    character(len=48), intent(out) :: ids(46)
    ids = [character(len=48) ::                                                                   &
      'runtime.amplitudes.dfact', 'runtime.dof.lmdofn',                                           &
      'runtime.increment.iblks_at_model', 'runtime.increment.lblks_at_model',                     &
      'runtime.activation.appear', 'runtime.boundary.ldofix', 'runtime.boundary.lnefix',          &
      'runtime.boundary.leldofix', 'runtime.boundary.levdofix', 'runtime.boundary.lefdofix',      &
      'runtime.dof.iffix', 'runtime.dof.fixed', 'runtime.dof.nodfn', 'runtime.dof.ntotv',         &
      'runtime.dof.ldofs', 'runtime.dof.ldofs_f', 'runtime.dof.trans_nintf',                      &
      'runtime.topology.listp_group_mgroup', 'runtime.topology.listp_group_listg',                &
      'runtime.topology.listp_group_listp', 'runtime.topology.unode_ipoin',                       &
      'runtime.topology.unode_ne_unode', 'runtime.topology.unode_list',                           &
      'runtime.topology.unode_np_unode', 'runtime.topology.unode_patch_nod',                       &
      'runtime.gauss.djacb', 'runtime.gauss.gpcod', 'runtime.gauss.cartd',                        &
      'runtime.gauss.djacb_mass', 'runtime.gauss.gpcod_mass', 'runtime.element.elcod_f',          &
      'runtime.element.tload', 'runtime.element.eload', 'runtime.element.rload',                  &
      'runtime.vectors.result_zero', 'runtime.vectors.tofor', 'runtime.vectors.stfor',            &
      'runtime.vectors.toforl', 'runtime.vectors.toform', 'runtime.vectors.delitfi',              &
      'runtime.vectors.deltafi', 'runtime.element.ice0', 'runtime.cursor.lineload',                &
      'runtime.cursor.line_load_block', 'runtime.cursor.linet', 'runtime.cursor.line_temp_block' ]
  end subroutine all_row_ids

  ! ============================================================================
  ! the 46 rows, one call each. Order follows docs/m2/state-field-map.toml's own
  ! "fields @ model_ready" section (the order they appear in that file).
  ! ============================================================================
  subroutine compare_all_rows(cn, ulog, rt, j_control, j_dof, j_mesh, j_steps, j_loads)
    character(len=*), intent(in) :: cn
    integer, intent(in) :: ulog
    type(runtime_state_t), intent(in) :: rt
    character(len=*), intent(in) :: j_control, j_dof, j_mesh, j_steps, j_loads

    integer :: nevab, ngaus, ncartd, ngpcod, nnode_egaus

    ! -- exact-rule scalars/vectors (checked first: the STOP rule fires here) -------
    call check_ledger(cn, ulog, rt, 'runtime.amplitudes.dfact', RUNTIME_VALUE_DEFINED)
    call compare_f64(cn, ulog, j_loads, 'runtime.amplitudes.dfact', 'exact',                       &
                     real(tcurves(1:ntcurve)%dfact, real64), 0.0_real64, 0.0_real64)

    call check_ledger(cn, ulog, rt, 'runtime.dof.lmdofn', RUNTIME_VALUE_DEFINED)
    call compare_i32(cn, ulog, j_dof, 'runtime.dof.lmdofn', 'exact',                                &
                     int(pack(lmdofn(1:mdofn), .true.), int32))

    call check_ledger(cn, ulog, rt, 'runtime.increment.iblks_at_model', RUNTIME_VALUE_DEFINED)
    call compare_i32(cn, ulog, j_control, 'runtime.increment.iblks_at_model', 'exact',              &
                     [int(iblks, int32)])

    call check_ledger(cn, ulog, rt, 'runtime.increment.lblks_at_model', RUNTIME_VALUE_DEFINED)
    call compare_i32(cn, ulog, j_control, 'runtime.increment.lblks_at_model', 'exact',              &
                     [int(lblks, int32)])

    call check_ledger(cn, ulog, rt, 'runtime.activation.appear', RUNTIME_VALUE_DEFINED)
    call compare_i32(cn, ulog, j_steps, 'runtime.activation.appear', 'exact',                       &
                     int(pack(appear(1:ngroup), .true.), int32))

    call check_ledger(cn, ulog, rt, 'runtime.dof.iffix', RUNTIME_VALUE_DEFINED)
    call compare_i32(cn, ulog, j_dof, 'runtime.dof.iffix', 'exact',                                 &
                     int(pack(iffix(1:ntotv), .true.), int32))

    call check_ledger(cn, ulog, rt, 'runtime.dof.fixed', RUNTIME_VALUE_DEFINED)
    call compare_f64(cn, ulog, j_dof, 'runtime.dof.fixed', 'exact',                                 &
                     pack(fixed(1:ntotv), .true.), 0.0_real64, 0.0_real64)

    call check_ledger(cn, ulog, rt, 'runtime.dof.ntotv', RUNTIME_VALUE_DEFINED)
    call compare_i32(cn, ulog, j_dof, 'runtime.dof.ntotv', 'exact', [int(ntotv, int32)])

    call check_ledger(cn, ulog, rt, 'runtime.dof.trans_nintf', RUNTIME_VALUE_DEFINED)
    call compare_i32(cn, ulog, j_dof, 'runtime.dof.trans_nintf', 'exact',                           &
                     int(trans(1:ntotv)%nintf, int32))

    call check_ledger(cn, ulog, rt, 'runtime.vectors.result_zero', RUNTIME_VALUE_DEFINED)
    call compare_f64(cn, ulog, j_dof, 'runtime.vectors.result_zero', 'exact',                       &
                     pack(result_zero(1:ntotv), .true.), 0.0_real64, 0.0_real64)

    call check_ledger(cn, ulog, rt, 'runtime.vectors.tofor', RUNTIME_VALUE_DEFINED)
    call compare_f64(cn, ulog, j_dof, 'runtime.vectors.tofor', 'exact',                             &
                     pack(tofor(1:ntotv), .true.), 0.0_real64, 0.0_real64)

    call check_ledger(cn, ulog, rt, 'runtime.vectors.stfor', RUNTIME_VALUE_DEFINED)
    call compare_f64(cn, ulog, j_dof, 'runtime.vectors.stfor', 'exact',                             &
                     pack(stfor(1:ntotv), .true.), 0.0_real64, 0.0_real64)

    call check_ledger(cn, ulog, rt, 'runtime.vectors.toforl', RUNTIME_VALUE_DEFINED)
    call compare_f64(cn, ulog, j_dof, 'runtime.vectors.toforl', 'exact',                            &
                     pack(toforl(1:ntotv), .true.), 0.0_real64, 0.0_real64)

    call check_ledger(cn, ulog, rt, 'runtime.vectors.toform', RUNTIME_VALUE_DEFINED)
    call compare_f64(cn, ulog, j_dof, 'runtime.vectors.toform', 'exact',                            &
                     pack(toform(1:ntotv), .true.), 0.0_real64, 0.0_real64)

    call check_ledger(cn, ulog, rt, 'runtime.element.ice0', RUNTIME_VALUE_DEFINED)
    call compare_i32(cn, ulog, j_mesh, 'runtime.element.ice0', 'exact',                             &
                     int(pack(ice0(1:nelem), .true.), int32))

    ! -- hash-rule rows (elementwise equality -- see module header) -----------------
    call check_ledger(cn, ulog, rt, 'runtime.boundary.ldofix', RUNTIME_VALUE_DEFINED)
    call compare_i32(cn, ulog, j_dof, 'runtime.boundary.ldofix', 'hash',                            &
                     int(prescrib(1:ndofix)%ldofix, int32))

    call check_ledger(cn, ulog, rt, 'runtime.boundary.lnefix', RUNTIME_VALUE_DEFINED)
    call compare_i32(cn, ulog, j_dof, 'runtime.boundary.lnefix', 'hash',                            &
                     int(prescrib(1:ndofix)%lnefix, int32))

    call check_ledger(cn, ulog, rt, 'runtime.boundary.leldofix', RUNTIME_VALUE_DEFINED)
    call compare_i32(cn, ulog, j_dof, 'runtime.boundary.leldofix', 'hash', ragged_prescrib_i32(1))

    call check_ledger(cn, ulog, rt, 'runtime.boundary.levdofix', RUNTIME_VALUE_DEFINED)
    call compare_i32(cn, ulog, j_dof, 'runtime.boundary.levdofix', 'hash', ragged_prescrib_i32(2))

    call check_ledger(cn, ulog, rt, 'runtime.boundary.lefdofix', RUNTIME_VALUE_DEFINED)
    call compare_i32(cn, ulog, j_dof, 'runtime.boundary.lefdofix', 'hash', ragged_prescrib_i32(3))

    call check_ledger(cn, ulog, rt, 'runtime.dof.nodfn', RUNTIME_VALUE_DEFINED)
    call compare_i32(cn, ulog, j_dof, 'runtime.dof.nodfn', 'hash',                                  &
                     int(pack(nodfn(1:cdofn, 1:npoin), .true.), int32))

    call check_ledger(cn, ulog, rt, 'runtime.dof.ldofs', RUNTIME_VALUE_DEFINED)
    call compare_i32(cn, ulog, j_dof, 'runtime.dof.ldofs', 'hash', legacy_ldofs())

    call check_ledger(cn, ulog, rt, 'runtime.dof.ldofs_f', RUNTIME_VALUE_DEFINED)
    call compare_i32(cn, ulog, j_dof, 'runtime.dof.ldofs_f', 'hash', legacy_ldofs_f())

    call check_ledger(cn, ulog, rt, 'runtime.topology.listp_group_mgroup', RUNTIME_VALUE_DEFINED)
    call compare_i32(cn, ulog, j_mesh, 'runtime.topology.listp_group_mgroup', 'hash',               &
                     int(listp_group(1:npoin)%mgroup, int32))

    call check_ledger(cn, ulog, rt, 'runtime.topology.listp_group_listg', RUNTIME_VALUE_DEFINED)
    call compare_i32(cn, ulog, j_mesh, 'runtime.topology.listp_group_listg', 'hash',                &
                     ragged_listp_group_i32(.true.))

    call check_ledger(cn, ulog, rt, 'runtime.topology.listp_group_listp', RUNTIME_VALUE_DEFINED)
    call compare_i32(cn, ulog, j_mesh, 'runtime.topology.listp_group_listp', 'hash',                &
                     ragged_listp_group_i32(.false.))

    call check_ledger(cn, ulog, rt, 'runtime.topology.unode_ipoin', RUNTIME_VALUE_DEFINED)
    call compare_i32(cn, ulog, j_mesh, 'runtime.topology.unode_ipoin', 'hash',                      &
                     ragged_unode_scalar_i32(1))

    call check_ledger(cn, ulog, rt, 'runtime.topology.unode_ne_unode', RUNTIME_VALUE_DEFINED)
    call compare_i32(cn, ulog, j_mesh, 'runtime.topology.unode_ne_unode', 'hash',                   &
                     ragged_unode_scalar_i32(2))

    call check_ledger(cn, ulog, rt, 'runtime.topology.unode_list', RUNTIME_VALUE_DEFINED)
    call compare_i32(cn, ulog, j_mesh, 'runtime.topology.unode_list', 'hash', ragged_unode_list_i32())

    ! -- abs_tol-rule rows (Q4 Gauss geometry; atol=1e-14, rtol=1e-12 from the map) --
    ngaus = size(element(1)%egaus(1)%djacb)
    ngpcod = size(element(1)%egaus(1)%gpcod)
    ncartd = size(element(1)%egaus(1)%cartd)
    nnode_egaus = size(element(1)%egaus(1)%cartd, 2)
    nevab = size(element(1)%ldofs)

    call check_ledger(cn, ulog, rt, 'runtime.gauss.djacb', RUNTIME_VALUE_DEFINED)
    call compare_f64(cn, ulog, j_mesh, 'runtime.gauss.djacb', 'abs_tol',                            &
                     legacy_egaus_flat(1, ngaus), 1.0e-14_real64, 1.0e-12_real64)

    call check_ledger(cn, ulog, rt, 'runtime.gauss.gpcod', RUNTIME_VALUE_DEFINED)
    call compare_f64(cn, ulog, j_mesh, 'runtime.gauss.gpcod', 'abs_tol',                            &
                     legacy_egaus_flat(2, ngpcod), 1.0e-14_real64, 1.0e-12_real64)

    call check_ledger(cn, ulog, rt, 'runtime.gauss.cartd', RUNTIME_VALUE_DEFINED)
    call compare_f64(cn, ulog, j_mesh, 'runtime.gauss.cartd', 'abs_tol',                            &
                     legacy_egaus_flat(3, ncartd), 1.0e-14_real64, 1.0e-12_real64)

    ! -- ignore-rule rows: NOT_COMPARABLE by rule, classified by the ledger's own three
    !    situations (docs/m3/M3-03-runtime.md S3). No legacy memory is read for these:
    !    two of them (RESERVED contents, and the ABSENT pointer) are UNDEFINED / not even
    !    safe to call associated() on, per that module's own header. The ledger check
    !    (a safe read of build_runtime's own bookkeeping, never of the raw memory) is the
    !    only assertion made about them here.
    call check_ledger(cn, ulog, rt, 'runtime.gauss.djacb_mass', RUNTIME_VALUE_DEFINED)
    call emit(ulog, cn, 'runtime.gauss.djacb_mass', 'ignore', 'NOT_COMPARABLE',                     &
             'DEFINED but unconsumed: egaus(2) mass-rule geometry, computed but no static_2d '// &
             'consumer reads it (order_intrules=(/1,1/)); map excludes it from the snapshot')

    call check_ledger(cn, ulog, rt, 'runtime.gauss.gpcod_mass', RUNTIME_VALUE_DEFINED)
    call emit(ulog, cn, 'runtime.gauss.gpcod_mass', 'ignore', 'NOT_COMPARABLE',                     &
             'DEFINED but unconsumed: same reason as runtime.gauss.djacb_mass')

    call check_ledger(cn, ulog, rt, 'runtime.element.elcod_f', RUNTIME_VALUE_DEFINED)
    call emit(ulog, cn, 'runtime.element.elcod_f', 'ignore', 'NOT_COMPARABLE',                      &
             'DEFINED but redundant: element-local copy of mesh.nodes.xyz, already compared '// &
             'via the mesh checkpoint; map excludes the copy from the snapshot')

    call check_ledger(cn, ulog, rt, 'runtime.element.tload', RUNTIME_VALUE_RESERVED)
    call emit(ulog, cn, 'runtime.element.tload', 'ignore', 'NOT_COMPARABLE',                        &
             'RESERVED: allocated at model_ready, contents undefined until the first '// &
             'assembly (Global.f90:1321-1323); must not be read, so it is not')

    call check_ledger(cn, ulog, rt, 'runtime.element.eload', RUNTIME_VALUE_RESERVED)
    call emit(ulog, cn, 'runtime.element.eload', 'ignore', 'NOT_COMPARABLE', 'RESERVED: same reason as runtime.element.tload')

    call check_ledger(cn, ulog, rt, 'runtime.element.rload', RUNTIME_VALUE_RESERVED)
    call emit(ulog, cn, 'runtime.element.rload', 'ignore', 'NOT_COMPARABLE', 'RESERVED: same reason as runtime.element.tload')

    call check_ledger(cn, ulog, rt, 'runtime.vectors.delitfi', RUNTIME_VALUE_RESERVED)
    call emit(ulog, cn, 'runtime.vectors.delitfi', 'ignore', 'NOT_COMPARABLE',                      &
             'RESERVED: allocated Fem.f90:246, first assigned Fem.f90:3693/3716 -- after model_ready')

    call check_ledger(cn, ulog, rt, 'runtime.vectors.deltafi', RUNTIME_VALUE_RESERVED)
    call emit(ulog, cn, 'runtime.vectors.deltafi', 'ignore', 'NOT_COMPARABLE', 'RESERVED: same reason as runtime.vectors.delitfi')

    call check_ledger(cn, ulog, rt, 'runtime.cursor.lineload', RUNTIME_VALUE_RESERVED)
    call emit(ulog, cn, 'runtime.cursor.lineload', 'ignore', 'NOT_COMPARABLE',                      &
             'RESERVED (recorded via publish_check_vacuous): runtime_only restart-cursor '// &
             'bookkeeping, no model_ready assertion in the map')

    call check_ledger(cn, ulog, rt, 'runtime.cursor.line_load_block', RUNTIME_VALUE_RESERVED)
    call emit(ulog, cn, 'runtime.cursor.line_load_block', 'ignore', 'NOT_COMPARABLE',               &
             'RESERVED: same reason as runtime.cursor.lineload')

    call check_ledger(cn, ulog, rt, 'runtime.cursor.linet', RUNTIME_VALUE_RESERVED)
    call emit(ulog, cn, 'runtime.cursor.linet', 'ignore', 'NOT_COMPARABLE',                         &
             'RESERVED: same reason as runtime.cursor.lineload')

    call check_ledger(cn, ulog, rt, 'runtime.cursor.line_temp_block', RUNTIME_VALUE_RESERVED)
    call emit(ulog, cn, 'runtime.cursor.line_temp_block', 'ignore', 'NOT_COMPARABLE',               &
             'RESERVED: same reason as runtime.cursor.lineload')

    call check_ledger(cn, ulog, rt, 'runtime.topology.unode_np_unode', RUNTIME_VALUE_ABSENT)
    call emit(ulog, cn, 'runtime.topology.unode_np_unode', 'ignore', 'NOT_COMPARABLE',              &
             'ABSENT: assigned only in the stabpw P/W branch (Global.f90:1425-1439), not taken '// &
             'on static_2d; the asserted property is the absence itself, confirmed only via the '// &
             'ledger above -- the scalar is not read directly (undefined, not a structural fact)')

    call check_ledger(cn, ulog, rt, 'runtime.topology.unode_patch_nod', RUNTIME_VALUE_ABSENT)
    call emit(ulog, cn, 'runtime.topology.unode_patch_nod', 'ignore', 'NOT_COMPARABLE',             &
             'ABSENT: pointer allocated only in the same stabpw branch; on this path even '// &
             'associated() on it is unsafe (module header), so only the ledger is consulted')
  end subroutine compare_all_rows

  ! --------------------------------------------------------------------------
  ! ragged legacy-side flatteners (see module header for why leaf order matches)
  ! --------------------------------------------------------------------------

  !> which=1 leldofix, 2 levdofix, 3 lefdofix. Concatenates prescrib(k)'s lnefix-sized
  !> sub-array for k = 1..ndofix, in record order -- the same order the map's
  !> `index_by = "steps[0].boundary[].name"` and the adapter's own `emit =
  !> adapter:runtime_boundary_*` note say the baseline was built in.
  function ragged_prescrib_i32(which) result(arr)
    integer, intent(in) :: which
    integer(int32), allocatable :: arr(:)
    integer :: k, m, ntot, pos
    ntot = 0
    do k = 1, ndofix
      ntot = ntot + prescrib(k)%lnefix
    end do
    allocate (arr(ntot))
    pos = 0
    do k = 1, ndofix
      m = prescrib(k)%lnefix
      select case (which)
      case (1); arr(pos + 1:pos + m) = int(prescrib(k)%leldofix(1:m), int32)
      case (2); arr(pos + 1:pos + m) = int(prescrib(k)%levdofix(1:m), int32)
      case (3); arr(pos + 1:pos + m) = int(prescrib(k)%lefdofix(1:m), int32)
      end select
      pos = pos + m
    end do
  end function ragged_prescrib_i32

  !> listg (want_listg=.true.) or listp (.false.), concatenated node-major: for each
  !> ipoin = 1..npoin, that node's mgroup-sized sub-array. mgroup is 1 on both golden
  !> cases (ngroup=1), so this degenerates to one entry per node, but the loop makes no
  !> such assumption.
  function ragged_listp_group_i32(want_listg) result(arr)
    logical, intent(in) :: want_listg
    integer(int32), allocatable :: arr(:)
    integer :: ip, m, ntot, pos
    ntot = 0
    do ip = 1, npoin
      ntot = ntot + listp_group(ip)%mgroup
    end do
    allocate (arr(ntot))
    pos = 0
    do ip = 1, npoin
      m = listp_group(ip)%mgroup
      if (want_listg) then
        arr(pos + 1:pos + m) = int(listp_group(ip)%listg(1:m), int32)
      else
        arr(pos + 1:pos + m) = int(listp_group(ip)%listp(1:m), int32)
      end if
      pos = pos + m
    end do
  end function ragged_listp_group_i32

  !> which=1 unode(:)%ipoin, 2 unode(:)%ne_unode -- one scalar per unode entry,
  !> concatenated group-major then local-node-major (group(ig)%np_unode entries per
  !> group). Both golden cases have ngroup=1, so this is one group's list, but again the
  !> loop does not assume it.
  function ragged_unode_scalar_i32(which) result(arr)
    integer, intent(in) :: which
    integer(int32), allocatable :: arr(:)
    integer :: ig, ip, ntot, pos
    ntot = 0
    do ig = 1, ngroup
      ntot = ntot + group(ig)%np_unode
    end do
    allocate (arr(ntot))
    pos = 0
    do ig = 1, ngroup
      do ip = 1, group(ig)%np_unode
        pos = pos + 1
        if (which == 1) then
          arr(pos) = int(group(ig)%unode(ip)%ipoin, int32)
        else
          arr(pos) = int(group(ig)%unode(ip)%ne_unode, int32)
        end if
      end do
    end do
  end function ragged_unode_scalar_i32

  !> group(ig)%unode(ip)%list(1:ne_unode(ip)), doubly ragged: outer over (group, local
  !> node), inner over that node's own attached-element count.
  function ragged_unode_list_i32() result(arr)
    integer(int32), allocatable :: arr(:)
    integer :: ig, ip, m, ntot, pos
    ntot = 0
    do ig = 1, ngroup
      do ip = 1, group(ig)%np_unode
        ntot = ntot + group(ig)%unode(ip)%ne_unode
      end do
    end do
    allocate (arr(ntot))
    pos = 0
    do ig = 1, ngroup
      do ip = 1, group(ig)%np_unode
        m = group(ig)%unode(ip)%ne_unode
        arr(pos + 1:pos + m) = int(group(ig)%unode(ip)%list(1:m), int32)
        pos = pos + m
      end do
    end do
  end function ragged_unode_list_i32

  !> element(:)%ldofs(:), concatenated element-major (ie=1..nelem outer, dof position
  !> inner) -- matches map shape ["nevab","nelem"] reversed, i.e. element outer.
  function legacy_ldofs() result(arr)
    integer(int32), allocatable :: arr(:)
    integer :: ie, m, ntot, pos
    m = size(element(1)%ldofs)
    ntot = m*nelem
    allocate (arr(ntot))
    pos = 0
    do ie = 1, nelem
      arr(pos + 1:pos + m) = int(element(ie)%ldofs(1:m), int32)
      pos = pos + m
    end do
  end function legacy_ldofs

  function legacy_ldofs_f() result(arr)
    integer(int32), allocatable :: arr(:)
    integer :: ie, m, ntot, pos
    m = size(element(1)%field(1)%ldofs_f)
    ntot = m*nelem
    allocate (arr(ntot))
    pos = 0
    do ie = 1, nelem
      arr(pos + 1:pos + m) = int(element(ie)%field(1)%ldofs_f(1:m), int32)
      pos = pos + m
    end do
  end function legacy_ldofs_f

  !> which=1 djacb (1-D per element), 2 gpcod (2-D, ndimn x ngaus), 3 cartd (3-D, ndimn x
  !> nnode x ngaus). `pack` on a Fortran array returns its elements in column-major
  !> (first-subscript-fastest) order, which is exactly the order the map's `shape`
  !> column names its dimensions in (fastest first) -- so concatenating `pack` results
  !> element-major reproduces the baseline's own flatten (see module header).
  function legacy_egaus_flat(which, per_elem) result(arr)
    integer, intent(in) :: which, per_elem
    real(real64), allocatable :: arr(:)
    integer :: ie, ntot, pos
    ntot = per_elem*nelem
    allocate (arr(ntot))
    pos = 0
    do ie = 1, nelem
      select case (which)
      case (1); arr(pos + 1:pos + per_elem) = real(element(ie)%egaus(1)%djacb, real64)
      case (2); arr(pos + 1:pos + per_elem) = real(pack(element(ie)%egaus(1)%gpcod, .true.), real64)
      case (3); arr(pos + 1:pos + per_elem) = real(pack(element(ie)%egaus(1)%cartd, .true.), real64)
      end select
      pos = pos + per_elem
    end do
  end function legacy_egaus_flat

  ! ============================================================================
  ! the value-state ledger cross-check: a SAFE read of build_runtime's own
  ! bookkeeping (never of raw legacy/runtime memory) confirming that this row's
  ! DEFINED/RESERVED/ABSENT classification -- fixed by reading yl_runtime_build.f90's
  ! publish_reserved/publish_absent/publish_check_vacuous call sites once, by hand,
  ! before writing this program -- still holds for the build actually produced here.
  ! A disagreement here is reported but does not by itself trigger the exact-rule STOP
  ! rule (it is a ledger-vs-expectation disagreement, not a value-vs-baseline one).
  ! ============================================================================
  subroutine check_ledger(cn, ulog, rt, map_id, expected)
    character(len=*), intent(in) :: cn, map_id
    integer, intent(in) :: ulog
    type(runtime_state_t), intent(in) :: rt
    integer(int32), intent(in) :: expected
    integer(int32) :: state
    logical :: found
    character(len=200) :: detail
    call runtime_status_get(rt, map_id, state, found)
    if (.not. found) then
      detail = 'MISSING from runtime%field_status'
      write (output_unit, '(a)') '  LEDGER  '//trim(cn)//'  '//trim(map_id)//'  '//trim(detail)
      write (ulog, '(a)') trim(cn)//'|'//trim(map_id)//'|ledger|LEDGER_MISSING|'//trim(detail)
      return
    end if
    if (state /= expected) then
      write (detail, '(a,i0,a,i0)') 'ledger disagreement: expected state ', expected,               &
        ' (from yl_runtime_build.f90 publish_* call sites), runtime reports ', state
      write (output_unit, '(a)') '  LEDGER  '//trim(cn)//'  '//trim(map_id)//'  '//trim(detail)
      write (ulog, '(a)') trim(cn)//'|'//trim(map_id)//'|ledger|LEDGER_MISMATCH|'//trim(detail)
    end if
  end subroutine check_ledger

  ! ============================================================================
  ! comparison drivers
  ! ============================================================================

  subroutine compare_i32(cn, ulog, jtext, map_id, rule, legacy)
    character(len=*), intent(in) :: cn, jtext, map_id, rule
    integer(int32), intent(in) :: legacy(:)
    integer, intent(in) :: ulog
    integer(int32), allocatable :: ref(:)
    logical :: ok
    integer :: i, nbad
    character(len=300) :: detail

    call load_i32_ref(jtext, map_id, ref, ok)
    if (.not. ok) then
      call emit(ulog, cn, map_id, rule, 'UNVERIFIED',                                              &
               'no "'//trim(map_id)//'" field (or no "values" entry) in the baseline json')
      return
    end if
    if (size(ref) /= size(legacy)) then
      write (detail, '(a,i0,a,i0)') 'shape mismatch: baseline has ', size(ref),                     &
        ' flattened values, runtime flattened to ', size(legacy)
      call emit(ulog, cn, map_id, rule, 'MISMATCH', trim(detail))
      if (rule == 'exact') call stop_on_exact_mismatch(cn, map_id, trim(detail))
      return
    end if
    nbad = count(ref /= legacy)
    if (nbad == 0) then
      write (detail, '(a,i0,a)') 'match, n=', size(ref), ' values, elementwise equal'
      call emit(ulog, cn, map_id, rule, 'MATCH', trim(detail))
    else
      detail = 'no mismatch located (unexpected)'
      do i = 1, size(ref)
        if (ref(i) /= legacy(i)) then
          write (detail, '(a,i0,a,i0,a,i0,a,i0,a)') 'first mismatch at flat index ', i, ' of ',    &
            size(ref), ': baseline=', ref(i), ' runtime=', legacy(i), ' ('//itoa(nbad)//           &
            ' of '//itoa(size(ref))//' elements differ)'
          exit
        end if
      end do
      call emit(ulog, cn, map_id, rule, 'MISMATCH', trim(detail))
      if (rule == 'exact') call stop_on_exact_mismatch(cn, map_id, trim(detail))
    end if
  end subroutine compare_i32

  !> rule='exact' is passed with atol=rtol=0, which for the all-zero exact f64 rows
  !> (docs/m2/state-field-map.toml's own "R24" notes) is a bit-exact test: 0.0d0 either
  !> side of the comparison has no rounding to tolerate. rule='abs_tol' uses the
  !> atol/rtol the caller took from that row's own `compare` table entry.
  subroutine compare_f64(cn, ulog, jtext, map_id, rule, legacy, atol, rtol)
    character(len=*), intent(in) :: cn, jtext, map_id, rule
    real(real64), intent(in) :: legacy(:), atol, rtol
    integer, intent(in) :: ulog
    real(real64), allocatable :: ref(:)
    logical :: ok
    integer :: i, nbad
    real(real64) :: worst, thresh, d
    character(len=300) :: detail

    call load_f64_ref(jtext, map_id, ref, ok)
    if (.not. ok) then
      call emit(ulog, cn, map_id, rule, 'UNVERIFIED',                                              &
               'no "'//trim(map_id)//'" field (or no "values" entry) in the baseline json')
      return
    end if
    if (size(ref) /= size(legacy)) then
      write (detail, '(a,i0,a,i0)') 'shape mismatch: baseline has ', size(ref),                     &
        ' flattened values, runtime flattened to ', size(legacy)
      call emit(ulog, cn, map_id, rule, 'MISMATCH', trim(detail))
      if (rule == 'exact') call stop_on_exact_mismatch(cn, map_id, trim(detail))
      return
    end if
    nbad = 0
    worst = 0.0_real64
    do i = 1, size(ref)
      d = abs(ref(i) - legacy(i))
      thresh = atol + rtol*abs(ref(i))
      if (d > thresh) nbad = nbad + 1
      if (d > worst) worst = d
    end do
    if (nbad == 0) then
      if (rule == 'abs_tol') then
        write (detail, '(a,i0,a,es10.3,a,es8.1,a,es8.1)') 'match, n=', size(ref),                  &
          ' values within tolerance, worst |diff|=', worst, ', atol=', atol, ' rtol=', rtol
      else
        write (detail, '(a,i0,a)') 'match, n=', size(ref), ' values, bit-exact (all zero)'
      end if
      call emit(ulog, cn, map_id, rule, 'MATCH', trim(detail))
    else
      detail = 'no mismatch located (unexpected)'
      do i = 1, size(ref)
        d = abs(ref(i) - legacy(i))
        thresh = atol + rtol*abs(ref(i))
        if (d > thresh) then
          write (detail, '(a,i0,a,i0,a,es22.15,a,es22.15,a,i0,a,i0,a)')                            &
            'first mismatch at flat index ', i, ' of ', size(ref), ': baseline=', ref(i),          &
            ' runtime=', legacy(i), ' ('//itoa(nbad)//' of '//itoa(size(ref))//' elements exceed tolerance)'
          exit
        end if
      end do
      call emit(ulog, cn, map_id, rule, 'MISMATCH', trim(detail))
      if (rule == 'exact') call stop_on_exact_mismatch(cn, map_id, trim(detail))
    end if
  end subroutine compare_f64

  subroutine stop_on_exact_mismatch(cn, map_id, detail)
    character(len=*), intent(in) :: cn, map_id, detail
    write (error_unit, '(a)') ''
    write (error_unit, '(a)') '================================================================'
    write (error_unit, '(a)') 'STOP RULE TRIGGERED: an exact-rule row disagrees with the frozen baseline.'
    write (error_unit, '(a)') 'case:   '//cn
    write (error_unit, '(a)') 'row:    '//map_id
    write (error_unit, '(a)') 'detail: '//detail
    write (error_unit, '(a)') 'This means a build_runtime derivation disagrees with legacy on a value'
    write (error_unit, '(a)') 'legacy asserts is deterministic. Per instruction: stop here, do not widen'
    write (error_unit, '(a)') 'a tolerance, do not keep going. Report to the team lead.'
    write (error_unit, '(a)') '================================================================'
    error stop 1
  end subroutine stop_on_exact_mismatch

  subroutine emit(ulog, cn, map_id, rule, cls, detail)
    integer, intent(in) :: ulog
    character(len=*), intent(in) :: cn, map_id, rule, cls, detail
    write (ulog, '(a)') trim(cn)//'|'//trim(map_id)//'|'//trim(rule)//'|'//trim(cls)//'|'//trim(detail)
    write (output_unit, '(a)') '  '//trim(cls)//'  '//trim(map_id)//'  ['//trim(rule)//']  '//trim(detail)
    select case (trim(cls))
    case ('MATCH'); n_match = n_match + 1
    case ('MISMATCH'); n_mismatch = n_mismatch + 1
    case ('NOT_COMPARABLE'); n_notcomp = n_notcomp + 1
    case ('UNVERIFIED'); n_unverified = n_unverified + 1
    end select
  end subroutine emit

  ! ============================================================================
  ! minimal JSON leaf reader -- see the module header for why a full parser is not
  ! needed on these particular files (no field object nests another object).
  ! ============================================================================

  function read_text_file(path) result(text)
    character(len=*), intent(in) :: path
    character(len=:), allocatable :: text
    integer :: u, ios, flen
    inquire (file=path, size=flen)
    if (flen < 0) flen = 0
    allocate (character(len=flen) :: text)
    if (flen == 0) return
    open (newunit=u, file=path, access='stream', form='unformatted', status='old',                 &
          action='read', iostat=ios)
    if (ios /= 0) then
      text = ''
      return
    end if
    read (u, iostat=ios) text
    close (u)
  end function read_text_file

  !> Locates `"<map_id>":{...}` and, within it, the span of the `"values"` entry
  !> (bracket- and quote-aware, so a comma or `[`/`]` inside a quoted hex string cannot
  !> happen in this data, but the scan does not assume it). See the module header for
  !> why no field object here nests another `{...}`.
  subroutine find_field_values(text, map_id, ok, vs, ve)
    character(len=*), intent(in) :: text, map_id
    logical, intent(out) :: ok
    integer, intent(out) :: vs, ve

    character(len=:), allocatable :: key
    character(len=:), allocatable :: body
    integer :: p, body_start, brace_rel, body_end, vk, i, depth, val_rel_start
    logical :: instr
    character :: c

    ok = .false.; vs = 0; ve = 0
    key = '"'//trim(map_id)//'":{'
    p = index(text, key)
    if (p == 0) return
    body_start = p + len(key)
    brace_rel = index(text(body_start:), '}')
    if (brace_rel == 0) return
    body_end = body_start + brace_rel - 2
    if (body_end < body_start) return
    body = text(body_start:body_end)

    vk = index(body, '"values":')
    if (vk == 0) return
    val_rel_start = vk + len('"values":')

    depth = 0; instr = .false.
    i = val_rel_start
    do while (i <= len(body))
      c = body(i:i)
      if (instr) then
        if (c == '"') instr = .false.
      else
        select case (c)
        case ('"'); instr = .true.
        case ('['); depth = depth + 1
        case (']'); depth = depth - 1
        case (','); if (depth == 0) exit
        end select
      end if
      i = i + 1
    end do

    vs = body_start - 1 + val_rel_start
    ve = body_start - 1 + (i - 1)
    if (ve < vs) return
    ok = .true.
  end subroutine find_field_values

  !> Depth-first leaf flatten of the value span: every bare number and every quoted
  !> string becomes one token, in the order it is encountered; `[`, `]`, `,` and
  !> whitespace are skipped regardless of nesting depth. See the module header for why
  !> this lines up with a legacy-side flatten without needing to interpret the nesting.
  subroutine flatten_tokens(text, vs, ve, tokens, n)
    character(len=*), intent(in) :: text
    integer, intent(in) :: vs, ve
    character(len=32), allocatable, intent(out) :: tokens(:)
    integer, intent(out) :: n

    character(len=32) :: buf(max(ve - vs + 1, 1))
    integer :: i, tstart
    logical :: instr, innum
    character :: c

    n = 0; instr = .false.; innum = .false.; tstart = vs
    do i = vs, ve
      c = text(i:i)
      if (instr) then
        if (c == '"') then
          n = n + 1
          buf(n) = text(tstart:i - 1)
          instr = .false.
        end if
      else if (innum) then
        if (.not. is_num_char(c)) then
          n = n + 1
          buf(n) = text(tstart:i - 1)
          innum = .false.
          if (c == '"') then
            instr = .true.; tstart = i + 1
          end if
        end if
      else
        if (c == '"') then
          instr = .true.; tstart = i + 1
        else if (is_num_start(c)) then
          innum = .true.; tstart = i
        end if
      end if
    end do
    if (innum) then
      n = n + 1
      buf(n) = text(tstart:ve)
    end if
    allocate (tokens(n))
    if (n > 0) tokens(1:n) = buf(1:n)
  end subroutine flatten_tokens

  pure logical function is_num_start(c) result(r)
    character, intent(in) :: c
    r = (c >= '0' .and. c <= '9') .or. c == '-'
  end function is_num_start

  pure logical function is_num_char(c) result(r)
    character, intent(in) :: c
    r = (c >= '0' .and. c <= '9') .or. c == '-' .or. c == '+' .or. c == '.' .or. c == 'e' .or. c == 'E'
  end function is_num_char

  subroutine load_i32_ref(jtext, map_id, arr, ok)
    character(len=*), intent(in) :: jtext, map_id
    integer(int32), allocatable, intent(out) :: arr(:)
    logical, intent(out) :: ok
    integer :: vs, ve, n, k
    character(len=32), allocatable :: toks(:)
    call find_field_values(jtext, map_id, ok, vs, ve)
    if (.not. ok) return
    call flatten_tokens(jtext, vs, ve, toks, n)
    allocate (arr(n))
    do k = 1, n
      read (toks(k), *) arr(k)
    end do
  end subroutine load_i32_ref

  subroutine load_f64_ref(jtext, map_id, arr, ok)
    character(len=*), intent(in) :: jtext, map_id
    real(real64), allocatable, intent(out) :: arr(:)
    logical, intent(out) :: ok
    integer :: vs, ve, n, k
    character(len=32), allocatable :: toks(:)
    integer(int64) :: bits
    call find_field_values(jtext, map_id, ok, vs, ve)
    if (.not. ok) return
    call flatten_tokens(jtext, vs, ve, toks, n)
    allocate (arr(n))
    do k = 1, n
      read (toks(k) (1:16), '(Z16)') bits
      arr(k) = transfer(bits, arr(k))
    end do
  end subroutine load_f64_ref

  subroutine report_errors(where, errors)
    character(len=*), intent(in) :: where
    type(problem_errors_t), intent(inout) :: errors
    integer :: i
    do i = 1, errors%count()
      write (output_unit, '(a)') '    '//where//': '//errors%render(i)
    end do
  end subroutine report_errors

  pure function itoa(v) result(s)
    integer, intent(in) :: v
    character(len=:), allocatable :: s
    character(len=24) :: buf
    write (buf, '(i0)') v
    s = trim(buf)
  end function itoa

end program yl_adapter_bridge_test
