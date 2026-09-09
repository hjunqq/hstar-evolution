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
!   `output%frequency%{nodes,fields}` is this module's leaf, `output%format`/`output%field`/
!   `output%stress_averaging` are `.glb`'s -- corrected 2026-09-08 in
!   src/adapter/yl_adapter_parts.f90's leaf-ownership table after this module's first draft
!   flagged that its earlier version wrongly attributed all of `output` to `.glb`; the map
!   (docs/m2/state-field-map.toml, `steps0.output.frequency_nodes`/`frequency_fields` sourced
!   to `MAN.STATIC_U.increment_control`) is what settled it, and that table now says so.
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
!     4. A `ctx%filled`-dependency fixture: call `parse_man` with a freshly-reset,
!        never-filled `ctx` and confirm `F3/ctx-not-filled` fires (see below) rather than
!        silently proceeding with `lincs=0`. This closes the ordering risk for "did parse_glb
!        run first" but only for that much: `ctx%filled` is a proxy for "the driver reached
!        parse_glb", not a proof that `parse_inp` specifically ran before `parse_man` on the
!        same deck (parse_glb and parse_inp read different files and neither's state proves
!        the other ran). That residual half of the assumption is still open and still worth a
!        fixture documenting it, not closing it silently.
module yl_adapter_fem90

  use iso_fortran_env, only: int32, real64
  use yl_problem_types, only: case_t
  use yl_problem_builder, only: problem_builder_t, builder_set_case, builder_note_failure
  use yl_problem_errors, only: problem_errors_t, source_location_t, make_source_location, &
                                PE_INVALID_INPUT, PE_INTERNAL
  use yl_problem_optional, only: opt_set
  use yl_adapter_parts, only: step_parts_t, deck_context_t, reject_dialect

  implicit none
  private

  public :: parse_inp, parse_man


  ! See the module header note "WHY WHITELIST_MDOFN = 2 IS NOT AN INVENTED VALUE".
  integer(int32), parameter :: WHITELIST_MDOFN = 2_int32

  integer, parameter :: IOMSG_LEN = 256

