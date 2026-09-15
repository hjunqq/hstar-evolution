! yl_runtime_geometry -- the Gauss-point geometry, computed by LEGACY, for the commit layer.
!
! WHY THIS MODULE EXISTS AT ALL, AND WHY IT IS NOT IN build_runtime
!   `build_runtime` used to compute this: the quadrature rule, the shape functions, the
!   Jacobian, its inverse and the Cartesian derivatives, each transcribed from Elements.f90.
!   Every transcription was faithful and every one was a liability. On 2026-09-14 the
!   Jacobian copy produced cartd values 1-2 ULP from legacy's -- same formula, same loop
!   order, different machine code, because -O2 reassociates a scalar accumulator
!   differently from an array-element one. That seeded a divergence at step ONE of
!   train05b_slope_srm which eight printed digits hid for 74 steps and the plastic path
!   amplified to max|d| = 6.5e7.
!
!   The lesson is not "transcribe more carefully". It is that RuntimeState has no business
!   COMPUTING anything legacy computes. Its job (ADR-0009) is to say which state must exist
!   and to carry values across the seam -- existence and transport, not arithmetic. Gauss
!   geometry is arithmetic, and the algorithm belongs to legacy, so it is called here and
!   `build_runtime` no longer knows it exists. That is also what lets build_runtime go back
!   to building with no legacy source at all (R31).
!
! WHAT IT DOES NOT DECIDE
!   A non-positive Jacobian. legacy warns and integrates anyway (Elements.f90:3264-3271);
!   refusing is this build's decision, not legacy's, so the routine REPORTS the minimum
!   determinant and the caller raises. Keeping the refusal out of here also keeps this
!   module free of the error accumulator, which is what makes it a leaf.
module yl_runtime_geometry

  use iso_fortran_env, only: real64
  use variable_types, only: irk, ink
  use elements, only: getgauss, shfunc, jacob

  implicit none
  private

  public :: geometry_rule

contains

  !> One integration rule's geometry for one element, in legacy's own arithmetic.
  !>
  !> `elcod(ndimn, nnode)` is the element's node coordinates in legacy's node order.
  !> `ngaus` selects the rule: legacy's `getgauss` reads it together with `nnode`, so 4 is
  !> the 2x2 stiffness rule and 16 the 4x4 rule Q4 declares second.
  !>
  !> `cartd` is produced only when `with_gradients`, because legacy allocates it only for a
  !> rule whose name is not 'mass' (Elements.f90:1232); an allocated one for the mass rule
  !> would be a shape the solver never sees.
  subroutine geometry_rule(ndimn, nnode, ngaus, elcod, with_gradients, ie,                   &
                           djacb, gpcod, cartd, djacb_min)
    integer, intent(in) :: ndimn, nnode, ngaus, ie
    real(real64), intent(in) :: elcod(:,:)
    logical, intent(in) :: with_gradients
    real(real64), intent(out) :: djacb(:)            ! (ngaus)  weighted, legacy's `djacb`
    real(real64), intent(out) :: gpcod(:,:)          ! (ndimn, ngaus)
    real(real64), intent(out) :: cartd(:,:,:)        ! (ndimn, nnode, ngaus), untouched if not wanted
    real(real64), intent(out) :: djacb_min           ! the caller's B3 evidence

    real(irk) :: posgp(2, 16), weigp(16)
    real(irk) :: sh(4), dv(2, 4), elcod_l(2, 4), cartd_l(2, 4), xjaci_l(2, 2), dj
    integer :: igaus, id, inode

    djacb_min = huge(0.0_real64)
    call getgauss(int(ndimn, ink), int(nnode, ink), int(ngaus, ink), posgp, weigp)
    elcod_l(1:ndimn, 1:nnode) = real(elcod(1:ndimn, 1:nnode), irk)

    do igaus = 1, ngaus
      ! `u` is the third parent coordinate, unused in 2-D; legacy passes it too
      ! (Elements.f90:2067) and its callers on this path hold 0.
      call shfunc(int(ndimn, ink), int(nnode, ink), posgp(1, igaus), posgp(2, igaus),         &
                  0.0_irk, sh, dv)

      ! Elements.f90:1259-1261, SUM and not an accumulation loop, because that is the
      ! statement legacy executes and the two do not agree in the last bits.
      do id = 1, ndimn
        gpcod(id, igaus) = real(sum(elcod_l(id, 1:nnode)*sh(1:nnode)), real64)
      end do

      call jacob(int(ie, ink), int(ndimn, ink), int(nnode, ink), elcod_l, dv, cartd_l,       &
                 dj, xjaci_l)
      djacb_min = min(djacb_min, real(dj, real64))

      if (with_gradients) then
        do id = 1, ndimn
          do inode = 1, nnode
            cartd(id, inode, igaus) = real(cartd_l(id, inode), real64)
          end do
        end do
      end if

      ! Elements.f90:1363. The 'AX' axisymmetric variant multiplies by gpcod(1) as well;
      ! it is not on this path and is not reproduced, so a deck that reached it would be
      ! silently wrong -- which is why the element class is gated long before here.
      djacb(igaus) = real(dj*weigp(igaus), real64)
    end do
  end subroutine geometry_rule

end module yl_runtime_geometry
