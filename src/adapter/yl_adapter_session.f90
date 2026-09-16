! yl_adapter_session -- the state the adapter entry has to remember between blocks.
!
! WHY THIS MODULE EXISTS
!   `yl_adapter_override` used to be a one-shot: legacy's block loop ran once, so the
!   ProblemState it built could live and die inside that call. A multi-block analysis
!   ends that. legacy re-reads `.pre` and the tail of `.loa` at the top of every block
!   (Fem.f90:1873/1896), which is the same thing as saying that part of the input is
!   per-STEP; the modern path therefore has to come back at the top of every block with
!   that step's boundary conditions and loads, and it needs the ProblemState it already
!   built to do it.
!
!   So the session holds exactly two things and owns neither: the committed ProblemState
!   and the RuntimeState built from it. Nothing else belongs here -- a module with `save`
!   variables is a global, and the only defence against it growing into one is that its
!   contents are named and justified in one place.
module yl_adapter_session

  use yl_problem_types, only: problem_state_t
  use yl_runtime_types, only: runtime_state_t

  implicit none
  private

  !> The ProblemState the first block committed, kept for the blocks that follow.
  type(problem_state_t), allocatable, public, save :: session_problem
  !> The RuntimeState built from it. Block-scoped commits read the geometry and DOF
  !> numbering from here rather than rebuilding it: it does not change between blocks.
  type(runtime_state_t), allocatable, public, save :: session_runtime
  !> Whether the once-per-run commit has happened. `yl_adapter_override` is called from
  !> INSIDE legacy's block loop, so on a two-block deck it is called twice; the second
  !> call must not redo the full commit, which would hit commit_legacy_globals' own
  !> "these globals are already allocated" refusal.
  logical, public, save :: session_committed = .false.

end module yl_adapter_session