contains

  ! ============================================================================================
  ! inp -- PROGRAM FEM90's own body, Fem.f90:94-185
  ! ============================================================================================

  !> Reads the five `inp` records FEM90 consumes before `call global_data`
  !> (legacy/yl/Fem.f90:97-185) and polices the run_control/runblks whitelist.
  !>
  !> `ctx` is accepted only for uniformity with the other parsers (contract S2.2) and is
  !> INTENTIONALLY UNUSED here: `inp` is read before `.glb` in FEM90's own order
  !> (Fem.f90:94-117 precedes `call global_data`), so `ctx` cannot yet be filled when this
  !> runs. Reading it here would be a bug, not a missed opportunity -- do not "fix" that by
  !> adding a use of it.
  subroutine parse_inp(unit, ctx, b, errors)
    integer, intent(in) :: unit
    type(deck_context_t), intent(in) :: ctx
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
    if (.not. reject_nonzero(errors, restart, 'F1', 'restart', loc)) return
    if (.not. reject_nonzero(errors, relis, 'F1', 'relis', loc)) return
    if (.not. reject_nonzero(errors, sysrelis, 'F1', 'sysrelis', loc)) return
    if (.not. reject_nonzero(errors, adina, 'F1', 'adina', loc)) return
    if (.not. reject_nonzero(errors, uopt_r, 'F1', 'uopt_r', loc)) return
    if (.not. reject_nonzero(errors, gamamax, 'F1', 'gamamax', loc)) return

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
      call reject_dialect(errors, 'F1', 'runblks', loc, actual=itoa(int(runblks)), expected='1')
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
  !>
  !> `ctx` itself is not read for anything but `%filled` -- this module has no site that
  !> needs `ndimn`/`ngroup`/etc, only the ordering guarantee `%filled` stands for (see below).
  subroutine parse_man(unit, ctx, b, parts, errors)
    integer, intent(in) :: unit
    type(deck_context_t), intent(in) :: ctx
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

    ! Ordering guard, not a deck read: `ctx%filled` is set only by parse_glb, which FEM90's
    ! own body runs before STATIC_U (`call global_data` at Fem.f90:117, long before STATIC_U
    ! is ever reached). An unfilled `ctx` here means the driver invoked parse_man before
    ! parse_glb -- a sequencing bug in the driver, not a defect in the deck this module is
    ! reading, hence PE_INTERNAL rather than PE_INVALID_INPUT/PE_UNSUPPORTED. This closes only
    ! HALF of the residual ordering assumption flagged in the module header's equivalence-test
    ! note 4: it proves parse_glb ran first, and parse_glb necessarily runs after parse_inp in
    ! the documented FEM90 order, but it is not a direct proof that parse_inp itself ran on
    ! this same deck -- that half stays open and is why `lincs=0` below still cites parse_inp
    ! by name rather than by `ctx`.
    if (.not. ctx%filled) then
      loc = make_source_location(reader='STATIC_U')
      call builder_note_failure(b, PE_INTERNAL, 'F3/ctx-not-filled', 'deck_context', '', &
        'parse_man was called with an unfilled deck_context_t; parse_glb (and, by the ' // &
        'documented FEM90 call order, parse_inp) must run before parse_man on the same deck', &
        loc, errors)
      return
    end if

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
      call reject_dialect(errors, 'F2', 'multi-increment', loc, actual=itoa(int(nincs)), &
                          expected='1')
      return
    end if

    ! Fem.f90:280 (`if (restart==0) ... lincs=0`): lincs is pinned to 0 on this path. This
    ! module never reads `restart` itself -- INP.FEM90.run_control is parse_inp's site -- so
    ! this line is only correct because the driver calls parse_inp before parse_man on the
    ! same deck, exactly as FEM90's own body does (Fem.f90:99 precedes Fem.f90:3593). The
    ! `ctx%filled` check above proves parse_glb ran first (and parse_glb runs after parse_inp
    ! in that same documented order), which is corroborating evidence, not a direct proof for
    ! parse_inp specifically -- see the module header's equivalence-test note 4.
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
      if (.not. reject_nonzero(errors, cwater, 'F2', 'cwater', loc)) return
      if (.not. reject_nonzero(errors, qstatic, 'F2', 'qstatic', loc)) return

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

  !> Rejects a nonzero flag as the dialect row (`rule_id`, `condition`). Returns .true. (and
  !> emits nothing) when the flag is 0, matching this build's static-q4/1 pinned-guard values.
  !>
  !> WHAT `object_path` AND `why` USED TO DO, AND WHY THEY ARE GONE (M4-01 L2-b)
  !> Both were arguments, spelled at each call site. They are now columns of the row and are
  !> read from it, so a call site can no longer describe its own rejection differently from
  !> the table that declares it.
  !>
  !> WHAT CHANGED IN BEHAVIOUR, STATED RATHER THAN GLOSSED
  !> The old raise went through `builder_note_failure`, which ALSO set `b%failed` -- and
  !> stamped the finding `stage='builder'`, not `'adapt'`, which contradicted
  !> docs/m4/adapter-contract.md SS4. The unified raiser stamps PE_STAGE_ADAPT and does not
  !> touch the builder. `b` is therefore no longer read here, and both callers of parse_inp /
  !> parse_man (yl_adapter_driver and yl_adapter_fidelity) stop on `errors%count()` growing,
  !> not on `builder_failed`, so the fail-fast is unchanged; the two parsers themselves
  !> so the `b` dummy is gone too rather than kept as an argument nothing reads.
  function reject_nonzero(errors, value, rule_id, condition, loc) result(ok)
    type(problem_errors_t), intent(inout) :: errors
    integer(int32), intent(in) :: value
    character(len=*), intent(in) :: rule_id, condition
    type(source_location_t), intent(in) :: loc
    logical :: ok
    ok = (value == 0_int32)
    if (.not. ok) then
      call reject_dialect(errors, rule_id, condition, loc, actual=itoa(int(value)), expected='0')
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
