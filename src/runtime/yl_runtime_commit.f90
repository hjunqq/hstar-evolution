! yl_runtime_commit -- commit_legacy_globals: the ONE writer of the legacy globals.
!
! Scope (.ccg/tasks/m3-03-build-runtime-commit/plan.md delivery 5)
!   During the migration this is the only place in the repository that assigns to a
!   variable of `global_var`, `prescribed`, `applied_load` or `meshfine`. Everything else
!   -- the pipeline, build_runtime, the observers -- either reads legacy state or does not
!   touch it at all. Concentrating the writes in one module is what makes the ownership
!   question answerable: there is exactly one allocator and exactly one releaser.
!
!   It is NOT wired into the solver. Nothing in the solver link chain calls it, and
!   nothing here is compiled into build/<profile>/hstar. It is exercised by the isolated
!   bridge executable, which links the real legacy modules and no main program.
!
! THE COMMIT CONTRACT
!   Two phases, in this order, and the boundary between them is the whole design:
!
!     VERIFY + STAGE   Every registered row is checked against the value-state ledger
!                      and against its own allocation status, then every legacy target
!                      is built COMPLETE in a local temporary -- allocation, kind
!                      conversion, extent, the lot. Any failure returns here, and no
!                      global has been touched. Every staging buffer is POISONED at
!                      allocation and the real assignment overwrites it, so a value no
!                      assignment ever reached is published as a sentinel rather than as
!                      undefined memory that reads back as a plausible 0 -- see the
!                      STAGE_POISON note below, which records the three profiles that
!                      could not see a deleted write before this existed.
!     WRITE            The previous commit's storage is released and the staged values
!                      are moved in. Nothing in this phase allocates, converts, or can
!                      fail: it is `move_alloc` and scalar assignment, top to bottom.
!
!   So there is no state in which some globals carry this runtime and others carry the
!   last one. That is the property the task is named for, and it is structural rather
!   than reviewed: the staging locals are the only things that can fail, and they are
!   local.
!
! OWNERSHIP, AND WHY A REPEAT COMMIT DOES NOT LEAK
!   The legacy element, group, prescription and curve records reach their payloads
!   through POINTER components (Elements.f90:89, :112, Global.f90:250, Prescrib.f90:25).
!   `move_alloc` onto such an array deallocates the destination ARRAY and leaks every
!   target its pointer components still refer to -- which is exactly how "load two leaks
!   load one". So the write phase releases first, explicitly, target by target, and only
!   then moves.
!
!   It releases ONLY what a previous commit_legacy_globals allocated. `commit_owned`
!   records that, and it is the only thing that gets deallocated: storage a legacy reader
!   allocated is never freed here, because this module did not allocate it and does not
!   know what else still points into it. `commit_release` is idempotent -- calling it on
!   a fresh process, or twice in a row, is a no-op and not a double free.
!
!   That "never freed here" is not the same as "left alone", and it matters which: for
!   these pointer-bearing record types, `move_alloc` onto an already-allocated destination
!   deallocates the destination ARRAY but does not free the pointer targets still hanging
!   off it -- so moving onto a foreign allocation instead of releasing it first would
!   silently LEAK it, not preserve it. `commit_legacy_globals` therefore refuses to run at
!   all -- reports INV-COMMIT-TOTAL and touches no global -- when it finds ANY of the seven
!   record-array globals it moves (element, group, listp_group, prescrib, tcurves, trans)
!   already allocated while `commit_owned` is still false. That is the only condition
!   under which this module declines to commit a verified runtime.
!
!   The list is spelled out here and in the guard rather than described as "the record
!   arrays", because the first version of that guard described the class and enumerated
!   five of the six: `trans` was moved unguarded, and the leak the paragraph promises to
!   prevent was reachable through it. A list that must be maintained is honest about
!   needing maintenance; a description that quietly covers less than it says is not.
!
! WHAT IS WRITTEN
!   The 46 `model_ready` `RuntimeState.*` rows of docs/m2/state-field-map.toml, plus the
!   scalars that are those rows' own extents (npoin, nelem, ngroup, ndimn, mdofn, cdofn,
!   ntotv, ndofix, ntcurve). Nothing else. The extents are written because a committed
!   array whose declared extent disagrees with it is not a committed array; they are all
!   derived from the runtime itself and none is read from anywhere else.
!
!   Deliberately NOT written: everything that belongs to the ProblemState half of the
!   bridge -- coordinates, connectivity, materials, sections, solver controls, step
!   controls. That is M4-01. Because element(:) is rebuilt here rather than patched, the
!   M4-01 change is to FOLD the two halves into one staging pass, not to add a second
!   commit that writes the other components of the same records. A second writer would
!   reintroduce exactly the partial-commit state this module exists to make impossible,
!   and this note is here so that is a decision and not an accident.
!
! WHAT COMMITTING PROVES, AND WHAT IT DOES NOT
!   That the values reach the globals with the right extents and the right kinds. It
!   does not prove the solver is satisfied by them: no solver consumer runs here. It does
!   not prove the absence of a use-after-free or of a leak either -- a process cannot
!   observe its own leaks -- which is why the release path is written to be checkable by
!   an external tool and why that check is recorded as NOT PERFORMED rather than assumed.
module yl_runtime_commit

  use iso_fortran_env, only: int32, real64

  use variable_types, only: ink, irk
  use elements, only: element_field, gauss_element
  use global_var, only: element, group, listp_group, trans, appear,                             &
                        coord, appear_process, matno_process, average_appear,                   &
                        lmdofn, lcdofn, nodfn, iffix, fixed, order_time_mdofn, tension_joint,   &
                        modf_dis_blocks, tlink, equvs_process, force_process,                   &
                        pnorm, prot, icpnorm, lelenrt, icpspring,                              &
                        listglocbeam, links, trans_c, tension_contact,                          &
                        result_zero, tofor, stfor, toforl, toform, delitfi, deltafi,            &
                        line_load_block, line_temp_block, lineload, linet,                      &
                        npoin, nelem, ngroup, ndimn, mdofn, cdofn, ntotv, iblks, lblks,         &
                        element_lib, group_of_elements, group_of_dvide_ipoin,                   &
                        interpolation_group, unode_elements,                                    &
                        probn, outplot, type_problem, type_solver, type_load, type_ABC,         &
                        type_nl, nonsym, NGRAV, nmats, nblks, uinitial,                         &
                        gid_u, gid_s, gid_ms, gid_f, gid_rot, gid_v, gid_a, gid_T, gid_P,       &
                        gid_Pv, gid_ep, gid_Y, gid_FC, gid_Ns, gid_Ss, gid_Mxy, gid_bem,        &
                        gid_wh, gid_wv, gid_bcs,                                                &
                        restart, relis, ADINA, runblks, npoinb, nlayer, block_stab, nbackf,     &
                        ebody, ninit, state_change, Bparameter, stab_matde, nlinks, nsmat,      &
                        ntrans
  use prescribed, only: prescrib, ndofix, freedom_prescribe, nfixsets
  use applied_load, only: tcurves, ntcurve, time_curve, factg, tcurvegravity, gravy,          &
                          nplgroup, nedge, edge_load_group, delgroup, nbeamload, nplateload
  use meshfine, only: ice0
  use temperature, only: ntemp_surface, ntedge, ntelgroup, npipe
  use materials, only: props, material_property, mechanical_property, solid_skeleton

  use yl_problem_types, only: problem_state_t
  use yl_problem_deck_residue, only: deck_residue_t
  use yl_problem_existence, only: deck_existence_t
  include 'yl_runtime_scalars_use.inc'
  use yl_problem_optional, only: opt_int, opt_real, opt_text, opt_logical, opt_get, opt_is_set
  use yl_problem_errors, only: problem_errors_t, problem_error_t, make_problem_error,           &
                               PE_INTERNAL, PE_EXIT_INTERNAL
  use yl_runtime_types, only: runtime_state_t, runtime_status_get, runtime_status_count,        &
                              RUNTIME_VALUE_DEFINED, RUNTIME_VALUE_RESERVED,                    &
                              RUNTIME_VALUE_ABSENT
  use yl_runtime_rules, only: build_rule_produced_count, build_rule_produced_map_id,            &
                              build_rule_t, build_rule_row, build_rule_count, build_rule_key,   &
                              PE_STAGE_BUILD

  implicit none
  private

  public :: commit_legacy_globals, commit_release, commit_owns_globals
  public :: commit_provenance_count, commit_provenance_row, commit_provenance_of
  public :: commit_provenance_export

  ! .true. exactly while the legacy globals hold storage THIS module allocated. The
  ! release path frees nothing unless this is set, so a process whose globals were filled
  ! by the legacy readers cannot have them freed from under it.
  logical, save :: commit_owned = .false.

  ! --- STAGING POISON ---------------------------------------------------------
  ! Every staging buffer is filled with one of these the moment it is allocated, and the
  ! real assignment overwrites it. A staged value that no assignment ever reached is then
  ! published as the sentinel instead of as whatever the heap happened to contain.
  !
  ! WHY THIS EXISTS, measured rather than argued (docs/m4/L2c-fold-design.md §5.5):
  !   Deleting one real assignment from this module -- `s_group(ig)%unode(i)%np_unode =
  !   0_ink` was the case that found it -- left yl_runtime_bridge_test at 720/720 under
  !   `release`, under `strict` (-init=snan,arrays reaches reals only) and under
  !   `sanitize` (-check uninit / MemorySanitizer). Nothing in this repository could see
  !   a write that was simply not there. The reason is not carelessness in the tests: the
  !   legacy record types have no default initialisation, commit REALLOCATES their storage
  !   on every commit, and undefined memory reads back as 0 often enough to impersonate a
  !   correct value. "Wrote the wrong value" was caught; "never wrote it" was not, and the
  !   M4-01 fold's dominant failure mode is the second one -- it adds 89 rows that would
  !   otherwise be published straight out of undefined memory.
  !
  ! THREE RULES, and the second is the one that will be tempting to break:
  !   1 The sentinel must never reach legacy as a value. It lives only in the staging
  !     locals, and every component that this module ASSIGNS must be poisoned before the
  !     assignment and covered by it afterwards. Poisoning a component this module does
  !     NOT assign would publish a sentinel for no benefit -- which is why the poison
  !     routines below cover exactly the assigned set and say so component by component.
  !   2 RESERVED rows are the one exception: they are allocated and deliberately left
  !     unwritten, so they DO reach the globals carrying the sentinel. That is more honest
  !     than reaching them carrying 0, because 0 is a value and the ledger says these have
  !     none. Every such row is RUNTIME_VALUE_RESERVED in the ledger and `ignore` +
  !     `emit = "none"` in docs/m2/state-field-map.toml, so no snapshot and no comparison
  !     ever reads one. Which rows carry a sentinel out of here is the LEDGER'S decision;
  !     it must never become the residue of a forgotten assignment.
  !   3 The poison routines are maintained beside the null_ routines under the same
  !     discipline: null_ covers the POINTER components (an ownership question), poison_
  !     covers the assigned NON-pointer components (a "did anyone write this" question).
  !     Each states its own coverage, so a legacy type gaining a component shows up as a
  !     gap in both rather than in neither.
  !
  ! WHY huge() AND NOT A NaN: a signalling NaN would be the better real sentinel, but the
  ! `strict` and `sanitize` profiles compile with -fpe0, where merely copying one can trap
  ! far from the defect and turn a clear red line into a confusing crash. -init=snan
  ! already gives those two profiles the NaN behaviour for reals; huge() adds a sentinel
  ! that behaves identically in all four profiles. Neither value is producible by any
  ! legal path here: every integer this module stages is an index, a count or a 0/1/5
  ! flag, and every real is a coordinate, a force or a Jacobian.
  integer(ink), parameter :: STAGE_POISON_I = huge(0_ink)
  real(irk), parameter :: STAGE_POISON_R = huge(0.0_irk)

  ! ==========================================================================
  ! THE PROVENANCE LEDGER -- where every snapshot row's value came from
  ! ==========================================================================
  !
  ! One entry per `model_ready` row of docs/m2/state-field-map.toml with
  ! `emit /= "none"`: the 162 rows a shadow snapshot actually carries. The entry does
  ! not say WHETHER this module wrote the row -- writing is not a free variable, because
  ! yl_state_dump aborts on an unallocated target and emits undefined memory for an
  ! unassigned scalar, so every one of the 162 is written or the snapshot does not exist
  ! (docs/m4/L2c-fold-design.md §2). It says WHERE THE VALUE CAME FROM, which is the only
  ! question a reader of the snapshot cannot answer for themselves.
  !
  ! WHY THAT IS THE USEFUL QUESTION
  !   L3-c found five rows that reached a differential as MISMATCH while carrying nothing
  !   but Fortran's default initialisation (docs/m4/L3c-shadow-report.md §5.3). The defect
  !   was not the values; it was that a snapshot row and a provenance-free byte were
  !   indistinguishable downstream. A row whose entry says COMMIT_NOT_MIGRATED is evidence
  !   of nothing and must not be compared; a row that says COMMIT_FROM_RUNTIME is a claim
  !   this module is making and is answerable for.
  !
  ! THE BACKWARD HALF IS NOT CHECKED HERE, AND CANNOT BE
  !   Fortran cannot enumerate the map, so "does every emitted model_ready row have an
  !   entry?" is not answerable in this file -- exactly the split yl_runtime_rules already
  !   lives with for the rule table. commit_provenance_export prints the table as PROV|
  !   lines and `tools/yl_state_map.py commit-provenance` answers the other direction
  !   against the map itself. A row added to the map with no entry here therefore fails
  !   the BUILD, not a later reviewer's memory.
  !
  !   That is deliberately NOT the generated row list docs/m4/L2c-fold-design.md §4.3
  !   first proposed. A generated list would need its own `! Source : ... sha256` line and
  !   its own gate to keep that line honest -- and that exact provenance line has already
  !   drifted once in this repository (cded7f4, found by the L2-c review). Exporting the
  !   one hand-held table and checking it against the map removes the second copy instead
  !   of adding a second thing to keep in step. The deviation is reported, not silent.
  !
  ! WHAT THIS LEDGER STRUCTURALLY CANNOT COVER
  !   The 14 model_ready RuntimeState rows with `emit = "none"`. They are written by this
  !   module and no snapshot ever carries them, so a table built over emitted rows cannot
  !   name them. Their only guard is yl_runtime_bridge_test's assertions on the committed
  !   globals; four of them had none until a5a6e15. See L2c-fold-design.md §4.5.
  integer, parameter, public :: COMMIT_LEN_MAP_ID = 40
  ! Widened from 32 for the appear_process exception: a detail that has to be abbreviated
  ! to fit stops being a detail. It is the reader's only in-band warning that part of a
  ! row's value did not come from where its state says.
  integer, parameter, public :: COMMIT_LEN_NOTE = 72

  ! WHAT `state` IS A STATEMENT ABOUT -- the definition, settled 2026-09-09, and every
  ! criterion in tools/yl_state_map.py is generated from it:
  !
  !     `state` says WHERE THIS COMMIT READ THE VALUE FROM. It does NOT say who owns the
  !     row.
  !
  ! The two readings are both self-consistent and they classify rows differently, so one
  ! had to be chosen. Ownership is the wrong one for two reasons. It is already in the
  ! map's `owner` column, and restating it here would be the second source invariant 4
  ! forbids -- the ledger would carry no information a reader could not look up. And it
  ! does not survive contact with four of the six states: FROM_DECK rows are owned by
  ! `derived` or `not_migrated` and DERIVED rows by `derived`, so under an ownership
  ! reading those two states would be asserting nothing at all.
  !
  ! The read-site reading is what a snapshot reader actually needs and cannot get
  ! elsewhere: whether the byte in front of them is a value this module put there on
  ! purpose, and out of which object.
  !
  ! The consequence to keep in view: OWNER AND STATE ARE INDEPENDENT. A row owned by
  ! ProblemState can legitimately be FROM_RUNTIME -- `mesh.dimension` is exactly that,
  ! because commit stages `ndimn` as an extent of a runtime collection and the extent rule
  ! (L2c-fold-design.md §5.2) forbids re-deriving it from the ProblemState side. Anyone
  ! tempted to "fix" that row to FROM_PROBLEM is applying the ownership reading; the
  ! cross-check will stop them, and this paragraph is why.

  !> Read out of `runtime_state_t` -- either a component build_runtime produced, or an
  !> extent of one of its collections.
  integer(int32), parameter, public :: COMMIT_FROM_RUNTIME = 1_int32
  !> Read out of the finished `problem_state_t`. Unused until M4-01 step 3.
  integer(int32), parameter, public :: COMMIT_FROM_PROBLEM = 2_int32
  !> Not read from anywhere: computed here from a ProblemState collection's cardinality.
  !> Unused until step 5.
  integer(int32), parameter, public :: COMMIT_DERIVED = 3_int32
  !> Read out of `deck_residue_t`, with the adapter's rejection rule recorded in `note` as
  !> an independent cross-check. Unused until step 5.
  integer(int32), parameter, public :: COMMIT_FROM_DECK = 4_int32
  !> Read from nothing and written to nothing: the dump synthesises the value itself.
  integer(int32), parameter, public :: COMMIT_SYNTHETIC = 5_int32
  !> NO SOURCE. The row reaches the globals carrying whatever staging left there, and no
  !> comparison may treat it as evidence. Every occurrence is a debt, and the M4-01 exit
  !> condition is that this state does not appear in the table at all.
  integer(int32), parameter, public :: COMMIT_NOT_MIGRATED = 6_int32

  type, public :: commit_provenance_t
    !> The M2 map row this entry is about.
    character(len=COMMIT_LEN_MAP_ID) :: map_id = ''
    !> WHERE COMMIT READ THE VALUE FROM -- see the definition above. Not an ownership
    !> claim; the map's `owner` column is the ownership claim and this never restates it.
    integer(int32) :: state = COMMIT_NOT_MIGRATED
    !> Which object or expression, for a state whose source is not implied by the row
    !> itself: the extent for a FROM_RUNTIME row that is not RuntimeState-owned, the
    !> adapter's rejection rule id for FROM_DECK.
    character(len=COMMIT_LEN_NOTE) :: note = ''
  end type commit_provenance_t

  ! 162 entries, in state-field-map.toml order.
  !
  ! THE PER-STATE TALLY IS DELIBERATELY NOT WRITTEN HERE. It was, and it rotted: the
  ! comment went on saying "118 NOT_MIGRATED" while the number fell to 97, then 92, then 77,
  ! because nothing checks a count that only a human reads (docs/04-quality-gates.md, the
  ! recurring defect shape, item 7). `commit_provenance_export` prints the live tally and
  ! `tools/yl_state_map.py commit-provenance` puts it in every build log, including the
  ! NOT_MIGRATED line -- the count that is the honest headline of M4-01's progress, and
  ! whose fall to zero is the exit condition. Read it there, where it cannot be stale.
  type(commit_provenance_t), parameter :: COMMIT_PROVENANCE(*) = [                              &
    commit_provenance_t('case.name', COMMIT_FROM_PROBLEM, 'case.name'),                                                                  &
    commit_provenance_t('control.run.restart', COMMIT_FROM_DECK, 'F1/restart'),                                                        &
    commit_provenance_t('control.run.relis', COMMIT_FROM_DECK, 'F1/relis'),                                                          &
    commit_provenance_t('control.run.adina', COMMIT_FROM_DECK, 'F1/adina'),                                                          &
    commit_provenance_t('derived.counts.runblks', COMMIT_FROM_DECK, 'F1/runblks'),                                                     &
    commit_provenance_t('derived.counts.npoin', COMMIT_FROM_RUNTIME, 'extent npoin'),                                           &
    commit_provenance_t('derived.counts.npoinb', COMMIT_FROM_DECK, 'no gate: read+discarded'),                                                      &
    commit_provenance_t('derived.counts.nelem', COMMIT_FROM_RUNTIME, 'extent nelem'),                                           &
    commit_provenance_t('mesh.dimension', COMMIT_FROM_RUNTIME, 'extent ndimn'),                                                 &
    commit_provenance_t('derived.counts.nmats', COMMIT_DERIVED, 'count(materials)'),                                                       &
    commit_provenance_t('derived.counts.ngroup', COMMIT_FROM_RUNTIME, 'extent ngroup'),                                         &
    commit_provenance_t('steps0.output.format', COMMIT_FROM_PROBLEM, 'steps[0].output.format'),                                                       &
    commit_provenance_t('mesh.nodes.id', COMMIT_SYNTHETIC, 'dump emits 1..npoin'),                                              &
    commit_provenance_t('mesh.nodes.xyz', COMMIT_FROM_PROBLEM, 'mesh.nodes[].xyz'),                                                             &
    commit_provenance_t('mesh.elements.id', COMMIT_SYNTHETIC, 'dump emits 1..nelem'),                                           &
    commit_provenance_t('mesh.elements.nodes', COMMIT_FROM_PROBLEM, 'mesh.elements[].nodes'),                                                        &
    commit_provenance_t('mesh.elements.kind', COMMIT_FROM_PROBLEM, 'mesh.elements[].kind'),                                                         &
    commit_provenance_t('mesh.elements.group', COMMIT_FROM_PROBLEM, 'mesh.elements[].elset'),                                                        &
    commit_provenance_t('mesh.elements.material', COMMIT_FROM_PROBLEM, 'mesh.elements[].material'),                                                     &
    commit_provenance_t('mesh.sets.elset', COMMIT_FROM_PROBLEM, 'mesh.elsets[].elements'),                                                            &
    commit_provenance_t('mesh.sets.nset', COMMIT_FROM_PROBLEM, 'steps[0].boundary[].nset (dump regroups)'),                                                             &
    commit_provenance_t('materials.id', COMMIT_FROM_PROBLEM, 'props(:) index 1..nmats'),                                                               &
    commit_provenance_t('materials.kind', COMMIT_FROM_PROBLEM, 'associated(mechanical)'),                                                             &
    commit_provenance_t('materials.name', COMMIT_FROM_PROBLEM, 'materials[]'),                                                             &
    commit_provenance_t('derived.counts.nphase', COMMIT_DERIVED, 'count of associated(solid)'),                                                      &
    commit_provenance_t('materials.phase', COMMIT_FROM_PROBLEM, 'associated(solid)'),                                                            &
    commit_provenance_t('materials.model', COMMIT_FROM_PROBLEM, 'materials[]'),                                                            &
    commit_provenance_t('materials.density', COMMIT_FROM_PROBLEM, 'materials[]'),                                                          &
    commit_provenance_t('materials.ratio', COMMIT_FROM_PROBLEM, 'materials[]'),                                                            &
    commit_provenance_t('sections.thickness', COMMIT_FROM_PROBLEM, 'sections[] -> materials[]'),                                                         &
    commit_provenance_t('materials.E', COMMIT_FROM_PROBLEM, 'materials[]'),                                                                &
    commit_provenance_t('materials.nu', COMMIT_FROM_PROBLEM, 'materials[]'),                                                               &
    commit_provenance_t('materials.thermal_expansion', COMMIT_FROM_PROBLEM, 'materials[]'),                                                &
    commit_provenance_t('materials.icreep', COMMIT_FROM_PROBLEM, 'materials[]'),                                                           &
    commit_provenance_t('materials.kind_wt', COMMIT_FROM_PROBLEM, 'materials[]'),                                                          &
    commit_provenance_t('materials.jliqu', COMMIT_FROM_PROBLEM, 'materials[]'),                                                            &
    commit_provenance_t('sections.element', COMMIT_FROM_PROBLEM, 'sections[].element'),                                                           &
    commit_provenance_t('sections.name', COMMIT_FROM_PROBLEM, 'sections[].name'),                                                              &
    commit_provenance_t('sections.element_kind', COMMIT_FROM_PROBLEM, 'sections[].element_kind'),                                                      &
    commit_provenance_t('sections.class', COMMIT_FROM_PROBLEM, 'sections[].class'),                                                             &
    commit_provenance_t('derived.counts.nrfields', COMMIT_FROM_RUNTIME, 'size(element_field_variables(ie)%fields)'),                                                    &
    commit_provenance_t('sections.fields', COMMIT_FROM_PROBLEM, 'sections[].fields'),                                                            &
    commit_provenance_t('sections.special', COMMIT_FROM_PROBLEM, 'sections[].special'),                                                           &
    commit_provenance_t('sections.formulation', COMMIT_FROM_PROBLEM, 'sections[].formulation'),                                                       &
    commit_provenance_t('sections.elset_size', COMMIT_DERIVED, 'size(mesh.elsets[].elements)'),                                                        &
    commit_provenance_t('sections.material_header', COMMIT_FROM_PROBLEM, 'element%matno reconstruct'),                                                   &
    commit_provenance_t('sections.material', COMMIT_FROM_PROBLEM, 'sections[].material (effective)'),                                                          &
    commit_provenance_t('sections.type_nalgo', COMMIT_FROM_PROBLEM, 'sections[].algorithm'),                                                        &
    commit_provenance_t('sections.type_stiff', COMMIT_FROM_PROBLEM, 'sections[].stiffness_kind'),                                                        &
    commit_provenance_t('sections.type_ecoint', COMMIT_FROM_PROBLEM, 'sections[].stress_recovery'),                                                       &
    commit_provenance_t('sections.ilayer', COMMIT_FROM_PROBLEM, 'sections[].layer'),                                                            &
    commit_provenance_t('sections.elcod_local', COMMIT_FROM_PROBLEM, 'sections[].local_axes'),                                                       &
    commit_provenance_t('sections.uplift_ic', COMMIT_FROM_PROBLEM, 'sections[].uplift'),                                                         &
    commit_provenance_t('sections.liquj', COMMIT_FROM_PROBLEM, 'sections[].liquefaction'),                                                             &
    commit_provenance_t('sections.dof_count', COMMIT_DERIVED, 'nevab / nnode, both runtime extents'),                                                         &
    commit_provenance_t('sections.dof_list', COMMIT_FROM_RUNTIME, 'active_to_component(1:nfdof)'),                                                          &
    commit_provenance_t('derived.counts.nstre', COMMIT_DERIVED, 'legacy rule on ndimn and class'),                                                       &
    commit_provenance_t('derived.counts.ntcurve', COMMIT_FROM_RUNTIME, 'extent ntcurve'),                                       &
    commit_provenance_t('amplitudes.points.count', COMMIT_DERIVED, 'size(amplitudes[].points)'),                                                    &
    commit_provenance_t('amplitudes.type', COMMIT_FROM_PROBLEM, 'amplitudes[].type'),                                                            &
    commit_provenance_t('amplitudes.points.time', COMMIT_FROM_PROBLEM, 'amplitudes[].points[].time'),                                                     &
    commit_provenance_t('amplitudes.points.value', COMMIT_FROM_PROBLEM, 'amplitudes[].points[].value'),                                                    &
    commit_provenance_t('runtime.amplitudes.dfact', COMMIT_FROM_RUNTIME, ''),                                                   &
    commit_provenance_t('steps0.procedure', COMMIT_FROM_PROBLEM, 'steps[0].procedure'),                                                           &
    commit_provenance_t('solver.linear', COMMIT_FROM_PROBLEM, 'solver.linear'),                                                              &
    commit_provenance_t('steps0.load_mode', COMMIT_FROM_PROBLEM, 'steps[0].load_mode'),                                                           &
    commit_provenance_t('steps0.controls.nonlinear_type', COMMIT_FROM_PROBLEM, 'steps[0].controls.nonlinear_type'),                                             &
    commit_provenance_t('control.glb.nlayer', COMMIT_FROM_DECK, 'A-GLB/nlayer-nonzero'),                                                         &
    commit_provenance_t('control.glb.block_stab', COMMIT_FROM_DECK, 'A-GLB/pinned'),                                                     &
    commit_provenance_t('control.glb.nbackf', COMMIT_FROM_DECK, 'A-GLB/pinned'),                                                         &
    commit_provenance_t('control.glb.ebody', COMMIT_FROM_DECK, 'A-GLB/pinned'),                                                          &
    commit_provenance_t('control.glb.ninit', COMMIT_FROM_DECK, 'A-GLB/ninit-nonzero'),                                                          &
    commit_provenance_t('control.glb.uinitial', COMMIT_FROM_DECK, 'A-GLB/pinned all-zero'),                                                       &
    commit_provenance_t('control.glb.state_change', COMMIT_FROM_DECK, 'A-GLB/pinned'),                                                   &
    commit_provenance_t('control.glb.bparameter', COMMIT_FROM_DECK, 'A-GLB/pinned'),                                                     &
    commit_provenance_t('control.glb.stab_matde', COMMIT_FROM_DECK, 'A-GLB/interval > nblks'),                                                     &
    commit_provenance_t('derived.counts.nblks', COMMIT_DERIVED, 'count(steps)'),                                                       &
    commit_provenance_t('control.glb.nlinks', COMMIT_FROM_DECK, 'A-GLB/pinned'),                                                         &
    commit_provenance_t('solver.symmetric', COMMIT_FROM_PROBLEM, 'solver.symmetric'),                                                           &
    commit_provenance_t('interactions.absorbing.type', COMMIT_FROM_PROBLEM, 'interactions.absorbing.type'),                                                &
    commit_provenance_t('derived.counts.nsmat', COMMIT_FROM_DECK, 'no gate: read+discarded'),                                                       &
    commit_provenance_t('steps0.load.gravity.enabled', COMMIT_FROM_PROBLEM, 'steps[0].load.gravity.enabled'),                                                &
    commit_provenance_t('derived.counts.mdofn', COMMIT_FROM_RUNTIME, 'extent mdofn'),                                           &
    commit_provenance_t('derived.dof.active_flags', COMMIT_FROM_RUNTIME, 'reconstructed from lmdofn'),                          &
    commit_provenance_t('runtime.dof.lmdofn', COMMIT_FROM_RUNTIME, ''),                                                         &
    commit_provenance_t('derived.dof.cdofn', COMMIT_FROM_RUNTIME, 'extent cdofn'),                                              &
    commit_provenance_t('derived.dof.lcdofn', COMMIT_FROM_RUNTIME, 'lcdofn(1:cdofn)'),                                          &
    commit_provenance_t('runtime.increment.iblks_at_model', COMMIT_FROM_RUNTIME, ''),                                           &
    commit_provenance_t('runtime.increment.lblks_at_model', COMMIT_FROM_RUNTIME, ''),                                           &
    commit_provenance_t('steps0.activation.active', COMMIT_FROM_PROBLEM, 'steps[0].activation[]; col 0 = 0, legacy init Global.f90:968'),                                                   &
    commit_provenance_t('steps0.activation.material', COMMIT_FROM_PROBLEM, 'steps[0].activation[]'),                                                 &
    commit_provenance_t('runtime.activation.appear', COMMIT_FROM_RUNTIME, ''),                                                  &
    commit_provenance_t('steps0.output.stress_averaging', COMMIT_FROM_PROBLEM, 'steps[0].output'),                                             &
    commit_provenance_t('steps0.output.field.gid_u', COMMIT_FROM_PROBLEM, 'steps[0].output.field.u'),                                                  &
    commit_provenance_t('steps0.output.field.gid_s', COMMIT_FROM_PROBLEM, 'steps[0].output.field.s'),                                                  &
    commit_provenance_t('steps0.output.field.gid_ms', COMMIT_FROM_PROBLEM, 'steps[0].output.field.ms'),                                                 &
    commit_provenance_t('steps0.output.field.gid_f', COMMIT_FROM_PROBLEM, 'steps[0].output.field.f'),                                                  &
    commit_provenance_t('steps0.output.field.gid_rot', COMMIT_FROM_PROBLEM, 'steps[0].output.field.rot'),                                                &
    commit_provenance_t('steps0.output.field.gid_v', COMMIT_FROM_PROBLEM, 'steps[0].output.field.v'),                                                  &
    commit_provenance_t('steps0.output.field.gid_a', COMMIT_FROM_PROBLEM, 'steps[0].output.field.a'),                                                  &
    commit_provenance_t('steps0.output.field.gid_T', COMMIT_FROM_PROBLEM, 'steps[0].output.field.T'),                                                  &
    commit_provenance_t('steps0.output.field.gid_P', COMMIT_FROM_PROBLEM, 'steps[0].output.field.P'),                                                  &
    commit_provenance_t('steps0.output.field.gid_Pv', COMMIT_FROM_PROBLEM, 'steps[0].output.field.Pv'),                                                 &
    commit_provenance_t('steps0.output.field.gid_ep', COMMIT_FROM_PROBLEM, 'steps[0].output.field.ep'),                                                 &
    commit_provenance_t('steps0.output.field.gid_Y', COMMIT_FROM_PROBLEM, 'steps[0].output.field.Y'),                                                  &
    commit_provenance_t('steps0.output.field.gid_FC', COMMIT_FROM_PROBLEM, 'steps[0].output.field.FC'),                                                 &
    commit_provenance_t('steps0.output.field.gid_Ns', COMMIT_FROM_PROBLEM, 'steps[0].output.field.Ns'),                                                 &
    commit_provenance_t('steps0.output.field.gid_Ss', COMMIT_FROM_PROBLEM, 'steps[0].output.field.Ss'),                                                 &
    commit_provenance_t('steps0.output.field.gid_Mxy', COMMIT_FROM_PROBLEM, 'steps[0].output.field.Mxy'),                                                &
    commit_provenance_t('steps0.output.field.gid_bem', COMMIT_FROM_PROBLEM, 'steps[0].output.field.bem'),                                                &
    commit_provenance_t('steps0.output.field.gid_wh', COMMIT_FROM_PROBLEM, 'steps[0].output.field.wh'),                                                 &
    commit_provenance_t('steps0.output.field.gid_wv', COMMIT_FROM_PROBLEM, 'steps[0].output.field.wv'),                                                 &
    commit_provenance_t('steps0.output.field.gid_bcs', COMMIT_FROM_PROBLEM, 'steps[0].output.field.bcs'),                                                &
    commit_provenance_t('derived.counts.nfixsets', COMMIT_DERIVED, 'count(mesh.nsets)'),                                                    &
    commit_provenance_t('derived.counts.ndofix', COMMIT_FROM_RUNTIME, 'extent ndofix'),                                         &
    commit_provenance_t('steps0.boundary.set', COMMIT_FROM_PROBLEM, 'steps[0].boundary[].name'),                                                        &
    commit_provenance_t('steps0.boundary.dof', COMMIT_FROM_PROBLEM, 'steps[0].boundary[].dof'),                                                        &
    commit_provenance_t('steps0.boundary.amplitude', COMMIT_FROM_PROBLEM, 'steps[0].boundary[].amplitude'),                                                  &
    commit_provenance_t('steps0.boundary.nodes', COMMIT_FROM_PROBLEM, 'steps[0].boundary[].nset'),                                                      &
    commit_provenance_t('steps0.boundary.value', COMMIT_FROM_PROBLEM, 'steps[0].boundary[].value'),                                                      &
    commit_provenance_t('steps0.boundary.record_reaction', COMMIT_FROM_PROBLEM, 'steps[0].boundary[].record_reaction'),                                            &
    commit_provenance_t('runtime.boundary.ldofix', COMMIT_FROM_RUNTIME, ''),                                                    &
    commit_provenance_t('runtime.boundary.lnefix', COMMIT_FROM_RUNTIME, ''),                                                    &
    commit_provenance_t('runtime.boundary.leldofix', COMMIT_FROM_RUNTIME, ''),                                                  &
    commit_provenance_t('runtime.boundary.levdofix', COMMIT_FROM_RUNTIME, ''),                                                  &
    commit_provenance_t('runtime.boundary.lefdofix', COMMIT_FROM_RUNTIME, ''),                                                  &
    commit_provenance_t('runtime.dof.iffix', COMMIT_FROM_RUNTIME, ''),                                                          &
    commit_provenance_t('runtime.dof.fixed', COMMIT_FROM_RUNTIME, ''),                                                          &
    commit_provenance_t('control.glb.ntrans', COMMIT_FROM_DECK, 'A-GLB/ntrans-nonzero'),                                                         &
    commit_provenance_t('steps0.load.gravity.magnitude', COMMIT_FROM_PROBLEM, 'steps[0].load.gravity.magnitude'),                                              &
    commit_provenance_t('steps0.load.gravity.direction', COMMIT_FROM_PROBLEM, 'steps[0].load.gravity'),                                              &
    commit_provenance_t('steps0.load.gravity.amplitude', COMMIT_FROM_PROBLEM, 'steps[0].load.gravity'),                                              &
    commit_provenance_t('derived.counts.nplgroup', COMMIT_FROM_DECK, 'A3/point-load'),                                                    &
    commit_provenance_t('derived.counts.nedge', COMMIT_FROM_DECK, 'A4/edge-definition'),                                                       &
    commit_provenance_t('derived.counts.edge_load_group', COMMIT_FROM_DECK, 'A5/pressure-load'),                                             &
    commit_provenance_t('derived.counts.delgroup', COMMIT_FROM_DECK, 'no gate: shares A5 read'),                                                    &
    commit_provenance_t('derived.counts.nbeamload', COMMIT_FROM_DECK, 'A6/beam-load'),                                                   &
    commit_provenance_t('derived.counts.nplateload', COMMIT_FROM_DECK, 'A7/plate-load'),                                                  &
    commit_provenance_t('derived.counts.ntemp_surface', COMMIT_FROM_DECK, 'A12/temp-surface'),                                               &
    commit_provenance_t('derived.counts.ntedge', COMMIT_FROM_DECK, 'A13/temp-edge'),                                                      &
    commit_provenance_t('derived.counts.ntelgroup', COMMIT_FROM_DECK, 'A14/temp-elgroup'),                                                   &
    commit_provenance_t('derived.counts.npipe', COMMIT_FROM_DECK, 'A15/pipe-cooling'),                                                       &
    commit_provenance_t('runtime.dof.nodfn', COMMIT_FROM_RUNTIME, ''),                                                          &
    commit_provenance_t('runtime.dof.ntotv', COMMIT_FROM_RUNTIME, ''),                                                          &
    commit_provenance_t('runtime.dof.ldofs', COMMIT_FROM_RUNTIME, ''),                                                          &
    commit_provenance_t('runtime.dof.ldofs_f', COMMIT_FROM_RUNTIME, ''),                                                        &
    commit_provenance_t('runtime.dof.trans_nintf', COMMIT_FROM_RUNTIME, ''),                                                    &
    commit_provenance_t('runtime.topology.listp_group_mgroup', COMMIT_FROM_RUNTIME, ''),                                        &
    commit_provenance_t('runtime.topology.listp_group_listg', COMMIT_FROM_RUNTIME, ''),                                         &
    commit_provenance_t('runtime.topology.listp_group_listp', COMMIT_FROM_RUNTIME, ''),                                         &
    commit_provenance_t('runtime.topology.unode_ipoin', COMMIT_FROM_RUNTIME, ''),                                               &
    commit_provenance_t('runtime.topology.unode_ne_unode', COMMIT_FROM_RUNTIME, ''),                                            &
    commit_provenance_t('runtime.topology.unode_list', COMMIT_FROM_RUNTIME, ''),                                                &
    commit_provenance_t('runtime.gauss.djacb', COMMIT_FROM_RUNTIME, ''),                                                        &
    commit_provenance_t('runtime.gauss.gpcod', COMMIT_FROM_RUNTIME, ''),                                                        &
    commit_provenance_t('runtime.gauss.cartd', COMMIT_FROM_RUNTIME, ''),                                                        &
    commit_provenance_t('runtime.vectors.result_zero', COMMIT_FROM_RUNTIME, ''),                                                &
    commit_provenance_t('runtime.vectors.tofor', COMMIT_FROM_RUNTIME, ''),                                                      &
    commit_provenance_t('runtime.vectors.stfor', COMMIT_FROM_RUNTIME, ''),                                                      &
    commit_provenance_t('runtime.vectors.toforl', COMMIT_FROM_RUNTIME, ''),                                                     &
    commit_provenance_t('runtime.vectors.toform', COMMIT_FROM_RUNTIME, ''),                                                     &
    commit_provenance_t('runtime.element.ice0', COMMIT_FROM_RUNTIME, '')                                                        &
    ]

