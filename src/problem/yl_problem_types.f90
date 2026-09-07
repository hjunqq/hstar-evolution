! yl_problem_types -- the M3 ProblemState derived types.
!
! Scope (see .ccg/tasks/m3-01-problemstate-types/plan.md and requirements.md)
!   Types ONLY. No parse, no normalize, no validate, no finalize, no commit and no
!   RuntimeState: those are M3-02 and M3-03. Nothing here reads a legacy file format
!   or touches a solver work array (src/problem/README.md).
!
! Where the field names come from
!   Every component below is derived MECHANICALLY from the `owner` column of
!   docs/m2/state-field-map.toml, never from the `id` column, which still carries the
!   Fortran spellings (`gid_u`, `icreep`, `type_nalgo`, `nonsym`). The 98 exported rows
!   -- `compare.rule != "ignore"` and `owner` starting with `ProblemState.` -- are in
!   one-to-one correspondence with the 98 mapped leaf components declared here, and
!   `python3 tools/yl_problem_check.py check` enforces that correspondence in both
!   directions, fail-closed. Two components carry no map row and therefore carry an
!   `@m5-only` marker with a reason; every other component must trace to exactly one
!   map field id.
!
!   Because the names are mechanical, this module deliberately contains NO Fortran slot
!   name: no npoin, nelem, ndofix, mdofn, matno, nonsym, noutf. The check tool builds a
!   deny list out of the map's own `legacy_symbol` leaf names and fails on any leak.
!
! Absence discipline (ADR-0002)
!   `unset`, an explicit zero and an empty collection are three distinct states and no
!   value is ever overloaded as a second-meaning sentinel:
!     * authoring scalars are the opt_int / opt_real / opt_text wrappers of
!       yl_problem_optional -- default-initialised to unset, payload private, read only
!       through opt_get / opt_value_or;
!     * collections and per-entity vectors are `allocatable`, where NOT allocated means
!       unset and allocated with size 0 means explicitly empty;
!     * no component carries an initializer, a `pointer`, or a declared extent. Extents
!       are derived at finalize, so a count is never stored as a field.
!
! Shape convention
!   A row whose map `shape` carries one more dimension than the owner path has `[]`
!   collection levels becomes a deferred-shape rank-1 array on the entity that owns it
!   (mesh.nodes[].xyz over the spatial dimensions, mesh.elements[].nodes over the element
!   connectivity, controls.tolerance_dof over the degrees of freedom). Everything else is
!   a scalar of the owning entity. Ragged legacy arrays become one allocatable per
!   collection entry, not one flat array with a stored offset table.
module yl_problem_types

  use iso_fortran_env, only: int32, real64
  use yl_problem_optional, only: opt_int, opt_real, opt_text, opt_logical

  implicit none
  private

  ! Default private; every exported entity carries an explicit `public` attribute on its
  ! own `type, public ::` header, so this module has exactly one place per name.

  ! --- case -------------------------------------------------------------------
  ! ProblemState.case (2 components: 1 mapped + 1 M5-only)

  type, public :: case_t
    type(opt_text) :: name
    type(opt_text) :: units   !@m5-only: ADR-0003 mandates an explicit SI unit declaration that no legacy record carries
  end type case_t

  ! --- mesh -------------------------------------------------------------------
  ! ProblemState.mesh (10 mapped components across 5 types)

  type, public :: node_t
    type(opt_int) :: id
    real(real64), allocatable :: xyz(:)
  end type node_t

  type, public :: element_t
    type(opt_int) :: id
    type(opt_int) :: kind
    type(opt_int) :: material
    type(opt_int) :: elset
    integer(int32), allocatable :: nodes(:)
  end type element_t

  ! One ordered element list per element set; the set key is the section name.
  type, public :: elset_t
    integer(int32), allocatable :: elements(:)
  end type elset_t

  ! One ordered node list per node set; the set key is the boundary name.
  type, public :: nset_t
    integer(int32), allocatable :: nodes(:)
  end type nset_t

  type, public :: mesh_t
    type(opt_int) :: dimension
    type(node_t), allocatable :: nodes(:)
    type(element_t), allocatable :: elements(:)
    type(elset_t), allocatable :: elsets(:)
    type(nset_t), allocatable :: nsets(:)
  end type mesh_t

  ! --- materials --------------------------------------------------------------
  ! ProblemState.materials[] (13 mapped components)

  type, public :: material_t
    type(opt_int) :: id
    type(opt_text) :: name
    type(opt_text) :: kind
    type(opt_text) :: phase
    type(opt_text) :: model
    type(opt_real) :: E                    ! Pa
    type(opt_real) :: nu                   ! 1
    type(opt_real) :: density              ! kg/m3
    type(opt_real) :: thermal_expansion    ! 1/K
    type(opt_real) :: solid_ratio          ! 1
    type(opt_int) :: creep_model
    type(opt_int) :: liquefaction
    type(opt_int) :: wetting_kind
  end type material_t

  ! --- sections ---------------------------------------------------------------
  ! ProblemState.sections[] (17 mapped components). A section holds the FORMULATION and
  ! the material reference only; the element membership lives in mesh.elsets[] and the
  ! constitutive parameters live in materials[]. `material` is the effective material
  ! after the step activation override; `material_header` is the value as read from the
  ! group header and exists only so the bridge can re-emit that record.

  type, public :: section_t
    type(opt_text) :: name
    type(opt_text) :: element
    type(opt_int) :: element_kind
    type(opt_text) :: class
    type(opt_text) :: fields
    type(opt_text) :: formulation
    type(opt_text) :: special
    type(opt_int) :: material
    type(opt_int) :: material_header
    type(opt_int) :: algorithm
    type(opt_int) :: stiffness_kind
    type(opt_int) :: stress_recovery
    type(opt_int) :: layer
    type(opt_int) :: liquefaction
    type(opt_int) :: uplift
    type(opt_real) :: local_axes           ! 1
    type(opt_real) :: thickness            ! m
  end type section_t

  ! --- amplitudes -------------------------------------------------------------
  ! ProblemState.amplitudes[] (3 mapped components + 1 M5-only)

  type, public :: amplitude_point_t
    type(opt_real) :: time                 ! s
    type(opt_real) :: value                ! 1
  end type amplitude_point_t

  type, public :: amplitude_t
    type(opt_text) :: name   !@m5-only: seven map rows index by this amplitude key but the key is never exported as a value
    type(opt_text) :: type
    type(amplitude_point_t), allocatable :: points(:)
  end type amplitude_t

  ! --- interactions -----------------------------------------------------------
  ! ProblemState.interactions (1 mapped component). Placeholder: on the static_2d path
  ! the absorbing boundary is a guard string only, with no interaction semantics behind
  ! it. The object exists so ADR-0003's top-level shape is complete.

  type, public :: absorbing_t
    type(opt_text) :: type
  end type absorbing_t

  type, public :: interactions_t
    type(absorbing_t) :: absorbing
  end type interactions_t

  ! --- solver -----------------------------------------------------------------
  ! ProblemState.solver (6 mapped components)

  type, public :: profile_t
    type(opt_int) :: singularity_check
    type(opt_int) :: condition_check
    type(opt_int) :: positive_definite_check
    type(opt_int) :: pivot_file
  end type profile_t

  type, public :: solver_t
    type(opt_text) :: linear
    ! Reads the legacy `nonsym` slot (a 0/1 flag, Solver.f90:7240) whose sense is
    ! inverted; the inversion is the bridge's job. The map keeps dtype i32 because
    ! that is the legacy WIRE type driving the state dump and the frozen baselines.
    type(opt_logical) :: symmetric  !@repr: bool from i32; legacy nonsym is a 0/1 flag with inverted sense, the bridge converts
    type(profile_t) :: profile
  end type solver_t

  ! --- steps ------------------------------------------------------------------
  ! ProblemState.steps[0] (47 mapped components across 8 types). Authoring `steps[0]` is
  ! Fortran `steps(1)`; the collection is allocatable so "no steps declared" and "an
  ! empty step list" stay distinguishable.

  type, public :: activation_t
    type(opt_int) :: material
    type(opt_int) :: active
  end type activation_t

  ! One prescribed record: set, node set, degree of freedom, value and amplitude
  ! reference. Values vary per record, so a single scalar per set would lose them.
  type, public :: boundary_t
    type(opt_int) :: name
    type(opt_int) :: nset
    type(opt_int) :: dof
    type(opt_real) :: value                ! m
    type(opt_int) :: amplitude
    type(opt_int) :: record_reaction
  end type boundary_t

  type, public :: controls_t
    type(opt_int) :: nonlinear_type
    type(opt_int) :: increments
    type(opt_int) :: max_iterations
    type(opt_int) :: steps
    type(opt_int) :: step_increment
    type(opt_int) :: restart_frequency
    type(opt_real) :: time_increment       ! s
    type(opt_real) :: tolerance_force      ! N
    real(real64), allocatable :: tolerance_dof(:)   ! m, one per degree of freedom
  end type controls_t

  type, public :: gravity_t
    type(opt_int) :: enabled
    type(opt_real) :: magnitude            ! m/s2
    real(real64), allocatable :: direction(:)       ! 1, one per spatial dimension
    integer(int32), allocatable :: amplitude(:)     ! id, one amplitude reference per section
  end type gravity_t

  type, public :: load_t
    type(gravity_t) :: gravity
  end type load_t

  ! Output request selectors, not results: each is an integer request level, so a
  ! logical would lose the levels the legacy writer supports.
  type, public :: output_field_t
    type(opt_int) :: u
    type(opt_int) :: v
    type(opt_int) :: a
    type(opt_int) :: s
    type(opt_int) :: ms
    type(opt_int) :: f
    type(opt_int) :: rot
    type(opt_int) :: T
    type(opt_int) :: P
    type(opt_int) :: Pv
    type(opt_int) :: ep
    type(opt_int) :: Y
    type(opt_int) :: FC
    type(opt_int) :: Ns
    type(opt_int) :: Ss
    type(opt_int) :: Mxy
    type(opt_int) :: bem
    type(opt_int) :: wh
    type(opt_int) :: wv
    type(opt_int) :: bcs
  end type output_field_t

  ! Two independent cadences read from one record; they never shared a field.
  type, public :: frequency_t
    type(opt_int) :: nodes
    type(opt_int) :: fields
  end type frequency_t

  type, public :: output_t
    type(opt_text) :: format
    type(output_field_t) :: field
    type(frequency_t) :: frequency
    integer(int32), allocatable :: stress_averaging(:)   ! 1, one per section
  end type output_t

  type, public :: step_t
    type(opt_text) :: procedure
    type(opt_text) :: load_mode
    type(controls_t) :: controls
    type(boundary_t), allocatable :: boundary(:)
    type(activation_t), allocatable :: activation(:)
    type(load_t) :: load
    type(output_t) :: output
  end type step_t

  ! --- root -------------------------------------------------------------------
  ! ADR-0003 top-level shape: case / mesh / materials / sections / amplitudes /
  ! interactions / steps[] / solver. All counts are derived, never stored.

  type, public :: problem_state_t
    type(case_t) :: case
    type(mesh_t) :: mesh
    type(material_t), allocatable :: materials(:)
    type(section_t), allocatable :: sections(:)
    type(amplitude_t), allocatable :: amplitudes(:)
    type(interactions_t) :: interactions
    type(step_t), allocatable :: steps(:)
    type(solver_t) :: solver
  end type problem_state_t

end module yl_problem_types
