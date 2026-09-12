! yl_modern_prelude -- the two things the modern path must set BEFORE global_data runs.
!
! The adapter entry lives inside global_data, which is already too late for `probn`: every
! file the solver opens, input and output alike, is named `probn//extension`, and those
! opens happen on the way to the entry. `.inp` supplies probn and six run switches in
! legacy; on the modern path there is no `.inp`, so this reads the same case.toml the entry
! will read again and sets exactly those.
!
! WHY READING THE FILE TWICE IS THE RIGHT TRADE
!   The alternative is a parsed document carried in a module variable between two points in
!   legacy control flow -- shared mutable state across a seam, for a file of fifty lines.
!   Reading twice costs nothing measurable and keeps each half able to fail on its own.
!
! WHAT IT DOES NOT DO
!   It does not validate. If the file is malformed the ENTRY says so, with the line and the
!   key; a prelude that reported its own half of the diagnostics would give the operator two
!   different messages for one bad file.
subroutine yl_modern_prelude()

  use iso_fortran_env, only: int32
  use variable_types, only: irk

  use yl_diag, only: yl_input_file
  use solver, only: iafile, icond, ipdchk, ising
  use global_var, only: probn, restart, relis, sysrelis, ADINA, Uopt_R, gamamax, runblks,   &
                        outplot, rmesh, level_set_problem, nflow, upliftin, outind
  use yl_authoring_toml, only: toml_doc_t, toml_read

  implicit none

  type(toml_doc_t) :: doc
  integer(int32) :: k

  ! Silence here, not a diagnostic: the entry re-reads this file and owns the verdict.
  call toml_read(trim(yl_input_file), doc)
  if (.not. doc%failed) then
    k = doc%find('mesh.file')
    ! `mesh.file` is the run prefix, for the mesh pair AND for everything the solver
    ! writes -- which is what legacy's probn has always been.
    if (k /= 0_int32) probn = trim(doc%entry(k)%svalue)
  end if

  ! The `.inp` run switches. All six are pinned by the capability whitelist (the adapter
  ! refuses a deck that sets any of them), so on the modern path they are constants, not
  ! values an author was spared writing.
  restart = 0
  relis = 0
  sysrelis = 0
  ADINA = 0
  Uopt_R = 0
  gamamax = 0
  ! One block: multiple blocks are a capability the whitelist does not admit.
  runblks = 1

  ! `outplot` decides WHICH output units global_data opens, and those opens happen before
  ! the adapter entry runs -- so it has to be set here rather than by the commit. The
  ! contract whitelists one output format; GIDR is its legacy spelling.
  outplot = 'GIDR'
  ! The switches the skipped reads would have set, all pinned off by the whitelist. They
  ! are read before the entry and decide which further files global_data opens.
  rmesh = 0
  level_set_problem = 0
  nflow = 0
  upliftin = 0
  outind = 0

  ! The PROFILE control record legacy reads lazily from `.sol` inside solve
  ! (Solver.f90:6831), long after the entry has run. The whitelist admits one setting, and
  ! the golden decks carry it: no pivot file, no condition estimate, and both the
  ! positive-definite and singularity checks on. Set here for the same reason as probn --
  ! the read happens outside the entry's reach.
  iafile = 0
  icond = 0
  ipdchk = 1
  ising = 1


end subroutine yl_modern_prelude


!> The `.man` step records, for the modern path.
!>
!> These are ROUTINE LOCALS of STATIC_U, not module state -- `cwater` is declared at
!> Fem.f90:2397 inside the routine -- so nothing outside can reach them and they are passed
!> in explicitly. That is the honest shape anyway: the modern path is supplying the values
!> a read would have produced, at the point the read would have happened.
!>
!> `increments` and `max_iterations` are AUTHORED; the rest are whitelist constants (one
!> step per increment, no water column, no restart cadence).
subroutine yl_modern_step_controls(nincs_, miter, ditime, noutn, noutf, nstep, inc_step,     &
                                   nresta, cwater, qstatic)
  use iso_fortran_env, only: int32
  use variable_types, only: irk, ink
  use yl_diag, only: yl_input_file
  use yl_authoring_toml, only: toml_doc_t, toml_read
  implicit none
  integer(ink), intent(out) :: nincs_, miter, noutn, noutf, nstep, inc_step, nresta
  integer(ink), intent(out) :: cwater, qstatic
  real(irk), intent(out) :: ditime
  type(toml_doc_t) :: doc
  integer(int32) :: k
  nincs_ = 1_ink
  miter = 1_ink
  call toml_read(trim(yl_input_file), doc)
  if (.not. doc%failed) then
    k = doc%find('step[1].controls.increments')
    if (k /= 0_int32) nincs_ = int(doc%entry(k)%ivalue, ink)
    k = doc%find('step[1].controls.max_iterations')
    if (k /= 0_int32) miter = int(doc%entry(k)%ivalue, ink)
  end if
  ditime = 1.0_irk
  noutn = 1_ink
  noutf = 1_ink
  nstep = 1_ink
  inc_step = 1_ink
  nresta = 1_ink
  cwater = 0_ink
  qstatic = 0_ink
end subroutine yl_modern_step_controls


!> The convergence tolerances, likewise locals of STATIC_U. `toler_var` is one value per
!> degree of freedom and the contract lets the author write one number, so the fan-out
!> happens here, where mdofn is known.
subroutine yl_modern_tolerances(toler_force)
  use iso_fortran_env, only: int32
  use variable_types, only: irk
  use yl_diag, only: yl_input_file
  ! toler_var is reached through the MODULE, not through a dummy: passing it in from
  ! inside STATIC_U faulted under -check pointers, and it cannot be set earlier either --
  ! legacy allocates it at Fem.f90:214, which runs AFTER the entry (the entry lives inside
  ! global_data, called at :117). So the only place that works is right here, where the
  ! read it replaces used to be.
  use global_var, only: toler_var, mdofn
  use yl_authoring_toml, only: toml_doc_t, toml_read
  implicit none
  real(irk), intent(out) :: toler_force
  type(toml_doc_t) :: doc
  integer(int32) :: k
  toler_force = 1.0e-5_irk
  if (allocated(toler_var)) toler_var = 1.0e-5_irk
  call toml_read(trim(yl_input_file), doc)
  if (doc%failed) return
  k = doc%find('step[1].controls.tolerance_force')
  if (k /= 0_int32) toler_force = real(doc%entry(k)%rvalue, irk)
  k = doc%find('step[1].controls.tolerance_dof')
  if (k /= 0_int32 .and. allocated(toler_var)) then
    toler_var(1:max(int(mdofn), 1)) = real(doc%entry(k)%rvalue, irk)
  end if
end subroutine yl_modern_tolerances


!> Reserved for modern values that need a size the commit computes. Empty today: the one
!> candidate (toler_var) turned out to belong at its read site instead, because legacy
!> allocates it AFTER the entry runs.
subroutine yl_modern_after_commit()
  implicit none
end subroutine yl_modern_after_commit
