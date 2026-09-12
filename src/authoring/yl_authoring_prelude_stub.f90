! The prelude's counterpart for builds without the authoring layer. Fem.f90 calls
! yl_modern_prelude behind `if (yl_input_enabled)`, and every target that links the legacy
! tree therefore needs the symbol. This one REFUSES for the same reason the adapter stub
! does: a build that cannot read modern input must say so, not quietly read a deck.
subroutine yl_modern_prelude()
  use yl_diag, only: diag_abort, EXIT_UNSUPPORTED
  implicit none
  call diag_abort('UNSUPPORTED', EXIT_UNSUPPORTED, 'yl_modern_prelude_stub', &
       'this binary was built without the authoring layer; --input=FILE is not available')
end subroutine yl_modern_prelude

! The two `.man` substitutes. Unreachable in a build without the authoring layer (the
! prelude above refuses first), so they only have to exist.
subroutine yl_modern_step_controls(nincs_, miter, ditime, noutn, noutf, nstep, inc_step,     &
                                   nresta, cwater, qstatic)
  use variable_types, only: irk, ink
  implicit none
  integer(ink), intent(out) :: nincs_, miter, noutn, noutf, nstep, inc_step, nresta
  integer(ink), intent(out) :: cwater, qstatic
  real(irk), intent(out) :: ditime
  nincs_ = 0_ink; miter = 0_ink; noutn = 0_ink; noutf = 0_ink; nstep = 0_ink
  inc_step = 0_ink; nresta = 0_ink; cwater = 0_ink; qstatic = 0_ink; ditime = 0.0_irk
end subroutine yl_modern_step_controls

subroutine yl_modern_tolerances(toler_force)
  use variable_types, only: irk
  implicit none
  real(irk), intent(out) :: toler_force
  toler_force = 0.0_irk
end subroutine yl_modern_tolerances

subroutine yl_modern_after_commit()
  implicit none
end subroutine yl_modern_after_commit
