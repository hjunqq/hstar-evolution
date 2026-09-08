! R-order falsification probe (M4-01 planning, NOT product code).
!
! ONE question: can the legacy module reader `global_data` be driven correctly from
! outside PROGRAM FEM90? The proposed M4-01 oracle architecture depends on the answer.
!
! It replicates exactly what FEM90's main body does before `call global_data`
! (Fem.f90:94-117): set the diagnostic mode, open `inp`, read its four leading
! records, call TIME, then call global_data. Nothing else. If FEM90 establishes
! state that global_data silently depends on, this program is where it shows up.
program rorder_probe
  use variable_types, only: ink, irk
  use yl_diag, only: diag_set_mode_from_argv
  use global_var
  use materials, only: props, material_set
  implicit none

  ! `text` and `char_time` are NOT declared here: global_var already provides them,
  ! which is itself a small piece of evidence that the module carries the scratch
  ! state FEM90's prologue uses.
  integer :: ios
  integer :: n_nonzero_coord, i

  write (*, '(a)') '=== R-order probe: driving global_data outside PROGRAM FEM90 ==='

  call diag_set_mode_from_argv()

  open (inpunit, file='inp', status='old', iostat=ios)
  if (ios /= 0) then
    write (*, '(a,i0)') 'FALSIFIED(setup): cannot open inp, iostat=', ios
    stop 2
  end if
  read (inpunit, *) text
  read (inpunit, *) restart, relis, sysrelis, ADINA, Uopt_R, gamamax
  read (inpunit, *) text
  read (inpunit, *) probn
  call TIME(char_time)

  write (*, '(a,i0,a)') 'pre-call state: inp read, restart=', restart, ' probn='//trim(probn)

  ! The whole experiment is this one line.
  call global_data

  ! One step further: material_set is FEM90's very next reader call (Fem.f90:191).
  ! Included because extending the confirmed set from one reader to two costs one line;
  ! external_load_1 (:1682) and prescrib_set (:1873) sit deep in FEM90's flow and are
  ! deliberately NOT attempted here -- that is a separate, smaller question.
  call material_set
  write (*, '(a)') '--- global_data + material_set returned; observed globals ---'
  write (*, '(a,i0)') '  npoin  = ', npoin
  write (*, '(a,i0)') '  nelem  = ', nelem
  write (*, '(a,i0)') '  ndimn  = ', ndimn
  write (*, '(a,i0)') '  ngroup = ', ngroup
  write (*, '(a,i0)') '  nmats  = ', nmats
  write (*, '(a,i0)') '  mdofn  = ', mdofn
  write (*, '(a,i0)') '  cdofn  = ', cdofn
  write (*, '(a,i0)') '  ntotv  = ', ntotv

  if (allocated(coord)) then
    n_nonzero_coord = 0
    do i = 1, size(coord, 2)
      if (coord(1, i) /= 0.0_irk .or. coord(2, i) /= 0.0_irk) n_nonzero_coord = n_nonzero_coord + 1
    end do
    write (*, '(a,i0,a,i0)') '  coord allocated (', size(coord, 1), ',', size(coord, 2)
    write (*, '(a,i0)') '  coord entries not both-zero = ', n_nonzero_coord
    write (*, '(a,es22.15,a,es22.15)') '  coord(:,2) = ', coord(1, 2), ' , ', coord(2, 2)
    write (*, '(a,es22.15,a,es22.15)') '  coord(:,npoin) = ', coord(1, npoin), ' , ', coord(2, npoin)
  else
    write (*, '(a)') '  coord NOT allocated'
  end if

  if (allocated(element)) then
    write (*, '(a,i0)') '  element allocated, size = ', size(element)
    if (associated(element(1)%field)) then
      if (associated(element(1)%field(1)%lnods_f)) then
        write (*, '(a,4(i0,1x))') '  element(1)%field(1)%lnods_f = ', element(1)%field(1)%lnods_f
      end if
    end if
  else
    write (*, '(a)') '  element NOT allocated'
  end if

  if (allocated(nodfn)) then
    write (*, '(a,i0,a,i0)') '  nodfn allocated (', size(nodfn, 1), ',', size(nodfn, 2)
  else
    write (*, '(a)') '  nodfn NOT allocated'
  end if

  if (allocated(props)) then
    write (*, '(a,i0)') '  props allocated, size = ', size(props)
    ! props is a derived type carrying allocatable components; its ALLOCATION and
    ! extent are all this probe needs -- the question is whether material_set ran,
    ! not what the material values are.
  else
    write (*, '(a)') '  props NOT allocated'
  end if
  write (*, '(a)') '=== probe completed without abort ==='

end program rorder_probe
