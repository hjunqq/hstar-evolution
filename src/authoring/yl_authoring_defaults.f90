! yl_authoring_defaults -- the contract's default table, as code.
!
! `docs/m5/authoring-contract.md` SS5 lists every ProblemState field the author does NOT
! write, with the reason it is not a physical choice. This module is that table executable,
! and the two are meant to be read side by side: a value here with no row there is a
! default nobody agreed to.
!
! THE VALUES ARE THE WHITELIST'S, NOT "SOMETHING REASONABLE"
!   Each one is what the whitelisted static slice actually requires, taken from the golden
!   decks' own records (the .glb group header at 1.glb:59 and the .mat material record) --
!   not invented. Where the whitelist admits exactly one value, that value is here; where
!   it would admit several, the field is NOT in this module and the contract requires the
!   author to write it.
!
! WHY NOT DERIVE THEM FROM THE LEGACY DECK AT RUN TIME
!   Because then the modern path would need a deck to run, which is the one thing M5 is
!   for. These are constants of the capability whitelist, and when the whitelist widens
!   they stop being constants -- at which point the corresponding contract row moves out
!   of SS5 and becomes an authored field. That is the migration, not a regression.
module yl_authoring_defaults

  use iso_fortran_env, only: int32, real64

  use yl_problem_optional, only: opt_set
  use yl_problem_types, only: material_t, section_t, solver_t, boundary_t, controls_t,       &
                              load_t, output_t, activation_t, interactions_t
  use yl_problem_deck_residue, only: deck_residue_t
  use yl_problem_existence, only: deck_existence_t

  implicit none
  private

  public :: default_material, default_section, default_solver, default_boundary
  public :: default_controls, default_load, default_output, default_activation
  public :: default_interactions, default_load_mode, set_stress_averaging
  public :: stress_averaging_code
  public :: default_residue, default_existence
  public :: element_kind_of, nodes_per_element, formulation_code, amplitude_code
  public :: procedure_code, solver_code, legacy_material_name, enable_output_field

