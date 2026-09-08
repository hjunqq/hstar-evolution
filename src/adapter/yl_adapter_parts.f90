! yl_adapter_parts -- the adapter's cross-file scaffolding.
!
! Three types, one purpose: the legacy deck splits across nine files objects that
! ProblemState keeps whole, so something has to carry a fact or a fragment from the
! file that supplies it to the file that needs it.
!
!   deck_context_t   READ  facts established by `.glb` that later parsers need in order
!                          to size a read or take a branch. Filled by parse_glb only.
!   step_parts_t     WRITE fragments of `steps[0]`, from four files.
!   solver_parts_t   WRITE fragments of `solver`, from two files.
!
! WHY THIS TYPE EXISTS
!   `ProblemState.steps[0]` is fed by four different deck files. Counted from
!   docs/m2/state-field-map.toml: `.glb` supplies 28 of its fields, `.man` 10,
!   `.pre` 6 and `.loa` 3. Worse, two of its aggregate components are themselves
!   split across files:
!
!     load_t      .gravity.enabled                  <- .glb (GLB.global_data.material_class_counts)
!                 .gravity.magnitude/direction      <- .loa (LOA.external_load_2.gravity)
!                 .gravity.amplitude                <- .loa (LOA.external_load_2.gravity_curves)
!     controls_t  .nonlinear_type                   <- .glb (GLB.global_data.problem_type)
!                 the other eight                   <- .man (MAN.STATIC_U.*)
!
!   `yl_problem_builder`'s step setters are SINGLETON: `builder_step_set_load` and
!   `builder_step_set_controls` may each be called once per step, and a second call
!   is rejected as `builder.duplicate_singleton`. That is deliberate and correct --
!   it is what stops one writer silently overwriting another's value. So no parser
!   can set a partial `load_t` and let a later parser complete it, and threading a
!   shared `step_builder_t` through the parsers would not help: the second setter
!   call is rejected no matter who makes it.
!
!   Hence this type. Parsers never call a step builder routine at all. Each fills
!   only the leaves it owns in a shared `step_parts_t`, and the sequencing driver
!   performs every `builder_step_*` call exactly once, at the end, from the
!   assembled whole. The builder's singleton discipline survives intact and is
!   still doing its job -- it now guards the driver's single pass rather than
!   being worked around.
!
! LEAF OWNERSHIP -- who fills what
!   One leaf, one writer. This table is the contract; a parser writing a leaf it
!   does not own is a defect even if the value happens to be right, because the
!   second writer's value would win silently and neither author would know.
!
!     procedure_        .glb     load_mode        .glb
!     activation(:)     .glb
!     output%format, output%field, output%stress_averaging   .glb
!     output%frequency%nodes, output%frequency%fields        .man
!         ^ corrected 2026-09-08: the first draft of this table attributed all of
!           `output` to .glb. The map sources steps0.output.frequency.nodes/fields to
!           MAN.STATIC_U.increment_control. Caught by the .man parser's author while
!           following the map instead of this comment -- which is the right order of
!           precedence, and the reason the map is the authority and this is a summary.
!     controls%nonlinear_type          .glb
!     controls%(the other eight)       .man
!     load%gravity%enabled             .glb
!     load%gravity%magnitude/direction/amplitude   .loa
!     boundary(:)       .pre
!
! WHAT THIS TYPE IS NOT
!   It is not part of `ProblemState` and never will be. It is adapter scaffolding
!   with the lifetime of one parse, and it exists only because the deck splits an
!   object the model keeps whole. A modern input format (M5) authors `steps[0]` in
!   one place and needs nothing like it.
module yl_adapter_parts

  use iso_fortran_env, only: int32
  use yl_problem_optional, only: opt_text
  use yl_problem_types, only: controls_t, load_t, output_t, boundary_t, activation_t,          &
                              solver_t, profile_t

  implicit none
  private

  public :: step_parts_t, step_parts_reset
  public :: solver_parts_t, solver_parts_reset
  public :: deck_context_t, deck_context_reset
  public :: LEN_TYPE_ABC, TYPE_ABC_MIF

  type :: step_parts_t
    ! Scalars and aggregates, filled leaf by leaf per the ownership table above.
    type(opt_text) :: procedure_
    type(opt_text) :: load_mode
    type(controls_t) :: controls
    type(load_t) :: load
    type(output_t) :: output
    ! Collections. Unallocated means the owning parser never ran; allocated with
    ! size 0 means it ran and found none -- the same three-state reading every
    ! collection carries in this repository (ADR-0002).
    type(boundary_t), allocatable :: boundary(:)
    type(activation_t), allocatable :: activation(:)
  end type step_parts_t

  !> Facts `.glb` establishes that later parsers need. READ-ONLY for everyone except
  !> `parse_glb`, which fills it.
  !>
  !> WHY: `.loa` sizes its gravity records by `ndimn` and `ngroup`; `.pre` chooses
  !> between an 8-field FIX header and a 9-field MIF header on `type_abc`, and has two
  !> further branches on `nbackdt` and `ntrans`; `.cor`/`.ele` need `ndimn` and the
  !> element kind to know a record's shape at all. Every one of those is read from
  !> `.glb` by a different module. Without this record the later parsers must GUESS,
  !> and the failure mode is silent: a wrong `ndimn` misaligns every subsequent read,
  !> and a MIF deck parsed as FIX produces no I/O error at all -- it just reads the
  !> wrong fields. That is why these travel as data rather than as assumptions.
  !> Legacy's own width for `type_abc` (Global.f90:99). Kept identical so a value read
  !> from the deck cannot be silently truncated on its way into this record.
  integer, parameter :: LEN_TYPE_ABC = 50
  !> The ONE value that changes the prescribed-set header's shape (Prescrib.f90:218).
  !> Named here so `.glb` and `.pre` cannot drift on the spelling independently.
  character(len=*), parameter :: TYPE_ABC_MIF = 'MIF'

  type :: deck_context_t
    logical :: filled = .false.        ! parse_glb sets this last; readers must check it
    integer(int32) :: ndimn = 0        ! GLB.global_data.sizes_and_switches
    integer(int32) :: ngroup = 0       ! GLB.global_data.sizes_and_switches
    integer(int32) :: nnode = 0        ! nodes per element of the (single) group
    integer(int32) :: element_kind = 0 ! group header `index`; 5 is Q4
    !> `character(50)` in legacy (Global.f90:99 declares
    !> `character(50) type_problem,type_solver,type_load,type_ABC,type_solver_ctt`).
    !> An earlier draft of this record typed it `integer(int32)`, which would have made
    !> the .pre parser compare it against a number; caught before it shipped.
    !> THE GATE IS `== TYPE_ABC_MIF`, NOT `/= 'FIX'`: Prescrib.f90:218/220 branches on
    !> `type_abc=='MIF'` for the 9-field header and `type_abc/='MIF'` for the 8-field one,
    !> so everything that is not MIF takes the ordinary path. Comparing against 'FIX'
    !> instead would reject every value legacy accepts except that one literal.
    character(len=LEN_TYPE_ABC) :: type_abc = ''
    integer(int32) :: nbackdt = 0      ! GLB.global_data.init_and_blocks
    integer(int32) :: ntrans = 0       ! GLB.global_data.init_and_blocks
  end type deck_context_t

  !> Fragments of the top-level `solver`, which two files supply:
  !>   `.glb` -> linear (GLB.global_data.problem_type), symmetric (GLB..init_and_blocks)
  !>   `.sol` -> profile%* (SOL.PROFILE.profile_control, four fields)
  !> `builder_set_solver` is a one-shot setter, exactly like the step setters, so the
  !> same rule applies: parsers fill their own leaves here and the driver makes the one
  !> `builder_set_solver` call.
  type :: solver_parts_t
    type(solver_t) :: solver
  end type solver_parts_t

contains

  !> Return the aggregate to its as-declared state. One intrinsic assignment from a
  !> default-initialised local, for the same reason `runtime_free` is written that
  !> way: it is total by construction and cannot miss a component added later.
  pure subroutine step_parts_reset(parts)
    type(step_parts_t), intent(inout) :: parts
    type(step_parts_t) :: fresh
    parts = fresh
  end subroutine step_parts_reset

  pure subroutine solver_parts_reset(parts)
    type(solver_parts_t), intent(inout) :: parts
    type(solver_parts_t) :: fresh
    parts = fresh
  end subroutine solver_parts_reset

  pure subroutine deck_context_reset(ctx)
    type(deck_context_t), intent(inout) :: ctx
    type(deck_context_t) :: fresh
    ctx = fresh
  end subroutine deck_context_reset

end module yl_adapter_parts
