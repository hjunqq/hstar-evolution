! yl_adapter_material -- M4-01 legacy adapter: .mat (materials) and .sol (solver
! controls), per docs/m4/adapter-contract.md §2. Neither deck touches `steps[0]`, so
! both routines keep the plain three-argument parse_<kind>(unit, b, errors) shape
! (contract §2, "不碰 steps[0] 的...沿用不带 parts 的三参形式").
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
! solver_t is a cross-file singleton -- UNRESOLVED, flagged to the team lead
!   docs/m2/state-field-map.toml puts solver.symmetric's source at .glb
!   (GLB.global_data.init_and_blocks, legacy_symbol global_var.nonsym), not at .sol.
!   yl_problem_builder's builder_set_solver is a SINGLETON setter (one call per
!   draft, like builder_step_set_load / _controls); this is exactly the class of bug
!   the 2026-09-08 contract revision fixed for steps[0] via yl_adapter_step_parts.
!   solver_t has no such aggregate. parse_sol below fills solver%linear and
!   solver%profile.* and calls builder_set_solver, leaving solver%symmetric UNSET
!   (never guessed -- see the routine). If the .glb parser (yl_adapter_model) also
!   calls builder_set_solver for solver%symmetric, the two calls collide and the
!   second is rejected outright; if it does not, solver%symmetric never gets set at
!   all. Neither outcome is this module's to fix (file ownership) or silently paper
!   over. Reported to the team lead; the likely fix mirrors step_parts_t.
module yl_adapter_material

  use iso_fortran_env, only: int32, real64, iostat_end
  use yl_problem_optional, only: opt_set
  use yl_problem_types, only: material_t, solver_t
  use yl_problem_builder, only: problem_builder_t, builder_add_material, &
                                 builder_materials_empty, builder_set_solver, builder_failed
  use yl_problem_errors, only: problem_errors_t, source_location_t, make_source_location, &
                                make_problem_error, PE_INVALID_INPUT, PE_UNSUPPORTED

  implicit none
  private

  public :: parse_mat, parse_sol

  ! L2-b has not yet landed PE_STAGE_ADAPT (adapter-contract.md §4). This literal is
  ! this module's best guess at that constant's eventual value, spelled the same way
  ! as the four stage names already in yl_problem_errors.f90. Replace with
  ! PE_STAGE_ADAPT once L2-b adds it.
  character(len=*), parameter :: STAGE_ADAPT = 'adapt'

