! yl_adapter_material -- M4-01 legacy adapter: .mat (materials) and .sol (solver
! controls), per docs/m4/adapter-contract.md §2. Neither deck touches `steps[0]`,
! confirmed against the state-field map and against team-lead review: .mat feeds
! only materials[], .sol feeds only the top-level solver singleton. parse_mat keeps
! the plain parse_<kind>(unit, ctx, b, errors) shape; parse_sol additionally takes
! `sparts` per contract §2.2 (below).
!
! Scope
!   The fourteen reader-inventory sites whose `file` is .mat (12) or .sol (2):
!     MAT.material_set.title#1              (Material.f90:243)
!     MAT.material_set.curve_count          (Material.f90:245)
!     MAT.material_set.comment_line_count   (Material.f90:261)
!     MAT.material_set.comment_line#1       (Material.f90:264)
!     MAT.material_set.title#2              (Material.f90:270)
!     MAT.material_set.nmats                (Material.f90:272)
!     MAT.material_set.title#3              (Material.f90:281)
!     MAT.material_set.material_header      (Material.f90:283)
!     MAT.material_set.material_nphase      (Material.f90:298)
!     MAT.material_set.material_phase       (Material.f90:302)
!     MAT.material_set.elastic_isotropic    (Material.f90:310)
!     MAT.material_set.elastic_extra        (Material.f90:313)
!     SOL.PROFILE.title#1                   (Solver.f90:6829)
!     SOL.PROFILE.profile_control           (Solver.f90:6831)
!   and nothing else. Neither routine opens/closes/rewinds `unit` (L2-a owns that
!   lifecycle), touches a legacy global, or writes ProblemState except through
!   yl_problem_builder.
!
! Whitelist (static-q4/1; not enlarged, adapter-contract.md §5): MECHANICAL / SOLID /
! ELASTIC_ISOTROPIC material, no property curves, no creep, no wetting deformation,
! no liquefaction, no CONTACT or NOLINORMK material, PROFILE solver with no pivot
! file. Every one of those is a BRANCH in `material_set` / `PROFILE` that reads
! additional records this build has no ProblemState field for (Material.f90:294-722
! is one long nested SELECT on exactly these switches). Continuing to read past an
! un-whitelisted switch would consume the wrong shape and corrupt every record after
! it, so this parser checks each switch the instant it is read and returns with
! PE_UNSUPPORTED before attempting anything the legacy branch would have read next.
! This mirrors the contract's "失败即返回，不吞掉错误、不继续读" (§2) rather than
! duplicating it: unlike a value the validate stage could still reject after the
! fact (e.g. rule V6's duplicate-id check, deliberately NOT repeated here), a wrong
! record SHAPE is unrecoverable inside this parser and must stop it cold.
!
! solver_t is a cross-file singleton -- RESOLVED via yl_adapter_parts.solver_parts_t
!   docs/m2/state-field-map.toml puts solver.symmetric's source at .glb
!   (GLB.global_data.init_and_blocks, legacy_symbol global_var.nonsym) and
!   solver.linear at .glb too (GLB.global_data.problem_type) -- only
!   solver.profile.* (the four SOL.PROFILE.profile_control fields) is .sol's.
!   yl_problem_builder's builder_set_solver is a SINGLETON setter, the same class of
!   bug the 2026-09-08 contract revision fixed for steps[0] via
!   yl_adapter_parts.step_parts_t; the same file now also carries solver_parts_t for
!   exactly this split. This was flagged from here and confirmed correct except for
!   one detail: `linear` was originally assumed to be .sol's, but the map sources it
!   from .glb like `symmetric`. parse_sol below therefore fills ONLY
!   sparts%solver%profile.* and never calls builder_set_solver itself -- L2-a's
!   driver makes that one call once both this parser and the .glb parser have filled
!   their leaves of the shared `sparts`.
!
! sections[] is ALSO a deferred-publication object (adapter-contract.md §2.4, added
! 2026-09-09 after L3-a's fidelity gate) -- the third instance of this shape, after
! steps[0] and solver:
!   `sections[].thickness` comes from .mat (Material.f90:319, stored PER MATERIAL,
!   `props(imat)%mechanical%solid%thickness`) while every other field of a section
!   comes from .glb's group header. Legacy reads .glb before .mat (Fem.f90:117,:191),
!   so at the point parse_glb builds a section it does not yet know that section's
!   thickness, and `builder_add_section` -- like builder_set_solver -- takes a whole
!   section_t with no way to amend one already published. So parse_glb fills every
!   OTHER field of secparts%sections(:) and does not call builder_add_section;
!   parse_mat below resolves section -> material (via ctx%group_matno) -> thickness
!   and fills ONLY that one field; the driver calls builder_add_section once per
!   section, in order, after both have run.
!
!   This module's own earlier defect (fixed here): an prior revision of parse_mat
!   read `thickness` (Material.f90:319) and DISCARDED it, reasoning correctly that
!   its ProblemState owner is sections[], not materials[], but wrongly concluding
!   that made it someone else's field to fill -- the same mistake this file's
!   `.ele`-attribution note (yl_adapter_mesh.f90) had already named once: the map's
!   `owner`/`derived_from` columns name the FIELD'S SOURCE FILE, not a different
!   MODULE, and nothing else in this repository read .mat's thickness at all.
!   Caught by L3-a's fidelity gate, not by any golden-deck numeric mismatch (both
!   golden decks carry the map's "plane-strain placeholder" thickness of 1.0, so a
!   silently dropped value and a correctly threaded one look identical there).
module yl_adapter_material

  use iso_fortran_env, only: int32, real64, iostat_end
  use yl_problem_optional, only: opt_set
  use yl_problem_types, only: material_t
  use yl_problem_builder, only: problem_builder_t, builder_add_material, &
                                 builder_materials_empty, builder_failed
  use yl_problem_errors, only: problem_errors_t, source_location_t, make_source_location, &
                                make_problem_error, PE_INVALID_INPUT, PE_INTERNAL,             &
                                PE_STAGE_ADAPT
  use yl_adapter_parts, only: deck_context_t, solver_parts_t, section_parts_t, reject_dialect

  implicit none
  private

  public :: parse_mat, parse_sol


contains

  ! ============================================================================
  ! .mat
  ! ============================================================================

  ! RD: MAT.material_set.title#1 .. MAT.material_set.elastic_extra
  ! (Material.f90:243-313). See the module header for why every switch below is
  ! checked the instant it is read, not deferred to a later stage.
  !
  ! `ctx` (adapter-contract.md §2.2) polices call order (below) and, new in this
  ! revision, supplies `ctx%group_matno(:)` -- the material id each section's
  ! header declared -- which is what lets this routine resolve section ->
  ! material -> thickness (adapter-contract.md §2.4, module header). No other
  ! .mat record shape in this whitelist slice depends on ctx: unlike .cor/.ele/.pre,
  ! nothing else material_set reads here is sized or branched by ndimn, element
  ! kind or type_abc.
  !
  ! `secparts` is `yl_adapter_parts.section_parts_t`: parse_glb fills every field of
  ! secparts%sections(:) except thickness, this routine fills only that field, and
  ! the driver publishes the finished sections (module header).
  subroutine parse_mat(unit, ctx, b, secparts, errors)
    integer, intent(in) :: unit
    type(deck_context_t), intent(in) :: ctx
    type(problem_builder_t), intent(inout) :: b
    type(section_parts_t), intent(inout) :: secparts
    type(problem_errors_t), intent(inout) :: errors

    character(len=200) :: text
    character(len=200) :: iomsg_buf
    character(len=30) :: property, name, phase, material
    integer(int32) :: ios, nscurve, nline, iline, mmats, jmat
    integer(int32) :: imat, nphase, icreep, kind_wt, jliqu
    integer(int32) :: iE_switch, iNu_switch
    real(real64) :: density, ratio, thickness, e, nu, alfa, density_w
    real(real64), allocatable :: mat_thickness(:)   ! thickness by material id, filled below
    type(material_t) :: mat
    type(source_location_t) :: loc

    if (.not. ctx%filled) then
      loc = make_source_location(file='.mat', reader='material_set', line=243_int32)
      call errors%add(make_problem_error(code=PE_INTERNAL, stage=PE_STAGE_ADAPT, &
                      rule_id='A-MAT/context-not-filled', object_path='materials', &
                      message='parse_mat was called before parse_glb filled deck_context_t', &
                      source=loc))
      return
    end if

    ! RD: MAT.material_set.title#1 (Material.f90:243) -- a title line, discarded.
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    if (.not. mat_read_ok(errors, ios, iomsg_buf, 'MAT.material_set.title#1', 243_int32)) return

    ! RD: MAT.material_set.curve_count (Material.f90:245)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) nscurve
    if (.not. mat_read_ok(errors, ios, iomsg_buf, 'MAT.material_set.curve_count', 245_int32)) return
    if (nscurve /= 0_int32) then
      call mat_reject(errors, 'curve-count', 245_int32, itoa(nscurve))
      return
    end if

    ! RD: MAT.material_set.comment_line_count (Material.f90:261)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) nline
    if (.not. mat_read_ok(errors, ios, iomsg_buf, 'MAT.material_set.comment_line_count', &
                          261_int32)) return
    do iline = 1_int32, nline
      ! RD: MAT.material_set.comment_line#1 (Material.f90:264) -- free text, discarded.
      read (unit, *, iostat=ios, iomsg=iomsg_buf) text
      if (.not. mat_read_ok(errors, ios, iomsg_buf, 'MAT.material_set.comment_line#1', &
                            264_int32, rec=iline)) return
    end do

    ! RD: MAT.material_set.title#2 (Material.f90:270) -- a title line, discarded.
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    if (.not. mat_read_ok(errors, ios, iomsg_buf, 'MAT.material_set.title#2', 270_int32)) return

    ! RD: MAT.material_set.nmats (Material.f90:272)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) mmats
    if (.not. mat_read_ok(errors, ios, iomsg_buf, 'MAT.material_set.nmats', 272_int32)) return

    ! mmats must equal the .glb-declared nmats (Material.f90:274, diag_range) for
    ! `props` to be sized correctly; that cross-file count lives on the .glb side and
    ! is invisible here (same class of gap as ndimn in yl_adapter_mesh.f90). Left to
    ! whatever cross-file count-consistency rule the pipeline runs, not asserted here.
    if (mmats <= 0_int32) then
      loc = make_source_location(file='.mat', reader='material_set', line=272_int32)
      call builder_materials_empty(b, loc, errors)
      return
    end if

    ! Sized by mmats, indexed by imat: materials.id's own note records that imat IS
    ! the props(:) index (Material.f90:293, "props(imat)%name=trim(name)"), so this
    ! mirrors legacy's own storage instead of inventing a second numbering. Needed
    ! now (not merely nice to have) because the array is about to be INDEXED by
    ! imat below -- unlike the duplicate-id question (left to rule V6, module
    ! header), an out-of-range imat here is a memory-safety problem this routine
    ! cannot defer to a later stage.
    allocate (mat_thickness(mmats))

    do jmat = 1_int32, mmats

      ! RD: MAT.material_set.title#3 (Material.f90:281) -- a title line, discarded.
      read (unit, *, iostat=ios, iomsg=iomsg_buf) text
      if (.not. mat_read_ok(errors, ios, iomsg_buf, 'MAT.material_set.title#3', 281_int32, &
                            rec=jmat)) return

      ! RD: MAT.material_set.material_header (Material.f90:283)
      read (unit, *, iostat=ios, iomsg=iomsg_buf) property, name, imat
      if (.not. mat_read_ok(errors, ios, iomsg_buf, 'MAT.material_set.material_header', &
                            283_int32, rec=jmat)) return
      if (imat < 1_int32 .or. imat > mmats) then
        loc = make_source_location(file='.mat', reader='material_set', line=283_int32, &
                                    record=jmat)
        call errors%add(make_problem_error(code=PE_INVALID_INPUT, stage=PE_STAGE_ADAPT, &
                        rule_id='A-MAT/material-id-range', object_path='materials', &
                        index=jmat, field='id', &
                        message='imat must address the 1..nmats props(:) slot ' &
                        //'(Material.f90:274, diag_range); mat_thickness(imat) below ' &
                        //'would be indexed out of bounds otherwise', &
                        actual=itoa(imat), expected='1..'//itoa(mmats), source=loc))
        return
      end if
      if (trim(property) /= 'MECHANICAL') then
        call mat_reject(errors, 'property', 294_int32, trim(property), rec=jmat)
        return
      end if

      ! RD: MAT.material_set.material_nphase (Material.f90:298)
      read (unit, *, iostat=ios, iomsg=iomsg_buf) nphase
      if (.not. mat_read_ok(errors, ios, iomsg_buf, 'MAT.material_set.material_nphase', &
                            298_int32, rec=jmat)) return
      if (nphase /= 1_int32) then
        call mat_reject(errors, 'phase-count', 298_int32, itoa(nphase), rec=jmat)
        return
      end if

      ! RD: MAT.material_set.material_phase (Material.f90:302)
      read (unit, *, iostat=ios, iomsg=iomsg_buf) phase
      if (.not. mat_read_ok(errors, ios, iomsg_buf, 'MAT.material_set.material_phase', &
                            302_int32, rec=jmat)) return
      if (trim(phase) /= 'SOLID') then
        call mat_reject(errors, 'phase', 305_int32, trim(phase), rec=jmat)
        return
      end if

      ! RD: MAT.material_set.elastic_isotropic (Material.f90:310)
      read (unit, *, iostat=ios, iomsg=iomsg_buf) material, density, ratio, thickness, e, nu, &
                                                   alfa, icreep, kind_wt, jliqu
      if (.not. mat_read_ok(errors, ios, iomsg_buf, 'MAT.material_set.elastic_isotropic', &
                            310_int32, rec=jmat)) return

      ! RD: MAT.material_set.elastic_extra (Material.f90:313) -- always read (it is
      ! unconditional in legacy, Material.f90:313, ahead of every jliqu/icreep/kind_wt
      ! branch below). iE/iNu/density_w map to materials.ie / materials.inu /
      ! materials.density_w in docs/m2/state-field-map.toml, all three
      ! `owner = "not_migrated"` ("consumed only when Bparameter/=0", which
      ! static-q4/1 fixes at 0) -- read here and discarded, not this parser's field.
      read (unit, *, iostat=ios, iomsg=iomsg_buf) iE_switch, iNu_switch, density_w
      if (.not. mat_read_ok(errors, ios, iomsg_buf, 'MAT.material_set.elastic_extra', &
                            313_int32, rec=jmat)) return

      if (icreep /= 0_int32) then
        call mat_reject(errors, 'creep', 357_int32, itoa(icreep), rec=jmat)
        return
      end if
      if (kind_wt /= 0_int32) then
        call mat_reject(errors, 'wetting', 402_int32, itoa(kind_wt), rec=jmat)
        return
      end if
      if (jliqu /= 0_int32) then
        call mat_reject(errors, 'liquefaction', 330_int32, itoa(jliqu), rec=jmat)
        return
      end if
      if (trim(name) == 'CONTACT') then
        call mat_reject(errors, 'contact-material', 419_int32, trim(name), rec=jmat)
        return
      end if
      if (trim(name) == 'NOLINORMK') then
        call mat_reject(errors, 'nonlinear-normal-stiffness', 450_int32, trim(name), rec=jmat)
        return
      end if
      if (trim(material) /= 'ELASTIC_ISOTROPIC') then
        call mat_reject(errors, 'model', 457_int32, trim(material), rec=jmat)
        return
      end if

      call opt_set(mat%id, imat)
      call opt_set(mat%name, trim(name))
      call opt_set(mat%kind, trim(property))          ! == 'MECHANICAL', checked above
      call opt_set(mat%phase, trim(phase))             ! == 'SOLID', checked above
      call opt_set(mat%model, trim(material))          ! == 'ELASTIC_ISOTROPIC', checked above
      call opt_set(mat%E, e)
      call opt_set(mat%nu, nu)
      call opt_set(mat%density, density)
      call opt_set(mat%thermal_expansion, alfa)
      call opt_set(mat%solid_ratio, ratio)
      call opt_set(mat%creep_model, icreep)             ! == 0, checked above
      call opt_set(mat%liquefaction, jliqu)              ! == 0, checked above
      call opt_set(mat%wetting_kind, kind_wt)            ! == 0, checked above
      ! `thickness` (Material.f90:319) is NOT a materials[] field -- its ProblemState
      ! owner is sections[].thickness (docs/m2/state-field-map.toml id
      ! "sections.thickness") -- but it MUST still be captured here: this is the
      ! only place .mat's thickness is ever read, and an earlier revision of this
      ! routine stopped at "not my field" and dropped the value outright (module
      ! header). Recorded by material id; resolved to each section below.
      mat_thickness(imat) = thickness

      loc = make_source_location(file='.mat', reader='material_set', line=283_int32, &
                                  record=jmat)
      call builder_add_material(b, mat, loc, errors)
      if (builder_failed(b)) return
    end do

    call resolve_section_thickness(errors, ctx, mat_thickness, secparts)
  end subroutine parse_mat

  ! Section -> material -> thickness (adapter-contract.md §2.4). Positional: section
  ! `igroup` is `secparts%sections(igroup)`, whose material is `ctx%group_matno(igroup)`
  ! (the same positional convention rule N4 already uses for mesh.elsets[], see
  ! yl_adapter_mesh.f90).
  !
  ! The map requires rejecting a deck where two sections share a material but
  ! disagree on thickness. Because legacy stores thickness PER MATERIAL
  ! (Material.f90:319) and this routine resolves every section through the SAME
  ! `mat_thickness` table by the SAME key, two sections sharing a material cannot
  ! actually disagree here -- the loop below still checks (comparing against the
  ! first section seen for that material), because the alternative is asserting a
  ! property of this routine's own indexing rather than of the deck, and this
  ! gate's charter is deck defects, not code proofs. On both golden decks ngroup==1,
  ! so the "second section, same material" branch below is never even reached; it
  ! exists for when the capability gate someday admits more than one section.
  subroutine resolve_section_thickness(errors, ctx, mat_thickness, secparts)
    type(problem_errors_t), intent(inout) :: errors
    type(deck_context_t), intent(in) :: ctx
    real(real64), intent(in) :: mat_thickness(:)
    type(section_parts_t), intent(inout) :: secparts

    integer(int32) :: igroup, matno, j
    integer(int32), allocatable :: seen_matno(:)
    real(real64), allocatable :: seen_thickness(:)
    integer(int32) :: n_seen
    type(source_location_t) :: loc

    allocate (seen_matno(0), seen_thickness(0))
    n_seen = 0_int32

    do igroup = 1_int32, size(ctx%group_matno)
      matno = ctx%group_matno(igroup)
      if (matno < 1_int32 .or. matno > size(mat_thickness)) then
        loc = make_source_location(file='.mat', reader='material_set', line=283_int32)
        call errors%add(make_problem_error(code=PE_INVALID_INPUT, stage=PE_STAGE_ADAPT, &
                        rule_id='A-MAT/section-material-range', object_path='sections[]', &
                        index=igroup, field='material', &
                        message='section references a material id .mat never defined', &
                        actual=itoa(matno), expected='1..'//itoa(size(mat_thickness)), &
                        source=loc))
        return
      end if

      do j = 1_int32, n_seen
        if (seen_matno(j) /= matno) cycle
        if (seen_thickness(j) /= mat_thickness(matno)) then
          loc = make_source_location(file='.mat', reader='material_set', line=319_int32)
          call errors%add(make_problem_error(code=PE_INVALID_INPUT, stage=PE_STAGE_ADAPT, &
                          rule_id='A-MAT/thickness-conflict', object_path='sections[]', &
                          index=igroup, field='thickness', &
                          message='this section''s material already resolved to a ' &
                          //'different thickness for an earlier section -- impossible ' &
                          //'from a single well-formed .mat, so something upstream ' &
                          //'(ctx%group_matno or this table) is wrong', &
                          actual=itoa_real(mat_thickness(matno)), &
                          expected=itoa_real(seen_thickness(j)), source=loc))
          return
        end if
        exit
      end do
      if (j > n_seen) then
        seen_matno = [seen_matno, matno]
        seen_thickness = [seen_thickness, mat_thickness(matno)]
        n_seen = n_seen + 1_int32
      end if

      call opt_set(secparts%sections(igroup)%thickness, mat_thickness(matno))
    end do
  end subroutine resolve_section_thickness

  ! ============================================================================
  ! .sol
  ! ============================================================================

  ! RD: SOL.PROFILE.title#1 / SOL.PROFILE.profile_control (Solver.f90:6829,:6831)
  ! Both reads are inside PROFILE's Operation=='SET' branch (Solver.f90:6820), ahead
  ! of three conditions this parser cannot see and must not act on anyway
  ! (Solver.f90:6821-6828):
  !   * restart==1 skips (iblks-1) pairs of `text` records first;
  !   * meshc==1 .or. rmesh/=0, and separately Bparameter/=0, each rewind(solveunit).
  ! restart/meshc/rmesh/Bparameter live in .man/.glb, not .sol, so this parser cannot
  ! evaluate them; and adapter-contract.md §2 forbids rewinding `unit` regardless.
  ! This routine is therefore only correct for the single-pass, no-restart case that
  ! the static-q4/1 whitelist assumes (single stage, single increment). A restart
  ! deck is a cursor-coupling gap for L2-a, not fixed here (see module header for
  ! the parallel gap already flagged for ndimn/nnode in yl_adapter_mesh.f90).
  !
  ! `b` is taken, per the shared parser shape, but never called: this routine owns
  ! only sparts%solver%profile.* (adapter-contract.md §2.2, "solver_parts_t"), never
  ! solver%linear or solver%symmetric (both .glb's), and builder_set_solver is a
  ! one-shot setter the driver alone calls once every contributing leaf is filled.
  subroutine parse_sol(unit, ctx, b, sparts, errors)
    integer, intent(in) :: unit
    type(deck_context_t), intent(in) :: ctx
    type(problem_builder_t), intent(inout) :: b
    type(solver_parts_t), intent(inout) :: sparts
    type(problem_errors_t), intent(inout) :: errors

    character(len=200) :: text, iomsg_buf
    integer(int32) :: ios, iafile, icond, ipdchk, ising
    type(source_location_t) :: loc

    if (.not. ctx%filled) then
      loc = make_source_location(file='.sol', reader='PROFILE', line=6829_int32)
      call errors%add(make_problem_error(code=PE_INTERNAL, stage=PE_STAGE_ADAPT, &
                      rule_id='A-SOL/context-not-filled', object_path='solver', &
                      message='parse_sol was called before parse_glb filled deck_context_t', &
                      source=loc))
      return
    end if

    ! RD: SOL.PROFILE.title#1 (Solver.f90:6829) -- a title line, discarded.
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    if (.not. sol_read_ok(errors, ios, iomsg_buf, 'SOL.PROFILE.title#1', 6829_int32)) return

    ! RD: SOL.PROFILE.profile_control (Solver.f90:6831)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) iafile, icond, ipdchk, ising
    if (.not. sol_read_ok(errors, ios, iomsg_buf, 'SOL.PROFILE.profile_control', &
                          6831_int32)) return

    if (iafile /= 0_int32) then
      loc = make_source_location(file='.sol', reader='PROFILE', line=6833_int32)
      call reject_dialect(errors, 'A-SOL', 'pivot-file', loc, actual=itoa(iafile))
      return
    end if

    ! Fill only this parser's leaves of the shared solver_parts_t. solver%linear and
    ! solver%symmetric are the .glb parser's (module header); writing them here
    ! would be exactly the "second writer wins silently" defect adapter-parts.f90's
    ! header warns against, even though this parser happens to know PROFILE is the
    ! active solver (it is this file's own identity, not a value read from .sol).
    call opt_set(sparts%solver%profile%pivot_file, iafile)
    call opt_set(sparts%solver%profile%condition_check, icond)
    call opt_set(sparts%solver%profile%positive_definite_check, ipdchk)
    call opt_set(sparts%solver%profile%singularity_check, ising)
  end subroutine parse_sol

  ! ============================================================================
  ! shared helpers
  ! ============================================================================

  ! Any nonzero iostat on a .mat read -- including end-of-file -- is a truncated or
  ! malformed deck: every read in parse_mat is for a record shape this whitelist
  ! slice fixes in advance, so running out of file or failing to parse a record here
  ! can never be anything but PE_INVALID_INPUT.
  logical function mat_read_ok(errors, ios, iomsg_buf, id, site, rec) result(ok)
    type(problem_errors_t), intent(inout) :: errors
    integer(int32), intent(in) :: ios
    character(len=*), intent(in) :: iomsg_buf, id
    integer(int32), intent(in) :: site
    integer(int32), intent(in), optional :: rec
    type(source_location_t) :: loc
    ok = (ios == 0_int32)
    if (ok) return
    loc = make_source_location(file='.mat', reader='material_set', line=site, record=rec)
    call errors%add(make_problem_error(code=PE_INVALID_INPUT, stage=PE_STAGE_ADAPT, &
                    rule_id='A-MAT/malformed-record', object_path='materials', index=rec, &
                    message='malformed .mat record ('//trim(id)//'): '//trim(iomsg_buf), &
                    source=loc))
  end function mat_read_ok

  logical function sol_read_ok(errors, ios, iomsg_buf, id, site) result(ok)
    type(problem_errors_t), intent(inout) :: errors
    integer(int32), intent(in) :: ios
    character(len=*), intent(in) :: iomsg_buf, id
    integer(int32), intent(in) :: site
    type(source_location_t) :: loc
    ok = (ios == 0_int32)
    if (ok) return
    loc = make_source_location(file='.sol', reader='PROFILE', line=site)
    call errors%add(make_problem_error(code=PE_INVALID_INPUT, stage=PE_STAGE_ADAPT, &
                    rule_id='A-SOL/malformed-record', object_path='solver', &
                    message='malformed .sol record ('//trim(id)//'): '//trim(iomsg_buf), &
                    source=loc))
  end function sol_read_ok

  ! Every .mat whitelist departure, through the ONE adapter-wide dialect raiser (L2-b,
  ! yl_adapter_parts). This wrapper survives it because it still carries something the
  ! raiser cannot know: every A-MAT row is read from '.mat' by 'material_set', so a
  ! call site names only the legacy line and the record ordinal. object_path, field and
  ! the wording now come from the row and are no longer arguments -- passing them is
  ! what let a call site disagree with its own declaration.
  subroutine mat_reject(errors, condition, site, actual, rec)
    type(problem_errors_t), intent(inout) :: errors
    character(len=*), intent(in) :: condition, actual
    integer(int32), intent(in) :: site
    integer(int32), intent(in), optional :: rec
    type(source_location_t) :: loc
    loc = make_source_location(file='.mat', reader='material_set', line=site, record=rec)
    call reject_dialect(errors, 'A-MAT', condition, loc, actual=actual, idx=rec)
  end subroutine mat_reject

  ! Minimal integer-to-text helper for `actual=`. Private and local, same rationale
  ! as yl_problem_errors's own itoa: no dependency pulled in for one conversion.
  pure function itoa(value) result(text)
    integer(int32), intent(in) :: value
    character(len=:), allocatable :: text
    character(len=12) :: buffer
    write (buffer, '(i0)') value
    text = trim(buffer)
  end function itoa

  ! Minimal real-to-text helper for `actual=`/`expected=` on the thickness-conflict
  ! finding. Full precision (g0), not a rounded display format: the two values being
  ! compared came from the same real64 read, so any formatting difference between
  ! them would itself be a false lead when the finding is being read back.
  pure function itoa_real(value) result(text)
    real(real64), intent(in) :: value
    character(len=:), allocatable :: text
    character(len=32) :: buffer
    write (buffer, '(g0)') value
    text = trim(buffer)
  end function itoa_real

end module yl_adapter_material
