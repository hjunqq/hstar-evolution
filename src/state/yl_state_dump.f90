! yl_state_serializer -- checkpoint state dump for the legacy YL solver (M2-02).
!
! GENERATED FILE -- DO NOT EDIT BY HAND.
! Source : docs/m2/state-field-map.toml (sha256 fcbfe41b1424)
! Command: python3 tools/yl_state_map.py gen-fortran -o src/state/yl_state_dump.f90
!
! One private routine per covered checkpoint; every non-ignore field of that checkpoint is
! emitted once, in state-field-map.toml order. `emit = "generated"` rows traverse their
! legacy symbol directly (dense, Fortran order, one guard statement per parent);
! `emit = "adapter:<name>"` rows delegate to emit_<name> in yl_state_adapters.
! Writing nothing and changing nothing when yl_dump_enabled is .false. is part of the
! contract: the dispatcher returns before any unit is opened. state_open sanitizes the
! checkpoint id into the snapshot directory name; the header keeps the raw id.
module yl_state_serializer
  use, intrinsic :: iso_fortran_env, only: int64
  use yl_diag, only: yl_dump_enabled, yl_dump_dir
  use yl_state_io
  use yl_state_adapters
  use applied_load, only: delgroup, edge_load_group, factg, gravy, nbeamload, nedge, nplateload, nplgroup, ntcurve, tcurvegravity, &
    tcurves
  use global_var, only: ADINA, appear, average_appear, block_stab, Bparameter, cdofn, coord, ditime, ebody, element, fixed, gid_a, &
    gid_bcs, gid_bem, gid_ep, gid_f, gid_FC, gid_ms, gid_Mxy, gid_Ns, gid_P, gid_Pv, gid_rot, gid_s, gid_Ss, gid_T, gid_u, gid_v, &
    gid_wh, gid_wv, gid_Y, group, iblks, iffix, iincs, inc_step, lblks, lincs, listp_group, lmdofn, matno_process, mdofn, miter, &
    nbackf, nblks, ndimn, nelem, NGRAV, ngroup, nincs, ninit, nlayer, nlinks, nmats, nodfn, nonsym, noutf, noutn, npoin, npoinb, &
    nresta, nsmat, nstep, ntotv, ntrans, outplot, probn, Qstatic, relis, restart, result_zero, runblks, stab_matde, state_change, &
    stfor, tofor, toforl, toform, toler_force, toler_var, trans, trstep, ttime, type_ABC, type_load, type_nl, type_problem, &
    type_solver, uinitial
  use materials, only: props
  use meshfine, only: ice0
  use prescribed, only: ndofix, nfixsets, prescrib
  use solver, only: iafile, icond, ipdchk, iseq, ising, neq, operation, totveq
  use temperature, only: npipe, ntedge, ntelgroup, ntemp_surface
  implicit none
  private
  public :: yl_state_dump