contains

  !> Everything about a material except density/E/nu, which are physical and authored.
  subroutine default_material(m)
    type(material_t), intent(out) :: m
    ! kind is the PROPERTY family and phase is the material phase; legacy's .mat record
    ! carries both and the whitelist admits one of each.
    call opt_set(m%kind, 'MECHANICAL')
    call opt_set(m%phase, 'SOLID')
    ! props%name is legacy's .mat header word, which IS the phase word -- not the
    ! constitutive model and not the author's reference label (Fem.f90:258 tests it
    ! against 'NSTOKS'). The model comes from the authored `model` key.
    call opt_set(m%name, 'SOLID')
    call opt_set(m%creep_model, 0_int32)   ! creep is not on the whitelist
    call opt_set(m%wetting_kind, 0_int32)
    call opt_set(m%liquefaction, 0_int32)
    call opt_set(m%solid_ratio, 1.0_real64)
    call opt_set(m%thermal_expansion, 1.0e-5_real64)   ! unconsumed on a static path
  end subroutine default_material

  !> The .glb group header's non-physical columns (1.glb:59 on both golden decks).
  subroutine default_section(s)
    type(section_t), intent(out) :: s
    call opt_set(s%class, 'CO')            ! continuum; 'BM' would select a beam
    call opt_set(s%fields, 'U')            ! displacement field; gravity needs fieldid(1:1)=='U'
    call opt_set(s%special, 'ST')          ! static special-formulation switch
    call opt_set(s%algorithm, 0_int32)
    call opt_set(s%stiffness_kind, 1_int32)
    call opt_set(s%stress_recovery, 1_int32)
    call opt_set(s%layer, 1_int32)
    call opt_set(s%uplift, 0_int32)
    call opt_set(s%liquefaction, 0_int32)
    call opt_set(s%local_axes, 0.0_real64)
    ! Unit thickness is right for plane strain and becomes a PHYSICAL choice the day plane
    ! stress is whitelisted; the contract marks this row as the edge case for exactly that.
    call opt_set(s%thickness, 1.0_real64)
  end subroutine default_section

  subroutine default_solver(s)
    type(solver_t), intent(out) :: s
    ! symmetric is opt_LOGICAL: the map keeps dtype i32 because that is the legacy WIRE
    ! type, and the bridge inverts legacy's `nonsym`. Here the authoring value is the
    ! physical one -- the whitelisted solver is symmetric.
    call opt_set(s%symmetric, .true.)
    call opt_set(s%profile%pivot_file, 0_int32)
    call opt_set(s%profile%condition_check, 0_int32)
    call opt_set(s%profile%positive_definite_check, 1_int32)
    call opt_set(s%profile%singularity_check, 1_int32)
  end subroutine default_solver

  subroutine default_boundary(b)
    type(boundary_t), intent(out) :: b
    call opt_set(b%amplitude, 0_int32)     ! a prescribed value with no curve is constant
    ! prescrib%outfix: report the reaction at this constrained dof. A pure output switch
    ! (it changes no equation), and 1 on both frozen references, so recording is the
    ! default rather than silently dropping reactions the legacy path reports.
    call opt_set(b%record_reaction, 1_int32)
  end subroutine default_boundary

  subroutine default_controls(c)
    type(controls_t), intent(out) :: c
    call opt_set(c%nonlinear_type, 5_int32)      ! kresl set on the first iteration only
    call opt_set(c%steps, 1_int32)
    call opt_set(c%step_increment, 1_int32)
    call opt_set(c%time_increment, 1.0_real64)   ! static: the curve's abscissa, no more
    call opt_set(c%restart_frequency, 1_int32)
  end subroutine default_controls

  subroutine default_load(l)
    type(load_t), intent(out) :: l
    call opt_set(l%gravity%enabled, 0_int32)
  end subroutine default_load

  !> Every GiD switch off; `enable_output_field` turns on what the author asked for.
  subroutine default_output(o)
    type(output_t), intent(out) :: o
    call opt_set(o%format, 'GIDR')
    ! stress_averaging is one flag PER SECTION, so it is sized where the section count is
    ! known; default_output cannot allocate it. See set_stress_averaging below.
    call opt_set(o%frequency%fields, 1_int32)
    call opt_set(o%frequency%nodes, 1_int32)
    call opt_set(o%field%u, 0_int32);   call opt_set(o%field%v, 0_int32)
    call opt_set(o%field%a, 0_int32);   call opt_set(o%field%rot, 0_int32)
    call opt_set(o%field%s, 0_int32);   call opt_set(o%field%ms, 0_int32)
    call opt_set(o%field%f, 0_int32);   call opt_set(o%field%t, 0_int32)
    call opt_set(o%field%p, 0_int32);   call opt_set(o%field%pv, 0_int32)
    call opt_set(o%field%ep, 0_int32);  call opt_set(o%field%y, 0_int32)
    call opt_set(o%field%fc, 0_int32);  call opt_set(o%field%ns, 0_int32)
    call opt_set(o%field%ss, 0_int32);  call opt_set(o%field%mxy, 0_int32)
    call opt_set(o%field%bem, 0_int32); call opt_set(o%field%bcs, 0_int32)
    call opt_set(o%field%wh, 0_int32);  call opt_set(o%field%wv, 0_int32)
  end subroutine default_output

  !> One averaging flag per section, all off. Separate from default_output because the
  !> section count is not known until the sections are read, and an array sized by a guess
  !> is a bug waiting for the second section.
  subroutine set_stress_averaging(o, nsection, code)
    type(output_t), intent(inout) :: o
    integer, intent(in) :: nsection
    integer(int32), intent(in) :: code
    if (allocated(o%stress_averaging)) deallocate (o%stress_averaging)
    allocate (o%stress_averaging(max(nsection, 0)))
    o%stress_averaging = code
  end subroutine set_stress_averaging

  !> `average_appear` (Global.f90:1023, Output.f90:5102). It decides what the reported nodal
  !> stresses ARE, so it is a physical statement about the output and the contract requires
  !> it in writing. legacy also admits -1/-2 (the pre-2005 variants of the same two schemes);
  !> they are not whitelisted because no golden deck exercises them.
  !>
  !> On THIS slice only 0 vs non-zero is observable: the iaver==1 / iaver==2 split at
  !> Output.f90:5128-5129 sits inside `if (nnode == 8 .and. ndimn == 3)`, so on 2-D Q4
  !> 'smoothed' and 'direct' produce identical numbers. Measured, not assumed -- setting
  !> 'smoothed' leaves the frozen reference reproduced exactly, setting 'none' moves the
  !> stresses by 1.5e5 and leaves the displacements untouched. Both names are kept because
  !> they are legacy's own two schemes and they diverge the day a 3-D 8-node element is
  !> whitelisted; nothing here may be re-derived from the fact that they agree today.
  pure integer(int32) function stress_averaging_code(name) result(c)
    character(len=*), intent(in) :: name
    select case (trim(name))
    case ('none');     c = 0_int32
    case ('smoothed'); c = 1_int32
    case ('direct');   c = 2_int32
    case default;      c = 0_int32
    end select
  end function stress_averaging_code

  subroutine enable_output_field(o, name)
    type(output_t), intent(inout) :: o
    character(len=*), intent(in) :: name
    select case (trim(name))
    case ('u'); call opt_set(o%field%u, 1_int32)
    case ('s'); call opt_set(o%field%s, 1_int32)
    end select
  end subroutine enable_output_field

  !> Every section active. Construction staging is M6.7, not a choice left implicit here.
  subroutine default_activation(a, material)
    type(activation_t), intent(out) :: a
    integer(int32), intent(in) :: material
    call opt_set(a%active, 1_int32)
    call opt_set(a%material, material)
  end subroutine default_activation

  function default_interactions() result(x)
    type(interactions_t) :: x
    ! 'FIX' is legacy's own no-absorbing-boundary sentinel (global_data init); every test on
    ! type_ABC is against 'VIE' / 'MIF', so the word is a label, not a physical choice. Real
    ! absorbing boundaries are M7.
    call opt_set(x%absorbing%type, 'FIX')
  end function default_interactions

  pure function default_load_mode() result(s)
    character(len=:), allocatable :: s
    s = 'LOAD'
  end function default_load_mode

  !> The deck values ProblemState does not model, at their whitelisted values.
  !>
  !> Every one of these is a PINNED GUARD: docs/m2/M2-01-checkpoints.md SS1 lists them with
  !> the branch each one decides, and the adapter's dialect gate refuses a deck that
  !> carries anything else. So on the modern path they are constants of the whitelist,
  !> exactly as SS5 of the contract says -- not values an author was spared writing.
  !>
  !> `npoinb` is the exception in form only: it is a COUNT (the golden decks carry
  !> npoinb == npoin), so it is derived from the mesh rather than pinned.
  subroutine default_residue(r, npoin)
    type(deck_residue_t), intent(out) :: r
    integer(int32), intent(in) :: npoin
    call opt_set(r%restart, 0_int32);        call opt_set(r%relis, 0_int32)
    call opt_set(r%adina, 0_int32);          call opt_set(r%runblks, 1_int32)
    call opt_set(r%ninit, 0_int32);          call opt_set(r%nlinks, 0_int32)
    call opt_set(r%block_stab, 0_int32);     call opt_set(r%nbackf, 0_int32)
    call opt_set(r%ebody, 0_int32);          call opt_set(r%nlayer, 0_int32)
    call opt_set(r%state_change, 0_int32);   call opt_set(r%bparameter, 0_int32)
    call opt_set(r%ntrans, 0_int32)
    ! 99999 is a DISABLE SENTINEL, not a zero: stab_initialize never runs on this path.
    call opt_set(r%stab_matde, 99999_int32)
    call opt_set(r%npoinb, npoin)
    call opt_set(r%nsmat, 1_int32)           ! stiffness reformed on the first iteration only
    call opt_set(r%nplgroup, 0_int32);       call opt_set(r%nedge, 0_int32)
    call opt_set(r%edge_load_group, 0_int32); call opt_set(r%delgroup, 0_int32)
    call opt_set(r%nbeamload, 0_int32);      call opt_set(r%nplateload, 0_int32)
    call opt_set(r%ntemp_surface, 0_int32);  call opt_set(r%ntedge, 0_int32)
    call opt_set(r%ntelgroup, 0_int32);      call opt_set(r%npipe, 0_int32)
    if (allocated(r%uinitial)) deallocate (r%uinitial)
    allocate (r%uinitial(1))
    r%uinitial = 0_int32
  end subroutine default_residue

  !> The runtime state manifest's rows (ADR-0009) at their whitelisted values.
  !> Sizes come from the mesh and the sections; values are zero because every one of these
  !> is a switch the whitelist pins off. The scalars carrier default-initialises itself.
  subroutine default_existence(e, nelem, ngroup, mdofn)
    type(deck_existence_t), intent(out) :: e
    integer(int32), intent(in) :: nelem, ngroup, mdofn
    allocate (e%order_time_mdofn(max(int(mdofn), 0)));  e%order_time_mdofn = 0_int32
    allocate (e%tension_joint(max(int(nelem), 0)));     e%tension_joint = 0_int32
    allocate (e%group_order_time(2, 1, max(int(ngroup), 0))); e%group_order_time = 0_int32
    allocate (e%group_type_mass(1, max(int(ngroup), 0)));     e%group_type_mass = 0_int32
    allocate (e%modf_dis_blocks(1));                    e%modf_dis_blocks = 0_int32
    allocate (e%tlink(2, 0))
    allocate (e%equvs_process(max(int(ngroup), 0)));    e%equvs_process = 0_int32
    allocate (e%force_process(max(int(ngroup), 0)));    e%force_process = 0_int32
    ! The .glb scalars the whitelist leaves non-zero. Taken from the golden decks' own
    ! records; every other scalar is zero by the carrier's own initialisation.
    e%scalars%nmass = 1_int32
    e%scalars%nhmat = 1_int32
    e%scalars%nqmat = 1_int32
    e%scalars%nswkw = 1_int32
    e%scalars%ntsmat = 999_int32
    e%scalars%nthmat = 999_int32
    e%scalars%beeta1 = 0.5_real64
    e%scalars%beeta2 = 0.25_real64
    e%scalars%theta1 = 1.0_real64
  end subroutine default_existence

  ! --- the authoring vocabulary -> the legacy codes the solver reads ---------------
  ! These are TRANSLATIONS, not defaults: the author writes the physical choice in CAE
  ! words and the solver stores it in its own. Keeping them here rather than inline keeps
  ! the mapping module free of magic strings.

  pure integer(int32) function element_kind_of(element) result(k)
    character(len=*), intent(in) :: element
    select case (trim(element))
    case ('Q4'); k = 5_int32
    case default; k = 0_int32
    end select
  end function element_kind_of

  pure integer(int32) function nodes_per_element(element) result(n)
    character(len=*), intent(in) :: element
    select case (trim(element))
    case ('Q4'); n = 4_int32
    case default; n = 0_int32
    end select
  end function nodes_per_element

  pure function formulation_code(formulation) result(s)
    character(len=*), intent(in) :: formulation
    character(len=:), allocatable :: s
    select case (trim(formulation))
    case ('plane_strain'); s = 'PE'
    case default; s = ''
    end select
  end function formulation_code

  pure function amplitude_code(kind) result(s)
    character(len=*), intent(in) :: kind
    character(len=:), allocatable :: s
    select case (trim(kind))
    case ('linear'); s = 'LINEAR'
    case default; s = ''
    end select
  end function amplitude_code

  pure function procedure_code(kind) result(s)
    character(len=*), intent(in) :: kind
    character(len=:), allocatable :: s
    select case (trim(kind))
    case ('static'); s = 'Q'
    case default; s = ''
    end select
  end function procedure_code

  pure function solver_code(kind) result(s)
    character(len=*), intent(in) :: kind
    character(len=:), allocatable :: s
    select case (trim(kind))
    case ('profile'); s = 'PROFILE'
    case default; s = ''
    end select
  end function solver_code

  pure function legacy_material_name(model) result(s)
    character(len=*), intent(in) :: model
    character(len=:), allocatable :: s
    select case (trim(model))
    case ('elastic_isotropic'); s = 'ELASTIC_ISOTROPIC'
    case default; s = ''
    end select
  end function legacy_material_name

end module yl_authoring_defaults
