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
  !> `ndimn` is the MESH dimension; `lndimn` is the element KIND's own parent dimension
  !> (`elkn(index)%ndimn`, Elements.f90:163) and the two are not the same thing -- a 2-node
  !> bar in a 2-D mesh has lndimn = 1. legacy builds its Gauss tables with the KIND's value
  !> (`getgauss(lnidmn, ...)`, `shfunc(lnidmn, ...)`, :190/:201) and its coordinates with
  !> the MESH's, so both are passed. Until M9 there was one element kind and one number.
  !>
  !> `ngaus` selects the rule: legacy's `getgauss` reads it together with `nnode`, so 4 is
  !> the 2x2 stiffness rule and 16 the 4x4 rule Q4 declares second.
  !>
  !> `cartd` is produced only when `with_gradients`, because legacy allocates it only for a
  !> rule whose name is not 'mass' (Elements.f90:1232); an allocated one for the mass rule
  !> would be a shape the solver never sees.
  subroutine geometry_rule(ndimn, lndimn, nnode, ngaus, elcod, with_gradients, ie,           &
                           djacb, gpcod, cartd, djacb_min)
    integer, intent(in) :: ndimn, lndimn, nnode, ngaus, ie
    real(real64), intent(in) :: elcod(:,:)
    logical, intent(in) :: with_gradients
    real(real64), intent(out) :: djacb(:)            ! (ngaus)  weighted, legacy's `djacb`
    real(real64), intent(out) :: gpcod(:,:)          ! (ndimn, ngaus)
    real(real64), intent(out) :: cartd(:,:,:)        ! (lndimn, nnode, ngaus), untouched if not wanted
    real(real64), intent(out) :: djacb_min           ! the caller's B3 evidence

    real(irk) :: posgp(3, 16), weigp(16)
    real(irk) :: sh(4), dv(3, 4), elcod_l(3, 4), cartd_l(3, 4), xjaci_l(3, 3), dj
    real(irk) :: s, t, u, bar
    integer :: igaus, id, inode

    djacb_min = huge(0.0_real64)
    call getgauss(int(lndimn, ink), int(nnode, ink), int(ngaus, ink), posgp, weigp)
    elcod_l = 0.0_irk
    elcod_l(1:ndimn, 1:nnode) = real(elcod(1:ndimn, 1:nnode), irk)

    ! Elements.f90:1233. For a 2-node element the Jacobian IS the bar length, computed once
    ! for the whole element and not per Gauss point, and `jacob` is never called: the
    ! parent-to-physical map of a straight segment is constant. Reproduced as the statement
    ! legacy executes, for the same reason the `sum` below is a sum and not a loop.
    bar = 0.0_irk
    if (nnode == 2) bar = sqrt(sum((elcod_l(1:ndimn, 2) - elcod_l(1:ndimn, 1))**2))

    do igaus = 1, ngaus
      ! Elements.f90:195-199: t and u are ZERO for a kind whose parent space has fewer
      ! dimensions, and are read from posgp only when it has them.
      s = posgp(1, igaus)
      t = 0.0_irk
      u = 0.0_irk
      if (lndimn >= 2) t = posgp(2, igaus)
      if (lndimn == 3) u = posgp(3, igaus)
      call shfunc(int(lndimn, ink), int(nnode, ink), s, t, u, sh, dv)

      ! Elements.f90:1259-1261, SUM and not an accumulation loop, because that is the
      ! statement legacy executes and the two do not agree in the last bits.
      do id = 1, ndimn
        gpcod(id, igaus) = real(sum(elcod_l(id, 1:nnode)*sh(1:nnode)), real64)
      end do

      if (nnode == 2) then
        ! Elements.f90:1263 -- `cartd = deriv/djacb`, the whole 2-node branch.
        dj = bar
        if (with_gradients) then
          do inode = 1, nnode
            do id = 1, lndimn
              cartd(id, inode, igaus) = real(dv(id, inode)/bar, real64)
            end do
          end do
        end if
      else
        call jacob(int(ie, ink), int(lndimn, ink), int(nnode, ink), elcod_l(1:lndimn, 1:nnode), &
                   dv(1:lndimn, 1:nnode), cartd_l(1:lndimn, 1:nnode), dj,                      &
                   xjaci_l(1:lndimn, 1:lndimn))
        if (with_gradients) then
          do id = 1, lndimn
            do inode = 1, nnode
              cartd(id, inode, igaus) = real(cartd_l(id, inode), real64)
            end do
          end do
        end if
      end if
      djacb_min = min(djacb_min, real(dj, real64))

      ! Elements.f90:1363. The 'AX' axisymmetric variant multiplies by gpcod(1) as well;
      ! it is not on this path and is not reproduced, so a deck that reached it would be
      ! silently wrong -- which is why the element class is gated long before here.
      djacb(igaus) = real(dj*weigp(igaus), real64)
    end do
  end subroutine geometry_rule

end module yl_runtime_geometry
