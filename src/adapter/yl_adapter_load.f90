! yl_adapter_load -- repository-side parser for the `.loa` and `.pre` deck files
! (M4-01, L1-e; docs/m4/adapter-contract.md).
!
! Scope
!   Reproduces the read PROTOCOL of `external_load_1` and `external_load_2`
!   (legacy/yl/Load.f90) and `prescrib_set` (legacy/yl/Prescrib.f90): gravity,
!   fixed/prescribed displacement, point loads (group form) and, since 2026-09-23,
!   the edge table and per-block edge pressure loads -- each in exactly the shape
!   the authoring contract can state, so both input paths have one boundary.
!   `.pre` and external_load_2 are read once PER BLOCK into that block's
!   `step_parts_t`. Beam loads, plate loads, stochastic curve modifiers, MIF/VIE
!   boundaries, restart-linked boundary records and every edge/pressure shape
!   outside that one are OUTSIDE the whitelist; each, when a deck carries it, is
!   reported as PE_UNSUPPORTED with a rule id -- never silently skipped, never
!   guessed, never defaulted (docs/m4/adapter-contract.md SS5).
!
!   Every read below carries the reader-inventory id it reproduces
!   (docs/m1/reader-inventory.toml) in an adjacent marker comment, with the
!   legacy line number, per contract SS3. `A-IO/*` rule ids are this module's
!   own I/O-failure namespace; `A1`.. are this module's whitelist-rejection
!   rule ids (contract SS4's `A<n>/<condition>` shape -- no repository-wide
!   registry exists yet, so these are scoped to this file and self-describing).
!
! `parts`, not the step builder (contract SS2.1)
!   `ProblemState.steps[0]` is fed by four deck files, and two of its
!   aggregates are themselves split across files (`load_t.gravity`,
!   `controls_t`). `yl_problem_builder`'s step setters are single-call
!   singletons, so no parser may call one for a field it only partially owns.
!   This module therefore never touches `yl_problem_builder`'s step routines
!   at all: it writes only the leaves `src/adapter/yl_adapter_step_parts.f90`
!   assigns it -- `load%gravity%magnitude`, `load%gravity%direction`,
!   `load%gravity%amplitude`, `load%concentrated`, `load%pressure` (from `.loa`)
!   and `boundary(:)` (from `.pre`) -- into each block's `step_parts_t`, which the
!   L2-a driver assembles into one step per block, at the end, through the real
!   builder. `amplitudes[]` and `surface_edges[]` are not part of that split (they
!   are top-level `ProblemState` collections, not step leaves), so they are
!   written the ordinary way, through `b`.
!
! Context from `.glb` (contract SS2.2, yl_adapter_parts.f90 deck_context_t)
!   `external_load_2`'s gravity records are sized by `ctx%ndimn`/`ctx%ngroup`,
!   and `prescrib_set`'s branch structure is gated by `ctx%type_abc`/
!   `ctx%nbackdt`/`ctx%ntrans` -- all four read earlier from `.glb` by
!   `yl_adapter_model`, not from `.loa` or `.pre`, and carried in via `ctx`
!   rather than guessed (a wrong `ndimn` misaligns every read after it; a MIF
!   deck read as FIX raises no I/O error at all, it just reads the wrong
!   fields). `ctx%filled` is checked first: calling this module before
!   `parse_glb` has run is this module's own fault, not the deck's, so it is
!   PE_INTERNAL rather than a guess.
!
!   `ctx%type_abc` is `character(len=LEN_TYPE_ABC)` (Global.f90:99's own
!   width); the whitelist gate is `== TYPE_ABC_MIF` (both exported from
!   yl_adapter_parts.f90), NOT `/= 'FIX'` -- Prescrib.f90:218/220 branches on
!   `type_abc=='MIF'` for the 9-field header and `/='MIF'` for the ordinary
!   8-field one, so every non-MIF value takes the 8-field path. An earlier
!   draft of this module had the type and the polarity both wrong (inferred
!   `integer`, gated on `/= 'FIX'`, reasoning from the golden decks alone);
!   corrected against the lead's fix to deck_context_t and against
!   Prescrib.f90 itself.
!
! What this module assumes and cannot itself verify
!   `prescrib_set` skips a listed node when
!   `nodfn(lmdofn(ifixvar), node) == 0` (Prescrib.f90:253-254) -- the node's
!   condensed dof does not exist. This module has neither `nodfn` nor `lmdofn`
!   and cannot evaluate that guard. On the static-q4/1 whitelist `lmdofn` is
!   documented as the identity map for a full-dof deck
!   (docs/m1/reader-inventory.toml, GLB.global_data.lmdofn note), so no dof is
!   condensed away and every listed node is admitted. That premise is used
!   below without being checked; if a future whitelist admits condensed dof
!   maps this module must be revisited.
!
! House rules followed here
!   Guards are reproduced, never assumed: every legacy `if` that gates a read
!   or a branch is re-evaluated from the values this module actually has.
!   A read that fails (bad iostat) or a value outside the whitelist returns
!   immediately with a finding; nothing after it is read, because a
!   position-sensitive protocol that keeps reading past a misalignment only
!   produces garbage at a shifted offset.
module yl_adapter_load

  use iso_fortran_env, only: int32, real64
  use yl_problem_types, only: boundary_t, amplitude_t, amplitude_point_t, surface_edge_t, &
                              pressure_t
  use yl_problem_optional, only: opt_set, opt_value_or
  use yl_problem_errors, only: problem_errors_t, source_location_t, make_source_location, &
                                make_problem_error, PE_INVALID_INPUT, PE_INTERNAL,             &
                                PE_STAGE_ADAPT
  use yl_problem_builder, only: problem_builder_t, amplitude_builder_t, &
                                builder_amplitude_begin, builder_amplitude_set_name, &
                                builder_amplitude_set_type, builder_amplitude_add_point, &
                                builder_amplitude_finish, builder_add_amplitude, &
                                builder_add_surface_edge, builder_surface_edges_empty
  use yl_problem_deck_residue, only: deck_residue_t
  use yl_adapter_parts, only: step_parts_t, deck_context_t, TYPE_ABC_MIF, reject_dialect

  implicit none
  private

  public :: parse_loa, parse_pre


  character(len=*), parameter :: SRC_LOA = 'Load.f90'
  character(len=*), parameter :: SRC_PRE = 'Prescrib.f90'