contains

  subroutine yl_state_dump(checkpoint)
    character(len=*), intent(in) :: checkpoint
    type(state_writer_t) :: w

    if (.not. yl_dump_enabled) return
    select case (trim(checkpoint))
    case ('model_ready')
      call state_open(w, yl_dump_dir, 'model_ready', 162)
      call dump_model_ready(w)
      call state_close(w, 162)
    case ('phase_ready(1)')
      call state_open(w, yl_dump_dir, 'phase_ready(1)', 11)
      call dump_phase_ready_1(w)
      call state_close(w, 11)
    case ('increment_ready(1,1)')
      call state_open(w, yl_dump_dir, 'increment_ready(1,1)', 17)
      call dump_increment_ready_1_1(w)
      call state_close(w, 17)
    case default
      call state_fail(w, '', 'yl_state_dump called with an unregistered checkpoint: '//trim(checkpoint))
    end select
  end subroutine yl_state_dump

  ! model_ready: 162 fields
  subroutine dump_model_ready(w)
    type(state_writer_t), intent(inout) :: w
    integer :: d1, d2, d3, d4
    integer :: n1, n2, n3

    ! case.name  <- global_var.probn
    call begin_field(w, 'case.name', NO_KEY, SCALAR_SHAPE, 'str')
    call put_str(w, probn)
    call end_field(w)
    ! control.run.restart  <- global_var.restart
    call begin_field(w, 'control.run.restart', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, restart)
    call end_field(w)
    ! control.run.relis  <- global_var.relis
    call begin_field(w, 'control.run.relis', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, relis)
    call end_field(w)
    ! control.run.adina  <- global_var.ADINA
    call begin_field(w, 'control.run.adina', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, ADINA)
    call end_field(w)
    ! derived.counts.runblks  <- global_var.runblks
    call begin_field(w, 'derived.counts.runblks', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, runblks)
    call end_field(w)
    ! derived.counts.npoin  <- global_var.npoin
    call begin_field(w, 'derived.counts.npoin', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, npoin)
    call end_field(w)
    ! derived.counts.npoinb  <- global_var.npoinb
    call begin_field(w, 'derived.counts.npoinb', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, npoinb)
    call end_field(w)
    ! derived.counts.nelem  <- global_var.nelem
    call begin_field(w, 'derived.counts.nelem', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, nelem)
    call end_field(w)
    ! mesh.dimension  <- global_var.ndimn
    call begin_field(w, 'mesh.dimension', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, ndimn)
    call end_field(w)
    ! derived.counts.nmats  <- global_var.nmats
    call begin_field(w, 'derived.counts.nmats', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, nmats)
    call end_field(w)
    ! derived.counts.ngroup  <- global_var.ngroup
    call begin_field(w, 'derived.counts.ngroup', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, ngroup)
    call end_field(w)
    ! steps0.output.format  <- global_var.outplot
    call begin_field(w, 'steps0.output.format', NO_KEY, SCALAR_SHAPE, 'str')
    call put_str(w, outplot)
    call end_field(w)
    ! mesh.nodes.id  <- emit_mesh_nodes_id (handwritten adapter)
    call emit_mesh_nodes_id(w)
    ! mesh.nodes.xyz  <- global_var.coord
    if (.not. allocated(coord)) call state_fail(w, 'mesh.nodes.xyz', 'coord is not allocated')
    call begin_field(w, 'mesh.nodes.xyz', NO_KEY, [integer(int64) :: int(size(coord, 1), int64), int(size(coord, 2), int64)], 'f64')
    do d2 = 1, size(coord, 2)
      do d1 = 1, size(coord, 1)
        call put_f64(w, coord(d1, d2))
      end do
    end do
    call end_field(w)
    ! mesh.elements.id  <- emit_mesh_elements_id (handwritten adapter)
    call emit_mesh_elements_id(w)
    ! mesh.elements.nodes  <- global_var.element%field%lnods_f
    if (.not. allocated(element)) call state_fail(w, 'mesh.elements.nodes', 'element is not allocated')
    n1 = 0
    if (size(element) >= 1) then
      if (.not. associated(element(1)%field)) call state_fail(w, 'mesh.elements.nodes', 'element(1)%field is not associated')
      if (size(element(1)%field) < 1) call state_fail(w, 'mesh.elements.nodes', 'element(1)%field is empty')
      if (.not. associated(element(1)%field(1)%lnods_f)) call state_fail(w, 'mesh.elements.nodes', &
        'element(1)%field(1)%lnods_f is not associated')
      n1 = size(element(1)%field(1)%lnods_f)
    end if
    call begin_field(w, 'mesh.elements.nodes', NO_KEY, [integer(int64) :: int(n1, int64), int(size(element), int64)], 'i32')
    do d2 = 1, size(element)
      if (.not. associated(element(d2)%field)) call state_fail(w, 'mesh.elements.nodes', 'element(d2)%field is not associated')
      if (size(element(d2)%field) < 1) call state_fail(w, 'mesh.elements.nodes', 'element(d2)%field is empty')
      if (.not. associated(element(d2)%field(1)%lnods_f)) call state_fail(w, 'mesh.elements.nodes', &
        'element(d2)%field(1)%lnods_f is not associated')
      if (size(element(d2)%field(1)%lnods_f) /= n1) call state_fail(w, 'mesh.elements.nodes', &
        'element(d2)%field(1)%lnods_f extent 1 is ragged')
      do d1 = 1, n1
        call put_i32(w, element(d2)%field(1)%lnods_f(d1))
      end do
    end do
    call end_field(w)
    ! mesh.elements.kind  <- global_var.element%index
    if (.not. allocated(element)) call state_fail(w, 'mesh.elements.kind', 'element is not allocated')
    call begin_field(w, 'mesh.elements.kind', NO_KEY, [integer(int64) :: int(size(element), int64)], 'i32')
    do d1 = 1, size(element)
      call put_i32(w, element(d1)%index)
    end do
    call end_field(w)
    ! mesh.elements.group  <- global_var.element%group
    if (.not. allocated(element)) call state_fail(w, 'mesh.elements.group', 'element is not allocated')
    call begin_field(w, 'mesh.elements.group', NO_KEY, [integer(int64) :: int(size(element), int64)], 'i32')
    do d1 = 1, size(element)
      call put_i32(w, element(d1)%group)
    end do
    call end_field(w)
    ! mesh.elements.material  <- global_var.element%matno
    if (.not. allocated(element)) call state_fail(w, 'mesh.elements.material', 'element is not allocated')
    call begin_field(w, 'mesh.elements.material', NO_KEY, [integer(int64) :: int(size(element), int64)], 'i32')
    do d1 = 1, size(element)
      call put_i32(w, element(d1)%matno)
    end do
    call end_field(w)
    ! mesh.sets.elset  <- emit_mesh_sets_elset (handwritten adapter)
    call emit_mesh_sets_elset(w)
    ! mesh.sets.nset  <- emit_mesh_sets_nset (handwritten adapter)
    call emit_mesh_sets_nset(w)
    ! materials.id  <- emit_materials_id (handwritten adapter)
    call emit_materials_id(w)
    ! materials.kind  <- emit_materials_kind (handwritten adapter)
    call emit_materials_kind(w)
    ! materials.name  <- materials.props%name
    if (.not. allocated(props)) call state_fail(w, 'materials.name', 'props is not allocated')
    call begin_field(w, 'materials.name', NO_KEY, [integer(int64) :: int(size(props), int64)], 'str')
    do d1 = 1, size(props)
      call put_str(w, props(d1)%name)
    end do
    call end_field(w)
    ! derived.counts.nphase  <- emit_derived_counts_nphase (handwritten adapter)
    call emit_derived_counts_nphase(w)
    ! materials.phase  <- emit_materials_phase (handwritten adapter)
    call emit_materials_phase(w)
    ! materials.model  <- materials.props%mechanical%solid%material
    if (.not. allocated(props)) call state_fail(w, 'materials.model', 'props is not allocated')
    call begin_field(w, 'materials.model', NO_KEY, [integer(int64) :: int(size(props), int64)], 'str')
    do d1 = 1, size(props)
      if (.not. associated(props(d1)%mechanical)) call state_fail(w, 'materials.model', 'props(d1)%mechanical is not associated')
      if (.not. associated(props(d1)%mechanical%solid)) call state_fail(w, 'materials.model', &
        'props(d1)%mechanical%solid is not associated')
      call put_str(w, props(d1)%mechanical%solid%material)
    end do
    call end_field(w)
    ! materials.density  <- materials.props%mechanical%solid%density
    if (.not. allocated(props)) call state_fail(w, 'materials.density', 'props is not allocated')
    call begin_field(w, 'materials.density', NO_KEY, [integer(int64) :: int(size(props), int64)], 'f64')
    do d1 = 1, size(props)
      if (.not. associated(props(d1)%mechanical)) call state_fail(w, 'materials.density', 'props(d1)%mechanical is not associated')
      if (.not. associated(props(d1)%mechanical%solid)) call state_fail(w, 'materials.density', &
        'props(d1)%mechanical%solid is not associated')
      call put_f64(w, props(d1)%mechanical%solid%density)
    end do
    call end_field(w)
    ! materials.ratio  <- materials.props%mechanical%solid%ratio
    if (.not. allocated(props)) call state_fail(w, 'materials.ratio', 'props is not allocated')
    call begin_field(w, 'materials.ratio', NO_KEY, [integer(int64) :: int(size(props), int64)], 'f64')
    do d1 = 1, size(props)
      if (.not. associated(props(d1)%mechanical)) call state_fail(w, 'materials.ratio', 'props(d1)%mechanical is not associated')
      if (.not. associated(props(d1)%mechanical%solid)) call state_fail(w, 'materials.ratio', &
        'props(d1)%mechanical%solid is not associated')
      call put_f64(w, props(d1)%mechanical%solid%ratio)
    end do
    call end_field(w)
    ! sections.thickness  <- materials.props%mechanical%solid%thickness
    if (.not. allocated(props)) call state_fail(w, 'sections.thickness', 'props is not allocated')
    call begin_field(w, 'sections.thickness', NO_KEY, [integer(int64) :: int(size(props), int64)], 'f64')
    do d1 = 1, size(props)
      if (.not. associated(props(d1)%mechanical)) call state_fail(w, 'sections.thickness', 'props(d1)%mechanical is not associated')
      if (.not. associated(props(d1)%mechanical%solid)) call state_fail(w, 'sections.thickness', &
        'props(d1)%mechanical%solid is not associated')
      call put_f64(w, props(d1)%mechanical%solid%thickness)
    end do
    call end_field(w)
    ! materials.E  <- materials.props%mechanical%solid%e
    if (.not. allocated(props)) call state_fail(w, 'materials.E', 'props is not allocated')
    call begin_field(w, 'materials.E', NO_KEY, [integer(int64) :: int(size(props), int64)], 'f64')
    do d1 = 1, size(props)
      if (.not. associated(props(d1)%mechanical)) call state_fail(w, 'materials.E', 'props(d1)%mechanical is not associated')
      if (.not. associated(props(d1)%mechanical%solid)) call state_fail(w, 'materials.E', &
        'props(d1)%mechanical%solid is not associated')
      call put_f64(w, props(d1)%mechanical%solid%e)
    end do
    call end_field(w)
    ! materials.nu  <- materials.props%mechanical%solid%nu
    if (.not. allocated(props)) call state_fail(w, 'materials.nu', 'props is not allocated')
    call begin_field(w, 'materials.nu', NO_KEY, [integer(int64) :: int(size(props), int64)], 'f64')
    do d1 = 1, size(props)
      if (.not. associated(props(d1)%mechanical)) call state_fail(w, 'materials.nu', 'props(d1)%mechanical is not associated')
      if (.not. associated(props(d1)%mechanical%solid)) call state_fail(w, 'materials.nu', &
        'props(d1)%mechanical%solid is not associated')
      call put_f64(w, props(d1)%mechanical%solid%nu)
    end do
    call end_field(w)
    ! materials.thermal_expansion  <- materials.props%mechanical%solid%alfa
    if (.not. allocated(props)) call state_fail(w, 'materials.thermal_expansion', 'props is not allocated')
    call begin_field(w, 'materials.thermal_expansion', NO_KEY, [integer(int64) :: int(size(props), int64)], 'f64')
    do d1 = 1, size(props)
      if (.not. associated(props(d1)%mechanical)) call state_fail(w, 'materials.thermal_expansion', &
        'props(d1)%mechanical is not associated')
      if (.not. associated(props(d1)%mechanical%solid)) call state_fail(w, 'materials.thermal_expansion', &
        'props(d1)%mechanical%solid is not associated')
      call put_f64(w, props(d1)%mechanical%solid%alfa)
    end do
    call end_field(w)
    ! materials.icreep  <- materials.props%mechanical%solid%icreep
    if (.not. allocated(props)) call state_fail(w, 'materials.icreep', 'props is not allocated')
    call begin_field(w, 'materials.icreep', NO_KEY, [integer(int64) :: int(size(props), int64)], 'i32')
    do d1 = 1, size(props)
      if (.not. associated(props(d1)%mechanical)) call state_fail(w, 'materials.icreep', 'props(d1)%mechanical is not associated')
      if (.not. associated(props(d1)%mechanical%solid)) call state_fail(w, 'materials.icreep', &
        'props(d1)%mechanical%solid is not associated')
      call put_i32(w, props(d1)%mechanical%solid%icreep)
    end do
    call end_field(w)
    ! materials.kind_wt  <- materials.props%mechanical%solid%kind_wt
    if (.not. allocated(props)) call state_fail(w, 'materials.kind_wt', 'props is not allocated')
    call begin_field(w, 'materials.kind_wt', NO_KEY, [integer(int64) :: int(size(props), int64)], 'i32')
    do d1 = 1, size(props)
      if (.not. associated(props(d1)%mechanical)) call state_fail(w, 'materials.kind_wt', 'props(d1)%mechanical is not associated')
      if (.not. associated(props(d1)%mechanical%solid)) call state_fail(w, 'materials.kind_wt', &
        'props(d1)%mechanical%solid is not associated')
      call put_i32(w, props(d1)%mechanical%solid%kind_wt)
    end do
    call end_field(w)
    ! materials.jliqu  <- materials.props%mechanical%solid%jliqu
    if (.not. allocated(props)) call state_fail(w, 'materials.jliqu', 'props is not allocated')
    call begin_field(w, 'materials.jliqu', NO_KEY, [integer(int64) :: int(size(props), int64)], 'i32')
    do d1 = 1, size(props)
      if (.not. associated(props(d1)%mechanical)) call state_fail(w, 'materials.jliqu', 'props(d1)%mechanical is not associated')
      if (.not. associated(props(d1)%mechanical%solid)) call state_fail(w, 'materials.jliqu', &
        'props(d1)%mechanical%solid is not associated')
      call put_i32(w, props(d1)%mechanical%solid%jliqu)
    end do
    call end_field(w)
    ! sections.element  <- global_var.group%name
    if (.not. allocated(group)) call state_fail(w, 'sections.element', 'group is not allocated')
    call begin_field(w, 'sections.element', NO_KEY, [integer(int64) :: int(size(group), int64)], 'str')
    do d1 = 1, size(group)
      call put_str(w, group(d1)%name)
    end do
    call end_field(w)
    ! sections.name  <- global_var.group%kname
    if (.not. allocated(group)) call state_fail(w, 'sections.name', 'group is not allocated')
    call begin_field(w, 'sections.name', NO_KEY, [integer(int64) :: int(size(group), int64)], 'str')
    do d1 = 1, size(group)
      call put_str(w, group(d1)%kname)
    end do
    call end_field(w)
    ! sections.element_kind  <- global_var.group%index
    if (.not. allocated(group)) call state_fail(w, 'sections.element_kind', 'group is not allocated')
    call begin_field(w, 'sections.element_kind', NO_KEY, [integer(int64) :: int(size(group), int64)], 'i32')
    do d1 = 1, size(group)
      call put_i32(w, group(d1)%index)
    end do
    call end_field(w)
    ! sections.class  <- global_var.group%class
    if (.not. allocated(group)) call state_fail(w, 'sections.class', 'group is not allocated')
    call begin_field(w, 'sections.class', NO_KEY, [integer(int64) :: int(size(group), int64)], 'str')
    do d1 = 1, size(group)
      call put_str(w, group(d1)%class)
    end do
    call end_field(w)
    ! derived.counts.nrfields  <- global_var.group%nrfields
    if (.not. allocated(group)) call state_fail(w, 'derived.counts.nrfields', 'group is not allocated')
    call begin_field(w, 'derived.counts.nrfields', NO_KEY, [integer(int64) :: int(size(group), int64)], 'i32')
    do d1 = 1, size(group)
      call put_i32(w, group(d1)%nrfields)
    end do
    call end_field(w)
    ! sections.fields  <- global_var.group%fieldid
    if (.not. allocated(group)) call state_fail(w, 'sections.fields', 'group is not allocated')
    call begin_field(w, 'sections.fields', NO_KEY, [integer(int64) :: int(size(group), int64)], 'str')
    do d1 = 1, size(group)
      call put_str(w, group(d1)%fieldid)
    end do
    call end_field(w)
    ! sections.special  <- global_var.group%special
    if (.not. allocated(group)) call state_fail(w, 'sections.special', 'group is not allocated')
    call begin_field(w, 'sections.special', NO_KEY, [integer(int64) :: int(size(group), int64)], 'str')
    do d1 = 1, size(group)
      call put_str(w, group(d1)%special)
    end do
    call end_field(w)
    ! sections.formulation  <- global_var.group%sptype
    if (.not. allocated(group)) call state_fail(w, 'sections.formulation', 'group is not allocated')
    call begin_field(w, 'sections.formulation', NO_KEY, [integer(int64) :: int(size(group), int64)], 'str')
    do d1 = 1, size(group)
      call put_str(w, group(d1)%sptype)
    end do
    call end_field(w)
    ! sections.elset_size  <- global_var.group%nelgroup
    if (.not. allocated(group)) call state_fail(w, 'sections.elset_size', 'group is not allocated')
    call begin_field(w, 'sections.elset_size', NO_KEY, [integer(int64) :: int(size(group), int64)], 'i32')
    do d1 = 1, size(group)
      call put_i32(w, group(d1)%nelgroup)
    end do
    call end_field(w)
    ! sections.material_header  <- emit_sections_material_header (handwritten adapter)
    call emit_sections_material_header(w)
    ! sections.material  <- global_var.group%matno
    if (.not. allocated(group)) call state_fail(w, 'sections.material', 'group is not allocated')
    call begin_field(w, 'sections.material', NO_KEY, [integer(int64) :: int(size(group), int64)], 'i32')
    do d1 = 1, size(group)
      call put_i32(w, group(d1)%matno)
    end do
    call end_field(w)
    ! sections.type_nalgo  <- global_var.group%type_nalgo
    if (.not. allocated(group)) call state_fail(w, 'sections.type_nalgo', 'group is not allocated')
    call begin_field(w, 'sections.type_nalgo', NO_KEY, [integer(int64) :: int(size(group), int64)], 'i32')
    do d1 = 1, size(group)
      call put_i32(w, group(d1)%type_nalgo)
    end do
    call end_field(w)
    ! sections.type_stiff  <- global_var.group%type_stiff
    if (.not. allocated(group)) call state_fail(w, 'sections.type_stiff', 'group is not allocated')
    call begin_field(w, 'sections.type_stiff', NO_KEY, [integer(int64) :: int(size(group), int64)], 'i32')
    do d1 = 1, size(group)
      call put_i32(w, group(d1)%type_stiff)
    end do
    call end_field(w)
    ! sections.type_ecoint  <- global_var.group%type_ecoint
    if (.not. allocated(group)) call state_fail(w, 'sections.type_ecoint', 'group is not allocated')
    call begin_field(w, 'sections.type_ecoint', NO_KEY, [integer(int64) :: int(size(group), int64)], 'i32')
    do d1 = 1, size(group)
      call put_i32(w, group(d1)%type_ecoint)
    end do
    call end_field(w)
    ! sections.ilayer  <- global_var.group%ilayer
    if (.not. allocated(group)) call state_fail(w, 'sections.ilayer', 'group is not allocated')
    call begin_field(w, 'sections.ilayer', NO_KEY, [integer(int64) :: int(size(group), int64)], 'i32')
    do d1 = 1, size(group)
      call put_i32(w, group(d1)%ilayer)
    end do
    call end_field(w)
    ! sections.elcod_local  <- global_var.group%elcod_local
    if (.not. allocated(group)) call state_fail(w, 'sections.elcod_local', 'group is not allocated')
    call begin_field(w, 'sections.elcod_local', NO_KEY, [integer(int64) :: int(size(group), int64)], 'f64')
    do d1 = 1, size(group)
      call put_f64(w, group(d1)%elcod_local)
    end do
    call end_field(w)
    ! sections.uplift_ic  <- global_var.group%uplift_ic
    if (.not. allocated(group)) call state_fail(w, 'sections.uplift_ic', 'group is not allocated')
    call begin_field(w, 'sections.uplift_ic', NO_KEY, [integer(int64) :: int(size(group), int64)], 'i32')
    do d1 = 1, size(group)
      call put_i32(w, group(d1)%uplift_ic)
    end do
    call end_field(w)
    ! sections.liquj  <- global_var.group%liquj
    if (.not. allocated(group)) call state_fail(w, 'sections.liquj', 'group is not allocated')
    call begin_field(w, 'sections.liquj', NO_KEY, [integer(int64) :: int(size(group), int64)], 'i32')
    do d1 = 1, size(group)
      call put_i32(w, group(d1)%liquj)
    end do
    call end_field(w)
    ! sections.dof_count  <- emit_sections_dof_count (handwritten adapter)
    call emit_sections_dof_count(w)
    ! sections.dof_list  <- emit_sections_dof_list (handwritten adapter)
    call emit_sections_dof_list(w)
    ! derived.counts.nstre  <- global_var.group%nstre
    if (.not. allocated(group)) call state_fail(w, 'derived.counts.nstre', 'group is not allocated')
    call begin_field(w, 'derived.counts.nstre', NO_KEY, [integer(int64) :: int(size(group), int64)], 'i32')
    do d1 = 1, size(group)
      call put_i32(w, group(d1)%nstre)
    end do
    call end_field(w)
    ! derived.counts.ntcurve  <- applied_load.ntcurve
    call begin_field(w, 'derived.counts.ntcurve', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, ntcurve)
    call end_field(w)
    ! amplitudes.points.count  <- applied_load.tcurves%ntime
    if (.not. allocated(tcurves)) call state_fail(w, 'amplitudes.points.count', 'tcurves is not allocated')
    call begin_field(w, 'amplitudes.points.count', NO_KEY, [integer(int64) :: int(size(tcurves), int64)], 'i32')
    do d1 = 1, size(tcurves)
      call put_i32(w, tcurves(d1)%ntime)
    end do
    call end_field(w)
    ! amplitudes.type  <- applied_load.tcurves%type_curve
    if (.not. allocated(tcurves)) call state_fail(w, 'amplitudes.type', 'tcurves is not allocated')
    call begin_field(w, 'amplitudes.type', NO_KEY, [integer(int64) :: int(size(tcurves), int64)], 'str')
    do d1 = 1, size(tcurves)
      call put_str(w, tcurves(d1)%type_curve)
    end do
    call end_field(w)
    ! amplitudes.points.time  <- emit_amplitudes_points_time (handwritten adapter)
    call emit_amplitudes_points_time(w)
    ! amplitudes.points.value  <- emit_amplitudes_points_value (handwritten adapter)
    call emit_amplitudes_points_value(w)
    ! runtime.amplitudes.dfact  <- applied_load.tcurves%dfact
    if (.not. allocated(tcurves)) call state_fail(w, 'runtime.amplitudes.dfact', 'tcurves is not allocated')
    call begin_field(w, 'runtime.amplitudes.dfact', NO_KEY, [integer(int64) :: int(size(tcurves), int64)], 'f64')
    do d1 = 1, size(tcurves)
      call put_f64(w, tcurves(d1)%dfact)
    end do
    call end_field(w)
    ! steps0.procedure  <- global_var.type_problem
    call begin_field(w, 'steps0.procedure', NO_KEY, SCALAR_SHAPE, 'str')
    call put_str(w, type_problem)
    call end_field(w)
    ! solver.linear  <- global_var.type_solver
    call begin_field(w, 'solver.linear', NO_KEY, SCALAR_SHAPE, 'str')
    call put_str(w, type_solver)
    call end_field(w)
    ! steps0.load_mode  <- global_var.type_load
    call begin_field(w, 'steps0.load_mode', NO_KEY, SCALAR_SHAPE, 'str')
    call put_str(w, type_load)
    call end_field(w)
    ! steps0.controls.nonlinear_type  <- global_var.type_nl
    call begin_field(w, 'steps0.controls.nonlinear_type', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, type_nl)
    call end_field(w)
    ! control.glb.nlayer  <- global_var.nlayer
    call begin_field(w, 'control.glb.nlayer', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, nlayer)
    call end_field(w)
    ! control.glb.block_stab  <- global_var.block_stab
    call begin_field(w, 'control.glb.block_stab', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, block_stab)
    call end_field(w)
    ! control.glb.nbackf  <- global_var.nbackf
    call begin_field(w, 'control.glb.nbackf', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, nbackf)
    call end_field(w)
    ! control.glb.ebody  <- global_var.ebody
    call begin_field(w, 'control.glb.ebody', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, ebody)
    call end_field(w)
    ! control.glb.ninit  <- global_var.ninit
    call begin_field(w, 'control.glb.ninit', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, ninit)
    call end_field(w)
    ! control.glb.uinitial  <- global_var.uinitial
    if (.not. allocated(uinitial)) call state_fail(w, 'control.glb.uinitial', 'uinitial is not allocated')
    call begin_field(w, 'control.glb.uinitial', NO_KEY, [integer(int64) :: int(size(uinitial), int64)], 'i32')
    do d1 = 1, size(uinitial)
      call put_i32(w, uinitial(d1))
    end do
    call end_field(w)
    ! control.glb.state_change  <- global_var.state_change
    call begin_field(w, 'control.glb.state_change', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, state_change)
    call end_field(w)
    ! control.glb.bparameter  <- global_var.Bparameter
    call begin_field(w, 'control.glb.bparameter', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, Bparameter)
    call end_field(w)
    ! control.glb.stab_matde  <- global_var.stab_matde
    call begin_field(w, 'control.glb.stab_matde', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, stab_matde)
    call end_field(w)
    ! derived.counts.nblks  <- global_var.nblks
    call begin_field(w, 'derived.counts.nblks', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, nblks)
    call end_field(w)
    ! control.glb.nlinks  <- global_var.nlinks
    call begin_field(w, 'control.glb.nlinks', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, nlinks)
    call end_field(w)
    ! solver.symmetric  <- global_var.nonsym
    call begin_field(w, 'solver.symmetric', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, nonsym)
    call end_field(w)
    ! interactions.absorbing.type  <- global_var.type_ABC
    call begin_field(w, 'interactions.absorbing.type', NO_KEY, SCALAR_SHAPE, 'str')
    call put_str(w, type_ABC)
    call end_field(w)
    ! derived.counts.nsmat  <- global_var.nsmat
    call begin_field(w, 'derived.counts.nsmat', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, nsmat)
    call end_field(w)
    ! steps0.load.gravity.enabled  <- global_var.NGRAV
    call begin_field(w, 'steps0.load.gravity.enabled', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, NGRAV)
    call end_field(w)
    ! derived.counts.mdofn  <- global_var.mdofn
    call begin_field(w, 'derived.counts.mdofn', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, mdofn)
    call end_field(w)
    ! derived.dof.active_flags  <- emit_derived_dof_active_flags (handwritten adapter)
    call emit_derived_dof_active_flags(w)
    ! runtime.dof.lmdofn  <- global_var.lmdofn
    if (.not. allocated(lmdofn)) call state_fail(w, 'runtime.dof.lmdofn', 'lmdofn is not allocated')
    call begin_field(w, 'runtime.dof.lmdofn', NO_KEY, [integer(int64) :: int(size(lmdofn), int64)], 'i32')
    do d1 = 1, size(lmdofn)
      call put_i32(w, lmdofn(d1))
    end do
    call end_field(w)
    ! derived.dof.cdofn  <- global_var.cdofn
    call begin_field(w, 'derived.dof.cdofn', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, cdofn)
    call end_field(w)
    ! derived.dof.lcdofn  <- emit_derived_dof_lcdofn (handwritten adapter)
    call emit_derived_dof_lcdofn(w)
    ! runtime.increment.iblks_at_model  <- global_var.iblks
    call begin_field(w, 'runtime.increment.iblks_at_model', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, iblks)
    call end_field(w)
    ! runtime.increment.lblks_at_model  <- global_var.lblks
    call begin_field(w, 'runtime.increment.lblks_at_model', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, lblks)
    call end_field(w)
    ! steps0.activation.active  <- emit_steps0_activation_active (handwritten adapter)
    call emit_steps0_activation_active(w)
    ! steps0.activation.material  <- global_var.matno_process
    if (.not. allocated(matno_process)) call state_fail(w, 'steps0.activation.material', 'matno_process is not allocated')
    call begin_field(w, 'steps0.activation.material', NO_KEY, [integer(int64) :: int(size(matno_process, 1), int64), &
      int(size(matno_process, 2), int64)], 'i32')
    do d2 = 1, size(matno_process, 2)
      do d1 = 1, size(matno_process, 1)
        call put_i32(w, matno_process(d1, d2))
      end do
    end do
    call end_field(w)
    ! runtime.activation.appear  <- global_var.appear
    if (.not. allocated(appear)) call state_fail(w, 'runtime.activation.appear', 'appear is not allocated')
    call begin_field(w, 'runtime.activation.appear', NO_KEY, [integer(int64) :: int(size(appear), int64)], 'i32')
    do d1 = 1, size(appear)
      call put_i32(w, appear(d1))
    end do
    call end_field(w)
    ! steps0.output.stress_averaging  <- global_var.average_appear
    if (.not. allocated(average_appear)) call state_fail(w, 'steps0.output.stress_averaging', 'average_appear is not allocated')
    call begin_field(w, 'steps0.output.stress_averaging', NO_KEY, [integer(int64) :: int(size(average_appear), int64)], 'i32')
    do d1 = 1, size(average_appear)
      call put_i32(w, average_appear(d1))
    end do
    call end_field(w)
    ! steps0.output.field.gid_u  <- global_var.gid_u
    call begin_field(w, 'steps0.output.field.gid_u', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, gid_u)
    call end_field(w)
    ! steps0.output.field.gid_s  <- global_var.gid_s
    call begin_field(w, 'steps0.output.field.gid_s', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, gid_s)
    call end_field(w)
    ! steps0.output.field.gid_ms  <- global_var.gid_ms
    call begin_field(w, 'steps0.output.field.gid_ms', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, gid_ms)
    call end_field(w)
    ! steps0.output.field.gid_f  <- global_var.gid_f
    call begin_field(w, 'steps0.output.field.gid_f', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, gid_f)
    call end_field(w)
    ! steps0.output.field.gid_rot  <- global_var.gid_rot
    call begin_field(w, 'steps0.output.field.gid_rot', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, gid_rot)
    call end_field(w)
    ! steps0.output.field.gid_v  <- global_var.gid_v
    call begin_field(w, 'steps0.output.field.gid_v', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, gid_v)
    call end_field(w)
    ! steps0.output.field.gid_a  <- global_var.gid_a
    call begin_field(w, 'steps0.output.field.gid_a', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, gid_a)
    call end_field(w)
    ! steps0.output.field.gid_T  <- global_var.gid_T
    call begin_field(w, 'steps0.output.field.gid_T', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, gid_T)
    call end_field(w)
    ! steps0.output.field.gid_P  <- global_var.gid_P
    call begin_field(w, 'steps0.output.field.gid_P', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, gid_P)
    call end_field(w)
    ! steps0.output.field.gid_Pv  <- global_var.gid_Pv
    call begin_field(w, 'steps0.output.field.gid_Pv', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, gid_Pv)
    call end_field(w)
    ! steps0.output.field.gid_ep  <- global_var.gid_ep
    call begin_field(w, 'steps0.output.field.gid_ep', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, gid_ep)
    call end_field(w)
    ! steps0.output.field.gid_Y  <- global_var.gid_Y
    call begin_field(w, 'steps0.output.field.gid_Y', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, gid_Y)
    call end_field(w)
    ! steps0.output.field.gid_FC  <- global_var.gid_FC
    call begin_field(w, 'steps0.output.field.gid_FC', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, gid_FC)
    call end_field(w)
    ! steps0.output.field.gid_Ns  <- global_var.gid_Ns
    call begin_field(w, 'steps0.output.field.gid_Ns', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, gid_Ns)
    call end_field(w)
    ! steps0.output.field.gid_Ss  <- global_var.gid_Ss
    call begin_field(w, 'steps0.output.field.gid_Ss', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, gid_Ss)
    call end_field(w)
    ! steps0.output.field.gid_Mxy  <- global_var.gid_Mxy
    call begin_field(w, 'steps0.output.field.gid_Mxy', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, gid_Mxy)
    call end_field(w)
    ! steps0.output.field.gid_bem  <- global_var.gid_bem
    call begin_field(w, 'steps0.output.field.gid_bem', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, gid_bem)
    call end_field(w)
    ! steps0.output.field.gid_wh  <- global_var.gid_wh
    call begin_field(w, 'steps0.output.field.gid_wh', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, gid_wh)
    call end_field(w)
    ! steps0.output.field.gid_wv  <- global_var.gid_wv
    call begin_field(w, 'steps0.output.field.gid_wv', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, gid_wv)
    call end_field(w)
    ! steps0.output.field.gid_bcs  <- global_var.gid_bcs
    call begin_field(w, 'steps0.output.field.gid_bcs', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, gid_bcs)
    call end_field(w)
    ! derived.counts.nfixsets  <- prescribed.nfixsets
    call begin_field(w, 'derived.counts.nfixsets', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, nfixsets)
    call end_field(w)
    ! derived.counts.ndofix  <- prescribed.ndofix
    call begin_field(w, 'derived.counts.ndofix', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, ndofix)
    call end_field(w)
    ! steps0.boundary.set  <- prescribed.prescrib%ifixset
    if (.not. allocated(prescrib)) call state_fail(w, 'steps0.boundary.set', 'prescrib is not allocated')
    call begin_field(w, 'steps0.boundary.set', NO_KEY, [integer(int64) :: int(size(prescrib), int64)], 'i32')
    do d1 = 1, size(prescrib)
      call put_i32(w, prescrib(d1)%ifixset)
    end do
    call end_field(w)
    ! steps0.boundary.dof  <- prescribed.prescrib%ifixvar
    if (.not. allocated(prescrib)) call state_fail(w, 'steps0.boundary.dof', 'prescrib is not allocated')
    call begin_field(w, 'steps0.boundary.dof', NO_KEY, [integer(int64) :: int(size(prescrib), int64)], 'i32')
    do d1 = 1, size(prescrib)
      call put_i32(w, prescrib(d1)%ifixvar)
    end do
    call end_field(w)
    ! steps0.boundary.amplitude  <- prescribed.prescrib%itcurve
    if (.not. allocated(prescrib)) call state_fail(w, 'steps0.boundary.amplitude', 'prescrib is not allocated')
    call begin_field(w, 'steps0.boundary.amplitude', NO_KEY, [integer(int64) :: int(size(prescrib), int64)], 'i32')
    do d1 = 1, size(prescrib)
      call put_i32(w, prescrib(d1)%itcurve)
    end do
    call end_field(w)
    ! steps0.boundary.nodes  <- prescribed.prescrib%nodfix
    if (.not. allocated(prescrib)) call state_fail(w, 'steps0.boundary.nodes', 'prescrib is not allocated')
    call begin_field(w, 'steps0.boundary.nodes', NO_KEY, [integer(int64) :: int(size(prescrib), int64)], 'i32')
    do d1 = 1, size(prescrib)
      call put_i32(w, prescrib(d1)%nodfix)
    end do
    call end_field(w)
    ! steps0.boundary.value  <- prescribed.prescrib%vdofix
    if (.not. allocated(prescrib)) call state_fail(w, 'steps0.boundary.value', 'prescrib is not allocated')
    call begin_field(w, 'steps0.boundary.value', NO_KEY, [integer(int64) :: int(size(prescrib), int64)], 'f64')
    do d1 = 1, size(prescrib)
      call put_f64(w, prescrib(d1)%vdofix)
    end do
    call end_field(w)
    ! steps0.boundary.record_reaction  <- prescribed.prescrib%outfix
    if (.not. allocated(prescrib)) call state_fail(w, 'steps0.boundary.record_reaction', 'prescrib is not allocated')
    call begin_field(w, 'steps0.boundary.record_reaction', NO_KEY, [integer(int64) :: int(size(prescrib), int64)], 'i32')
    do d1 = 1, size(prescrib)
      call put_i32(w, prescrib(d1)%outfix)
    end do
    call end_field(w)
    ! runtime.boundary.ldofix  <- prescribed.prescrib%ldofix
    if (.not. allocated(prescrib)) call state_fail(w, 'runtime.boundary.ldofix', 'prescrib is not allocated')
    call begin_field(w, 'runtime.boundary.ldofix', NO_KEY, [integer(int64) :: int(size(prescrib), int64)], 'i32')
    do d1 = 1, size(prescrib)
      call put_i32(w, prescrib(d1)%ldofix)
    end do
    call end_field(w)
    ! runtime.boundary.lnefix  <- prescribed.prescrib%lnefix
    if (.not. allocated(prescrib)) call state_fail(w, 'runtime.boundary.lnefix', 'prescrib is not allocated')
    call begin_field(w, 'runtime.boundary.lnefix', NO_KEY, [integer(int64) :: int(size(prescrib), int64)], 'i32')
    do d1 = 1, size(prescrib)
      call put_i32(w, prescrib(d1)%lnefix)
    end do
    call end_field(w)
    ! runtime.boundary.leldofix  <- emit_runtime_boundary_leldofix (handwritten adapter)
    call emit_runtime_boundary_leldofix(w)
    ! runtime.boundary.levdofix  <- emit_runtime_boundary_levdofix (handwritten adapter)
    call emit_runtime_boundary_levdofix(w)
    ! runtime.boundary.lefdofix  <- emit_runtime_boundary_lefdofix (handwritten adapter)
    call emit_runtime_boundary_lefdofix(w)
    ! runtime.dof.iffix  <- global_var.iffix
    if (.not. allocated(iffix)) call state_fail(w, 'runtime.dof.iffix', 'iffix is not allocated')
    call begin_field(w, 'runtime.dof.iffix', NO_KEY, [integer(int64) :: int(size(iffix), int64)], 'i32')
    do d1 = 1, size(iffix)
      call put_i32(w, iffix(d1))
    end do
    call end_field(w)
    ! runtime.dof.fixed  <- global_var.fixed
    if (.not. allocated(fixed)) call state_fail(w, 'runtime.dof.fixed', 'fixed is not allocated')
    call begin_field(w, 'runtime.dof.fixed', NO_KEY, [integer(int64) :: int(size(fixed), int64)], 'f64')
    do d1 = 1, size(fixed)
      call put_f64(w, fixed(d1))
    end do
    call end_field(w)
    ! control.glb.ntrans  <- global_var.ntrans
    call begin_field(w, 'control.glb.ntrans', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, ntrans)
    call end_field(w)
    ! steps0.load.gravity.magnitude  <- applied_load.gravy
    call begin_field(w, 'steps0.load.gravity.magnitude', NO_KEY, SCALAR_SHAPE, 'f64')
    call put_f64(w, gravy)
    call end_field(w)
    ! steps0.load.gravity.direction  <- applied_load.factg
    if (.not. allocated(factg)) call state_fail(w, 'steps0.load.gravity.direction', 'factg is not allocated')
    call begin_field(w, 'steps0.load.gravity.direction', NO_KEY, [integer(int64) :: int(size(factg), int64)], 'f64')
    do d1 = 1, size(factg)
      call put_f64(w, factg(d1))
    end do
    call end_field(w)
    ! steps0.load.gravity.amplitude  <- applied_load.tcurvegravity
    if (.not. allocated(tcurvegravity)) call state_fail(w, 'steps0.load.gravity.amplitude', 'tcurvegravity is not allocated')
    call begin_field(w, 'steps0.load.gravity.amplitude', NO_KEY, [integer(int64) :: int(size(tcurvegravity), int64)], 'i32')
    do d1 = 1, size(tcurvegravity)
      call put_i32(w, tcurvegravity(d1))
    end do
    call end_field(w)
    ! derived.counts.nplgroup  <- applied_load.nplgroup
    call begin_field(w, 'derived.counts.nplgroup', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, nplgroup)
    call end_field(w)
    ! derived.counts.nedge  <- applied_load.nedge
    call begin_field(w, 'derived.counts.nedge', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, nedge)
    call end_field(w)
    ! derived.counts.edge_load_group  <- applied_load.edge_load_group
    call begin_field(w, 'derived.counts.edge_load_group', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, edge_load_group)
    call end_field(w)
    ! derived.counts.delgroup  <- applied_load.delgroup
    call begin_field(w, 'derived.counts.delgroup', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, delgroup)
    call end_field(w)
    ! derived.counts.nbeamload  <- applied_load.nbeamload
    call begin_field(w, 'derived.counts.nbeamload', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, nbeamload)
    call end_field(w)
    ! derived.counts.nplateload  <- applied_load.nplateload
    call begin_field(w, 'derived.counts.nplateload', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, nplateload)
    call end_field(w)
    ! derived.counts.ntemp_surface  <- temperature.ntemp_surface
    call begin_field(w, 'derived.counts.ntemp_surface', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, ntemp_surface)
    call end_field(w)
    ! derived.counts.ntedge  <- temperature.ntedge
    call begin_field(w, 'derived.counts.ntedge', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, ntedge)
    call end_field(w)
    ! derived.counts.ntelgroup  <- temperature.ntelgroup
    call begin_field(w, 'derived.counts.ntelgroup', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, ntelgroup)
    call end_field(w)
    ! derived.counts.npipe  <- temperature.npipe
    call begin_field(w, 'derived.counts.npipe', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, npipe)
    call end_field(w)
    ! runtime.dof.nodfn  <- global_var.nodfn
    if (.not. allocated(nodfn)) call state_fail(w, 'runtime.dof.nodfn', 'nodfn is not allocated')
    call begin_field(w, 'runtime.dof.nodfn', NO_KEY, [integer(int64) :: int(size(nodfn, 1), int64), int(size(nodfn, 2), int64)], &
      'i32')
    do d2 = 1, size(nodfn, 2)
      do d1 = 1, size(nodfn, 1)
        call put_i32(w, nodfn(d1, d2))
      end do
    end do
    call end_field(w)
    ! runtime.dof.ntotv  <- global_var.ntotv
    call begin_field(w, 'runtime.dof.ntotv', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, ntotv)
    call end_field(w)
    ! runtime.dof.ldofs  <- global_var.element%ldofs
    if (.not. allocated(element)) call state_fail(w, 'runtime.dof.ldofs', 'element is not allocated')
    n1 = 0
    if (size(element) >= 1) then
      if (.not. associated(element(1)%ldofs)) call state_fail(w, 'runtime.dof.ldofs', 'element(1)%ldofs is not associated')
      n1 = size(element(1)%ldofs)
    end if
    call begin_field(w, 'runtime.dof.ldofs', NO_KEY, [integer(int64) :: int(n1, int64), int(size(element), int64)], 'i32')
    do d2 = 1, size(element)
      if (.not. associated(element(d2)%ldofs)) call state_fail(w, 'runtime.dof.ldofs', 'element(d2)%ldofs is not associated')
      if (size(element(d2)%ldofs) /= n1) call state_fail(w, 'runtime.dof.ldofs', 'element(d2)%ldofs extent 1 is ragged')
      do d1 = 1, n1
        call put_i32(w, element(d2)%ldofs(d1))
      end do
    end do
    call end_field(w)
    ! runtime.dof.ldofs_f  <- global_var.element%field%ldofs_f
    if (.not. allocated(element)) call state_fail(w, 'runtime.dof.ldofs_f', 'element is not allocated')
    n1 = 0
    if (size(element) >= 1) then
      if (.not. associated(element(1)%field)) call state_fail(w, 'runtime.dof.ldofs_f', 'element(1)%field is not associated')
      if (size(element(1)%field) < 1) call state_fail(w, 'runtime.dof.ldofs_f', 'element(1)%field is empty')
      if (.not. associated(element(1)%field(1)%ldofs_f)) call state_fail(w, 'runtime.dof.ldofs_f', &
        'element(1)%field(1)%ldofs_f is not associated')
      n1 = size(element(1)%field(1)%ldofs_f)
    end if
    call begin_field(w, 'runtime.dof.ldofs_f', NO_KEY, [integer(int64) :: int(n1, int64), int(size(element), int64)], 'i32')
    do d2 = 1, size(element)
      if (.not. associated(element(d2)%field)) call state_fail(w, 'runtime.dof.ldofs_f', 'element(d2)%field is not associated')
      if (size(element(d2)%field) < 1) call state_fail(w, 'runtime.dof.ldofs_f', 'element(d2)%field is empty')
      if (.not. associated(element(d2)%field(1)%ldofs_f)) call state_fail(w, 'runtime.dof.ldofs_f', &
        'element(d2)%field(1)%ldofs_f is not associated')
      if (size(element(d2)%field(1)%ldofs_f) /= n1) call state_fail(w, 'runtime.dof.ldofs_f', &
        'element(d2)%field(1)%ldofs_f extent 1 is ragged')
      do d1 = 1, n1
        call put_i32(w, element(d2)%field(1)%ldofs_f(d1))
      end do
    end do
    call end_field(w)
    ! runtime.dof.trans_nintf  <- global_var.trans%nintf
    if (.not. allocated(trans)) call state_fail(w, 'runtime.dof.trans_nintf', 'trans is not allocated')
    call begin_field(w, 'runtime.dof.trans_nintf', NO_KEY, [integer(int64) :: int(size(trans), int64)], 'i32')
    do d1 = 1, size(trans)
      call put_i32(w, trans(d1)%nintf)
    end do
    call end_field(w)
    ! runtime.topology.listp_group_mgroup  <- global_var.listp_group%mgroup
    if (.not. allocated(listp_group)) call state_fail(w, 'runtime.topology.listp_group_mgroup', 'listp_group is not allocated')
    call begin_field(w, 'runtime.topology.listp_group_mgroup', NO_KEY, [integer(int64) :: int(size(listp_group), int64)], 'i32')
    do d1 = 1, size(listp_group)
      call put_i32(w, listp_group(d1)%mgroup)
    end do
    call end_field(w)
    ! runtime.topology.listp_group_listg  <- emit_runtime_topology_listp_group_listg (handwritten adapter)
    call emit_runtime_topology_listp_group_listg(w)
    ! runtime.topology.listp_group_listp  <- emit_runtime_topology_listp_group_listp (handwritten adapter)
    call emit_runtime_topology_listp_group_listp(w)
    ! runtime.topology.unode_ipoin  <- emit_runtime_topology_unode_ipoin (handwritten adapter)
    call emit_runtime_topology_unode_ipoin(w)
    ! runtime.topology.unode_ne_unode  <- emit_runtime_topology_unode_ne_unode (handwritten adapter)
    call emit_runtime_topology_unode_ne_unode(w)
    ! runtime.topology.unode_list  <- emit_runtime_topology_unode_list (handwritten adapter)
    call emit_runtime_topology_unode_list(w)
    ! runtime.gauss.djacb  <- global_var.element%egaus%djacb
    if (.not. allocated(element)) call state_fail(w, 'runtime.gauss.djacb', 'element is not allocated')
    n1 = 0
    if (size(element) >= 1) then
      if (.not. associated(element(1)%egaus)) call state_fail(w, 'runtime.gauss.djacb', 'element(1)%egaus is not associated')
      if (size(element(1)%egaus) < 1) call state_fail(w, 'runtime.gauss.djacb', 'element(1)%egaus is empty')
      if (.not. associated(element(1)%egaus(1)%djacb)) call state_fail(w, 'runtime.gauss.djacb', &
        'element(1)%egaus(1)%djacb is not associated')
      n1 = size(element(1)%egaus(1)%djacb)
    end if
    call begin_field(w, 'runtime.gauss.djacb', NO_KEY, [integer(int64) :: int(n1, int64), int(size(element), int64)], 'f64')
    do d2 = 1, size(element)
      if (.not. associated(element(d2)%egaus)) call state_fail(w, 'runtime.gauss.djacb', 'element(d2)%egaus is not associated')
      if (size(element(d2)%egaus) < 1) call state_fail(w, 'runtime.gauss.djacb', 'element(d2)%egaus is empty')
      if (.not. associated(element(d2)%egaus(1)%djacb)) call state_fail(w, 'runtime.gauss.djacb', &
        'element(d2)%egaus(1)%djacb is not associated')
      if (size(element(d2)%egaus(1)%djacb) /= n1) call state_fail(w, 'runtime.gauss.djacb', &
        'element(d2)%egaus(1)%djacb extent 1 is ragged')
      do d1 = 1, n1
        call put_f64(w, element(d2)%egaus(1)%djacb(d1))
      end do
    end do
    call end_field(w)
    ! runtime.gauss.gpcod  <- global_var.element%egaus%gpcod
    if (.not. allocated(element)) call state_fail(w, 'runtime.gauss.gpcod', 'element is not allocated')
    n1 = 0
    n2 = 0
    if (size(element) >= 1) then
      if (.not. associated(element(1)%egaus)) call state_fail(w, 'runtime.gauss.gpcod', 'element(1)%egaus is not associated')
      if (size(element(1)%egaus) < 1) call state_fail(w, 'runtime.gauss.gpcod', 'element(1)%egaus is empty')
      if (.not. associated(element(1)%egaus(1)%gpcod)) call state_fail(w, 'runtime.gauss.gpcod', &
        'element(1)%egaus(1)%gpcod is not associated')
      n1 = size(element(1)%egaus(1)%gpcod, 1)
      n2 = size(element(1)%egaus(1)%gpcod, 2)
    end if
    call begin_field(w, 'runtime.gauss.gpcod', NO_KEY, [integer(int64) :: int(n1, int64), int(n2, int64), &
      int(size(element), int64)], 'f64')
    do d3 = 1, size(element)
      if (.not. associated(element(d3)%egaus)) call state_fail(w, 'runtime.gauss.gpcod', 'element(d3)%egaus is not associated')
      if (size(element(d3)%egaus) < 1) call state_fail(w, 'runtime.gauss.gpcod', 'element(d3)%egaus is empty')
      if (.not. associated(element(d3)%egaus(1)%gpcod)) call state_fail(w, 'runtime.gauss.gpcod', &
        'element(d3)%egaus(1)%gpcod is not associated')
      if (size(element(d3)%egaus(1)%gpcod, 1) /= n1) call state_fail(w, 'runtime.gauss.gpcod', &
        'element(d3)%egaus(1)%gpcod extent 1 is ragged')
      if (size(element(d3)%egaus(1)%gpcod, 2) /= n2) call state_fail(w, 'runtime.gauss.gpcod', &
        'element(d3)%egaus(1)%gpcod extent 2 is ragged')
      do d2 = 1, n2
        do d1 = 1, n1
          call put_f64(w, element(d3)%egaus(1)%gpcod(d1, d2))
        end do
      end do
    end do
    call end_field(w)
    ! runtime.gauss.cartd  <- global_var.element%egaus%cartd
    if (.not. allocated(element)) call state_fail(w, 'runtime.gauss.cartd', 'element is not allocated')
    n1 = 0
    n2 = 0
    n3 = 0
    if (size(element) >= 1) then
      if (.not. associated(element(1)%egaus)) call state_fail(w, 'runtime.gauss.cartd', 'element(1)%egaus is not associated')
      if (size(element(1)%egaus) < 1) call state_fail(w, 'runtime.gauss.cartd', 'element(1)%egaus is empty')
      if (.not. associated(element(1)%egaus(1)%cartd)) call state_fail(w, 'runtime.gauss.cartd', &
        'element(1)%egaus(1)%cartd is not associated')
      n1 = size(element(1)%egaus(1)%cartd, 1)
      n2 = size(element(1)%egaus(1)%cartd, 2)
      n3 = size(element(1)%egaus(1)%cartd, 3)
    end if
    call begin_field(w, 'runtime.gauss.cartd', NO_KEY, [integer(int64) :: int(n1, int64), int(n2, int64), int(n3, int64), &
      int(size(element), int64)], 'f64')
    do d4 = 1, size(element)
      if (.not. associated(element(d4)%egaus)) call state_fail(w, 'runtime.gauss.cartd', 'element(d4)%egaus is not associated')
      if (size(element(d4)%egaus) < 1) call state_fail(w, 'runtime.gauss.cartd', 'element(d4)%egaus is empty')
      if (.not. associated(element(d4)%egaus(1)%cartd)) call state_fail(w, 'runtime.gauss.cartd', &
        'element(d4)%egaus(1)%cartd is not associated')
      if (size(element(d4)%egaus(1)%cartd, 1) /= n1) call state_fail(w, 'runtime.gauss.cartd', &
        'element(d4)%egaus(1)%cartd extent 1 is ragged')
      if (size(element(d4)%egaus(1)%cartd, 2) /= n2) call state_fail(w, 'runtime.gauss.cartd', &
        'element(d4)%egaus(1)%cartd extent 2 is ragged')
      if (size(element(d4)%egaus(1)%cartd, 3) /= n3) call state_fail(w, 'runtime.gauss.cartd', &
        'element(d4)%egaus(1)%cartd extent 3 is ragged')
      do d3 = 1, n3
        do d2 = 1, n2
          do d1 = 1, n1
            call put_f64(w, element(d4)%egaus(1)%cartd(d1, d2, d3))
          end do
        end do
      end do
    end do
    call end_field(w)
    ! runtime.vectors.result_zero  <- global_var.result_zero
    if (.not. allocated(result_zero)) call state_fail(w, 'runtime.vectors.result_zero', 'result_zero is not allocated')
    call begin_field(w, 'runtime.vectors.result_zero', NO_KEY, [integer(int64) :: int(size(result_zero), int64)], 'f64')
    do d1 = 1, size(result_zero)
      call put_f64(w, result_zero(d1))
    end do
    call end_field(w)
    ! runtime.vectors.tofor  <- global_var.tofor
    if (.not. allocated(tofor)) call state_fail(w, 'runtime.vectors.tofor', 'tofor is not allocated')
    call begin_field(w, 'runtime.vectors.tofor', NO_KEY, [integer(int64) :: int(size(tofor), int64)], 'f64')
    do d1 = 1, size(tofor)
      call put_f64(w, tofor(d1))
    end do
    call end_field(w)
    ! runtime.vectors.stfor  <- global_var.stfor
    if (.not. allocated(stfor)) call state_fail(w, 'runtime.vectors.stfor', 'stfor is not allocated')
    call begin_field(w, 'runtime.vectors.stfor', NO_KEY, [integer(int64) :: int(size(stfor), int64)], 'f64')
    do d1 = 1, size(stfor)
      call put_f64(w, stfor(d1))
    end do
    call end_field(w)
    ! runtime.vectors.toforl  <- global_var.toforl
    if (.not. allocated(toforl)) call state_fail(w, 'runtime.vectors.toforl', 'toforl is not allocated')
    call begin_field(w, 'runtime.vectors.toforl', NO_KEY, [integer(int64) :: int(size(toforl), int64)], 'f64')
    do d1 = 1, size(toforl)
      call put_f64(w, toforl(d1))
    end do
    call end_field(w)
    ! runtime.vectors.toform  <- global_var.toform
    if (.not. allocated(toform)) call state_fail(w, 'runtime.vectors.toform', 'toform is not allocated')
    call begin_field(w, 'runtime.vectors.toform', NO_KEY, [integer(int64) :: int(size(toform), int64)], 'f64')
    do d1 = 1, size(toform)
      call put_f64(w, toform(d1))
    end do
    call end_field(w)
    ! runtime.element.ice0  <- meshfine.ice0
    if (.not. allocated(ice0)) call state_fail(w, 'runtime.element.ice0', 'ice0 is not allocated')
    call begin_field(w, 'runtime.element.ice0', NO_KEY, [integer(int64) :: int(size(ice0), int64)], 'i32')
    do d1 = 1, size(ice0)
      call put_i32(w, ice0(d1))
    end do
    call end_field(w)
  end subroutine dump_model_ready

  ! phase_ready(1): 11 fields
  subroutine dump_phase_ready_1(w)
    type(state_writer_t), intent(inout) :: w
    integer :: d1

    ! steps0.controls.increments  <- global_var.nincs
    call begin_field(w, 'steps0.controls.increments', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, nincs)
    call end_field(w)
    ! runtime.increment.lincs  <- global_var.lincs
    call begin_field(w, 'runtime.increment.lincs', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, lincs)
    call end_field(w)
    ! solver.profile.iafile  <- solver.iafile
    call begin_field(w, 'solver.profile.iafile', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, iafile)
    call end_field(w)
    ! solver.profile.icond  <- solver.icond
    call begin_field(w, 'solver.profile.icond', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, icond)
    call end_field(w)
    ! solver.profile.ipdchk  <- solver.ipdchk
    call begin_field(w, 'solver.profile.ipdchk', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, ipdchk)
    call end_field(w)
    ! solver.profile.ising  <- solver.ising
    call begin_field(w, 'solver.profile.ising', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, ising)
    call end_field(w)
    ! runtime.solver.operation  <- solver.operation
    call begin_field(w, 'runtime.solver.operation', NO_KEY, SCALAR_SHAPE, 'str')
    call put_str(w, operation)
    call end_field(w)
    ! runtime.eq.totveq  <- solver.totveq
    if (.not. allocated(totveq)) call state_fail(w, 'runtime.eq.totveq', 'totveq is not allocated')
    call begin_field(w, 'runtime.eq.totveq', NO_KEY, [integer(int64) :: int(size(totveq), int64)], 'i32')
    do d1 = 1, size(totveq)
      call put_i32(w, totveq(d1))
    end do
    call end_field(w)
    ! runtime.eq.neq  <- solver.neq
    call begin_field(w, 'runtime.eq.neq', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, neq)
    call end_field(w)
    ! runtime.eq.iseq  <- solver.iseq
    if (.not. allocated(iseq)) call state_fail(w, 'runtime.eq.iseq', 'iseq is not allocated')
    call begin_field(w, 'runtime.eq.iseq', NO_KEY, [integer(int64) :: int(size(iseq), int64)], 'i32')
    do d1 = 1, size(iseq)
      call put_i32(w, iseq(d1))
    end do
    call end_field(w)
    ! runtime.solver.stiff_length  <- emit_runtime_solver_stiff_length (handwritten adapter)
    call emit_runtime_solver_stiff_length(w)
  end subroutine dump_phase_ready_1

  ! increment_ready(1,1): 17 fields
  subroutine dump_increment_ready_1_1(w)
    type(state_writer_t), intent(inout) :: w
    integer :: d1

    ! steps0.controls.max_iterations  <- global_var.miter
    call begin_field(w, 'steps0.controls.max_iterations', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, miter)
    call end_field(w)
    ! steps0.controls.time_increment  <- global_var.ditime
    call begin_field(w, 'steps0.controls.time_increment', NO_KEY, SCALAR_SHAPE, 'f64')
    call put_f64(w, ditime)
    call end_field(w)
    ! steps0.output.frequency_nodes  <- global_var.noutn
    call begin_field(w, 'steps0.output.frequency_nodes', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, noutn)
    call end_field(w)
    ! steps0.output.frequency_fields  <- global_var.noutf
    call begin_field(w, 'steps0.output.frequency_fields', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, noutf)
    call end_field(w)
    ! steps0.controls.steps  <- global_var.nstep
    call begin_field(w, 'steps0.controls.steps', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, nstep)
    call end_field(w)
    ! steps0.controls.step_increment  <- global_var.inc_step
    call begin_field(w, 'steps0.controls.step_increment', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, inc_step)
    call end_field(w)
    ! steps0.controls.restart_frequency  <- global_var.nresta
    call begin_field(w, 'steps0.controls.restart_frequency', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, nresta)
    call end_field(w)
    ! steps0.controls.qstatic  <- global_var.Qstatic
    call begin_field(w, 'steps0.controls.qstatic', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, Qstatic)
    call end_field(w)
    ! steps0.controls.tolerance_force  <- global_var.toler_force
    call begin_field(w, 'steps0.controls.tolerance_force', NO_KEY, SCALAR_SHAPE, 'f64')
    call put_f64(w, toler_force)
    call end_field(w)
    ! steps0.controls.tolerance_dof  <- global_var.toler_var
    if (.not. allocated(toler_var)) call state_fail(w, 'steps0.controls.tolerance_dof', 'toler_var is not allocated')
    call begin_field(w, 'steps0.controls.tolerance_dof', NO_KEY, [integer(int64) :: int(size(toler_var), int64)], 'f64')
    do d1 = 1, size(toler_var)
      call put_f64(w, toler_var(d1))
    end do
    call end_field(w)
    ! runtime.time.ttime  <- global_var.ttime
    call begin_field(w, 'runtime.time.ttime', NO_KEY, SCALAR_SHAPE, 'f64')
    call put_f64(w, ttime)
    call end_field(w)
    ! runtime.time.trstep  <- global_var.trstep
    call begin_field(w, 'runtime.time.trstep', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, trstep)
    call end_field(w)
    ! runtime.increment.iincs  <- global_var.iincs
    call begin_field(w, 'runtime.increment.iincs', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, iincs)
    call end_field(w)
    ! runtime.increment.iblks  <- global_var.iblks
    call begin_field(w, 'runtime.increment.iblks', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, iblks)
    call end_field(w)
    ! runtime.increment.lblks  <- global_var.lblks
    call begin_field(w, 'runtime.increment.lblks', NO_KEY, SCALAR_SHAPE, 'i32')
    call put_i32(w, lblks)
    call end_field(w)
    ! runtime.amplitudes.dfact_at_increment  <- applied_load.tcurves%dfact
    if (.not. allocated(tcurves)) call state_fail(w, 'runtime.amplitudes.dfact_at_increment', 'tcurves is not allocated')
    call begin_field(w, 'runtime.amplitudes.dfact_at_increment', NO_KEY, [integer(int64) :: int(size(tcurves), int64)], 'f64')
    do d1 = 1, size(tcurves)
      call put_f64(w, tcurves(d1)%dfact)
    end do
    call end_field(w)
    ! runtime.dof.fixed_at_increment  <- global_var.fixed
    if (.not. allocated(fixed)) call state_fail(w, 'runtime.dof.fixed_at_increment', 'fixed is not allocated')
    call begin_field(w, 'runtime.dof.fixed_at_increment', NO_KEY, [integer(int64) :: int(size(fixed), int64)], 'f64')
    do d1 = 1, size(fixed)
      call put_f64(w, fixed(d1))
    end do
    call end_field(w)
  end subroutine dump_increment_ready_1_1

end module yl_state_serializer
