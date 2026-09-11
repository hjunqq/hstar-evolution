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

  implicit none
  private

  public :: default_material, default_section, default_solver, default_boundary
  public :: default_controls, default_load, default_output, default_activation
  public :: default_interactions, default_load_mode, set_stress_averaging
  public :: element_kind_of, nodes_per_element, formulation_code, amplitude_code
  public :: procedure_code, solver_code, legacy_material_name, enable_output_field

contains

  !> Everything about a material except density/E/nu, which are physical and authored.
  subroutine default_material(m)
    type(material_t), intent(out) :: m
    call opt_set(m%kind, 'SOLID')          ! the whitelist has one phase kind
    call opt_set(m%phase, 'SOLID')
    call opt_set(m%model, 'ELASTIC_ISOTROPIC')
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
    call opt_set(b%record_reaction, 0_int32)
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
  subroutine set_stress_averaging(o, nsection)
    type(output_t), intent(inout) :: o
    integer, intent(in) :: nsection
    if (allocated(o%stress_averaging)) deallocate (o%stress_averaging)
    allocate (o%stress_averaging(max(nsection, 0)))
    o%stress_averaging = 0_int32
  end subroutine set_stress_averaging

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
    call opt_set(x%absorbing%type, '')     ! absorbing boundaries are M7
  end function default_interactions

  pure function default_load_mode() result(s)
    character(len=:), allocatable :: s
    s = 'LOAD'
  end function default_load_mode

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
