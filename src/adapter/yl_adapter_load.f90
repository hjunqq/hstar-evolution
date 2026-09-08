! yl_adapter_load -- repository-side parser for the `.loa` and `.pre` deck files
! (M4-01, L1-e; docs/m4/adapter-contract.md).
!
! Scope
!   Reproduces the read PROTOCOL of `external_load_1` and `external_load_2`
!   (legacy/yl/Load.f90) and `prescrib_set` (legacy/yl/Prescrib.f90) for the
!   static-q4/1 whitelisted slice only: gravity plus fixed/prescribed
!   displacement. Point loads, edge/pressure loads, beam loads, plate loads,
!   stochastic curve modifiers, MIF/VIE boundaries and restart-linked boundary
!   records are all OUTSIDE that whitelist; every one of those, when a deck
!   carries it, is reported as PE_UNSUPPORTED with a rule id -- never silently
!   skipped, never guessed, never defaulted (docs/m4/adapter-contract.md SS5).
!
!   Every read below carries the reader-inventory id it reproduces
!   (docs/m1/reader-inventory.toml) in an adjacent `! RD:` comment, with the
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
!   `load%gravity%amplitude` (from `.loa`) and `boundary(:)` (from `.pre`) --
!   into the shared `step_parts_t` the L2-a driver assembles once, at the end,
!   through the real builder. `amplitudes[]` is not part of that split (it is
!   a top-level `ProblemState` collection, not a `steps[0]` leaf), so it is
!   written the ordinary way, through `b`.
!
! Context this module does not own but needs (open item; flagged to the lead)
!   `external_load_2`'s gravity records are sized by `ndimn`/`ngroup`, and
!   `prescrib_set`'s branch structure is gated by `type_abc`/`nbackdT`/`ntrans`
!   -- all four read earlier from `.glb` by `yl_adapter_model`, not from `.loa`
!   or `.pre`. No shared context type exists yet, so they are taken here as
!   plain `intent(in)` scalar arguments pending a decision on whether they
!   should be consolidated into one (analogous to `step_parts_t`).
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
  use yl_problem_types, only: boundary_t, amplitude_t, amplitude_point_t
  use yl_problem_optional, only: opt_set
  use yl_problem_errors, only: problem_errors_t, source_location_t, make_source_location, &
                                make_problem_error, PE_INVALID_INPUT, PE_UNSUPPORTED
  use yl_problem_builder, only: problem_builder_t, amplitude_builder_t, &
                                builder_amplitude_begin, builder_amplitude_set_name, &
                                builder_amplitude_set_type, builder_amplitude_add_point, &
                                builder_amplitude_finish, builder_add_amplitude
  use yl_adapter_step_parts, only: step_parts_t

  implicit none
  private

  public :: parse_loa, parse_pre

  ! PE_STAGE_ADAPT is not yet defined in yl_problem_errors (contract SS4: "L2-b
  ! 负责新增此常量"). Literal value the constant is expected to hold; switch to
  ! the real constant once it lands so this module has one place to change.
  character(len=*), parameter :: STAGE_ADAPT = 'adapt'

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
  subroutine parse_loa(unit, ndimn, ngroup, b, parts, errors)
    integer, intent(in) :: unit
    integer(int32), intent(in) :: ndimn   ! GLB.global_data.sizes_and_switches: mesh.dimension
    integer(int32), intent(in) :: ngroup  ! GLB.global_data.sizes_and_switches: derived(sections)
    type(problem_builder_t), intent(inout) :: b
    type(step_parts_t), intent(inout) :: parts
    type(problem_errors_t), intent(inout) :: errors

    logical :: ok

    call external_load_1(unit, b, errors, ok)
    if (.not. ok) return
    call external_load_2(unit, ndimn, ngroup, parts, errors, ok)
  end subroutine parse_loa

  !> Parses `.pre`: `prescrib_set` in full.
  subroutine parse_pre(unit, ndimn, type_abc, nbackdt, ntrans, b, parts, errors)
    integer, intent(in) :: unit
    integer(int32), intent(in) :: ndimn      ! GLB.global_data.sizes_and_switches: mesh.dimension
    character(len=*), intent(in) :: type_abc ! GLB.global_data.init_and_blocks: gates the set_header variant
    integer(int32), intent(in) :: nbackdt    ! GLB.global_data.init_and_blocks: gates the restart-linked branch
    integer(int32), intent(in) :: ntrans     ! GLB.global_data.transform_and_mif: gates the MIF coordinate record
    type(problem_builder_t), intent(inout) :: b  ! unused: .pre writes only parts%boundary, no top-level collection
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
    if (nbackdt == 2) then
      loc = make_source_location(file=SRC_PRE, reader='PRE.prescrib_set.set_count', line=213_int32)
      call reject_unsupported(errors, 'A8/restart-linked-boundary-unsupported', 'steps[0].boundary', &
           'nbackdT == 2: the Prescrib.f90:184-201 record shape is a restart-linked dialect ' // &
           'outside the static-q4/1 whitelist and is not reproduced', loc)
      return
    end if

    ! Prescrib.f90:218 vs :220 -- the two set_header variants are picked by
    ! type_abc. The 9-field 'MIF' variant is PRE.prescrib_set.reached_only_
    ! Prescrib_213 in the inventory: reached but never executed on either
    ! golden deck (both carry type_abc='FIX'). Only fixed/prescribed
    ! displacement is in the static-q4/1 whitelist, so MIF is rejected here
    ! rather than misread as an 8-field record.
    if (trim(type_abc) /= 'FIX') then
      loc = make_source_location(file=SRC_PRE, reader='PRE.prescrib_set.reached_only_Prescrib_213', &
                                  line=218_int32)
      call reject_unsupported(errors, 'A9/mif-boundary-unsupported', 'steps[0].boundary', &
           "type_abc = '" // trim(type_abc) // "': only 'FIX' is in the static-q4/1 whitelist; " // &
           'the 9-field MIF/VIE record shape (Prescrib.f90:218) is not reproduced', loc)
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
        call reject_unsupported(errors, 'A10/extrapolation-record-unsupported', 'steps[0].boundary', &
             'nextr /= 0: the per-node extrapolation list (Prescrib.f90:261-266) is not reproduced', &
             loc, index=int(ifixset, int32))
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
      if (ntrans > 0 .and. ifixvar <= ndimn) then
        loc = make_source_location(file=SRC_PRE, reader='PRE.prescrib_set.set_nodes', line=244_int32, &
                                    record=int(ifixset, int32))
        call reject_unsupported(errors, 'A11/mif-coordinate-record-unsupported', 'steps[0].boundary', &
             'ntrans > 0 and ifixvar <= ndimn: the MIF free-face coordinate record ' // &
             '(Prescrib.f90:248-249) is not reproduced', loc, index=int(ifixset, int32))
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
        ! itcurve == 0 means "no curve" (docs/m2/state-field-map.toml
        ! steps0.boundary.amplitude note) -- ADR-0002 keeps that as UNSET
        ! rather than a stored 0, so a downstream reader cannot mistake "no
        ! amplitude" for "amplitude id 0".
        if (itcurve /= 0) call opt_set(bd%amplitude, int(itcurve, int32))
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
  end subroutine parse_pre

  ! ==========================================================================
  ! Load.f90:109 external_load_1 -- time curves, point loads (rejected if
  ! present), edge definitions (rejected if present)
  ! ==========================================================================

  subroutine external_load_1(unit, b, errors, ok)
    integer, intent(in) :: unit
    type(problem_builder_t), intent(inout) :: b
    type(problem_errors_t), intent(inout) :: errors
    logical, intent(out) :: ok

    character(len=20) :: text, type_curve
    integer :: ios
    integer :: ntcurve, itcurve, ntime, nstoch_curve, nline
    integer :: nplgroup, kpload, nedge
    real(real64), allocatable :: ttime_curve(:), dfact_curve(:)
    type(amplitude_builder_t) :: ab
    type(amplitude_t) :: amp
    type(amplitude_point_t) :: pt
    type(source_location_t) :: loc
    integer :: i
    logical :: io_ok

    ok = .false.

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
        call reject_unsupported(errors, 'A1/stochastic-curve-modifier-unsupported', 'amplitudes', &
             'nstoch_curve /= 0: the stochastic curve parameter record (Load.f90:171) is not ' // &
             'reproduced', loc, index=int(itcurve, int32))
        return
      end if

      ! Load.f90:174-232 -- type_curve selects the record shape. 'LINEAR' (the
      ! select-case default, Load.f90:218-222) is the only shape reproduced;
      ! HARMONIC/FOURIERSERIES/WATERLEVEL/SEISMIC/EXTRAPOLATION/ARCLENGTH each
      ! read different fields and are outside the static-q4/1 whitelist.
      if (trim(type_curve) /= 'LINEAR') then
        call reject_unsupported(errors, 'A2/curve-type-unsupported', 'amplitudes', &
             "type_curve = '" // trim(type_curve) // "': only 'LINEAR' (Load.f90:218-222) is in " // &
             'the static-q4/1 whitelist; every other named case (Load.f90:175-217) reads a ' // &
             'different record shape that is not reproduced', loc, index=int(itcurve, int32))
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

      ! RD: same reader id, Load.f90:231 -- the LINEAR branch reads a SECOND
      ! record (the dfact_curve factors) right after curve_points; it has no
      ! diag_check_read of its own and so is not a separate id in the reader
      ! inventory (docs/m2/state-field-map.toml, amplitudes.points.value note:
      ! "Read by the untracked statement Load.f90:231 ... not a separate M1
      ! reader"), but it is on the executed path and skipping it would
      ! desynchronise every read after it.
      read (unit, *, iostat=ios) dfact_curve(1:ntime)
      call check_io(errors, ios, 'LOA.external_load_1.curve_points', SRC_LOA, 231, 'amplitudes', &
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

    ! Load.f90:245-333 -- nplgroup/=0 defines concentrated point loads; out of
    ! the static-q4/1 whitelist (gravity and fixed/prescribed displacement
    ! only).
    if (nplgroup /= 0) then
      loc = make_source_location(file=SRC_LOA, reader='LOA.external_load_1.point_load_count', &
                                  line=241_int32)
      call reject_unsupported(errors, 'A3/point-load-unsupported', 'steps[0].load', &
           'nplgroup /= 0: point loads (Load.f90:246-333) are outside the static-q4/1 whitelist', loc)
      return
    end if

    ! RD: LOA.external_load_1.title#3 (Load.f90:363)
    read (unit, *, iostat=ios) text
    call check_io(errors, ios, 'LOA.external_load_1.title#3', SRC_LOA, 363, 'steps[0].load', io_ok)
    if (.not. io_ok) return

    ! RD: LOA.external_load_1.edge_count (Load.f90:365)
    read (unit, *, iostat=ios) nedge
    call check_io(errors, ios, 'LOA.external_load_1.edge_count', SRC_LOA, 365, 'steps[0].load', io_ok)
    if (.not. io_ok) return

    ! Load.f90:369-465 -- nedge/=0 defines the edges external_load_2 later
    ! attaches pressure loads to; out of the static-q4/1 whitelist.
    if (nedge /= 0) then
      loc = make_source_location(file=SRC_LOA, reader='LOA.external_load_1.edge_count', line=365_int32)
      call reject_unsupported(errors, 'A4/edge-definition-unsupported', 'steps[0].load', &
           'nedge /= 0: edge definitions (Load.f90:369-465) feed only pressure loads, which ' // &
           'are outside the static-q4/1 whitelist', loc)
      return
    end if

    ok = .true.
  end subroutine external_load_1

  ! ==========================================================================
  ! Load.f90:721 external_load_2 -- edge pressure loads (rejected if present),
  ! gravity, beam loads (rejected if present), plate loads (rejected if
  ! present)
  ! ==========================================================================

  subroutine external_load_2(unit, ndimn, ngroup, parts, errors, ok)
    integer, intent(in) :: unit
    integer(int32), intent(in) :: ndimn, ngroup
    type(step_parts_t), intent(inout) :: parts
    type(problem_errors_t), intent(inout) :: errors
    logical, intent(out) :: ok

    character(len=20) :: text
    integer :: ios
    integer :: edge_load_group, delgroup, nbeamload, nplateload, nline
    real(real64) :: gravy
    real(real64), allocatable :: factg(:), factf(:)
    integer(int32), allocatable :: tcurvegravity(:)
    type(source_location_t) :: loc
    logical :: io_ok

    ok = .false.

    ! RD: LOA.external_load_2.title#1 (Load.f90:749)
    read (unit, *, iostat=ios) text
    call check_io(errors, ios, 'LOA.external_load_2.title#1', SRC_LOA, 749, 'steps[0].load', io_ok)
    if (.not. io_ok) return

    ! RD: LOA.external_load_2.title#2 (Load.f90:751)
    read (unit, *, iostat=ios) text
    call check_io(errors, ios, 'LOA.external_load_2.title#2', SRC_LOA, 751, 'steps[0].load', io_ok)
    if (.not. io_ok) return

    ! RD: LOA.external_load_2.edge_load_groups (Load.f90:754)
    read (unit, *, iostat=ios) edge_load_group, delgroup
    call check_io(errors, ios, 'LOA.external_load_2.edge_load_groups', SRC_LOA, 754, &
                  'steps[0].load', io_ok)
    if (.not. io_ok) return

    ! Load.f90:757-908 -- edge_load_group/=0 defines edge pressure / water-
    ! pressure loads (delgroup is only meaningful inside that same block); out
    ! of the static-q4/1 whitelist.
    if (edge_load_group /= 0) then
      loc = make_source_location(file=SRC_LOA, reader='LOA.external_load_2.edge_load_groups', &
                                  line=754_int32)
      call reject_unsupported(errors, 'A5/pressure-load-unsupported', 'steps[0].load', &
           'edge_load_group /= 0: edge / water-pressure loads (Load.f90:757-908) are outside ' // &
           'the static-q4/1 whitelist', loc)
      return
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
    ! owns load%gravity%magnitude/direction/amplitude. load%gravity%enabled
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
      call reject_unsupported(errors, 'A6/beam-load-unsupported', 'steps[0].load', &
           'nbeamload /= 0: beam loads (Load.f90:936-1004) are outside the static-q4/1 whitelist', loc)
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
      call reject_unsupported(errors, 'A7/plate-load-unsupported', 'steps[0].load', &
           'nplateload /= 0: plate/water-pressure loads (Load.f90:1017-1080) are outside the ' // &
           'static-q4/1 whitelist', loc)
      return
    end if

    ok = .true.
  end subroutine external_load_2

  ! ==========================================================================
  ! shared helpers
  ! ==========================================================================

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
    call errors%add(make_problem_error(code=PE_INVALID_INPUT, stage=STAGE_ADAPT, &
                                       rule_id='A-IO/'//trim(reader_id), object_path=object_path, &
                                       message='I/O error reading '//trim(reader_id), source=loc))
  end subroutine check_io

  !> Raises PE_UNSUPPORTED for a deck record outside the static-q4/1 whitelist.
  subroutine reject_unsupported(errors, rule_id, object_path, message, loc, index)
    type(problem_errors_t), intent(inout) :: errors
    character(len=*), intent(in) :: rule_id, object_path, message
    type(source_location_t), intent(in) :: loc
    integer(int32), intent(in), optional :: index

    call errors%add(make_problem_error(code=PE_UNSUPPORTED, stage=STAGE_ADAPT, rule_id=rule_id, &
                                       object_path=object_path, message=message, source=loc, &
                                       index=index))
  end subroutine reject_unsupported

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
