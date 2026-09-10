! yl_adapter_model -- M4-01 legacy adapter: .glb (the model/control deck), per
! docs/m4/adapter-contract.md SS2.
!
! Scope
!   The 75 reader-inventory sites whose `file` is ".glb" (docs/m1/reader-inventory.toml;
!   filter `file = ".glb"` -- confirmed 75 by `python3 tools/yl_io_inventory.py`-style
!   count against the toml, not just grep, since a naive text split over-counts by one
!   entry that belongs to `.man`). Every read below carries that site's `id` and legacy
!   `site` in an adjacent comment (contract SS3); grep for "RD:" to enumerate all 75.
!
!   Two sites the golden-deck evidence in reader-inventory marks `reached_only = false`
!   (never taken on either golden deck) are NOT read as data here: `rmesh/=0` (would read
!   valv1,valv2, Global.f90:722) and `nlayer==2` (would read three more scalars,
!   Global.f90:810). Both guards are enforced EARLIER, at the point their controlling
!   switch is first read (sizes_and_switches for rmesh, problem_type for nlayer), which
!   makes the later `if` unreachable by construction: this parser has already returned
!   PE_UNSUPPORTED before execution could reach it. That is reproducing the guard, not
!   skipping it (adapter-contract.md SS2's "do not assume the guard is taken" is about not
!   defaulting an UNCHECKED branch, not about the textual position of the check).
!
!   One more legacy guard has NO reader-inventory entry at all (checked: zero hits for
!   "point_direct" in docs/m1/reader-inventory.toml) -- `if(group(igroup)%index==20 .or.
!   ==21 .or. ==22 .or. ==26) read group(igroup)%point_direct` (Global.f90:1249-1250,
!   format confirmed from the group_of_elements declaration at Global.f90:237:
!   `point_direct(2)`, plain integers). This looks like an M1 inventory gap rather than a
!   deliberate omission (worth a follow-up against tools/yl_io_inventory.py) and IS
!   implemented below, faithfully, rather than folded into a blanket "reject any group
!   index" rule: the whitelist's Q4-only judgement on `element_kind` already belongs to
!   the M3 capability gate (yl_problem_pipeline.f90 capability_gate, item 'element.kind_code'),
!   which runs on the FINISHED draft and can see every section at once. Pre-empting that
!   here, before the value even reaches the builder, would just be a second copy of the
!   same rule with its own chance to drift from the table.
!
! What this parser writes, and through what channel
!   ONLY through yl_problem_builder (mesh.dimension, interactions) and through three
!   shared scratch aggregates in src/adapter/yl_adapter_parts.f90 (adapter-contract.md
!   SS2.1/SS2.2/SS2.4):
!     `step_parts_t`    -- `procedure_`, `load_mode`, `output` (the whole aggregate),
!                         `activation(:)`, and EXACTLY ONE leaf each of `controls`
!                         (nonlinear_type) and `load` (gravity.enabled). Every other
!                         `step_parts_t` leaf (the other eight `controls` fields,
!                         gravity's magnitude/direction/amplitude, `boundary(:)`) belongs
!                         to `.man`/`.loa`/`.pre` and is left untouched -- writing it here
!                         would be the exact silent-second-writer defect that module's
!                         header warns about, even if the value happened to be right.
!     `solver_parts_t`  -- `linear`, `symmetric`. `profile%*` belongs to `.sol` and is left
!                         untouched. `builder_set_solver` (a duplicate_singleton setter,
!                         same as the step setters) is therefore never called from here;
!                         L2-a makes that one call after every parser has run.
!     `section_parts_t` -- every `sections[]` field this module ever read EXCEPT
!                         `thickness`, which is `.mat`'s leaf (read AFTER .glb,
!                         Fem.f90:117 then :191) and is deliberately left unset here for
!                         `parse_mat` to fill. `builder_add_section` is, for the same
!                         reason as the two aggregates above, never called from here.
!   It also FILLS `deck_context_t` (intent(inout), see the subroutine header) so that
!   `.cor`/`.ele`/`.loa`/`.pre` do not have to guess `ndimn`/`ngroup`/element kind/
!   `type_abc`/`nbackdt`/`ntrans` the way yl_adapter_mesh.f90's own module header
!   currently documents having to (its NDIMN=2/NNODE_Q4=4 hardcoding).
!
!   sections[].material and sections[].material_header are NOT set here despite `matno`
!   being read at the .glb group header (RD: GLB.global_data.group_header): both map rows
!   are `source = ["derived:..."]` in docs/m2/state-field-map.toml -- the EFFECTIVE value is
!   computed later from steps[0].activation[].material and mesh.elements[].material (which
!   is itself populated while reading .ele, a file this module does not own). `gmatno`
!   below is read (to keep the record complete and the cursor correct) and then discarded.
!
! Counts read here but never authored: npoin, npoinb, nelem, nmats, ngroup, nblks, mdofn,
!   nrfields, nfdof are all `owner = "derived"` rows -- cardinalities the FINALIZE stage
!   recomputes from the actual collections, never values a parser hands to the builder
!   (yl_problem_types.f90 module header: "no npoin, nelem, ... no Fortran slot name in
!   ProblemState"). They are kept as local Fortran variables here purely to size the
!   arrays legacy sizes them with (ngroup for the per-group loop, mdofn for lmdofn, nblks
!   for the block-indexed arrays, ngroup/nelem for listglocbeam/lelenrt -- see the
!   crack_and_beam note below) and to run the whitelist checks that follow.
!
! Interleaving with .cor/.ele (owned by yl_adapter_mesh) -- reported to L2-a
!   `global_data` reads .glb straight through titles #1-#29 (Global.f90:691-1155), then
!   ALL of .cor (Global.f90:1176, a separate unit -- no cursor conflict with gunit), then
!   .glb titles #30-#34 plus the `do igroup=1,ngroup` header loop (group_header /
!   group_mass_damping / group_order_time / group_nfdof / group_listdof), and INSIDE that
!   same per-group loop iteration, all of that group's `.ele` elements (`call
!   read_element`, a third unit, Elements.f90:1087) before moving to the next group's
!   header. Since .glb/.cor/.ele are three independent Fortran units this parser's own
!   cursor on `unit` is unaffected by whatever the mesh parser does on cunit/eunit in
!   between -- there is no sequencing constraint THIS module needs from L2-a beyond "call
!   parse_glb on a `unit` positioned at the start of the .glb protocol and do not
!   interleave another .glb read from elsewhere". yl_adapter_mesh's own header confirms
!   the matching design choice on its side: it reads .cor/.ele to IOSTAT_END rather than
!   depending on npoin/nelem/ndimn/element_kind from this module, so there is no data
!   dependency in that direction either. This parser therefore reads all 75 .glb sites in
!   one call, uninterrupted.
!
! Whitelist (static-q4/1; not enlarged here, adapter-contract.md SS5): 2D, Q4, displacement
!   field, linear-elastic isotropic, single static step, fixed/prescribed displacement,
!   gravity.
!
!   Two kinds of rejection appear below, and they are deliberately NOT the same kind:
!     (a) Fields the M3 capability gate already checks on the finished draft (mesh.dimension,
!         solver.linear/symmetric, sections[].element/element_kind/class/fields/formulation,
!         steps[].procedure, steps[].load.gravity.enabled -- yl_problem_pipeline.f90
!         capability_gate) are stored as-read and NOT re-checked here. A second copy of
!         that judgement in this file could only drift from the capability table it is
!         supposed to defer to.
!     (b) Fields with NO ProblemState home at all -- pinned legacy switches
!         (rmesh, ntlink, mat_curve, meshc, level_set_problem, ljdp, nlinks,
!         block_stab, nbackf, ebody, ninit, uinitial, state_change, Bparameter, nlayer,
!         ntrans, nlocalbeam/ndimnrt) plus two fields this parser is the sole guard for
!         because nothing downstream inspects them (`type_ABC`, `type_nl`) and one
!         structural limit this parser's own single-step design imposes (`nblks`) -- are
!         checked HERE, against the value docs/m2/state-field-map.toml's notes record as
!         observed/required on both golden decks ("pinned guard: value 0 keeps control
!         flow on static_2d path"), because if this parser does not check them nothing
!         in the pipeline ever will: they carry no ProblemState component for a downstream
!         rule to inspect.
!   `outplot` is technically case (a)-adjacent (legacy_only, no gate row) but IS checked
!   here for the same "nothing else will" reason as case (b).
!
!   `stab_matde` is case (b) too but is NOT a flat zero-pin, and getting that wrong once
!   already broke a real deck (2026-09-08 correction, below): legacy's guard is
!   `if(iblks>=stab_matde) call stab_initialize` (Fem.f90:2441 et al.), so the DISABLING
!   value is stab_matde > nblks (both golden decks carry 99999, a disable sentinel), not
!   0. An earlier reading of docs/m2/state-field-map.toml's note had this backwards and
!   rejected every real deck; the map's note has since been corrected. See the check
!   itself, right after nblks is read and pinned to 1 (seq 7), for the exact condition.
!
! nsmat, nmass, nhmat, nqmat, nldfl, kgmat, nswkw, uwcpl, nflow, ECWPIPE (material_class_counts),
!   kinit/winit/neuman/equvs/nbspring/outind/nbackdT/ninistn (init_and_blocks),
!   stabpw/kglb/balgor/upliftin (problem_type), ntsmat/nthmat/kstat/ground_inf/src/
!   nextrf/submodel (special_counts), res_* (res_flags), the FSI/newmark/equvs_process/
!   appear_level/force_process/order_time_mdofn records: read and validated for
!   iostat only, NOT pinned. docs/m2/state-field-map.toml documents these as "0 on both
!   cases" or "unused switch" WITHOUT the "pinned guard: keeps control flow on static_2d
!   path" language used for the fields this module does pin -- i.e. the note is an
!   OBSERVATION about the two golden decks, not a claim that a different value takes the
!   model outside static-q4/1. Pinning them anyway would silently narrow the whitelist
!   below what SS5 actually describes. If M4's shadow-mode diff (A-shadow) or the bridge
!   comparison (A-bridge) ever turns up a real divergence traceable to one of these,
!   that is new evidence for a real pin, not something this parser should have guessed.
module yl_adapter_model

  use iso_fortran_env, only: int32, real64, iostat_end
  use yl_problem_optional, only: opt_set
  use yl_problem_types, only: section_t, interactions_t, output_t, &
                               output_field_t, activation_t
  use yl_problem_builder, only: problem_builder_t, builder_set_mesh_dimension, &
                                 builder_set_interactions, builder_failed
  use yl_problem_errors, only: problem_errors_t, source_location_t, make_source_location, &
                                make_problem_error, PE_INVALID_INPUT, PE_STAGE_ADAPT
  use yl_problem_deck_residue, only: deck_residue_t
  use yl_problem_existence, only: deck_existence_t
  use yl_adapter_parts, only: step_parts_t, deck_context_t, solver_parts_t, section_parts_t, &
                               LEN_TYPE_ABC, reject_dialect

  implicit none
  private

  public :: parse_glb


  character(len=*), parameter :: SITE_FILE = '.glb'

contains

  ! RD: many (see below) -- one call per .glb record, in legacy call order.
  !
  ! `ctx` (adapter-contract.md SS2.2) is intent(inout) here -- this is the ONE parser that
  ! FILLS it, from the group-1 element kind and the switches every other parser needs to
  ! size a read or pick a branch, so that yl_adapter_mesh's own NDIMN=2/NNODE_Q4=4
  ! hardcoding (its module header names this exact gap) has a real value to consult
  ! instead.
  !
  ! `sparts`/`secparts` are not in the illustrative signature the contract text first
  ! showed for parse_glb (that snippet predates solver_parts_t/section_parts_t and was
  ! never updated for either), but by the time section_parts_t landed (SS2.4) the
  ! contract itself names this as the third instance of the same shape: an object the
  ! model keeps whole (`solver`, `sections[]`) that the deck splits across files, so this
  ! parser fills its leaves in the shared aggregate exactly as it does for `parts`, and
  ! never calls `builder_set_solver` / `builder_add_section` itself. `sections[].thickness`
  ! is `.mat`'s leaf (read AFTER .glb, Fem.f90:117 then :191) and is left unset here.
  subroutine parse_glb(unit, ctx, b, parts, sparts, secparts, residue, existence, errors)
    integer, intent(in) :: unit
    type(deck_context_t), intent(inout) :: ctx
    type(problem_builder_t), intent(inout) :: b
    type(step_parts_t), intent(inout) :: parts
    type(solver_parts_t), intent(inout) :: sparts
    type(section_parts_t), intent(inout) :: secparts
    !> Carries out the 13 `.glb` values ADR-0003 does not model. Filled only once every
    !> gate below has accepted the deck.
    type(deck_residue_t), intent(inout) :: residue
    !> The existence face (ADR-0009). `.glb` supplies its only row so far.
    type(deck_existence_t), intent(inout) :: existence
    type(problem_errors_t), intent(inout) :: errors

    integer(int32) :: ios
    character(len=256) :: iomsg_buf
    type(source_location_t) :: loc
    character(len=80) :: text

    ! sizes_and_switches (Global.f90:694)
    integer(int32) :: npoin, npoinb, nelem, ndimn, nmats, ngroup
    integer(int32) :: ntlink, mat_curve, meshc, rmesh, level_set_problem, ljdp, stab_matde
    character(len=20) :: outplot
    real(real64) :: kstab

    ! init_and_blocks (Global.f90:762)
    integer(int32) :: ninit, kinit, winit, nblks, nlinks, nonsym
    integer(int32) :: outinp, outintr, outintw, neuman, equvs
    character(len=50) :: type_ABC
    integer(int32) :: block_stab, nbackf, nbspring, ebody, outind, nbackdT, ninistn

    ! problem_type (Global.f90:789)
    character(len=50) :: type_problem, type_solver, type_load
    integer(int32) :: type_nl, stabpw, nlayer, kglb, state_change, Bparameter, balgor, upliftin

    ! material_class_counts (Global.f90:815)
    integer(int32) :: nmass, nsmat, nhmat, nqmat, nldfl, kgmat, nswkw, uwcpl, NGRAV, nflow, ECWPIPE

    ! special_counts (Global.f90:833)
    integer(int32) :: ntsmat, nthmat, kstat, ground_inf, src, nextrf, submodel

    ! mdofn / lmdofn / order_time_mdofn (Global.f90:950,955,957)
    integer(int32) :: mdofn
    integer(int32), allocatable :: lmdofn(:), order_time_mdofn(:)

    ! newmark (Global.f90:961)
    real(real64) :: beeta1, beeta2, theta1

    ! per-ngroup arrays (Global.f90:976,983,989,998,1015,1023)
    integer(int32), allocatable :: equvs_process(:), appear_level(:)
    integer(int32), allocatable :: appear_process(:), matno_process(:)
    integer(int32), allocatable :: force_process(:), average_appear(:)

    ! gid_flags (Global.f90:1027) -- 20 GiD result-write flags, one .glb record
    integer(int32) :: gid_u, gid_s, gid_ms, gid_f, gid_rot, gid_v, gid_a, gid_T, gid_P, gid_Pv
    integer(int32) :: gid_ep, gid_Y, gid_FC, gid_Ns, gid_Ss, gid_Mxy, gid_bem, gid_wh, gid_wv, gid_bcs

    ! res_flags (Global.f90:1032) -- 17 binary .res write flags, not_migrated
    integer(int32) :: res_u, res_s, res_ms, res_f, res_rot, res_v, res_a, res_T, res_P, res_Pv
    integer(int32) :: res_ep, res_Y, res_FC, res_Ns, res_Ss, res_Tv, res_Pa

    ! fsi_params (Global.f90:1058) -- M7.6 scope, not_migrated
    integer(int32) :: Icaddmass, ifswater
    real(real64) :: swlifs2006, toth, ifsgravity, absorb, alfa_p4, stiff_p4

    ! crack_and_beam (Global.f90:1062) -- concrete damage / beam local axes, not_migrated.
    ! listglocbeam/lelenrt are allocated to the SAME bounds legacy gives them
    ! (Global.f90:1054 `allocate(listglocbeam(ngroup))`, :708 `allocate(...,lelenrt(nelem),...)`)
    ! so the `(1:nlocalbeam)`/`(1:ndimnrt)` slices in the single combined read below can
    ! never run past this parser's own storage regardless of what nlocalbeam/ndimnrt turn
    ! out to be -- ngroup and nelem are both already known by this point in the sequence.
    real(real64) :: ftcrack, coefMpa, ktan1, ktan2
    integer(int32) :: ikindks, doubsig, nlocalbeam, ndimnrt
    integer(int32), allocatable :: listglocbeam(:), lelenrt(:)

    ! transform_and_mif (Global.f90:1075) -- not_migrated except the ntrans pin
    integer(int32) :: ntrans, nlaymif, ifixvar0_inpb
    real(real64) :: epsMIFb, gamaMIF, camif, dxmif

    ! block-indexed arrays (Global.f90:1079,1084,1089,1093) -- sized nblks, pinned to 1
    ! by the time these are read (init_and_blocks, seq 7, runs first).
    real(real64), allocatable :: hdam(:), water_level(:)
    integer(int32), allocatable :: modf_dis_blocks(:), uinitial(:)

    ! group header loop (Global.f90:1216) and its per-field sub-records
    integer(int32) :: igroup, ifield
    character(len=10) :: gname, gspecial, gsptype
    character(len=20) :: gkname
    integer(int32) :: gindex
    character(len=2) :: gclass
    integer(int32) :: gnrfields
    character(len=5) :: gfieldid
    integer(int32) :: gnelgroup, gmatno, gtype_nalgo, gtype_stiff, gtype_ecoint, gilayer
    real(real64) :: gelcod_local
    integer(int32) :: ggroup_inf, guplift_ic, gliquj
    integer(int32), allocatable :: gtype_mass(:)
    real(real64) :: galfa, gbeta
    integer(int32), allocatable :: gorder_time(:, :)
    integer(int32) :: point_direct(2)
    integer(int32) :: nfdof
    integer(int32), allocatable :: glistdof(:)
    type(section_t) :: sec
    type(activation_t), allocatable :: activation(:)

    ! tension/contact joint, contact_point_to_point, link_concrete_* (Global.f90:1812
    ! onward) -- all empty_section on both golden decks, M6.6/M6.8/M9 scope.
    integer(int32) :: tsel
    integer(int32) :: ngaps, ngapb, contactpe, miter_bt, iblks_bt, nonsbt, xlwsol
    integer(int32) :: method_gapi, miter_state, restart_ctt, istatec
    real(real64) :: tor_bt, damp_ctt
    character(len=50) :: type_solver_ctt
    integer(int32) :: nrcsteel, nwcpipe

    type(interactions_t) :: inter
    type(output_t) :: outp
    integer(int32) :: ctx_gindex, ctx_nnode
    ctx_gindex = 0_int32
    ctx_nnode = 0_int32

    ! -------------------------------------------------------------------------------
    ! seq 1 -- RD: GLB.global_data.title#1 (Global.f90:691)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(691_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 2 -- RD: GLB.global_data.sizes_and_switches (Global.f90:694)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) npoin, npoinb, nelem, ndimn, nmats, ngroup, &
      ntlink, outplot, kstab, mat_curve, meshc, rmesh, level_set_problem, ljdp, stab_matde
    loc = here(694_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'mesh', 'sizes_and_switches', iomsg_buf); return
    end if
    ! Pinned switches sharing this record (state-field-map.toml note on
    ! steps0.output.format: "ntlink,kstab,mat_curve,meshc,rmesh,level_set_problem,ljdp
    ! are unused_switch and pinned 0"; stab_matde shares the record but is NOT flat-zero
    ! pinned -- checked separately below, after nblks is known, see the module header's
    ! 2026-09-08 correction note). rmesh is checked FIRST and separately here because it
    ! is also the guard for the reached_only read at Global.f90:722 (module
    ! header note): pinning it here makes that branch unreachable, which is this
    ! parser's way of reproducing rather than skipping the guard.
    if (rmesh /= 0_int32) then
      call reject_dialect(errors, 'A-GLB', 'rmesh-nonzero', loc, actual=itoa(rmesh), expected='0')
      return
    end if
    if (ntlink /= 0_int32) then
      call reject_pinned(errors, loc, 'ntlink-nonzero', ntlink); return
    end if
    if (mat_curve /= 0_int32) then
      call reject_pinned(errors, loc, 'mat_curve-nonzero', mat_curve); return
    end if
    if (meshc /= 0_int32) then
      call reject_pinned(errors, loc, 'meshc-nonzero', meshc); return
    end if
    if (level_set_problem /= 0_int32) then
      call reject_pinned(errors, loc, 'level_set_problem-nonzero', level_set_problem); return
    end if
    if (ljdp /= 0_int32) then
      call reject_pinned(errors, loc, 'ljdp-nonzero', ljdp); return
    end if
    ! stab_matde is NOT checked here (module header note below on the correction): its
    ! meaning depends on nblks, read only at seq 7 (init_and_blocks). Checked there.
    if (abs(kstab) > 0.0_real64) then
      call reject_dialect(errors, 'A-GLB', 'kstab-nonzero', loc, actual=rtoa(kstab), expected='0.0')
      return
    end if
    if (trim(outplot) /= 'GIDR') then
      call reject_dialect(errors, 'A-GLB', 'outplot-not-gidr', loc, actual=trim(outplot), &
                          expected='GIDR')
      return
    end if
    ! mesh.dimension: a real ProblemState field. Stored as read; the M3 capability gate
    ! (yl_problem_pipeline.f90, item 'analysis.dimension') is the whitelist judge for 2D,
    ! not this parser (module header, case (a)).
    call builder_set_mesh_dimension(b, ndimn, loc, errors)
    if (builder_failed(b)) return

    ! seq 3 -- RD: GLB.global_data.title#2 (Global.f90:720)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(720_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 4, GLB.global_data.reached_only_Global_691 (Global.f90:722): "if(rmesh/=0)
    ! read valv1,valv2" -- unreachable, rmesh pinned 0 above. Not read.

    ! seq 5 -- RD: GLB.global_data.title#3 (Global.f90:725) -- ndivide title; no value
    ! read when rmesh==0 (reader-inventory note), consistent with the pin above.
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(725_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 6 -- RD: GLB.global_data.title#4 (Global.f90:759)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(759_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 7 -- RD: GLB.global_data.init_and_blocks (Global.f90:762)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) ninit, kinit, winit, nblks, nlinks, nonsym, &
      outinp, outintr, outintw, neuman, equvs, type_ABC, block_stab, nbackf, nbspring, ebody, &
      outind, nbackdT, ninistn
    loc = here(762_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'solver', 'init_and_blocks', iomsg_buf); return
    end if
    if (nblks /= 1_int32) then
      call reject_dialect(errors, 'A-GLB', 'multiple-blocks', loc, actual=itoa(nblks), expected='1')
      return
    end if
    ! stab_matde (read at seq 2, sizes_and_switches): CORRECTED 2026-09-08 -- an earlier
    ! reading of docs/m2/state-field-map.toml's note had this backwards (both golden
    ! decks carry 99999, which this parser used to reject outright). Legacy's guard is
    ! `if(iblks>=stab_matde) call stab_initialize` (Fem.f90:2441,3030,3661,4869): with
    ! `iblks<=nblks` always true on this whitelist (nblks==1, just pinned above),
    ! `stab_matde>nblks` makes the condition FALSE, i.e. stab_initialize never runs and
    ! the feature is DISABLED -- 99999 is a disable sentinel, not a violated pin.
    ! `stab_matde<=nblks` is the unsupported case: it would run stab_initialize, which
    ! this build does not reproduce.
    if (stab_matde <= nblks) then
      call reject_dialect(errors, 'A-GLB', 'stab-matde-enabled', loc, actual=itoa(stab_matde), &
                          expected='> '//itoa(nblks))
      return
    end if
    if (nlinks /= 0_int32) then
      call reject_pinned(errors, loc, 'nlinks-nonzero', nlinks); return
    end if
    if (block_stab /= 0_int32) then
      call reject_pinned(errors, loc, 'block_stab-nonzero', block_stab); return
    end if
    if (nbackf /= 0_int32) then
      call reject_pinned(errors, loc, 'nbackf-nonzero', nbackf); return
    end if
    if (ebody /= 0_int32) then
      call reject_pinned(errors, loc, 'ebody-nonzero', ebody); return
    end if
    if (ninit /= 0_int32) then
      call reject_pinned(errors, loc, 'ninit-nonzero', ninit); return
    end if
    ! solver.symmetric: legacy `nonsym` is a 0/1 flag with INVERTED sense
    ! (yl_problem_types.f90: "type(opt_logical) :: symmetric ... nonsym is a 0/1 flag with
    ! inverted sense, the bridge converts"). This parser is that conversion boundary.
    call opt_set(sparts%solver%symmetric, nonsym == 0_int32)
    ! interactions.absorbing.type: a real ProblemState field with NO capability-gate row
    ! (checked: capability_gate in yl_problem_pipeline.f90 never mentions 'interactions'),
    ! so this parser is the only whitelist guard it has. 'MIF' changes the .pre
    ! set_header record shape (state-field-map.toml note) that .pre's own parser (a
    ! different module) does not implement.
    if (trim(type_ABC) /= 'FIX') then
      call reject_dialect(errors, 'A-GLB', 'absorbing-not-fix', loc, actual=trim(type_ABC), &
                          expected='FIX')
      return
    end if
    call opt_set(inter%absorbing%type, trim(type_ABC))

    ! seq 8 -- RD: GLB.global_data.title#5 (Global.f90:786)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(786_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 9 -- RD: GLB.global_data.problem_type (Global.f90:789)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) type_problem, type_solver, type_load, type_nl, &
      stabpw, nlayer, kglb, state_change, Bparameter, balgor, upliftin
    loc = here(789_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'steps[0]', 'problem_type', iomsg_buf); return
    end if
    if (nlayer /= 0_int32) then
      call reject_dialect(errors, 'A-GLB', 'nlayer-nonzero', loc, actual=itoa(nlayer), expected='0')
      return
    end if
    if (state_change /= 0_int32) then
      call reject_pinned(errors, loc, 'state_change-nonzero', state_change)
      return
    end if
    if (Bparameter /= 0_int32) then
      call reject_pinned(errors, loc, 'Bparameter-nonzero', Bparameter); return
    end if
    ! type_nl: no capability-gate row (checked). ALGORT's kresl=1-at-first-iteration path
    ! (state-field-map.toml note, Fem.f90:15451) is only confirmed for the value 5; any
    ! other value changes iteration control this build's ProblemState.controls does not
    ! model narrowly enough to trust.
    if (type_nl /= 5_int32) then
      call reject_dialect(errors, 'A-GLB', 'nonlinear-type-not-5', loc, actual=itoa(type_nl), &
                          expected='5')
      return
    end if
    call opt_set(parts%procedure_, trim(type_problem))
    call opt_set(parts%load_mode, trim(type_load))
    call opt_set(parts%controls%nonlinear_type, type_nl)
    call opt_set(sparts%solver%linear, trim(type_solver))

    ! seq 10 -- RD: GLB.global_data.title#6 (Global.f90:807)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(807_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 11, GLB.global_data.reached_only_Global_772 (Global.f90:810): "if(nlayer==2)
    ! read type_nl_layer1,type_nl_layer2,solver_iter" -- unreachable, nlayer pinned 0
    ! above. Not read.

    ! seq 12 -- RD: GLB.global_data.title#7 (Global.f90:812)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(812_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 13 -- RD: GLB.global_data.material_class_counts (Global.f90:815)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) nmass, nsmat, nhmat, nqmat, nldfl, kgmat, &
      nswkw, uwcpl, NGRAV, nflow, ECWPIPE
    loc = here(815_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'steps[0].load.gravity', 'material_class_counts', iomsg_buf)
      return
    end if
    ! load.gravity.enabled: real content (0 or 1), gated downstream (capability item
    ! 'load.gravity_enabled'). Stored as-is.
    call opt_set(parts%load%gravity%enabled, NGRAV)

    ! seq 14 -- RD: GLB.global_data.title#8 (Global.f90:818) -- nfreeflownode title
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(818_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 15 -- RD: GLB.global_data.title#9 (Global.f90:830)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(830_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 16 -- RD: GLB.global_data.special_counts (Global.f90:833)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) ntsmat, nthmat, kstat, ground_inf, src, &
      nextrf, submodel
    loc = here(833_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'control.glb', 'special_counts', iomsg_buf); return
    end if

    ! seq 17 -- RD: GLB.global_data.title#10 (Global.f90:948)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(948_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 18 -- RD: GLB.global_data.mdofn (Global.f90:950)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) mdofn
    loc = here(950_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'derived.counts', 'mdofn', iomsg_buf); return
    end if
    ! mdofn is "derived" (not authored) but static-q4/1 is a SINGLE displacement field in
    ! ndimn dimensions, so mdofn = ndimn is the only value consistent with that shape; a
    ! larger mdofn means an extra field (temperature, pore pressure, ...) this build does
    ! not carry.
    if (mdofn /= ndimn) then
      call reject_dialect(errors, 'A-GLB', 'mdofn-mismatch', loc, actual=itoa(mdofn), &
                          expected=itoa(ndimn))
      return
    end if
    allocate (lmdofn(mdofn), order_time_mdofn(mdofn))

    ! seq 19 -- RD: GLB.global_data.lmdofn (Global.f90:955)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) lmdofn(1:mdofn)
    loc = here(955_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'derived.dof', 'lmdofn', iomsg_buf); return
    end if

    ! seq 20 -- RD: GLB.global_data.order_time_mdofn (Global.f90:957)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) order_time_mdofn(1:mdofn)
    loc = here(957_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'control.glb', 'order_time_mdofn', iomsg_buf); return
    end if

    ! seq 21 -- RD: GLB.global_data.title#11 (Global.f90:959)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(959_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 22 -- RD: GLB.global_data.newmark (Global.f90:961) -- static slice ignores these
    read (unit, *, iostat=ios, iomsg=iomsg_buf) beeta1, beeta2, theta1
    loc = here(961_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'control.glb', 'newmark', iomsg_buf); return
    end if

    ! seq 23 -- RD: GLB.global_data.title#12 (Global.f90:973)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(973_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 24 -- RD: GLB.global_data.equvs_process (Global.f90:976)
    allocate (equvs_process(max(ngroup, 0_int32)))
    read (unit, *, iostat=ios, iomsg=iomsg_buf) equvs_process(1:ngroup)
    loc = here(976_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'control.glb', 'equvs_process', iomsg_buf); return
    end if

    ! seq 25 -- RD: GLB.global_data.title#13 (Global.f90:980)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(980_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 26 -- RD: GLB.global_data.appear_level (Global.f90:983)
    allocate (appear_level(max(ngroup, 0_int32)))
    read (unit, *, iostat=ios, iomsg=iomsg_buf) appear_level(1:ngroup)
    loc = here(983_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'control.glb', 'appear_level', iomsg_buf); return
    end if

    ! seq 27 -- RD: GLB.global_data.title#14 (Global.f90:985)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(985_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 28 -- RD: GLB.global_data.appear_process (Global.f90:989), loop iblk=1..nblks.
    ! nblks==1 (pinned above), so this is exactly one record; iblk=1 IS steps[0]
    ! (state-field-map.toml note: "YL iblks=1 maps to steps[0]"). Column 0 (the block-0
    ! initial state) is never read from file (zeroed at Global.f90:968) and the
    ! Fem.f90:1719-1720 mutation it can trigger needs column0==1, which is therefore
    ! always false on this path -- so the value read here IS the value at model_ready,
    ! with no further transform needed.
    allocate (appear_process(max(ngroup, 0_int32)))
    read (unit, *, iostat=ios, iomsg=iomsg_buf) appear_process(1:ngroup)
    loc = here(989_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'steps[0].activation', 'appear_process', iomsg_buf); return
    end if

    ! seq 29 -- RD: GLB.global_data.title#15 (Global.f90:994)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(994_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 30 -- RD: GLB.global_data.matno_process (Global.f90:998), loop iblk=1..nblks;
    ! same single-block simplification as appear_process above.
    allocate (matno_process(max(ngroup, 0_int32)))
    read (unit, *, iostat=ios, iomsg=iomsg_buf) matno_process(1:ngroup)
    loc = here(998_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'steps[0].activation', 'matno_process', iomsg_buf); return
    end if

    ! seq 31 -- RD: GLB.global_data.title#16 (Global.f90:1012)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(1012_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 32 -- RD: GLB.global_data.force_process (Global.f90:1015)
    allocate (force_process(max(ngroup, 0_int32)))
    read (unit, *, iostat=ios, iomsg=iomsg_buf) force_process(1:ngroup)
    loc = here(1015_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'control.glb', 'force_process', iomsg_buf); return
    end if

    ! seq 33 -- RD: GLB.global_data.title#17 (Global.f90:1021)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(1021_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 34 -- RD: GLB.global_data.average_appear (Global.f90:1023)
    allocate (average_appear(max(ngroup, 0_int32)))
    read (unit, *, iostat=ios, iomsg=iomsg_buf) average_appear(1:ngroup)
    loc = here(1023_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'steps[0].output', 'stress_averaging', iomsg_buf); return
    end if

    ! seq 35 -- RD: GLB.global_data.title#18 (Global.f90:1025)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(1025_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 36 -- RD: GLB.global_data.gid_flags (Global.f90:1027) -- one record, 20 flags
    read (unit, *, iostat=ios, iomsg=iomsg_buf) gid_u, gid_s, gid_ms, gid_f, gid_rot, gid_v, &
      gid_a, gid_T, gid_P, gid_Pv, gid_ep, gid_Y, gid_FC, gid_Ns, gid_Ss, gid_Mxy, gid_bem, &
      gid_wh, gid_wv, gid_bcs
    loc = here(1027_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'steps[0].output.field', 'gid_flags', iomsg_buf); return
    end if
    call opt_set(outp%field%u, gid_u); call opt_set(outp%field%s, gid_s)
    call opt_set(outp%field%ms, gid_ms); call opt_set(outp%field%f, gid_f)
    call opt_set(outp%field%rot, gid_rot); call opt_set(outp%field%v, gid_v)
    call opt_set(outp%field%a, gid_a); call opt_set(outp%field%T, gid_T)
    call opt_set(outp%field%P, gid_P); call opt_set(outp%field%Pv, gid_Pv)
    call opt_set(outp%field%ep, gid_ep); call opt_set(outp%field%Y, gid_Y)
    call opt_set(outp%field%FC, gid_FC); call opt_set(outp%field%Ns, gid_Ns)
    call opt_set(outp%field%Ss, gid_Ss); call opt_set(outp%field%Mxy, gid_Mxy)
    call opt_set(outp%field%bem, gid_bem); call opt_set(outp%field%wh, gid_wh)
    call opt_set(outp%field%wv, gid_wv); call opt_set(outp%field%bcs, gid_bcs)
    call opt_set(outp%format, trim(outplot))

    ! seq 37 -- RD: GLB.global_data.title#19 (Global.f90:1030)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(1030_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 38 -- RD: GLB.global_data.res_flags (Global.f90:1032) -- not_migrated (binary
    ! .res writer, no ProblemState output.res.* component); read for cursor only.
    read (unit, *, iostat=ios, iomsg=iomsg_buf) res_u, res_s, res_ms, res_f, res_rot, res_v, &
      res_a, res_T, res_P, res_Pv, res_ep, res_Y, res_FC, res_Ns, res_Ss, res_Tv, res_Pa
    loc = here(1032_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'output.res', 'res_flags', iomsg_buf); return
    end if

    ! seq 39 -- RD: GLB.global_data.title#20 (Global.f90:1056)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(1056_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 40 -- RD: GLB.global_data.fsi_params (Global.f90:1058) -- M7.6 scope, not_migrated
    read (unit, *, iostat=ios, iomsg=iomsg_buf) Icaddmass, swlifs2006, toth, ifswater, &
      ifsgravity, absorb, alfa_p4, stiff_p4
    loc = here(1058_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'control.glb', 'fsi_params', iomsg_buf); return
    end if

    ! seq 41 -- RD: GLB.global_data.title#21 (Global.f90:1060)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(1060_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 42 -- RD: GLB.global_data.crack_and_beam (Global.f90:1062). listglocbeam/lelenrt
    ! are pre-sized to ngroup/nelem (see the declaration comment above) so the
    ! `(1:nlocalbeam)`/`(1:ndimnrt)` slices are always in bounds.
    allocate (listglocbeam(max(ngroup, 0_int32)), lelenrt(max(nelem, 0_int32)))
    read (unit, *, iostat=ios, iomsg=iomsg_buf) ftcrack, coefMpa, ikindks, doubsig, ktan1, &
      ktan2, nlocalbeam, ndimnrt, listglocbeam(1:nlocalbeam), lelenrt(1:ndimnrt)
    loc = here(1062_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'control.glb', 'crack_and_beam', iomsg_buf); return
    end if
    if (nlocalbeam /= 0_int32 .or. ndimnrt /= 0_int32) then
      call reject_dialect(errors, 'A-GLB', 'crack-beam-nonzero', loc, &
                          actual=itoa(nlocalbeam)//','//itoa(ndimnrt), expected='0,0')
      return
    end if

    ! seq 43 -- RD: GLB.global_data.title#22 (Global.f90:1073)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(1073_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 44 -- RD: GLB.global_data.transform_and_mif (Global.f90:1075)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) ntrans, nlaymif, epsMIFb, gamaMIF, &
      ifixvar0_inpb, camif, dxmif
    loc = here(1075_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'control.glb', 'transform_and_mif', iomsg_buf); return
    end if
    if (ntrans /= 0_int32) then
      call reject_pinned(errors, loc, 'ntrans-nonzero', ntrans); return
    end if

    ! seq 45 -- RD: GLB.global_data.title#23 (Global.f90:1077)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(1077_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 46 -- RD: GLB.global_data.hdam (Global.f90:1079) -- nblks==1
    allocate (hdam(1))
    read (unit, *, iostat=ios, iomsg=iomsg_buf) hdam(1:nblks)
    loc = here(1079_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'control.glb', 'hdam', iomsg_buf); return
    end if

    ! seq 47 -- RD: GLB.global_data.title#24 (Global.f90:1082)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(1082_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 48 -- RD: GLB.global_data.water_level (Global.f90:1084) -- -99 = none
    allocate (water_level(1))
    read (unit, *, iostat=ios, iomsg=iomsg_buf) water_level(1:nblks)
    loc = here(1084_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'control.glb', 'water_level', iomsg_buf); return
    end if

    ! seq 49 -- RD: GLB.global_data.title#25 (Global.f90:1087)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(1087_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 50 -- RD: GLB.global_data.modf_dis_blocks (Global.f90:1089)
    allocate (modf_dis_blocks(1))
    read (unit, *, iostat=ios, iomsg=iomsg_buf) modf_dis_blocks(1:nblks)
    loc = here(1089_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'control.glb', 'modf_dis_blocks', iomsg_buf); return
    end if

    ! seq 51 -- RD: GLB.global_data.title#26 (Global.f90:1091)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(1091_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 52 -- RD: GLB.global_data.uinitial (Global.f90:1093)
    allocate (uinitial(1))
    read (unit, *, iostat=ios, iomsg=iomsg_buf) uinitial(1:nblks)
    loc = here(1093_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'control.glb', 'uinitial', iomsg_buf); return
    end if
    if (any(uinitial(1:nblks) /= 0_int32)) then
      call reject_pinned(errors, loc, 'uinitial-nonzero', uinitial(1)); return
    end if

    ! seq 53 -- RD: GLB.global_data.title#27 (Global.f90:1099) -- backf() title; nbackf=0
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(1099_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 54 -- RD: GLB.global_data.title#28 (Global.f90:1140) -- ILINKS title; nlinks=0
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(1140_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 55 -- RD: GLB.global_data.title#29 (Global.f90:1155) -- tLINKS title; ntlink=0
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(1155_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! ---------------------------------------------------------------------------------
    ! INTERLEAVING (module header): all of .cor is read here by yl_adapter_mesh, on a
    ! separate unit. No action for this parser.
    ! ---------------------------------------------------------------------------------

    ! seq 56-60 -- RD: GLB.global_data.title#30..#34 (Global.f90:1192,1195,1197,1199,1201)
    ! -- five group-section title lines, read once regardless of ngroup.
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(1192_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(1195_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(1197_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(1199_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(1201_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    if (ngroup <= 0_int32) then
      allocate (secparts%sections(0))
      allocate (activation(0))
      allocate (ctx%nelgroup(0), ctx%group_matno(0), ctx%group_kind(0))
    else
      allocate (secparts%sections(ngroup))
      allocate (activation(ngroup))
      allocate (ctx%nelgroup(ngroup), ctx%group_matno(ngroup), ctx%group_kind(ngroup))
      do igroup = 1, ngroup
        ! seq 61 -- RD: GLB.global_data.group_header (Global.f90:1216), loop igroup=1..ngroup
        read (unit, *, iostat=ios, iomsg=iomsg_buf) gname, gkname, gindex, gclass, &
          gnrfields, gfieldid, gspecial, gsptype, gnelgroup, gmatno, gtype_nalgo, &
          gtype_stiff, gtype_ecoint, gilayer, gelcod_local, ggroup_inf, guplift_ic, gliquj
        loc = here(1216_int32, index=igroup)
        if (ios /= 0) then
          call fail_read(errors, loc, 'sections', 'group_header', iomsg_buf, index=igroup)
          return
        end if

        ! Undocumented guard (module header): no reader-inventory entry, format
        ! confirmed from Global.f90:237 (`point_direct(2)`, plain integers).
        if (gindex == 20_int32 .or. gindex == 21_int32 .or. gindex == 22_int32 .or. &
            gindex == 26_int32) then
          read (unit, *, iostat=ios, iomsg=iomsg_buf) point_direct
          loc = here(1250_int32, index=igroup)
          if (ios /= 0) then
            call fail_read(errors, loc, 'sections', 'point_direct', iomsg_buf, index=igroup)
            return
          end if
        end if

        if (allocated(gtype_mass)) deallocate (gtype_mass)
        if (allocated(gorder_time)) deallocate (gorder_time)
        allocate (gtype_mass(gnrfields), gorder_time(2, gnrfields))

        ! seq 62 -- RD: GLB.global_data.group_mass_damping (Global.f90:1242) -- not_migrated
        read (unit, *, iostat=ios, iomsg=iomsg_buf) gtype_mass(1:gnrfields), galfa, gbeta
        loc = here(1242_int32, index=igroup)
        if (ios /= 0) then
          call fail_read(errors, loc, 'sections', 'group_mass_damping', iomsg_buf, index=igroup)
          return
        end if

        ! seq 63 -- RD: GLB.global_data.group_order_time (Global.f90:1245) -- not_migrated
        read (unit, *, iostat=ios, iomsg=iomsg_buf) &
          (gorder_time(:, ifield), ifield=1, gnrfields)
        loc = here(1245_int32, index=igroup)
        if (ios /= 0) then
          call fail_read(errors, loc, 'sections', 'group_order_time', iomsg_buf, index=igroup)
          return
        end if

        do ifield = 1, gnrfields
          ! seq 64 -- RD: GLB.global_data.group_nfdof (Global.f90:1255), loop ifield
          read (unit, *, iostat=ios, iomsg=iomsg_buf) nfdof
          loc = here(1255_int32, index=igroup)
          if (ios /= 0) then
            call fail_read(errors, loc, 'derived.counts', 'group_nfdof', iomsg_buf, &
              index=igroup)
            return
          end if
          if (allocated(glistdof)) deallocate (glistdof)
          allocate (glistdof(max(nfdof, 0_int32)))
          ! seq 65 -- RD: GLB.global_data.group_listdof (Global.f90:1263), loop ifield
          read (unit, *, iostat=ios, iomsg=iomsg_buf) glistdof(1:nfdof)
          loc = here(1263_int32, index=igroup)
          if (ios /= 0) then
            call fail_read(errors, loc, 'derived.dof', 'group_listdof', iomsg_buf, index=igroup)
            return
          end if
        end do

        ! secparts%sections(igroup): only the leaves docs/m2/state-field-map.toml owns as
        ! ProblemState.sections[].* with source GLB.global_data.group_header. material
        ! and material_header are NOT set here (module header: both are `derived`, from
        ! mesh.elements[].material, populated while reading .ele -- a file this module
        ! does not own). thickness is NOT set here either: it is .mat's leaf
        ! (adapter-contract.md SS2.4, read AFTER .glb, Fem.f90:117 then :191) -- left
        ! unset for parse_mat to fill, and the driver publishes the assembled whole with
        ! one builder_add_section call per section, never this parser.
        call opt_set(sec%name, trim(gkname))
        call opt_set(sec%element, trim(gname))
        call opt_set(sec%element_kind, gindex)
        call opt_set(sec%class, trim(gclass))
        call opt_set(sec%fields, trim(gfieldid))
        call opt_set(sec%formulation, trim(gsptype))
        call opt_set(sec%special, trim(gspecial))
        call opt_set(sec%algorithm, gtype_nalgo)
        call opt_set(sec%stiffness_kind, gtype_stiff)
        call opt_set(sec%stress_recovery, gtype_ecoint)
        call opt_set(sec%layer, gilayer)
        call opt_set(sec%uplift, guplift_ic)
        call opt_set(sec%liquefaction, gliquj)
        call opt_set(sec%local_axes, gelcod_local)
        secparts%sections(igroup) = sec

        ! steps[0].activation[igroup]: fully .glb-sourced (appear_process/matno_process
        ! at block 1, both read above before this loop). Owned entirely by this parser
        ! per yl_adapter_parts.f90's leaf table.
        call opt_set(activation(igroup)%material, matno_process(igroup))
        call opt_set(activation(igroup)%active, appear_process(igroup))

        ! deck_context_t (adapter-contract.md SS2.2) describes "the (single) group"; take
        ! group 1's element kind/node count as the value every other parser sees. The
        ! nnode mapping is legacy compile-time DATA (Elements.f90:135 `q4_define(elkn(5))`
        ! via `kinddefine`, not a deck value) -- 5 is the only kind this parser can name
        ! with confidence; anything else is 0 and lets the capability gate's rejection of
        ! that element_kind be the visible failure rather than a guessed node count.
        if (igroup == 1_int32) then
          ctx_gindex = gindex
          if (gindex == 5_int32) then
            ctx_nnode = 4_int32
          else
            ctx_nnode = 0_int32
          end if
        end if

        ! deck_context_t's per-section arrays (adapter-contract.md SS2.3, added after
        ! L2-a's first integration run): .ele carries no group boundary of its own, so
        ! parse_ele attributes its records to a section POSITIONALLY -- group 1 takes
        ! the first ctx%nelgroup(1) records, group 2 the next ctx%nelgroup(2), and so on.
        ! This parser is the only place gnelgroup/gmatno/gindex are ever seen, so it is
        ! the only place that can hand them on.
        ctx%nelgroup(igroup) = gnelgroup
        ctx%group_matno(igroup) = gmatno
        ctx%group_kind(igroup) = gindex

        ! ---------------------------------------------------------------------------
        ! INTERLEAVING (module header): this group's .ele elements are read here by
        ! yl_adapter_mesh (Elements.f90:1087, a separate unit), before legacy moves to
        ! the next group's header. No action for this parser.
        ! ---------------------------------------------------------------------------
      end do
    end if
    parts%activation = activation

    ! seq 66 -- RD: GLB.global_data.title#35 (Global.f90:1809) -- tension_joint title
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(1809_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 67 -- RD: GLB.global_data.tension_joint_count (Global.f90:1812) -- 0 on both cases
    read (unit, *, iostat=ios, iomsg=iomsg_buf) tsel
    loc = here(1812_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'empty_section', 'tension_joint_count', iomsg_buf); return
    end if
    if (tsel /= 0) then
      call reject_dialect(errors, 'A-GLB', 'tension-joint-nonzero', loc, actual=itoa(tsel), &
                          expected='0')
      return
    end if

    ! seq 68 -- RD: GLB.global_data.title#36 (Global.f90:1826) -- contact_joint title
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = here(1826_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 69 -- RD: GLB.global_data.contact_joint_count (Global.f90:1829) -- 0 on both cases
    read (unit, *, iostat=ios, iomsg=iomsg_buf) tsel
    loc = here(1829_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'empty_section', 'contact_joint_count', iomsg_buf); return
    end if
    if (tsel /= 0) then
      call reject_dialect(errors, 'A-GLB', 'contact-joint-nonzero', loc, actual=itoa(tsel), &
                          expected='0')
      return
    end if

    ! seq 70 -- RD: GLB.contact_point_to_point.title#1 (Global.f90:3466). `routine` here
    ! is contact_point_to_point, not global_data (reader-inventory), but it is still gunit
    ! (module header: read order is what this parser reproduces, not source line order --
    ! seq 70-71 run, on the file, before seq 72-73 even though link_concrete_and_steel's
    ! own source text sits earlier in Global.f90 than link_concrete_and_water_pipe's).
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = make_source_location(file=SITE_FILE, reader='contact_point_to_point', line=3466_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 71 -- RD: GLB.contact_point_to_point.contact_control (Global.f90:3469) --
    ! ngaps=ngapb=0 -> interactions empty on both golden decks (M6.6 scope)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) ngaps, ngapb, contactpe, miter_bt, tor_bt, &
      iblks_bt, nonsbt, xlwsol, method_gapi, miter_state, type_solver_ctt, restart_ctt, &
      damp_ctt, istatec
    loc = make_source_location(file=SITE_FILE, reader='contact_point_to_point', line=3469_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'empty_section', 'contact_control', iomsg_buf); return
    end if
    if (ngaps /= 0 .or. ngapb /= 0) then
      call reject_dialect(errors, 'A-GLB', 'contact-pairs-nonzero', loc,                        &
                          actual=itoa(ngaps)//'/'//itoa(ngapb), expected='0/0')
      return
    end if

    ! seq 72 -- RD: GLB.link_concrete_and_steel.title#1 (Global.f90:4678)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = make_source_location(file=SITE_FILE, reader='link_concrete_and_steel', line=4678_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 73 -- RD: GLB.link_concrete_and_steel.rc_steel_count (Global.f90:4681) -- 0 on
    ! both cases (M6.8 scope)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) nrcsteel
    loc = make_source_location(file=SITE_FILE, reader='link_concrete_and_steel', line=4681_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'empty_section', 'rc_steel_count', iomsg_buf); return
    end if
    if (nrcsteel /= 0) then
      call reject_dialect(errors, 'A-GLB', 'rc-steel-nonzero', loc, actual=itoa(nrcsteel), &
                          expected='0')
      return
    end if

    ! seq 74 -- RD: GLB.link_concrete_and_water_pipe.title#1 (Global.f90:4542)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) text
    loc = make_source_location(file=SITE_FILE, reader='link_concrete_and_water_pipe', &
                                line=4542_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'case', 'title', iomsg_buf); return
    end if

    ! seq 75 -- RD: GLB.link_concrete_and_water_pipe.water_pipe_count (Global.f90:4545) --
    ! 0 on both cases (M9 scope)
    read (unit, *, iostat=ios, iomsg=iomsg_buf) nwcpipe
    loc = make_source_location(file=SITE_FILE, reader='link_concrete_and_water_pipe', &
                                line=4545_int32)
    if (ios /= 0) then
      call fail_read(errors, loc, 'empty_section', 'water_pipe_count', iomsg_buf); return
    end if
    if (nwcpipe /= 0) then
      call reject_dialect(errors, 'A-GLB', 'water-pipe-nonzero', loc, actual=itoa(nwcpipe), &
                          expected='0')
      return
    end if

    ! -------------------------------------------------------------------------------
    ! All 75 .glb sites read. Commit the whole-aggregate leaves this parser owns.
    outp%stress_averaging = average_appear
    parts%output = outp

    ! interactions is not split across files (module header table has no second writer
    ! for it), so this is a direct, single builder call rather than a *_parts leaf.
    call builder_set_interactions(b, inter, here(762_int32), errors)
    if (builder_failed(b)) return

    ! deck_context_t (adapter-contract.md SS2.2): filled last, per its own header
    ! ("parse_glb sets this last; readers must check it").
    ctx%ndimn = ndimn
    ctx%ngroup = ngroup
    ctx%nnode = ctx_nnode
    ctx%element_kind = ctx_gindex
    ctx%type_abc = type_ABC
    ctx%nbackdt = nbackdT
    ctx%ntrans = ntrans
    ctx%filled = .true.

    ! ---- the 13 values .glb leaves in legacy's globals that ADR-0003 does not model ----
    ! Set HERE, at the end, for the same reason parse_inp sets its four after the gates:
    ! every one of these has already been through its rejection above, so a refused deck
    ! leaves the carrier untouched and a filled carrier means "this deck was accepted AND
    ! this is what it said". The gate and the carried value stay two independent sources;
    ! commit cross-checks them rather than deriving one from the other (1.6.2).
    ! Existence face (ADR-0009): predict reads this array once per dof per increment
    ! (Fem.f90:10752) although nothing observes its value at any checkpoint. The deck's
    ! values are carried, not a constant zero -- see existence-face.toml.
    existence%order_time_mdofn = order_time_mdofn

    call opt_set(residue%npoinb, npoinb)
    call opt_set(residue%stab_matde, stab_matde)
    call opt_set(residue%ninit, ninit)
    call opt_set(residue%nlinks, nlinks)
    call opt_set(residue%block_stab, block_stab)
    call opt_set(residue%nbackf, nbackf)
    call opt_set(residue%ebody, ebody)
    call opt_set(residue%nlayer, nlayer)
    call opt_set(residue%state_change, state_change)
    call opt_set(residue%bparameter, Bparameter)
    call opt_set(residue%nsmat, nsmat)
    call opt_set(residue%ntrans, ntrans)
    ! uinitial is the carrier's only array. It is [nblks] long in the map and legacy reads
    ! exactly nblks values into it (Global.f90:1093), so the carried copy is that slice --
    ! not the local's allocated length, which this file sizes at 1.
    if (allocated(residue%uinitial)) deallocate (residue%uinitial)
    allocate (residue%uinitial(nblks))
    residue%uinitial = uinitial(1:nblks)

  contains

    ! Every .glb source_location_t in this routine, in one place.
    function here(line, index) result(loc)
      integer(int32), intent(in) :: line
      integer(int32), intent(in), optional :: index
      type(source_location_t) :: loc
      if (present(index)) then
        loc = make_source_location(file=SITE_FILE, reader='global_data', line=line, &
                                    record=index)
      else
        loc = make_source_location(file=SITE_FILE, reader='global_data', line=line)
      end if
    end function here

  end subroutine parse_glb

  ! One malformed-.glb-record finding, in the shape adapter-contract.md SS4 describes.
  subroutine fail_read(errors, loc, object_path, field, iomsg_buf, index)
    type(problem_errors_t), intent(inout) :: errors
    type(source_location_t), intent(in) :: loc
    character(len=*), intent(in) :: object_path, field, iomsg_buf
    integer(int32), intent(in), optional :: index
    call errors%add(make_problem_error(code=PE_INVALID_INPUT, stage=PE_STAGE_ADAPT, &
                    rule_id='A-GLB/malformed-record', object_path=object_path, field=field, &
                    index=index, message='malformed .glb record: '//trim(iomsg_buf), &
                    source=loc))
  end subroutine fail_read

  ! Shorthand for the many "pinned guard: value 0 keeps control flow on static_2d path"
  ! switches (module header, case (b)): every one of them is pinned to 0 in
  ! docs/m2/state-field-map.toml, so the expected value is the literal '0' every time
  ! and only the observed value differs between call sites.
  !
  ! `condition` is passed in full and spelled out at each call site rather than built
  ! here from the field name. Deriving it would put a run-time string in the position
  ! of a table key: a renamed field would then miss its row and surface as L2-b's
  ! "dialect the table does not declare" INTERNAL fault instead of failing to compile.
  subroutine reject_pinned(errors, loc, condition, actual)
    type(problem_errors_t), intent(inout) :: errors
    type(source_location_t), intent(in) :: loc
    character(len=*), intent(in) :: condition
    integer(int32), intent(in) :: actual
    call reject_dialect(errors, 'A-GLB', condition, loc, actual=itoa(actual), expected='0')
  end subroutine reject_pinned

  pure function itoa(v) result(s)
    integer(int32), intent(in) :: v
    character(len=:), allocatable :: s
    character(len=32) :: buf
    write (buf, '(I0)') v
    s = trim(buf)
  end function itoa

  pure function rtoa(v) result(s)
    real(real64), intent(in) :: v
    character(len=:), allocatable :: s
    character(len=32) :: buf
    write (buf, '(ES14.6)') v
    s = trim(adjustl(buf))
  end function rtoa

end module yl_adapter_model