contains

  !> Publish `runtime` into the legacy globals.
  !>
  !>   problem  the finished ProblemState. intent(in): the ProblemState half of the fold
  !>            reads its values from here. NOT READ YET -- M4-01 step 3 is the first that
  !>            does; see THE THREE INPUTS below.
  !>   residue  the deck values that reach a legacy global and no ProblemState field
  !>            (yl_problem_deck_residue). NOT READ YET -- step 5.
  !>   runtime  the built runtime. intent(in): committing does not consume it, and the
  !>            same runtime may be committed again -- see the T02 properties.
  !>   errors   findings are APPENDED. A finding here is always PE_INTERNAL: by the time
  !>            a runtime exists its deck has been validated, so anything wrong at this
  !>            point is a broken pipeline and not a bad model.
  !>
  !> THE THREE INPUTS, AND WHY THEY ARE THREE
  !>   Each carries the rows the other two cannot. `runtime` holds what build_runtime
  !>   produced; `problem` holds the ProblemState-owned rows, which no runtime component
  !>   carries; `residue` holds the rows the M2 map owns at `derived` / `not_migrated` and
  !>   that nothing can recompute, which neither of the other two may hold -- putting them
  !>   in problem_state_t would make the map's `owner` column lie (see that module's
  !>   header), and putting them in runtime_state_t is the move that kills option B in
  !>   docs/m4/L2c-fold-design.md §3.
  !>
  !>   All three are intent(in) and none is consumed. The commit reads them in ONE staging
  !>   pass and publishes in ONE write phase, so a third input adds no second writer and no
  !>   second transaction -- which is the property §3.2.5 of the design had to argue for
  !>   and this signature has to keep.
  !>
  !> WHY TWO OF THEM ARE UNREAD TODAY
  !>   The signature lands before the reads on purpose. Threading three arguments through
  !>   eleven call sites and folding 118 rows in the same commit would put a mechanical
  !>   change and a semantic one behind one review; this way the semantic steps land
  !>   against a signature that is already green. `tools/yl_state_map.py commit-provenance`
  !>   reports the debt as NOT_MIGRATED=118, and it is meant to fall to zero.
  !>
  !> On success every registered global carries this runtime. On failure not one global
  !> was touched.
  subroutine commit_legacy_globals(problem, residue, existence, runtime, errors)
    type(problem_state_t), intent(in) :: problem
    type(deck_residue_t), intent(in) :: residue
    !> The EXISTENCE FACE (ADR-0009, docs/m4/existence-face.toml): legacy arrays the solver
    !> requires to exist whose values no checkpoint observes. Written by its own pass below,
    !> with its own provenance bucket, so the comparison face's bijection keeps its exact
    !> meaning instead of being widened to mean two things.
    type(deck_existence_t), intent(in) :: existence
    type(runtime_state_t), intent(in) :: runtime
    type(problem_errors_t), intent(inout) :: errors

    ! staging: scalars
    integer(ink) :: s_npoin, s_nelem, s_ngroup, s_ndimn, s_mdofn, s_cdofn, s_ntotv
    integer(ink) :: s_ndofix, s_ntcurve, s_iblks, s_lblks, s_lineload, s_linet
    integer :: nevab, ngaus, ngaus_mass, nnode
    ! staging: the existence face (ADR-0009). One buffer per existence-face.toml row.
    integer(ink), allocatable :: s_ex_order_time_mdofn(:), s_ex_tension_joint(:)
    integer(ink), allocatable :: s_ex_modf_dis_blocks(:)
    integer(ink), allocatable :: s_ex_tlink(:,:), s_ex_equvs(:), s_ex_force_process(:)
    integer(ink), allocatable :: s_ex_listglocbeam(:), s_ex_tension_contact(:)
    integer(ink), allocatable :: s_ex_icpnorm(:), s_ex_lelenrt(:), s_ex_icpspring(:)
    real(irk), allocatable :: s_ex_pnorm(:,:), s_ex_prot(:,:,:)
    ! staging: the ProblemState half's plain arrays (M4-01 step 3)
    real(irk), allocatable :: s_coord(:,:), s_factg(:)
    integer(ink), allocatable :: s_appear_process(:,:), s_matno_process(:,:)
    integer(ink), allocatable :: s_average_appear(:), s_tcurvegravity(:)
    type(material_property), allocatable :: s_props(:)
    ! n_materials / n_steps, NOT nmats / nblks. Those two names are use-associated from
    ! global_var, and a local of the same name silently shadows the global: step 5b's
    ! `nmats = s_nmats` assigned the LOCAL and the legacy global kept its old value, with
    ! nothing to show for it. group_sentinels caught that -- it seeds nmats/nblks with
    ! out-of-range values precisely so an accidental write, or in this case an absent one,
    ! is visible. The locals are renamed so the write phase can only mean the global.
    integer :: n_materials, n_steps, id_, ib
    ! staging: the C2 scalars and the residue's 27 (M4-01 step 5b). Declared with the
    ! LEGACY kinds so a character that does not fit is truncated HERE, in staging, where
    ! the bridge test's trim() comparison can see it -- not in the write phase, where the
    ! whole point is that nothing can go wrong.
    character(len=200) :: s_probn
    character(len=20) :: s_outplot
    character(len=50) :: s_type_problem, s_type_solver, s_type_load, s_type_abc
    integer(ink) :: s_type_nl, s_nonsym, s_ngrav, s_nmats, s_nblks, s_nfixsets
    integer(ink) :: s_gid_u, s_gid_s, s_gid_ms, s_gid_f, s_gid_rot, s_gid_v, s_gid_a
    integer(ink) :: s_gid_t, s_gid_p, s_gid_pv, s_gid_ep, s_gid_y, s_gid_fc, s_gid_ns
    integer(ink) :: s_gid_ss, s_gid_mxy, s_gid_bem, s_gid_wh, s_gid_wv, s_gid_bcs
    real(irk) :: s_gravy
    integer(ink) :: s_restart, s_relis, s_adina, s_runblks, s_npoinb, s_nlayer
    integer(ink) :: s_block_stab, s_nbackf, s_ebody, s_ninit, s_state_change
    integer(ink) :: s_bparameter, s_stab_matde, s_nlinks, s_nsmat, s_ntrans
    integer(ink) :: s_nplgroup, s_nedge, s_edge_load_group, s_delgroup
    integer(ink) :: s_nbeamload, s_nplateload
    integer(ink) :: s_ntemp_surface, s_ntedge, s_ntelgroup, s_npipe
    integer(ink), allocatable :: s_uinitial(:)
    ! staging: plain arrays
    integer(ink), allocatable :: s_lmdofn(:), s_lcdofn(:), s_nodfn(:,:), s_iffix(:)
    integer(ink), allocatable :: s_appear(:), s_ice0(:)
    integer(ink), allocatable :: s_line_load_block(:), s_line_temp_block(:)
    real(irk), allocatable :: s_fixed(:), s_result_zero(:), s_tofor(:), s_stfor(:)
    real(irk), allocatable :: s_toforl(:), s_toform(:), s_delitfi(:), s_deltafi(:)
    ! staging: record arrays
    type(element_lib), allocatable :: s_element(:)
    type(group_of_elements), allocatable :: s_group(:)
    type(group_of_dvide_ipoin), allocatable :: s_listp(:)
    type(interpolation_group), allocatable :: s_trans(:)
    type(freedom_prescribe), allocatable :: s_prescrib(:)
    type(time_curve), allocatable :: s_tcurves(:)

    integer :: i, ie, ig, j, n, f, nrf, nfdof, nstre
    logical :: ok

    ! ---------------------------------------------------------------- verify
    call verify_registered(problem, residue, existence, runtime, errors, ok)
    if (.not. ok) return

    ! W4 guard (see the OWNERSHIP header): if any record-array global this module writes
    ! is already allocated while `commit_owned` is false, the storage was not put there by
    ! a previous commit_legacy_globals -- it can only be a legacy reader's own allocation.
    ! Staging and then `move_alloc`-ing over it would deallocate that array without
    ! freeing the pointer targets inside it, i.e. leak it silently. Refuse instead of
    ! leaking: this module will not run in a process whose legacy globals were populated
    ! by something else.
    if (.not. commit_owned) then
      ! ALL SEVEN record-array globals this module move_allocs, not six: `trans` is
      ! `interpolation_group`, which carries `listf` and `rintf` pointers
      ! (Global.f90:210-214) and is moved at the same unconditional move_alloc as the
      ! rest. Omitting it left the exact leak this guard exists to prevent reachable
      ! through one of the doors -- found in M3-03 Round-2 review. The seventh, `props`,
      ! arrived with M4-01 step 3 and is listed here on the same commit that added its
      ! move_alloc, which is the rule that paragraph asked for.
      !
      ! WHY THE STEP-3 PLAIN ARRAYS ARE **NOT** HERE, deliberately: coord,
      ! appear_process, matno_process, average_appear, factg and tcurvegravity hold no
      ! pointer components, so move_alloc over a foreign allocation of one of them
      ! deallocates it completely and leaks nothing. This guard is about LEAKS, not about
      ! ownership in general, and widening it to "every global this module moves" would
      ! make it refuse in cases where there is nothing to prevent -- a guard that fires
      ! for the wrong reason. `props` is here because props(i)%mechanical%solid is a
      ! two-level pointer chain and is exactly what would leak.
      if (allocated(element) .or. allocated(group) .or. allocated(listp_group) .or.            &
          allocated(prescrib) .or. allocated(tcurves) .or. allocated(trans) .or.               &
          allocated(props)) then
        call fail(errors, 'one of element, group, listp_group, prescrib, tcurves, trans '//    &
                  'or props is already allocated but commit_owned is false -- committing '//   &
                  'would silently leak a foreign allocation via move_alloc; refusing to run '//&
                  'in a process whose legacy globals were populated by something other than '//&
                  'this module')
        return
      end if
    end if

    ! Scalars first (see STAGE_POISON_I): every published scalar is poisoned before it is
    ! computed. Seven of them are also the extents of the allocations below, so deleting
    ! one of those assignments fails at the `allocate` rather than at a comparison -- a
    ! louder failure than the one this mechanism is for, but a failure either way.
    s_npoin = STAGE_POISON_I;   s_nelem = STAGE_POISON_I;   s_ngroup = STAGE_POISON_I
    s_ndimn = STAGE_POISON_I;   s_mdofn = STAGE_POISON_I;   s_cdofn = STAGE_POISON_I
    s_ntotv = STAGE_POISON_I;   s_ndofix = STAGE_POISON_I;  s_ntcurve = STAGE_POISON_I
    s_iblks = STAGE_POISON_I;   s_lblks = STAGE_POISON_I
    s_lineload = STAGE_POISON_I; s_linet = STAGE_POISON_I

    s_npoin = int(size(runtime%dof%node_variables, 2), ink)
    s_cdofn = int(size(runtime%dof%node_variables, 1), ink)
    s_nelem = int(size(runtime%element), ink)
    s_ngroup = int(size(runtime%activation%section_state), ink)
    s_mdofn = int(size(runtime%dof%component_to_active), ink)
    s_ndimn = int(size(runtime%element(1)%field_coordinates, 1), ink)
    nnode = size(runtime%element(1)%field_coordinates, 2)
    nevab = size(runtime%dof%element_variables(1)%values)
    ngaus = size(runtime%gauss(1)%stiffness%weighted_jacobian)
    ngaus_mass = size(runtime%gauss(1)%mass%weighted_jacobian)
    s_ntotv = int(size(runtime%dof%fixed_mask), ink)
    s_ndofix = int(size(runtime%boundary), ink)
    s_ntcurve = int(size(runtime%amplitudes), ink)
    s_iblks = int(opt_or(runtime%increment%current_block), ink)
    s_lblks = int(opt_or(runtime%increment%completed_blocks), ink)
    ! The two line cursors are RESERVED: no value is claimed for them, so they are
    ! staged as zero and the ledger is what says the zero means nothing. Writing a
    ! number that looks like a file offset would be worse than writing none.
    s_lineload = 0_ink
    s_linet = 0_ink

    ! ------------------------------------------------- problem/runtime agreement
    ! EVERY extent this routine uses to INDEX `problem`, checked in one place and BEFORE
    ! the first staging loop that does so.
    !
    ! The extent rule (L2c-fold-design.md 5.2) makes the runtime the single derivation
    ! source and lets the ProblemState side only assert agreement -- but an assertion
    ! placed after the loop it protects is not a guard. Two of these checks used to sit
    ! beside the arrays they were about (nodes just above the coord loop, amplitudes just
    ! above the tcurves loop) and so ran AFTER the element and section loops had already
    ! indexed `problem%mesh%elements(ie)` and `problem%sections(ig)` with ie and ig running
    ! to the RUNTIME's counts. A runtime built from a larger model than the problem handed
    ! in was therefore an out-of-bounds read, not a reported disagreement -- and the
    ! element and section counts had no agreement check at all, so nothing would have said
    ! so afterwards either. Found while trying to fire the nodes check on purpose: the
    ! attempt could not be made safely, which is its own evidence.
    !
    ! These are MOVED here, not copied: a second copy beside each loop would be the second
    ! source invariant 4 forbids, and would rot apart from this one.
    if (size(problem%mesh%nodes) /= int(s_npoin)) then
      call fail(errors, 'ProblemState carries '//itoa(size(problem%mesh%nodes))//               &
                ' nodes and the runtime numbers '//itoa(int(s_npoin))//                         &
                '; the extent rule makes the runtime the source and this a disagreement')
      return
    end if
    if (size(problem%mesh%elements) /= int(s_nelem)) then
      call fail(errors, 'ProblemState carries '//itoa(size(problem%mesh%elements))//            &
                ' elements and the runtime numbers '//itoa(int(s_nelem))//                      &
                '; the extent rule makes the runtime the source and this a disagreement')
      return
    end if
    if (size(problem%sections) /= int(s_ngroup) .or.                                            &
        size(problem%mesh%elsets) /= int(s_ngroup)) then
      call fail(errors, 'ProblemState carries '//itoa(size(problem%sections))//                 &
                ' sections and '//itoa(size(problem%mesh%elsets))//                             &
                ' element sets and the runtime numbers '//itoa(int(s_ngroup))//                 &
                '; the extent rule makes the runtime the source and this a disagreement')
      return
    end if
    if (size(problem%amplitudes) /= int(s_ntcurve)) then
      call fail(errors, 'ProblemState carries '//itoa(size(problem%amplitudes))//               &
                ' amplitudes and the runtime numbers '//itoa(int(s_ntcurve))//                  &
                '; the extent rule makes the runtime the source and this a disagreement')
      return
    end if
    ! The boundary records are the one pairing that is NOT a plain extent question, so its
    ! message says something different. build_boundary DROPS a record whose resolved
    ! variable index is 0 (contract `boundary.skip_unnumbered_record`,
    ! yl_runtime_build.f90:871), and one drop shifts the source of every later record by
    ! one -- publishing the wrong node, component and value for each, all individually
    ! plausible. commit cannot recover the correspondence without re-deriving the dof
    ! numbering build_runtime owns, which invariant 4 forbids, so it refuses instead:
    ! widening the capability gate to a deck that can skip a record fails HERE, at the line
    ! that makes the assumption.
    if (size(problem%steps(1)%boundary) /= int(s_ndofix)) then
      call fail(errors, 'ProblemState carries '//itoa(size(problem%steps(1)%boundary))//        &
                ' boundary records and build_runtime admitted '//itoa(int(s_ndofix))//          &
                '; commit reads the two positionally and cannot recover which record was '//    &
                'skipped without re-deriving the dof numbering')
      return
    end if

    ! ----------------------------------------------------------------- stage
    ! Plain arrays. `int(..., ink)` and `real(..., irk)` are explicit at every crossing:
    ! the runtime is int32/real64 by construction and the legacy kinds are whatever
    ! Vartype.f90 says they are, and an implicit conversion here would be the one place
    ! a kind change in the legacy tree could go unnoticed.
    allocate (s_lmdofn(s_mdofn), s_lcdofn(s_mdofn))
    s_lmdofn = STAGE_POISON_I;  s_lcdofn = STAGE_POISON_I
    s_lmdofn = int(runtime%dof%component_to_active, ink)
    s_lcdofn = int(runtime%dof%active_to_component, ink)

    allocate (s_nodfn(s_cdofn, s_npoin))
    s_nodfn = STAGE_POISON_I
    s_nodfn = int(runtime%dof%node_variables, ink)

    allocate (s_iffix(s_ntotv), s_fixed(s_ntotv))
    s_iffix = STAGE_POISON_I;  s_fixed = STAGE_POISON_R
    s_iffix = int(runtime%dof%fixed_mask, ink)
    s_fixed = real(runtime%dof%prescribed_value, irk)

    allocate (s_appear(s_ngroup))
    s_appear = STAGE_POISON_I
    s_appear = int(runtime%activation%section_state, ink)

    allocate (s_result_zero(s_ntotv), s_tofor(s_ntotv), s_stfor(s_ntotv),                       &
              s_toforl(s_ntotv), s_toform(s_ntotv))
    s_result_zero = STAGE_POISON_R;  s_tofor = STAGE_POISON_R;  s_stfor = STAGE_POISON_R
    s_toforl = STAGE_POISON_R;       s_toform = STAGE_POISON_R
    s_result_zero = real(runtime%vectors%total_displacement, irk)
    s_tofor = real(runtime%vectors%external_force_total, irk)
    s_stfor = real(runtime%vectors%internal_force, irk)
    s_toforl = real(runtime%vectors%external_force_load, irk)
    s_toform = real(runtime%vectors%external_force_mass, irk)

    ! RESERVED (rule 2 of the STAGE_POISON note): allocated to the final length, contents
    ! deliberately not set. Reading them before the first increment is what the ledger
    ! forbids, and staging a real value here would quietly turn "undefined" into "zero".
    ! They are poisoned like everything else and therefore reach the globals CARRYING THE
    ! SENTINEL -- which is the honest form of "this has no value yet". All four are
    ! RUNTIME_VALUE_RESERVED in the ledger and `ignore` + `emit = "none"` in the M2 map,
    ! so nothing dumps or compares them.
    allocate (s_delitfi(s_ntotv), s_deltafi(s_ntotv))
    ! ZEROED, not poisoned (2026-09-11). These two are the increment work vectors legacy
    ! allocates at Fem.f90:246 and never initialises, so the map calls them RESERVED and
    ! nothing compares them. That was accurate about legacy and wrong about what the
    ! SOLVER does: the second residual evaluation reads delitfi before anything writes it,
    ! and legacy only survives that because a freshly mapped page is zero.
    !
    ! Under --adapter=on the poison made it visible: Fem.f90:240 deallocates these (commit
    ! had allocated them) and :246 reallocates the same block, so the huge() sentinel came
    ! straight back and the second residual was NaN while the FIRST matched legacy
    ! exactly. Zeroing here reproduces what legacy actually has rather than what its
    ! source literally says. The underlying read-before-write in legacy is R23's family
    ! and is not fixed here.
    s_delitfi = 0.0_irk;  s_deltafi = 0.0_irk

    allocate (s_line_load_block(size(runtime%cursor%load_line_per_block)))
    allocate (s_line_temp_block(size(runtime%cursor%temperature_line_per_block)))
    s_line_load_block = STAGE_POISON_I;  s_line_temp_block = STAGE_POISON_I

    allocate (s_ice0(s_nelem))
    s_ice0 = STAGE_POISON_I
    do ie = 1, int(s_nelem)
      s_ice0(ie) = int(opt_or(runtime%element(ie)%refinement_skip), ink)
    end do

    allocate (s_trans(s_ntotv))
    do i = 1, int(s_ntotv)
      s_trans(i)%nintf = STAGE_POISON_I
      s_trans(i)%nintf = int(runtime%dof%interpolation_count(i), ink)
      nullify (s_trans(i)%listf, s_trans(i)%rintf)
    end do

    ! Element records: the four per-element pointer payloads plus the two Gauss rules.
    allocate (s_element(s_nelem))
    do ie = 1, int(s_nelem)
      call null_element(s_element(ie))
      call poison_element(s_element(ie))
      ! mesh.elements.material -> element%matno. Written here and not only for its own
      ! row: sections.material_header is RECONSTRUCTED from element(group(g)%list(1))%matno
      ! (the .glb header slot it came from is overwritten in place at Fem.f90:1717 and is
      ! not observable at model_ready), so leaving matno unassigned would publish that row
      ! out of the sentinel even with group%list correct.
      s_element(ie)%matno = int(opt_or(problem%mesh%elements(ie)%material), ink)
      ! The last two element rows (M4-01 step 4, element). Both are `derived:index_map` in
      ! the map and both are owned by ProblemState -- legacy fills them from the group loop
      ! that reads the element (Elements.f90:1082,1112), and the pipeline's
      ! derive_element_kinds reproduces exactly that from the element-to-elset reference.
      ! So commit copies them; it does not re-derive them from the elset membership, which
      ! would be a second derivation of something ProblemState already decided.
      s_element(ie)%index = int(opt_or(problem%mesh%elements(ie)%kind), ink)
      s_element(ie)%group = int(opt_or(problem%mesh%elements(ie)%elset), ink)
      allocate (s_element(ie)%ldofs(nevab))
      s_element(ie)%ldofs = STAGE_POISON_I
      s_element(ie)%ldofs = int(runtime%dof%element_variables(ie)%values, ink)

      allocate (s_element(ie)%field(1))
      call null_element_field(s_element(ie)%field(1))
      allocate (s_element(ie)%field(1)%ldofs_f(nevab))
      s_element(ie)%field(1)%ldofs_f = STAGE_POISON_I
      s_element(ie)%field(1)%ldofs_f =                                                          &
        int(runtime%dof%element_field_variables(ie)%fields(1)%values, ink)
      allocate (s_element(ie)%field(1)%elcod_f(s_ndimn, nnode))
      s_element(ie)%field(1)%elcod_f = STAGE_POISON_R
      s_element(ie)%field(1)%elcod_f = real(runtime%element(ie)%field_coordinates, irk)
      ! mesh.elements.nodes (step 3b). One of the two rows whose absence aborts the dump
      ! unconditionally: yl_state_dump.f90:135 tests associated(element(1)%field(1)%lnods_f)
      ! with no count in front of it, so a null here is not a wrong value, it is no
      ! snapshot at all.
      allocate (s_element(ie)%field(1)%lnods_f(nnode))
      s_element(ie)%field(1)%lnods_f = STAGE_POISON_I
      s_element(ie)%field(1)%lnods_f = int(problem%mesh%elements(ie)%nodes, ink)
      ! DEFINED as zero, corrected 2026-09-10 (see yl_runtime_build.f90 for the finding).
      ! They were staged as RESERVED poison on the map's claim that legacy never
      ! initialises them; Global.f90:1325-1327 sets all three to 0.0 three lines after the
      ! allocates the map's reason cites. Poisoned buffers here made Residu.f90:1021's
      ! `eload = eload + eload` produce an Infinity residual.
      allocate (s_element(ie)%field(1)%tload(nevab))
      allocate (s_element(ie)%field(1)%eload(nevab))
      allocate (s_element(ie)%field(1)%rload(nevab))
      s_element(ie)%field(1)%tload = STAGE_POISON_R
      s_element(ie)%field(1)%eload = STAGE_POISON_R
      s_element(ie)%field(1)%rload = STAGE_POISON_R
      s_element(ie)%field(1)%tload = real(runtime%element(ie)%total_load, irk)
      s_element(ie)%field(1)%eload = real(runtime%element(ie)%external_load, irk)
      s_element(ie)%field(1)%rload = real(runtime%element(ie)%body_load, irk)

      ! Existence face (ADR-0009), derived-zero. stiff_u assigns into this every
      ! increment (Stiff.f90:672) and legacy creates it while reading .ele
      ! (Global.f90:1312-1313: allocate, then =0.0). Zeroed rather than poisoned
      ! BECAUSE that is what legacy leaves here at model_ready -- the poison
      ! discipline exists to make an unwritten row visible, and this row is written,
      ! by legacy, to zero.
      ! Existence face (ADR-0009), derived. FORCE_EXTERNAL loops `do ifield = 1,
      ! element(ie)%nrfields` (Fem.f90:13417-13418); at 0 the body-force assembly runs
      ! zero times and the correct element loads gravity computed are discarded.
      s_element(ie)%nrfields = int(size(runtime%dof%element_field_variables(ie)%fields), ink)   !@existence: element_nrfields
      allocate (s_element(ie)%field(1)%khandmc(1)%fstif(nevab, nevab))   !@existence: element_field_khandmc_fstif
      s_element(ie)%field(1)%khandmc(1)%fstif = 0.0_irk

      allocate (s_element(ie)%egaus(2))
      call null_gauss(s_element(ie)%egaus(1))
      call null_gauss(s_element(ie)%egaus(2))
      allocate (s_element(ie)%egaus(1)%djacb(ngaus))
      allocate (s_element(ie)%egaus(1)%gpcod(s_ndimn, ngaus))
      allocate (s_element(ie)%egaus(1)%cartd(s_ndimn, nnode, ngaus))
      s_element(ie)%egaus(1)%djacb = STAGE_POISON_R
      s_element(ie)%egaus(1)%gpcod = STAGE_POISON_R
      s_element(ie)%egaus(1)%cartd = STAGE_POISON_R
      s_element(ie)%egaus(1)%djacb = real(runtime%gauss(ie)%stiffness%weighted_jacobian, irk)
      s_element(ie)%egaus(1)%gpcod = real(runtime%gauss(ie)%stiffness%point_coordinates, irk)
      s_element(ie)%egaus(1)%cartd = real(runtime%gauss(ie)%stiffness%shape_gradient, irk)
      allocate (s_element(ie)%egaus(2)%djacb(ngaus_mass))
      allocate (s_element(ie)%egaus(2)%gpcod(s_ndimn, ngaus_mass))
      s_element(ie)%egaus(2)%djacb = STAGE_POISON_R
      s_element(ie)%egaus(2)%gpcod = STAGE_POISON_R
      s_element(ie)%egaus(2)%djacb = real(runtime%gauss(ie)%mass%weighted_jacobian, irk)
      s_element(ie)%egaus(2)%gpcod = real(runtime%gauss(ie)%mass%point_coordinates, irk)
      ! egaus(2)%cartd stays null: legacy allocates cartd only for a rule whose name is
      ! not 'mass' (Elements.f90:1232), so an allocated one here would be a shape the
      ! solver never sees and a leak the releaser would have to guess at.
    end do

    ! Section records: the per-section node table.
    allocate (s_group(s_ngroup))
    do ig = 1, int(s_ngroup)
      call null_group(s_group(ig))
      call poison_group(s_group(ig))
      ! sections.elset_size and mesh.sets.elset (step 3b). The other unconditional abort:
      ! yl_state_adapters.f90:271 fails outright on nelgroup < 1 before it looks at
      ! anything, then on an unassociated list. Both are needed to reach
      ! sections.material_header at all.
      !
      ! The ELEMENT IDS, not the storage indices: the map calls this row's values element
      ! ids, and mesh.elements[].id is the 1-based record order on this path (the adapter
      ! synthesises it and legacy discards the deck's own i0), so the two coincide here.
      ! They would not coincide under a renumbering, which is why this reads elsets rather
      ! than counting.
      n = size(problem%mesh%elsets(ig)%elements)
      s_group(ig)%nelgroup = int(n, ink)
      allocate (s_group(ig)%list(n))
      s_group(ig)%list = STAGE_POISON_I
      s_group(ig)%list = int(problem%mesh%elsets(ig)%elements, ink)

      ! The 15 ProblemState-owned section header fields (M4-01 step 4, group).
      ! CHARACTER TRUNCATION IS THE HAZARD HERE, not absence: legacy's slots are short
      ! (class is character(2), fieldid character(5), name character(10)) and Fortran
      ! truncates a longer right-hand side silently. The staging poison cannot see that --
      ! a truncated string is a written value -- so yl_runtime_bridge_test compares each
      ! committed field against trim() of its ProblemState source, which is what a
      ! truncation breaks.
      s_group(ig)%kname = opt_text_or(problem%sections(ig)%name)
      s_group(ig)%name = opt_text_or(problem%sections(ig)%element)
      s_group(ig)%class = opt_text_or(problem%sections(ig)%class)
      s_group(ig)%fieldid = opt_text_or(problem%sections(ig)%fields)
      s_group(ig)%sptype = opt_text_or(problem%sections(ig)%formulation)
      s_group(ig)%special = opt_text_or(problem%sections(ig)%special)
      s_group(ig)%index = int(opt_or(problem%sections(ig)%element_kind), ink)
      ! matno is the EFFECTIVE material, not the .glb header slot: legacy overwrites the
      ! header value in place at Fem.f90:1717, so what is observable at model_ready is
      ! sections[].material. sections[].material_header is the pre-overwrite value and is
      ! reconstructed from element%matno instead (step 3b) -- two rows, two sources, and
      ! they are identical only by accident on the golden decks.
      s_group(ig)%matno = int(opt_or(problem%sections(ig)%material), ink)
      s_group(ig)%ilayer = int(opt_or(problem%sections(ig)%layer), ink)
      s_group(ig)%liquj = int(opt_or(problem%sections(ig)%liquefaction), ink)
      s_group(ig)%uplift_ic = int(opt_or(problem%sections(ig)%uplift), ink)
      s_group(ig)%type_nalgo = int(opt_or(problem%sections(ig)%algorithm), ink)
      s_group(ig)%type_stiff = int(opt_or(problem%sections(ig)%stiffness_kind), ink)

      ! Existence face (ADR-0009): estif_assemble reads this every increment
      ! (Stiff.f90:3344). sections.order_time is a map row with emit="none", so it is
      ! never compared -- and null_group nullifies the pointer, which is what the
      ! comparison face wants and what left the adapter path with nothing to read.
      allocate (s_group(ig)%type_mass(size(existence%group_type_mass, 1)))   !@existence: group_type_mass
      s_group(ig)%type_mass = int(existence%group_type_mass(:, ig), ink)
      allocate (s_group(ig)%order_time(2, size(existence%group_order_time, 2)))   !@existence: group_order_time
      s_group(ig)%order_time = int(existence%group_order_time(:, :, ig), ink)
      s_group(ig)%type_ecoint = int(opt_or(problem%sections(ig)%stress_recovery), ink)
      s_group(ig)%elcod_local = real(opt_or_real(problem%sections(ig)%local_axes), irk)

      ! ---- the four remaining section rows (M4-01 step 4, group) -------------------
      !
      ! nrfields: FROM_RUNTIME. It is the plain extent of a runtime collection -- the
      ! number of field slices build_runtime split this section's element variables into.
      ! It does NOT go through ProblemState: sections[].fields is an opt_text NAMING a
      ! field, not a list of them, so ProblemState has no count to offer.
      !
      ! Read from the section's FIRST element and then required to hold for every element
      ! of the section. Reading only element 1 would be a spot check, and the W1 fix in
      ! verify_registered is this file's precedent for refusing that: a split that
      ! regressed only element 2 would be committed blind.
      ie = int(problem%mesh%elsets(ig)%elements(1))
      nrf = size(runtime%dof%element_field_variables(ie)%fields)
      do i = 1, size(problem%mesh%elsets(ig)%elements)
        if (size(runtime%dof%element_field_variables(                                           &
              int(problem%mesh%elsets(ig)%elements(i)))%fields) /= nrf) then
          call fail(errors, 'section '//itoa(ig)//' splits its elements into different '//      &
                    'numbers of fields; nrfields is a property of the section and cannot '//    &
                    'be read from one element')
          return
        end if
      end do
      s_group(ig)%nrfields = int(nrf, ink)

      ! sections.dof_count: DERIVED. nfdof = nevab / nnode, where both are runtime extents
      ! (nevab = size(runtime%dof%element_variables(1)%values), nnode =
      ! size(runtime%element(1)%field_coordinates, 2)) and the map states the relation as
      ! "nevab = nfdof*nnode". Computed, not read, which is what DERIVED means here.
      if (nnode <= 0 .or. mod(nevab, nnode) /= 0) then
        call fail(errors, 'nevab '//itoa(nevab)//' is not a whole multiple of nnode '//         &
                  itoa(nnode)//', so the per-field dof count nevab/nnode is not an integer')
        return
      end if
      nfdof = nevab / nnode

      ! sections.dof_list: PRECONDITION FIRST, then a copy.
      !
      ! listdof_f is the list of GLOBAL COMPONENT NUMBERS the field carries. commit takes
      ! it from the runtime's active_to_component (the same array that becomes `lcdofn`),
      ! which is the model's component list -- and that is the field's list only when the
      ! section has ONE field carrying EVERY component. With two fields the deck decides
      ! which components go to which field, and nothing in the runtime or in ProblemState
      ! records that split: commit would be inventing it.
      !
      ! So the condition is stated and REFUSED when it does not hold, rather than noted.
      ! Widening the capability gate to a multi-field section fails HERE, at the line that
      ! makes the assumption, instead of silently publishing one field's components as
      ! another's.
      if (nrf /= 1 .or. nfdof /= int(s_mdofn)) then
        call fail(errors, 'section '//itoa(ig)//' has '//itoa(nrf)//' field(s) carrying '//     &
                  itoa(nfdof)//' dofs against a model component count of '//                    &
                  itoa(int(s_mdofn))//'; commit can only source a field dof list from the '//   &
                  'model component list when one field carries every component')
        return
      end if
      allocate (s_group(ig)%dof(nrf))
      do f = 1, nrf
        s_group(ig)%dof(f)%nfdof = int(nfdof, ink)
        allocate (s_group(ig)%dof(f)%listdof_f(nfdof))
        s_group(ig)%dof(f)%listdof_f = STAGE_POISON_I
        s_group(ig)%dof(f)%listdof_f = int(runtime%dof%active_to_component(1:nfdof), ink)
      end do

      ! derived.counts.nstre: DERIVED, and the derivation is legacy's own, transcribed
      ! from Global.f90:1279-1289 in that order because the later lines OVERWRITE the
      ! earlier ones:
      !     nstre = 3*(ndimn-1)              ! :1279
      !     if (ndimn == 2) nstre = 4        ! :1287   -- not 3, which the formula gives
      !     if (class == 'BM' .or. index == 1) nstre = 1   ! :1288
      ! Writing only the ndimn==2 case would be right on both golden decks and wrong as
      ! soon as a 3-D or beam section appears.
      nstre = 3 * (int(s_ndimn) - 1)
      if (int(s_ndimn) == 2) nstre = 4
      if (trim(opt_text_or(problem%sections(ig)%class)) == 'BM' .or.                             &
          int(opt_or(problem%sections(ig)%element_kind)) == 1) nstre = 1
      s_group(ig)%nstre = int(nstre, ink)

      n = size(runtime%topology%sections(ig)%nodes)
      s_group(ig)%np_unode = int(n, ink)
      allocate (s_group(ig)%unode(n))
      do i = 1, n
        call null_unode(s_group(ig)%unode(i))
        call poison_unode(s_group(ig)%unode(i))
        s_group(ig)%unode(i)%ipoin = int(opt_or(runtime%topology%sections(ig)%nodes(i)%node_id), ink)
        s_group(ig)%unode(i)%ne_unode =                                                         &
          int(opt_or(runtime%topology%sections(ig)%nodes(i)%element_count), ink)
        allocate (s_group(ig)%unode(i)%list(size(runtime%topology%sections(ig)%nodes(i)%elements)))
        s_group(ig)%unode(i)%list = STAGE_POISON_I
        s_group(ig)%unode(i)%list = int(runtime%topology%sections(ig)%nodes(i)%elements, ink)
        ! np_unode and patch_nod are the stabilisation pair: not assigned and not
        ! allocated on this path. The ledger calls them ABSENT and verify_registered
        ! has already refused a runtime that allocated them.
        s_group(ig)%unode(i)%np_unode = 0_ink
      end do
    end do

    ! Node -> section index.
    allocate (s_listp(s_npoin))
    do i = 1, int(s_npoin)
      n = int(runtime%topology%node_sections%group_count(i))
      s_listp(i)%mgroup = STAGE_POISON_I
      s_listp(i)%mgroup = int(n, ink)
      nullify (s_listp(i)%listg, s_listp(i)%listp)
      if (n > 0) then
        allocate (s_listp(i)%listg(n), s_listp(i)%listp(n))
        s_listp(i)%listg = STAGE_POISON_I;  s_listp(i)%listp = STAGE_POISON_I
        s_listp(i)%listg = int(runtime%topology%node_sections%section_index(i)%values, ink)
        s_listp(i)%listp = int(runtime%topology%node_sections%position_in_section(i)%values, ink)
      end if
    end do

    ! Prescription records.
    !
    allocate (s_prescrib(s_ndofix))
    do i = 1, int(s_ndofix)
      call null_prescrib(s_prescrib(i))
      call poison_prescrib(s_prescrib(i))
      ! The six ProblemState-owned constraint fields (M4-01 step 4, prescrib). A
      ! field-by-field copy and not a regrouping: the adapter already emits one
      ! steps[0].boundary[] row per admitted (set, node) pair (yl_adapter_load.f90:271-289),
      ! which is one legacy prescrib record.
      !
      ! FIVE OF THE SIX ARE SMALL INTEGERS OUT OF ONE RECORD, so a source mix-up between
      ! them is a value swap and not a type error. They are equal to each other on the
      ! golden decks often enough that the bridge fixture had to be made able to tell them
      ! apart -- see the note beside the fixture's boundary records.
      s_prescrib(i)%ifixset = int(opt_or(problem%steps(1)%boundary(i)%name), ink)
      ! nodfix carries TWO map rows, and only one of them is read from here in the obvious
      ! sense. steps0.boundary.nodes is the record's node. mesh.sets.nset is owned by
      ! ProblemState.mesh.nsets[].nodes, and the dump RECONSTRUCTS it as the distinct nodfix
      ! of each ifixset in first-occurrence order (yl_state_adapters.f90:399-433) -- which is
      ! the same arithmetic finalize_problem uses to build mesh.nsets[] out of these very
      ! records (derive_node_sets, yl_problem_pipeline.f90:1394). So both rows are FROM_
      ! PROBLEM and both are read HERE; committing from mesh.nsets[] instead would be a
      ! second path to the same value, which is what invariant 4 forbids.
      s_prescrib(i)%nodfix = int(opt_or(problem%steps(1)%boundary(i)%nset), ink)
      s_prescrib(i)%ifixvar = int(opt_or(problem%steps(1)%boundary(i)%dof), ink)
      s_prescrib(i)%itcurve = int(opt_or(problem%steps(1)%boundary(i)%amplitude), ink)
      s_prescrib(i)%outfix = int(opt_or(problem%steps(1)%boundary(i)%record_reaction), ink)
      s_prescrib(i)%vdofix = real(opt_or_real(problem%steps(1)%boundary(i)%value), irk)
      s_prescrib(i)%ldofix = int(opt_or(runtime%boundary(i)%dof_index), ink)
      s_prescrib(i)%lnefix = int(opt_or(runtime%boundary(i)%element_count), ink)
      n = size(runtime%boundary(i)%attached_element)
      allocate (s_prescrib(i)%leldofix(n), s_prescrib(i)%levdofix(n), s_prescrib(i)%lefdofix(n))
      s_prescrib(i)%leldofix = STAGE_POISON_I
      s_prescrib(i)%levdofix = STAGE_POISON_I
      s_prescrib(i)%lefdofix = STAGE_POISON_I
      s_prescrib(i)%leldofix = int(runtime%boundary(i)%attached_element, ink)
      s_prescrib(i)%levdofix = int(runtime%boundary(i)%attached_local_position, ink)
      s_prescrib(i)%lefdofix = int(runtime%boundary(i)%attached_field, ink)
    end do

    ! ---------------------------------------------------- ProblemState half (step 3)
    ! The first values this module takes out of `problem` rather than out of `runtime`.
    ! Extents still come from the runtime (§5.2 of the design gives every extent exactly
    ! one derivation source); ProblemState supplies only the VALUES, and where both sides
    ! know a count the ProblemState side is asserted to agree rather than used.
    n_materials = size(problem%materials)
    n_steps = size(problem%steps)

    ! mesh.nodes.xyz -> coord(ndimn, npoin), Fortran order. The extent is the runtime's,
    ! and the two are asserted to agree in the agreement gate above.
    allocate (s_coord(s_ndimn, s_npoin))
    s_coord = STAGE_POISON_R
    do i = 1, int(s_npoin)
      s_coord(:, i) = real(problem%mesh%nodes(i)%xyz, irk)
    end do

    ! steps[0].activation[].active -> appear_process(1:ngroup, 0:nblks).
    !
    ! THE ONE MIXED ROW IN THE LEDGER. Columns 1..nblks come from ProblemState, but COLUMN
    ! 0 IS A LEGACY CONSTANT with no ProblemState counterpart -- `activation[]` carries one
    ! entry per step, not nblks+1 -- so this row's entry says FROM_PROBLEM while part of
    ! its value is legacy's own initialisation. Audited 2026-09-09 (M4-01 3b checkpoint):
    ! of the five literals this staging assigns, three belong to `emit = "none"` rows and
    ! one is overwritten before publication; this is the only published row with a constant
    ! component, which is why the ledger keeps six states instead of growing a seventh for
    ! it. The exception is not left to this comment: the ledger's note carries it, and
    ! yl_runtime_bridge_test asserts BOTH `lbound(appear_process,2) == 0` and
    ! `appear_process(:,0) == 0`, so it is a red line rather than a claim. If a SECOND
    ! mixed row ever appears, that is a category and the state vocabulary is reopened.
    !
    ! LOWER BOUND 0 ON THE SECOND DIMENSION, not 1: column 0 is the initial state, zeroed
    ! at Global.f90:968 and CONSUMED at Fem.f90:1719-1720, and yl_state_adapters.f90:815
    ! asserts `lbound(...,2) == 0` before emitting. A 1-based allocation here would shift
    ! every column by one and still look well formed.
    allocate (s_appear_process(s_ngroup, 0:n_steps))
    s_appear_process = STAGE_POISON_I
    s_appear_process(:, 0) = 0_ink
    do ib = 1, n_steps
      do ig = 1, int(s_ngroup)
        s_appear_process(ig, ib) = int(opt_or(problem%steps(ib)%activation(ig)%active), ink)
      end do
    end do

    ! steps[0].activation[].material -> matno_process(ngroup, nblks). 1-based, unlike
    ! appear_process: Global.f90:965 allocates it (ngroup, nblks).
    allocate (s_matno_process(s_ngroup, n_steps))
    s_matno_process = STAGE_POISON_I
    do ib = 1, n_steps
      do ig = 1, int(s_ngroup)
        s_matno_process(ig, ib) = int(opt_or(problem%steps(ib)%activation(ig)%material), ink)
      end do
    end do

    ! steps[0].output.stress_averaging -> average_appear(ngroup)
    allocate (s_average_appear(s_ngroup))
    s_average_appear = STAGE_POISON_I
    s_average_appear = int(problem%steps(1)%output%stress_averaging, ink)

    ! steps[0].load.gravity.{direction,amplitude} -> factg(ndimn), tcurvegravity(ngroup)
    allocate (s_factg(s_ndimn))
    s_factg = STAGE_POISON_R
    s_factg = real(problem%steps(1)%load%gravity%direction, irk)

    allocate (s_tcurvegravity(s_ngroup))
    s_tcurvegravity = STAGE_POISON_I
    s_tcurvegravity = int(problem%steps(1)%load%gravity%amplitude, ink)

    ! materials[] -> props(nmats), a TWO-LEVEL POINTER CHAIN: props(i)%mechanical is a
    ! pointer to a mechanical_property, whose %solid is a pointer to a solid_skeleton.
    ! yl_state_dump guards both levels (`props(d1)%mechanical is not associated`, then
    ! `%solid`), and commit_release has to unwind them in the opposite order. This is the
    ! heaviest ownership this module has taken on, and every allocation here has a matching
    ! deallocate in commit_release -- see the release path's own comment.
    allocate (s_props(n_materials))
    do id_ = 1, n_materials
      nullify (s_props(id_)%mechanical, s_props(id_)%heat, s_props(id_)%geometry)
      s_props(id_)%name = ''
      allocate (s_props(id_)%mechanical)
      nullify (s_props(id_)%mechanical%solid, s_props(id_)%mechanical%fluid)
      allocate (s_props(id_)%mechanical%solid)
      call null_solid(s_props(id_)%mechanical%solid)
      call poison_solid(s_props(id_)%mechanical%solid)
      s_props(id_)%name = opt_text_or(problem%materials(id_)%name)
      associate (sk => s_props(id_)%mechanical%solid)
        sk%material = opt_text_or(problem%materials(id_)%model)
        sk%e = real(opt_or_real(problem%materials(id_)%E), irk)
        sk%nu = real(opt_or_real(problem%materials(id_)%nu), irk)
        sk%density = real(opt_or_real(problem%materials(id_)%density), irk)
        sk%alfa = real(opt_or_real(problem%materials(id_)%thermal_expansion), irk)
        sk%ratio = real(opt_or_real(problem%materials(id_)%solid_ratio), irk)
        sk%icreep = int(opt_or(problem%materials(id_)%creep_model), ink)
        sk%jliqu = int(opt_or(problem%materials(id_)%liquefaction), ink)
        sk%kind_wt = int(opt_or(problem%materials(id_)%wetting_kind), ink)
      end associate
    end do
    ! sections[].thickness is authored on the SECTION and stored on the MATERIAL
    ! (Material.f90:319; the map's note on that row records the indirection). Resolved
    ! section -> material -> props here, which is the same direction yl_adapter_parts
    ! resolves it when it fills sections[].thickness in the first place.
    do ig = 1, size(problem%sections)
      id_ = int(opt_or(problem%sections(ig)%material))
      if (id_ >= 1 .and. id_ <= n_materials) then
        s_props(id_)%mechanical%solid%thickness =                                             &
          real(opt_or_real(problem%sections(ig)%thickness), irk)
      end if
    end do

    ! Amplitude records. Only the current factor is a model_ready row; the curve itself
    ! is authored data and belongs to the ProblemState half.
    ! Amplitude records. The extent is the runtime's; the agreement gate above has already
    ! refused a problem whose amplitude count differs.
    allocate (s_tcurves(s_ntcurve))
    do i = 1, int(s_ntcurve)
      call null_tcurve(s_tcurves(i))
      call poison_tcurve(s_tcurves(i))
      s_tcurves(i)%dfact = real(opt_or_real(runtime%amplitudes(i)%factor), irk)

      ! The three ProblemState-sourced amplitude fields (M4-01 step 4, tcurves).
      !
      ! type_curve is character(20) and the map compares it trim()ed, so this is the same
      ! silent-truncation hazard as the section header strings: the poison cannot see it,
      ! because a truncated string is a written one. The bridge test's trim() comparison is
      ! what catches it.
      s_tcurves(i)%type_curve = opt_text_or(problem%amplitudes(i)%type)
      ! amplitudes.points.count -> ntime. DERIVED, not FROM_PROBLEM: it is the CARDINALITY
      ! of a ProblemState collection rather than a value read out of one, and the map owns
      ! it as `derived` with the rule "= count(amplitudes[].points)". The runtime cannot
      ! supply it either -- amplitude_state_t carries only `factor` -- so unlike every
      ! extent in this routine there is no runtime source to prefer.
      n = size(problem%amplitudes(i)%points)
      s_tcurves(i)%ntime = int(n, ink)
      ! ttime_curve / dfact_curve: the two pointer targets this step adds to the record
      ! array. commit_release grows with them, in the same commit, innermost first.
      allocate (s_tcurves(i)%ttime_curve(n), s_tcurves(i)%dfact_curve(n))
      s_tcurves(i)%ttime_curve = STAGE_POISON_R
      s_tcurves(i)%dfact_curve = STAGE_POISON_R
      do j = 1, n
        s_tcurves(i)%ttime_curve(j) =                                                           &
          real(opt_or_real(problem%amplitudes(i)%points(j)%time), irk)
        s_tcurves(i)%dfact_curve(j) =                                                           &
          real(opt_or_real(problem%amplitudes(i)%points(j)%value), irk)
      end do
    end do

    ! ---------------------------------------------- the C2 scalars (M4-01 step 5b)
    ! Poisoned first, as everywhere else, so a deleted assignment publishes a sentinel
    ! rather than whatever the stack held. Characters get '' for the reason poison_group
    ! states: there is no integer sentinel for a character(20), so for those the detection
    ! of a missing write is the bridge test's trim() comparison.
    s_type_nl = STAGE_POISON_I;   s_nonsym = STAGE_POISON_I;   s_ngrav = STAGE_POISON_I
    s_nmats = STAGE_POISON_I;     s_nblks = STAGE_POISON_I;    s_nfixsets = STAGE_POISON_I
    s_gravy = STAGE_POISON_R
    s_probn = '';  s_outplot = '';  s_type_problem = '';  s_type_solver = ''
    s_type_load = '';  s_type_abc = ''

    s_probn = opt_text_or(problem%case%name)
    s_outplot = opt_text_or(problem%steps(1)%output%format)
    s_type_problem = opt_text_or(problem%steps(1)%procedure)
    s_type_solver = opt_text_or(problem%solver%linear)
    s_type_load = opt_text_or(problem%steps(1)%load_mode)
    s_type_abc = opt_text_or(problem%interactions%absorbing%type)
    s_type_nl = int(opt_or(problem%steps(1)%controls%nonlinear_type), ink)
    s_ngrav = int(opt_or(problem%steps(1)%load%gravity%enabled), ink)
    s_gravy = real(opt_or_real(problem%steps(1)%load%gravity%magnitude), irk)

    ! nonsym IS INVERTED, and the map says so: solver.symmetric is a logical, the legacy
    ! slot is a 0/1 flag "whose sense is inverted; the inversion is the bridge's job"
    ! (yl_problem_types.f90:179-182). symmetric = .true. therefore means nonsym = 0.
    ! Both golden decks are symmetric, so the right answer is 0 and getting the direction
    ! backwards yields 1 -- visible on the decks we have, unlike most of the swaps this
    ! file has had to build fixtures for.
    s_nonsym = merge(0_ink, 1_ink, opt_logical_or(problem%solver%symmetric))

    ! The 20 GiD output switches. One line each, named on both sides, because a
    ! transposition inside a 20-element list is exactly the kind of thing no count check
    ! would catch and no golden deck would show (they are all 0 or 1).
    s_gid_u = int(opt_or(problem%steps(1)%output%field%u), ink)
    s_gid_s = int(opt_or(problem%steps(1)%output%field%s), ink)
    s_gid_ms = int(opt_or(problem%steps(1)%output%field%ms), ink)
    s_gid_f = int(opt_or(problem%steps(1)%output%field%f), ink)
    s_gid_rot = int(opt_or(problem%steps(1)%output%field%rot), ink)
    s_gid_v = int(opt_or(problem%steps(1)%output%field%v), ink)
    s_gid_a = int(opt_or(problem%steps(1)%output%field%a), ink)
    s_gid_t = int(opt_or(problem%steps(1)%output%field%T), ink)
    s_gid_p = int(opt_or(problem%steps(1)%output%field%P), ink)
    s_gid_pv = int(opt_or(problem%steps(1)%output%field%Pv), ink)
    s_gid_ep = int(opt_or(problem%steps(1)%output%field%ep), ink)
    s_gid_y = int(opt_or(problem%steps(1)%output%field%Y), ink)
    s_gid_fc = int(opt_or(problem%steps(1)%output%field%FC), ink)
    s_gid_ns = int(opt_or(problem%steps(1)%output%field%Ns), ink)
    s_gid_ss = int(opt_or(problem%steps(1)%output%field%Ss), ink)
    s_gid_mxy = int(opt_or(problem%steps(1)%output%field%Mxy), ink)
    s_gid_bem = int(opt_or(problem%steps(1)%output%field%bem), ink)
    s_gid_wh = int(opt_or(problem%steps(1)%output%field%wh), ink)
    s_gid_wv = int(opt_or(problem%steps(1)%output%field%wv), ink)
    s_gid_bcs = int(opt_or(problem%steps(1)%output%field%bcs), ink)

    ! The three DERIVED counts: cardinalities of ProblemState collections, computed here
    ! rather than read from anywhere. n_materials and n_steps were already being computed for
    ! extent checks above; nfixsets is the node-set count finalize_problem derived from
    ! the boundary records' distinct set ordinals (derive_node_sets).
    s_nmats = int(n_materials, ink)
    s_nblks = int(n_steps, ink)
    s_nfixsets = int(size(problem%mesh%nsets), ink)

    ! ---------------------------------------- the residue's 27 (M4-01 step 5b)
    ! Every one of these is READ FROM THE CARRIER and then CROSS-CHECKED against the gate
    ! rule that admitted it. Two independent sources that must agree is stronger than
    ! deriving one from the other (L2c-fold-design.md 1.6.2): the adapter's rejection
    ! proves what the value must be, the carrier says what the deck actually held, and a
    ! disagreement means one of the two is broken rather than that the deck is unusual.
    s_restart = int(opt_or(residue%restart), ink)
    s_relis = int(opt_or(residue%relis), ink)
    s_adina = int(opt_or(residue%adina), ink)
    s_runblks = int(opt_or(residue%runblks), ink)
    s_npoinb = int(opt_or(residue%npoinb), ink)
    s_nlayer = int(opt_or(residue%nlayer), ink)
    s_block_stab = int(opt_or(residue%block_stab), ink)
    s_nbackf = int(opt_or(residue%nbackf), ink)
    s_ebody = int(opt_or(residue%ebody), ink)
    s_ninit = int(opt_or(residue%ninit), ink)
    s_state_change = int(opt_or(residue%state_change), ink)
    s_bparameter = int(opt_or(residue%bparameter), ink)
    s_stab_matde = int(opt_or(residue%stab_matde), ink)
    s_nlinks = int(opt_or(residue%nlinks), ink)
    s_nsmat = int(opt_or(residue%nsmat), ink)
    s_ntrans = int(opt_or(residue%ntrans), ink)
    s_nplgroup = int(opt_or(residue%nplgroup), ink)
    s_nedge = int(opt_or(residue%nedge), ink)
    s_edge_load_group = int(opt_or(residue%edge_load_group), ink)
    s_delgroup = int(opt_or(residue%delgroup), ink)
    s_nbeamload = int(opt_or(residue%nbeamload), ink)
    s_nplateload = int(opt_or(residue%nplateload), ink)
    s_ntemp_surface = int(opt_or(residue%ntemp_surface), ink)
    s_ntedge = int(opt_or(residue%ntedge), ink)
    s_ntelgroup = int(opt_or(residue%ntelgroup), ink)
    s_npipe = int(opt_or(residue%npipe), ink)

    ! uinitial is the carrier's only array, and the only NEW allocatable global this step
    ! adds: staged here, move_alloc'd below, released in commit_release, and named in the
    ! release-totality assertion -- the four places design 5.1 says must move together.
    ! Its extent is n_steps, which is a ProblemState cardinality, so the length and the
    ! values come from two different objects and are required to agree.
    if (size(residue%uinitial) /= n_steps) then
      call fail(errors, 'the deck residue carries '//itoa(size(residue%uinitial))//           &
                ' uinitial values and ProblemState has '//itoa(n_steps)//                       &
                ' steps; the carrier and the model disagree about how many blocks '//         &
                'this deck has')
      return
    end if
    allocate (s_uinitial(n_steps))
    s_uinitial = STAGE_POISON_I
    s_uinitial = int(residue%uinitial, ink)

    ! Existence face (ADR-0009). Poisoned like every other buffer: a row that is declared
    ! and never written must show up as huge(), not as a plausible zero.
    allocate (s_ex_order_time_mdofn(size(existence%order_time_mdofn)))
    s_ex_order_time_mdofn = STAGE_POISON_I
    s_ex_order_time_mdofn = int(existence%order_time_mdofn, ink)

    allocate (s_ex_tension_joint(size(existence%tension_joint)))
    s_ex_tension_joint = STAGE_POISON_I
    s_ex_tension_joint = int(existence%tension_joint, ink)

    allocate (s_ex_modf_dis_blocks(size(existence%modf_dis_blocks)))
    s_ex_modf_dis_blocks = STAGE_POISON_I
    s_ex_modf_dis_blocks = int(existence%modf_dis_blocks, ink)

    ! Runtime state manifest (ADR-0009), the rows global_data allocates unconditionally
    ! past the adapter entry. Enumerated by tools/yl_runtime_scan.py, not by crash.
    allocate (s_ex_tlink(size(existence%tlink, 1), size(existence%tlink, 2)))
    s_ex_tlink = int(existence%tlink, ink)
    allocate (s_ex_equvs(size(existence%equvs_process)))
    s_ex_equvs = int(existence%equvs_process, ink)
    allocate (s_ex_force_process(size(existence%force_process)))
    s_ex_force_process = int(existence%force_process, ink)
    ! derived-zero: legacy allocates and zeroes these (Global.f90:1055, :1825).
    allocate (s_ex_listglocbeam(s_ngroup))
    s_ex_listglocbeam = 0_ink
    allocate (s_ex_tension_contact(s_nelem))
    s_ex_tension_contact = 0_ink
    ! Global.f90:708-710 allocates these five and zeroes them. On the ADAPTER path legacy
    ! still does it and commit's move_alloc simply replaces the (identical) zeros; on the
    ! MODERN path the read block they sit in is skipped, so commit is the only thing that
    ! can establish them -- and out_gid_write reads icpnorm while writing the results.
    allocate (s_ex_pnorm(s_ndimn, s_npoin));           s_ex_pnorm = 0.0_irk
    allocate (s_ex_prot(s_ndimn, s_ndimn, s_npoin));   s_ex_prot = 0.0_irk
    allocate (s_ex_icpnorm(s_npoin));                  s_ex_icpnorm = 0_ink
    allocate (s_ex_lelenrt(s_nelem));                  s_ex_lelenrt = 0_ink
    allocate (s_ex_icpspring(s_npoin));                s_ex_icpspring = 0_ink

    call verify_residue_against_gates(residue, errors, ok)
    if (.not. ok) return

    ! ----------------------------------------------------------------- write
    ! From here on nothing allocates, converts or can fail.
    call commit_release()

    npoin = s_npoin;  nelem = s_nelem;  ngroup = s_ngroup;  ndimn = s_ndimn
    mdofn = s_mdofn;  cdofn = s_cdofn;  ntotv = s_ntotv
    ndofix = s_ndofix; ntcurve = s_ntcurve
    iblks = s_iblks;  lblks = s_lblks
    lineload = s_lineload; linet = s_linet
    ! The C2 scalars and the residue's 26 (M4-01 step 5b). Assignment only, from staged
    ! locals of the legacy kinds -- no conversion, no read of `problem` or `residue`, and
    ! nothing here that can fail.
    probn = s_probn;  outplot = s_outplot
    type_problem = s_type_problem;  type_solver = s_type_solver
    type_load = s_type_load;  type_ABC = s_type_abc
    type_nl = s_type_nl;  nonsym = s_nonsym;  NGRAV = s_ngrav
    nmats = s_nmats;  nblks = s_nblks;  nfixsets = s_nfixsets;  gravy = s_gravy
    gid_u = s_gid_u;  gid_s = s_gid_s;  gid_ms = s_gid_ms;  gid_f = s_gid_f
    gid_rot = s_gid_rot;  gid_v = s_gid_v;  gid_a = s_gid_a;  gid_T = s_gid_t
    gid_P = s_gid_p;  gid_Pv = s_gid_pv;  gid_ep = s_gid_ep;  gid_Y = s_gid_y
    gid_FC = s_gid_fc;  gid_Ns = s_gid_ns;  gid_Ss = s_gid_ss;  gid_Mxy = s_gid_mxy
    gid_bem = s_gid_bem;  gid_wh = s_gid_wh;  gid_wv = s_gid_wv;  gid_bcs = s_gid_bcs
    restart = s_restart;  relis = s_relis;  ADINA = s_adina;  runblks = s_runblks
    npoinb = s_npoinb;  nlayer = s_nlayer;  block_stab = s_block_stab
    nbackf = s_nbackf;  ebody = s_ebody;  ninit = s_ninit
    state_change = s_state_change;  Bparameter = s_bparameter
    stab_matde = s_stab_matde;  nlinks = s_nlinks;  nsmat = s_nsmat;  ntrans = s_ntrans
    nplgroup = s_nplgroup;  nedge = s_nedge;  edge_load_group = s_edge_load_group
    delgroup = s_delgroup;  nbeamload = s_nbeamload;  nplateload = s_nplateload
    ntemp_surface = s_ntemp_surface;  ntedge = s_ntedge
    ntelgroup = s_ntelgroup;  npipe = s_npipe

    call move_alloc(s_lmdofn, lmdofn)
    call move_alloc(s_lcdofn, lcdofn)
    call move_alloc(s_nodfn, nodfn)
    call move_alloc(s_iffix, iffix)
    call move_alloc(s_fixed, fixed)
    call move_alloc(s_appear, appear)
    call move_alloc(s_result_zero, result_zero)
    call move_alloc(s_tofor, tofor)
    call move_alloc(s_stfor, stfor)
    call move_alloc(s_toforl, toforl)
    call move_alloc(s_toform, toform)
    call move_alloc(s_delitfi, delitfi)
    call move_alloc(s_deltafi, deltafi)
    call move_alloc(s_line_load_block, line_load_block)
    call move_alloc(s_line_temp_block, line_temp_block)
    call move_alloc(s_ice0, ice0)
    call move_alloc(s_trans, trans)
    call move_alloc(s_element, element)
    call move_alloc(s_group, group)
    call move_alloc(s_listp, listp_group)
    call move_alloc(s_prescrib, prescrib)
    call move_alloc(s_tcurves, tcurves)

    ! The ProblemState half (step 3). Same phase, same rules: nothing here allocates,
    ! converts or can fail.
    call move_alloc(s_coord, coord)
    call move_alloc(s_appear_process, appear_process)
    call move_alloc(s_matno_process, matno_process)
    call move_alloc(s_average_appear, average_appear)
    call move_alloc(s_factg, factg)
    call move_alloc(s_tcurvegravity, tcurvegravity)
    call move_alloc(s_props, props)
    call move_alloc(s_uinitial, uinitial)

    ! --- the EXISTENCE FACE (ADR-0009) -----------------------------------------------
    ! Written in its own pass, in the same WRITE phase, so it cannot introduce a second
    ! writer of the legacy globals -- the constraint that killed the first M4-02 design.
    ! Every symbol here is registered in docs/m4/existence-face.toml with the site whose
    ! abort demanded it; tools/yl_existence_check.py asserts this pass and that table are
    ! the same set, in both directions.
    call move_alloc(s_ex_order_time_mdofn, order_time_mdofn)   !@existence: order_time_mdofn
    call move_alloc(s_ex_tension_joint, tension_joint)         !@existence: tension_joint
    call move_alloc(s_ex_modf_dis_blocks, modf_dis_blocks)     !@existence: modf_dis_blocks
    call move_alloc(s_ex_tlink, tlink)                         !@existence: tlink
    call move_alloc(s_ex_equvs, equvs_process)                 !@existence: equvs_process
    call move_alloc(s_ex_force_process, force_process)         !@existence: force_process
    call move_alloc(s_ex_listglocbeam, listglocbeam)           !@existence: listglocbeam
    call move_alloc(s_ex_tension_contact, tension_contact)     !@existence: tension_contact
    call move_alloc(s_ex_pnorm, pnorm)                         !@existence: pnorm
    call move_alloc(s_ex_prot, prot)                           !@existence: prot
    call move_alloc(s_ex_icpnorm, icpnorm)                     !@existence: icpnorm
    call move_alloc(s_ex_lelenrt, lelenrt)                     !@existence: lelenrt
    call move_alloc(s_ex_icpspring, icpspring)                 !@existence: icpspring
    ! links and trans_c are derived-type arrays legacy allocates unconditionally
    ! (Global.f90:1138, :1772). nlinks is 0 on the whitelist, so links is empty; trans_c
    ! is per-node and legacy sets only %nintf = 0 right after allocating it.
    allocate (links(int(opt_or(residue%nlinks), ink)))         !@existence: links
    allocate (trans_c(s_npoin))                                !@existence: trans_c
    trans_c(1:s_npoin)%nintf = 0_ink

    include 'yl_runtime_scalars.inc'

    commit_owned = .true.
  end subroutine commit_legacy_globals

  !> True while the legacy globals hold storage this module allocated.
  pure logical function commit_owns_globals() result(owned)
    owned = commit_owned
  end function commit_owns_globals

  !> Release everything a previous commit allocated. IDEMPOTENT and total.
  !>
  !> Frees the POINTER targets first and the arrays that hold them second, because
  !> deallocating the array first would lose the only handle on those targets. Does
  !> nothing at all unless a previous commit set `commit_owned`: storage a legacy reader
  !> allocated is not this module's to free.
  subroutine commit_release()
    integer :: i, ig

    if (.not. commit_owned) return

    if (allocated(element)) then
      do i = 1, size(element)
        if (associated(element(i)%ldofs)) deallocate (element(i)%ldofs)
        if (associated(element(i)%field)) then
          do ig = 1, size(element(i)%field)
            if (associated(element(i)%field(ig)%lnods_f)) deallocate (element(i)%field(ig)%lnods_f)
            if (associated(element(i)%field(ig)%ldofs_f)) deallocate (element(i)%field(ig)%ldofs_f)
            if (associated(element(i)%field(ig)%elcod_f)) deallocate (element(i)%field(ig)%elcod_f)
            if (associated(element(i)%field(ig)%tload)) deallocate (element(i)%field(ig)%tload)
            if (associated(element(i)%field(ig)%eload)) deallocate (element(i)%field(ig)%eload)
            if (associated(element(i)%field(ig)%rload)) deallocate (element(i)%field(ig)%rload)
            if (associated(element(i)%field(ig)%khandmc(1)%fstif)) &
              deallocate (element(i)%field(ig)%khandmc(1)%fstif)   !@existence: element_field_khandmc_fstif
          end do
          deallocate (element(i)%field)
        end if
        if (associated(element(i)%egaus)) then
          do ig = 1, size(element(i)%egaus)
            if (associated(element(i)%egaus(ig)%djacb)) deallocate (element(i)%egaus(ig)%djacb)
            if (associated(element(i)%egaus(ig)%gpcod)) deallocate (element(i)%egaus(ig)%gpcod)
            if (associated(element(i)%egaus(ig)%cartd)) deallocate (element(i)%egaus(ig)%cartd)
          end do
          deallocate (element(i)%egaus)
        end if
      end do
      deallocate (element)
    end if

    if (allocated(group)) then
      do i = 1, size(group)
        if (associated(group(i)%list)) deallocate (group(i)%list)
        if (associated(group(i)%type_mass)) deallocate (group(i)%type_mass)   !@existence: group_type_mass
        if (associated(group(i)%order_time)) deallocate (group(i)%order_time)   !@existence: group_order_time
        if (associated(group(i)%unode)) then
          do ig = 1, size(group(i)%unode)
            if (associated(group(i)%unode(ig)%list)) deallocate (group(i)%unode(ig)%list)
          end do
          deallocate (group(i)%unode)
        end if
        ! group%dof is the SECOND two-level chain in this routine (props is the first),
        ! and it is unwound the same way: every listdof_f before the dof array that holds
        ! them, or deallocating dof loses the only handle on them. Neither the
        ! release-totality assertion nor MSan can see it if this is dropped -- the lead
        ! measured that on prescrib%leldofix, a one-level pointer that predates the fold --
        ! so a green suite says nothing about this line.
        !
        ! It is no longer unmeasured. M4-01 step 6 gave this site its own positive
        ! control: deleting this release is reported by LeakSanitizer at :927 (the
        ! `allocate` for listdof_f), the only site named, while the suite stays
        ! 1292/1292. The instrument is `tools/build.sh --profile asan`, NOT valgrind --
        ! valgrind is not installable on this host, and this comment said "valgrind exit
        ! condition" until 2026-09-09, after step 6 had already settled the question with
        ! a different tool. Six of the routine's record arrays have such a control; the
        ! other fifteen inner-release sites do not, and are not covered by it.
        if (associated(group(i)%dof)) then
          do ig = 1, size(group(i)%dof)
            if (associated(group(i)%dof(ig)%listdof_f))                                         &
              deallocate (group(i)%dof(ig)%listdof_f)
          end do
          deallocate (group(i)%dof)
        end if
      end do
      deallocate (group)
    end if

    if (allocated(listp_group)) then
      do i = 1, size(listp_group)
        if (associated(listp_group(i)%listg)) deallocate (listp_group(i)%listg)
        if (associated(listp_group(i)%listp)) deallocate (listp_group(i)%listp)
      end do
      deallocate (listp_group)
    end if

    if (allocated(prescrib)) then
      do i = 1, size(prescrib)
        if (associated(prescrib(i)%leldofix)) deallocate (prescrib(i)%leldofix)
        if (associated(prescrib(i)%levdofix)) deallocate (prescrib(i)%levdofix)
        if (associated(prescrib(i)%lefdofix)) deallocate (prescrib(i)%lefdofix)
      end do
      deallocate (prescrib)
    end if

    ! tcurves grew two pointer targets per curve in M4-01 step 4 (ttime_curve,
    ! dfact_curve), so this is no longer a bare deallocate. Note what the release-totality
    ! assertion can and cannot see here: it would catch dropping the `deallocate (tcurves)`
    ! below, because an unreleased ALLOCATABLE is still allocated afterwards -- but it
    ! would NOT catch dropping either pointer deallocate, exactly as measured for
    ! props(i)%mechanical%solid (design 5.1.3). That blind spot closes at step 6, not here.
    if (allocated(uinitial)) deallocate (uinitial)
    if (allocated(tcurves)) then
      do i = 1, size(tcurves)
        if (associated(tcurves(i)%ttime_curve)) deallocate (tcurves(i)%ttime_curve)
        if (associated(tcurves(i)%dfact_curve)) deallocate (tcurves(i)%dfact_curve)
      end do
      deallocate (tcurves)
    end if
    if (allocated(trans)) deallocate (trans)

    ! props: the two-level chain, unwound INNERMOST FIRST. Deallocating props(i)%mechanical
    ! before its %solid would lose the only handle on the solid_skeleton -- the same shape
    ! as the pointer-before-array rule this whole routine is built on, one level deeper.
    if (allocated(props)) then
      do i = 1, size(props)
        if (associated(props(i)%mechanical)) then
          if (associated(props(i)%mechanical%solid)) deallocate (props(i)%mechanical%solid)
          deallocate (props(i)%mechanical)
        end if
      end do
      deallocate (props)
    end if

    if (allocated(coord)) deallocate (coord)
    if (allocated(appear_process)) deallocate (appear_process)
    if (allocated(matno_process)) deallocate (matno_process)
    if (allocated(average_appear)) deallocate (average_appear)
    if (allocated(factg)) deallocate (factg)
    if (allocated(tcurvegravity)) deallocate (tcurvegravity)

    if (allocated(order_time_mdofn)) deallocate (order_time_mdofn)   !@existence: order_time_mdofn
    if (allocated(tension_joint)) deallocate (tension_joint)         !@existence: tension_joint
    if (allocated(modf_dis_blocks)) deallocate (modf_dis_blocks)     !@existence: modf_dis_blocks
    if (allocated(tlink)) deallocate (tlink)                         !@existence: tlink
    if (allocated(equvs_process)) deallocate (equvs_process)         !@existence: equvs_process
    if (allocated(force_process)) deallocate (force_process)         !@existence: force_process
    if (allocated(listglocbeam)) deallocate (listglocbeam)           !@existence: listglocbeam
    if (allocated(tension_contact)) deallocate (tension_contact)     !@existence: tension_contact
    if (allocated(pnorm)) deallocate (pnorm)                         !@existence: pnorm
    if (allocated(prot)) deallocate (prot)                           !@existence: prot
    if (allocated(icpnorm)) deallocate (icpnorm)                     !@existence: icpnorm
    if (allocated(lelenrt)) deallocate (lelenrt)                     !@existence: lelenrt
    if (allocated(icpspring)) deallocate (icpspring)                 !@existence: icpspring
    if (allocated(links)) deallocate (links)                         !@existence: links
    if (allocated(trans_c)) deallocate (trans_c)                     !@existence: trans_c
    if (allocated(lmdofn)) deallocate (lmdofn)
    if (allocated(lcdofn)) deallocate (lcdofn)
    if (allocated(nodfn)) deallocate (nodfn)
    if (allocated(iffix)) deallocate (iffix)
    if (allocated(fixed)) deallocate (fixed)
    if (allocated(appear)) deallocate (appear)
    if (allocated(result_zero)) deallocate (result_zero)
    if (allocated(tofor)) deallocate (tofor)
    if (allocated(stfor)) deallocate (stfor)
    if (allocated(toforl)) deallocate (toforl)
    if (allocated(toform)) deallocate (toform)
    if (allocated(delitfi)) deallocate (delitfi)
    if (allocated(deltafi)) deallocate (deltafi)
    if (allocated(line_load_block)) deallocate (line_load_block)
    if (allocated(line_temp_block)) deallocate (line_temp_block)
    if (allocated(ice0)) deallocate (ice0)

    ndofix = 0_ink
    ntcurve = 0_ink
    commit_owned = .false.
  end subroutine commit_release

  ! ==========================================================================
  ! the provenance ledger: accessors and export
  ! ==========================================================================

  !> How many snapshot rows the table declares.
  pure integer function commit_provenance_count() result(n)
    n = size(COMMIT_PROVENANCE)
  end function commit_provenance_count

  !> Row `i` of the table. `found` is .false. for an out-of-range index rather than an
  !> error, so a walker can be written as a plain loop over 1 .. count.
  pure subroutine commit_provenance_row(i, map_id, state, note, found)
    integer, intent(in) :: i
    character(len=:), allocatable, intent(out) :: map_id, note
    integer(int32), intent(out) :: state
    logical, intent(out) :: found
    map_id = ''
    note = ''
    state = COMMIT_NOT_MIGRATED
    found = .false.
    if (i < 1 .or. i > size(COMMIT_PROVENANCE)) return
    map_id = trim(COMMIT_PROVENANCE(i)%map_id)
    note = trim(COMMIT_PROVENANCE(i)%note)
    state = COMMIT_PROVENANCE(i)%state
    found = .true.
  end subroutine commit_provenance_row

  !> The declared provenance of one map row. `found` is .false. when the row is not in
  !> the table at all, which is a DIFFERENT answer from COMMIT_NOT_MIGRATED recorded
  !> deliberately -- the same distinction runtime_status_get draws for the value ledger.
  pure subroutine commit_provenance_of(map_id, state, found)
    character(len=*), intent(in) :: map_id
    integer(int32), intent(out) :: state
    logical, intent(out) :: found
    integer :: i
    state = COMMIT_NOT_MIGRATED
    found = .false.
    do i = 1, size(COMMIT_PROVENANCE)
      if (trim(COMMIT_PROVENANCE(i)%map_id) == trim(map_id)) then
        state = COMMIT_PROVENANCE(i)%state
        found = .true.
        return
      end if
    end do
  end subroutine commit_provenance_of

  !> Print the table as PROV| lines for the Python cross-check to read.
  !>
  !> This is an EXPORT, not an assertion: it makes no claim and counts towards no
  !> PASS/FAIL total, for the same reason yl_runtime_selftest's export_rule_table does.
  !> The table then exists exactly ONCE in the repository -- as the parameter array above
  !> -- and `tools/yl_state_map.py commit-provenance` parses these lines instead of
  !> keeping a second copy that can drift against it.
  subroutine commit_provenance_export(unit)
    integer, intent(in) :: unit
    integer :: i
    character(len=32) :: n
    write (n, '(i0)') size(COMMIT_PROVENANCE)
    write (unit, '(a)') 'PROVS|checkpoint=model_ready|rows='//trim(adjustl(n))
    do i = 1, size(COMMIT_PROVENANCE)
      write (unit, '(a)') 'PROV|'//trim(COMMIT_PROVENANCE(i)%map_id)//'|'//                      &
        trim(commit_provenance_state_name(COMMIT_PROVENANCE(i)%state))//'|'//                   &
        trim(COMMIT_PROVENANCE(i)%note)
    end do
  end subroutine commit_provenance_export

  !> The spelling the export uses. Kept next to the parameters so a new state cannot be
  !> added without a name -- an unnamed state would export as `?` and fail the parse
  !> rather than pass as something.
  pure function commit_provenance_state_name(state) result(name)
    integer(int32), intent(in) :: state
    character(len=:), allocatable :: name
    select case (state)
    case (COMMIT_FROM_RUNTIME); name = 'FROM_RUNTIME'
    case (COMMIT_FROM_PROBLEM); name = 'FROM_PROBLEM'
    case (COMMIT_DERIVED);      name = 'DERIVED'
    case (COMMIT_FROM_DECK);    name = 'FROM_DECK'
    case (COMMIT_SYNTHETIC);    name = 'SYNTHETIC'
    case (COMMIT_NOT_MIGRATED); name = 'NOT_MIGRATED'
    case default;               name = '?'
    end select
  end function commit_provenance_state_name

  ! ==========================================================================
  ! verification
  ! ==========================================================================

  ! INV-COMMIT-TOTAL: every row the rule table produces has a ledger entry, and the
  ! ledger entry agrees with what is actually allocated.
  !
  ! This is the check that makes the commit safe to write blind afterwards. It runs over
  ! the RULE TABLE rather than over a list kept here, so a row added to the table without
  ! a commit for it fails here instead of being committed as a silent absence.
  subroutine verify_registered(problem, residue, existence, runtime, errors, ok)
    type(problem_state_t), intent(in) :: problem
    type(deck_residue_t), intent(in) :: residue
    type(deck_existence_t), intent(in) :: existence
    type(runtime_state_t), intent(in) :: runtime
    type(problem_errors_t), intent(inout) :: errors
    logical, intent(out) :: ok

    integer :: i, j
    integer(int32) :: state
    logical :: found
    character(len=:), allocatable :: map_id

    ok = .false.

    ! The provenance ledger's own well-formedness, checked before anything else because a
    ! malformed table would make every later answer meaningless. Only the half Fortran can
    ! see is here -- non-empty ids, a nameable state, no id claimed twice. The other half
    ! ("does every emitted model_ready map row have an entry?") needs the map itself and
    ! is `tools/yl_state_map.py commit-provenance`, run from tools/build.sh against the
    ! PROV| export; see the ledger's header for why the split is where it is.
    call verify_provenance_table(errors, ok)
    if (.not. ok) return
    ok = .false.

    call verify_problem_inputs(problem, errors, ok)
    if (.not. ok) return
    ok = .false.

    call verify_residue_inputs(residue, errors, ok)
    if (.not. ok) return
    ok = .false.

    call verify_existence_inputs(existence, errors, ok)
    if (.not. ok) return
    ok = .false.

    if (runtime_status_count(runtime) /= build_rule_produced_count()) then
      call fail(errors, 'the runtime ledger holds '//itoa(runtime_status_count(runtime))//      &
                ' rows and the rule table produces '//itoa(build_rule_produced_count()))
      return
    end if

    do i = 1, build_rule_produced_count()
      map_id = build_rule_produced_map_id(i)
      call runtime_status_get(runtime, map_id, state, found)
      if (.not. found) then
        call fail(errors, 'the runtime carries no ledger entry for '//map_id)
        return
      end if
      select case (state)
      case (RUNTIME_VALUE_DEFINED, RUNTIME_VALUE_RESERVED, RUNTIME_VALUE_ABSENT)
      case default
        call fail(errors, 'the ledger entry for '//map_id//' is not a committable state')
        return
      end select
    end do

    ! The structural half: what the ledger says must match what is allocated. Only the
    ! collections the commit dereferences are named, and each is named because a wrong
    ! answer here is an unguarded dereference in the staging loops below.
    if (.not. allocated(runtime%dof%node_variables) .or.                                        &
        .not. allocated(runtime%dof%component_to_active) .or.                                   &
        .not. allocated(runtime%dof%active_to_component) .or.                                   &
        .not. allocated(runtime%dof%fixed_mask) .or.                                            &
        .not. allocated(runtime%dof%prescribed_value) .or.                                      &
        .not. allocated(runtime%dof%interpolation_count) .or.                                   &
        .not. allocated(runtime%dof%element_variables) .or.                                     &
        .not. allocated(runtime%dof%element_field_variables)) then
      call fail(errors, 'the runtime dof group is incomplete')
      return
    end if
    if (.not. allocated(runtime%element) .or. .not. allocated(runtime%gauss) .or.               &
        .not. allocated(runtime%boundary) .or. .not. allocated(runtime%amplitudes) .or.         &
        .not. allocated(runtime%topology%sections) .or.                                         &
        .not. allocated(runtime%activation%section_state)) then
      call fail(errors, 'a top-level runtime collection is not allocated')
      return
    end if
    if (size(runtime%element) < 1 .or. size(runtime%gauss) < 1 .or.                             &
        size(runtime%activation%section_state) < 1) then
      call fail(errors, 'a top-level runtime collection is empty')
      return
    end if
    if (.not. allocated(runtime%gauss(1)%stiffness%shape_gradient)) then
      call fail(errors, 'the stiffness rule carries no shape gradients')
      return
    end if
    ! W1 fix: both checks below used to look only at index 1. That made them spot checks,
    ! not invariants -- a loop-index bug that only regressed element 2, or section 2, or
    ! node 2 of some section, would sail through unexamined and get committed blind. Every
    ! element's mass rule and every node of every section is checked now, and the failure
    ! names the offending index so a regression is locatable from the message alone.
    do i = 1, size(runtime%gauss)
      if (allocated(runtime%gauss(i)%mass%shape_gradient)) then
        call fail(errors, 'the mass rule carries shape gradients for gauss('//itoa(i)//         &
                  '), which legacy never allocates for it')
        return
      end if
    end do
    if (allocated(runtime%topology%sections)) then
      do i = 1, size(runtime%topology%sections)
        if (.not. allocated(runtime%topology%sections(i)%nodes)) cycle
        do j = 1, size(runtime%topology%sections(i)%nodes)
          if (allocated(runtime%topology%sections(i)%nodes(j)%patch_nodes)) then
            call fail(errors, 'the stabilisation patch list is allocated for section('//        &
                      itoa(i)//')%nodes('//itoa(j)//'), but the ledger records it as ABSENT '// &
                      'on this path')
            return
          end if
        end do
      end do
    end if

    ok = .true.
  end subroutine verify_registered

  ! INV-COMMIT-TOTAL, ProblemState half: every ProblemState scalar the staging pass reads
  ! must actually be SET.
  !
  ! WHY THIS IS A CHECK AND NOT A FALLBACK. The staging code reads these through `opt_or`
  ! / `opt_or_real`, whose fallback is 0. That fallback is justified for the RUNTIME side
  ! -- verify_registered has already accepted the runtime, so an unset scalar there is a
  ! reported fault before staging begins -- but nothing had made the same promise about
  ! the ProblemState side, and `opt_or` cannot tell "authored as zero" from "never
  ! authored". So commit would publish a 0 for a value no deck supplied: exactly the
  ! forging deck_residue_t and the staging poison exist to prevent, in the one place
  ! neither of them can see (the poison is overwritten by the fallback, and the fallback
  ! is a legal value).
  !
  ! Found by the step-3b landing assertion: the bridge fixture never authored
  ! mesh.elements[].material, element%matno came out 0 through this fallback, and
  ! sections.material_header -- which the dump RECONSTRUCTS from element%matno -- was
  ! silently wrong. A missing input has to be a rejection, not a zero.
  !
  ! Checked here rather than at each read so the VERIFY/STAGE split holds: a rejection
  ! must happen before any staging local exists, or "a failed commit touches nothing"
  ! becomes a claim about where the return statement is.
  !
  ! "EVERY" IS ENFORCED, NOT PROMISED. The first version of this routine said "every" and
  ! covered 8 of the 13 opt_or reads and none of the allocatables -- the lead enumerated
  ! the gap and demonstrated it (drop materials[].thermal_expansion from the fixture:
  ! PASS 841/841, the unauthored value published as 0.0). A hand-kept list beside a
  ! staging pass that grows is the same defect this task has now hit nine times, so the
  ! list is no longer hand-kept: `tools/yl_state_map.py commit-inputs` extracts the
  ! ProblemState leaves the STAGING reads and the leaves THIS ROUTINE checks, and fails
  ! the build when the first is not contained in the second. Adding a read without a
  ! check is a build failure, not a review question.
  subroutine verify_problem_inputs(problem, errors, ok)
    type(problem_state_t), intent(in) :: problem
    type(problem_errors_t), intent(inout) :: errors
    logical, intent(out) :: ok
    integer :: i, k

    ok = .false.

    ! (a) the top-level collections. `size()` of an unallocated allocatable is undefined,
    ! so these come before anything that indexes them -- including the loops below.
    if (.not. allocated(problem%mesh%nodes) .or. .not. allocated(problem%mesh%elements) .or.   &
        .not. allocated(problem%mesh%elsets) .or. .not. allocated(problem%materials) .or.      &
        .not. allocated(problem%sections) .or. .not. allocated(problem%steps) .or.       &
        .not. allocated(problem%amplitudes)) then
      call fail(errors, 'a top-level ProblemState collection this commit reads is not '//      &
                'allocated (mesh.nodes, mesh.elements, mesh.elsets, materials, sections, '//   &
                'steps or amplitudes)')
      return
    end if

    ! (b) the per-entity ALLOCATABLES. Unlike an unset opt_int, reading one of these when
    ! it is unallocated is undefined behaviour rather than a silent zero -- so this half is
    ! the more dangerous of the two even though the opt_or half is the one that was found
    ! first.
    do i = 1, size(problem%mesh%nodes)
      if (.not. allocated(problem%mesh%nodes(i)%xyz)) then
        call fail(errors, 'mesh.nodes['//itoa(i)//'].xyz is not allocated'); return
      end if
    end do
    do i = 1, size(problem%mesh%elements)
      if (.not. allocated(problem%mesh%elements(i)%nodes)) then
        call fail(errors, 'mesh.elements['//itoa(i)//'].nodes is not allocated'); return
      end if
    end do
    do i = 1, size(problem%mesh%elsets)
      if (.not. allocated(problem%mesh%elsets(i)%elements)) then
        call fail(errors, 'mesh.elsets['//itoa(i)//'].elements is not allocated'); return
      end if
    end do
    ! Each amplitude's point list. `ntime` is its SIZE, so an unallocated one is both an
    ! undefined read and a published count of nothing.
    do i = 1, size(problem%amplitudes)
      if (.not. allocated(problem%amplitudes(i)%points)) then
        call fail(errors, 'amplitudes['//itoa(i)//'].points is not allocated'); return
      end if
    end do
    if (.not. allocated(problem%steps(1)%output%stress_averaging) .or.                         &
        .not. allocated(problem%steps(1)%load%gravity%direction) .or.                          &
        .not. allocated(problem%steps(1)%load%gravity%amplitude)) then
      call fail(errors, 'steps[0].output.stress_averaging, .load.gravity.direction or '//      &
                '.load.gravity.amplitude is not allocated')
      return
    end if
    ! The staging pass both SIZES itself from this collection (the record-alignment
    ! precondition) and indexes it, so an unallocated one is undefined behaviour twice over.
    if (.not. allocated(problem%steps(1)%boundary)) then
      call fail(errors, 'steps[0].boundary is not allocated'); return
    end if

    ! (c) the SCALARS, every one this module reads through an opt_* fallback. The fallback
    ! cannot tell "authored as zero" from "never authored", so each one is a place where a
    ! missing input would be published as 0 / 0.0 / ''.
    do i = 1, size(problem%mesh%elements)
      if (.not. opt_is_set(problem%mesh%elements(i)%material) .or.                            &
          .not. opt_is_set(problem%mesh%elements(i)%kind) .or.                                 &
          .not. opt_is_set(problem%mesh%elements(i)%elset)) then
        call fail(errors, 'mesh.elements['//itoa(i)//'] has an unset material, kind or '//     &
                  'elset; commit will not publish a default for a value the deck did not '//   &
                  'supply')
        return
      end if
    end do
    do k = 1, size(problem%steps)
      if (.not. allocated(problem%steps(k)%activation)) then
        call fail(errors, 'steps['//itoa(k)//'].activation is not allocated'); return
      end if
      do i = 1, size(problem%steps(k)%activation)
        if (.not. opt_is_set(problem%steps(k)%activation(i)%active) .or.                       &
            .not. opt_is_set(problem%steps(k)%activation(i)%material)) then
          call fail(errors, 'steps['//itoa(k)//'].activation['//itoa(i)//                      &
                    '] has an unset active or material')
          return
        end if
      end do
    end do
    ! The six constraint fields. `value` is the one real among them, and it is the one an
    ! unset field would publish most quietly: 0.0 is the value both golden decks carry, so
    ! an unauthored displacement and an authored zero are the same byte in the snapshot.
    do i = 1, size(problem%steps(1)%boundary)
      if (.not. opt_is_set(problem%steps(1)%boundary(i)%name) .or.                             &
          .not. opt_is_set(problem%steps(1)%boundary(i)%nset) .or.                             &
          .not. opt_is_set(problem%steps(1)%boundary(i)%dof) .or.                              &
          .not. opt_is_set(problem%steps(1)%boundary(i)%value) .or.                            &
          .not. opt_is_set(problem%steps(1)%boundary(i)%amplitude) .or.                        &
          .not. opt_is_set(problem%steps(1)%boundary(i)%record_reaction)) then
        call fail(errors, 'steps[0].boundary['//itoa(i)//'] has an unset field this '//        &
                  'commit reads (name, nset, dof, value, amplitude or record_reaction)')
        return
      end if
    end do
    do i = 1, size(problem%amplitudes)
      if (.not. opt_is_set(problem%amplitudes(i)%type)) then
        call fail(errors, 'amplitudes['//itoa(i)//'].type is not set'); return
      end if
      do k = 1, size(problem%amplitudes(i)%points)
        if (.not. opt_is_set(problem%amplitudes(i)%points(k)%time) .or.                        &
            .not. opt_is_set(problem%amplitudes(i)%points(k)%value)) then
          call fail(errors, 'amplitudes['//itoa(i)//'].points['//itoa(k)//                     &
                    '] has an unset time or value')
          return
        end if
      end do
    end do
    do i = 1, size(problem%sections)
      if (.not. opt_is_set(problem%sections(i)%material) .or.                                  &
          .not. opt_is_set(problem%sections(i)%thickness) .or.                                 &
          .not. opt_is_set(problem%sections(i)%name) .or.                                      &
          .not. opt_is_set(problem%sections(i)%element) .or.                                   &
          .not. opt_is_set(problem%sections(i)%class) .or.                                     &
          .not. opt_is_set(problem%sections(i)%fields) .or.                                    &
          .not. opt_is_set(problem%sections(i)%formulation) .or.                               &
          .not. opt_is_set(problem%sections(i)%special) .or.                                   &
          .not. opt_is_set(problem%sections(i)%element_kind) .or.                              &
          .not. opt_is_set(problem%sections(i)%layer) .or.                                     &
          .not. opt_is_set(problem%sections(i)%liquefaction) .or.                              &
          .not. opt_is_set(problem%sections(i)%uplift) .or.                                    &
          .not. opt_is_set(problem%sections(i)%algorithm) .or.                                 &
          .not. opt_is_set(problem%sections(i)%stiffness_kind) .or.                            &
          .not. opt_is_set(problem%sections(i)%stress_recovery) .or.                           &
          .not. opt_is_set(problem%sections(i)%local_axes)) then
        call fail(errors, 'sections['//itoa(i)//'] has an unset field this commit reads '//    &
                  '(material, thickness, name, element, class, fields, formulation, '//        &
                  'special, element_kind, layer, liquefaction, uplift, algorithm, '//          &
                  'stiffness_kind, stress_recovery or local_axes)')
        return
      end if
    end do
    ! The C2 scalars (step 5b). Every one is read through an opt_* fallback in staging, so
    ! every one has to be here or commit publishes a default for a value no deck supplied.
    if (.not. opt_is_set(problem%case%name) .or.                                              &
        .not. opt_is_set(problem%solver%linear) .or.                                          &
        .not. opt_is_set(problem%solver%symmetric) .or.                                       &
        .not. opt_is_set(problem%interactions%absorbing%type) .or.                            &
        .not. opt_is_set(problem%steps(1)%procedure) .or.                                     &
        .not. opt_is_set(problem%steps(1)%load_mode) .or.                                     &
        .not. opt_is_set(problem%steps(1)%output%format) .or.                                 &
        .not. opt_is_set(problem%steps(1)%controls%nonlinear_type) .or.                       &
        .not. opt_is_set(problem%steps(1)%load%gravity%enabled) .or.                          &
        .not. opt_is_set(problem%steps(1)%load%gravity%magnitude)) then
      call fail(errors, 'an unset top-level control this commit reads (case.name, '//         &
                'solver.linear, solver.symmetric, interactions.absorbing.type, '//            &
                'steps[0].procedure, .load_mode, .output.format, '//                          &
                '.controls.nonlinear_type, .load.gravity.enabled or .magnitude)')
      return
    end if
    ! The 20 GiD switches, named individually for the same reason they are staged
    ! individually: a list that silently covers 19 of 20 is this task's signature defect.
    if (.not. opt_is_set(problem%steps(1)%output%field%u) .or.                                &
        .not. opt_is_set(problem%steps(1)%output%field%s) .or.                                &
        .not. opt_is_set(problem%steps(1)%output%field%ms) .or.                               &
        .not. opt_is_set(problem%steps(1)%output%field%f) .or.                                &
        .not. opt_is_set(problem%steps(1)%output%field%rot) .or.                              &
        .not. opt_is_set(problem%steps(1)%output%field%v) .or.                                &
        .not. opt_is_set(problem%steps(1)%output%field%a) .or.                                &
        .not. opt_is_set(problem%steps(1)%output%field%T) .or.                                &
        .not. opt_is_set(problem%steps(1)%output%field%P) .or.                                &
        .not. opt_is_set(problem%steps(1)%output%field%Pv) .or.                               &
        .not. opt_is_set(problem%steps(1)%output%field%ep) .or.                               &
        .not. opt_is_set(problem%steps(1)%output%field%Y) .or.                                &
        .not. opt_is_set(problem%steps(1)%output%field%FC) .or.                               &
        .not. opt_is_set(problem%steps(1)%output%field%Ns) .or.                               &
        .not. opt_is_set(problem%steps(1)%output%field%Ss) .or.                               &
        .not. opt_is_set(problem%steps(1)%output%field%Mxy) .or.                              &
        .not. opt_is_set(problem%steps(1)%output%field%bem) .or.                              &
        .not. opt_is_set(problem%steps(1)%output%field%wh) .or.                               &
        .not. opt_is_set(problem%steps(1)%output%field%wv) .or.                               &
        .not. opt_is_set(problem%steps(1)%output%field%bcs)) then
      call fail(errors, 'steps[0].output.field has an unset GiD switch; all 20 are read '//   &
                'by the staging pass')
      return
    end if
    if (.not. allocated(problem%mesh%nsets)) then
      call fail(errors, 'mesh.nsets is not allocated; nfixsets is its cardinality'); return
    end if

    do i = 1, size(problem%materials)
      if (.not. opt_is_set(problem%materials(i)%E) .or.                                        &
          .not. opt_is_set(problem%materials(i)%nu) .or.                                       &
          .not. opt_is_set(problem%materials(i)%density) .or.                                  &
          .not. opt_is_set(problem%materials(i)%thermal_expansion) .or.                        &
          .not. opt_is_set(problem%materials(i)%solid_ratio) .or.                              &
          .not. opt_is_set(problem%materials(i)%creep_model) .or.                              &
          .not. opt_is_set(problem%materials(i)%liquefaction) .or.                             &
          .not. opt_is_set(problem%materials(i)%wetting_kind) .or.                             &
          .not. opt_is_set(problem%materials(i)%name) .or.                                     &
          .not. opt_is_set(problem%materials(i)%model)) then
        call fail(errors, 'materials['//itoa(i)//'] has an unset E, nu, density, '//           &
                  'thermal_expansion, solid_ratio, creep_model, liquefaction, '//              &
                  'wetting_kind, name or model')
        return
      end if
    end do
    ok = .true.
  end subroutine verify_problem_inputs

  ! INV-COMMIT-TOTAL, residue CROSS-CHECK: the carried value must agree with the gate that
  ! let the deck through.
  !
  ! The adapter refuses every one of these unless it holds the value named below, so by
  ! the time commit runs there are TWO independent statements about each: what the gate
  ! proved, and what the carrier says the deck actually held. This asserts they agree.
  ! That is deliberately stronger than deriving one from the other -- v3 of the design
  ! proposed writing the gate's value as a constant and the lead overruled it, because a
  ! constant makes the two indistinguishable and a disagreement then has nowhere to show
  ! (L2c-fold-design.md 1.6.2). A mismatch here means the adapter's gate and its carrier
  ! have drifted apart, which is a defect in this repository, not an unusual deck.
  !
  ! WHAT IS NOT CROSS-CHECKED, and why, because a list that quietly covers less than it
  ! claims is this task's most-repeated defect:
  !   * `stab_matde` has an INTERVAL for a gate (`> nblks` disables), not a value, so the
  !     check is that it lands in the admitted interval -- 1.6.3.
  !   * `npoinb`, `nsmat` and `delgroup` have NO gate at all: the adapter reads them and
  !     discards them (1.7.1's table). There is nothing to agree with, and inventing an
  !     expectation here would be exactly the "second source of truth" the carrier exists
  !     to avoid. They are carried unchecked, and that is the honest state.
  !   * `runblks` is gated to 1, not 0.
  subroutine verify_residue_against_gates(residue, errors, ok)
    type(deck_residue_t), intent(in) :: residue
    type(problem_errors_t), intent(inout) :: errors
    logical, intent(out) :: ok

    ok = .false.

    if (opt_or(residue%restart) /= 0 .or. opt_or(residue%relis) /= 0 .or.                     &
        opt_or(residue%adina) /= 0) then
      call fail(errors, 'the deck residue carries a non-zero restart, relis or adina, '//     &
                'but the adapter rejects any deck that does (F1); the gate and the '//        &
                'carrier disagree')
      return
    end if
    if (opt_or(residue%runblks) /= 1) then
      call fail(errors, 'the deck residue carries runblks /= 1, but the adapter rejects '//   &
                'any deck that does; the gate and the carrier disagree')
      return
    end if
    if (opt_or(residue%ninit) /= 0 .or. opt_or(residue%nlinks) /= 0 .or.                      &
        opt_or(residue%block_stab) /= 0 .or. opt_or(residue%nbackf) /= 0 .or.                 &
        opt_or(residue%ebody) /= 0 .or. opt_or(residue%nlayer) /= 0 .or.                      &
        opt_or(residue%state_change) /= 0 .or. opt_or(residue%bparameter) /= 0 .or.           &
        opt_or(residue%ntrans) /= 0) then
      call fail(errors, 'the deck residue carries a non-zero .glb control value (ninit, '//   &
                'nlinks, block_stab, nbackf, ebody, nlayer, state_change, bparameter or '//   &
                'ntrans), but the adapter rejects any deck that does; the gate and the '//    &
                'carrier disagree')
      return
    end if
    if (any(residue%uinitial /= 0_int32)) then
      call fail(errors, 'the deck residue carries a non-zero uinitial, but the adapter '//    &
                'rejects any deck that does; the gate and the carrier disagree')
      return
    end if
    if (opt_or(residue%nplgroup) /= 0 .or. opt_or(residue%nedge) /= 0 .or.                    &
        opt_or(residue%edge_load_group) /= 0 .or. opt_or(residue%nbeamload) /= 0 .or.         &
        opt_or(residue%nplateload) /= 0) then
      call fail(errors, 'the deck residue carries a non-zero .loa count (nplgroup, nedge, '// &
                'edge_load_group, nbeamload or nplateload), but the adapter rejects any '//   &
                'deck that does; the gate and the carrier disagree')
      return
    end if
    if (opt_or(residue%ntemp_surface) /= 0 .or. opt_or(residue%ntedge) /= 0 .or.              &
        opt_or(residue%ntelgroup) /= 0 .or. opt_or(residue%npipe) /= 0) then
      call fail(errors, 'the deck residue carries a non-zero .tem count (ntemp_surface, '//   &
                'ntedge, ntelgroup or npipe), but the adapter rejects any deck that does '//  &
                '(A12..A15); the gate and the carrier disagree')
      return
    end if
    ! An interval, not a value: stab_matde > nblks is what disables it, and a compliant
    ! third deck could carry 5 where both goldens carry 99999.
    if (opt_or(residue%stab_matde) <= int(size_of_blocks(residue))) then
      call fail(errors, 'the deck residue carries stab_matde inside the range the '//         &
                'adapter rejects; the gate and the carrier disagree')
      return
    end if

    ok = .true.
  end subroutine verify_residue_against_gates

  !> nblks as the carrier itself implies it: uinitial is [nblks] long by construction.
  !> Used only by the stab_matde interval check, and taken from the carrier rather than
  !> from ProblemState so that the cross-check compares the gate against the CARRIER
  !> alone, without a third object joining in.
  pure integer function size_of_blocks(residue) result(n)
    type(deck_residue_t), intent(in) :: residue
    n = 0
    if (allocated(residue%uinitial)) n = size(residue%uinitial)
  end function size_of_blocks

  ! INV-COMMIT-TOTAL, residue half: every component of the carrier must be SET.
  !
  ! WHY THIS EXISTS BEFORE COMMIT READS A SINGLE ONE OF THEM. The defect fixed in 4b3ff7d
  ! -- a checker whose header said "every" and covered 8 of 13 -- was not a fact about
  ! ProblemState. It is a fact about any input read through an `opt_*` fallback: the
  ! fallback cannot tell "the deck said 0" from "no parser filled this", and those two are
  ! exactly what deck_residue_t exists to keep apart (see its module header). Writing the
  ! guard after the first read would repeat the same mistake on a second surface, so it
  ! goes up first and `tools/yl_state_map.py commit-inputs` now checks containment on BOTH
  ! surfaces rather than only the original one.
  !
  ! THE LIST IS NOT WRITTEN OUT HERE EITHER. Every component is checked by walking the
  ! type, one `opt_is_set` per line in declaration order, so a component added to
  ! deck_residue_t and forgotten here is a gap this file makes visible rather than one
  ! that hides behind "every". The carrier's own bijection gate (P11) is what keeps that
  ! type in step with the map, so the two together are the closed loop: map -> type ->
  ! this check -> commit.
  subroutine verify_residue_inputs(residue, errors, ok)
    type(deck_residue_t), intent(in) :: residue
    type(problem_errors_t), intent(inout) :: errors
    logical, intent(out) :: ok

    ok = .false.

    ! uinitial is the one allocatable: unallocated is undefined behaviour on read, not a
    ! silent zero, so it is checked as a separate condition from the 26 scalars.
    if (.not. allocated(residue%uinitial)) then
      call fail(errors, 'the deck residue carries no uinitial; it is an allocatable and '//   &
                'reading it unallocated is undefined, not a default')
      return
    end if

    if (.not. opt_is_set(residue%block_stab) .or.                                             &
        .not. opt_is_set(residue%bparameter) .or.                                             &
        .not. opt_is_set(residue%ebody) .or.                                                  &
        .not. opt_is_set(residue%nbackf) .or.                                                 &
        .not. opt_is_set(residue%ninit) .or.                                                  &
        .not. opt_is_set(residue%nlayer) .or.                                                 &
        .not. opt_is_set(residue%nlinks) .or.                                                 &
        .not. opt_is_set(residue%ntrans) .or.                                                 &
        .not. opt_is_set(residue%stab_matde) .or.                                             &
        .not. opt_is_set(residue%state_change) .or.                                           &
        .not. opt_is_set(residue%adina) .or.                                                  &
        .not. opt_is_set(residue%relis) .or.                                                  &
        .not. opt_is_set(residue%restart)) then
      call fail(errors, 'the deck residue has an unset control value (block_stab, '//         &
                'bparameter, ebody, nbackf, ninit, nlayer, nlinks, ntrans, stab_matde, '//    &
                'state_change, adina, relis or restart); commit will not publish a '//        &
                'default for a value no parser supplied')
      return
    end if

    if (.not. opt_is_set(residue%delgroup) .or.                                               &
        .not. opt_is_set(residue%edge_load_group) .or.                                        &
        .not. opt_is_set(residue%nbeamload) .or.                                              &
        .not. opt_is_set(residue%nedge) .or.                                                  &
        .not. opt_is_set(residue%npipe) .or.                                                  &
        .not. opt_is_set(residue%nplateload) .or.                                             &
        .not. opt_is_set(residue%nplgroup) .or.                                               &
        .not. opt_is_set(residue%npoinb) .or.                                                 &
        .not. opt_is_set(residue%nsmat) .or.                                                  &
        .not. opt_is_set(residue%ntedge) .or.                                                 &
        .not. opt_is_set(residue%ntelgroup) .or.                                              &
        .not. opt_is_set(residue%ntemp_surface) .or.                                          &
        .not. opt_is_set(residue%runblks)) then
      call fail(errors, 'the deck residue has an unset count (delgroup, edge_load_group, '//  &
                'nbeamload, nedge, npipe, nplateload, nplgroup, npoinb, nsmat, ntedge, '//    &
                'ntelgroup, ntemp_surface or runblks); commit will not publish a default '//  &
                'for a value no parser supplied')
      return
    end if

    ok = .true.
  end subroutine verify_residue_inputs

  !> Every existence-face component must be allocated before the staging pass reads it.
  !>
  !> Same rule and same reason as verify_residue_inputs: an unallocated component means
  !> "the parser never ran", and staging an empty array for it would publish a zero-length
  !> legacy global that reads exactly like a deck whose record was empty. ADR-0002's
  !> three-state absence discipline applies here even though these values are never
  !> compared -- "nothing observes it" is not "anything will do".
  subroutine verify_existence_inputs(existence, errors, ok)
    type(deck_existence_t), intent(in) :: existence
    type(problem_errors_t), intent(inout) :: errors
    logical, intent(out) :: ok
    ok = .false.
    if (.not. allocated(existence%order_time_mdofn)) then
      call fail(errors, 'existence face: order_time_mdofn is not allocated -- the .glb '//   &
                'parser did not run, and committing an empty array would publish a legacy '// &
                'global that reads like a deck record nobody wrote')
      return
    end if
    if (.not. allocated(existence%tlink)) then
      call fail(errors, 'runtime state manifest: tlink is not allocated -- see above')
      return
    end if
    if (.not. allocated(existence%equvs_process)) then
      call fail(errors, 'runtime state manifest: equvs_process is not allocated')
      return
    end if
    if (.not. allocated(existence%force_process)) then
      call fail(errors, 'runtime state manifest: force_process is not allocated')
      return
    end if
    if (.not. allocated(existence%modf_dis_blocks)) then
      call fail(errors, 'existence face: modf_dis_blocks is not allocated -- see above')
      return
    end if
    if (.not. allocated(existence%group_type_mass)) then
      call fail(errors, 'runtime state manifest: group_type_mass is not allocated')
      return
    end if
    if (.not. allocated(existence%group_order_time)) then
      call fail(errors, 'existence face: group_order_time is not allocated -- see above')
      return
    end if
    if (.not. allocated(existence%tension_joint)) then
      call fail(errors, 'existence face: tension_joint is not allocated -- see above; the '// &
                'same rule applies to every row of the face')
      return
    end if
    ok = .true.
  end subroutine verify_existence_inputs

  ! INV-COMMIT-TOTAL, provenance half: the table above must be well formed. An entry with
  ! an empty id names no row; an entry with an unnameable state exports as `?` and would
  ! fail the Python parse rather than the commit, which is later and further from the
  ! cause; two entries claiming one row means the ledger answers one question twice and
  ! `commit_provenance_of` silently keeps the first. None of the three is reachable today,
  ! and all three are checked anyway -- the same discipline as check_bijection asserting a
  ! forward half that is true by construction, because an assertion that cannot fail is
  ! cheaper than the review that would otherwise have to notice.
  subroutine verify_provenance_table(errors, ok)
    type(problem_errors_t), intent(inout) :: errors
    logical, intent(out) :: ok
    integer :: i, j

    ok = .false.
    if (size(COMMIT_PROVENANCE) < 1) then
      call fail(errors, 'the provenance ledger is empty')
      return
    end if
    do i = 1, size(COMMIT_PROVENANCE)
      if (len_trim(COMMIT_PROVENANCE(i)%map_id) == 0) then
        call fail(errors, 'provenance entry '//itoa(i)//' names no map row')
        return
      end if
      if (commit_provenance_state_name(COMMIT_PROVENANCE(i)%state) == '?') then
        call fail(errors, 'the provenance entry for '//trim(COMMIT_PROVENANCE(i)%map_id)//     &
                  ' carries a state with no exported name')
        return
      end if
      do j = i + 1, size(COMMIT_PROVENANCE)
        if (trim(COMMIT_PROVENANCE(i)%map_id) == trim(COMMIT_PROVENANCE(j)%map_id)) then
          call fail(errors, 'the provenance ledger claims '//                                  &
                    trim(COMMIT_PROVENANCE(i)%map_id)//' twice, at entries '//itoa(i)//        &
                    ' and '//itoa(j))
          return
        end if
      end do
    end do
    ok = .true.
  end subroutine verify_provenance_table

  ! ==========================================================================
  ! nulling helpers
  ! ==========================================================================
  !
  ! A staged legacy record is nulled component by component before anything is allocated
  ! into it. Default initialisation would do this if the legacy types had any; they do
  ! not, so a staged record would otherwise start with undefined pointer components and
  ! `associated()` on one of those is undefined behaviour -- including inside
  ! commit_release, which is the last place that may be uncertain.
  !
  ! Nulling is EXHAUSTIVE, not limited to the components this module itself sets or the
  ! releaser tests. It costs nothing (a null pointer claims no storage and no ownership)
  ! and it must cover every pointer component because this module hands the whole record
  ! on to code it does not control -- yl_state_dump.f90 already calls `associated()` on
  ! several element components this module never touches, and nothing here can promise
  ! that is the last such reader. "the ones we use" would be an ownership boundary this
  ! module cannot enforce; nulling everything sidesteps the question.
  !
  ! Each subroutine below is checked against the legacy type's own pointer declarations
  ! and states the count, so a legacy type gaining a new pointer component shows up as a
  ! mismatch the next time this file is touched rather than as a silent gap.

  ! element_lib (Elements.f90:94-119): 15 `pointer` declaration lines, 25 pointer
  ! components.
  subroutine null_element(e)
    type(element_lib), intent(inout) :: e
    nullify (e%list_ne_include, e%point_direct)
    nullify (e%estif, e%mmat, e%gstif, e%rotation, e%stres0, e%evk)
    nullify (e%gmatx, e%qmatxa, e%rh, e%alfa, e%estift, e%estifh, e%djacb_dd)
    nullify (e%alfa_it, e%alfa_first, e%alfa_second, e%indx)
    nullify (e%aera_local, e%ldofs, e%field, e%egaus, e%cstif, e%strainx0)
  end subroutine null_element

  ! element_field (Elements.f90:62-92): 20 `pointer` declaration lines with live code (a
  ! 21st, `gpvar_s`, is commented out in the legacy source and is not a real component),
  ! 41 pointer components.
  !
  ! khandmc(2) is a FIXED-size array of type(stiff_field) -- not itself a pointer
  ! component of element_field -- but it comes into existence the instant `field(1)` is
  ! allocated, and stiff_field's own two pointers (fstif, hstar; Elements.f90:52-54) are
  ! then exactly as undefined as anything else nulled here, for the same reason. Nulled
  ! too, so nothing reachable from a staged field(1) is left indeterminate.
  subroutine null_element_field(f)
    type(element_field), intent(inout) :: f
    nullify (f%lnods_f, f%lnods, f%ldofs_f, f%icftcontact, f%isatu)
    nullify (f%elcod_f, f%gpvar0, f%sigz, f%gpvar, f%dmatxd)
    nullify (f%bmatx, f%gamamax, f%gamamax0, f%gamamax_ini, f%gamamax_error)
    nullify (f%relat_dis_nod0, f%relat_dis_nod, f%relat_dis_gaus0, f%relat_dis_gaus)
    nullify (f%strain0, f%strain, f%kdiag, f%vkstrain0, f%vkstrain)
    nullify (f%gapg0, f%gapg, f%gapn0, f%gapn, f%ntstress, f%natural_thickness)
    nullify (f%state, f%state0, f%state1)
    nullify (f%omega, f%dsig, f%stran0, f%rr, f%stran0_s)
    nullify (f%tload, f%eload, f%rload)
    nullify (f%khandmc(1)%fstif, f%khandmc(1)%hstar)
    nullify (f%khandmc(2)%fstif, f%khandmc(2)%hstar)
  end subroutine null_element_field

  ! gauss_element (Elements.f90:20-28): 5 `pointer` declaration lines, 15 pointer
  ! components.
  subroutine null_gauss(g)
    type(gauss_element), intent(inout) :: g
    nullify (g%gpcod, g%djacb, g%cartd, g%bbar, g%shapwxy)
    nullify (g%pwatr, g%permr, g%satur, g%csmos, g%poros, g%voide)
    nullify (g%iload, g%iload0, g%vdval, g%vdval0)
  end subroutine null_gauss

  ! group_of_elements (Global.f90:234-261): 8 `pointer` declaration lines, 10 pointer
  ! components. water_pipe, temp_pre and dof point at other record types this module
  ! never populates -- the pointer still must be nulled, because an unset bit pattern
  ! there is exactly the same undefined `associated()` hazard as any other component.
  ! The `g%np_unode = 0_ink` this routine used to carry moved to poison_group: zeroing an
  ! assigned scalar here MASKS a deleted assignment, which is exactly the defect the
  ! STAGE_POISON note describes. Nulling stays about pointers only.
  subroutine null_group(g)
    type(group_of_elements), intent(inout) :: g
    nullify (g%type_mass, g%order_time, g%list, g%belem, g%unode)
    nullify (g%water_pipe, g%temp_pre, g%lcgroup, g%valun, g%dof)
  end subroutine null_group

  ! unode_elements (Global.f90:263-271): 3 `pointer` declaration lines, 4 pointer
  ! components.
  ! The three scalar zeroings this routine used to carry moved to poison_unode, for the
  ! reason given above null_group. `np_unode` in particular was zeroed here AND assigned 0
  ! in the staging loop, so deleting the staging line changed nothing observable -- the
  ! measured blind spot of docs/m4/L2c-fold-design.md §5.5.1.
  subroutine null_unode(u)
    type(unode_elements), intent(inout) :: u
    nullify (u%list, u%patch_nod, u%patch_sta, u%patch_load)
  end subroutine null_unode

  ! freedom_prescribe (Prescrib.f90:14-35): 9 `pointer` declaration lines, 9 pointer
  ! components.
  subroutine null_prescrib(p)
    type(freedom_prescribe), intent(inout) :: p
    nullify (p%leldofix, p%levdofix, p%lefdofix, p%listep, p%value_ext,                         &
             p%ldofixb, p%lnofixb, p%mlist, p%rintf)
  end subroutine null_prescrib

  ! time_curve (Load.f90:20-32): 12 `pointer` declaration lines, 24 pointer components.
  subroutine null_tcurve(c)
    type(time_curve), intent(inout) :: c
    nullify (c%dtrec, c%dtend, c%dtbegin, c%ample, c%ttime_curve, c%dfact_curve,                &
             c%time_begin, c%detal, c%fact_inc, c%a0sin, c%asin, c%wsin, c%w0sin,               &
             c%dx, c%Ca, c%AI, c%omega, c%nalgo, c%ncdis, c%piter, c%giter, c%Nextr,            &
             c%NFS, c%order_stoch_parameter)
  end subroutine null_tcurve

  ! solid_skeleton (Material.f90): 18 `pointer` declaration lines beyond the two nulled on
  ! mechanical_property itself. Nulled for the same reason as every other legacy record
  ! here -- the type has no default initialisation, so `associated()` on an unset component
  ! is undefined, and yl_state_dump reaches into props(i)%mechanical%solid.
  subroutine null_solid(sk)
    type(solid_skeleton), intent(inout) :: sk
    nullify (sk%normalstress, sk%normale, sk%gap_define)
    nullify (sk%ClassicalEP, sk%CamClay, sk%SoilPZ, sk%Concrete, sk%DuncanChang)
    nullify (sk%Goodman, sk%creep, sk%Elastic_Spring, sk%Elastic_ep, sk%Plane_lowft)
    nullify (sk%steel_ep, sk%steel_sp, sk%wetting_def, sk%SandPZ, sk%ClayPZ, sk%scycl)
  end subroutine null_solid

  ! ==========================================================================
  ! poisoning helpers
  ! ==========================================================================
  !
  ! The counterpart of the null_ family, and the split between them is the point: null_
  ! answers "who owns this storage" and covers every POINTER component exhaustively;
  ! poison_ answers "did anyone actually write this" and covers exactly the NON-pointer
  ! components this module ASSIGNS. Neither set is a subset of the other and neither may
  ! be widened to the union:
  !
  !   * nulling a pointer this module never touches costs nothing (a null pointer claims
  !     no storage), which is why null_ is exhaustive;
  !   * poisoning a scalar this module never assigns PUBLISHES A SENTINEL into a legacy
  !     record, which is rule 1 of the STAGE_POISON note. So poison_ is exact, and each
  !     routine below names the assignment site that justifies every component it covers.
  !
  ! Called immediately after the matching null_ and before any real assignment. A legacy
  ! type gaining a component therefore shows up as a gap in whichever family should have
  ! covered it, rather than in neither.

  ! group_of_elements: 1 component, `np_unode`, assigned in the section-record loop
  ! (`s_group(ig)%np_unode = int(n, ink)`). Every other non-pointer component of this type
  ! belongs to the ProblemState half and is not assigned here yet -- M4-01 adds them, and
  ! each addition belongs in this routine on the same commit.
  ! group_of_elements: 2 components. `np_unode` is assigned in the section-record loop;
  ! `nelgroup` arrived with step 3b and is the count yl_state_adapters checks BEFORE it
  ! looks at anything else, so an unassigned one aborts the dump rather than mis-sizing a
  ! read. Every other non-pointer component of this type is still the ProblemState half's
  ! and is not assigned here yet -- each addition belongs in this routine on the same
  ! commit that adds its assignment.
  subroutine poison_group(g)
    type(group_of_elements), intent(inout) :: g
    g%np_unode = STAGE_POISON_I
    g%nelgroup = STAGE_POISON_I
    g%nrfields = STAGE_POISON_I
    g%nstre = STAGE_POISON_I
    ! The 15 section header fields (step 4). Characters get '' rather than a numeric
    ! sentinel -- there is no integer to put in a character(2) -- so for those the
    ! detection of a missing write is the bridge test's trim() comparison, not the value
    ! itself. Stated here because it is the one place the poison is weaker than elsewhere.
    g%index = STAGE_POISON_I
    g%matno = STAGE_POISON_I
    g%ilayer = STAGE_POISON_I
    g%liquj = STAGE_POISON_I
    g%uplift_ic = STAGE_POISON_I
    g%type_nalgo = STAGE_POISON_I
    g%type_stiff = STAGE_POISON_I
    g%type_ecoint = STAGE_POISON_I
    g%elcod_local = STAGE_POISON_R
    g%kname = ''
    g%name = ''
    g%class = ''
    g%fieldid = ''
    g%sptype = ''
    g%special = ''
  end subroutine poison_group

  ! time_curve: 3 non-pointer components assigned in the amplitude-record loop -- `dfact`
  ! from the runtime, `ntime` and `type_curve` from ProblemState (M4-01 step 4).
  ! `nstoch_curve` is NOT assigned and so is NOT poisoned; its map row is not emitted at
  ! model_ready. `type_curve` gets '' for the reason poison_group states: there is no
  ! integer sentinel for a character(20), so a missing write to it is caught by the bridge
  ! test's trim() comparison rather than by the sentinel. The pointer components, including
  ! the two this step allocates, belong to null_tcurve and must not appear here.
  subroutine poison_tcurve(c)
    type(time_curve), intent(inout) :: c
    c%dfact = STAGE_POISON_R
    c%ntime = STAGE_POISON_I
    c%type_curve = ''
  end subroutine poison_tcurve

  ! element_lib: 3 components assigned in the element-record loop -- `matno` since step 3b,
  ! `index` and `group` since step 4. The type's other scalars (nstre, nrfields,
  ! ne_include, jblks, ktotg, icbound, neqcy, area, minedge, elength) are not assigned here
  ! and so are not poisoned; none of their map rows is emitted at model_ready.
  subroutine poison_element(e)
    type(element_lib), intent(inout) :: e
    e%matno = STAGE_POISON_I
    e%index = STAGE_POISON_I
    e%group = STAGE_POISON_I
  end subroutine poison_element

  ! unode_elements: 3 components. `ipoin` and `ne_unode` are assigned from the runtime;
  ! `np_unode` is assigned the literal 0 because the ledger calls it ABSENT on this path,
  ! and it is poisoned exactly so that "assigned 0 deliberately" stays distinguishable
  ! from "never assigned". `patch_nod`/`patch_sta`/`patch_load` are pointers -- null_unode
  ! owns them, and they must NOT appear here.
  subroutine poison_unode(u)
    type(unode_elements), intent(inout) :: u
    u%ipoin = STAGE_POISON_I
    u%ne_unode = STAGE_POISON_I
    u%np_unode = STAGE_POISON_I
  end subroutine poison_unode

  ! freedom_prescribe: 8 components, all assigned in the prescription-record loop --
  ! `ldofix` and `lnefix` from the runtime, and `ifixset`, `nodfix`, `ifixvar`, `itcurve`,
  ! `outfix`, `vdofix` from ProblemState (M4-01 step 4).
  ! The type's remaining scalars (mfixset, ifixvar0, jfixvar, gamaw, rdofix, bfrecoord) are
  ! NOT assigned here and are deliberately NOT poisoned: their map rows are not emitted at
  ! model_ready, so a sentinel in them would reach a global for no reader's benefit. Rule 1
  ! of the STAGE_POISON note -- poison covers exactly the assigned set.
  subroutine poison_prescrib(p)
    type(freedom_prescribe), intent(inout) :: p
    p%ldofix = STAGE_POISON_I
    p%lnefix = STAGE_POISON_I
    p%ifixset = STAGE_POISON_I
    p%nodfix = STAGE_POISON_I
    p%ifixvar = STAGE_POISON_I
    p%itcurve = STAGE_POISON_I
    p%outfix = STAGE_POISON_I
    p%vdofix = STAGE_POISON_R
  end subroutine poison_prescrib

  ! solid_skeleton: the 10 non-pointer components this module assigns. `thickness` is
  ! assigned in a SECOND pass (section -> material), so poisoning it here is what makes a
  ! material no section points at show up as a sentinel rather than as a plausible 0.
  subroutine poison_solid(sk)
    type(solid_skeleton), intent(inout) :: sk
    sk%e = STAGE_POISON_R
    sk%nu = STAGE_POISON_R
    sk%density = STAGE_POISON_R
    sk%alfa = STAGE_POISON_R
    sk%ratio = STAGE_POISON_R
    sk%thickness = STAGE_POISON_R
    sk%icreep = STAGE_POISON_I
    sk%jliqu = STAGE_POISON_I
    sk%kind_wt = STAGE_POISON_I
    sk%material = ''
  end subroutine poison_solid

  ! ==========================================================================
  ! small helpers
  ! ==========================================================================

  ! Every rejection this module can raise is the one rule row INV-COMMIT-TOTAL, and its
  ! identity is read OUT OF THE RULE TABLE rather than spelled here: the finding must
  ! carry the composed key `<rule_id>/<condition>` that build_rule_exercised matches on,
  ! and the row's own object path and field. Spelling the bare family id here is exactly
  ! the drift that made the M3-03 build rules invisible to their own coverage walk; see
  ! the raise_row header in yl_runtime_build.f90 for the full account.
  subroutine fail(errors, message)
    type(problem_errors_t), intent(inout) :: errors
    character(len=*), intent(in) :: message
    type(problem_error_t) :: finding
    type(build_rule_t) :: row
    logical :: found
    integer :: i, k

    i = 0
    do k = 1, build_rule_count()
      call build_rule_row(k, row, found)
      if (.not. found) cycle
      if (trim(row%rule_id) == 'INV-COMMIT-TOTAL') then
        i = k
        exit
      end if
    end do
    if (i == 0) then
      ! The commit's own rule row has gone from the table. Reported as itself rather
      ! than silently degraded, because a rejection nothing can attribute is worse than
      ! a loud one.
      finding = make_problem_error(PE_INTERNAL, PE_STAGE_BUILD, 'INV-COMMIT-TOTAL', 'runtime',  &
                                   field='*', message='the rule table no longer declares '//    &
                                   'INV-COMMIT-TOTAL; original finding: '//message,             &
                                   exit_class=PE_EXIT_INTERNAL)
      call errors%add(finding)
      return
    end if
    finding = make_problem_error(trim(row%code), PE_STAGE_BUILD, build_rule_key(i),             &
                                 trim(row%object_path), field=trim(row%field),                  &
                                 message=message)
    call errors%add(finding)
  end subroutine fail

  ! The value of an opt_int, or 0 when it is unset. The commit only reaches these after
  ! verify_registered accepted the runtime, so an unset scalar here would already be a
  ! reported fault; the fallback exists so the staging loops have no branch.
  pure integer(int32) function opt_or(x) result(v)
    type(opt_int), intent(in) :: x
    logical :: found
    call opt_get(x, v, found)
    if (.not. found) v = 0_int32
  end function opt_or

  ! The value of an opt_text, or '' when unset -- the same fallback discipline as opt_or.
  pure function opt_text_or(x) result(v)
    type(opt_text), intent(in) :: x
    character(len=:), allocatable :: v
    logical :: found
    call opt_get(x, v, found)
    if (.not. found) v = ''
  end function opt_text_or

  ! The value of an opt_logical, or .false. when unset. Same fallback discipline as
  ! opt_or, and same caveat: verify_problem_inputs is what stops an unset one reaching
  ! here, because .false. is a legitimate answer this cannot distinguish from silence.
  pure logical function opt_logical_or(x) result(v)
    type(opt_logical), intent(in) :: x
    logical :: found
    call opt_get(x, v, found)
    if (.not. found) v = .false.
  end function opt_logical_or

  pure real(real64) function opt_or_real(x) result(v)
    type(opt_real), intent(in) :: x
    logical :: found
    call opt_get(x, v, found)
    if (.not. found) v = 0.0_real64
  end function opt_or_real

  pure function itoa(v) result(s)
    integer, intent(in) :: v
    character(len=:), allocatable :: s
    character(len=24) :: buf
    write (buf, '(i0)') v
    s = trim(buf)
  end function itoa

end module yl_runtime_commit
