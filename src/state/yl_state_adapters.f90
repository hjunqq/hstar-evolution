! yl_state_adapters -- handwritten M2-02 adapters.
!
! One public emit_<name>(w) per field id that the state field map marks
! emit = "adapter:<name>"; <name> is the field id with '.' replaced by '_'.
! Each routine owns every record of its field and nothing else.
!
! Observer discipline (plan-fortran.md sections 3 and 6). An adapter MUST NOT:
!   * assign a legacy global, allocate, deallocate or re-associate a legacy
!     object,
!   * call a legacy computational routine or read an input unit,
!   * reuse a legacy scratch index (igroup, ielem, ipoin, i0, ...): every loop
!     variable below is a local of the adapter.
! It may only read whitelisted, initialised legacy components and write through
! the state writer.
!
! Association discipline. Legacy pointer components have no default
! initialisation, so associated() on a pointer that was never allocated is
! undefined behaviour, not a false answer. Every parent is therefore tested
! before a child is touched, and the components listed as undefined in
! docs/m2/M2-01-checkpoints.md section 6 are never queried at all:
!   group%unode%patch_nod, props%mechanical%fluid, props%heat, props%geometry,
!   prescrib%listep, prescrib%value_ext.
! Where a count says a pointer was never allocated (listp_group%mgroup == 0,
! prescrib%lnefix == 0), the adapter emits the empty record from the count and
! does not query the pointer.
!
! Ragged fields emit one record per outer index, keyed by the 1-based outer
! tuple in lexicographic order. An outer domain of size zero emits a single
! field-presence record key=[] shape=[0], so the field id is always present.
module yl_state_adapters

  use iso_fortran_env, only: int64
  use variable_types, only: ink
  use yl_state_io, only: state_writer_t, begin_field, end_field, &
                         put_i32, put_f64, put_str, state_fail, NO_KEY, SCALAR_SHAPE
  use global_var, only: npoin, nelem, nmats, ngroup, mdofn, cdofn, nblks, &
                        lmdofn, lcdofn, group, element, listp_group, appear_process
  use materials, only: props
  use prescribed, only: prescrib, ndofix, nfixsets
  use applied_load, only: tcurves, ntcurve
  use solver, only: global_stiff1

  implicit none
  private

  public :: emit_mesh_nodes_id
  public :: emit_mesh_elements_id
  public :: emit_materials_id
  public :: emit_materials_kind
  public :: emit_materials_phase
  public :: emit_derived_counts_nphase
  public :: emit_derived_dof_active_flags
  public :: emit_sections_material_header
  public :: emit_derived_dof_lcdofn
  public :: emit_runtime_solver_stiff_length
  public :: emit_mesh_sets_elset
  public :: emit_mesh_sets_nset
  public :: emit_sections_dof_count
  public :: emit_sections_dof_list
  public :: emit_amplitudes_points_time
  public :: emit_amplitudes_points_value
  public :: emit_runtime_boundary_leldofix
  public :: emit_runtime_boundary_levdofix
  public :: emit_runtime_boundary_lefdofix
  public :: emit_runtime_topology_listp_group_listg
  public :: emit_runtime_topology_listp_group_listp
  public :: emit_runtime_topology_unode_ipoin
  public :: emit_runtime_topology_unode_ne_unode
  public :: emit_runtime_topology_unode_list
  public :: emit_steps0_activation_active