contains

  ! ============================================================================
  ! .mat
  ! ============================================================================

  ! RD: MAT.material_set.title#1 .. MAT.material_set.elastic_extra
  ! (Material.f90:243-313). See the module header for why every switch below is
  ! checked the instant it is read, not deferred to a later stage.
  subroutine parse_mat(unit, b, errors)
    integer, intent(in) :: unit
    type(problem_builder_t), intent(inout) :: b
    type(problem_errors_t), intent(inout) :: errors

    character(len=200) :: text
    character(len=200) :: iomsg_buf
    character(len=30) :: property, name, phase, material
    integer(int32) :: ios, nscurve, nline, iline, mmats, jmat
    integer(int32) :: imat, nphase, icreep, kind_wt, jliqu
    integer(int32) :: iE_switch, iNu_switch
    real(real64) :: density, ratio, thickness, e, nu, alfa, density_w
    type(material_t) :: mat
    type(source_location_t) :: loc

    ! RD: MAT.material_set.title#1 (Material.f90:243) -- a title line, discarded.
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    if (.not. mat_read_ok(errors, ios, iomsg_buf, 'MAT.material_set.title#1', 243_int32)) return

    ! RD: MAT.material_set.curve_count (Material.f90:245)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) nscurve
    if (.not. mat_read_ok(errors, ios, iomsg_buf, 'MAT.material_set.curve_count', 245_int32)) return
    if (nscurve /= 0_int32) then
      call mat_reject(errors, 'A-MAT/curve-count', 245_int32, &
                      'property curves (nscurve/=0) read npoints/type_curve/strain_curve/' &
                      //'stress_curve records this parser cannot shape (Material.f90:250-257)', &
                      itoa(nscurve))
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

    do jmat = 1_int32, mmats

      ! RD: MAT.material_set.title#3 (Material.f90:281) -- a title line, discarded.
      read (unit, *, iostat=ios, iomsg=iomsg_buf) text
      if (.not. mat_read_ok(errors, ios, iomsg_buf, 'MAT.material_set.title#3', 281_int32, &
                            rec=jmat)) return

      ! RD: MAT.material_set.material_header (Material.f90:283)
      read (unit, *, iostat=ios, iomsg=iomsg_buf) property, name, imat
      if (.not. mat_read_ok(errors, ios, iomsg_buf, 'MAT.material_set.material_header', &
                            283_int32, rec=jmat)) return
      if (trim(property) /= 'MECHANICAL') then
        call mat_reject(errors, 'A-MAT/property', 294_int32, &
                        'property_select (Material.f90:294) has a branch per property; only ' &
                        //'MECHANICAL is whitelisted', trim(property), rec=jmat, field='kind')
        return
      end if

      ! RD: MAT.material_set.material_nphase (Material.f90:298)
      read (unit, *, iostat=ios, iomsg=iomsg_buf) nphase
      if (.not. mat_read_ok(errors, ios, iomsg_buf, 'MAT.material_set.material_nphase', &
                            298_int32, rec=jmat)) return
      if (nphase /= 1_int32) then
        call mat_reject(errors, 'A-MAT/phase-count', 298_int32, &
                        'the phase loop (Material.f90:300) reads one phase record per nphase; ' &
                        //'only a single SOLID phase is whitelisted', itoa(nphase), rec=jmat)
        return
      end if

      ! RD: MAT.material_set.material_phase (Material.f90:302)
      read (unit, *, iostat=ios, iomsg=iomsg_buf) phase
      if (.not. mat_read_ok(errors, ios, iomsg_buf, 'MAT.material_set.material_phase', &
                            302_int32, rec=jmat)) return
      if (trim(phase) /= 'SOLID') then
        call mat_reject(errors, 'A-MAT/phase', 305_int32, &
                        'phase_select (Material.f90:305) also has a FLUID branch reading ' &
                        //'different fields; only SOLID is whitelisted', trim(phase), &
                        rec=jmat, field='phase')
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
        call mat_reject(errors, 'A-MAT/creep', 357_int32, &
                        'icreep>0 reads a creep-model record shaped by icreep itself ' &
                        //'(Material.f90:357-398); not whitelisted', itoa(icreep), &
                        rec=jmat, field='creep_model')
        return
      end if
      if (kind_wt /= 0_int32) then
        call mat_reject(errors, 'A-MAT/wetting', 402_int32, &
                        'kind_wt>0 reads a wetting-deformation record (Material.f90:402-418); ' &
                        //'not whitelisted', itoa(kind_wt), rec=jmat, field='wetting_kind')
        return
      end if
      if (jliqu /= 0_int32) then
        call mat_reject(errors, 'A-MAT/liquefaction', 330_int32, &
                        'jliqu/=0 reads anti-liquefaction cyclic records (Material.f90:330-345); ' &
                        //'not whitelisted', itoa(jliqu), rec=jmat, field='liquefaction')
        return
      end if
      if (trim(name) == 'CONTACT') then
        call mat_reject(errors, 'A-MAT/contact-material', 419_int32, &
                        'name==CONTACT reads a gap/friction record (Material.f90:419-423); ' &
                        //'not whitelisted', trim(name), rec=jmat, field='name')
        return
      end if
      if (trim(name) == 'NOLINORMK') then
        call mat_reject(errors, 'A-MAT/nonlinear-normal-stiffness', 450_int32, &
                        'name==NOLINORMK reads a piecewise-normal-stiffness record ' &
                        //'(Material.f90:450-456); not whitelisted', trim(name), rec=jmat, &
                        field='name')
        return
      end if
      if (trim(material) /= 'ELASTIC_ISOTROPIC') then
        call mat_reject(errors, 'A-MAT/model', 457_int32, &
                        'material_select (Material.f90:457) has a branch per constitutive ' &
                        //'model, each with its own extra records; only ELASTIC_ISOTROPIC is ' &
                        //'whitelisted (capability row G3 material.model)', trim(material), &
                        rec=jmat, field='model')
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
      ! `thickness` (Material.f90:319) is read above but NOT stored: its ProblemState
      ! owner is sections[].thickness, not materials[] (docs/m2/state-field-map.toml
      ! id "sections.thickness" -- "resolving section -> material -> thickness ... is
      ! the bridge's job, not this map's"). Nothing in this parser owns sections[].

      loc = make_source_location(file='.mat', reader='material_set', line=283_int32, &
                                  record=jmat)
      call builder_add_material(b, mat, loc, errors)
      if (builder_failed(b)) return
    end do
  end subroutine parse_mat

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
  subroutine parse_sol(unit, b, errors)
    integer, intent(in) :: unit
    type(problem_builder_t), intent(inout) :: b
    type(problem_errors_t), intent(inout) :: errors

    character(len=200) :: text, iomsg_buf
    integer(int32) :: ios, iafile, icond, ipdchk, ising
    type(solver_t) :: sv
    type(source_location_t) :: loc

    ! RD: SOL.PROFILE.title#1 (Solver.f90:6829) -- a title line, discarded.
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    if (.not. sol_read_ok(errors, ios, iomsg_buf, 'SOL.PROFILE.title#1', 6829_int32)) return

    ! RD: SOL.PROFILE.profile_control (Solver.f90:6831)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) iafile, icond, ipdchk, ising
    if (.not. sol_read_ok(errors, ios, iomsg_buf, 'SOL.PROFILE.profile_control', &
                          6831_int32)) return

    if (iafile /= 0_int32) then
      loc = make_source_location(file='.sol', reader='PROFILE', line=6833_int32)
      call errors%add(make_problem_error(code=PE_UNSUPPORTED, stage=STAGE_ADAPT, &
                      rule_id='A-SOL/pivot-file', object_path='solver', &
                      field='profile.pivot_file', &
                      message='iafile/=0 opens a separate unformatted pivot file ' &
                      //'(Solver.f90:6833, the PARDISO/pivot-capture variant); not whitelisted', &
                      actual=itoa(iafile), source=loc))
      return
    end if

    call opt_set(sv%linear, 'PROFILE')
    call opt_set(sv%profile%pivot_file, iafile)
    call opt_set(sv%profile%condition_check, icond)
    call opt_set(sv%profile%positive_definite_check, ipdchk)
    call opt_set(sv%profile%singularity_check, ising)
    ! sv%symmetric is left UNSET here on purpose -- see the module header
    ! ("solver_t is a cross-file singleton -- UNRESOLVED").

    loc = make_source_location(file='.sol', reader='PROFILE', line=6831_int32)
    call builder_set_solver(b, sv, loc, errors)
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
    call errors%add(make_problem_error(code=PE_INVALID_INPUT, stage=STAGE_ADAPT, &
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
    call errors%add(make_problem_error(code=PE_INVALID_INPUT, stage=STAGE_ADAPT, &
                    rule_id='A-SOL/malformed-record', object_path='solver', &
                    message='malformed .sol record ('//trim(id)//'): '//trim(iomsg_buf), &
                    source=loc))
  end function sol_read_ok

  ! One place to raise a whitelist-departure finding for .mat, so every reject above
  ! carries the same object_path and the same PE_UNSUPPORTED/STAGE_ADAPT pair.
  subroutine mat_reject(errors, rule_id, site, message, actual, rec, field)
    type(problem_errors_t), intent(inout) :: errors
    character(len=*), intent(in) :: rule_id, message, actual
    integer(int32), intent(in) :: site
    integer(int32), intent(in), optional :: rec
    character(len=*), intent(in), optional :: field
    type(source_location_t) :: loc
    loc = make_source_location(file='.mat', reader='material_set', line=site, record=rec)
    call errors%add(make_problem_error(code=PE_UNSUPPORTED, stage=STAGE_ADAPT, &
                    rule_id=rule_id, object_path='materials', index=rec, field=field, &
                    message=message, actual=actual, source=loc))
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

end module yl_adapter_material
