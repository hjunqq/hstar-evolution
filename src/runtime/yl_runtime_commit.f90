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
!   all -- reports INV-COMMIT-TOTAL and touches no global -- when it finds ANY of the six
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
                        lmdofn, lcdofn, nodfn, iffix, fixed,                                    &
                        result_zero, tofor, stfor, toforl, toform, delitfi, deltafi,            &
                        line_load_block, line_temp_block, lineload, linet,                      &
                        npoin, nelem, ngroup, ndimn, mdofn, cdofn, ntotv, iblks, lblks,         &
                        element_lib, group_of_elements, group_of_dvide_ipoin,                   &
                        interpolation_group, unode_elements
  use prescribed, only: prescrib, ndofix, freedom_prescribe
  use applied_load, only: tcurves, ntcurve, time_curve
  use meshfine, only: ice0

  use yl_problem_optional, only: opt_int, opt_real, opt_get
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
  integer, parameter, public :: COMMIT_LEN_NOTE = 32

  !> Produced by build_runtime and published from the runtime by this module.
  integer(int32), parameter, public :: COMMIT_FROM_RUNTIME = 1_int32
  !> Taken from the finished ProblemState. Unused until M4-01 step 3.
  integer(int32), parameter, public :: COMMIT_FROM_PROBLEM = 2_int32
  !> Computed here from a ProblemState collection's cardinality. Unused until step 5.
  integer(int32), parameter, public :: COMMIT_DERIVED = 3_int32
  !> Carried from the deck by deck_residue_t, with the adapter's rejection rule recorded
  !> in `note` as an independent cross-check. Unused until step 5.
  integer(int32), parameter, public :: COMMIT_FROM_DECK = 4_int32
  !> The dump synthesises the value and reads no global; nothing to do here.
  integer(int32), parameter, public :: COMMIT_SYNTHETIC = 5_int32
  !> NO SOURCE. The row reaches the globals carrying whatever staging left there, and no
  !> comparison may treat it as evidence. Every occurrence is a debt, and the M4-01 exit
  !> condition is that this state does not appear in the table at all.
  integer(int32), parameter, public :: COMMIT_NOT_MIGRATED = 6_int32

  type, public :: commit_provenance_t
    character(len=COMMIT_LEN_MAP_ID) :: map_id = ''
    integer(int32) :: state = COMMIT_NOT_MIGRATED
    character(len=COMMIT_LEN_NOTE) :: note = ''
  end type commit_provenance_t

  ! 162 entries, in state-field-map.toml order. Today: 42 FROM_RUNTIME (the 32 emitted
  ! RuntimeState rows plus the 10 whose value is an extent or a reconstruction of one),
  ! 2 SYNTHETIC, 118 NOT_MIGRATED. The 118 are the fold's remaining work and the count is
  ! the honest headline of M4-01's progress -- it is meant to fall to zero.
  type(commit_provenance_t), parameter :: COMMIT_PROVENANCE(*) = [                              &
    commit_provenance_t('case.name', COMMIT_NOT_MIGRATED, ''),                                                                  &
    commit_provenance_t('control.run.restart', COMMIT_NOT_MIGRATED, ''),                                                        &
    commit_provenance_t('control.run.relis', COMMIT_NOT_MIGRATED, ''),                                                          &
    commit_provenance_t('control.run.adina', COMMIT_NOT_MIGRATED, ''),                                                          &
    commit_provenance_t('derived.counts.runblks', COMMIT_NOT_MIGRATED, ''),                                                     &
    commit_provenance_t('derived.counts.npoin', COMMIT_FROM_RUNTIME, 'extent npoin'),                                           &
    commit_provenance_t('derived.counts.npoinb', COMMIT_NOT_MIGRATED, ''),                                                      &
    commit_provenance_t('derived.counts.nelem', COMMIT_FROM_RUNTIME, 'extent nelem'),                                           &
    commit_provenance_t('mesh.dimension', COMMIT_FROM_RUNTIME, 'extent ndimn'),                                                 &
    commit_provenance_t('derived.counts.nmats', COMMIT_NOT_MIGRATED, ''),                                                       &
    commit_provenance_t('derived.counts.ngroup', COMMIT_FROM_RUNTIME, 'extent ngroup'),                                         &
    commit_provenance_t('steps0.output.format', COMMIT_NOT_MIGRATED, ''),                                                       &
    commit_provenance_t('mesh.nodes.id', COMMIT_SYNTHETIC, 'dump emits 1..npoin'),                                              &
    commit_provenance_t('mesh.nodes.xyz', COMMIT_NOT_MIGRATED, ''),                                                             &
    commit_provenance_t('mesh.elements.id', COMMIT_SYNTHETIC, 'dump emits 1..nelem'),                                           &
    commit_provenance_t('mesh.elements.nodes', COMMIT_NOT_MIGRATED, ''),                                                        &
    commit_provenance_t('mesh.elements.kind', COMMIT_NOT_MIGRATED, ''),                                                         &
    commit_provenance_t('mesh.elements.group', COMMIT_NOT_MIGRATED, ''),                                                        &
    commit_provenance_t('mesh.elements.material', COMMIT_NOT_MIGRATED, ''),                                                     &
    commit_provenance_t('mesh.sets.elset', COMMIT_NOT_MIGRATED, ''),                                                            &
    commit_provenance_t('mesh.sets.nset', COMMIT_NOT_MIGRATED, ''),                                                             &
    commit_provenance_t('materials.id', COMMIT_NOT_MIGRATED, ''),                                                               &
    commit_provenance_t('materials.kind', COMMIT_NOT_MIGRATED, ''),                                                             &
    commit_provenance_t('materials.name', COMMIT_NOT_MIGRATED, ''),                                                             &
    commit_provenance_t('derived.counts.nphase', COMMIT_NOT_MIGRATED, ''),                                                      &
    commit_provenance_t('materials.phase', COMMIT_NOT_MIGRATED, ''),                                                            &
    commit_provenance_t('materials.model', COMMIT_NOT_MIGRATED, ''),                                                            &
    commit_provenance_t('materials.density', COMMIT_NOT_MIGRATED, ''),                                                          &
    commit_provenance_t('materials.ratio', COMMIT_NOT_MIGRATED, ''),                                                            &
    commit_provenance_t('sections.thickness', COMMIT_NOT_MIGRATED, ''),                                                         &
    commit_provenance_t('materials.E', COMMIT_NOT_MIGRATED, ''),                                                                &
    commit_provenance_t('materials.nu', COMMIT_NOT_MIGRATED, ''),                                                               &
    commit_provenance_t('materials.thermal_expansion', COMMIT_NOT_MIGRATED, ''),                                                &
    commit_provenance_t('materials.icreep', COMMIT_NOT_MIGRATED, ''),                                                           &
    commit_provenance_t('materials.kind_wt', COMMIT_NOT_MIGRATED, ''),                                                          &
    commit_provenance_t('materials.jliqu', COMMIT_NOT_MIGRATED, ''),                                                            &
    commit_provenance_t('sections.element', COMMIT_NOT_MIGRATED, ''),                                                           &
    commit_provenance_t('sections.name', COMMIT_NOT_MIGRATED, ''),                                                              &
    commit_provenance_t('sections.element_kind', COMMIT_NOT_MIGRATED, ''),                                                      &
    commit_provenance_t('sections.class', COMMIT_NOT_MIGRATED, ''),                                                             &
    commit_provenance_t('derived.counts.nrfields', COMMIT_NOT_MIGRATED, ''),                                                    &
    commit_provenance_t('sections.fields', COMMIT_NOT_MIGRATED, ''),                                                            &
    commit_provenance_t('sections.special', COMMIT_NOT_MIGRATED, ''),                                                           &
    commit_provenance_t('sections.formulation', COMMIT_NOT_MIGRATED, ''),                                                       &
    commit_provenance_t('sections.elset_size', COMMIT_NOT_MIGRATED, ''),                                                        &
    commit_provenance_t('sections.material_header', COMMIT_NOT_MIGRATED, ''),                                                   &
    commit_provenance_t('sections.material', COMMIT_NOT_MIGRATED, ''),                                                          &
    commit_provenance_t('sections.type_nalgo', COMMIT_NOT_MIGRATED, ''),                                                        &
    commit_provenance_t('sections.type_stiff', COMMIT_NOT_MIGRATED, ''),                                                        &
    commit_provenance_t('sections.type_ecoint', COMMIT_NOT_MIGRATED, ''),                                                       &
    commit_provenance_t('sections.ilayer', COMMIT_NOT_MIGRATED, ''),                                                            &
    commit_provenance_t('sections.elcod_local', COMMIT_NOT_MIGRATED, ''),                                                       &
    commit_provenance_t('sections.uplift_ic', COMMIT_NOT_MIGRATED, ''),                                                         &
    commit_provenance_t('sections.liquj', COMMIT_NOT_MIGRATED, ''),                                                             &
    commit_provenance_t('sections.dof_count', COMMIT_NOT_MIGRATED, ''),                                                         &
    commit_provenance_t('sections.dof_list', COMMIT_NOT_MIGRATED, ''),                                                          &
    commit_provenance_t('derived.counts.nstre', COMMIT_NOT_MIGRATED, ''),                                                       &
    commit_provenance_t('derived.counts.ntcurve', COMMIT_FROM_RUNTIME, 'extent ntcurve'),                                       &
    commit_provenance_t('amplitudes.points.count', COMMIT_NOT_MIGRATED, ''),                                                    &
    commit_provenance_t('amplitudes.type', COMMIT_NOT_MIGRATED, ''),                                                            &
    commit_provenance_t('amplitudes.points.time', COMMIT_NOT_MIGRATED, ''),                                                     &
    commit_provenance_t('amplitudes.points.value', COMMIT_NOT_MIGRATED, ''),                                                    &
    commit_provenance_t('runtime.amplitudes.dfact', COMMIT_FROM_RUNTIME, ''),                                                   &
    commit_provenance_t('steps0.procedure', COMMIT_NOT_MIGRATED, ''),                                                           &
    commit_provenance_t('solver.linear', COMMIT_NOT_MIGRATED, ''),                                                              &
    commit_provenance_t('steps0.load_mode', COMMIT_NOT_MIGRATED, ''),                                                           &
    commit_provenance_t('steps0.controls.nonlinear_type', COMMIT_NOT_MIGRATED, ''),                                             &
    commit_provenance_t('control.glb.nlayer', COMMIT_NOT_MIGRATED, ''),                                                         &
    commit_provenance_t('control.glb.block_stab', COMMIT_NOT_MIGRATED, ''),                                                     &
    commit_provenance_t('control.glb.nbackf', COMMIT_NOT_MIGRATED, ''),                                                         &
    commit_provenance_t('control.glb.ebody', COMMIT_NOT_MIGRATED, ''),                                                          &
    commit_provenance_t('control.glb.ninit', COMMIT_NOT_MIGRATED, ''),                                                          &
    commit_provenance_t('control.glb.uinitial', COMMIT_NOT_MIGRATED, ''),                                                       &
    commit_provenance_t('control.glb.state_change', COMMIT_NOT_MIGRATED, ''),                                                   &
    commit_provenance_t('control.glb.bparameter', COMMIT_NOT_MIGRATED, ''),                                                     &
    commit_provenance_t('control.glb.stab_matde', COMMIT_NOT_MIGRATED, ''),                                                     &
    commit_provenance_t('derived.counts.nblks', COMMIT_NOT_MIGRATED, ''),                                                       &
    commit_provenance_t('control.glb.nlinks', COMMIT_NOT_MIGRATED, ''),                                                         &
    commit_provenance_t('solver.symmetric', COMMIT_NOT_MIGRATED, ''),                                                           &
    commit_provenance_t('interactions.absorbing.type', COMMIT_NOT_MIGRATED, ''),                                                &
    commit_provenance_t('derived.counts.nsmat', COMMIT_NOT_MIGRATED, ''),                                                       &
    commit_provenance_t('steps0.load.gravity.enabled', COMMIT_NOT_MIGRATED, ''),                                                &
    commit_provenance_t('derived.counts.mdofn', COMMIT_FROM_RUNTIME, 'extent mdofn'),                                           &
    commit_provenance_t('derived.dof.active_flags', COMMIT_FROM_RUNTIME, 'reconstructed from lmdofn'),                          &
    commit_provenance_t('runtime.dof.lmdofn', COMMIT_FROM_RUNTIME, ''),                                                         &
    commit_provenance_t('derived.dof.cdofn', COMMIT_FROM_RUNTIME, 'extent cdofn'),                                              &
    commit_provenance_t('derived.dof.lcdofn', COMMIT_FROM_RUNTIME, 'lcdofn(1:cdofn)'),                                          &
    commit_provenance_t('runtime.increment.iblks_at_model', COMMIT_FROM_RUNTIME, ''),                                           &
    commit_provenance_t('runtime.increment.lblks_at_model', COMMIT_FROM_RUNTIME, ''),                                           &
    commit_provenance_t('steps0.activation.active', COMMIT_NOT_MIGRATED, ''),                                                   &
    commit_provenance_t('steps0.activation.material', COMMIT_NOT_MIGRATED, ''),                                                 &
    commit_provenance_t('runtime.activation.appear', COMMIT_FROM_RUNTIME, ''),                                                  &
    commit_provenance_t('steps0.output.stress_averaging', COMMIT_NOT_MIGRATED, ''),                                             &
    commit_provenance_t('steps0.output.field.gid_u', COMMIT_NOT_MIGRATED, ''),                                                  &
    commit_provenance_t('steps0.output.field.gid_s', COMMIT_NOT_MIGRATED, ''),                                                  &
    commit_provenance_t('steps0.output.field.gid_ms', COMMIT_NOT_MIGRATED, ''),                                                 &
    commit_provenance_t('steps0.output.field.gid_f', COMMIT_NOT_MIGRATED, ''),                                                  &
    commit_provenance_t('steps0.output.field.gid_rot', COMMIT_NOT_MIGRATED, ''),                                                &
    commit_provenance_t('steps0.output.field.gid_v', COMMIT_NOT_MIGRATED, ''),                                                  &
    commit_provenance_t('steps0.output.field.gid_a', COMMIT_NOT_MIGRATED, ''),                                                  &
    commit_provenance_t('steps0.output.field.gid_T', COMMIT_NOT_MIGRATED, ''),                                                  &
    commit_provenance_t('steps0.output.field.gid_P', COMMIT_NOT_MIGRATED, ''),                                                  &
    commit_provenance_t('steps0.output.field.gid_Pv', COMMIT_NOT_MIGRATED, ''),                                                 &
    commit_provenance_t('steps0.output.field.gid_ep', COMMIT_NOT_MIGRATED, ''),                                                 &
    commit_provenance_t('steps0.output.field.gid_Y', COMMIT_NOT_MIGRATED, ''),                                                  &
    commit_provenance_t('steps0.output.field.gid_FC', COMMIT_NOT_MIGRATED, ''),                                                 &
    commit_provenance_t('steps0.output.field.gid_Ns', COMMIT_NOT_MIGRATED, ''),                                                 &
    commit_provenance_t('steps0.output.field.gid_Ss', COMMIT_NOT_MIGRATED, ''),                                                 &
    commit_provenance_t('steps0.output.field.gid_Mxy', COMMIT_NOT_MIGRATED, ''),                                                &
    commit_provenance_t('steps0.output.field.gid_bem', COMMIT_NOT_MIGRATED, ''),                                                &
    commit_provenance_t('steps0.output.field.gid_wh', COMMIT_NOT_MIGRATED, ''),                                                 &
    commit_provenance_t('steps0.output.field.gid_wv', COMMIT_NOT_MIGRATED, ''),                                                 &
    commit_provenance_t('steps0.output.field.gid_bcs', COMMIT_NOT_MIGRATED, ''),                                                &
    commit_provenance_t('derived.counts.nfixsets', COMMIT_NOT_MIGRATED, ''),                                                    &
    commit_provenance_t('derived.counts.ndofix', COMMIT_FROM_RUNTIME, 'extent ndofix'),                                         &
    commit_provenance_t('steps0.boundary.set', COMMIT_NOT_MIGRATED, ''),                                                        &
    commit_provenance_t('steps0.boundary.dof', COMMIT_NOT_MIGRATED, ''),                                                        &
    commit_provenance_t('steps0.boundary.amplitude', COMMIT_NOT_MIGRATED, ''),                                                  &
    commit_provenance_t('steps0.boundary.nodes', COMMIT_NOT_MIGRATED, ''),                                                      &
    commit_provenance_t('steps0.boundary.value', COMMIT_NOT_MIGRATED, ''),                                                      &
    commit_provenance_t('steps0.boundary.record_reaction', COMMIT_NOT_MIGRATED, ''),                                            &
    commit_provenance_t('runtime.boundary.ldofix', COMMIT_FROM_RUNTIME, ''),                                                    &
    commit_provenance_t('runtime.boundary.lnefix', COMMIT_FROM_RUNTIME, ''),                                                    &
    commit_provenance_t('runtime.boundary.leldofix', COMMIT_FROM_RUNTIME, ''),                                                  &
    commit_provenance_t('runtime.boundary.levdofix', COMMIT_FROM_RUNTIME, ''),                                                  &
    commit_provenance_t('runtime.boundary.lefdofix', COMMIT_FROM_RUNTIME, ''),                                                  &
    commit_provenance_t('runtime.dof.iffix', COMMIT_FROM_RUNTIME, ''),                                                          &
    commit_provenance_t('runtime.dof.fixed', COMMIT_FROM_RUNTIME, ''),                                                          &
    commit_provenance_t('control.glb.ntrans', COMMIT_NOT_MIGRATED, ''),                                                         &
    commit_provenance_t('steps0.load.gravity.magnitude', COMMIT_NOT_MIGRATED, ''),                                              &
    commit_provenance_t('steps0.load.gravity.direction', COMMIT_NOT_MIGRATED, ''),                                              &
    commit_provenance_t('steps0.load.gravity.amplitude', COMMIT_NOT_MIGRATED, ''),                                              &
    commit_provenance_t('derived.counts.nplgroup', COMMIT_NOT_MIGRATED, ''),                                                    &
    commit_provenance_t('derived.counts.nedge', COMMIT_NOT_MIGRATED, ''),                                                       &
    commit_provenance_t('derived.counts.edge_load_group', COMMIT_NOT_MIGRATED, ''),                                             &
    commit_provenance_t('derived.counts.delgroup', COMMIT_NOT_MIGRATED, ''),                                                    &
    commit_provenance_t('derived.counts.nbeamload', COMMIT_NOT_MIGRATED, ''),                                                   &
    commit_provenance_t('derived.counts.nplateload', COMMIT_NOT_MIGRATED, ''),                                                  &
    commit_provenance_t('derived.counts.ntemp_surface', COMMIT_NOT_MIGRATED, ''),                                               &
    commit_provenance_t('derived.counts.ntedge', COMMIT_NOT_MIGRATED, ''),                                                      &
    commit_provenance_t('derived.counts.ntelgroup', COMMIT_NOT_MIGRATED, ''),                                                   &
    commit_provenance_t('derived.counts.npipe', COMMIT_NOT_MIGRATED, ''),                                                       &
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
  !>   runtime  the built runtime. intent(in): committing does not consume it, and the
  !>            same runtime may be committed again -- see the T02 properties.
  !>   errors   findings are APPENDED. A finding here is always PE_INTERNAL: by the time
  !>            a runtime exists its deck has been validated, so anything wrong at this
  !>            point is a broken pipeline and not a bad model.
  !>
  !> On success every registered global carries this runtime. On failure not one global
  !> was touched.
  subroutine commit_legacy_globals(runtime, errors)
    type(runtime_state_t), intent(in) :: runtime
    type(problem_errors_t), intent(inout) :: errors

    ! staging: scalars
    integer(ink) :: s_npoin, s_nelem, s_ngroup, s_ndimn, s_mdofn, s_cdofn, s_ntotv
    integer(ink) :: s_ndofix, s_ntcurve, s_iblks, s_lblks, s_lineload, s_linet
    integer :: nevab, ngaus, ngaus_mass, nnode
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

    integer :: i, ie, ig, n
    logical :: ok

    ! ---------------------------------------------------------------- verify
    call verify_registered(runtime, errors, ok)
    if (.not. ok) return

    ! W4 guard (see the OWNERSHIP header): if any record-array global this module writes
    ! is already allocated while `commit_owned` is false, the storage was not put there by
    ! a previous commit_legacy_globals -- it can only be a legacy reader's own allocation.
    ! Staging and then `move_alloc`-ing over it would deallocate that array without
    ! freeing the pointer targets inside it, i.e. leak it silently. Refuse instead of
    ! leaking: this module will not run in a process whose legacy globals were populated
    ! by something else.
    if (.not. commit_owned) then
      ! ALL SIX record-array globals this module move_allocs, not five: `trans` is
      ! `interpolation_group`, which carries `listf` and `rintf` pointers
      ! (Global.f90:210-214) and is moved at the same unconditional move_alloc as the
      ! rest. Omitting it left the exact leak this guard exists to prevent reachable
      ! through one of the six doors -- found in M3-03 Round-2 review. If a seventh
      ! record array is ever committed, it belongs in this list on the same commit that
      ! adds its move_alloc.
      if (allocated(element) .or. allocated(group) .or. allocated(listp_group) .or.            &
          allocated(prescrib) .or. allocated(tcurves) .or. allocated(trans)) then
        call fail(errors, 'one of element, group, listp_group, prescrib, tcurves or trans '//  &
                  'is already allocated but commit_owned is false -- committing would '//      &
                  'silently leak a foreign allocation via move_alloc; refusing to run in a '// &
                  'process whose legacy globals were populated by something other than '//     &
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
    s_delitfi = STAGE_POISON_R;  s_deltafi = STAGE_POISON_R

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
      ! RESERVED, as above: allocated to their final length and not written, so they carry
      ! the sentinel out (rule 2 of the STAGE_POISON note).
      allocate (s_element(ie)%field(1)%tload(nevab))
      allocate (s_element(ie)%field(1)%eload(nevab))
      allocate (s_element(ie)%field(1)%rload(nevab))
      s_element(ie)%field(1)%tload = STAGE_POISON_R
      s_element(ie)%field(1)%eload = STAGE_POISON_R
      s_element(ie)%field(1)%rload = STAGE_POISON_R

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
    allocate (s_prescrib(s_ndofix))
    do i = 1, int(s_ndofix)
      call null_prescrib(s_prescrib(i))
      call poison_prescrib(s_prescrib(i))
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

    ! Amplitude records. Only the current factor is a model_ready row; the curve itself
    ! is authored data and belongs to the ProblemState half.
    allocate (s_tcurves(s_ntcurve))
    do i = 1, int(s_ntcurve)
      call null_tcurve(s_tcurves(i))
      s_tcurves(i)%dfact = STAGE_POISON_R
      s_tcurves(i)%dfact = real(opt_or_real(runtime%amplitudes(i)%factor), irk)
    end do

    ! ----------------------------------------------------------------- write
    ! From here on nothing allocates, converts or can fail.
    call commit_release()

    npoin = s_npoin;  nelem = s_nelem;  ngroup = s_ngroup;  ndimn = s_ndimn
    mdofn = s_mdofn;  cdofn = s_cdofn;  ntotv = s_ntotv
    ndofix = s_ndofix; ntcurve = s_ntcurve
    iblks = s_iblks;  lblks = s_lblks
    lineload = s_lineload; linet = s_linet

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
            if (associated(element(i)%field(ig)%ldofs_f)) deallocate (element(i)%field(ig)%ldofs_f)
            if (associated(element(i)%field(ig)%elcod_f)) deallocate (element(i)%field(ig)%elcod_f)
            if (associated(element(i)%field(ig)%tload)) deallocate (element(i)%field(ig)%tload)
            if (associated(element(i)%field(ig)%eload)) deallocate (element(i)%field(ig)%eload)
            if (associated(element(i)%field(ig)%rload)) deallocate (element(i)%field(ig)%rload)
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
        if (associated(group(i)%unode)) then
          do ig = 1, size(group(i)%unode)
            if (associated(group(i)%unode(ig)%list)) deallocate (group(i)%unode(ig)%list)
          end do
          deallocate (group(i)%unode)
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

    if (allocated(tcurves)) deallocate (tcurves)
    if (allocated(trans)) deallocate (trans)

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
  subroutine verify_registered(runtime, errors, ok)
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
  subroutine poison_group(g)
    type(group_of_elements), intent(inout) :: g
    g%np_unode = STAGE_POISON_I
  end subroutine poison_group

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

  ! freedom_prescribe: 2 components, `ldofix` and `lnefix`, both assigned in the
  ! prescription-record loop. The rest of this type's scalars (itcurve, ifixvar, vdofix,
  ! nodfix, outfix, ifixset, ...) are the ProblemState half -- not assigned here yet.
  subroutine poison_prescrib(p)
    type(freedom_prescribe), intent(inout) :: p
    p%ldofix = STAGE_POISON_I
    p%lnefix = STAGE_POISON_I
  end subroutine poison_prescrib

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