contains

  ! ------------------------------------------------------------- helpers ----
  ! Decimal text of an integer, for failure messages only.
  function ia(v) result(s)
    integer(ink), intent(in) :: v
    character(len=24) :: s
    write (s, '(i0)') v
  end function ia

  ! A count that indexes a legacy array must be non-negative.
  subroutine need_count(w, id, name, n)
    type(state_writer_t), intent(inout) :: w
    character(len=*), intent(in) :: id, name
    integer(ink), intent(in) :: n
    if (n < 0_ink) call state_fail(w, id, trim(name) // '=' // trim(ia(n)) // ' is negative')
  end subroutine need_count

  ! Empty outer domain: one field-presence record so the id is never missing.
  subroutine empty_domain(w, id, dtype)
    type(state_writer_t), intent(inout) :: w
    character(len=*), intent(in) :: id, dtype
    call begin_field(w, id, NO_KEY, [0_int64], dtype)
    call end_field(w)
  end subroutine empty_domain

  ! ---------------------------------------------------------- identifiers ----
  ! mesh.nodes.id -- 1..npoin. The deck id i0 is read into the global scratch,
  ! checked against ipoin by the M1-03 guards and never stored, so the id is
  ! the row index. The scratch i0 itself is never read here.
  subroutine emit_mesh_nodes_id(w)
    type(state_writer_t), intent(inout) :: w
    character(len=*), parameter :: id = 'mesh.nodes.id'
    integer(ink) :: i
    call need_count(w, id, 'npoin', npoin)
    call begin_field(w, id, NO_KEY, [int(npoin, int64)], 'i32')
    do i = 1_ink, npoin
      call put_i32(w, i)
    end do
    call end_field(w)
  end subroutine emit_mesh_nodes_id

  ! mesh.elements.id -- 1..nelem, the record order across groups.
  subroutine emit_mesh_elements_id(w)
    type(state_writer_t), intent(inout) :: w
    character(len=*), parameter :: id = 'mesh.elements.id'
    integer(ink) :: i
    call need_count(w, id, 'nelem', nelem)
    call begin_field(w, id, NO_KEY, [int(nelem, int64)], 'i32')
    do i = 1_ink, nelem
      call put_i32(w, i)
    end do
    call end_field(w)
  end subroutine emit_mesh_elements_id

  ! materials.id -- 1..nmats, the props(:) index.
  subroutine emit_materials_id(w)
    type(state_writer_t), intent(inout) :: w
    character(len=*), parameter :: id = 'materials.id'
    integer(ink) :: i
    call need_count(w, id, 'nmats', nmats)
    if (.not. allocated(props)) call state_fail(w, id, 'props is not allocated')
    if (int(nmats, int64) > int(size(props), int64)) then
      call state_fail(w, id, 'nmats=' // trim(ia(nmats)) // ' exceeds size(props)')
    end if
    call begin_field(w, id, NO_KEY, [int(nmats, int64)], 'i32')
    do i = 1_ink, nmats
      call put_i32(w, i)
    end do
    call end_field(w)
  end subroutine emit_materials_id

  ! ------------------------------------------------ material reconstructions ----
  ! COVERED-PATH RECONSTRUCTION. materials.kind is the material_set local
  ! `property`, which is not stored; the map defines it as 'MECHANICAL' exactly
  ! when props(imat)%mechanical is associated. That pointer has no default
  ! initialisation (Material.f90:200-205) and is only allocated at :297, so
  ! associated() on it is undefined for any deck that does not take the
  ! MECHANICAL branch. On the covered static_2d path every material takes it,
  ! so the constant below is exact here and is NOT a general reconstruction:
  ! a deck with a non-MECHANICAL material would need the reader to capture the
  ! keyword instead. Same limitation as materials.phase and
  ! derived.counts.nphase.
  subroutine emit_materials_kind(w)
    type(state_writer_t), intent(inout) :: w
    character(len=*), parameter :: id = 'materials.kind'
    integer(ink) :: i
    call need_count(w, id, 'nmats', nmats)
    if (.not. allocated(props)) call state_fail(w, id, 'props is not allocated')
    if (int(nmats, int64) > int(size(props), int64)) then
      call state_fail(w, id, 'nmats=' // trim(ia(nmats)) // ' exceeds size(props)')
    end if
    call begin_field(w, id, NO_KEY, [int(nmats, int64)], 'str')
    do i = 1_ink, nmats
      call put_str(w, 'MECHANICAL')
    end do
    call end_field(w)
  end subroutine emit_materials_kind

  ! COVERED-PATH RECONSTRUCTION, see emit_materials_kind. phase is the
  ! material_set local, 'SOLID' exactly when props%mechanical%solid is
  ! associated; that pointer is likewise uninitialised unless the SOLID branch
  ! ran (Material.f90:309), which it does for every material on this path.
  subroutine emit_materials_phase(w)
    type(state_writer_t), intent(inout) :: w
    character(len=*), parameter :: id = 'materials.phase'
    integer(ink) :: i
    call need_count(w, id, 'nmats', nmats)
    if (.not. allocated(props)) call state_fail(w, id, 'props is not allocated')
    if (int(nmats, int64) > int(size(props), int64)) then
      call state_fail(w, id, 'nmats=' // trim(ia(nmats)) // ' exceeds size(props)')
    end if
    call begin_field(w, id, NO_KEY, [int(nmats, int64)], 'str')
    do i = 1_ink, nmats
      call put_str(w, 'SOLID')
    end do
    call end_field(w)
  end subroutine emit_materials_phase

  ! COVERED-PATH RECONSTRUCTION. nphase is a material_set local (Material.f90:298)
  ! and cannot be recounted here: counting associated phase pointers would have
  ! to query props%mechanical%fluid, which has no null initialisation
  ! (Material.f90:179) and is therefore undefined on this path. The covered
  ! decks have exactly one phase (SOLID) per material, so 1 is emitted. This
  ! does NOT prove the header count of an arbitrary deck.
  subroutine emit_derived_counts_nphase(w)
    type(state_writer_t), intent(inout) :: w
    character(len=*), parameter :: id = 'derived.counts.nphase'
    integer(ink) :: i
    call need_count(w, id, 'nmats', nmats)
    if (.not. allocated(props)) call state_fail(w, id, 'props is not allocated')
    if (int(nmats, int64) > int(size(props), int64)) then
      call state_fail(w, id, 'nmats=' // trim(ia(nmats)) // ' exceeds size(props)')
    end if
    call begin_field(w, id, NO_KEY, [int(nmats, int64)], 'i32')
    do i = 1_ink, nmats
      call put_i32(w, 1_ink)
    end do
    call end_field(w)
  end subroutine emit_derived_counts_nphase

  ! ------------------------------------------------------------- dof maps ----
  ! derived.dof.active_flags -- the deck 0/1 activation flag. lmdofn is
  ! overwritten in place with the condensed index (Global.f90:1119-1125), which
  ! only rewrites non-zero entries, so zero/non-zero is preserved and the flag
  ! is merge(1, 0, lmdofn(i) /= 0).
  subroutine emit_derived_dof_active_flags(w)
    type(state_writer_t), intent(inout) :: w
    character(len=*), parameter :: id = 'derived.dof.active_flags'
    integer(ink) :: i
    call need_count(w, id, 'mdofn', mdofn)
    if (.not. allocated(lmdofn)) call state_fail(w, id, 'lmdofn is not allocated')
    if (int(mdofn, int64) > int(size(lmdofn), int64)) then
      call state_fail(w, id, 'mdofn=' // trim(ia(mdofn)) // ' exceeds size(lmdofn)')
    end if
    call begin_field(w, id, NO_KEY, [int(mdofn, int64)], 'i32')
    do i = 1_ink, mdofn
      call put_i32(w, merge(1_ink, 0_ink, lmdofn(i) /= 0_ink))
    end do
    call end_field(w)
  end subroutine emit_derived_dof_active_flags

  ! derived.dof.lcdofn -- condensed -> global dof map. lcdofn is allocated with
  ! mdofn entries (Global.f90:954) but only 1:cdofn is ever assigned (:1124);
  ! cdofn+1:mdofn is uninitialised and must never be read, so the emitted shape
  ! is [cdofn], not [mdofn].
  subroutine emit_derived_dof_lcdofn(w)
    type(state_writer_t), intent(inout) :: w
    character(len=*), parameter :: id = 'derived.dof.lcdofn'
    integer(ink) :: i
    call need_count(w, id, 'cdofn', cdofn)
    if (.not. allocated(lcdofn)) call state_fail(w, id, 'lcdofn is not allocated')
    if (int(cdofn, int64) > int(size(lcdofn), int64)) then
      call state_fail(w, id, 'cdofn=' // trim(ia(cdofn)) // ' exceeds size(lcdofn)')
    end if
    call begin_field(w, id, NO_KEY, [int(cdofn, int64)], 'i32')
    do i = 1_ink, cdofn
      call put_i32(w, lcdofn(i))
    end do
    call end_field(w)
  end subroutine emit_derived_dof_lcdofn

  ! ------------------------------------------------------------- sections ----
  ! sections.material_header -- the .glb group header matno. group%matno is
  ! overwritten in place at Fem.f90:1717, so the header value is recovered from
  ! the first element of the group, where read_element copied it
  ! (Elements.f90:1083) and never wrote it again.
  subroutine emit_sections_material_header(w)
    type(state_writer_t), intent(inout) :: w
    character(len=*), parameter :: id = 'sections.material_header'
    integer(ink) :: g, ne, e
    call need_count(w, id, 'ngroup', ngroup)
    if (.not. allocated(group)) call state_fail(w, id, 'group is not allocated')
    if (.not. allocated(element)) call state_fail(w, id, 'element is not allocated')
    if (int(ngroup, int64) > int(size(group), int64)) then
      call state_fail(w, id, 'ngroup=' // trim(ia(ngroup)) // ' exceeds size(group)')
    end if
    call begin_field(w, id, NO_KEY, [int(ngroup, int64)], 'i32')
    do g = 1_ink, ngroup
      ne = group(g)%nelgroup
      if (ne < 1_ink) call state_fail(w, id, 'group ' // trim(ia(g)) // ' has nelgroup=' // trim(ia(ne)))
      if (.not. associated(group(g)%list)) then
        call state_fail(w, id, 'group(' // trim(ia(g)) // ')%list is not associated')
      end if
      if (size(group(g)%list) < 1) call state_fail(w, id, 'group(' // trim(ia(g)) // ')%list is empty')
      e = group(g)%list(1)
      if (e < 1_ink .or. int(e, int64) > int(size(element), int64)) then
        call state_fail(w, id, 'group(' // trim(ia(g)) // ')%list(1)=' // trim(ia(e)) // ' is out of range')
      end if
      call put_i32(w, element(e)%matno)
    end do
    call end_field(w)
  end subroutine emit_sections_material_header

  ! sections.dof_count -- group(g)%dof(f)%nfdof, one record per group.
  subroutine emit_sections_dof_count(w)
    type(state_writer_t), intent(inout) :: w
    character(len=*), parameter :: id = 'sections.dof_count'
    integer(ink) :: g, f, nf
    call need_count(w, id, 'ngroup', ngroup)
    if (ngroup == 0_ink) then
      call empty_domain(w, id, 'i32')
      return
    end if
    if (.not. allocated(group)) call state_fail(w, id, 'group is not allocated')
    if (int(ngroup, int64) > int(size(group), int64)) then
      call state_fail(w, id, 'ngroup=' // trim(ia(ngroup)) // ' exceeds size(group)')
    end if
    do g = 1_ink, ngroup
      nf = group(g)%nrfields
      call need_count(w, id, 'nrfields', nf)
      if (nf > 0_ink) then
        if (.not. associated(group(g)%dof)) then
          call state_fail(w, id, 'group(' // trim(ia(g)) // ')%dof is not associated')
        end if
        if (int(nf, int64) > int(size(group(g)%dof), int64)) then
          call state_fail(w, id, 'nrfields exceeds size(group(' // trim(ia(g)) // ')%dof)')
        end if
      end if
      call begin_field(w, id, [int(g, int64)], [int(nf, int64)], 'i32')
      do f = 1_ink, nf
        call put_i32(w, group(g)%dof(f)%nfdof)
      end do
      call end_field(w)
    end do
  end subroutine emit_sections_dof_count

  ! sections.dof_list -- group(g)%dof(f)%listdof_f, one record per (group, field).
  subroutine emit_sections_dof_list(w)
    type(state_writer_t), intent(inout) :: w
    character(len=*), parameter :: id = 'sections.dof_list'
    integer(ink) :: g, f, k, nf, nd
    call need_count(w, id, 'ngroup', ngroup)
    if (ngroup == 0_ink) then
      call empty_domain(w, id, 'i32')
      return
    end if
    if (.not. allocated(group)) call state_fail(w, id, 'group is not allocated')
    if (int(ngroup, int64) > int(size(group), int64)) then
      call state_fail(w, id, 'ngroup=' // trim(ia(ngroup)) // ' exceeds size(group)')
    end if
    do g = 1_ink, ngroup
      nf = group(g)%nrfields
      call need_count(w, id, 'nrfields', nf)
      if (nf > 0_ink) then
        if (.not. associated(group(g)%dof)) then
          call state_fail(w, id, 'group(' // trim(ia(g)) // ')%dof is not associated')
        end if
        if (int(nf, int64) > int(size(group(g)%dof), int64)) then
          call state_fail(w, id, 'nrfields exceeds size(group(' // trim(ia(g)) // ')%dof)')
        end if
      end if
      do f = 1_ink, nf
        nd = group(g)%dof(f)%nfdof
        call need_count(w, id, 'nfdof', nd)
        if (nd > 0_ink) then
          if (.not. associated(group(g)%dof(f)%listdof_f)) then
            call state_fail(w, id, 'group(' // trim(ia(g)) // ')%dof(' // trim(ia(f)) // &
              ')%listdof_f is not associated')
          end if
          if (int(nd, int64) > int(size(group(g)%dof(f)%listdof_f), int64)) then
            call state_fail(w, id, 'nfdof exceeds size(listdof_f) in group ' // trim(ia(g)))
          end if
        end if
        call begin_field(w, id, [int(g, int64), int(f, int64)], [int(nd, int64)], 'i32')
        do k = 1_ink, nd
          call put_i32(w, group(g)%dof(f)%listdof_f(k))
        end do
        call end_field(w)
      end do
    end do
  end subroutine emit_sections_dof_list

  ! ----------------------------------------------------------------- sets ----
  ! mesh.sets.elset -- group(g)%list(1:nelgroup), one ordered list per group.
  subroutine emit_mesh_sets_elset(w)
    type(state_writer_t), intent(inout) :: w
    character(len=*), parameter :: id = 'mesh.sets.elset'
    integer(ink) :: g, k, ne
    call need_count(w, id, 'ngroup', ngroup)
    if (ngroup == 0_ink) then
      call empty_domain(w, id, 'i32')
      return
    end if
    if (.not. allocated(group)) call state_fail(w, id, 'group is not allocated')
    if (int(ngroup, int64) > int(size(group), int64)) then
      call state_fail(w, id, 'ngroup=' // trim(ia(ngroup)) // ' exceeds size(group)')
    end if
    do g = 1_ink, ngroup
      ne = group(g)%nelgroup
      call need_count(w, id, 'nelgroup', ne)
      if (ne > 0_ink) then
        if (.not. associated(group(g)%list)) then
          call state_fail(w, id, 'group(' // trim(ia(g)) // ')%list is not associated')
        end if
        if (int(ne, int64) > int(size(group(g)%list), int64)) then
          call state_fail(w, id, 'nelgroup exceeds size(group(' // trim(ia(g)) // ')%list)')
        end if
      end if
      call begin_field(w, id, [int(g, int64)], [int(ne, int64)], 'i32')
      do k = 1_ink, ne
        call put_i32(w, group(g)%list(k))
      end do
      call end_field(w)
    end do
  end subroutine emit_mesh_sets_elset

  ! mesh.sets.nset -- the distinct prescrib%nodfix of one ifixset, in first
  ! occurrence order. The reader local list_fix is deallocated at
  ! Prescrib.f90:386, so the set is recovered from the prescrib records. The
  ! duplicate test rescans the earlier records instead of allocating a mark
  ! array: quadratic in ndofix, acceptable at the measured boundary sizes.
  subroutine emit_mesh_sets_nset(w)
    type(state_writer_t), intent(inout) :: w
    character(len=*), parameter :: id = 'mesh.sets.nset'
    integer(ink) :: s, k, n
    call need_count(w, id, 'nfixsets', nfixsets)
    call need_count(w, id, 'ndofix', ndofix)
    if (nfixsets == 0_ink) then
      call empty_domain(w, id, 'i32')
      return
    end if
    if (ndofix > 0_ink) then
      if (.not. allocated(prescrib)) call state_fail(w, id, 'prescrib is not allocated')
      if (int(ndofix, int64) > int(size(prescrib), int64)) then
        call state_fail(w, id, 'ndofix=' // trim(ia(ndofix)) // ' exceeds size(prescrib)')
      end if
    end if
    do s = 1_ink, nfixsets
      n = 0_ink
      do k = 1_ink, ndofix
        if (prescrib(k)%ifixset /= s) cycle
        if (first_in_set(k, s)) n = n + 1_ink
      end do
      call begin_field(w, id, [int(s, int64)], [int(n, int64)], 'i32')
      do k = 1_ink, ndofix
        if (prescrib(k)%ifixset /= s) cycle
        if (first_in_set(k, s)) call put_i32(w, prescrib(k)%nodfix)
      end do
      call end_field(w)
    end do
  end subroutine emit_mesh_sets_nset

  ! .true. when record k is the first record of set s carrying its nodfix.
  logical function first_in_set(k, s)
    integer(ink), intent(in) :: k, s
    integer(ink) :: j
    first_in_set = .true.
    do j = 1_ink, k - 1_ink
      if (prescrib(j)%ifixset /= s) cycle
      if (prescrib(j)%nodfix == prescrib(k)%nodfix) then
        first_in_set = .false.
        return
      end if
    end do
  end function first_in_set

  ! ------------------------------------------------------------ amplitudes ----
  ! amplitudes.points.time -- tcurves(c)%ttime_curve(1:ntime), one list per curve.
  subroutine emit_amplitudes_points_time(w)
    type(state_writer_t), intent(inout) :: w
    character(len=*), parameter :: id = 'amplitudes.points.time'
    integer(ink) :: c, k, nt
    call need_count(w, id, 'ntcurve', ntcurve)
    if (ntcurve == 0_ink) then
      call empty_domain(w, id, 'f64')
      return
    end if
    if (.not. allocated(tcurves)) call state_fail(w, id, 'tcurves is not allocated')
    if (int(ntcurve, int64) > int(size(tcurves), int64)) then
      call state_fail(w, id, 'ntcurve=' // trim(ia(ntcurve)) // ' exceeds size(tcurves)')
    end if
    do c = 1_ink, ntcurve
      nt = tcurves(c)%ntime
      call need_count(w, id, 'ntime', nt)
      if (nt > 0_ink) then
        if (.not. associated(tcurves(c)%ttime_curve)) then
          call state_fail(w, id, 'tcurves(' // trim(ia(c)) // ')%ttime_curve is not associated')
        end if
        if (int(nt, int64) > int(size(tcurves(c)%ttime_curve), int64)) then
          call state_fail(w, id, 'ntime exceeds size(ttime_curve) in curve ' // trim(ia(c)))
        end if
      end if
      call begin_field(w, id, [int(c, int64)], [int(nt, int64)], 'f64')
      do k = 1_ink, nt
        call put_f64(w, tcurves(c)%ttime_curve(k))
      end do
      call end_field(w)
    end do
  end subroutine emit_amplitudes_points_time

  ! amplitudes.points.value -- tcurves(c)%dfact_curve(1:ntime), one list per curve.
  subroutine emit_amplitudes_points_value(w)
    type(state_writer_t), intent(inout) :: w
    character(len=*), parameter :: id = 'amplitudes.points.value'
    integer(ink) :: c, k, nt
    call need_count(w, id, 'ntcurve', ntcurve)
    if (ntcurve == 0_ink) then
      call empty_domain(w, id, 'f64')
      return
    end if
    if (.not. allocated(tcurves)) call state_fail(w, id, 'tcurves is not allocated')
    if (int(ntcurve, int64) > int(size(tcurves), int64)) then
      call state_fail(w, id, 'ntcurve=' // trim(ia(ntcurve)) // ' exceeds size(tcurves)')
    end if
    do c = 1_ink, ntcurve
      nt = tcurves(c)%ntime
      call need_count(w, id, 'ntime', nt)
      if (nt > 0_ink) then
        if (.not. associated(tcurves(c)%dfact_curve)) then
          call state_fail(w, id, 'tcurves(' // trim(ia(c)) // ')%dfact_curve is not associated')
        end if
        if (int(nt, int64) > int(size(tcurves(c)%dfact_curve), int64)) then
          call state_fail(w, id, 'ntime exceeds size(dfact_curve) in curve ' // trim(ia(c)))
        end if
      end if
      call begin_field(w, id, [int(c, int64)], [int(nt, int64)], 'f64')
      do k = 1_ink, nt
        call put_f64(w, tcurves(c)%dfact_curve(k))
      end do
      call end_field(w)
    end do
  end subroutine emit_amplitudes_points_value

  ! -------------------------------------------------------------- boundary ----
  ! The three prescrib expansion lists share one shape (lnefix per record) and
  ! one guard sequence; only the component read differs. leldofix/levdofix/
  ! lefdofix are allocated together at Prescrib.f90:334 for every record of the
  ! covered branch, including lnefix == 0, but a zero-length record is emitted
  ! from the count without querying the pointer.
  subroutine emit_runtime_boundary_leldofix(w)
    type(state_writer_t), intent(inout) :: w
    character(len=*), parameter :: id = 'runtime.boundary.leldofix'
    integer(ink) :: r, k, ne
    if (.not. boundary_domain(w, id)) return
    do r = 1_ink, ndofix
      ne = boundary_extent(w, id, r)
      if (ne > 0_ink) then
        if (.not. associated(prescrib(r)%leldofix)) then
          call state_fail(w, id, 'prescrib(' // trim(ia(r)) // ')%leldofix is not associated')
        end if
        if (int(ne, int64) > int(size(prescrib(r)%leldofix), int64)) then
          call state_fail(w, id, 'lnefix exceeds size(leldofix) in record ' // trim(ia(r)))
        end if
      end if
      call begin_field(w, id, [int(r, int64)], [int(ne, int64)], 'i32')
      do k = 1_ink, ne
        call put_i32(w, prescrib(r)%leldofix(k))
      end do
      call end_field(w)
    end do
  end subroutine emit_runtime_boundary_leldofix

  subroutine emit_runtime_boundary_levdofix(w)
    type(state_writer_t), intent(inout) :: w
    character(len=*), parameter :: id = 'runtime.boundary.levdofix'
    integer(ink) :: r, k, ne
    if (.not. boundary_domain(w, id)) return
    do r = 1_ink, ndofix
      ne = boundary_extent(w, id, r)
      if (ne > 0_ink) then
        if (.not. associated(prescrib(r)%levdofix)) then
          call state_fail(w, id, 'prescrib(' // trim(ia(r)) // ')%levdofix is not associated')
        end if
        if (int(ne, int64) > int(size(prescrib(r)%levdofix), int64)) then
          call state_fail(w, id, 'lnefix exceeds size(levdofix) in record ' // trim(ia(r)))
        end if
      end if
      call begin_field(w, id, [int(r, int64)], [int(ne, int64)], 'i32')
      do k = 1_ink, ne
        call put_i32(w, prescrib(r)%levdofix(k))
      end do
      call end_field(w)
    end do
  end subroutine emit_runtime_boundary_levdofix

  subroutine emit_runtime_boundary_lefdofix(w)
    type(state_writer_t), intent(inout) :: w
    character(len=*), parameter :: id = 'runtime.boundary.lefdofix'
    integer(ink) :: r, k, ne
    if (.not. boundary_domain(w, id)) return
    do r = 1_ink, ndofix
      ne = boundary_extent(w, id, r)
      if (ne > 0_ink) then
        if (.not. associated(prescrib(r)%lefdofix)) then
          call state_fail(w, id, 'prescrib(' // trim(ia(r)) // ')%lefdofix is not associated')
        end if
        if (int(ne, int64) > int(size(prescrib(r)%lefdofix), int64)) then
          call state_fail(w, id, 'lnefix exceeds size(lefdofix) in record ' // trim(ia(r)))
        end if
      end if
      call begin_field(w, id, [int(r, int64)], [int(ne, int64)], 'i32')
      do k = 1_ink, ne
        call put_i32(w, prescrib(r)%lefdofix(k))
      end do
      call end_field(w)
    end do
  end subroutine emit_runtime_boundary_lefdofix

  ! .false. (with the field-presence record already written) when there is no
  ! prescribed record at all; otherwise checks the prescrib array once.
  logical function boundary_domain(w, id)
    type(state_writer_t), intent(inout) :: w
    character(len=*), intent(in) :: id
    boundary_domain = .false.
    call need_count(w, id, 'ndofix', ndofix)
    if (ndofix == 0_ink) then
      call empty_domain(w, id, 'i32')
      return
    end if
    if (.not. allocated(prescrib)) call state_fail(w, id, 'prescrib is not allocated')
    if (int(ndofix, int64) > int(size(prescrib), int64)) then
      call state_fail(w, id, 'ndofix=' // trim(ia(ndofix)) // ' exceeds size(prescrib)')
    end if
    boundary_domain = .true.
  end function boundary_domain

  integer(ink) function boundary_extent(w, id, r)
    type(state_writer_t), intent(inout) :: w
    character(len=*), intent(in) :: id
    integer(ink), intent(in) :: r
    boundary_extent = prescrib(r)%lnefix
    call need_count(w, id, 'lnefix', boundary_extent)
  end function boundary_extent

  ! -------------------------------------------------------------- topology ----
  ! runtime.topology.listp_group_listg -- the group ids attached to each node.
  ! listp_group(p)%listg is only allocated when mgroup > 0 (Global.f90:1466),
  ! and the component has no null initialisation, so mgroup == 0 emits the
  ! empty record without querying the pointer.
  subroutine emit_runtime_topology_listp_group_listg(w)
    type(state_writer_t), intent(inout) :: w
    character(len=*), parameter :: id = 'runtime.topology.listp_group_listg'
    integer(ink) :: p, k, mg
    if (.not. listp_domain(w, id)) return
    do p = 1_ink, npoin
      mg = listp_group(p)%mgroup
      call need_count(w, id, 'mgroup', mg)
      if (mg > 0_ink) then
        if (.not. associated(listp_group(p)%listg)) then
          call state_fail(w, id, 'listp_group(' // trim(ia(p)) // ')%listg is not associated')
        end if
        if (int(mg, int64) > int(size(listp_group(p)%listg), int64)) then
          call state_fail(w, id, 'mgroup exceeds size(listg) at node ' // trim(ia(p)))
        end if
      end if
      call begin_field(w, id, [int(p, int64)], [int(mg, int64)], 'i32')
      do k = 1_ink, mg
        call put_i32(w, listp_group(p)%listg(k))
      end do
      call end_field(w)
    end do
  end subroutine emit_runtime_topology_listp_group_listg

  ! runtime.topology.listp_group_listp -- the position of the node inside each
  ! attached group's unode list.
  subroutine emit_runtime_topology_listp_group_listp(w)
    type(state_writer_t), intent(inout) :: w
    character(len=*), parameter :: id = 'runtime.topology.listp_group_listp'
    integer(ink) :: p, k, mg
    if (.not. listp_domain(w, id)) return
    do p = 1_ink, npoin
      mg = listp_group(p)%mgroup
      call need_count(w, id, 'mgroup', mg)
      if (mg > 0_ink) then
        if (.not. associated(listp_group(p)%listp)) then
          call state_fail(w, id, 'listp_group(' // trim(ia(p)) // ')%listp is not associated')
        end if
        if (int(mg, int64) > int(size(listp_group(p)%listp), int64)) then
          call state_fail(w, id, 'mgroup exceeds size(listp) at node ' // trim(ia(p)))
        end if
      end if
      call begin_field(w, id, [int(p, int64)], [int(mg, int64)], 'i32')
      do k = 1_ink, mg
        call put_i32(w, listp_group(p)%listp(k))
      end do
      call end_field(w)
    end do
  end subroutine emit_runtime_topology_listp_group_listp

  logical function listp_domain(w, id)
    type(state_writer_t), intent(inout) :: w
    character(len=*), intent(in) :: id
    listp_domain = .false.
    call need_count(w, id, 'npoin', npoin)
    if (npoin == 0_ink) then
      call empty_domain(w, id, 'i32')
      return
    end if
    if (.not. allocated(listp_group)) call state_fail(w, id, 'listp_group is not allocated')
    if (int(npoin, int64) > int(size(listp_group), int64)) then
      call state_fail(w, id, 'npoin=' // trim(ia(npoin)) // ' exceeds size(listp_group)')
    end if
    listp_domain = .true.
  end function listp_domain

  ! runtime.topology.unode_ipoin -- global node id of each group-local node.
  subroutine emit_runtime_topology_unode_ipoin(w)
    type(state_writer_t), intent(inout) :: w
    character(len=*), parameter :: id = 'runtime.topology.unode_ipoin'
    integer(ink) :: g, k, np
    if (.not. unode_domain(w, id)) return
    do g = 1_ink, ngroup
      np = unode_extent(w, id, g)
      call begin_field(w, id, [int(g, int64)], [int(np, int64)], 'i32')
      do k = 1_ink, np
        call put_i32(w, group(g)%unode(k)%ipoin)
      end do
      call end_field(w)
    end do
  end subroutine emit_runtime_topology_unode_ipoin

  ! runtime.topology.unode_ne_unode -- number of group elements at each node.
  subroutine emit_runtime_topology_unode_ne_unode(w)
    type(state_writer_t), intent(inout) :: w
    character(len=*), parameter :: id = 'runtime.topology.unode_ne_unode'
    integer(ink) :: g, k, np
    if (.not. unode_domain(w, id)) return
    do g = 1_ink, ngroup
      np = unode_extent(w, id, g)
      call begin_field(w, id, [int(g, int64)], [int(np, int64)], 'i32')
      do k = 1_ink, np
        call put_i32(w, group(g)%unode(k)%ne_unode)
      end do
      call end_field(w)
    end do
  end subroutine emit_runtime_topology_unode_ne_unode

  ! runtime.topology.unode_list -- the element ids attached to one group-local
  ! node; one record per (group, local node). unode%patch_nod is deliberately
  ! never touched here: it is only allocated for stabilised P/W fields
  ! (Global.f90:1441) and is undefined on this path.
  subroutine emit_runtime_topology_unode_list(w)
    type(state_writer_t), intent(inout) :: w
    character(len=*), parameter :: id = 'runtime.topology.unode_list'
    integer(ink) :: g, k, e, np, ne
    if (.not. unode_domain(w, id)) return
    do g = 1_ink, ngroup
      np = unode_extent(w, id, g)
      do k = 1_ink, np
        ne = group(g)%unode(k)%ne_unode
        call need_count(w, id, 'ne_unode', ne)
        if (ne > 0_ink) then
          if (.not. associated(group(g)%unode(k)%list)) then
            call state_fail(w, id, 'group(' // trim(ia(g)) // ')%unode(' // trim(ia(k)) // &
              ')%list is not associated')
          end if
          if (int(ne, int64) > int(size(group(g)%unode(k)%list), int64)) then
            call state_fail(w, id, 'ne_unode exceeds size(unode%list) in group ' // trim(ia(g)))
          end if
        end if
        call begin_field(w, id, [int(g, int64), int(k, int64)], [int(ne, int64)], 'i32')
        do e = 1_ink, ne
          call put_i32(w, group(g)%unode(k)%list(e))
        end do
        call end_field(w)
      end do
    end do
  end subroutine emit_runtime_topology_unode_list

  logical function unode_domain(w, id)
    type(state_writer_t), intent(inout) :: w
    character(len=*), intent(in) :: id
    unode_domain = .false.
    call need_count(w, id, 'ngroup', ngroup)
    if (ngroup == 0_ink) then
      call empty_domain(w, id, 'i32')
      return
    end if
    if (.not. allocated(group)) call state_fail(w, id, 'group is not allocated')
    if (int(ngroup, int64) > int(size(group), int64)) then
      call state_fail(w, id, 'ngroup=' // trim(ia(ngroup)) // ' exceeds size(group)')
    end if
    unode_domain = .true.
  end function unode_domain

  integer(ink) function unode_extent(w, id, g)
    type(state_writer_t), intent(inout) :: w
    character(len=*), intent(in) :: id
    integer(ink), intent(in) :: g
    unode_extent = group(g)%np_unode
    call need_count(w, id, 'np_unode', unode_extent)
    if (unode_extent > 0_ink) then
      if (.not. associated(group(g)%unode)) then
        call state_fail(w, id, 'group(' // trim(ia(g)) // ')%unode is not associated')
      end if
      if (int(unode_extent, int64) > int(size(group(g)%unode), int64)) then
        call state_fail(w, id, 'np_unode exceeds size(group(' // trim(ia(g)) // ')%unode)')
      end if
    end if
  end function unode_extent

  ! ---------------------------------------------------------------- solver ----
  ! runtime.solver.stiff_length -- size(global_stiff1) = iseq(neq), the skyline
  ! profile length. Only the length is read; no stiffness value is touched.
  ! phase_ready(1) checkpoint.
  subroutine emit_runtime_solver_stiff_length(w)
    type(state_writer_t), intent(inout) :: w
    character(len=*), parameter :: id = 'runtime.solver.stiff_length'
    integer(int64) :: n
    if (.not. allocated(global_stiff1)) call state_fail(w, id, 'global_stiff1 is not allocated')
    n = int(size(global_stiff1, kind=int64), int64)
    if (n > int(huge(0_ink), int64)) then
      call state_fail(w, id, 'size(global_stiff1) does not fit in a 32-bit value')
    end if
    call begin_field(w, id, NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, int(n, ink))
    call end_field(w)
  end subroutine emit_runtime_solver_stiff_length

  ! ------------------------------------------------------------ activation ----
  ! steps0.activation.active -- appear_process(1:ngroup, 0:nblks), dense in
  ! Fortran (column-major) order. The block dimension is declared from 0, and
  ! column 0 is part of the value: it is zeroed at Global.f90:968 and consumed
  ! at Fem.f90:1719-1720 as appear_process(igroup, iblks-1) with iblks = 1, so
  ! a 1-based traversal would drop it. The declared extent nblks1 is nblks + 1.
  subroutine emit_steps0_activation_active(w)
    type(state_writer_t), intent(inout) :: w
    character(len=*), parameter :: id = 'steps0.activation.active'
    integer(ink) :: g, b
    call need_count(w, id, 'ngroup', ngroup)
    call need_count(w, id, 'nblks', nblks)
    if (.not. allocated(appear_process)) call state_fail(w, id, 'appear_process is not allocated')
    if (lbound(appear_process, 1) /= 1 .or. lbound(appear_process, 2) /= 0) then
      call state_fail(w, id, 'appear_process does not have the expected (1:ngroup, 0:nblks) bounds')
    end if
    if (int(ngroup, int64) > int(ubound(appear_process, 1), int64) .or. &
        int(nblks, int64) > int(ubound(appear_process, 2), int64)) then
      call state_fail(w, id, 'ngroup/nblks exceed the bounds of appear_process')
    end if
    call begin_field(w, id, NO_KEY, [int(ngroup, int64), int(nblks, int64) + 1_int64], 'i32')
    do b = 0_ink, nblks
      do g = 1_ink, ngroup
        call put_i32(w, appear_process(g, b))
      end do
    end do
    call end_field(w)
  end subroutine emit_steps0_activation_active

end module yl_state_adapters