contains

  ! ==========================================================================
  ! public entries
  ! ==========================================================================

  !> Parses `.loa`: `external_load_1` then `external_load_2`, in that order --
  !> both run against the same unit in the legacy call sequence
  !> (Fem.f90 -> STATIC_U), so a rewind between them would desynchronise the
  !> cursor from the deck the driver actually opened.
  !>
  !> legacy reads external_load_1 ONCE, before the block loop (Fem.f90:1682), and
  !> external_load_2 once PER BLOCK inside it (Fem.f90:1896), each time from where the
  !> previous block stopped. So the file is: the analysis-wide part (curves, point loads,
  !> the edge table), then one external_load_2 section per block, in block order.
  subroutine parse_loa(unit, ctx, b, blocks, residue, errors)
    integer, intent(in) :: unit
    type(deck_context_t), intent(in) :: ctx
    type(problem_builder_t), intent(inout) :: b
    !> One per block; see yl_adapter_parts.f90's deck_context_t%nblks.
    type(step_parts_t), intent(inout) :: blocks(:)
    type(deck_residue_t), intent(inout) :: residue
    type(problem_errors_t), intent(inout) :: errors

    logical :: ok
    integer :: nedge, iblk

    call require_context(errors, ctx, ok)
    if (.not. ok) return
    call require_blocks(errors, ctx, size(blocks), ok)
    if (.not. ok) return

    call external_load_1(unit, b, blocks(1), residue, nedge, errors, ok)
    if (.not. ok) return
    ! The point-load table belongs to the analysis, not to a block (legacy has one
    ! `pload` for the whole run), and the contract writes it under every step; commit
    ! refuses steps that disagree about it. So every block carries block 1's.
    do iblk = 2, size(blocks)
      blocks(iblk)%load%concentrated = blocks(1)%load%concentrated
    end do

    do iblk = 1, size(blocks)
      call external_load_2(unit, ctx, blocks(iblk), nedge, iblk, errors, ok)
      if (.not. ok) return
    end do
    call require_face_ranges(errors, blocks, ok)
    if (.not. ok) return

    ! The four external_load_2 counts are PER BLOCK, and commit_block_state publishes
    ! the edge-load pair itself, block by block. commit therefore requires the residue
    ! to carry 0 for edge_load_group (a second source of truth otherwise) and the
    ! modern path's default table carries 0 for all four; the beam and plate counts are
    ! gated to 0 in every block above. `delgroup` has no consumer in either path but
    ! the differential compares globals, so it is carried like the others.
    call opt_set(residue%edge_load_group, 0_int32)
    call opt_set(residue%delgroup, 0_int32)
    call opt_set(residue%nbeamload, 0_int32)
    call opt_set(residue%nplateload, 0_int32)
  end subroutine parse_loa

  !> Parses `.pre`: `prescrib_set` in full, once per block. legacy calls prescrib_set at
  !> the top of every block (Fem.f90:1873) and the file is not rewound between them on
  !> this whitelist (Prescrib.f90:111-112: meshc / rmesh / Bparameter, all refused), so
  !> block k's section is the k-th one in the file.
  subroutine parse_pre(unit, ctx, b, blocks, errors)
    integer, intent(in) :: unit
    type(deck_context_t), intent(in) :: ctx
    type(problem_builder_t), intent(inout) :: b  ! unused: .pre writes only parts%boundary, no top-level collection
    type(step_parts_t), intent(inout) :: blocks(:)
    type(problem_errors_t), intent(inout) :: errors

    logical :: ok
    integer :: iblk, mark

    call require_context(errors, ctx, ok)
    if (.not. ok) return
    call require_blocks(errors, ctx, size(blocks), ok)
    if (.not. ok) return
    do iblk = 1, size(blocks)
      mark = errors%count()
      call parse_pre_block(unit, ctx, blocks(iblk), errors)
      if (errors%count() > mark) return
    end do
  end subroutine parse_pre

  !> One block's `prescrib_set` section.
  subroutine parse_pre_block(unit, ctx, parts, errors)
    integer, intent(in) :: unit
    type(deck_context_t), intent(in) :: ctx
    type(step_parts_t), intent(inout) :: parts
    type(problem_errors_t), intent(inout) :: errors

    character(len=20) :: text
    integer :: ios
    integer :: nfixsets, nline, ifixset, nfixnods
    integer :: ifixvar, itcurve, outfix, jfixvar, nextr
    real(real64) :: tfixvar, gamawx
    integer(int32), allocatable :: list_fix(:)
    real(real64), allocatable :: val_fix(:)
    type(boundary_t), allocatable :: rows(:)
    type(boundary_t) :: bd
    integer :: n_rows, k
    type(source_location_t) :: loc
    logical :: io_ok

    ! Prescrib.f90:102-110 -- a restart pre-scan ("do jblks=1,iblks-1 read ...") gated on
    ! restart==1, which skips the sections of the blocks a restart does not re-run. Not
    ! reproduced: `restart` is refused by name in parse_inp (F1/restart), so on this
    ! whitelist every block is run from the start and reads its own section in turn.
    ! (Until M7 this comment argued from nblks==1 instead; that premise is gone, and the
    ! refusal of restart is what now keeps the branch unreachable.)
    n_rows = 0

    ! RD: PRE.prescrib_set.title#1 (Prescrib.f90:211)
    read (unit, *, iostat=ios) text
    call check_io(errors, ios, 'PRE.prescrib_set.title#1', SRC_PRE, 211, 'steps[0].boundary', io_ok)
    if (.not. io_ok) return

    ! RD: PRE.prescrib_set.set_count (Prescrib.f90:213)
    read (unit, *, iostat=ios) nfixsets, nline
    call check_io(errors, ios, 'PRE.prescrib_set.set_count', SRC_PRE, 213, 'steps[0].boundary', io_ok)
    if (.not. io_ok) return

    ! Prescrib.f90:184-201 -- a restart-linked record shape gated on nbackdT==2,
    ! read INSTEAD of the nfixsets loop below (not inside it). Not in the
    ! reader inventory (never reached on the whitelisted static path: both
    ! golden decks carry nbackdT=0). Not reproduced.
    if (ctx%nbackdt == 2) then
      loc = make_source_location(file=SRC_PRE, reader='PRE.prescrib_set.set_count', line=213_int32)
      call reject_dialect(errors, 'A8', 'restart-linked-boundary-unsupported', loc, &
                          actual=itoa(int(ctx%nbackdt)), expected='0 or 1')
      return
    end if

    ! Prescrib.f90:218 vs :220 -- the two set_header variants are picked by
    ! type_abc. The 9-field 'MIF' variant is PRE.prescrib_set.reached_only_
    ! Prescrib_213 in the inventory: reached but never executed on either
    ! golden deck (both carry type_abc='FIX'). Only fixed/prescribed
    ! displacement is in the static-q4/1 whitelist, so MIF is rejected here
    ! rather than misread as an 8-field record.
    ! THE GATE IS == TYPE_ABC_MIF, NOT /= 'FIX' (Prescrib.f90:218/220 branches on
    ! type_abc=='MIF' for the 9-field header and type_abc/='MIF' for the ordinary
    ! 8-field one; yl_adapter_parts.f90's deck_context_t carries the same warning).
    ! An earlier draft of this module got this backwards ('FIX' as the accepted
    ! literal, mirrored from the golden decks alone) -- caught and corrected by
    ! the lead before it shipped.
    if (trim(ctx%type_abc) == TYPE_ABC_MIF) then
      loc = make_source_location(file=SRC_PRE, reader='PRE.prescrib_set.reached_only_Prescrib_213', &
                                  line=218_int32)
      call reject_dialect(errors, 'A9', 'mif-boundary-unsupported', loc, &
                          actual=trim(ctx%type_abc), expected='not '//TYPE_ABC_MIF)
      return
    end if

    do ifixset = 1, nfixsets
      ! RD: PRE.prescrib_set.set_header (Prescrib.f90:220)
      read (unit, *, iostat=ios) ifixvar, nfixnods, itcurve, tfixvar, outfix, jfixvar, gamawx, nextr
      call check_io(errors, ios, 'PRE.prescrib_set.set_header', SRC_PRE, 220, 'steps[0].boundary', &
                    io_ok, record=int(ifixset, int32))
      if (.not. io_ok) return
      ! tfixvar (time-derivative order) and gamawx carry no ProblemState map
      ! row (docs/m2/state-field-map.toml has no owner for either); read here
      ! only to keep the cursor aligned, not stored.

      ! Prescrib.f90:261-266 -- nextr/=0 adds a per-node extrapolation list
      ! read inside the node loop below; not reproduced (not in the static-
      ! q4/1 whitelist and nextr=0 on both golden decks).
      if (nextr /= 0) then
        loc = make_source_location(file=SRC_PRE, reader='PRE.prescrib_set.set_header', line=220_int32, &
                                    record=int(ifixset, int32))
        call reject_dialect(errors, 'A10', 'extrapolation-record-unsupported', loc, &
                            actual=itoa(nextr), expected='0', idx=int(ifixset, int32))
        return
      end if

      allocate (list_fix(nfixnods))
      ! RD: PRE.prescrib_set.set_nodes (Prescrib.f90:235)
      read (unit, *, iostat=ios) list_fix(1:nfixnods)
      call check_io(errors, ios, 'PRE.prescrib_set.set_nodes', SRC_PRE, 235, 'steps[0].boundary', &
                    io_ok, record=int(ifixset, int32))
      if (.not. io_ok) then
        deallocate (list_fix)
        return
      end if

      ! Prescrib.f90:248-249 -- ntrans>0 .and. ifixvar<=ndimn reads an extra
      ! MIF free-face coordinate record here; not reproduced (out of
      ! whitelist; ntrans=0 on both golden decks per GLB.global_data.
      ! transform_and_mif's note).
      if (ctx%ntrans > 0 .and. ifixvar <= ctx%ndimn) then
        loc = make_source_location(file=SRC_PRE, reader='PRE.prescrib_set.set_nodes', line=244_int32, &
                                    record=int(ifixset, int32))
        call reject_dialect(errors, 'A11', 'mif-coordinate-record-unsupported', loc, &
                            actual='ntrans='//itoa(int(ctx%ntrans))//' ifixvar='//itoa(ifixvar), &
                            expected='ntrans=0', idx=int(ifixset, int32))
        deallocate (list_fix)
        return
      end if

      allocate (val_fix(nfixnods))
      ! RD: PRE.prescrib_set.set_values (Prescrib.f90:242)
      read (unit, *, iostat=ios) val_fix(1:nfixnods)
      call check_io(errors, ios, 'PRE.prescrib_set.set_values', SRC_PRE, 242, 'steps[0].boundary', &
                    io_ok, record=int(ifixset, int32))
      if (.not. io_ok) then
        deallocate (list_fix, val_fix)
        return
      end if

      ! One steps[0].boundary[] row per admitted (set, node) pair -- confirmed
      ! against yl_problem_types.f90's boundary_t comment ("set, node set,
      ! degree of freedom, value and amplitude reference. Values vary per
      ! record") and against derive_node_sets (yl_problem_pipeline.f90:1394),
      ! which reads %name as the set ordinal and %nset as a single node id and
      ! groups rows sharing %name into one mesh.nsets[] entry. This is NOT one
      ! row per record and NOT one row per unique (node,dof): a record naming
      ! 17 nodes produces 17 rows here, all sharing %name=ifixset and %dof=
      ! ifixvar, one per node. "Admitted" is the identity-lmdofn premise
      ! documented in the module header -- every listed node, on this
      ! whitelist, produces a row.
      do k = 1, nfixnods
        call opt_set(bd%name, int(ifixset, int32))
        call opt_set(bd%nset, list_fix(k))
        call opt_set(bd%dof, int(ifixvar, int32))
        call opt_set(bd%value, val_fix(k))
        ! itcurve is always an AUTHORED value, never absent: the deck states it
        ! on every set_header record, and docs/m2/state-field-map.toml defines
        ! its domain explicitly -- "0 = constant (no curve) on both cases;
        ! otherwise 1..ntcurve". 0 there is a meaningful reading ("this record
        ! has no amplitude reference"), not "the record is silent about
        ! amplitude". ADR-0002 exists to keep those two apart, which means
        ! recording the 0 rather than leaving the field unset: unset would
        ! claim the deck never said anything, when it said exactly 0. (An
        ! earlier draft of this line got that backwards and dropped every
        ! itcurve=0 to absence -- caught by the L3-a fidelity gate, which
        ! compares against a frozen baseline that exports the 0 verbatim.)
        call opt_set(bd%amplitude, int(itcurve, int32))
        call opt_set(bd%record_reaction, int(outfix, int32))
        call push_boundary(rows, n_rows, bd)
      end do

      deallocate (list_fix, val_fix)
    end do

    if (allocated(rows)) then
      allocate (parts%boundary(n_rows))
      parts%boundary(1:n_rows) = rows(1:n_rows)
    else
      allocate (parts%boundary(0))
    end if
  end subroutine parse_pre_block

  ! ==========================================================================
  ! Load.f90:109 external_load_1 -- time curves, point loads, the edge table
  ! ==========================================================================

  subroutine external_load_1(unit, b, parts, residue, nedge, errors, ok)
    integer, intent(in) :: unit
    type(problem_builder_t), intent(inout) :: b
    type(step_parts_t), intent(inout) :: parts
    type(deck_residue_t), intent(inout) :: residue
    !> The size of the edge table, which every block's edge-load ranges index into.
    integer, intent(out) :: nedge
    type(problem_errors_t), intent(inout) :: errors
    logical, intent(out) :: ok

    character(len=20) :: text, type_curve
    integer :: ios
    integer :: ntcurve, itcurve, ntime, nstoch_curve, nline
    integer :: nplgroup, kpload
    integer :: iplgroup, order_time_curve, nudofn, npload
    integer :: tedge, sedge, nnode, index, vdimn, iedge, i0, aelem
    integer :: lnode(2)
    type(surface_edge_t) :: se
    real(real64), allocatable :: ttime_curve(:), dfact_curve(:)
    type(amplitude_builder_t) :: ab
    type(amplitude_t) :: amp
    type(amplitude_point_t) :: pt
    type(source_location_t) :: loc
    integer :: i
    logical :: io_ok

    ok = .false.
    nedge = 0

    ! RD: LOA.external_load_1.title#1 (Load.f90:143)
    read (unit, *, iostat=ios) text
    call check_io(errors, ios, 'LOA.external_load_1.title#1', SRC_LOA, 143, 'amplitudes', io_ok)
    if (.not. io_ok) return

    ! RD: LOA.external_load_1.curve_count (Load.f90:145)
    read (unit, *, iostat=ios) ntcurve
    call check_io(errors, ios, 'LOA.external_load_1.curve_count', SRC_LOA, 145, 'amplitudes', io_ok)
    if (.not. io_ok) return

    do itcurve = 1, ntcurve
      ! RD: LOA.external_load_1.curve_header (Load.f90:156)
      read (unit, *, iostat=ios) ntime, type_curve, nstoch_curve, nline
      call check_io(errors, ios, 'LOA.external_load_1.curve_header', SRC_LOA, 156, 'amplitudes', &
                    io_ok, record=int(itcurve, int32))
      if (.not. io_ok) return

      loc = make_source_location(file=SRC_LOA, reader='LOA.external_load_1.curve_header', &
                                  line=156_int32, record=int(itcurve, int32))

      ! Load.f90:169-172 -- nstoch_curve/=0 reads a stochastic-parameter-order
      ! record here; not reproduced (not in the static-q4/1 whitelist).
      if (nstoch_curve /= 0) then
        call reject_dialect(errors, 'A1', 'stochastic-curve-modifier-unsupported', loc, &
                            actual=itoa(nstoch_curve), expected='0', idx=int(itcurve, int32))
        return
      end if

      ! Load.f90:174-232 -- type_curve selects the record shape. 'LINEAR' (the
      ! select-case default, Load.f90:218-222) is the only shape reproduced;
      ! HARMONIC/FOURIERSERIES/WATERLEVEL/SEISMIC/EXTRAPOLATION/ARCLENGTH each
      ! read different fields and are outside the static-q4/1 whitelist.
      if (trim(type_curve) /= 'LINEAR') then
        call reject_dialect(errors, 'A2', 'curve-type-unsupported', loc, &
                            actual=trim(type_curve), expected='LINEAR', idx=int(itcurve, int32))
        return
      end if

      allocate (ttime_curve(ntime), dfact_curve(ntime))

      ! RD: LOA.external_load_1.curve_points (Load.f90:220)
      read (unit, *, iostat=ios) ttime_curve(1:ntime)
      call check_io(errors, ios, 'LOA.external_load_1.curve_points', SRC_LOA, 220, 'amplitudes', &
                    io_ok, record=int(itcurve, int32))
      if (.not. io_ok) then
        deallocate (ttime_curve, dfact_curve)
        return
      end if

      ! RD: LOA.external_load_1.curve_factors (Load.f90:231) -- the LINEAR branch reads a
      ! SECOND record (the dfact_curve factors) right after curve_points. It has no
      ! diag_check_read of its own, is absent from the 152-reader inventory,
      ! and was swept into the .loa "not_on_path" bucket by a blanket reason
      ! that does not actually cover it -- a real M1 census gap, confirmed by
      ! contradiction against 1.loa and written up in
      ! docs/m1/M1-finding-2026-09-08-unwrapped-loa-read.md. It is on the
      ! executed path regardless (both golden cases only complete if it
      ! runs), so it is reproduced here; skipping it would desynchronise
      ! every read after it.
      read (unit, *, iostat=ios) dfact_curve(1:ntime)
      call check_io(errors, ios, 'LOA.external_load_1.curve_factors', SRC_LOA, 231, 'amplitudes', &
                    io_ok, record=int(itcurve, int32))
      if (.not. io_ok) then
        deallocate (ttime_curve, dfact_curve)
        return
      end if

      call builder_amplitude_begin(ab)
      ! amplitude_t%name is @m5-only (yl_problem_types.f90): no legacy record
      ! carries it. itcurve is the deck's own curve ordinal and is exactly the
      ! id steps[0].boundary[].amplitude / gravity.amplitude already reference
      ! (docs/m2/state-field-map.toml notes "0 = constant, otherwise
      ! 1..ntcurve"), so naming the amplitude by that ordinal keeps the
      ! reference meaningful without inventing a value nothing in the deck
      ! states.
      call builder_amplitude_set_name(b, ab, itoa(itcurve), loc, errors)
      call builder_amplitude_set_type(b, ab, trim(type_curve), loc, errors)
      do i = 1, ntime
        call opt_set(pt%time, ttime_curve(i))
        call opt_set(pt%value, dfact_curve(i))
        call builder_amplitude_add_point(b, ab, pt, loc, errors)
      end do
      call builder_amplitude_finish(b, ab, amp, loc, errors)
      call builder_add_amplitude(b, amp, loc, errors)

      deallocate (ttime_curve, dfact_curve)
    end do

    ! RD: LOA.external_load_1.title#2 (Load.f90:239)
    read (unit, *, iostat=ios) text
    call check_io(errors, ios, 'LOA.external_load_1.title#2', SRC_LOA, 239, 'steps[0].load', io_ok)
    if (.not. io_ok) return

    ! RD: LOA.external_load_1.point_load_count (Load.f90:241)
    read (unit, *, iostat=ios) nplgroup, kpload
    call check_io(errors, ios, 'LOA.external_load_1.point_load_count', SRC_LOA, 241, &
                  'steps[0].load', io_ok)
    if (.not. io_ok) return

    ! Load.f90:245-333 -- nplgroup/=0 defines concentrated point loads. The authoring path
    ! has carried these since M7 Phase 4 (`[[step.load]] type="concentrated"`); this is the
    ! same capability on the legacy-deck path, so that the two paths have ONE acceptable
    ! boundary rather than two. No force is computed here and none is invented: legacy's
    ! point-load record has no derived part (docs/m7 Phase 4 SS3), so this is pure carriage
    ! into `concentrated_t`, which `commit_point_loads` already publishes.
    ! (Load.f90:269-285 rotates pxyz by prot at nodes with icpnorm /= 0 and widens it to
    ! ndimn. Unreachable: the only assignment to icpnorm anywhere in legacy is the
    ! `icpnorm=0` at Global.f90:710, so the vector legacy uses is the one it read.)
    !
    ! kpload selects the RECORD SHAPE. kpload==1 is the group form reproduced here;
    ! kpload==2 (Load.f90:305-311) is a second, `corlist`-based form that no golden deck
    ! uses and that M7 left suspended, so it stays a named refusal -- guessing the shape
    ! would desynchronise the file cursor and every later read would be wrong.
    if (nplgroup /= 0 .and. kpload /= 1) then
      loc = make_source_location(file=SRC_LOA, reader='LOA.external_load_1.point_load_count', &
                                  line=241_int32)
      call reject_dialect(errors, 'A3', 'point-load-form-unsupported', loc, &
                          actual=itoa(kpload), expected='1')
      return
    end if

    if (nplgroup /= 0) then
      allocate (parts%load%concentrated(nplgroup))
      do iplgroup = 1, nplgroup
        ! RD: LOA.external_load_1.point_load_group (Load.f90:250)
        read (unit, *, iostat=ios) order_time_curve, nudofn, npload, nline
        call check_io(errors, ios, 'LOA.external_load_1.point_load_group', SRC_LOA, 250, &
                      'steps[0].load.concentrated', io_ok, record=int(iplgroup, int32))
        if (.not. io_ok) return

        loc = make_source_location(file=SRC_LOA, &
                reader='LOA.external_load_1.point_load_group', line=250_int32, &
                record=int(iplgroup, int32))

        ! nudofn and npload SIZE the two reads below; a non-positive size is not a
        ! capability question but a malformed record, and reading on it would consume
        ! the wrong number of values.
        if (nudofn <= 0 .or. npload <= 0) then
          call reject_dialect(errors, 'A3', 'point-load-degenerate-counts', loc, &
                              actual=itoa(nudofn)//'/'//itoa(npload), expected='both > 0', &
                              idx=int(iplgroup, int32))
          return
        end if

        call opt_set(parts%load%concentrated(iplgroup)%amplitude, int(order_time_curve, int32))
        allocate (parts%load%concentrated(iplgroup)%value(nudofn))
        allocate (parts%load%concentrated(iplgroup)%nodes(npload))

        ! RD: LOA.external_load_1.point_load_force (Load.f90:261)
        read (unit, *, iostat=ios) parts%load%concentrated(iplgroup)%value(1:nudofn)
        call check_io(errors, ios, 'LOA.external_load_1.point_load_force', SRC_LOA, 261, &
                      'steps[0].load.concentrated', io_ok, record=int(iplgroup, int32))
        if (.not. io_ok) return

        ! Load.f90:264-297 branches on the curve type: EXTRAPOLATION reads a listep table
        ! instead of a plain node list. A2 above already refuses every curve type but
        ! LINEAR, so that branch is unreachable from here -- this read is the LINEAR one
        ! (Load.f90:266), and the refusal that keeps it unreachable is A2, not silence.
        ! RD: LOA.external_load_1.point_load_nodes (Load.f90:266)
        read (unit, *, iostat=ios) parts%load%concentrated(iplgroup)%nodes(1:npload)
        call check_io(errors, ios, 'LOA.external_load_1.point_load_nodes', SRC_LOA, 266, &
                      'steps[0].load.concentrated', io_ok, record=int(iplgroup, int32))
        if (.not. io_ok) return
      end do
    else
      ! "ran, found none" is not the same state as "never ran" (ADR-0002): an explicitly
      ! empty array is what tells commit this deck carries no concentrated force.
      allocate (parts%load%concentrated(0))
    end if

    ! RD: LOA.external_load_1.title#3 (Load.f90:363)
    read (unit, *, iostat=ios) text
    call check_io(errors, ios, 'LOA.external_load_1.title#3', SRC_LOA, 363, 'steps[0].load', io_ok)
    if (.not. io_ok) return

    ! RD: LOA.external_load_1.edge_count (Load.f90:365)
    read (unit, *, iostat=ios) nedge
    call check_io(errors, ios, 'LOA.external_load_1.edge_count', SRC_LOA, 365, 'steps[0].load', io_ok)
    if (.not. io_ok) return

    ! Load.f90:369-392 -- the edge table external_load_2's pressure loads index into, "for
    ! whole analysis": chunks of `sedge` edges sharing one (nnode, index, vdimn) header,
    ! until nedge edges have been read. Carried as ProblemState.surface_edges[], the same
    ! flattened table the modern path lays its named faces out into, row for row.
    !
    ! Admitted: the one edge shape the contract can state -- `kind = "edge2"`, i.e.
    ! nnode 2, element class (index) 1, no flattened coordinate (vdimn 0); the modern map
    ! encodes exactly that (yl_authoring_map.f90). Any other header is a shape the other
    ! path cannot express, so it is refused rather than carried on one path only. A
    ! chunk of sedge < 1 is refused too: legacy's `do while (tedge < nedge)` would never
    ! advance on it, and one that overruns nedge would write past `edges(nedge)`.
    if (nedge < 0) then
      loc = make_source_location(file=SRC_LOA, reader='LOA.external_load_1.edge_count', line=365_int32)
      call reject_dialect(errors, 'A4', 'edge-table-unsupported', loc, &
                          actual='nedge='//itoa(nedge), expected='nedge >= 0')
      return
    end if
    if (nedge == 0) then
      ! "ran, found none" (ADR-0002), as the modern path states it.
      loc = make_source_location(file=SRC_LOA, reader='LOA.external_load_1.edge_count', line=365_int32)
      call builder_surface_edges_empty(b, loc, errors)
    end if
    tedge = 0
    do while (tedge < nedge)
      ! RD: LOA.external_load_1.edge_chunk_title (Load.f90:377)
      read (unit, *, iostat=ios) text
      call check_io(errors, ios, 'LOA.external_load_1.edge_chunk_title', SRC_LOA, 377, &
                    'surface_edges', io_ok, record=int(tedge + 1, int32))
      if (.not. io_ok) return
      ! RD: LOA.external_load_1.edge_chunk_header (Load.f90:379)
      read (unit, *, iostat=ios) sedge, nnode, index, vdimn
      call check_io(errors, ios, 'LOA.external_load_1.edge_chunk_header', SRC_LOA, 379, &
                    'surface_edges', io_ok, record=int(tedge + 1, int32))
      if (.not. io_ok) return
      loc = make_source_location(file=SRC_LOA, reader='LOA.external_load_1.edge_chunk_header', &
                                  line=379_int32, record=int(tedge + 1, int32))
      if (nnode /= 2 .or. index /= 1 .or. vdimn /= 0 .or. sedge < 1 .or. tedge + sedge > nedge) then
        call reject_dialect(errors, 'A4', 'edge-table-unsupported', loc, &
                            actual='sedge='//itoa(sedge)//' nnode='//itoa(nnode)//' index='// &
                                   itoa(index)//' vdimn='//itoa(vdimn), &
                            expected='nnode=2 index=1 vdimn=0, 1 <= sedge <= '//itoa(nedge - tedge))
        return
      end if
      do iedge = 1, sedge
        tedge = tedge + 1
        ! RD: LOA.external_load_1.edge_nodes (Load.f90:388)
        read (unit, *, iostat=ios) i0, lnode(1:nnode), aelem
        call check_io(errors, ios, 'LOA.external_load_1.edge_nodes', SRC_LOA, 388, &
                      'surface_edges', io_ok, record=int(tedge, int32))
        if (.not. io_ok) return
        ! i0 is the row's own ordinal, which legacy reads and discards.
        if (allocated(se%nodes)) deallocate (se%nodes)
        allocate (se%nodes(2))
        se%nodes = int(lnode, int32)
        call opt_set(se%element, int(aelem, int32))
        call opt_set(se%element_class, int(index, int32))
        call opt_set(se%projection_axis, int(vdimn, int32))
        loc = make_source_location(file=SRC_LOA, reader='LOA.external_load_1.edge_nodes', &
                                    line=388_int32, record=int(tedge, int32))
        call builder_add_surface_edge(b, se, loc, errors)
      end do
    end do

    ! Carried out after the gates, as everywhere else on this surface.
    call opt_set(residue%nplgroup, int(nplgroup, int32))
    call opt_set(residue%nedge, int(nedge, int32))

    ok = .true.
  end subroutine external_load_1

  ! ==========================================================================
  ! Load.f90:903 external_load_2 -- ONE BLOCK's edge pressure loads, gravity,
  ! beam loads (rejected if present), plate loads (rejected if present)
  ! ==========================================================================

  subroutine external_load_2(unit, ctx, parts, nedge, iblk, errors, ok)
    integer, intent(in) :: unit
    type(deck_context_t), intent(in) :: ctx
    type(step_parts_t), intent(inout) :: parts
    integer, intent(in) :: nedge   ! the edge table's size, from external_load_1
    integer, intent(in) :: iblk    ! which block this section is, for locations only
    type(problem_errors_t), intent(inout) :: errors
    logical, intent(out) :: ok

    character(len=20) :: text
    integer :: ios
    integer :: edge_load_group, delgroup, nbeamload, nplateload, nline
    integer :: ipegroup, begin_edge, end_edge, itcurve, water, code_load, total
    real(real64) :: cor0, cor1, p0, p1, fact
    type(pressure_t), allocatable :: prs(:)
    integer(int32) :: ndimn, ngroup
    real(real64) :: gravy
    real(real64), allocatable :: factg(:), factf(:)
    integer(int32), allocatable :: tcurvegravity(:)
    type(source_location_t) :: loc
    logical :: io_ok

    ok = .false.
    ndimn = ctx%ndimn
    ngroup = ctx%ngroup

    ! RD: LOA.external_load_2.title#1 (Load.f90:749)
    read (unit, *, iostat=ios) text
    call check_io(errors, ios, 'LOA.external_load_2.title#1', SRC_LOA, 749, 'steps[0].load', io_ok)
    if (.not. io_ok) return

    ! RD: LOA.external_load_2.title#2 (Load.f90:751)
    read (unit, *, iostat=ios) text
    call check_io(errors, ios, 'LOA.external_load_2.title#2', SRC_LOA, 751, 'steps[0].load', io_ok)
    if (.not. io_ok) return

    ! RD: LOA.external_load_2.edge_load_groups (Load.f90:932)
    read (unit, *, iostat=ios) edge_load_group, delgroup
    call check_io(errors, ios, 'LOA.external_load_2.edge_load_groups', SRC_LOA, 932, &
                  'steps[0].load', io_ok)
    if (.not. io_ok) return

    ! Load.f90:938-969 -- this block's edge-load groups. `edge_load_group` is the total
    ! number of loaded edges and `delgroup` the number of groups; legacy reads no group
    ! at all when edge_load_group == 0 (its `goto 33`), whatever delgroup says. Each group
    ! is one pressure_t, the shape the modern path builds from a `type = "pressure"`
    ! load, and commit_block_state hands it to legacy's own edge_load_group_apply.
    !
    ! Admitted: what the contract can state. `water` (the distribution axis) = 2, i.e.
    ! "y, deepening downward" -- the one value the modern map writes; `water == 0` is a
    ! per-node pressure TABLE read inside edge_load_group_apply, which the contract has
    ! no key for; `code_load /= 0` is legacy's second, far-side distribution, which it
    ! reads into a local and the contract does not carry either. A range outside the
    ! edge table, or ranges that do not add up to edge_load_group, would make legacy
    ! index past `edges` or leave `edgeload` entries unset: refused by name too.
    if (edge_load_group == 0 .and. delgroup /= 0) then
      ! legacy reads no group here and leaves `delgroup` (and the previous block's
      ! edge loads) standing; commit publishes this block's own, i.e. none. Refused
      ! rather than let the two disagree about a count the deck states.
      loc = make_source_location(file=SRC_LOA, reader='LOA.external_load_2.edge_load_groups', &
                                  line=932_int32, record=int(iblk, int32))
      call reject_dialect(errors, 'A5', 'pressure-edge-range', loc, &
                          actual='edge_load_group=0 delgroup='//itoa(delgroup), expected='delgroup=0')
      return
    end if
    if (edge_load_group /= 0) then
      allocate (prs(max(delgroup, 0)))
      total = 0
      do ipegroup = 1, delgroup
        ! RD: LOA.external_load_2.edge_load_group (Load.f90:944)
        read (unit, *, iostat=ios) begin_edge, end_edge, itcurve, water, code_load
        call check_io(errors, ios, 'LOA.external_load_2.edge_load_group', SRC_LOA, 944, &
                      'steps[].load.pressure', io_ok, record=int(ipegroup, int32))
        if (.not. io_ok) return
        loc = make_source_location(file=SRC_LOA, reader='LOA.external_load_2.edge_load_group', &
                                    line=944_int32, record=int(ipegroup, int32))
        if (water /= 2 .or. code_load /= 0) then
          call reject_dialect(errors, 'A5', 'pressure-distribution-unsupported', loc, &
                              actual='water='//itoa(water)//' code_load='//itoa(code_load), &
                              expected='water=2 code_load=0', idx=int(ipegroup, int32))
          return
        end if
        if (begin_edge < 1 .or. end_edge < begin_edge .or. end_edge > nedge) then
          call reject_dialect(errors, 'A5', 'pressure-edge-range', loc, &
                              actual=itoa(begin_edge)//'..'//itoa(end_edge), &
                              expected='1 <= begin <= end <= '//itoa(nedge), &
                              idx=int(ipegroup, int32))
          return
        end if
        ! RD: LOA.external_load_2.edge_load_distribution (Load.f90:950)
        read (unit, *, iostat=ios) cor0, cor1, p0, p1, fact
        call check_io(errors, ios, 'LOA.external_load_2.edge_load_distribution', SRC_LOA, 950, &
                      'steps[].load.pressure', io_ok, record=int(ipegroup, int32))
        if (.not. io_ok) return
        call opt_set(prs(ipegroup)%first_edge, int(begin_edge, int32))
        call opt_set(prs(ipegroup)%last_edge, int(end_edge, int32))
        call opt_set(prs(ipegroup)%amplitude, int(itcurve, int32))
        call opt_set(prs(ipegroup)%distribution_axis, int(water, int32))
        allocate (prs(ipegroup)%at(2), prs(ipegroup)%value(2))
        prs(ipegroup)%at = [cor0, cor1]
        prs(ipegroup)%value = [p0, p1]
        call opt_set(prs(ipegroup)%scale, fact)
        total = total + end_edge - begin_edge + 1
      end do
      if (total /= edge_load_group) then
        loc = make_source_location(file=SRC_LOA, reader='LOA.external_load_2.edge_load_groups', &
                                    line=932_int32, record=int(iblk, int32))
        call reject_dialect(errors, 'A5', 'pressure-edge-range', loc, &
                            actual='groups cover '//itoa(total)//' edges', &
                            expected='edge_load_group = '//itoa(edge_load_group))
        return
      end if
      call move_alloc(prs, parts%load%pressure)
    else
      ! "ran, found none" (ADR-0002): this block carries no pressure.
      allocate (parts%load%pressure(0))
    end if

    ! RD: LOA.external_load_2.title#3 (Load.f90:910)
    read (unit, *, iostat=ios) text
    call check_io(errors, ios, 'LOA.external_load_2.title#3', SRC_LOA, 910, 'steps[0].load', io_ok)
    if (.not. io_ok) return

    allocate (factg(ndimn), factf(ndimn))
    ! RD: LOA.external_load_2.gravity (Load.f90:912)
    read (unit, *, iostat=ios) gravy, factg(1:ndimn), factf(1:ndimn)
    call check_io(errors, ios, 'LOA.external_load_2.gravity', SRC_LOA, 912, 'steps[0].load', io_ok)
    if (.not. io_ok) then
      deallocate (factg, factf)
      return
    end if

    ! RD: LOA.external_load_2.gravity_curve_title (Load.f90:919)
    read (unit, *, iostat=ios) text, nline
    call check_io(errors, ios, 'LOA.external_load_2.gravity_curve_title', SRC_LOA, 919, &
                  'steps[0].load', io_ok)
    if (.not. io_ok) then
      deallocate (factg, factf)
      return
    end if

    allocate (tcurvegravity(ngroup))
    ! RD: LOA.external_load_2.gravity_curves (Load.f90:921)
    read (unit, *, iostat=ios) tcurvegravity(1:ngroup)
    call check_io(errors, ios, 'LOA.external_load_2.gravity_curves', SRC_LOA, 921, &
                  'steps[0].load', io_ok)
    if (.not. io_ok) then
      deallocate (factg, factf, tcurvegravity)
      return
    end if

    ! Leaf ownership (yl_adapter_step_parts.f90 module header): this module
    ! owns load%gravity%magnitude/direction/amplitude. load%gravity%recompute_every
    ! (NGRAV, GLB.global_data.material_class_counts) belongs to the .glb
    ! parser and is deliberately left untouched here -- writing it would be a
    ! second, silent writer of a leaf this module does not own.
    call opt_set(parts%load%gravity%magnitude, gravy)
    parts%load%gravity%direction = factg(1:ndimn)
    parts%load%gravity%amplitude = tcurvegravity(1:ngroup)
    ! factf (Load.f90:912) carries no ProblemState map row; read only to keep
    ! the cursor aligned, not stored.

    deallocate (factg, factf, tcurvegravity)

    ! RD: LOA.external_load_2.title#4 (Load.f90:931)
    read (unit, *, iostat=ios) text
    call check_io(errors, ios, 'LOA.external_load_2.title#4', SRC_LOA, 931, 'steps[0].load', io_ok)
    if (.not. io_ok) return

    ! RD: LOA.external_load_2.beam_load_count (Load.f90:933)
    read (unit, *, iostat=ios) nbeamload
    call check_io(errors, ios, 'LOA.external_load_2.beam_load_count', SRC_LOA, 933, &
                  'steps[0].load', io_ok)
    if (.not. io_ok) return

    ! Load.f90:936-1004 -- nbeamload/=0 defines beam loads; out of whitelist.
    if (nbeamload /= 0) then
      loc = make_source_location(file=SRC_LOA, reader='LOA.external_load_2.beam_load_count', &
                                  line=933_int32)
      call reject_dialect(errors, 'A6', 'beam-load-unsupported', loc, &
                          actual=itoa(nbeamload), expected='0')
      return
    end if

    ! RD: LOA.external_load_2.title#5 (Load.f90:1012)
    read (unit, *, iostat=ios) text
    call check_io(errors, ios, 'LOA.external_load_2.title#5', SRC_LOA, 1012, 'steps[0].load', io_ok)
    if (.not. io_ok) return

    ! RD: LOA.external_load_2.plate_load_count (Load.f90:1014)
    read (unit, *, iostat=ios) nplateload
    call check_io(errors, ios, 'LOA.external_load_2.plate_load_count', SRC_LOA, 1014, &
                  'steps[0].load', io_ok)
    if (.not. io_ok) return

    ! Load.f90:1016-1080 -- nplateload==0 returns immediately (nothing more to
    ! read on this path); nplateload/=0 defines plate/water-pressure loads,
    ! out of the static-q4/1 whitelist.
    if (nplateload /= 0) then
      loc = make_source_location(file=SRC_LOA, reader='LOA.external_load_2.plate_load_count', &
                                  line=1014_int32)
      call reject_dialect(errors, 'A7', 'plate-load-unsupported', loc, &
                          actual=itoa(nplateload), expected='0')
      return
    end if

    ! The four counts go to the residue once, in parse_loa, not per block here.
    ok = .true.
  end subroutine external_load_2

  ! ==========================================================================
  ! shared helpers
  ! ==========================================================================

  !> Refuses to proceed on an unfilled deck_context_t. A caller invoking this
  !> module before parse_glb has run is this module's own integration fault,
  !> not a defect in the deck, so it is PE_INTERNAL rather than PE_INVALID_INPUT
  !> or PE_UNSUPPORTED -- the two codes this module otherwise ever raises.
  subroutine require_context(errors, ctx, ok)
    type(problem_errors_t), intent(inout) :: errors
    type(deck_context_t), intent(in) :: ctx
    logical, intent(out) :: ok

    ok = ctx%filled
    if (ok) return
    call errors%add(make_problem_error(code=PE_INTERNAL, stage=PE_STAGE_ADAPT, &
                                       rule_id='A0/deck-context-not-filled', &
                                       object_path='steps[0]', &
                                       message='parse_loa/parse_pre called with an unfilled ' // &
                                       'deck_context_t; parse_glb must run first'))
  end subroutine require_context

  !> Every pressure range, across every block, must be either IDENTICAL to or DISJOINT
  !> from every other. That is exactly the set of ranges the modern path can produce:
  !> it lays named faces out as non-overlapping contiguous ranges and a load names one
  !> whole face. Partially overlapping ranges (1..2 and 2..3) are legal to legacy but
  !> have no case.toml that states them, so they are refused by the range row.
  subroutine require_face_ranges(errors, blocks, ok)
    type(problem_errors_t), intent(inout) :: errors
    type(step_parts_t), intent(in) :: blocks(:)
    logical, intent(out) :: ok
    integer :: ib, jb, ip, jp, a1, a2, c1, c2
    type(source_location_t) :: loc

    ok = .true.
    do ib = 1, size(blocks)
      if (.not. allocated(blocks(ib)%load%pressure)) cycle
      do ip = 1, size(blocks(ib)%load%pressure)
        a1 = int(opt_value_or(blocks(ib)%load%pressure(ip)%first_edge, 0_int32))
        a2 = int(opt_value_or(blocks(ib)%load%pressure(ip)%last_edge, 0_int32))
        do jb = ib, size(blocks)
          if (.not. allocated(blocks(jb)%load%pressure)) cycle
          do jp = 1, size(blocks(jb)%load%pressure)
            if (jb == ib .and. jp <= ip) cycle
            c1 = int(opt_value_or(blocks(jb)%load%pressure(jp)%first_edge, 0_int32))
            c2 = int(opt_value_or(blocks(jb)%load%pressure(jp)%last_edge, 0_int32))
            if ((a1 == c1 .and. a2 == c2) .or. a2 < c1 .or. c2 < a1) cycle
            ok = .false.
            loc = make_source_location(file=SRC_LOA, reader='LOA.external_load_2.edge_load_group', &
                                        line=944_int32, record=int(jp, int32))
            call reject_dialect(errors, 'A5', 'pressure-edge-range', loc, &
                                actual=itoa(a1)//'..'//itoa(a2)//' (block '//itoa(ib)//') vs '// &
                                       itoa(c1)//'..'//itoa(c2)//' (block '//itoa(jb)//')', &
                                expected='identical or disjoint ranges')
            return
          end do
        end do
      end do
    end do
  end subroutine require_face_ranges

  !> The driver sizes the per-block parts from `.glb`'s nblks; a mismatch here is the
  !> driver's fault, not the deck's.
  subroutine require_blocks(errors, ctx, n, ok)
    type(problem_errors_t), intent(inout) :: errors
    type(deck_context_t), intent(in) :: ctx
    integer, intent(in) :: n
    logical, intent(out) :: ok

    ok = (n == ctx%nblks .and. n >= 1)
    if (ok) return
    call errors%add(make_problem_error(code=PE_INTERNAL, stage=PE_STAGE_ADAPT, &
                                       rule_id='A0/blocks-not-sized', object_path='steps', &
                                       message='parse_loa/parse_pre were handed '//itoa(n)// &
                                       ' block parts for a deck of '//itoa(int(ctx%nblks))//' blocks'))
  end subroutine require_blocks

  !> Raises PE_INVALID_INPUT and sets ok=.false. on a nonzero iostat; leaves
  !> ok=.true. and raises nothing otherwise. Every read in this module is
  !> immediately followed by a call to this so a bad deck record is reported
  !> with the reader id that failed, never swallowed and never read past.
  subroutine check_io(errors, ios, reader_id, source_file, source_line, object_path, ok, record)
    type(problem_errors_t), intent(inout) :: errors
    integer, intent(in) :: ios
    character(len=*), intent(in) :: reader_id, source_file, object_path
    integer, intent(in) :: source_line
    logical, intent(out) :: ok
    integer(int32), intent(in), optional :: record
    type(source_location_t) :: loc

    ok = (ios == 0)
    if (ok) return
    loc = make_source_location(file=source_file, reader=reader_id, line=int(source_line, int32), &
                                record=record)
    call errors%add(make_problem_error(code=PE_INVALID_INPUT, stage=PE_STAGE_ADAPT, &
                                       rule_id='A-IO/'//trim(reader_id), object_path=object_path, &
                                       message='I/O error reading '//trim(reader_id), source=loc))
  end subroutine check_io

  !> Appends to a geometrically-grown boundary_t buffer, mirroring the
  !> SEED_CAPACITY-then-double growth yl_problem_builder uses for its own
  !> collections (this module cannot call the builder's private growth code,
  !> only its public add/finish routines, and parts%boundary is filled
  !> directly rather than through a builder call -- see the module header).
  subroutine push_boundary(rows, n, value)
    type(boundary_t), allocatable, intent(inout) :: rows(:)
    integer, intent(inout) :: n
    type(boundary_t), intent(in) :: value
    type(boundary_t), allocatable :: tmp(:)
    integer, parameter :: SEED_CAPACITY = 16

    if (.not. allocated(rows)) then
      allocate (rows(SEED_CAPACITY))
    else if (n >= size(rows)) then
      allocate (tmp(2*size(rows)))
      tmp(1:n) = rows(1:n)
      call move_alloc(tmp, rows)
    end if
    n = n + 1
    rows(n) = value
  end subroutine push_boundary

  !> Decimal text of a positive loop ordinal (itcurve, ifixset), for the one
  !> place this module needs one: amplitude_t%name (see external_load_1).
  function itoa(i) result(s)
    integer, intent(in) :: i
    character(len=:), allocatable :: s
    character(len=12) :: buf
    write (buf, '(I0)') i
    s = trim(buf)
  end function itoa

end module yl_adapter_load
