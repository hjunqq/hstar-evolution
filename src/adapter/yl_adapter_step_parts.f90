! yl_adapter_step_parts -- the scratch aggregate through which four deck files
! assemble ONE `steps[0]`.
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
!     output            .glb     activation(:)    .glb
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
module yl_adapter_step_parts

  use iso_fortran_env, only: int32
  use yl_problem_optional, only: opt_text
  use yl_problem_types, only: controls_t, load_t, output_t, boundary_t, activation_t

  implicit none
  private

  public :: step_parts_t, step_parts_reset

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

contains

  !> Return the aggregate to its as-declared state. One intrinsic assignment from a
  !> default-initialised local, for the same reason `runtime_free` is written that
  !> way: it is total by construction and cannot miss a component added later.
  pure subroutine step_parts_reset(parts)
    type(step_parts_t), intent(inout) :: parts
    type(step_parts_t) :: fresh
    parts = fresh
  end subroutine step_parts_reset

end module yl_adapter_step_parts
