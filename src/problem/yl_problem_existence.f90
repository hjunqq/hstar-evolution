! yl_problem_existence -- the deck values a legacy global must HOLD even though nothing
! compares them.
!
! WHAT THIS IS, IN ONE SENTENCE
!   The carrier for `docs/m4/existence-face.toml`: legacy arrays the solver requires to
!   exist, whose values come from the deck, and which the M2 map does not register because
!   nothing observes them at any checkpoint.
!
! WHY IT IS A SEPARATE TYPE FROM deck_residue_t
!   `deck_residue_t` carries rows the map DOES emit -- its membership is COMPUTED as the
!   map's residue and checked by set equality. This type carries rows the map does NOT
!   emit, and cannot: joining the emitted set is the only way into the residue, and that
!   would make the frozen baseline incomplete and force a re-freeze that
!   `yl_state_probe.py freeze` deliberately refuses (ADR-0006: the baseline is worth
!   something because it does not follow the implementation).
!
!   Two carriers, two tables, two bijections. M3-03's single bijection (commit's derive
!   rules <-> the map's model_ready rows) is NOT weakened -- it keeps its exact meaning on
!   the comparison face, and the existence face gets its own of the same shape. Merging
!   them would have been the weakening: one table meaning two things is how "compared" and
!   "must exist" got confused in the first place.
!
! HOW A ROW GETS IN HERE
!   Only after a real run aborted for want of it, at a named site. `existence-face.toml`'s
!   `observed_requirement` is that evidence and is mandatory. The defect this face exists
!   to fix was a classification made by READING being overturned by EXECUTION
!   (`order_time_mdofn`, tagged "unused_switch / dynamic time integration", read once per
!   dof per increment by predict). Filling this table by reading would reproduce exactly
!   that defect one level up.
!
! WHY THE VALUES STILL COME FROM THE DECK
!   "Its value is not compared" does not license writing a constant. On the two golden
!   decks `order_time_mdofn` is all zeros; a third deck may not be. `stab_matde` is the
!   standing lesson -- both golden decks carry 99999 and pinning that constant would
!   silently corrupt a deck that carries something else.
!
! ABSENCE DISCIPLINE (ADR-0002)
!   An unallocated component means "the parser never ran", not "the array is empty".
!   Commit must report that rather than publish a zero-length array: publishing an empty
!   array for something nobody read is the forging this discipline exists to prevent.
module yl_problem_existence

  use iso_fortran_env, only: int32

  implicit none
  private

  !> One component per row of docs/m4/existence-face.toml.
  !> `tools/yl_existence_check.py` checks that this set is EXACTLY the table's rows, that
  !> each component's NAME equals its row's `carrier`, and that commit's existence pass
  !> writes exactly the same set -- all as set equalities, in both directions.
  type, public :: deck_existence_t
    !@existence: order_time_mdofn
    integer(int32), allocatable :: order_time_mdofn(:)
    !@existence: tension_joint
    integer(int32), allocatable :: tension_joint(:)
    !@existence: tlink
    !> (2, ntlink). ntlink is a .glb size; on the whitelist it is 0 and the array is empty,
    !> but the EXTENT still has to come from the deck rather than from a pinned 0.
    integer(int32), allocatable :: tlink(:, :)
    !@existence: equvs_process
    integer(int32), allocatable :: equvs_process(:)
    !@existence: force_process
    integer(int32), allocatable :: force_process(:)
    !@existence: modf_dis_blocks
    integer(int32), allocatable :: modf_dis_blocks(:)
    !@existence: group_type_mass
    !> (nrfields, ngroup). Read from the same .glb record as order_time; gravity reads
    !> group(ig)%type_mass(ifield) every increment.
    integer(int32), allocatable :: group_type_mass(:, :)
    !@existence: group_order_time
    !> (2, nrfields, ngroup). Ragged in legacy (nrfields varies per group); this build's
    !> whitelist admits one shape, and the parser refuses a deck where a later group
    !> disagrees rather than silently truncating.
    integer(int32), allocatable :: group_order_time(:, :, :)
  end type deck_existence_t

end module yl_problem_existence
