! yl_adapter_fem90 -- the nine FEM90/STATIC_U reader sites that no other adapter module can
! reach and no oracle can check.
!
! WHY THIS MODULE IS SEPARATE (read this before changing anything below)
!   docs/m4/adapter-contract.md assigns 125 whitelisted reader sites across five parser
!   modules plus a harvest oracle. 116 of them sit in callable `module` subprograms and are
!   cross-checked field by field by that oracle (docs/m4/evidence/R-order-probe/). The nine
!   sites in THIS module do not: five `inp` sites live in `PROGRAM FEM90`'s own body
!   (legacy/yl/Fem.f90:97-185) and four `.man` sites live in `STATIC_U`
!   (legacy/yl/Fem.f90:3593-3633), an INTERNAL subprogram of that program. Fortran cannot
!   call an internal procedure from outside its host program unit, `legacy/yl` is forbidden
!   to modify (ADR-0001), and the oracle is therefore structurally unable to drive these nine
!   the way it drives the other 116.
!
!   Consequently this is the one place in the whole M4 task where a divergence between this
!   module and `legacy/yl/Fem.f90` has no automatic tripwire. Every read below quotes the
!   exact legacy statement it reproduces, not just its reader-inventory id, so that a future
!   diff against Fem.f90 is a literal text comparison rather than a re-derivation from
!   memory. Anyone touching a `read` in this file must re-quote the legacy statement at the
!   line cited, not just trust the comment already here.
!
! THE NINE SITES (docs/m1/reader-inventory.toml, verified in full at legacy/yl/Fem.f90)
!   INP.FEM90.title#1         Fem.f90:97    guard always                (parse_inp)
!   INP.FEM90.run_control     Fem.f90:99    guard always                (parse_inp)
!   INP.FEM90.title#2         Fem.f90:101   guard always                (parse_inp)
!   INP.FEM90.problem_name    Fem.f90:103   guard always                (parse_inp)
!   INP.FEM90.runblks         Fem.f90:185   guard always                (parse_inp)
!   MAN.STATIC_U.title#1           Fem.f90:3593  guard type_problem=='Q' (parse_man)
!   MAN.STATIC_U.nincs              Fem.f90:3595  guard STATIC_U         (parse_man)
!   MAN.STATIC_U.increment_control  Fem.f90:3627  guard loop iincs=lincs+1..nincs (parse_man)
!   MAN.STATIC_U.tolerances         Fem.f90:3633  guard loop iincs        (parse_man)
!
! WHAT FEEDS ProblemState AND WHAT DOES NOT
!   `case.name`                                <- INP.FEM90.problem_name (probn)
!   `steps[0].controls.increments`             <- MAN.STATIC_U.nincs
!   `steps[0].controls.{max_iterations,        <- MAN.STATIC_U.increment_control
!    steps,step_increment,restart_frequency,
!    time_increment}`
!   `steps[0].controls.tolerance_force`        <- MAN.STATIC_U.tolerances
!   `steps[0].controls.tolerance_dof(:)`       <- MAN.STATIC_U.tolerances
!   `steps[0].output.frequency.{nodes,fields}` <- MAN.STATIC_U.increment_control (noutn/noutf)
!   everything else (both title lines in `inp`, the `.man` title, the six run_control flags,
!   `derived.counts.runblks` itself, `cwater`, `Qstatic`) has `owner = "not_migrated"` or
!   `owner = "derived"` in docs/m2/state-field-map.toml: it is read only to advance the deck
!   cursor and to police the whitelist, never written to a `ProblemState` field.
!
! `steps[0]` IS SHARED -- via `step_parts_t`, NOT the step builder (2026-09-08 contract
! revision, discovered by L1-e)
!   `steps[0]` is fed by four deck files, and `controls_t`/`load_t` are themselves split
!   across them: `controls%nonlinear_type` is `.glb`'s, the other eight `controls` fields are
!   `.man`'s (this module). `builder_step_set_controls` is a singleton setter -- a second call
!   is rejected as `builder.duplicate_singleton` -- so no parser may call it with a partial
!   value. Per the revised contract this module therefore never touches `yl_problem_builder`'s
!   step API at all: it only fills the `controls` and `output%frequency` leaves it owns on the
!   shared `step_parts_t`; the sequencing driver (L2-a) performs every `builder_step_*` call
!   exactly once after all four parsers have run.
!
!   DISCREPANCY FLAGGED, NOT FIXED (src/adapter/yl_adapter_step_parts.f90 is not this module's
!   file): that module's leaf-ownership table lists the whole of `output` as `.glb`'s. But
!   docs/m2/state-field-map.toml sources `steps0.output.frequency_nodes` and
!   `steps0.output.frequency_fields` to `MAN.STATIC_U.increment_control` (Fem.f90:3627,
!   `noutn`/`noutf`) -- not to any `.glb` site. This module follows the map (the primary
!   record) and writes `parts%output%frequency` only; `parts%output%format` and
!   `parts%output%field` are left untouched, matching the table's intent for the leaves that
!   are actually `.glb`'s. The table's header comment should be corrected to read
!   "output.frequency .man, output.format/field .glb" -- flagged to the team, not edited here.
!
! WHITELIST (static-q4/1, unchanged, not enlarged -- docs/m4/adapter-contract.md S5)
!   Every one of the six `inp` run_control flags is pinned to 0 by the map itself
!   ("pinned guard: value 0 keeps control flow on static_2d path", each of
!   control.run.{restart,relis,sysrelis,adina,uopt_r,gamamax}). A nonzero value diverts FEM90
!   into a branch this build cannot follow: `restart` resumes a prior run (Fem.f90:277-309),
!   `Uopt_R` reads an entire extra optimisation-coordinate deck at Fem.f90:120-142 that has no
!   reader-inventory entry at all, `ADINA` stops the run for an alternate export
!   (Fem.f90:1900-1902), and `gamamax` opens an equivalent-linearisation soil file
!   (Fem.f90:1724-1730). None of these are representable by reading further with this module's
!   nine sites, so all six are rejected rather than guessed at.
!
!   `derived.counts.runblks` = len(steps) (state-field-map.toml note on that row); static-q4/1
!   is single-stage, so anything but 1 asks for a `steps` array this slice cannot represent.
!
!   `nincs` has no counterpart array in `controls_t` (the type carries one scalar set of the
!   per-increment fields, not one per increment), and legacy overwrites those fields on every
!   pass of `do iincs=lincs+1,nincs`. A `nincs` other than 1 would therefore silently drop
!   every increment but the last one if this module kept reading -- so it is rejected before
!   the loop runs at all, not discovered by watching the loop run more than once.
!
!   `cwater` and `Qstatic` are read every increment_control record but neither has a
!   `ProblemState` owner (both `not_migrated`); nonzero enables water-coupling or
!   quasi-static-force branches this whitelist slice (2D, Q4, displacement field, linear
!   elastic isotropic, single-stage static, fixed/prescribed displacement, gravity) does not
!   cover.
!
! WHY `WHITELIST_MDOFN = 2` IS NOT AN INVENTED VALUE
!   `MAN.STATIC_U.tolerances` reads `toler_var(1:mdofn)`, and `mdofn` is a legacy global this
!   module is forbidden to touch (`use global_var` is banned outside the harvest oracle,
!   adapter-contract.md S2) and has no other channel to reach this module. But static-q4/1
!   fixes the field to "位移场" (displacement only) in 2D, and the R-order-probe evidence
!   (docs/m4/evidence/R-order-probe/README.md) measured `mdofn`/`cdofn` as exactly 2/2 on
!   both golden cases under that same whitelist. `mdofn` is therefore not a value this module
!   is guessing: it is the one value a pure-displacement 2D field admits (2 dofs/node, ux and
!   uy), and reading any other count would mean a physical field the capability gate should
!   already have rejected upstream of this module. If the whitelist is ever widened to admit
!   a third dof (temperature, pore pressure, ...), this constant must be revisited together
!   with that widening -- it is flagged here for exactly that reason.
!
! TARGETED EQUIVALENCE TEST (design only -- L3's to build, per the task brief)
!   Since no oracle drives these nine sites, the negative-fixture discipline has to do double
!   duty as the positive check too:
!     1. Golden-deck replay: feed `cases/golden/*/legacy/inp` and `.../legacy/1.man` (the
!        real decks) through `parse_inp`/`parse_man` in isolation (no other adapter module, no
!        pipeline) and assert every committed field/leaf against a value hand-read from the
!        deck bytes with `grep -a`/`sed -n`, the same way this module's own reads were
!        verified while it was written. This is the closest available substitute for the
!        oracle: an independent human-legible re-derivation of the same nine records.
!     2. One negative fixture PER whitelist rejection, not one shared fixture: a deck with
!        `restart=1`, one with `relis=1`, ..., one with `runblks=2`, one with `nincs=2`, one
!        with `cwater=1`, one with `Qstatic=1` -- each asserting the specific rule id fires
!        and that reading stops at that record (no further builder/parts mutation happens).
!        adapter-contract.md's own history (M3-03 Round 1) is why: a shared fixture would
!        have let five broken rules hide behind one passing rejection.
!     3. A malformed-record fixture per read site (truncated line, non-numeric token) to
!        confirm `PE_INVALID_INPUT` fires with the reader-inventory id as `object_path` and
!        that no partial value reaches `b` or `parts` -- mirroring the sticky-failure
!        discipline `yl_problem_builder` already enforces on its own calls.
!     4. A `lincs`-dependency fixture: since `lincs=0` here is asserted from `restart==0`
!        (already enforced by `parse_inp`) rather than read, a test that calls `parse_man`
!        without first calling `parse_inp` on the same builder should still behave correctly
!        (this module never reads `restart` itself, so nothing in this file can detect that
!        ordering was skipped -- the test documents that residual risk rather than closing
!        it, since closing it would require a cross-module argument this file does not own).
module yl_adapter_fem90

  use iso_fortran_env, only: int32, real64
  use yl_problem_types, only: case_t
  use yl_problem_builder, only: problem_builder_t, builder_set_case, builder_note_failure
  use yl_problem_errors, only: problem_errors_t, source_location_t, make_source_location, &
                                PE_INVALID_INPUT, PE_UNSUPPORTED
  use yl_problem_optional, only: opt_set
  use yl_adapter_step_parts, only: step_parts_t

  implicit none
  private

  public :: parse_inp, parse_man

  ! docs/m4/adapter-contract.md S4 names `PE_STAGE_ADAPT` as a constant L2-b still has to add
  ! to yl_problem_errors. Until it exists this module names its own stage locally rather than
  ! block on a file it does not own; swap this literal for the real constant when it lands.
  character(len=*), parameter :: STAGE_ADAPT = 'adapt'

  ! See the module header note "WHY WHITELIST_MDOFN = 2 IS NOT AN INVENTED VALUE".
  integer(int32), parameter :: WHITELIST_MDOFN = 2_int32

  integer, parameter :: IOMSG_LEN = 256

contains

  ! ============================================================================================
  ! inp -- PROGRAM FEM90's own body, Fem.f90:94-185
  ! ============================================================================================

  !> Reads the five `inp` records FEM90 consumes before `call global_data`
  !> (legacy/yl/Fem.f90:97-185) and polices the run_control/runblks whitelist.
  subroutine parse_inp(unit, b, errors)
    integer, intent(in) :: unit
    type(problem_builder_t), intent(inout) :: b
    type(problem_errors_t), intent(inout) :: errors

    character(len=80) :: title
    integer(int32) :: restart, relis, sysrelis, adina, uopt_r, gamamax
    character(len=200) :: probn
    integer(int32) :: runblks
    integer :: ios
    character(len=IOMSG_LEN) :: iomsg_buf
    type(source_location_t) :: loc
    type(case_t) :: case_val

    ! RD: INP.FEM90.title#1 (Fem.f90:97)
    ! read (inpunit,*,iostat=yl_ios,iomsg=yl_msg) text
    read (unit, *, iostat=ios, iomsg=iomsg_buf) title
    loc = make_source_location(file='inp', reader='FEM90', line=97_int32, record=1_int32)
    if (.not. check_read(b, errors, ios, iomsg_buf, 'F0/inp-title-1', &
                         'INP.FEM90.title#1', loc)) return

    ! RD: INP.FEM90.run_control (Fem.f90:99)
    ! read (inpunit,*,iostat=yl_ios,iomsg=yl_msg) restart,relis,sysrelis,ADINA,Uopt_R,gamamax
    read (unit, *, iostat=ios, iomsg=iomsg_buf) restart, relis, sysrelis, adina, uopt_r, gamamax
    loc = make_source_location(file='inp', reader='FEM90', line=99_int32, record=2_int32)
    if (.not. check_read(b, errors, ios, iomsg_buf, 'F0/inp-run-control', &
                         'INP.FEM90.run_control', loc)) return

    ! Whitelist: static-q4/1 pins every one of these six flags at 0 (state-field-map.toml,
    ! control.run.{restart,relis,sysrelis,adina,uopt_r,gamamax}: "pinned guard: value 0 keeps
    ! control flow on static_2d path"). See the module header for what each nonzero value
    ! actually triggers in legacy.
    if (.not. reject_nonzero(b, errors, restart, 'control.run.restart', 'F1/restart', loc, &
        'restart/=0 resumes a prior run (Fem.f90:277-309); this build only reads a fresh ' // &
        'deck')) return
    if (.not. reject_nonzero(b, errors, relis, 'control.run.relis', 'F1/relis', loc, &
        'relis/=0 enables the reliability-analysis branch (STATIC_U_reli, Fem.f90:1921), ' // &
        'not read by this module')) return
    if (.not. reject_nonzero(b, errors, sysrelis, 'control.run.sysrelis', 'F1/sysrelis', loc, &
        'sysrelis/=0 enables the system-reliability branch (Fem.f90:5380,6230), not read ' // &
        'by this module')) return
    if (.not. reject_nonzero(b, errors, adina, 'control.run.adina', 'F1/adina', loc, &
        'ADINA/=0 diverts to the ADINA export path and stops the run (Fem.f90:1900-1902)')) &
        return
    if (.not. reject_nonzero(b, errors, uopt_r, 'control.run.uopt_r', 'F1/uopt_r', loc, &
        'Uopt_R==1 reads an entire extra optimisation-coordinate deck (Fem.f90:120-142) ' // &
        'that has no reader-inventory entry')) return
    if (.not. reject_nonzero(b, errors, gamamax, 'control.run.gamamax', 'F1/gamamax', loc, &
        'gamamax/=0 opens an equivalent-linearisation soil-constitutive file ' // &
        '(Fem.f90:1724-1730)')) return

    ! RD: INP.FEM90.title#2 (Fem.f90:101)
    ! read (inpunit,*,iostat=yl_ios,iomsg=yl_msg) text
    read (unit, *, iostat=ios, iomsg=iomsg_buf) title
    loc = make_source_location(file='inp', reader='FEM90', line=101_int32, record=3_int32)
    if (.not. check_read(b, errors, ios, iomsg_buf, 'F0/inp-title-2', &
                         'INP.FEM90.title#2', loc)) return

    ! RD: INP.FEM90.problem_name (Fem.f90:103)
    ! read (inpunit,*,iostat=yl_ios,iomsg=yl_msg) probn
    read (unit, *, iostat=ios, iomsg=iomsg_buf) probn
    loc = make_source_location(file='inp', reader='FEM90', line=103_int32, record=4_int32)
    if (.not. check_read(b, errors, ios, iomsg_buf, 'F0/inp-problem-name', &
                         'case.name', loc)) return
    call opt_set(case_val%name, trim(probn))
    call builder_set_case(b, case_val, loc, errors)

    ! RD: INP.FEM90.runblks (Fem.f90:185)
    ! read (inpunit,*,iostat=yl_ios,iomsg=yl_msg)runblks
    read (unit, *, iostat=ios, iomsg=iomsg_buf) runblks
    loc = make_source_location(file='inp', reader='FEM90', line=185_int32, record=5_int32)
    if (.not. check_read(b, errors, ios, iomsg_buf, 'F0/inp-runblks', &
                         'derived.counts.runblks', loc)) return

    ! Whitelist: static-q4/1 is single-stage. derived.counts.runblks's own map note reads
    ! "= len(steps) executed; equals nblks=1 on both cases" -- a runblks other than 1 asks for
    ! a `steps` array this capability slice does not cover.
    if (runblks /= 1_int32) then
      call builder_note_failure(b, PE_UNSUPPORTED, 'F1/runblks', 'derived.counts.runblks', &
        '', 'runblks must be 1 under static-q4/1 (single-stage static); this build cannot ' // &
        'represent a multi-block analysis', loc, errors)
      return
    end if
  end subroutine parse_inp

  ! ============================================================================================
  ! .man -- STATIC_U, Fem.f90:3593-3633 (an INTERNAL subprogram of PROGRAM FEM90)
  ! ============================================================================================

  !> Reads the four `.man` records STATIC_U consumes before its convergence loop
  !> (legacy/yl/Fem.f90:3593-3633), polices the nincs/cwater/Qstatic whitelist, and fills the
  !> `controls`/`output%frequency` leaves of `parts` that this module owns (see the module
  !> header's leaf-ownership discussion; the other leaves of `steps[0]` are `.glb`/`.loa`/
  !> `.pre`'s and are never touched here).
  subroutine parse_man(unit, b, parts, errors)
    integer, intent(in) :: unit
    type(problem_builder_t), intent(inout) :: b
    type(step_parts_t), intent(inout) :: parts
    type(problem_errors_t), intent(inout) :: errors

    character(len=80) :: title
    integer(int32) :: nincs, lincs, iincs
    integer(int32) :: miter, noutn, noutf, nstep, inc_step, nresta, cwater, qstatic
    real(real64) :: ditime
    real(real64) :: toler_force
    real(real64) :: toler_var(WHITELIST_MDOFN)
    integer :: ios
    character(len=IOMSG_LEN) :: iomsg_buf
    type(source_location_t) :: loc

    ! RD: MAN.STATIC_U.title#1 (Fem.f90:3593) -- guard type_problem=='Q' (STATIC_U)
    ! read(mainunit,*,iostat=yl_ios,iomsg=yl_msg)text
    read (unit, *, iostat=ios, iomsg=iomsg_buf) title
    loc = make_source_location(file='.man', reader='STATIC_U', line=3593_int32, record=1_int32)
    if (.not. check_read(b, errors, ios, iomsg_buf, 'F0/man-title-1', &
                         'MAN.STATIC_U.title#1', loc)) return

    ! RD: MAN.STATIC_U.nincs (Fem.f90:3595) -- guard STATIC_U
    ! read(mainunit,*,iostat=yl_ios,iomsg=yl_msg)nincs
    read (unit, *, iostat=ios, iomsg=iomsg_buf) nincs
    loc = make_source_location(file='.man', reader='STATIC_U', line=3595_int32, record=2_int32)
    if (.not. check_read(b, errors, ios, iomsg_buf, 'F0/man-nincs', &
                         'steps0.controls.increments', loc)) return

    ! Fem.f90:3596 (`call diag_range(...,'nincs',...,1_i8,...)`): nincs must be a positive
    ! increment count. This is ordinary malformed-input policing, not a whitelist choice.
    if (nincs < 1_int32) then
      call builder_note_failure(b, PE_INVALID_INPUT, 'F0/man-nincs-range', &
        'steps0.controls.increments', '', 'nincs must be >= 1', loc, errors)
      return
    end if

    ! Whitelist: controls_t carries ONE scalar set of the per-increment fields below, not one
    ! per increment, and legacy OVERWRITES them on every pass of `do iincs=lincs+1,nincs`
    ! (Fem.f90:3622). Continuing to read with nincs>1 would silently keep only the last
    ! increment's values -- rejected here, before the loop runs, rather than discovered by
    ! watching it iterate more than once.
    if (nincs /= 1_int32) then
      call builder_note_failure(b, PE_UNSUPPORTED, 'F2/multi-increment', &
        'steps0.controls.increments', '', &
        'nincs must be 1: ProblemState.steps[0].controls has no per-increment array, so ' // &
        'more than one increment cannot be represented without silently dropping data', &
        loc, errors)
      return
    end if

    ! Fem.f90:280 (`if (restart==0) ... lincs=0`): lincs is pinned to 0 on this path. This
    ! module never reads `restart` itself -- INP.FEM90.run_control is parse_inp's site -- so
    ! this line is only correct because the driver calls parse_inp before parse_man on the
    ! same builder, exactly as FEM90's own body does (Fem.f90:99 precedes Fem.f90:3593). See
    ! the module header's targeted-equivalence-test note 4 for the residual risk if that call
    ! order is ever violated.
    lincs = 0_int32

    ! Fem.f90:3622-3650 (loop body containing the two reads below). Reproduced as a loop, not
    ! hardcoded to one iteration, because that IS the legacy structure; it runs exactly once
    ! here only because lincs=0 and nincs=1 were just established above.
    do iincs = lincs + 1_int32, nincs

      ! RD: MAN.STATIC_U.increment_control (Fem.f90:3627) -- guard loop iincs=lincs+1..nincs
      ! read(mainunit,*,iostat=yl_ios,iomsg=yl_msg)miter,ditime,noutn,noutf,nstep,inc_step,
      !   nresta,cwater,Qstatic
      read (unit, *, iostat=ios, iomsg=iomsg_buf) miter, ditime, noutn, noutf, nstep, &
        inc_step, nresta, cwater, qstatic
      loc = make_source_location(file='.man', reader='STATIC_U', line=3627_int32, &
                                 record=int(iincs, int32))
      if (.not. check_read(b, errors, ios, iomsg_buf, 'F0/man-increment-control', &
                           'steps0.controls.max_iterations', loc)) return

      ! Fem.f90:3628-3630 (`call diag_range(...,1_i8,...)` for miter/nstep/inc_step): ordinary
      ! malformed-input policing on the same record, not a whitelist choice.
      if (miter < 1_int32) then
        call builder_note_failure(b, PE_INVALID_INPUT, 'F0/man-miter-range', &
          'steps0.controls.max_iterations', '', 'miter must be >= 1', loc, errors)
        return
      end if
      if (nstep < 1_int32) then
        call builder_note_failure(b, PE_INVALID_INPUT, 'F0/man-nstep-range', &
          'steps0.controls.steps', '', 'nstep must be >= 1', loc, errors)
        return
      end if
      if (inc_step < 1_int32) then
        call builder_note_failure(b, PE_INVALID_INPUT, 'F0/man-inc-step-range', &
          'steps0.controls.step_increment', '', 'inc_step must be >= 1', loc, errors)
        return
      end if

      ! Whitelist: cwater and Qstatic are read every record but neither has a ProblemState
      ! owner (state-field-map.toml: both `not_migrated`). Nonzero enables branches
      ! (Fem.f90:3636-3650 water-coupling; Qstatic-specific reads further down STATIC_U) this
      ! whitelist slice does not cover.
      if (.not. reject_nonzero(b, errors, cwater, 'not_migrated.cwater', 'F2/cwater', loc, &
          'cwater/=0 enables the water-coupling coefficient branch (Fem.f90:3636-3641), ' // &
          'not read by this module')) return
      if (.not. reject_nonzero(b, errors, qstatic, 'not_migrated.qstatic', 'F2/qstatic', loc, &
          'Qstatic/=0 enables the quasi-static-force reads further down STATIC_U, not read ' // &
          'by this module')) return

      ! RD: MAN.STATIC_U.tolerances (Fem.f90:3633) -- guard loop iincs
      ! read(mainunit,*,iostat=yl_ios,iomsg=yl_msg)toler_force,toler_var(1:mdofn)
      read (unit, *, iostat=ios, iomsg=iomsg_buf) toler_force, toler_var
      loc = make_source_location(file='.man', reader='STATIC_U', line=3633_int32, &
                                 record=int(iincs, int32))
      if (.not. check_read(b, errors, ios, iomsg_buf, 'F0/man-tolerances', &
                           'steps0.controls.tolerance_force', loc)) return

    end do

    ! Commit the leaves this module owns (see the module header's leaf-ownership table).
    ! controls%nonlinear_type is `.glb`'s and is deliberately left untouched.
    call opt_set(parts%controls%increments, nincs)
    call opt_set(parts%controls%max_iterations, miter)
    call opt_set(parts%controls%steps, nstep)
    call opt_set(parts%controls%step_increment, inc_step)
    call opt_set(parts%controls%restart_frequency, nresta)
    call opt_set(parts%controls%time_increment, ditime)
    call opt_set(parts%controls%tolerance_force, toler_force)
    parts%controls%tolerance_dof = toler_var

    ! output%frequency is this module's per the map (see the module header's flagged
    ! discrepancy with yl_adapter_step_parts's leaf-ownership comment); output%format and
    ! output%field are `.glb`'s and are deliberately left untouched.
    call opt_set(parts%output%frequency%nodes, noutn)
    call opt_set(parts%output%frequency%fields, noutf)
  end subroutine parse_man

  ! ============================================================================================
  ! private helpers
  ! ============================================================================================

  !> Checks an iostat from a list-directed read. On failure, binds PE_INVALID_INPUT to `b`
  !> (marking the whole draft failed) and returns .false. so the caller stops reading:
  !> adapter-contract.md S2 -- "失败即返回，不吞掉错误、不继续读" -- because this repo's
  !> position-sensitive deck protocol turns a bad read into misaligned garbage if reading
  !> continues past it.
  function check_read(b, errors, ios, iomsg_buf, rule_id, object_path, loc) result(ok)
    type(problem_builder_t), intent(inout) :: b
    type(problem_errors_t), intent(inout) :: errors
    integer, intent(in) :: ios
    character(len=*), intent(in) :: iomsg_buf
    character(len=*), intent(in) :: rule_id, object_path
    type(source_location_t), intent(in) :: loc
    logical :: ok
    ok = (ios == 0)
    if (.not. ok) then
      call builder_note_failure(b, PE_INVALID_INPUT, rule_id, object_path, '', &
        'list-directed read failed: iostat='//itoa(ios)//' iomsg='//trim(iomsg_buf), &
        loc, errors)
    end if
  end function check_read

  !> Rejects a nonzero flag as PE_UNSUPPORTED, naming `rule_id` and explaining in `why` (see
  !> the module header) what branch of legacy the flag would have taken. Returns .true. (and
  !> emits nothing) when the flag is 0, matching this build's static-q4/1 pinned-guard values.
  function reject_nonzero(b, errors, value, object_path, rule_id, loc, why) result(ok)
    type(problem_builder_t), intent(inout) :: b
    type(problem_errors_t), intent(inout) :: errors
    integer(int32), intent(in) :: value
    character(len=*), intent(in) :: object_path, rule_id, why
    type(source_location_t), intent(in) :: loc
    logical :: ok
    ok = (value == 0_int32)
    if (.not. ok) then
      call builder_note_failure(b, PE_UNSUPPORTED, rule_id, object_path, '', why, loc, errors)
    end if
  end function reject_nonzero

  !> Minimal integer-to-text helper, local so this module depends on neither yl_diag's
  !> diag_itoa nor yl_problem_manifest's private itoa.
  pure function itoa(value) result(text)
    integer, intent(in) :: value
    character(len=:), allocatable :: text
    character(len=12) :: buffer
    write (buffer, '(i0)') value
    text = trim(buffer)
  end function itoa

end module yl_adapter_fem90
