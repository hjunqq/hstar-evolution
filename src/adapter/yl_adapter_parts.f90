! yl_adapter_parts -- the adapter's cross-file scaffolding.
!
! Three types and one raiser. The types exist because the legacy deck splits across
! nine files objects that ProblemState keeps whole, so something has to carry a fact
! or a fragment from the file that supplies it to the file that needs it; the raiser
! exists because all six parsers refuse the same KIND of thing and must refuse it the
! same way (M4-01 L2-b, below).
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
! THE DIALECT RAISER (M4-01 L2-b)
!   `reject_dialect` is the ONE place an adapter says "this is valid legacy that this
!   build does not cover". Before L2-b each parser built that finding itself, so the
!   code, the stage, the rule-id shape and the wording were spelled in five modules
!   and 58 places; docs/m4/adapter-contract.md SS4 assigns the unification here and
!   docs/02-migration-plan.md M4 names the outward verdict UNSUPPORTED_LEGACY_DIALECT.
!
!   A parser now passes only what it observed: the row's two id halves, the source
!   location, and the value it read. Everything else -- code, stage, rule-id
!   composition, object_path, field, wording -- comes from the CAP_STAGE_ADAPT row in
!   yl_problem_profile. A raise site therefore CANNOT drift from its declaration,
!   because it no longer carries a copy of it.
!
!   THE COMPOSED KEY. The row's stable id is `rule_id/condition` and reject_dialect
!   composes it, from the row it just looked up, after the lookup succeeded. This is
!   deliberate and it is the shape yl_runtime_build's raise_row already uses: passing
!   a bare rule id where a composed key is expected is a bug this project has shipped
!   once, and the only durable fix is to make the joined string un-passable. A caller
!   here passes two arguments; there is nothing to join and nothing to get wrong.
!
!   A KEY THE TABLE DOES NOT DECLARE is reported as PE_INTERNAL, not silently
!   downgraded -- same reasoning as raise_row: the alternative is a finding whose rule
!   id no coverage walk will ever match, which is precisely the decay this mechanism
!   exists to prevent, reappearing as a typo.
!
! WHAT THIS TYPE IS NOT
!   It is not part of `ProblemState` and never will be. It is adapter scaffolding
!   with the lifetime of one parse, and it exists only because the deck splits an
!   object the model keeps whole. A modern input format (M5) authors `steps[0]` in
!   one place and needs nothing like it.
module yl_adapter_parts

  use iso_fortran_env, only: int32
  use yl_problem_optional, only: opt_text, opt_value_or
  use yl_problem_types, only: controls_t, load_t, output_t, boundary_t, activation_t,          &
                              solver_t, profile_t, section_t
  use yl_problem_errors, only: problem_errors_t, problem_error_t, source_location_t,           &
                               make_problem_error, PE_UNSUPPORTED, PE_INTERNAL,                &
                               PE_STAGE_ADAPT, PE_EXIT_INTERNAL
  use yl_problem_profile, only: capability_item_t, dialect_count, dialect_row, dialect_find,   &
                                dialect_key, DIALECT_VERDICT

  implicit none
  private

  public :: step_parts_t, step_parts_reset
  public :: solver_parts_t, solver_parts_reset
  public :: section_parts_t, section_parts_reset
  public :: deck_context_t, deck_context_reset
  public :: LEN_TYPE_ABC, TYPE_ABC_MIF
  public :: reject_dialect, dialect_verdict_of
  public :: dialect_row_exercised, dialect_first_uncovered

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
    !> Per-section data from `.glb`'s group-header loop, in group order.
    !>
    !> WHY THESE EXIST, added 2026-09-08 after L2-a's first integration run:
    !> legacy reads `.ele` INSIDE that loop, so a record's owning group is decided
    !> POSITIONALLY -- group 1 takes the first `nelgroup(1)` records, group 2 the next
    !> `nelgroup(2)`, and so on. The `.ele` file itself carries no group boundary; its
    !> records are just `i0, lnods(1:nnode)`. Without these arrays the `.ele` parser
    !> cannot attribute an element to a section at all, which is why nothing was setting
    !> `mesh.elements[].elset`, `mesh.elements[].material` or `mesh.elsets[]` -- the two
    !> parsers' headers each disclaimed the field and pointed at the other, and both were
    !> right: `.glb` never sees an element record and `.ele` never sees a group boundary.
    !>
    !> Unallocated means `parse_glb` has not run. On the current whitelist each has
    !> exactly one entry (the capability gate admits a single section), but they are
    !> arrays because the positional rule is per group and a scalar would quietly become
    !> wrong the day the gate widens.
    integer(int32), allocatable :: nelgroup(:)     ! elements in each section
    integer(int32), allocatable :: group_matno(:)  ! each section's header material id
    integer(int32), allocatable :: group_kind(:)   ! each section's element-kind index
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

  !> The `sections[]` collection, held back until BOTH files that feed it have run.
  !>
  !> WHY, added 2026-09-09 after L3-a found `sections[].thickness` being dropped:
  !> `.glb`'s group headers supply every section field except one, and `.mat` supplies
  !> `thickness` -- legacy stores it per material (`props(imat)%mechanical%solid%thickness`,
  !> Material.f90:319) while ADR-0003 gives it to the section, so it must be resolved
  !> section -> material -> thickness. `docs/m2/state-field-map.toml`'s own note on
  !> `sections.thickness` assigns that resolution to "the bridge's job", which is this
  !> adapter layer.
  !>
  !> Legacy reads `.glb` (Fem.f90:117) before `.mat` (:191), so at the moment `parse_glb`
  !> knows a section it does not yet know that section's thickness. `builder_add_section`
  !> takes a whole `section_t` and the builder has no way to amend one afterwards -- by
  !> design, since silent mutation of published state is what these types exist to
  !> prevent. So publication is deferred: `parse_glb` fills every other field here,
  !> `parse_mat` fills `thickness`, and the driver makes the `builder_add_section` calls
  !> once, in order, after both have run.
  !>
  !> This is the same shape as `step_parts_t` and `solver_parts_t`, for the same reason
  !> and the third time: the deck splits across files an object the model keeps whole.
  type :: section_parts_t
    type(section_t), allocatable :: sections(:)
  end type section_parts_t

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

  pure subroutine section_parts_reset(parts)
    type(section_parts_t), intent(inout) :: parts
    type(section_parts_t) :: fresh
    parts = fresh
  end subroutine section_parts_reset

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

  ! ==========================================================================
  ! the dialect raiser -- see the module header
  ! ==========================================================================

  !> Raise the CAP_STAGE_ADAPT row named by (`rule_id`, `condition`).
  !>
  !> The caller supplies ONLY run-time facts:
  !>   loc       where in the legacy deck the value was read (mandatory: a dialect
  !>             finding without a site sends its reader back to 125 read sites)
  !>   actual    the value that was actually read, rendered by the caller
  !>   expected  the whitelisted value, when it is a run-time comparand (e.g.
  !>             `> `//nblks). Omit it when the row's message already states it;
  !>             the table never holds it, because for most rows it is a sentence
  !>             rather than a value.
  !>   idx       the record ordinal, for a row raised inside a per-record loop.
  !>
  !> Everything that identifies the rule comes from the row. There is deliberately
  !> no `message` argument: a caller able to pass wording is a caller able to make
  !> the table's wording wrong without failing anything.
  subroutine reject_dialect(errors, rule_id, condition, loc, actual, expected, idx)
    type(problem_errors_t), intent(inout) :: errors
    character(len=*), intent(in) :: rule_id, condition
    type(source_location_t), intent(in) :: loc
    character(len=*), intent(in), optional :: actual, expected
    integer(int32), intent(in), optional :: idx

    type(capability_item_t) :: row
    logical :: found
    integer :: j

    j = dialect_find(rule_id, condition)
    if (j == 0) then
      ! Not a dialect this build declares. Reported as an INTERNAL fault at exit
      ! class 6, never as an UNSUPPORTED verdict at class 3: the deck may be
      ! perfectly ordinary and it is this program that is wrong.
      call errors%add(make_problem_error(PE_INTERNAL, PE_STAGE_ADAPT,                          &
                      trim(rule_id)//'/'//trim(condition), 'adapter', field='*',               &
                      message='the adapter raised a legacy dialect the capability table '//    &
                      'does not declare: '//trim(rule_id)//'/'//trim(condition),               &
                      exit_class=PE_EXIT_INTERNAL, source=loc))
      return
    end if

    call dialect_row(j, row, found)
    if (.not. found) return

    call errors%add(make_problem_error(code=PE_UNSUPPORTED, stage=PE_STAGE_ADAPT,              &
                    rule_id=dialect_key(j), object_path=trim(row%object_path),                 &
                    index=idx, field=field_or_absent(row), message=trim(row%message),          &
                    actual=actual, expected=expected, source=loc))
  end subroutine reject_dialect

  !> The row's `field`, or the string the caller must NOT pass when the row has none.
  !>
  !> A blank `field` and an absent `field` are different findings: absent means the
  !> row binds to the object as a whole, blank would mean it binds to a component
  !> whose name is the empty string. make_problem_error distinguishes them by
  !> presence, and a function result cannot be absent -- so this returns a
  !> zero-length string and the ONE caller above passes it through unconditionally.
  !> The consequence is recorded here rather than hidden: nineteen dialect rows have
  !> no field, and their findings carry `field` set to ''. dialect_row_exercised
  !> compares against the row's own trimmed field, so the two agree by construction.
  pure function field_or_absent(row) result(f)
    type(capability_item_t), intent(in) :: row
    character(len=:), allocatable :: f
    f = trim(row%field)
  end function field_or_absent

  !> The adapter's single outward verdict. DIALECT_VERDICT
  !> ('UNSUPPORTED_LEGACY_DIALECT', docs/02-migration-plan.md M4) when `errors`
  !> holds at least one dialect finding, the empty string otherwise.
  !>
  !> This is what "L2-b unifies the outward expression" means concretely: a caller
  !> at the adapter boundary asks ONE question and gets ONE answer, instead of
  !> pattern-matching on 58 rule ids or on a PE_UNSUPPORTED that the capability gate
  !> also raises for an entirely different reason (a draft that exists but is out of
  !> whitelist, at a later stage). The stage is what separates them, which is why
  !> this predicate tests the stage and not just the code.
  pure function dialect_verdict_of(errors) result(verdict)
    type(problem_errors_t), intent(in) :: errors
    character(len=:), allocatable :: verdict
    type(problem_error_t) :: finding
    logical :: found
    integer :: k
    verdict = ''
    do k = 1, errors%count()
      call errors%get(k, finding, found)
      if (.not. found) cycle
      if (opt_value_or(finding%code, '') /= PE_UNSUPPORTED) cycle
      if (opt_value_or(finding%stage, '') /= PE_STAGE_ADAPT) cycle
      verdict = DIALECT_VERDICT
      return
    end do
  end function dialect_verdict_of

  !> Did any finding in `errors` come from dialect row `j`?
  !>
  !> The binding unit is (key, object_path, field) with the key already carrying the
  !> condition, so it is the QUAD yl_runtime_rules argues for and not the M3-02
  !> triple. Lives here, next to the raiser, for the reason the capability version
  !> lives in yl_problem_pipeline: whoever chose the finding's spelling answers the
  !> question about it, so there is no second copy of that knowledge in a test.
  pure logical function dialect_row_exercised(errors, j) result(hit)
    type(problem_errors_t), intent(in) :: errors
    integer, intent(in) :: j
    type(capability_item_t) :: row
    type(problem_error_t) :: finding
    logical :: found
    integer :: k

    hit = .false.
    call dialect_row(j, row, found)
    if (.not. found) return

    do k = 1, errors%count()
      call errors%get(k, finding, found)
      if (.not. found) cycle
      if (opt_value_or(finding%rule_id, '') /= dialect_key(j)) cycle
      if (opt_value_or(finding%field, '') /= trim(row%field)) cycle
      if (opt_value_or(finding%object_path, '') /= trim(row%object_path)) cycle
      hit = .true.
      return
    end do
  end function dialect_row_exercised

  !> The first dialect row no finding in `errors` exercised, or 0 when every row is
  !> covered. An INDEX, not a logical, for the reason capability_first_uncovered is:
  !> "row 41, A-MAT/creep, has no counter-example" is actionable, "coverage
  !> incomplete" is not.
  pure integer function dialect_first_uncovered(errors) result(j)
    type(problem_errors_t), intent(in) :: errors
    integer :: k
    j = 0
    do k = 1, dialect_count()
      if (dialect_row_exercised(errors, k)) cycle
      j = k
      return
    end do
  end function dialect_first_uncovered

end module yl_adapter_parts
