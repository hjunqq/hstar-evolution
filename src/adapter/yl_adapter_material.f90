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
    character(len=20) :: criteria
    integer(int32) :: ios, nscurve, nline, iline, mmats, jmat
    integer(int32) :: imat, nphase, icreep, kind_wt, jliqu
    integer(int32) :: iE_switch, iNu_switch
    integer(int32) :: csigma0, cfrict, cdilan
    real(real64) :: density, ratio, thickness, e, nu, alfa, density_w
    real(real64) :: sigma0, hardening, frict_angle, dilan_angle
    character(len=20) :: dc_law
    real(real64) :: cc(8)          ! A B C D Fc Ct Gf h -- see read_concrete
    integer(int32) :: cc_icr
    real(real64) :: dc(12)   ! cohes phi K n Rf Nur Kur P0 Pa Kb m dphi -- see read_duncanchang
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
      ! material_select (Material.f90:457): one branch per constitutive model, each with
      ! its own extra records. ELASTIC_ISOTROPIC reads nothing more, which is the only
      ! reason the static slice could ignore this select entirely.
      if (trim(material) /= 'ELASTIC_ISOTROPIC' .and. trim(material) /= 'CLASSICALEP'        &
          .and. trim(material) /= 'DUNCANCHANG' .and. trim(material) /= 'CONCRETE') then
        call mat_reject(errors, 'model', 457_int32, trim(material), rec=jmat)
        return
      end if
      if (trim(material) == 'CLASSICALEP') then
        call read_classicalep(unit, jmat, criteria, sigma0, hardening, frict_angle,           &
                              dilan_angle, csigma0, cfrict, cdilan, errors)
        if (errors%any()) return
      end if
      if (trim(material) == 'DUNCANCHANG') then
        call read_duncanchang(unit, jmat, ctx, dc_law, dc, errors)
        if (errors%any()) return
      end if
      if (trim(material) == 'CONCRETE') then
        call read_concrete(unit, jmat, cc, cc_icr, errors)
        if (errors%any()) return
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
      if (trim(material) == 'CLASSICALEP') then
        ! Only the fields the criterion actually read. `criteria(1:2) == 'MC'` gates two
        ! of the four records in legacy, so leaving the others UNSET is the truthful
        ! shape: opt_ absence says "this criterion has no such parameter", which 0.0
        ! would not (0 degrees of friction is a real material).
        call opt_set(mat%plasticity%criterion, trim(criteria))
        call opt_set(mat%plasticity%yield_stress, sigma0)
        call opt_set(mat%plasticity%hardening_modulus, hardening)
        call opt_set(mat%plasticity%friction_angle, frict_angle)
        call opt_set(mat%plasticity%dilation_angle, dilan_angle)
        call opt_set(mat%plasticity%yield_stress_curve, csigma0)
        call opt_set(mat%plasticity%friction_angle_curve, cfrict)
        call opt_set(mat%plasticity%dilation_angle_curve, cdilan)
      end if
      if (trim(material) == 'DUNCANCHANG') then
        ! Positional, in legacy's own read order, so the mapping stays checkable against
        ! Material.f90:504-513 and 529-531 line by line. `dc` is documented at its
        ! declaration and filled in exactly one place.
        call opt_set(mat%duncan_chang%bulk_modulus_law, trim(dc_law))
        call opt_set(mat%duncan_chang%cohesion,                dc(1))
        call opt_set(mat%duncan_chang%friction_angle,          dc(2))
        call opt_set(mat%duncan_chang%modulus_number,          dc(3))
        call opt_set(mat%duncan_chang%modulus_exponent,        dc(4))
        call opt_set(mat%duncan_chang%failure_ratio,           dc(5))
        call opt_set(mat%duncan_chang%unload_modulus_exponent, dc(6))
        call opt_set(mat%duncan_chang%unload_modulus_number,   dc(7))
        call opt_set(mat%duncan_chang%min_confining_pressure,  dc(8))
        call opt_set(mat%duncan_chang%reference_pressure,      dc(9))
        call opt_set(mat%duncan_chang%bulk_modulus_number,     dc(10))
        call opt_set(mat%duncan_chang%bulk_modulus_exponent,   dc(11))
        call opt_set(mat%duncan_chang%friction_angle_reduction, dc(12))
      end if
      if (trim(material) == 'CONCRETE') then
        ! Positional, in legacy's own read order, so the mapping stays checkable against
        ! Material.f90:666-674 line by line.
        call opt_set(mat%concrete%dev_stress_quadratic,  cc(1))
        call opt_set(mat%concrete%dev_stress_linear,     cc(2))
        call opt_set(mat%concrete%principal_stress,      cc(3))
        call opt_set(mat%concrete%mean_stress,           cc(4))
        call opt_set(mat%concrete%compressive_strength,  cc(5))
        call opt_set(mat%concrete%tensile_ratio,         cc(6))
        call opt_set(mat%concrete%fracture_energy,       cc(7))
        call opt_set(mat%concrete%characteristic_length, cc(8))
        call opt_set(mat%concrete%crack_model,           cc_icr)
      end if
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

  !> The CLASSICALEP branch of material_select (Material.f90:618-654).
  !>
  !> Four records for the MC criterion, two of them gated on the criterion itself, which is
  !> why this cannot be a flat list of reads: the cursor position after this routine depends
  !> on what the FIRST record said. Getting that wrong desynchronises every read after it in
  !> the file rather than producing a wrong number, so the criterion whitelist is checked
  !> between the first record and the second, not afterwards.
  !>
  !> Only `MC` is whitelisted. legacy also has TC / VM / DP / MCC / DPC / MCJOINT; DP shares
  !> MC's record shape, the other four do not, and none of them has a real deck here.
  subroutine read_classicalep(unit, jmat, criteria, sigma0, hardening, frict_angle,          &
                              dilan_angle, csigma0, cfrict, cdilan, errors)
    integer, intent(in) :: unit
    integer(int32), intent(in) :: jmat
    character(len=*), intent(out) :: criteria
    real(real64), intent(out) :: sigma0, hardening, frict_angle, dilan_angle
    integer(int32), intent(out) :: csigma0, cfrict, cdilan
    type(problem_errors_t), intent(inout) :: errors
    character(len=200) :: iomsg_buf
    integer(int32) :: ios

    ! RD: MAT.material_set.classicalep_criteria (Material.f90:620)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) criteria, sigma0, hardening
    if (.not. mat_read_ok(errors, ios, iomsg_buf, 'MAT.material_set.classicalep_criteria',   &
                          620_int32, rec=jmat)) return
    if (trim(criteria) /= 'MC') then
      call mat_reject(errors, 'plasticity-criterion', 620_int32, trim(criteria), rec=jmat)
      return
    end if

    ! RD: MAT.material_set.classicalep_angles (Material.f90:625) -- MC and DP only.
    read (unit, *, iostat=ios, iomsg=iomsg_buf) frict_angle, dilan_angle
    if (.not. mat_read_ok(errors, ios, iomsg_buf, 'MAT.material_set.classicalep_angles',     &
                          625_int32, rec=jmat)) return

    ! RD: MAT.material_set.classicalep_csigma0 (Material.f90:645)
    ! A CURVE INDEX. legacy declares it integer(ink) and the deck writes `0.0`; ifx
    ! list-directed read accepts that into an integer as 0 -- measured, not assumed -- and
    ! reading it as an integer here is what keeps this parser byte-compatible with legacy's.
    read (unit, *, iostat=ios, iomsg=iomsg_buf) csigma0
    if (.not. mat_read_ok(errors, ios, iomsg_buf, 'MAT.material_set.classicalep_csigma0',    &
                          645_int32, rec=jmat)) return

    ! RD: MAT.material_set.classicalep_angle_curves (Material.f90:647) -- MC and DP only.
    read (unit, *, iostat=ios, iomsg=iomsg_buf) cfrict, cdilan
    if (.not. mat_read_ok(errors, ios, iomsg_buf,                                            &
                          'MAT.material_set.classicalep_angle_curves', 647_int32,            &
                          rec=jmat)) return

    if (csigma0 /= 0_int32 .or. cfrict /= 0_int32 .or. cdilan /= 0_int32) then
      call mat_reject(errors, 'plasticity-curves', 645_int32,                                &
                      itoa(csigma0)//','//itoa(cfrict)//','//itoa(cdilan), rec=jmat)
      return
    end if
  end subroutine read_classicalep

  !> The CONCRETE branch of material_select (Material.f90:664-674).
  !>
  !> One record of nine values. The ninth, `icr`, is a SELECTOR and decides what legacy
  !> does next, which is why it is checked here rather than afterwards:
  !>
  !>   icr == 2         reads a FURTHER record (ft0/eft/at/bt/alfat, Material.f90:700)
  !>   icr in {3,5,6}   reads nothing more, and instead DERIVES bb and et0 (:684-692)
  !>   other            neither
  !>
  !> Only 6 is whitelisted -- the one a real deck exercises. Admitting 3 as well would be
  !> a claim with no deck behind it: rcbeam uses 3, but rcbeam is M9's and suspended.
  !> Getting the branch wrong would not produce a wrong number, it would desynchronise the
  !> file, which is the same reason the DUNCANCHANG bulk law is checked between records.
  subroutine read_concrete(unit, jmat, cc, icr, errors)
    integer, intent(in) :: unit
    integer(int32), intent(in) :: jmat
    real(real64), intent(out) :: cc(8)
    integer(int32), intent(out) :: icr
    type(problem_errors_t), intent(inout) :: errors
    character(len=200) :: iomsg_buf
    integer(int32) :: ios

    cc = 0.0_real64
    ! RD: MAT.material_set.concrete (Material.f90:666)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) cc(1), cc(2), cc(3), cc(4), cc(5), cc(6),    &
                                                 cc(7), cc(8), icr
    if (.not. mat_read_ok(errors, ios, iomsg_buf, 'MAT.material_set.concrete',               &
                          666_int32, rec=jmat)) return
    if (icr /= 6_int32) then
      call mat_reject(errors, 'concrete-crack-model', 666_int32, itoa(icr), rec=jmat)
      return
    end if
  end subroutine read_concrete

  !> The DUNCANCHANG branch of material_select (Material.f90:501-543).
  !>
  !> Two records here, and like read_classicalep the SECOND one's shape depends on what
  !> the first said -- `model` selects between an EV/CR trio (G/F/Vtf) and an EB trio
  !> (Kb/m/dphi). Getting that wrong desynchronises every read after it in the file, so
  !> the law is whitelisted BETWEEN the two records, not afterwards.
  !>
  !> Two further records legacy can read in this branch are refused elsewhere rather than
  !> here, and both refusals are load-bearing for the cursor being where this routine
  !> leaves it:
  !>   Material.f90:515-520  k1/k2/nd/lamdaMax, read when type_problem == 'F'. Checked
  !>                         here against the .glb value the context carries, because it
  !>                         is a RECORD this routine would otherwise walk past.
  !>   Material.f90:539-542  phi_s/k_s, read when kind_wt > 0. The common-record gate
  !>                         above has already refused a non-zero kind_wt for every model,
  !>                         so that record cannot be present; re-checked by assertion
  !>                         rather than re-read.
  subroutine read_duncanchang(unit, jmat, ctx, law, dc, errors)
    integer, intent(in) :: unit
    integer(int32), intent(in) :: jmat
    type(deck_context_t), intent(in) :: ctx
    character(len=*), intent(out) :: law
    real(real64), intent(out) :: dc(12)
    type(problem_errors_t), intent(inout) :: errors
    character(len=200) :: iomsg_buf
    integer(int32) :: ios

    dc = 0.0_real64

    ! RD: MAT.material_set.duncanchang (Material.f90:504) -- model + nine numbers, in
    ! legacy's order: cohes phi K n Rf Nur Kur P0 Pa.
    read (unit, *, iostat=ios, iomsg=iomsg_buf) law, dc(1), dc(2), dc(3), dc(4), dc(5),      &
                                                 dc(6), dc(7), dc(8), dc(9)
    if (.not. mat_read_ok(errors, ios, iomsg_buf, 'MAT.material_set.duncanchang',            &
                          504_int32, rec=jmat)) return

    ! Material.f90:515 reads a further record when type_problem is 'F'. This build's decks
    ! are 'Q'; refusing by name here keeps the refusal next to the record it is about.
    if (trim(ctx%type_problem) == 'F') then
      call mat_reject(errors, 'duncanchang-f-problem', 515_int32, trim(ctx%type_problem),    &
                      rec=jmat)
      return
    end if

    if (trim(law) /= 'EB') then
      call mat_reject(errors, 'duncanchang-bulk-law', 522_int32, trim(law), rec=jmat)
      return
    end if

    ! RD: MAT.material_set.duncanchang_eb (Material.f90:529) -- Kb, m, dphi.
    read (unit, *, iostat=ios, iomsg=iomsg_buf) dc(10), dc(11), dc(12)
    if (.not. mat_read_ok(errors, ios, iomsg_buf, 'MAT.material_set.duncanchang_eb',         &
                          529_int32, rec=jmat)) return
  end subroutine read_duncanchang

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

    ! WHICH solver's records this file holds is decided by `.glb`, not by `.sol`: legacy
    ! branches on `type_solver` (Solver.f90:7777) and the two shapes have nothing in common
    ! -- PROFILE reads one four-integer record, PARDISO reads two records with a title
    ! before each. Reading the wrong shape does not give wrong numbers, it desynchronises
    ! the file, which is why the branch is taken from the context rather than guessed from
    ! the content.
    if (trim(ctx%type_solver) == 'PARDISO') then
      call parse_sol_pardiso(unit, sparts, errors)
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

  !> The PARDISO arm of `.sol` (Solver.f90:7788-7794).
  !>
  !> Four records: a title, `mtype/ncpu/msglvl`, a title, `isdefault`. `isdefault` is a
  !> CAPABILITY SWITCH, not a value: non-zero makes legacy read a further record of eight
  !> iparm tuning numbers (Solver.f90:7797-7799) that this build has nowhere to put. It is
  !> refused by name rather than walked past -- the same rule as the DUNCANCHANG bulk law,
  !> and for the same reason: a wrong guess about a conditional record desynchronises
  !> every read after it instead of producing a visibly wrong number.
  subroutine parse_sol_pardiso(unit, sparts, errors)
    integer, intent(in) :: unit
    type(solver_parts_t), intent(inout) :: sparts
    type(problem_errors_t), intent(inout) :: errors
    character(len=200) :: text, iomsg_buf
    integer(int32) :: ios, mtype, ncpu, msglvl, isdefault
    type(source_location_t) :: loc

    ! RD: SOL.PARDISO.title#1 (Solver.f90:7788) -- a title line, discarded.
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    if (.not. sol_read_ok(errors, ios, iomsg_buf, 'SOL.PARDISO.title#1', 7788_int32)) return

    ! RD: SOL.PARDISO.control (Solver.f90:7790)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) mtype, ncpu, msglvl
    if (.not. sol_read_ok(errors, ios, iomsg_buf, 'SOL.PARDISO.control', 7790_int32)) return

    ! RD: SOL.PARDISO.title#2 (Solver.f90:7792) -- a title line, discarded.
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    if (.not. sol_read_ok(errors, ios, iomsg_buf, 'SOL.PARDISO.title#2', 7792_int32)) return

    ! RD: SOL.PARDISO.isdefault (Solver.f90:7794)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) isdefault
    if (.not. sol_read_ok(errors, ios, iomsg_buf, 'SOL.PARDISO.isdefault', 7794_int32)) return
    if (isdefault /= 0_int32) then
      loc = make_source_location(file='.sol', reader='MAIN_PARDISO', line=7797_int32)
      call reject_dialect(errors, 'A-SOL', 'pardiso-iparm-tuning', loc, actual=itoa(isdefault))
      return
    end if

    call opt_set(sparts%solver%pardiso%matrix_type, mtype)
    call opt_set(sparts%solver%pardiso%threads, ncpu)
    call opt_set(sparts%solver%pardiso%message_level, msglvl)
  end subroutine parse_sol_pardiso

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
