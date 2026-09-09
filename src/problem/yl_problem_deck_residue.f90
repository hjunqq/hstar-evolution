! yl_problem_deck_residue -- the values the deck supplies that ProblemState does not model.
!
! WHAT THIS IS, IN ONE SENTENCE
!   Every row here is one the M2 map says is owned by `derived` or `not_migrated` -- NOT by
!   `ProblemState.*` -- and whose value cannot be recomputed from anything else. It exists
!   because legacy READS these from the deck and LEAVES THEM IN A GLOBAL, and the shadow
!   differential compares globals.
!
! WHY IT IS NOT PART OF problem_state_t, AND MUST NOT BECOME PART OF IT
!   `tools/yl_problem_check.py` enforces a bijection between problem_state_t's leaves and
!   the map's 98 `ProblemState.*` rows. None of the rows below has such an owner, so adding
!   any of them there would either fail that gate or require widening the map's `owner`
!   column to mean something it does not -- which is the same move that kills option B in
!   docs/m4/L2c-fold-design.md §3. If one of these rows ever GAINS a `ProblemState.*` owner,
!   it should move out of here on that same commit.
!
! WHY NOT A CONSTANT IN THE COMMIT EITHER
!   Because the deck supplies these values and a second deck may supply different ones.
!   `control.glb.stab_matde` is the standing example: the adapter's gate admits any value
!   greater than nblks, both golden decks happen to carry 99999, and pinning that constant
!   would silently corrupt the third deck. `derived.counts.nsmat` is the cautionary one:
!   the map's own note said 0 until 2026-09-09 and the frozen baseline says 1 (fixed in
!   0646de3), so even a value "documented" somewhere was wrong.
!
! WHY THE COMPONENT NAMES ARE LEGACY SLOT NAMES, DELIBERATELY
!   yl_problem_types and yl_runtime_types both ban legacy spellings, because their names
!   come from the map's `owner` column and a legacy name there would be a migration that
!   did not happen. These rows have NO owner path -- `nsmat`, `npoinb`, `stab_matde` are
!   legacy slots and nothing else, which is precisely why they are here rather than there.
!   Inventing CAE names for them would claim a modelling that does not exist. Each name is
!   the last segment of the map id and each component carries its own map marker, so the
!   correspondence is mechanical in both directions and
!   `tools/yl_state_map.py commit-provenance` asserts it.
!
! ABSENCE DISCIPLINE (ADR-0002)
!   Every scalar is an `opt_int`: unset, an explicit zero and "not read yet" stay three
!   distinct states. A parser that never ran leaves its component unset, and commit must
!   report that rather than publish a 0 -- publishing a 0 for a value nobody read is the
!   forging this type exists to prevent.
module yl_problem_deck_residue

  use iso_fortran_env, only: int32
  use yl_problem_optional, only: opt_int

  implicit none
  private

  !> The deck values that reach a legacy global and no ProblemState field.
  !>
  !> One component per map row; `tools/yl_state_map.py commit-provenance` checks that this
  !> set is EXACTLY the map's residue -- the emitted model_ready rows owned by `derived` or
  !> `not_migrated` that are not obtainable from a ProblemState cardinality or the runtime.
  !> One component more or fewer fails the build.
  type, public :: deck_residue_t
    type(opt_int) :: block_stab                          !@map: control.glb.block_stab
    type(opt_int) :: bparameter                          !@map: control.glb.bparameter
    type(opt_int) :: ebody                               !@map: control.glb.ebody
    type(opt_int) :: nbackf                              !@map: control.glb.nbackf
    type(opt_int) :: ninit                               !@map: control.glb.ninit
    type(opt_int) :: nlayer                              !@map: control.glb.nlayer
    type(opt_int) :: nlinks                              !@map: control.glb.nlinks
    type(opt_int) :: ntrans                              !@map: control.glb.ntrans
    type(opt_int) :: stab_matde                          !@map: control.glb.stab_matde
    type(opt_int) :: state_change                        !@map: control.glb.state_change
    integer(int32), allocatable :: uinitial(:)           !@map: control.glb.uinitial
    type(opt_int) :: adina                               !@map: control.run.adina
    type(opt_int) :: relis                               !@map: control.run.relis
    type(opt_int) :: restart                             !@map: control.run.restart
    type(opt_int) :: delgroup                            !@map: derived.counts.delgroup
    type(opt_int) :: edge_load_group                     !@map: derived.counts.edge_load_group
    type(opt_int) :: nbeamload                           !@map: derived.counts.nbeamload
    type(opt_int) :: nedge                               !@map: derived.counts.nedge
    type(opt_int) :: npipe                               !@map: derived.counts.npipe
    type(opt_int) :: nplateload                          !@map: derived.counts.nplateload
    type(opt_int) :: nplgroup                            !@map: derived.counts.nplgroup
    type(opt_int) :: npoinb                              !@map: derived.counts.npoinb
    type(opt_int) :: nsmat                               !@map: derived.counts.nsmat
    type(opt_int) :: ntedge                              !@map: derived.counts.ntedge
    type(opt_int) :: ntelgroup                           !@map: derived.counts.ntelgroup
    type(opt_int) :: ntemp_surface                       !@map: derived.counts.ntemp_surface
    type(opt_int) :: runblks                             !@map: derived.counts.runblks
  end type deck_residue_t

end module yl_problem_deck_residue
