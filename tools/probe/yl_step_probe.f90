! TEMPORARY DIAGNOSTIC -- not part of any build target, not a gate, delete when done.
!
! One question only: at which STEP do the legacy and adapter paths first differ, and in
! which quantity? The printed results agree to eight significant digits for 74 steps, which
! says nothing about the doubles behind them, so the probe records BIT PATTERNS.
!
! Called once per step from STATIC_U, immediately before out_record/outputres, so it sees
! the converged state of that step. Writes one line per step to `step-probe.txt`:
!
!   step <n> ttime <hex> dfact <hex> ... uu <hex> gp <hex> np <n>
!
! `uu` and `gp` are XOR-folds of the raw 64-bit patterns: two runs agree on the fold iff
! every value agrees bit for bit (XOR cannot mask a single-bit difference, only an even
! number of identical ones, which is what a plain sum could hide).
subroutine yl_step_probe()

  use iso_fortran_env, only: int64, int32
  use variable_types, only: irk, ink
  use global_var, only: istep, ttime, result_zero, npoin, nelem, element, coord
  use elements, only: elkn
  use applied_load, only: tcurves
  use materials, only: props

  implicit none

  integer, save :: u = -1
  logical, save :: opened = .false.
  integer(int64) :: fold_u, fold_g, fold_c, fold_x, fold_m
  integer(int64) :: fold_t, fold_e, fold_r
  integer :: i, j, k, nz_t, nd_t
  double precision :: v, mx_t
  character(len=16) :: hx

  if (.not. opened) then
    open (newunit=u, file='step-probe.txt', status='replace', action='write')
    opened = .true.
  end if

  fold_u = 0_int64
  if (allocated(result_zero)) then
    do i = 1, size(result_zero)
      fold_u = ieor(fold_u, transfer(real(result_zero(i), kind(1.0d0)), 0_int64))
    end do
  end if

  ! Gauss-point state: this is what carries plasticity across steps.
  fold_g = 0_int64
  if (allocated(element)) then
    do i = 1, size(element)
      if (.not. associated(element(i)%field)) cycle
      if (.not. associated(element(i)%field(1)%gpvar)) cycle
      do j = 1, size(element(i)%field(1)%gpvar, 1)
        do k = 1, size(element(i)%field(1)%gpvar, 2)
          fold_g = ieor(fold_g, transfer(real(element(i)%field(1)%gpvar(j, k), kind(1.0d0)), 0_int64))
        end do
      end do
    end do
  end if

  ! The strength-reduction factor, per curve: mat_curve's whole contribution.
  fold_c = 0_int64
  if (allocated(tcurves)) then
    do i = 1, size(tcurves)
      fold_c = ieor(fold_c, transfer(real(tcurves(i)%dfact, kind(1.0d0)), 0_int64))
    end do
  end if

  ! coord: constant through the run, so a difference here is an INPUT difference and the
  ! answer; identical here moves the search past the mesh.
  fold_x = 0_int64
  if (allocated(coord)) then
    do i = 1, size(coord, 1)
      do j = 1, size(coord, 2)
        fold_x = ieor(fold_x, transfer(real(coord(i, j), kind(1.0d0)), 0_int64))
      end do
    end do
  end if

  ! The material numbers the constitutive routine actually reads.
  fold_m = 0_int64
  if (allocated(props)) then
    do i = 1, size(props)
      if (.not. associated(props(i)%mechanical)) cycle
      if (.not. associated(props(i)%mechanical%solid)) cycle
      fold_m = ieor(fold_m, transfer(real(props(i)%mechanical%solid%e, kind(1.0d0)), 0_int64))
      fold_m = ieor(fold_m, transfer(real(props(i)%mechanical%solid%nu, kind(1.0d0)), 0_int64))
      fold_m = ieor(fold_m, transfer(real(props(i)%mechanical%solid%density, kind(1.0d0)), 0_int64))
      fold_m = ieor(fold_m, transfer(real(props(i)%mechanical%solid%thickness, kind(1.0d0)), 0_int64))
      if (associated(props(i)%mechanical%solid%ClassicalEP)) then
        fold_m = ieor(fold_m, transfer(real(props(i)%mechanical%solid%ClassicalEP%sigma0, kind(1.0d0)), 0_int64))
        fold_m = ieor(fold_m, transfer(real(props(i)%mechanical%solid%ClassicalEP%frict_angle, kind(1.0d0)), 0_int64))
        fold_m = ieor(fold_m, transfer(real(props(i)%mechanical%solid%ClassicalEP%dilan_angle, kind(1.0d0)), 0_int64))
        fold_m = ieor(fold_m, transfer(real(props(i)%mechanical%solid%ClassicalEP%hardening, kind(1.0d0)), 0_int64))
      end if
    end do
  end if

  ! The element load vectors, SEPARATELY: tload is the applied load, eload the one the
  ! step recomputes, rload the residual. Folding them together said only "one of these".
  fold_t = 0_int64; fold_e = 0_int64; fold_r = 0_int64
  if (allocated(element)) then
    do i = 1, size(element)
      if (.not. associated(element(i)%field)) cycle
      if (associated(element(i)%field(1)%tload)) then
        do j = 1, size(element(i)%field(1)%tload)
          fold_t = ieor(fold_t, transfer(real(element(i)%field(1)%tload(j), kind(1.0d0)), 0_int64))
        end do
      end if
      if (associated(element(i)%field(1)%eload)) then
        do j = 1, size(element(i)%field(1)%eload)
          fold_e = ieor(fold_e, transfer(real(element(i)%field(1)%eload(j), kind(1.0d0)), 0_int64))
        end do
      end if
      if (associated(element(i)%field(1)%rload)) then
        do j = 1, size(element(i)%field(1)%rload)
          fold_r = ieor(fold_r, transfer(real(element(i)%field(1)%rload(j), kind(1.0d0)), 0_int64))
        end do
      end if
    end do
  end if

  ! Counts, not just folds: a fold of 0x6D says "almost everything is 0.0 and something
  ! tiny is not", which is a different problem from "the values differ".
  nz_t = 0; nd_t = 0; mx_t = 0.0d0
  if (allocated(element)) then
    do i = 1, size(element)
      if (.not. associated(element(i)%field)) cycle
      if (.not. associated(element(i)%field(1)%tload)) cycle
      do j = 1, size(element(i)%field(1)%tload)
        v = real(element(i)%field(1)%tload(j), kind(1.0d0))
        if (v /= 0.0d0) nz_t = nz_t + 1
        if (v /= 0.0d0 .and. abs(v) < 1.0d-300) nd_t = nd_t + 1
        if (abs(v) > mx_t) mx_t = abs(v)
      end do
    end do
  end if

  ! The parent-element quadrature: legacy builds elkn(index)%ggaus(order)%posgp/weigp,
  ! and build_runtime has its own q4_stiffness_quadrature. If the two abscissas differ in
  ! the last bit, every shape gradient does, and cartd is where it first shows.
  if (int(istep) == 1) then
    do i = 1, size(elkn)
      if (.not. associated(elkn(i)%ggaus)) cycle
      do j = 1, size(elkn(i)%ggaus)
        if (.not. associated(elkn(i)%ggaus(j)%posgp)) cycle
        if (associated(elkn(i)%ggaus(j)%deriv)) then
          do k = 1, size(elkn(i)%ggaus(j)%deriv, 1)
            do nz_t = 1, size(elkn(i)%ggaus(j)%deriv, 2)
              do nd_t = 1, size(elkn(i)%ggaus(j)%deriv, 3)
                write (u, '(a,4(i0,a),z16.16)') '   deriv ', i, ' ', j, ' ', k, ' ', &
                  nz_t*100 + nd_t, ' = ', &
                  transfer(real(elkn(i)%ggaus(j)%deriv(k, nz_t, nd_t), kind(1.0d0)), 0_int64)
              end do
            end do
          end do
        end if
        do k = 1, size(elkn(i)%ggaus(j)%posgp, 1)
          do nz_t = 1, size(elkn(i)%ggaus(j)%posgp, 2)
            write (u, '(a,i0,a,i0,a,i0,a,i0,a,z16.16)') '   posgp kind ', i, ' rule ', j, &
              ' dim ', k, ' pt ', nz_t, ' = ', &
              transfer(real(elkn(i)%ggaus(j)%posgp(k, nz_t), kind(1.0d0)), 0_int64)
          end do
        end do
      end do
    end do
  end if

  write (hx, '(z16.16)') transfer(real(ttime, kind(1.0d0)), 0_int64)
  write (u, '(a,i0,a,a,8(a,z16.16),a,i0)') 'step ', int(istep), ' ttime ', hx, &
    ' dfact ', fold_c, ' coord ', fold_x, ' mat ', fold_m, ' tload ', fold_t, &
    ' eload ', fold_e, ' rload ', fold_r, ' uu ', fold_u, ' gp ', fold_g, ' np ', int(npoin)
  write (u, '(a,i0,a,i0,a,i0,a,es24.17)') '   tload step ', int(istep), &
    ' nonzero ', nz_t, ' denormalish ', nd_t, ' max ', mx_t

  ! Step 1 only, one fold per ELEMENT: enough to name which elements differ without
  ! dumping 3200 values, and the fold is still bit-exact.
  if (int(istep) == 1 .and. allocated(element)) then
    fold_c = 0_int64
    do i = 1, size(element)
      if (.not. associated(element(i)%field)) cycle
      if (.not. associated(element(i)%field(1)%tload)) cycle
      fold_t = 0_int64
      do j = 1, size(element(i)%field(1)%tload)
        fold_t = ieor(fold_t, transfer(real(element(i)%field(1)%tload(j), kind(1.0d0)), 0_int64))
      end do
      fold_e = 0_int64
      if (associated(element(i)%field(1)%elcod_f)) then
        do j = 1, size(element(i)%field(1)%elcod_f, 1)
          do k = 1, size(element(i)%field(1)%elcod_f, 2)
            fold_e = ieor(fold_e, transfer(real(element(i)%field(1)%elcod_f(j, k), kind(1.0d0)), 0_int64))
          end do
        end do
      end if
      ! egaus(1) is the STIFFNESS gauss set: djacb (weighted jacobian), gpcod and cartd
      ! (shape gradients). build_runtime COMPUTES these and the commit writes them, while
      ! legacy computes them in its own routine -- so this is the first place two
      ! independent implementations of the same arithmetic meet.
      fold_r = 0_int64
      if (associated(element(i)%egaus)) then
        if (associated(element(i)%egaus(1)%djacb)) then
          do j = 1, size(element(i)%egaus(1)%djacb)
            fold_r = ieor(fold_r, transfer(real(element(i)%egaus(1)%djacb(j), kind(1.0d0)), 0_int64))
          end do
        end if
        if (associated(element(i)%egaus(1)%cartd)) then
          do j = 1, size(element(i)%egaus(1)%cartd, 1)
            do k = 1, size(element(i)%egaus(1)%cartd, 2)
              fold_c = ieor(fold_c, transfer(real(element(i)%egaus(1)%cartd(j, k, 1), kind(1.0d0)), 0_int64))
            end do
          end do
        end if
      end if
      write (u, '(a,i0,4(a,z16.16))') '   elt ', i, ' tload ', fold_t, &
        ' elcod ', fold_e, ' djacb ', fold_r, ' cartd ', fold_c
      ! The two elements either side of the first divergence, value by value.
      if ((i == 100 .or. i == 101) .and. associated(element(i)%egaus)) then
        if (associated(element(i)%egaus(1)%cartd)) then
          do j = 1, size(element(i)%egaus(1)%cartd, 1)
            do k = 1, size(element(i)%egaus(1)%cartd, 2)
              write (u, '(a,3(i0,a),z16.16,a,es24.17)') '   CARTD ', i, ' ', j, ' ', k, ' = ', &
                transfer(real(element(i)%egaus(1)%cartd(j, k, 1), kind(1.0d0)), 0_int64), '  ', &
                real(element(i)%egaus(1)%cartd(j, k, 1), kind(1.0d0))
            end do
          end do
          do j = 1, size(element(i)%field(1)%elcod_f, 1)
            do k = 1, size(element(i)%field(1)%elcod_f, 2)
              write (u, '(a,3(i0,a),z16.16)') '   ELCOD ', i, ' ', j, ' ', k, ' = ', &
                transfer(real(element(i)%field(1)%elcod_f(j, k), kind(1.0d0)), 0_int64)
            end do
          end do
        end if
      end if
    end do
  end if
  flush (u)

end subroutine yl_step_probe
